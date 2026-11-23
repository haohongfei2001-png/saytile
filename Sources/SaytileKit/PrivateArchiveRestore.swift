import CryptoKit
import Foundation
import Darwin

extension SaytileStore {
    func stageArchivePage(_ manifests: [PrivateArchive], cursor: String) throws {
        try db.transaction {
            for m in manifests {
                try m.validate()
                try db.execute("INSERT OR REPLACE INTO icloud_inbox VALUES(?,?)",[.text(m.id.uuidString),.text(String(decoding: try m.encoded(), as: UTF8.self))])
            }
            try setArchiveState("cursor",cursor)
        }
    }

    func nextArchiveRestore(after row: Int64) throws -> (Int64,PrivateArchive)? {
        // The temporary order uses the original timeline sequence across pages.
        // CloudKit may deliver records in any order. The cursor is just
        // for this pass; failed records remain queued across restarts.
        try nextArchiveItem("icloud_restore_order", after: row)
    }
    func prepareArchiveRestoreOrder() throws {
        try db.script("""
            DROP TABLE IF EXISTS temp.icloud_restore_order;
            CREATE TEMP TABLE icloud_restore_order AS SELECT manifest FROM icloud_inbox
            ORDER BY COALESCE(json_extract(manifest,'$.sequence'),json_extract(manifest,'$.started')),id;
            """)
    }
    private func nextArchiveItem(_ table: String, after row: Int64) throws -> (Int64,PrivateArchive)? {
        try db.rows("SELECT rowid AS pos,manifest FROM " + table + " WHERE rowid>? ORDER BY rowid LIMIT 1", [.int(row)]).first.map {
            guard let str = $0["manifest"], let pos = $0["pos"].flatMap(Int64.init) else { throw ArchiveIssue.invalid }
            return (pos,try JSONDecoder().decode(PrivateArchive.self, from: Data(str.utf8)))
        }
    }

