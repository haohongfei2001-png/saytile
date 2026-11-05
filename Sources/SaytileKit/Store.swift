import Foundation
import Darwin

/// Native SQLite persistence. Audio files have one recording owner; text versions are immutable.
public actor SaytileStore {
    public nonisolated let directory: URL
    public nonisolated let audioDirectory: URL
    public nonisolated let recovery: StoreRecovery
    private let db: StoreDatabase
    private var leases: [UUID: UUID] = [:]
    private static let selection = "SELECT r.*,v.text FROM recordings r LEFT JOIN revisions v ON r.preferred_revision=v.id"

    public init(directory: URL) throws {
        self.directory = directory.standardizedFileURL
        self.audioDirectory = directory.appendingPathComponent("Audio",isDirectory:true).standardizedFileURL
        try FileManager.default.createDirectory(at: audioDirectory, withIntermediateDirectories:true)
        try FileManager.default.setAttributes([.posixPermissions:0o700],ofItemAtPath:directory.path)
        let database = try StoreDatabase(url:directory.appendingPathComponent("Saytile.sqlite"))
        db = database
        let version = try database.rows("PRAGMA user_version").first?["user_version"] ?? "0"
        guard version == "0" || version == "1" else { throw StoreError.database("资料库来自更新版本，请升级 Saytile。") }
        try database.script(Self.schema)
        func count(_ whereClause: String) throws -> Int { Int(try database.rows("SELECT COUNT(*) AS n FROM \(whereClause)").first?["n"] ?? "0") ?? 0 }
        recovery = try StoreRecovery(interruptedRecordings:count("recordings WHERE is_recording=1"),interruptedRecognitions:count("recordings WHERE recognition_state='running'"),unverifiedDispatches:count("dispatches WHERE state='dispatching'"))
        try database.transaction {
            try database.execute("UPDATE recordings SET is_recording=0,last_error='上次录音意外中断，已保存的原音可以恢复。' WHERE is_recording=1")
            try database.execute("UPDATE recordings SET recognition_state='queued',active_attempt=NULL WHERE recognition_state='running'")
            try database.execute("UPDATE bindings SET active=0")
            try database.execute("UPDATE dispatches SET state='unverified' WHERE state='dispatching'")
        }
        // Cleanup is resumed by recoverPendingDeletions, before importing any audio.
    }

    public func createRecording(id: UUID = UUID(), createdAt: Date = Date(), sampleRate: Double = 16000) throws -> Recording {
        guard sampleRate.isFinite && sampleRate > 0 else { throw StoreError.invalidFrames }
        try db.execute("INSERT INTO recordings(id,created_at,sample_rate) VALUES (?,?,?)",[.text(id.uuidString),.double(createdAt.timeIntervalSince1970),.double(sampleRate)])
        return try requireRecording(id)
    }
    public func recording(id: UUID) throws -> Recording? {
        try db.rows(Self.selection + " WHERE r.id=? AND r.deleted=0",[.text(id.uuidString)]).first.map(Self.decodeRecording)
    }
    public func listRecordings(query: String = "", limit: Int = 200, offset: Int = 0, filter: RecordingFilter = .all) throws -> [Recording] {
        let filterSQL: String
        switch filter { case .all: filterSQL = ""; case .pinned: filterSQL = " AND r.pinned=1"; case .needsRecovery: filterSQL = " AND r.recognition_state IN('queued','failed') AND r.audio_state='available'" }
        let escaped = query.replacingOccurrences(of:"\\",with:"\\\\").replacingOccurrences(of:"%",with:"\\%").replacingOccurrences(of:"_",with:"\\_")
        return try db.rows(Self.selection + " WHERE r.deleted=0" + filterSQL + " AND (?='' OR EXISTS (SELECT 1 FROM revisions s WHERE s.recording_id=r.id AND s.text LIKE ? ESCAPE '\\')) ORDER BY r.created_at DESC LIMIT ? OFFSET ?",[.text(query),.text("%" + escaped + "%"),.int(Int64(max(1,min(limit,1000)))),.int(Int64(max(0,offset)))]).map(Self.decodeRecording)
    }
    /// Capture/storage failure closes the source independently of ASR cancellation.
    /// Only published durable frames justify an available original-audio state.
    public func recordCaptureFailure(recordingID: UUID, message: String) throws {
        _ = try requireRecording(recordingID)
        try db.execute("UPDATE recordings SET is_recording=0,active_attempt=NULL,recognition_state='failed',last_error=?,audio_state=CASE WHEN audio_state='available' AND NOT EXISTS(SELECT 1 FROM chunks WHERE recording_id=recordings.id AND frames>0) THEN 'missing' ELSE audio_state END WHERE id=?",[.text(message),.text(recordingID.uuidString)])
    }
    public func finishRecording(id: UUID) throws {
        _ = try requireRecording(id)
        try db.execute("UPDATE recordings SET is_recording=0 WHERE id=?",[.text(id.uuidString)])
    }
    /// Call only after the file/header have been synchronized. Repeated checkpoints update this path.
    public func registerAudioChunk(recordingID: UUID, relativePath: String, frames: Int64) throws {
        let row = try requireRecording(recordingID)
        guard row.audioState == .available else { throw StoreError.audioUnavailable }
        guard frames >= 0 else { throw StoreError.invalidFrames }
        _ = try safeAudioURL(relativePath)
        guard relativePath.split(separator:"/").first == Substring(recordingID.uuidString) else { throw StoreError.invalidPath }
        try db.transaction {
            if let old = try db.rows("SELECT recording_id,frames FROM chunks WHERE path=?",[.text(relativePath)]).first {
                guard old["recording_id"] == recordingID.uuidString, frames >= Int64(old["frames"] ?? "0")! else { throw StoreError.invalidFrames }
                try db.execute("UPDATE chunks SET frames=? WHERE path=?",[.int(frames),.text(relativePath)])
            } else {
                try db.execute("INSERT INTO chunks(id,recording_id,path,frames,ordinal) SELECT ?,?,?,?,COALESCE(MAX(ordinal)+1,0) FROM chunks WHERE recording_id=?",[.text(UUID().uuidString),.text(recordingID.uuidString),.text(relativePath),.int(frames),.text(recordingID.uuidString)])
            }
        }
    }
    /// Startup-only reconciliation against the repaired physical file; never mutate an active capture.
    public func reconcileAudioChunk(recordingID: UUID, path: String, actualFrames: Int64) throws {
        let record = try requireRecording(recordingID)
        guard !record.isRecording else { throw StoreError.recordingActive }
        guard record.audioState == .available, actualFrames >= 0 else { throw StoreError.audioUnavailable }
        _ = try safeAudioURL(path)
        guard let previous = try db.rows("SELECT frames FROM chunks WHERE recording_id=? AND path=?",[.text(recordingID.uuidString),.text(path)]).first?["frames"],let oldFrames = Int64(previous) else { throw StoreError.invalidPath }
        try db.transaction {
            try db.execute("UPDATE chunks SET frames=? WHERE recording_id=? AND path=?",[.int(actualFrames),.text(recordingID.uuidString),.text(path)])
            if actualFrames < oldFrames {
                try db.execute("UPDATE recordings SET last_error='原音文件曾被截断，现已恢复可读取的部分。' WHERE id=?",[.text(recordingID.uuidString)])
            }
        }
    }
    public func markAudioMissing(recordingID: UUID, message: String) throws {
        let record = try requireRecording(recordingID)
        guard !record.isRecording else { throw StoreError.recordingActive }
        guard record.audioState == .available else { return }
        try db.execute("UPDATE recordings SET audio_state='missing',active_attempt=NULL,audio_epoch=audio_epoch+1,recognition_state='failed',last_error=? WHERE id=?",[.text(message),.text(recordingID.uuidString)])
    }
    public func audioChunks(recordingID: UUID) throws -> [AudioChunk] {
        let record = try requireRecording(recordingID)
        guard record.audioState == .available else { return [] }
        return try rawChunks(recordingID)
    }
    public func audioURL(for chunk: AudioChunk) throws -> URL {
        let record = try requireRecording(chunk.recordingID)
        guard record.audioState == .available else { throw StoreError.audioUnavailable }
        guard try rawChunks(chunk.recordingID).contains(where:{$0.id == chunk.id && $0.relativePath == chunk.relativePath}) else { throw StoreError.invalidPath }
        return try safeAudioURL(chunk.relativePath)
    }
    public func revisions(recordingID: UUID) throws -> [TranscriptRevision] {
        _ = try requireRecording(recordingID)
        return try db.rows("SELECT * FROM revisions WHERE recording_id=? ORDER BY created_at DESC,rowid DESC",[.text(recordingID.uuidString)]).map(Self.decodeRevision)
    }
    /// Freeze the exact text seen at a manual insertion click, without changing the selected draft.
    /// A volatile source may already have been pruned while the MainActor was scheduling this call.
    public func freezeRevision(recordingID: UUID, revisionID: UUID, text: String) throws -> TranscriptRevision {
        _ = try requireRecording(recordingID)
        return try db.transaction {
            let revision: TranscriptRevision
            if let row = try db.rows("SELECT * FROM revisions WHERE id=?",[.text(revisionID.uuidString)]).first {
                let existing = Self.decodeRevision(row)
                guard existing.recordingID == recordingID, existing.text == text else { throw StoreError.missingRevision }
                revision = existing
            } else {
                revision = TranscriptRevision(id:UUID(),recordingID:recordingID,text:text,origin:.partial,createdAt:Date())
                try insertRevision(revision,attempt:nil,base:nil)
            }
            try db.execute("INSERT OR IGNORE INTO frozen_revisions(revision_id) VALUES(?)",[.text(revision.id.uuidString)])
            return revision
        }
    }
    public func latestFinalRevision(recordingID: UUID) throws -> TranscriptRevision? {
        _ = try requireRecording(recordingID)
        return try db.rows("SELECT * FROM revisions WHERE recording_id=? AND origin='final' ORDER BY created_at DESC,rowid DESC LIMIT 1",[.text(recordingID.uuidString)]).first.map(Self.decodeRevision)
    }
    /// A durable editing draft is distinct from the selected transcript and its immutable history.
    public func loadDraft(recordingID: UUID) throws -> String? {
        try db.rows("SELECT d.text FROM editing_drafts d JOIN recordings r ON r.id=d.recording_id WHERE d.recording_id=? AND r.deleted=0",[.text(recordingID.uuidString)]).first?["text"]
    }
    public func saveDraft(recordingID: UUID, text: String) throws {
        _ = try requireRecording(recordingID)
        try db.execute("INSERT INTO editing_drafts(recording_id,text,updated_at) VALUES(?,?,?) ON CONFLICT(recording_id) DO UPDATE SET text=excluded.text,updated_at=excluded.updated_at",[.text(recordingID.uuidString),.text(text),.double(Date().timeIntervalSince1970)])
    }
    public func clearDraft(recordingID: UUID) throws {
        try db.execute("DELETE FROM editing_drafts WHERE recording_id=?",[.text(recordingID.uuidString)])
    }
    @discardableResult public func saveEdit(recordingID: UUID, text: String) throws -> TranscriptRevision {
        let record = try requireRecording(recordingID)
        let revision = TranscriptRevision(id:UUID(),recordingID:recordingID,text:text,origin:.userEdit,createdAt:Date())
        try db.transaction {
            try insertRevision(revision,attempt:nil,base:record.preferredRevisionID)
            try db.execute("UPDATE recordings SET preferred_revision=? WHERE id=?",[.text(revision.id.uuidString),.text(recordingID.uuidString)])
            try db.execute("DELETE FROM editing_drafts WHERE recording_id=?",[.text(recordingID.uuidString)])
        }
        return revision
    }
    public func selectRevision(recordingID: UUID, revisionID: UUID) throws {
        _ = try requireRecording(recordingID)
        guard try db.rows("SELECT id FROM revisions WHERE id=? AND recording_id=?",[.text(revisionID.uuidString),.text(recordingID.uuidString)]).first != nil else { throw StoreError.missingRevision }
        try db.execute("UPDATE recordings SET preferred_revision=? WHERE id=?",[.text(revisionID.uuidString),.text(recordingID.uuidString)])
    }
    public func setPinned(recordingID: UUID, pinned: Bool) throws {
        _ = try requireRecording(recordingID)
        try db.execute("UPDATE recordings SET pinned=? WHERE id=?",[.int(pinned ? 1:0),.text(recordingID.uuidString)])
    }
    public func beginRecognition(recordingID: UUID) throws -> RecognitionTicket {
        let record = try requireRecording(recordingID)
        guard record.audioState == .available else { throw StoreError.audioUnavailable }
        let epoch = Int64(try db.rows("SELECT audio_epoch FROM recordings WHERE id=?",[.text(recordingID.uuidString)])[0]["audio_epoch"]!)!
        let ticket = RecognitionTicket(id:UUID(),recordingID:recordingID,audioEpoch:epoch)
        try db.execute("UPDATE recordings SET active_attempt=?,recognition_state='running',last_error=NULL WHERE id=?",[.text(ticket.id.uuidString),.text(recordingID.uuidString)])
        return ticket
    }
    @discardableResult public func applyRecognition(ticket: RecognitionTicket, text: String, isFinal: Bool) throws -> Bool {
        try db.transaction {
            guard try validTicket(ticket) else { return false }
            let revision = TranscriptRevision(id:UUID(),recordingID:ticket.recordingID,text:text,origin:isFinal ? .final:.partial,createdAt:Date())
            try insertRevision(revision,attempt:ticket.id,base:nil)
            // An explicit user edit remains selected while later ASR results are preserved as other versions.
            try db.execute("UPDATE recordings SET preferred_revision=? WHERE id=? AND NOT EXISTS(SELECT 1 FROM revisions WHERE id=recordings.preferred_revision AND origin='userEdit')",[.text(revision.id.uuidString),.text(ticket.recordingID.uuidString)])
            // Only unreferenced volatile drafts can be replaced; finals and insertion snapshots remain immutable.
            try db.execute("DELETE FROM revisions WHERE recording_id=? AND origin='partial' AND attempt=? AND id<>? AND id NOT IN(SELECT revision_id FROM dispatches) AND id NOT IN(SELECT preferred_revision FROM recordings WHERE preferred_revision IS NOT NULL) AND id NOT IN(SELECT base_revision FROM revisions WHERE base_revision IS NOT NULL) AND id NOT IN(SELECT revision_id FROM frozen_revisions)",[.text(ticket.recordingID.uuidString),.text(ticket.id.uuidString),.text(revision.id.uuidString)])
            return true
        }
    }
    /// End only after the recognizer's final result stream has drained.
    public func finishRecognition(ticket: RecognitionTicket) throws {
        guard try validTicket(ticket) else { return }
        try db.execute("UPDATE recordings SET recognition_state='completed',active_attempt=NULL,last_error=NULL WHERE id=?",[.text(ticket.recordingID.uuidString)])
    }
    public func failRecognition(ticket: RecognitionTicket, message: String) throws {
        guard try validTicket(ticket) else { return }
        try db.execute("UPDATE recordings SET recognition_state='failed',active_attempt=NULL,last_error=? WHERE id=?",[.text(message),.text(ticket.recordingID.uuidString)])
    }
    public func queueRecognition(recordingID: UUID) throws {
        let record = try requireRecording(recordingID)
        guard record.audioState == .available else { throw StoreError.audioUnavailable }
        try db.execute("UPDATE recordings SET recognition_state='queued',active_attempt=NULL WHERE id=?",[.text(recordingID.uuidString)])
    }
    public func pendingRecordings(limit: Int = 100) throws -> [Recording] {
        try db.rows(Self.selection + " WHERE r.deleted=0 AND r.audio_state='available' AND r.is_recording=0 AND r.recognition_state IN('queued','failed') ORDER BY r.created_at LIMIT ?",[.int(Int64(max(1,min(1000,limit))))]).map(Self.decodeRecording)
    }

    /// Persisted finite retry scheduling prevents old failed records starving newer ones.
    /// Claims are taken transactionally, at most three automatically per recording.
    public func claimRecoveryRecording(now: Date = Date()) throws -> Recording? {
        try db.transaction {
            guard let row = try db.rows(Self.selection + " LEFT JOIN recovery_attempts a ON a.recording_id=r.id WHERE r.deleted=0 AND r.audio_state='available' AND r.is_recording=0 AND r.recognition_state IN('queued','failed') AND COALESCE(a.attempt_count,0)<3 AND COALESCE(a.retry_after,0)<=? ORDER BY COALESCE(a.attempt_count,0),r.created_at LIMIT 1",[.double(now.timeIntervalSince1970)]).first else { return nil }
            let record = Self.decodeRecording(row)
            let previous = Int(try db.rows("SELECT attempt_count FROM recovery_attempts WHERE recording_id=?",[.text(record.id.uuidString)]).first?["attempt_count"] ?? "0") ?? 0
            let delays: [Double] = [60,300,1800]
            try db.execute("INSERT INTO recovery_attempts(recording_id,attempt_count,retry_after) VALUES(?,?,?) ON CONFLICT(recording_id) DO UPDATE SET attempt_count=excluded.attempt_count,retry_after=excluded.retry_after",[.text(record.id.uuidString),.int(Int64(previous + 1)),.double(now.timeIntervalSince1970 + delays[min(previous,2)])])
            return record
        }
    }
    /// Yielding to live capture does not consume a failed recognition attempt.
    public func releaseRecoveryClaim(recordingID: UUID, now: Date = Date()) throws {
        try db.execute("UPDATE recovery_attempts SET attempt_count=MAX(0,attempt_count-1),retry_after=? WHERE recording_id=?",[.double(now.timeIntervalSince1970 + 30),.text(recordingID.uuidString)])
    }

    /// Leases are process-local; they expire on crash. New leases are refused once erasure is requested.
    public func acquireAudioLease(recordingID: UUID) throws -> UUID {
        guard try requireRecording(recordingID).audioState == .available else { throw StoreError.audioUnavailable }
        let lease = UUID(); leases[lease] = recordingID; return lease
    }
    public func releaseAudioLease(_ lease: UUID) throws {
        guard let recordingID = leases.removeValue(forKey:lease) else { return }
        try completeErasure(recordingID)
    }
    public func deleteAudio(recordingID: UUID) throws {
        let record = try requireRecording(recordingID)
        guard !record.isRecording else { throw StoreError.recordingActive }
        try beginErasure(recordingID,deleteRecord:false)
        try completeErasure(recordingID)
    }
    public func deleteRecord(recordingID: UUID) throws {
        let record = try requireRecording(recordingID)
        guard !record.isRecording else { throw StoreError.recordingActive }
        try beginErasure(recordingID,deleteRecord:true)
        try completeErasure(recordingID)
    }
    public func recoverPendingDeletions() throws {
        for row in try db.rows("SELECT recording_id,completed FROM erasures") {
            guard let id = UUID(uuidString:row["recording_id"]!) else { continue }
            let residual = try safeAudioURL(id.uuidString)
            if row["completed"] == "1", FileManager.default.fileExists(atPath:residual.path) {
                try db.execute("UPDATE erasures SET completed=0 WHERE recording_id=?",[.text(id.uuidString)])
                try db.execute("UPDATE recordings SET audio_state='deletePending' WHERE id=?",[.text(id.uuidString)])
            }
            try completeErasure(id)
        }
    }
    public func cleanupCandidates(olderThan: Date) throws -> [Recording] {
        try db.rows(Self.selection + " WHERE r.deleted=0 AND r.pinned=0 AND r.audio_state='available' AND r.recognition_state='completed' AND r.is_recording=0 AND r.created_at<? ORDER BY r.created_at",[.double(olderThan.timeIntervalSince1970)]).map(Self.decodeRecording).filter { !leases.values.contains($0.id) }
    }
    /// Revalidate the preview at execution time. Newly pinned, active, failed or leased audio stays protected.
    @discardableResult public func cleanupAudio(recordingIDs: [UUID], olderThan: Date) throws -> Int {
        let requested = Set(recordingIDs)
        let eligible = try cleanupCandidates(olderThan:olderThan).filter { requested.contains($0.id) }
        var count = 0
        for record in eligible {
            try beginErasure(record.id,deleteRecord:false)
            try completeErasure(record.id)
            count += 1
        }
        return count
    }
    public func storageSummary() throws -> StorageSummary {
        let keys: [URLResourceKey] = [.isRegularFileKey,.fileSizeKey,.isSymbolicLinkKey]
        var bytes: Int64 = 0
        if let enumerator = FileManager.default.enumerator(at:audioDirectory,includingPropertiesForKeys:keys) {
            for case let url as URL in enumerator {
                let value = try url.resourceValues(forKeys:Set(keys))
                if value.isRegularFile == true && value.isSymbolicLink != true { bytes += Int64(value.fileSize ?? 0) }
            }
        }
        let space = try FileManager.default.attributesOfFileSystem(forPath:directory.path)[.systemFreeSize] as? NSNumber
        func count(_ predicate: String) throws -> Int { Int(try db.rows("SELECT COUNT(*) AS n FROM recordings WHERE \(predicate)").first?["n"] ?? "0") ?? 0 }
        return try StorageSummary(audioBytes:bytes,recordingCount:count("deleted=0"),pendingRecognitionCount:count("deleted=0 AND recognition_state IN('queued','running','failed') AND audio_state='available'"),pendingDeletionCount:count("audio_state='deletePending'"),availableDiskBytes:space?.int64Value ?? 0)
    }

    private func requireRecording(_ id: UUID) throws -> Recording {
        guard let record = try recording(id:id) else { throw StoreError.missingRecording }; return record
    }
    private func validTicket(_ ticket: RecognitionTicket) throws -> Bool {
        try db.rows("SELECT id FROM recordings WHERE id=? AND deleted=0 AND audio_state='available' AND audio_epoch=? AND active_attempt=? AND recognition_state='running'",[.text(ticket.recordingID.uuidString),.int(ticket.audioEpoch),.text(ticket.id.uuidString)]).first != nil
    }
    private func insertRevision(_ revision: TranscriptRevision, attempt: UUID?, base: UUID?) throws {
        try db.execute("INSERT INTO revisions(id,recording_id,text,origin,created_at,attempt,base_revision) VALUES(?,?,?,?,?,?,?)",[.text(revision.id.uuidString),.text(revision.recordingID.uuidString),.text(revision.text),.text(revision.origin.rawValue),.double(revision.createdAt.timeIntervalSince1970),attempt.map{.text($0.uuidString)} ?? .null,base.map{.text($0.uuidString)} ?? .null])
    }
    private func rawChunks(_ id: UUID) throws -> [AudioChunk] {
        try db.rows("SELECT * FROM chunks WHERE recording_id=? ORDER BY ordinal",[.text(id.uuidString)]).map { AudioChunk(id:UUID(uuidString:$0["id"]!)!,recordingID:id,relativePath:$0["path"]!,frames:Int64($0["frames"]!)!,ordinal:Int($0["ordinal"]!)!) }
    }
    private func safeAudioURL(_ path: String) throws -> URL {
        guard !path.isEmpty, !path.hasPrefix("/"), !path.split(separator:"/",omittingEmptySubsequences:false).contains(where:{$0 == ".." || $0 == "." || $0.isEmpty}) else { throw StoreError.invalidPath }
        // resolvingSymlinksInPath alone does not reliably resolve an existing parent
        // symlink when its final file has not been created yet. Check every component.
        var componentURL = audioDirectory
        for component in path.split(separator:"/") {
            componentURL.appendPathComponent(String(component))
            var information = stat()
            let result = Darwin.lstat(componentURL.path,&information)
            if result == 0, information.st_mode & S_IFMT == S_IFLNK { throw StoreError.invalidPath }
            if result != 0, errno != ENOENT { throw StoreError.invalidPath }
        }
        let root = audioDirectory.resolvingSymlinksInPath().path + "/"
        let url = audioDirectory.appendingPathComponent(path).standardizedFileURL
        guard url.resolvingSymlinksInPath().path.hasPrefix(root) else { throw StoreError.invalidPath }
        return url
    }
    private func beginErasure(_ id: UUID, deleteRecord: Bool) throws {
        try db.transaction {
            try db.execute("INSERT OR IGNORE INTO erasures(recording_id,created_at,completed) VALUES(?,?,0)",[.text(id.uuidString),.double(Date().timeIntervalSince1970)])
            try db.execute("UPDATE recordings SET audio_state='deletePending',audio_epoch=audio_epoch+1,active_attempt=NULL,recognition_state='cancelled' WHERE id=? AND audio_state<>'deleted'",[.text(id.uuidString)])
            try db.execute("DELETE FROM recovery_attempts WHERE recording_id=?",[.text(id.uuidString)])
            if deleteRecord {
                // Keep only operation audit metadata; deleting a record erases its text snapshots as well.
                try db.execute("UPDATE recordings SET deleted=1,preferred_revision=NULL WHERE id=?",[.text(id.uuidString)])
                try db.execute("DELETE FROM editing_drafts WHERE recording_id=?",[.text(id.uuidString)])
                try db.execute("DELETE FROM cursors WHERE recording_id=?",[.text(id.uuidString)])
                try db.execute("DELETE FROM dispatches WHERE recording_id=?",[.text(id.uuidString)])
                try db.execute("DELETE FROM frozen_revisions WHERE revision_id IN(SELECT id FROM revisions WHERE recording_id=?)",[.text(id.uuidString)])
                try db.execute("DELETE FROM revisions WHERE recording_id=?",[.text(id.uuidString)])
            }
        }
    }
    private func completeErasure(_ id: UUID) throws {
        guard try db.rows("SELECT recording_id FROM erasures WHERE recording_id=? AND completed=0",[.text(id.uuidString)]).first != nil else { return }
        guard !leases.values.contains(id) else { return }
        // Remove the complete owned directory, including a crash tail not yet registered as a chunk.
        let url = try safeAudioURL(id.uuidString)
        if FileManager.default.fileExists(atPath:url.path) { try FileManager.default.removeItem(at:url) }
        let descriptor = Darwin.open(audioDirectory.path,O_RDONLY)
        guard descriptor >= 0 else { throw StoreError.database("无法同步原音删除目录") }
        let synced = Darwin.fsync(descriptor)
        Darwin.close(descriptor)
        guard synced == 0 else { throw StoreError.database("原音删除尚未同步，稍后将继续清理") }
        try db.transaction {
            try db.execute("UPDATE erasures SET completed=1 WHERE recording_id=?",[.text(id.uuidString)])
            try db.execute("UPDATE recordings SET audio_state='deleted' WHERE id=?",[.text(id.uuidString)])
            try db.execute("DELETE FROM chunks WHERE recording_id=?",[.text(id.uuidString)])
        }
    }
    private static func decodeRecording(_ row: [String:String]) -> Recording {
        Recording(id:UUID(uuidString:row["id"]!)!,createdAt:Date(timeIntervalSince1970:Double(row["created_at"]!)!),text:row["text"] ?? "",preferredRevisionID:row["preferred_revision"].flatMap(UUID.init(uuidString:)),duration:Double(row["total_frames"] ?? "0")! / Double(row["sample_rate"]!)!,isPinned:row["pinned"] == "1",audioState:AudioState(rawValue:row["audio_state"]!)!,recognitionState:RecognitionState(rawValue:row["recognition_state"]!)!,isRecording:row["is_recording"] == "1",lastError:row["last_error"],sampleRate:Double(row["sample_rate"]!)!)
    }
    private static func decodeRevision(_ row: [String:String]) -> TranscriptRevision {
        TranscriptRevision(id:UUID(uuidString:row["id"]!)!,recordingID:UUID(uuidString:row["recording_id"]!)!,text:row["text"]!,origin:RevisionOrigin(rawValue:row["origin"]!)!,createdAt:Date(timeIntervalSince1970:Double(row["created_at"]!)!))
    }
}

