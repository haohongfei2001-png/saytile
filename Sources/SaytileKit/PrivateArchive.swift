import CryptoKit
import Foundation

extension SaytileStore {
    func enablePrivateArchive(owner: String) throws {
        try db.transaction {
            try db.script("""
                CREATE TABLE IF NOT EXISTS icloud_state(key TEXT PRIMARY KEY,value TEXT NOT NULL);
                CREATE TABLE IF NOT EXISTS icloud_outbox(id TEXT PRIMARY KEY,generation INTEGER NOT NULL);
                CREATE TABLE IF NOT EXISTS icloud_baseline(id TEXT PRIMARY KEY,manifest TEXT NOT NULL);
                CREATE TABLE IF NOT EXISTS icloud_inbox(id TEXT PRIMARY KEY,manifest TEXT NOT NULL);
                CREATE TABLE IF NOT EXISTS icloud_assets(id TEXT PRIMARY KEY,manifest TEXT NOT NULL);
                CREATE TABLE IF NOT EXISTS icloud_groups(key TEXT PRIMARY KEY,position INTEGER NOT NULL);
                """)
            if let current = try archiveState("owner") {
                guard current == owner else { throw ArchiveIssue.accountChanged }
                return
            }
            try setArchiveState("owner", owner)
            try db.execute("INSERT INTO icloud_outbox SELECT id,1 FROM recordings")
            // No cloud calls or full scans from the capture/editor transaction.
            // Chunks and partials that change during speech are picked up by finishRecording.
            for (index, definition) in [
                ("recordings", "INSERT", "NEW.id"), ("recordings", "UPDATE OF preferred_revision,pinned,deleted,is_recording,audio_state", "NEW.id"),
                ("revisions", "INSERT", "NEW.recording_id"), ("chunks", "INSERT", "NEW.recording_id"),
                ("chunks", "UPDATE OF frames", "NEW.recording_id"), ("transcript_timeline", "UPDATE OF ended", "NEW.recording_id"),
                ("editing_drafts", "INSERT", "NEW.recording_id"), ("editing_drafts", "UPDATE", "NEW.recording_id"),
                ("editing_drafts", "DELETE", "OLD.recording_id")
            ].enumerated() {
                let (source, operation, key) = definition
                let whenClause = source == "recordings" ? " WHEN NEW.is_recording=0" : " WHEN EXISTS(SELECT 1 FROM recordings WHERE id=\(key) AND is_recording=0)"
                try db.script("""
                    CREATE TRIGGER icloud_dirty_\(index) AFTER \(operation) ON \(source)\(whenClause) BEGIN
                        INSERT INTO icloud_outbox VALUES(\(key),1)
                        ON CONFLICT(id) DO UPDATE SET generation=generation+1;
                    END;
                    """)
            }
        }
    }
    func archiveState(_ key: String) throws -> String? {
        try db.rows("SELECT value FROM icloud_state WHERE key=?", [.text(key)]).first?["value"]
    }
    func setArchiveState(_ key: String, _ value: String) throws {
        try db.execute("INSERT OR REPLACE INTO icloud_state VALUES(?,?)",[.text(key),.text(value)])
    }
    func archivePending(after lastID: String = "") throws -> [(UUID, Int64)] {
        try db.rows("SELECT q.id,q.generation FROM icloud_outbox q JOIN recordings r ON r.id=q.id WHERE r.is_recording=0 AND q.id>? ORDER BY q.id LIMIT 32", [.text(lastID)]).map {
            guard let id = $0["id"].flatMap(UUID.init(uuidString:)), let generation = $0["generation"].flatMap(Int64.init) else { throw ArchiveIssue.invalid }
            return (id, generation)
        }
    }
    func archiveBaseline(_ id: UUID) throws -> PrivateArchive? {
        try db.rows("SELECT manifest FROM icloud_baseline WHERE id=?", [.text(id.uuidString)]).first?["manifest"].map {
            try JSONDecoder().decode(PrivateArchive.self, from: Data($0.utf8))
        }
    }
    func acknowledgeArchive(_ manifest: PrivateArchive, generation: Int64?) throws {
        try db.transaction {
            try db.execute("INSERT OR REPLACE INTO icloud_baseline VALUES(?,?)",
                [.text(manifest.id.uuidString), .text(String(decoding: try manifest.encoded(), as: UTF8.self))])
            if let generation {
                try db.execute("DELETE FROM icloud_outbox WHERE id=? AND generation=?", [.text(manifest.id.uuidString),.int(generation)])
            }
        }
    }
    func exportArchive(_ id: UUID) async throws -> PrivateArchive? {
        let key: [StoreDatabase.Value] = [.text(id.uuidString)]
        let generation = try archiveGeneration(id)
        guard let r = try db.rows("""
            SELECT r.*,t.position,t.started,t.ended,t.day,t.utc_offset,g.started AS gs,g.day AS gd,g.utc_offset AS go
            FROM recordings r JOIN transcript_timeline t ON t.recording_id=r.id JOIN transcript_timeline g ON g.position=t.group_start WHERE r.id=?
            """,key).first else { return nil }
        guard r["is_recording"] == "0" else { throw StoreError.recordingActive }
        guard let start = r["started"].flatMap(Double.init), let rate = r["sample_rate"].flatMap(Double.init),
              let gstart = r["gs"].flatMap(Double.init), let day = r["day"], let gday = r["gd"],
              let off = r["utc_offset"].flatMap(Int.init), let goff = r["go"].flatMap(Int.init) else { throw ArchiveIssue.invalid }
        let deleted = r["deleted"] == "1"
        let audioDeleted = deleted || r["audio_state"] == "deleted" || r["audio_state"] == "deletePending"
        let versions = try db.rows("SELECT * FROM revisions WHERE recording_id=? ORDER BY created_at,id", key).map { row -> PrivateArchive.Version in
            guard let id = row["id"].flatMap(UUID.init(uuidString:)), let text = row["text"], let origin = row["origin"].flatMap(RevisionOrigin.init(rawValue:)),
                  let created = row["created_at"].flatMap(Double.init) else { throw ArchiveIssue.invalid }
            return .init(id: id,text: text,origin: origin,created: created,attempt: row["attempt"].flatMap(UUID.init(uuidString:)),base: row["base_revision"].flatMap(UUID.init(uuidString:)))
        }
        var chunks: [PrivateArchive.Chunk] = []
        if !audioDeleted && r["audio_state"] == "available" {
            for c in try audioChunks(recordingID: id) {
                try Task.checkCancellation()
                let bytes = try Data(contentsOf: audioURL(for: c), options: [.mappedIfSafe])
                try PrivateArchive.checked(c.frames >= 0 && c.frames <= (Int64(UInt32.max)-36)/2 &&
                    bytes.count == 44 + c.frames * 2 && bytes.prefix(44) == PCMJournal.header(frames: c.frames))
                chunks.append(.init(id: c.id,frames: c.frames,ordinal: c.ordinal,
                    sha256: SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()))
                // Long recordings rotate every 15 seconds. Let capture and editing
                // use the SQLite actor between bounded chunks.
                await Task.yield()
            }
        }
        guard try archiveGeneration(id) == generation else { throw ArchiveIssue.stale }
        let draft = try db.rows("""
            SELECT d.text,d.updated_at,b.revision_id FROM editing_drafts d LEFT JOIN archive_draft_bases b USING(recording_id)
            WHERE d.recording_id=?
            """, key).first.map { row -> PrivateArchive.Version in
            guard let text = row["text"], let stamp = row["updated_at"].flatMap(Double.init) else { throw ArchiveIssue.invalid }
            let base = row["revision_id"].flatMap(UUID.init(uuidString:))
            let signature = Data("\(id.uuidString)|\(stamp.bitPattern)|\(base?.uuidString ?? "")|".utf8) + Data(text.utf8)
            let digest = Array(SHA256.hash(data:signature).prefix(16))
            let uuid = digest.withUnsafeBytes { UUID(uuid: $0.loadUnaligned(as: uuid_t.self)) }
            return .init(id: uuid,text: text,origin: .userEdit,created: stamp,attempt: nil,base: base)
        }
        let prior = try archiveBaseline(id)
        let result = PrivateArchive(format: 1,id: id,started: start,ended: r["ended"].flatMap(Double.init),day: day,offset: off,
            group: .init(start: gstart,day: gday,offset: goff),sampleRate: rate,sequence: prior?.sequence ?? r["position"].flatMap(Int64.init),head: deleted ? nil : r["preferred_revision"].flatMap(UUID.init(uuidString:)),
            pinned: !deleted && r["pinned"] == "1",deleted: deleted,audioDeleted: audioDeleted,draft: deleted ? nil : draft,versions: deleted ? [] : versions,chunks: chunks)
        try result.validate()
        return result
    }
}