    func archiveGeneration(_ id: UUID) throws -> Int64? {
        try db.rows("SELECT generation FROM icloud_outbox WHERE id=?", [.text(id.uuidString)]).first?["generation"].flatMap(Int64.init)
    }
    func applyArchiveText(_ remote: PrivateArchive, localImport: Bool = false) async throws {
        try remote.validate()
        let key = StoreDatabase.Value.text(remote.id.uuidString)
        // Check immutable recording identity and version conflicts before honoring
        // a remote erasure. Deleting audio is irreversible outside a SQLite rollback.
        let snapshotGeneration = try archiveGeneration(remote.id)
        let local = try await exportArchive(remote.id)
        // Explicitly importing an older archive is additive. Neither an old
        // deletion nor an old available copy overrides the selected base Mac.
        if localImport, let local, local.deleted || remote.deleted { return }
        var incoming = remote
        if localImport, local?.audioDeleted == false, incoming.audioDeleted {
            incoming.audioDeleted = false
        }
        let baseline = localImport ? nil : try archiveBaseline(remote.id)
        let merged = try local?.merged(with: incoming, baseline: baseline) ?? incoming
        guard try archiveGeneration(remote.id) == snapshotGeneration else { throw ArchiveIssue.stale }
        if let record = try recording(id: remote.id) {
            if merged.deleted { try deleteRecord(recordingID: remote.id) }
            else if merged.audioDeleted && ![AudioState.deleted,.deletePending].contains(record.audioState) {
                try deleteAudio(recordingID: remote.id)
            }
        }
        let generation = try archiveGeneration(remote.id)
        try db.transaction {
            guard try archiveGeneration(remote.id) == generation else { throw ArchiveIssue.stale }
            if local == nil {
                try db.execute("""
                    INSERT INTO recordings(id,created_at,sample_rate,is_recording,audio_state,recognition_state,deleted)
                    VALUES(?,?,?,0,?,'cancelled',?)
                    """,[key,.double(merged.started),.double(merged.sampleRate),.text(merged.audioDeleted ? "deleted" : "missing"),.int(merged.deleted ? 1 : 0)])
                try db.execute("INSERT INTO icloud_restored_recordings VALUES(?)", [key])
                // Keep the original group's civil time even if its anchor was erased or arrives later.
                let group = merged.group
                let groupKey = "\(group.start.bitPattern):\(group.offset):\(group.day)"
                let anchor: Int64
                if let known = try db.rows("SELECT position FROM icloud_groups WHERE key=?", [.text(groupKey)]).first?["position"].flatMap(Int64.init) {
                    anchor = known
                } else {
                    if group.start == merged.started, let own = try timelinePosition(of: merged.id) { anchor = own }
                    else {
                        try db.execute("INSERT INTO transcript_timeline(started,ended,day,utc_offset) VALUES(?,?,?,?)",
                            [.double(group.start),.double(group.start),.text(group.day),.int(Int64(group.offset))])
                        guard let pos = try db.rows("SELECT last_insert_rowid() AS n").first?["n"].flatMap(Int64.init) else { throw ArchiveIssue.invalid }
                        anchor = pos
                    }
                    try db.execute("INSERT INTO icloud_groups VALUES(?,?)",[.text(groupKey),.int(anchor)])
                }
                try db.execute("UPDATE transcript_timeline SET ended=?,day=?,utc_offset=?,group_start=? WHERE recording_id=?",
                    [merged.ended.map(StoreDatabase.Value.double) ?? .null,.text(merged.day),.int(Int64(merged.offset)),.int(anchor),key])
            }
            if let paragraph = merged.paragraph {
                try restoreParagraph(paragraph, for: merged.id)
            }
            let existingVersions = Set(local?.versions.map(\.id) ?? [])
            for v in merged.versions where !existingVersions.contains(v.id) {
                try db.execute("INSERT INTO revisions(id,recording_id,text,origin,created_at,attempt,base_revision) VALUES(?,?,?,?,?,?,?)",
                    [.text(v.id.uuidString),key,.text(v.text),.text(v.origin.rawValue),.double(v.created),
                     v.attempt.map { .text($0.uuidString) } ?? .null, v.base.map { .text($0.uuidString) } ?? .null])
                try db.execute("INSERT INTO icloud_imported_revisions VALUES(?)", [.text(v.id.uuidString)])
            }
            if local?.head != merged.head || local?.pinned != merged.pinned {
                try db.execute("UPDATE recordings SET preferred_revision=?,pinned=? WHERE id=?",
                    [merged.head.map { .text($0.uuidString) } ?? .null,.int(merged.pinned ? 1 : 0),key])
            }
            if local?.draft != merged.draft {
                if let d = merged.draft {
                    try db.execute("INSERT OR REPLACE INTO editing_drafts VALUES(?,?,?)", [key,.text(d.text),.double(d.created)])
                    try db.execute("INSERT OR REPLACE INTO archive_draft_bases VALUES(?,?)", [key,d.base.map { .text($0.uuidString) } ?? .null])
                } else { try db.execute("DELETE FROM editing_drafts WHERE recording_id=?", [key]) }
            }
            if merged.head != nil {
                try db.execute("UPDATE recordings SET recognition_state='completed' WHERE id=? AND is_recording=0 AND recognition_state='cancelled'",[key])
            }
            if localImport { return }
            let manifestText = String(decoding: try remote.encoded(), as: UTF8.self)
            try db.execute("INSERT OR REPLACE INTO icloud_baseline VALUES(?,?)",[key,.text(manifestText)])
            if merged.audioDeleted || remote.chunks.isEmpty || local?.chunks == remote.chunks {
                try db.execute("DELETE FROM icloud_assets WHERE id=?",[key])
            } else {
                try db.execute("INSERT OR REPLACE INTO icloud_assets VALUES(?,?)",[key,.text(manifestText)])
            }
            if merged == remote { try db.execute("DELETE FROM icloud_outbox WHERE id=?",[key]) }
            try db.execute("DELETE FROM icloud_inbox WHERE id=?",[key])
        }
    }