extension SaytileStore {
    public func createBinding(label: String) throws -> UUID {
        let id = UUID()
        try db.execute("INSERT INTO bindings(id,label,active,created_at) VALUES(?,?,1,?)",[.text(id.uuidString),.text(label),.double(Date().timeIntervalSince1970)])
        return id
    }
    public func invalidateBinding(_ id: UUID) throws {
        try db.execute("UPDATE bindings SET active=0 WHERE id=?",[.text(id.uuidString)])
    }
    public func reserveDispatch(bindingID: UUID, recordingID: UUID, revisionID: UUID, stableUTF16End: Int) throws -> DispatchReservation? {
        do {
            return try db.transaction {
                guard let binding = try db.rows("SELECT active,created_at FROM bindings WHERE id=?",[.text(bindingID.uuidString)]).first,binding["active"] == "1" else { throw StoreError.bindingInvalid }
                let record = try requireRecording(recordingID)
                guard record.createdAt.timeIntervalSince1970 >= Double(binding["created_at"]!)! else { throw StoreError.bindingInvalid }
                guard let revision = try db.rows("SELECT text,origin FROM revisions WHERE id=? AND recording_id=?",[.text(revisionID.uuidString),.text(recordingID.uuidString)]).first else { throw StoreError.missingRevision }
                let text = revision["text"]!
                let cursor = try db.rows("SELECT end_utf16,prefix FROM cursors WHERE binding_id=? AND recording_id=?",[.text(bindingID.uuidString),.text(recordingID.uuidString)]).first
                let start = Int(cursor?["end_utf16"] ?? "0")!
                guard let prefix = Self.slice(text,start:0,end:start),prefix == (cursor?["prefix"] ?? "") else { throw StoreError.prefixChanged }
                guard stableUTF16End >= start, let suffix = Self.slice(text,start:start,end:stableUTF16End),let newPrefix = Self.slice(text,start:0,end:stableUTF16End) else { throw StoreError.invalidBoundary }
                guard stableUTF16End > start else { return nil }
                let reservation = DispatchReservation(id:UUID(),recordingID:recordingID,revisionID:revisionID,text:suffix,utf16Start:start,utf16End:stableUTF16End)
                try db.execute("INSERT INTO dispatches(id,binding_id,recording_id,revision_id,start_utf16,end_utf16,text,state,kind) VALUES(?,?,?,?,?,?,?,'dispatching','direct')",[.text(reservation.id.uuidString),.text(bindingID.uuidString),.text(recordingID.uuidString),.text(revisionID.uuidString),.int(Int64(start)),.int(Int64(stableUTF16End)),.text(suffix)])
                try db.execute("INSERT INTO cursors(binding_id,recording_id,end_utf16,prefix) VALUES(?,?,?,?) ON CONFLICT(binding_id,recording_id) DO UPDATE SET end_utf16=excluded.end_utf16,prefix=excluded.prefix",[.text(bindingID.uuidString),.text(recordingID.uuidString),.int(Int64(stableUTF16End)),.text(newPrefix)])
                return reservation
            }
        } catch StoreError.prefixChanged {
            try invalidateBinding(bindingID)
            throw StoreError.prefixChanged
        }
    }
    public func reserveManual(recordingID: UUID, revisionID: UUID, label: String) throws -> DispatchReservation {
        _ = try requireRecording(recordingID)
        guard let text = try db.rows("SELECT text FROM revisions WHERE id=? AND recording_id=?",[.text(revisionID.uuidString),.text(recordingID.uuidString)]).first?["text"] else { throw StoreError.missingRevision }
        let reservation = DispatchReservation(id:UUID(),recordingID:recordingID,revisionID:revisionID,text:text,utf16Start:0,utf16End:text.utf16.count)
        try db.execute("INSERT INTO dispatches(id,recording_id,revision_id,start_utf16,end_utf16,text,state,kind,label) VALUES(?,?,?,0,?,?,'dispatching','manual',?)",[.text(reservation.id.uuidString),.text(recordingID.uuidString),.text(revisionID.uuidString),.int(Int64(text.utf16.count)),.text(text),.text(label)])
        return reservation
    }
    public func completeDispatch(id: UUID, state: DispatchState) throws {
        guard state != .dispatching else { return }
        try db.execute("UPDATE dispatches SET state=? WHERE id=? AND state='dispatching'",[.text(state.rawValue),.text(id.uuidString)])
    }
    public func dispatchState(id: UUID) throws -> DispatchState? {
        try db.rows("SELECT state FROM dispatches WHERE id=?",[.text(id.uuidString)]).first?["state"].flatMap(DispatchState.init(rawValue:))
    }
    private static func slice(_ text: String, start: Int, end: Int) -> String? {
        guard start >= 0,end >= start,end <= text.utf16.count else { return nil }
        let units = text.utf16
        let lower = units.index(units.startIndex,offsetBy:start),upper = units.index(units.startIndex,offsetBy:end)
        guard let lo = String.Index(lower,within:text),let hi = String.Index(upper,within:text), text.indices.contains(lo) || lo == text.endIndex, text.indices.contains(hi) || hi == text.endIndex else { return nil }
        return String(text[lo..<hi])
    }
    private static let schema = """
    CREATE TABLE IF NOT EXISTS recordings(
      id TEXT PRIMARY KEY,created_at REAL NOT NULL,sample_rate REAL NOT NULL CHECK(sample_rate>0),
      preferred_revision TEXT,pinned INTEGER NOT NULL DEFAULT 0,deleted INTEGER NOT NULL DEFAULT 0,
      audio_state TEXT NOT NULL DEFAULT 'available' CHECK(audio_state IN('available','deletePending','deleted','missing')),
      recognition_state TEXT NOT NULL DEFAULT 'queued' CHECK(recognition_state IN('queued','running','completed','failed','cancelled')),
      is_recording INTEGER NOT NULL DEFAULT 1,audio_epoch INTEGER NOT NULL DEFAULT 1,
      active_attempt TEXT,last_error TEXT,total_frames INTEGER NOT NULL DEFAULT 0
    );
    CREATE TABLE IF NOT EXISTS chunks(
      id TEXT PRIMARY KEY,recording_id TEXT NOT NULL REFERENCES recordings(id),path TEXT NOT NULL UNIQUE,
      frames INTEGER NOT NULL CHECK(frames>=0),ordinal INTEGER NOT NULL,UNIQUE(recording_id,ordinal)
    );
    CREATE TRIGGER IF NOT EXISTS chunks_insert AFTER INSERT ON chunks BEGIN
      UPDATE recordings SET total_frames=(SELECT COALESCE(SUM(frames),0) FROM chunks WHERE recording_id=NEW.recording_id) WHERE id=NEW.recording_id;
    END;
    CREATE TRIGGER IF NOT EXISTS chunks_update AFTER UPDATE OF frames ON chunks BEGIN
      UPDATE recordings SET total_frames=(SELECT COALESCE(SUM(frames),0) FROM chunks WHERE recording_id=NEW.recording_id) WHERE id=NEW.recording_id;
    END;
    CREATE TABLE IF NOT EXISTS revisions(
      id TEXT PRIMARY KEY,recording_id TEXT NOT NULL REFERENCES recordings(id),text TEXT NOT NULL,
      origin TEXT NOT NULL CHECK(origin IN('partial','final','userEdit')),created_at REAL NOT NULL,attempt TEXT,base_revision TEXT
    );
    CREATE TRIGGER IF NOT EXISTS revisions_immutable BEFORE UPDATE ON revisions BEGIN
      SELECT RAISE(ABORT,'create a new revision');
    END;
    CREATE TABLE IF NOT EXISTS editing_drafts(recording_id TEXT PRIMARY KEY REFERENCES recordings(id),text TEXT NOT NULL,updated_at REAL NOT NULL);
    CREATE TABLE IF NOT EXISTS frozen_revisions(revision_id TEXT PRIMARY KEY REFERENCES revisions(id));
    CREATE TABLE IF NOT EXISTS recovery_attempts(recording_id TEXT PRIMARY KEY REFERENCES recordings(id),attempt_count INTEGER NOT NULL CHECK(attempt_count>=0),retry_after REAL NOT NULL);
    CREATE TABLE IF NOT EXISTS erasures(recording_id TEXT PRIMARY KEY,created_at REAL NOT NULL,completed INTEGER NOT NULL DEFAULT 0);
    CREATE TABLE IF NOT EXISTS bindings(id TEXT PRIMARY KEY,label TEXT NOT NULL,active INTEGER NOT NULL,created_at REAL NOT NULL);
    CREATE TABLE IF NOT EXISTS cursors(
      binding_id TEXT NOT NULL REFERENCES bindings(id),recording_id TEXT NOT NULL REFERENCES recordings(id),
      end_utf16 INTEGER NOT NULL CHECK(end_utf16>=0),prefix TEXT NOT NULL,PRIMARY KEY(binding_id,recording_id)
    );
    CREATE TRIGGER IF NOT EXISTS cursor_no_rewind BEFORE UPDATE OF end_utf16 ON cursors
      WHEN NEW.end_utf16<OLD.end_utf16 BEGIN SELECT RAISE(ABORT,'cursor cannot rewind'); END;
    CREATE TABLE IF NOT EXISTS dispatches(
      id TEXT PRIMARY KEY,binding_id TEXT REFERENCES bindings(id),recording_id TEXT NOT NULL REFERENCES recordings(id),
      revision_id TEXT NOT NULL REFERENCES revisions(id),start_utf16 INTEGER NOT NULL,end_utf16 INTEGER NOT NULL,
      text TEXT NOT NULL,state TEXT NOT NULL CHECK(state IN('dispatching','confirmed','unverified','failed','cancelled')),
      kind TEXT NOT NULL CHECK(kind IN('manual','direct')),label TEXT,CHECK(end_utf16>=start_utf16)
    );
    CREATE TRIGGER IF NOT EXISTS dispatch_no_overlap BEFORE INSERT ON dispatches
      WHEN NEW.kind='direct' AND EXISTS(SELECT 1 FROM dispatches WHERE kind='direct' AND binding_id=NEW.binding_id AND recording_id=NEW.recording_id AND NEW.start_utf16<end_utf16 AND start_utf16<NEW.end_utf16)
      BEGIN SELECT RAISE(ABORT,'dispatch overlaps prior reservation'); END;
    CREATE INDEX IF NOT EXISTS records_date ON recordings(created_at);
    CREATE INDEX IF NOT EXISTS revision_record ON revisions(recording_id,created_at);
    PRAGMA user_version=1;
    """
}