    /// Device-local timeline positions must not cross the wire. An anchor can
    /// arrive on a later page, or already be a tombstone on the source Mac.
    private func restoreParagraph(_ paragraph: PrivateArchive.Paragraph, for id: UUID) throws {
        guard let member = try timelinePosition(of: id) else { throw ArchiveIssue.invalid }
        let key = StoreDatabase.Value.text(paragraph.id.uuidString)
        let anchor: Int64
        if let mapped = try db.rows("SELECT position FROM icloud_paragraph_anchors WHERE id=?", [key]).first?["position"].flatMap(Int64.init) {
            anchor = mapped
        } else {
            if let existing = try timelinePosition(of: paragraph.id) {
                anchor = existing
            } else {
                try db.execute("""
                    INSERT INTO transcript_timeline(started,ended,day,utc_offset)
                    VALUES(?,?,?,?)
                    """, [.double(paragraph.start), .double(paragraph.start), .text(paragraph.day), .int(Int64(paragraph.offset))])
                guard let position = try db.rows("SELECT last_insert_rowid() AS position").first?["position"].flatMap(Int64.init) else { throw ArchiveIssue.invalid }
                anchor = position
                try db.execute("UPDATE transcript_timeline SET group_start=(SELECT group_start FROM transcript_timeline WHERE position=?) WHERE position=?", [.int(member), .int(anchor)])
                try db.execute("INSERT INTO timeline_paragraphs(position,paragraph_start) VALUES(?,?)", [.int(anchor), .int(anchor)])
            }
            try db.execute("INSERT INTO icloud_paragraph_anchors VALUES(?,?)", [key, .int(anchor)])
        }
        let original = try db.rows("SELECT started,day,utc_offset FROM transcript_timeline WHERE position=?", [.int(anchor)]).first
        guard original?["started"].flatMap(Double.init) == paragraph.start, original?["day"] == paragraph.day,
              original?["utc_offset"].flatMap(Int.init) == paragraph.offset else { throw ArchiveIssue.invalid }
        try db.execute("UPDATE timeline_paragraphs SET paragraph_start=? WHERE position=?", [.int(anchor), .int(member)])
        let state = try db.rows("""
            SELECT h.break_hidden,COALESCE(e.stamp,0) AS stamp FROM timeline_paragraphs h LEFT JOIN icloud_paragraph_edits e USING(position)
            WHERE h.position=?
            """, [.int(anchor)]).first
        guard let current = state?["stamp"].flatMap(Double.init) else { throw ArchiveIssue.invalid }
        // Older members cannot undo a more recent explicit join or split.
        if paragraph.edited > current || (paragraph.edited == current && paragraph.hidden) {
            try db.execute("UPDATE timeline_paragraphs SET break_hidden=? WHERE position=?", [.int(paragraph.hidden ? 1 : 0), .int(anchor)])
            try db.execute("INSERT OR REPLACE INTO icloud_paragraph_edits VALUES(?,?)", [.int(anchor), .double(paragraph.edited)])
        }
    }

    func nextArchiveAssets(after row: Int64) throws -> (Int64,PrivateArchive)? {
        try nextArchiveItem("icloud_assets", after: row)
    }
    func nextArchiveAssets(for id: UUID) throws -> PrivateArchive? {
        try db.rows("SELECT manifest FROM icloud_assets WHERE id=?",[.text(id.uuidString)]).first?["manifest"].map {
            try JSONDecoder().decode(PrivateArchive.self, from: Data($0.utf8))
        }
    }

    func archiveAssetURLs(_ m: PrivateArchive) throws -> [URL] {
        guard !m.chunks.isEmpty else { return [] }
        let chunks = try audioChunks(recordingID: m.id)
        try PrivateArchive.checked(chunks.map(\.id) == m.chunks.map(\.id))
        return try chunks.map { try audioURL(for: $0) }
    }

    /// CKAsset staging URLs are never saved to the database. Publish our own
    /// durable, verified WAV and only then make the group playable.
    func installArchiveAssets(_ m: PrivateArchive, files: [URL], localImport: Bool = false) async throws {
        try m.validate()
        try PrivateArchive.checked(files.count == m.chunks.count && !files.isEmpty)
        let key = StoreDatabase.Value.text(m.id.uuidString)
        if !localImport, try nextArchiveAssets(for: m.id) != m { throw ArchiveIssue.stale }
        guard let old = try recording(id: m.id), [.available,.missing].contains(old.audioState) else {
            if !localImport { try db.execute("DELETE FROM icloud_assets WHERE id=?",[key]) }
            return
        }
        let dir = audioDirectory.appendingPathComponent(m.id.uuidString, isDirectory: true)
        try StorePath.rejectSymbolicLink(dir)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let previous = try db.rows("SELECT id,path FROM chunks WHERE recording_id=?", [key])
        var restored: [(PrivateArchive.Chunk, String)] = []
        for (chunk, source) in zip(m.chunks,files) {
            try Task.checkCancellation()
            await Task.yield()
            guard let record = try recording(id: m.id), [.available,.missing].contains(record.audioState) else { throw ArchiveIssue.stale }
            let oldPath = previous.first { $0["id"] == chunk.id.uuidString }?["path"]
            let path = oldPath ?? "\(m.id.uuidString)/\(chunk.id.uuidString).wav"
            let pieces = path.split(separator: "/", omittingEmptySubsequences: false)
            try PrivateArchive.checked(pieces.count == 2 && pieces[0] == Substring(m.id.uuidString) &&
                pieces[1].hasSuffix(".wav") && UUID(uuidString: String(pieces[1].dropLast(4))) != nil)
            let target = dir.appendingPathComponent(String(pieces[1]))
            try StorePath.rejectSymbolicLink(target)
            // A checkpointed local original is never overwritten on hash mismatch.
            let exists = FileManager.default.fileExists(atPath: target.path)
            let bytes = try Data(contentsOf: exists ? target : source, options: [.mappedIfSafe])
            let digest = SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
            try PrivateArchive.checked(digest == chunk.sha256 && bytes.count == chunk.frames * 2 + 44 &&
                bytes.prefix(44) == PCMJournal.header(frames: chunk.frames))
            if !exists {
                // Stage with a non-WAV name so startup journal recovery cannot ingest a torn copy.
                let tmp = dir.appendingPathComponent(".restore-\(UUID().uuidString)")
                defer { try? FileManager.default.removeItem(at: tmp) }
                try bytes.write(to: tmp, options: [.withoutOverwriting])
                let handle = try FileHandle(forWritingTo: tmp)
                do { try handle.synchronize(); try handle.close() } catch { try? handle.close(); throw error }
                try FileManager.default.moveItem(at: tmp, to: target)
            }
            restored.append((chunk,path))
        }
        for location in [dir, audioDirectory] {
            let fd = Darwin.open(location.path,O_RDONLY | O_DIRECTORY | O_NOFOLLOW)
            guard fd >= 0 else { throw POSIXError(.EIO) }
            let synced = fsync(fd); Darwin.close(fd)
            guard synced == 0 else { throw POSIXError(.EIO) }
        }
        try db.transaction {
            guard try localImport || nextArchiveAssets(for: m.id) == m,
                  let record = try recording(id: m.id), [.available,.missing].contains(record.audioState) else { throw ArchiveIssue.stale }
            for (c,path) in restored {
                if let known = previous.first(where: { $0["id"] == c.id.uuidString }) {
                    try PrivateArchive.checked(known["path"] == path)
                } else {
                    try db.execute("INSERT INTO chunks(id,recording_id,path,frames,ordinal) VALUES(?,?,?,?,?)",
                        [.text(c.id.uuidString),key,.text(path),.int(c.frames),.int(Int64(c.ordinal))])
                }
            }
            try db.execute("UPDATE recordings SET audio_state='available',recognition_state=CASE WHEN preferred_revision IS NOT NULL THEN 'completed' ELSE 'cancelled' END WHERE id=?", [key])
            if !localImport { try db.execute("DELETE FROM icloud_assets WHERE id=?",[key]) }
        }
    }
}
