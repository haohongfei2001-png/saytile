import Foundation
import Darwin

/// Native SQLite persistence. Audio files have one recording owner; text versions are immutable.
public actor SaytileStore {
    public nonisolated let directory: URL
    public nonisolated let audioDirectory: URL
    public nonisolated let recovery: StoreRecovery
    private let db: StoreDatabase
    private let processLock: StoreProcessLock
    private var leases: [UUID: UUID] = [:]
    private static let selection = "SELECT r.*,v.text FROM recordings r LEFT JOIN revisions v ON r.preferred_revision=v.id"

    public init(directory: URL) throws {
        let normalized = directory.standardizedFileURL
        try StorePath.rejectSymbolicLink(normalized)
        try FileManager.default.createDirectory(at:normalized,withIntermediateDirectories:true)
        self.directory = normalized.resolvingSymlinksInPath()
        self.audioDirectory = self.directory.appendingPathComponent("Audio",isDirectory:true)
        try StorePath.rejectSymbolicLink(audioDirectory)
        try FileManager.default.createDirectory(at:audioDirectory,withIntermediateDirectories:true)
        try FileManager.default.setAttributes([.posixPermissions:0o700],ofItemAtPath:self.directory.path)
        processLock = try StoreProcessLock(directory:self.directory)
        for name in ["Saytile.sqlite","Saytile.sqlite-wal","Saytile.sqlite-shm"] {
            try StorePath.rejectSymbolicLink(self.directory.appendingPathComponent(name))
        }
        let database = try StoreDatabase(url:self.directory.appendingPathComponent("Saytile.sqlite"))
        db = database
        let version = try database.rows("PRAGMA user_version").first?["user_version"] ?? "0"
        guard version == "0" || version == "1" || version == "2" || version == "3" else { throw StoreError.database("资料库来自更新版本，请升级 Saytile。") }
        try database.configureForWriting()
        // DDL, index upgrades and version advancement commit together or roll back together.
        try database.transaction { try database.script(Self.schema) }
        func count(_ whereClause: String) throws -> Int { Int(try database.rows("SELECT COUNT(*) AS n FROM \(whereClause)").first?["n"] ?? "0") ?? 0 }
        recovery = try StoreRecovery(interruptedRecordings:count("recordings WHERE is_recording=1"),interruptedRecognitions:count("recordings WHERE recognition_state='running'"),unverifiedDispatches:count("dispatches WHERE state='dispatching'"))
        try database.transaction {
            try database.execute("UPDATE recordings SET is_recording=0,last_error='上次录音意外中断，已保存的原音可以恢复。' WHERE is_recording=1")
            try database.execute("UPDATE recordings SET recognition_state='queued',active_attempt=NULL WHERE recognition_state='running'")
            try database.execute("UPDATE model_runs SET state='interrupted' WHERE state='running'")
            try database.execute("UPDATE fusion_sessions SET state='interrupted' WHERE state='running'")
            try database.execute("UPDATE bindings SET active=0")
            try database.execute("UPDATE dispatches SET state='unverified' WHERE state='dispatching'")
        }
        // Cleanup is resumed by recoverPendingDeletions, before importing any audio.
    }

    /// Call only after producers and pending draft writes have stopped.
    public func close() throws {
        try db.close()
        leases.removeAll()
        processLock.close()
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
        return try db.rows(Self.selection + " WHERE r.deleted=0" + filterSQL + " AND (?='' OR EXISTS (SELECT 1 FROM revisions s WHERE s.recording_id=r.id AND s.text LIKE ? ESCAPE '\\') OR EXISTS (SELECT 1 FROM editing_drafts d WHERE d.recording_id=r.id AND d.text LIKE ? ESCAPE '\\')) ORDER BY r.created_at DESC,r.id DESC LIMIT ? OFFSET ?",[.text(query),.text("%" + escaped + "%"),.text("%" + escaped + "%"),.int(Int64(max(1,min(limit,1000)))),.int(Int64(max(0,offset)))]).map(Self.decodeRecording)
    }
    /// Pages the current listening session plus records explicitly returned to the panel.
    public func listPanelRecordings(createdSince: Date, includingIDs: [UUID], limit: Int = 100, offset: Int = 0) throws -> [Recording] {
        let (predicate,values) = try panelPredicate(createdSince:createdSince,includingIDs:includingIDs)
        return try db.rows(Self.selection + " WHERE " + predicate + " ORDER BY r.created_at DESC,r.id DESC LIMIT ? OFFSET ?",values + [.int(Int64(max(1,min(limit,1000)))),.int(Int64(max(0,offset)))]).map(Self.decodeRecording)
    }
    public func panelRecordingCount(createdSince: Date, includingIDs: [UUID]) throws -> Int {
        let (predicate,values) = try panelPredicate(createdSince:createdSince,includingIDs:includingIDs)
        return Int(try db.rows("SELECT COUNT(*) AS n FROM recordings r WHERE " + predicate,values).first?["n"] ?? "0") ?? 0
    }
    private func panelPredicate(createdSince: Date, includingIDs: [UUID]) throws -> (String,[StoreDatabase.Value]) {
        let ids = Set(includingIDs)
        guard ids.count <= 30_000 else { throw StoreError.database("输入板包含过多记录，请分批取用。") }
        var values: [StoreDatabase.Value] = [.double(createdSince.timeIntervalSince1970)]
        let included: String
        if ids.isEmpty { included = "" }
        else {
            included = " OR r.id IN(" + Array(repeating:"?",count:ids.count).joined(separator:",") + ")"
            values += ids.map { .text($0.uuidString) }
        }
        return ("r.deleted=0 AND (r.created_at>=?" + included + ")",values)
    }

    /// Capture/storage failure closes the source independently of ASR cancellation.
    /// Only published durable frames justify an available original-audio state.
    public func recordCaptureFailure(recordingID: UUID, message: String) throws {
        _ = try requireRecording(recordingID)
        try invalidateModelRuns(recordingID: recordingID)
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
        try invalidateModelRuns(recordingID: recordingID)
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
                let existing = try Self.decodeRevision(row)
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
        try db.transaction {
            try invalidateModelRuns(recordingID: recordingID)
            try db.execute("UPDATE recordings SET active_attempt=?,recognition_state='running',last_error=NULL WHERE id=?",[.text(ticket.id.uuidString),.text(recordingID.uuidString)])
        }
        return ticket
    }
    @discardableResult public func applyRecognition(ticket: RecognitionTicket, text: String, isFinal: Bool) throws -> Bool {
        try db.transaction {
            guard try validTicket(ticket), try db.rows("SELECT id FROM fusion_sessions WHERE id=?", [.text(ticket.id.uuidString)]).isEmpty else { return false }
            let revision = TranscriptRevision(id:UUID(),recordingID:ticket.recordingID,text:text,origin:isFinal ? .final:.partial,createdAt:Date())
            try insertRevision(revision,attempt:ticket.id,base:nil)
            // An explicit user edit remains selected while later ASR results are preserved as other versions.
            try db.execute("UPDATE recordings SET preferred_revision=? WHERE id=? AND NOT EXISTS(SELECT 1 FROM revisions WHERE id=recordings.preferred_revision AND origin='userEdit')",[.text(revision.id.uuidString),.text(ticket.recordingID.uuidString)])
            // Only unreferenced volatile drafts can be replaced; finals and insertion snapshots remain immutable.
            try db.execute("DELETE FROM revisions WHERE recording_id=? AND origin='partial' AND attempt=? AND id<>? AND NOT EXISTS(SELECT 1 FROM dispatches d WHERE d.revision_id=revisions.id) AND NOT EXISTS(SELECT 1 FROM recordings r WHERE r.preferred_revision=revisions.id) AND NOT EXISTS(SELECT 1 FROM revisions b WHERE b.base_revision=revisions.id) AND NOT EXISTS(SELECT 1 FROM frozen_revisions f WHERE f.revision_id=revisions.id)",[.text(ticket.recordingID.uuidString),.text(ticket.id.uuidString),.text(revision.id.uuidString)])
            return true
        }
    }
    /// End only after the recognizer's final result stream has drained.
    public func finishRecognition(ticket: RecognitionTicket) throws {
        guard try validTicket(ticket) else { return }
        try db.transaction {
            try invalidateModelRuns(recordingID: ticket.recordingID, sessionState: "completed")
            try db.execute("UPDATE recordings SET recognition_state='completed',active_attempt=NULL,last_error=NULL WHERE id=?",[.text(ticket.recordingID.uuidString)])
        }
    }
    public func failRecognition(ticket: RecognitionTicket, message: String) throws {
        guard try validTicket(ticket) else { return }
        try db.transaction {
            try invalidateModelRuns(recordingID: ticket.recordingID, sessionState: "failed")
            try db.execute("UPDATE recordings SET recognition_state='failed',active_attempt=NULL,last_error=? WHERE id=?",[.text(message),.text(ticket.recordingID.uuidString)])
        }
    }
    public func queueRecognition(recordingID: UUID) throws {
        let record = try requireRecording(recordingID)
        guard record.audioState == .available else { throw StoreError.audioUnavailable }
        try db.transaction {
            try invalidateModelRuns(recordingID: recordingID)
            try db.execute("UPDATE recordings SET recognition_state='queued',active_attempt=NULL WHERE id=?",[.text(recordingID.uuidString)])
        }
    }
    public func pendingRecordings(limit: Int = 100) throws -> [Recording] {
        try db.rows(Self.selection + " WHERE r.deleted=0 AND r.audio_state='available' AND r.is_recording=0 AND r.recognition_state IN('queued','failed') ORDER BY r.created_at LIMIT ?",[.int(Int64(max(1,min(1000,limit))))]).map(Self.decodeRecording)
    }

    /// Persisted finite retry scheduling prevents old failed records starving newer ones.
    /// Claims are taken transactionally, at most three automatically per recording.
    public func claimRecoveryRecording(now: Date = Date()) throws -> Recording? {
        try db.transaction {
            guard let row = try db.rows(Self.selection + " LEFT JOIN recovery_attempts a ON a.recording_id=r.id WHERE r.deleted=0 AND r.audio_state='available' AND r.is_recording=0 AND r.recognition_state IN('queued','failed') AND NOT EXISTS(SELECT 1 FROM recognition_retry_blocks block WHERE block.recording_id=r.id) AND COALESCE(a.attempt_count,0)<3 AND COALESCE(a.retry_after,0)<=? ORDER BY COALESCE(a.attempt_count,0),r.created_at LIMIT 1",[.double(now.timeIntervalSince1970)]).first else { return nil }
            let record = try Self.decodeRecording(row)
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
    public func recoverPendingDeletions() async throws {
        var cursor: Int64 = 0
        while true {
            let batch = try db.rows("SELECT rowid AS scan_id,recording_id,completed FROM erasures WHERE rowid>? ORDER BY rowid LIMIT 256",[.int(cursor)])
            guard !batch.isEmpty else { break }
            for row in batch {
                cursor = Int64(row["scan_id"]!)!
                guard let id = UUID(uuidString:row["recording_id"]!) else { continue }
                if row["completed"] == "1" {
                    let residual = try safeAudioURL(id.uuidString)
                    guard FileManager.default.fileExists(atPath:residual.path) else { continue }
                    try db.transaction {
                        try db.execute("UPDATE erasures SET completed=0 WHERE recording_id=?",[.text(id.uuidString)])
                        try db.execute("UPDATE recordings SET audio_state='deletePending' WHERE id=?",[.text(id.uuidString)])
                    }
                }
                try completeErasure(id)
                await Task.yield()
            }
            await Task.yield()
        }
    }
    public func cleanupCandidates(olderThan: Date) throws -> [Recording] {
        try db.rows(Self.selection + " WHERE r.deleted=0 AND r.pinned=0 AND r.audio_state='available' AND r.recognition_state='completed' AND r.is_recording=0 AND r.created_at<? ORDER BY r.created_at",[.double(olderThan.timeIntervalSince1970)]).map(Self.decodeRecording).filter { !leases.values.contains($0.id) }
    }
    /// Revalidate the preview at execution time. Newly pinned, active, failed or leased audio stays protected.
    @discardableResult public func cleanupAudio(recordingIDs: [UUID], olderThan: Date) async throws -> Int {
        var seen: Set<UUID> = []
        var count = 0
        for id in recordingIDs where seen.insert(id).inserted {
            try Task.checkCancellation()
            guard let record = try recording(id:id), !record.isPinned, !record.isRecording,
                  record.audioState == .available, record.recognitionState == .completed,
                  record.createdAt < olderThan, !leases.values.contains(id) else { await Task.yield(); continue }
            try beginErasure(id,deleteRecord:false)
            try completeErasure(id)
            count += 1
            // Each physical cleanup is already durable. Let capture checkpoints and edits run.
            await Task.yield()
        }
        return count
    }
    public func storageSummary() async throws -> StorageSummary {
        let audioRoot = audioDirectory
        let scan = Task.detached(priority:.utility) { try Self.audioSize(audioRoot) }
        let bytes = try await withTaskCancellationHandler { try await scan.value } onCancel: { scan.cancel() }
        let space = try FileManager.default.attributesOfFileSystem(forPath:directory.path)[.systemFreeSize] as? NSNumber
        func count(_ predicate: String) throws -> Int { Int(try db.rows("SELECT COUNT(*) AS n FROM recordings WHERE \(predicate)").first?["n"] ?? "0") ?? 0 }
        return try StorageSummary(audioBytes:bytes,recordingCount:count("deleted=0"),pendingRecognitionCount:count("deleted=0 AND recognition_state IN('queued','running','failed') AND audio_state='available'"),pendingDeletionCount:count("audio_state='deletePending'"),availableDiskBytes:space?.int64Value ?? 0)
    }

    private nonisolated static func audioSize(_ root: URL) throws -> Int64 {
        let keys: [URLResourceKey] = [.isRegularFileKey,.fileSizeKey,.isSymbolicLinkKey]
        var bytes: Int64 = 0
        if let enumerator = FileManager.default.enumerator(at:root,includingPropertiesForKeys:keys) {
            for case let url as URL in enumerator {
                try Task.checkCancellation()
                do {
                    let value = try url.resourceValues(forKeys:Set(keys))
                    if value.isRegularFile == true && value.isSymbolicLink != true { bytes += Int64(value.fileSize ?? 0) }
                } catch let error as CocoaError where error.code == .fileReadNoSuchFile { continue }
            }
        }
        return bytes
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
        try db.rows("SELECT * FROM chunks WHERE recording_id=? ORDER BY ordinal",[.text(id.uuidString)]).map { row in
            guard let chunkID = row["id"].flatMap(UUID.init(uuidString:)),let path = row["path"],let frames = row["frames"].flatMap(Int64.init), frames >= 0,let ordinal = row["ordinal"].flatMap(Int.init),ordinal >= 0 else { throw StoreError.database("原音索引损坏，请保留资料目录以便恢复。") }
            return AudioChunk(id:chunkID,recordingID:id,relativePath:path,frames:frames,ordinal:ordinal)
        }
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
            try invalidateModelRuns(recordingID: id)
            try db.execute("INSERT OR IGNORE INTO erasures(recording_id,created_at,completed) VALUES(?,?,0)",[.text(id.uuidString),.double(Date().timeIntervalSince1970)])
            try db.execute("UPDATE recordings SET audio_state='deletePending',audio_epoch=audio_epoch+1,active_attempt=NULL,recognition_state='cancelled' WHERE id=? AND audio_state<>'deleted'",[.text(id.uuidString)])
            try db.execute("DELETE FROM recovery_attempts WHERE recording_id=?",[.text(id.uuidString)])
            if deleteRecord {
                // Keep only operation audit metadata; deleting a record erases its text snapshots as well.
                try db.execute("UPDATE fusion_sessions SET stable_text='' WHERE recording_id=?", [.text(id.uuidString)])
                try db.execute("DELETE FROM fusion_dispatch_heads WHERE recording_id=?", [.text(id.uuidString)])
                try db.execute("DELETE FROM fusion_archives WHERE recording_id=?", [.text(id.uuidString)])
                try db.execute("DELETE FROM fusion_decisions WHERE recording_id=?", [.text(id.uuidString)])
                try db.execute("DELETE FROM recognition_candidates WHERE recording_id=?", [.text(id.uuidString)])
                try db.execute("UPDATE recordings SET deleted=1,preferred_revision=NULL WHERE id=?",[.text(id.uuidString)])
                try db.execute("DELETE FROM editing_drafts WHERE recording_id=?",[.text(id.uuidString)])
                // Keep a text-free ordering tombstone for active bindings. Removing it
                // would allow earlier delayed recognition to follow a deleted later record.
                try db.execute("UPDATE cursors SET prefix='' WHERE recording_id=?",[.text(id.uuidString)])
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
    private static func decodeRecording(_ row: [String:String]) throws -> Recording {
        guard let id = row["id"].flatMap(UUID.init(uuidString:)),
              let createdAt = row["created_at"].flatMap(Double.init), createdAt.isFinite,
              let sampleRate = row["sample_rate"].flatMap(Double.init), sampleRate.isFinite, sampleRate > 0,
              let frames = row["total_frames"].flatMap(Int64.init), frames >= 0,
              let audioState = row["audio_state"].flatMap(AudioState.init(rawValue:)),
              let recognition = row["recognition_state"].flatMap(RecognitionState.init(rawValue:)) else {
            throw StoreError.database("记录元数据损坏，请保留资料目录以便恢复。")
        }
        return Recording(id:id,createdAt:Date(timeIntervalSince1970:createdAt),text:row["text"] ?? "",preferredRevisionID:row["preferred_revision"].flatMap(UUID.init(uuidString:)),duration:Double(frames) / sampleRate,isPinned:row["pinned"] == "1",audioState:audioState,recognitionState:recognition,isRecording:row["is_recording"] == "1",lastError:row["last_error"],sampleRate:sampleRate)
    }
    private static func decodeRevision(_ row: [String:String]) throws -> TranscriptRevision {
        guard let id = row["id"].flatMap(UUID.init(uuidString:)),
              let recordingID = row["recording_id"].flatMap(UUID.init(uuidString:)),
              let text = row["text"],let origin = row["origin"].flatMap(RevisionOrigin.init(rawValue:)),
              let createdAt = row["created_at"].flatMap(Double.init),createdAt.isFinite else {
            throw StoreError.database("文字版本元数据损坏，请保留资料目录以便恢复。")
        }
        return TranscriptRevision(id:id,recordingID:recordingID,text:text,origin:origin,createdAt:Date(timeIntervalSince1970:createdAt))
    }

}

extension SaytileStore {
    public func createBinding(label: String, createdAt: Date = Date()) throws -> UUID {
        try db.transaction {
            let id = UUID()
            try db.execute("INSERT INTO bindings(id,label,active,created_at) VALUES(?,?,1,?)",[.text(id.uuidString),.text(label),.double(createdAt.timeIntervalSince1970)])
            // Recording rows are retained as tombstones on deletion. Their rowids
            // therefore establish creation order even when the clock has one tick
            // for both the binding and the next recording.
            try db.execute("INSERT INTO binding_boundaries(binding_id,recording_rowid) SELECT ?,COALESCE(MAX(rowid),0) FROM recordings",[.text(id.uuidString)])
            return id
        }
    }
    public func invalidateBinding(_ id: UUID) throws {
        try db.execute("UPDATE bindings SET active=0 WHERE id=?",[.text(id.uuidString)])
    }
    /// Finds final text not yet reserved for this live binding, including delayed ASR
    /// outside the panel's most recent page. The selected transcript is unchanged;
    /// callers still fetch the latest final revision and reserve it before dispatch.
    public func directInputCandidates(bindingID: UUID, createdSince: Date, limit: Int = 100) throws -> [Recording] {
        try directInputRows(bindingID:bindingID,createdSince:createdSince,limit:limit,deferred:false).map(Self.decodeRecording)
    }
    /// Earlier finalized text that cannot be appended without reordering the target.
    /// Already-reserved complete prefixes are excluded, so completed earlier speech
    /// is not incorrectly marked as deferred.
    public func deferredDirectInputRecordings(bindingID: UUID, createdSince: Date, limit: Int = 100) throws -> [UUID] {
        try directInputRows(bindingID:bindingID,createdSince:createdSince,limit:limit,deferred:true).compactMap { $0["id"].flatMap(UUID.init(uuidString:)) }
    }
    private func directInputRows(bindingID: UUID, createdSince: Date, limit: Int, deferred: Bool) throws -> [[String:String]] {
        let projection = deferred ? "SELECT r.id FROM recordings r" : Self.selection
        let orderPredicate = deferred
            ? "watermark.sequence IS NOT NULL AND r.rowid<watermark.sequence"
            : "watermark.sequence IS NULL OR r.rowid>=watermark.sequence"
        return try db.rows(projection + """
         JOIN bindings b ON b.id=? AND b.active=1
         JOIN binding_boundaries boundary ON boundary.binding_id=b.id
         JOIN revisions stable ON stable.id=(
           SELECT latest.id FROM revisions latest
           WHERE latest.recording_id=r.id AND latest.origin='final'
             AND NOT EXISTS(SELECT 1 FROM fusion_archives archive WHERE archive.revision_id=latest.id)
           ORDER BY latest.created_at DESC,latest.rowid DESC LIMIT 1
         )
         LEFT JOIN cursors cursor ON cursor.binding_id=b.id AND cursor.recording_id=r.id
         LEFT JOIN (
           SELECT MAX(prior.rowid) AS sequence FROM cursors progress
           JOIN recordings prior ON prior.id=progress.recording_id
           WHERE progress.binding_id=? AND progress.end_utf16>0
         ) watermark ON 1=1
         WHERE r.deleted=0 AND r.rowid>boundary.recording_rowid
           AND r.created_at>=? AND r.created_at>=b.created_at
           AND stable.text<>'' AND (cursor.prefix IS NULL OR stable.text<>cursor.prefix)
           AND (\(orderPredicate))
         ORDER BY r.rowid ASC LIMIT ?
        """,[.text(bindingID.uuidString),.text(bindingID.uuidString),.double(createdSince.timeIntervalSince1970),.int(Int64(max(1,min(limit,1000))))])
    }
    public func reserveDispatch(bindingID: UUID, recordingID: UUID, revisionID: UUID, stableUTF16End: Int) throws -> DispatchReservation? {
        do {
            return try db.transaction {
                guard try db.rows("""
                SELECT 1 FROM bindings b
                JOIN binding_boundaries boundary ON boundary.binding_id=b.id
                JOIN recordings r ON r.id=? AND r.deleted=0
                WHERE b.id=? AND b.active=1 AND r.rowid>boundary.recording_rowid
                  AND r.created_at>=b.created_at
                """,[.text(recordingID.uuidString),.text(bindingID.uuidString)]).first != nil else { throw StoreError.bindingInvalid }
                guard let revision = try db.rows("SELECT text,origin FROM revisions WHERE id=? AND recording_id=?",[.text(revisionID.uuidString),.text(recordingID.uuidString)]).first else { throw StoreError.missingRevision }
                guard try db.rows("SELECT revision_id FROM fusion_archives WHERE revision_id=?", [.text(revisionID.uuidString)]).isEmpty else { throw StoreError.lateRecognitionDeferred }
                let text = revision["text"]!
                let cursor = try db.rows("SELECT end_utf16,prefix FROM cursors WHERE binding_id=? AND recording_id=?",[.text(bindingID.uuidString),.text(recordingID.uuidString)]).first
                let start = Int(cursor?["end_utf16"] ?? "0")!
                let prefix = Self.slice(text,start:0,end:start)
                // Duplicate callbacks remain a no-op, even after a later record advanced.
                if stableUTF16End == start, prefix == (cursor?["prefix"] ?? "") { return nil }
                let advanced = try db.rows("""
                SELECT 1 FROM cursors progress
                JOIN recordings prior ON prior.id=progress.recording_id
                JOIN recordings current ON current.id=?
                WHERE progress.binding_id=? AND progress.end_utf16>0
                  AND prior.rowid>current.rowid LIMIT 1
                """,[.text(recordingID.uuidString),.text(bindingID.uuidString)]).first != nil
                guard !advanced else { throw StoreError.lateRecognitionDeferred }
                guard let prefix, prefix == (cursor?["prefix"] ?? "") else { throw StoreError.prefixChanged }
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
    CREATE TABLE IF NOT EXISTS binding_boundaries(binding_id TEXT PRIMARY KEY REFERENCES bindings(id),recording_rowid INTEGER NOT NULL);
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
    CREATE INDEX IF NOT EXISTS revision_latest_final ON revisions(recording_id,created_at DESC) WHERE origin='final';
    CREATE INDEX IF NOT EXISTS records_live_date ON recordings(deleted,created_at DESC,id DESC);
    CREATE INDEX IF NOT EXISTS records_preferred ON recordings(preferred_revision);
    CREATE INDEX IF NOT EXISTS revisions_base ON revisions(base_revision);
    CREATE INDEX IF NOT EXISTS revisions_attempt ON revisions(recording_id,origin,attempt);
    CREATE INDEX IF NOT EXISTS dispatch_revision ON dispatches(revision_id);
    CREATE INDEX IF NOT EXISTS recovery_candidates ON recordings(created_at) WHERE deleted=0 AND audio_state='available' AND is_recording=0 AND recognition_state IN('queued','failed');
    CREATE TABLE IF NOT EXISTS fusion_sessions(
      id TEXT PRIMARY KEY,recording_id TEXT NOT NULL REFERENCES recordings(id),audio_epoch INTEGER NOT NULL,
      mode TEXT NOT NULL,state TEXT NOT NULL,stable_text TEXT NOT NULL DEFAULT '',created_at REAL NOT NULL
    );
    CREATE TABLE IF NOT EXISTS model_runs(
      id TEXT PRIMARY KEY,recognition_id TEXT NOT NULL REFERENCES fusion_sessions(id),recording_id TEXT NOT NULL REFERENCES recordings(id),
      audio_epoch INTEGER NOT NULL,configuration_id TEXT NOT NULL,payload TEXT NOT NULL,state TEXT NOT NULL,
      last_sequence INTEGER NOT NULL DEFAULT -1,retryable INTEGER NOT NULL DEFAULT 1,last_error TEXT,created_at REAL NOT NULL
    );
    CREATE TABLE IF NOT EXISTS recognition_candidates(
      id TEXT PRIMARY KEY,run_id TEXT NOT NULL REFERENCES model_runs(id),recognition_id TEXT NOT NULL REFERENCES fusion_sessions(id),
      recording_id TEXT NOT NULL REFERENCES recordings(id),sequence INTEGER NOT NULL,payload TEXT NOT NULL,created_at REAL NOT NULL,UNIQUE(run_id,sequence)
    );
    CREATE TRIGGER IF NOT EXISTS candidates_immutable BEFORE UPDATE ON recognition_candidates BEGIN SELECT RAISE(ABORT,'create a new candidate'); END;
    CREATE TABLE IF NOT EXISTS fusion_dispatch_heads(recording_id TEXT PRIMARY KEY REFERENCES recordings(id),revision_id TEXT NOT NULL REFERENCES revisions(id));
    CREATE TABLE IF NOT EXISTS fusion_archives(revision_id TEXT PRIMARY KEY REFERENCES revisions(id),recording_id TEXT NOT NULL REFERENCES recordings(id),recognition_id TEXT NOT NULL REFERENCES fusion_sessions(id));
    CREATE TABLE IF NOT EXISTS fusion_decisions(id TEXT PRIMARY KEY,recognition_id TEXT NOT NULL REFERENCES fusion_sessions(id),recording_id TEXT NOT NULL REFERENCES recordings(id),payload TEXT NOT NULL,created_at REAL NOT NULL);
    CREATE TABLE IF NOT EXISTS model_usage(id TEXT PRIMARY KEY,run_id TEXT NOT NULL REFERENCES model_runs(id),recording_id TEXT NOT NULL REFERENCES recordings(id),payload TEXT NOT NULL,created_at REAL NOT NULL);
    CREATE TABLE IF NOT EXISTS recognition_retry_blocks(recording_id TEXT PRIMARY KEY REFERENCES recordings(id),reason TEXT NOT NULL);
    CREATE INDEX IF NOT EXISTS model_runs_recording ON model_runs(recording_id,created_at);
    CREATE INDEX IF NOT EXISTS model_runs_configuration ON model_runs(recognition_id,configuration_id);
    CREATE INDEX IF NOT EXISTS candidates_session ON recognition_candidates(recognition_id,run_id,sequence);
    CREATE INDEX IF NOT EXISTS candidates_recording ON recognition_candidates(recording_id,created_at);
    CREATE INDEX IF NOT EXISTS decisions_recording ON fusion_decisions(recording_id,created_at);
    CREATE INDEX IF NOT EXISTS usage_recording ON model_usage(recording_id,created_at);
    PRAGMA user_version=3;
    """
}

extension SaytileStore {
    /// This logical ticket owns publication. Provider tickets are separate and never accepted by applyRecognition.
    public func beginFusionRecognition(recordingID: UUID, mode: InputQualityMode = .highestQuality) throws -> RecognitionTicket {
        let record = try requireRecording(recordingID)
        guard record.audioState == .available else { throw StoreError.audioUnavailable }
        return try db.transaction {
            try invalidateModelRuns(recordingID: recordingID)
            let epoch = Int64(try db.rows("SELECT audio_epoch FROM recordings WHERE id=?", [.text(recordingID.uuidString)])[0]["audio_epoch"]!)!
            let ticket = RecognitionTicket(id: UUID(), recordingID: recordingID, audioEpoch: epoch)
            try db.execute("UPDATE recordings SET active_attempt=?,recognition_state='running',last_error=NULL WHERE id=?", [.text(ticket.id.uuidString), .text(recordingID.uuidString)])
            try db.execute("INSERT INTO fusion_sessions(id,recording_id,audio_epoch,mode,state,created_at) VALUES(?,?,?,?,'running',?)", [.text(ticket.id.uuidString), .text(recordingID.uuidString), .int(epoch), .text(mode.rawValue), .double(Date().timeIntervalSince1970)])
            return ticket
        }
    }
    public func isRecognitionCurrent(ticket: RecognitionTicket) throws -> Bool { try validTicket(ticket) }
    public func beginModelRun(ticket: RecognitionTicket, configuration: ModelConfiguration) throws -> ModelRunTicket {
        guard try validTicket(ticket), try db.rows("SELECT id FROM fusion_sessions WHERE id=? AND state='running'", [.text(ticket.id.uuidString)]).first != nil else { throw FusionError.staleGeneration }
        let run = ModelRunTicket(recognitionID: ticket.id, recordingID: ticket.recordingID, audioEpoch: ticket.audioEpoch,
            configurationID: configuration.id, provider: configuration.provider.rawValue, model: configuration.model, purpose: configuration.purpose)
        try db.transaction {
            try db.execute("UPDATE model_runs SET state='cancelled' WHERE recognition_id=? AND configuration_id=? AND state='running'", [.text(ticket.id.uuidString), .text(configuration.id.uuidString)])
            try db.execute("INSERT INTO model_runs(id,recognition_id,recording_id,audio_epoch,configuration_id,payload,state,last_sequence,retryable,created_at) VALUES(?,?,?,?,?,?,'running',-1,1,?)",
                [.text(run.id.uuidString), .text(ticket.id.uuidString), .text(ticket.recordingID.uuidString), .int(ticket.audioEpoch), .text(configuration.id.uuidString), .text(try Self.encodeEvidence(run)), .double(Date().timeIntervalSince1970)])
        }
        return run
    }
    @discardableResult public func appendRecognitionCandidate(_ candidate: RecognitionCandidate) throws -> Bool {
        try PrecisionFusion.validateCandidate(candidate)
        return try db.transaction {
            let run = candidate.run
            guard try validRun(run), let previous = try db.rows("SELECT last_sequence FROM model_runs WHERE id=?", [.text(run.id.uuidString)]).first,
                  candidate.sequence > (Int64(previous["last_sequence"] ?? "-1") ?? -1),
                  try db.rows("SELECT id FROM recognition_candidates WHERE id=?", [.text(candidate.id.uuidString)]).isEmpty else { return false }
            try db.execute("INSERT INTO recognition_candidates(id,run_id,recognition_id,recording_id,sequence,payload,created_at) VALUES(?,?,?,?,?,?,?)",
                [.text(candidate.id.uuidString), .text(run.id.uuidString), .text(run.recognitionID.uuidString), .text(run.recordingID.uuidString), .int(candidate.sequence), .text(try Self.encodeEvidence(candidate)), .double(candidate.createdAt.timeIntervalSince1970)])
            try db.execute("UPDATE model_runs SET last_sequence=? WHERE id=?", [.int(candidate.sequence), .text(run.id.uuidString)])
            return true
        }
    }
    public func latestRecognitionCandidates(ticket: RecognitionTicket) throws -> [RecognitionCandidate] {
        try db.rows("SELECT c.payload FROM recognition_candidates c JOIN model_runs r ON r.id=c.run_id AND r.last_sequence=c.sequence WHERE c.recognition_id=? AND NOT EXISTS(SELECT 1 FROM recognition_candidates newer JOIN model_runs n ON n.id=newer.run_id WHERE n.recognition_id=r.recognition_id AND n.configuration_id=r.configuration_id AND n.rowid>r.rowid) ORDER BY c.created_at,c.rowid", [.text(ticket.id.uuidString)])
            .map { try Self.decodeEvidence(RecognitionCandidate.self, $0["payload"]) }
    }
    public func recognitionCandidates(recordingID: UUID) throws -> [RecognitionCandidate] {
        _ = try requireRecording(recordingID)
        return try db.rows("SELECT payload FROM recognition_candidates WHERE recording_id=? ORDER BY created_at,rowid", [.text(recordingID.uuidString)])
            .map { try Self.decodeEvidence(RecognitionCandidate.self, $0["payload"]) }
    }
    public func modelRuns(recordingID: UUID) throws -> [ModelRunRecord] {
        _ = try requireRecording(recordingID)
        return try db.rows("SELECT * FROM model_runs WHERE recording_id=? ORDER BY created_at,rowid", [.text(recordingID.uuidString)]).map { row in
            guard let state = row["state"].flatMap(ModelRunState.init(rawValue:)), let sequence = row["last_sequence"].flatMap(Int64.init) else { throw FusionError.invalidCandidate }
            return ModelRunRecord(ticket: try Self.decodeEvidence(ModelRunTicket.self, row["payload"]), state: state, lastSequence: sequence, error: row["last_error"], retryable: row["retryable"] == "1")
        }
    }
    /// One provider failure does not finish/cancel the logical recording or other providers.
    public func finishModelRun(_ run: ModelRunTicket, error: String? = nil, retryable: Bool = true) throws {
        guard try validRun(run) else { return }
        try db.transaction {
            try db.execute("UPDATE model_runs SET state=?,last_error=?,retryable=? WHERE id=?",
                [.text(error == nil ? "completed" : "failed"), error.map { .text(Self.safeModelError($0)) } ?? .null, .int(retryable ? 1 : 0), .text(run.id.uuidString)])
            if error != nil && !retryable {
                try db.execute("INSERT OR REPLACE INTO recognition_retry_blocks(recording_id,reason) VALUES(?,'provider-action-required')", [.text(run.recordingID.uuidString)])
            }
        }
    }
    public func setRecognitionRetryable(ticket: RecognitionTicket, retryable: Bool) throws {
        guard try validTicket(ticket) else { return }
        if retryable { try db.execute("DELETE FROM recognition_retry_blocks WHERE recording_id=?", [.text(ticket.recordingID.uuidString)]) }
        else { try db.execute("INSERT OR REPLACE INTO recognition_retry_blocks(recording_id,reason) VALUES(?,'provider-action-required')", [.text(ticket.recordingID.uuidString)]) }
    }
    /// Explicit user retry/configuration changes can reset a blocked/expired automatic retry budget.
    public func resetRecognitionRetry(recordingID: UUID) throws {
        _ = try requireRecording(recordingID)
        try db.transaction {
            try db.execute("DELETE FROM recognition_retry_blocks WHERE recording_id=?", [.text(recordingID.uuidString)])
            try db.execute("DELETE FROM recovery_attempts WHERE recording_id=?", [.text(recordingID.uuidString)])
        }
    }
    /// The stable publication stream is independent of best-version archives and selected user drafts.
    public func latestDispatchableRevision(recordingID: UUID) throws -> TranscriptRevision? {
        _ = try requireRecording(recordingID)
        return try db.rows("SELECT v.* FROM revisions v WHERE v.recording_id=? AND v.origin='final' AND NOT EXISTS(SELECT 1 FROM fusion_archives a WHERE a.revision_id=v.id) ORDER BY v.created_at DESC,v.rowid DESC LIMIT 1", [.text(recordingID.uuidString)]).first.map(Self.decodeRevision)
    }
    @discardableResult public func publishFusion(ticket: RecognitionTicket, proposal: FusionProposal) throws -> FusionPublication {
        try db.transaction {
            guard try validTicket(ticket), let session = try db.rows("SELECT * FROM fusion_sessions WHERE id=? AND state='running'", [.text(ticket.id.uuidString)]).first else {
                return FusionPublication(revision: nil, published: false, deferred: true)
            }
            let current = try latestRecognitionCandidates(ticket: ticket)
            let sourceIDs = Set(proposal.sourceCandidateIDs)
            let sources = current.filter { sourceIDs.contains($0.id) }
            guard sources.count == sourceIDs.count else { return FusionPublication(revision: nil, published: false, deferred: true) }
            let sessionPrefix = session["stable_text"] ?? ""
            let mode = InputQualityMode(rawValue: session["mode"] ?? "") ?? .highestQuality
            if !proposal.selections.isEmpty {
                if let reviewed = proposal.reviewedCandidateIDs {
                    guard reviewed.count <= 4096 else { throw FusionError.invalidSelection }
                    for id in Set(reviewed) {
                        guard try db.rows("SELECT id FROM recognition_candidates WHERE id=? AND recognition_id=?", [.text(id.uuidString), .text(ticket.id.uuidString)]).first != nil else { throw FusionError.staleGeneration }
                    }
                }
                let horizon = current.filter { $0.run.purpose.isStreaming }.map(PrecisionFusion.reviewRetirementHorizon).min() ?? 0
                let relevant = current.filter { $0.run.purpose.isStreaming || sourceIDs.contains($0.id) || $0.audioEndSeconds + 0.1 >= horizon }
                let checked = try PrecisionFusion.validateSelection(spans: proposal.selections, candidates: relevant,
                    committedPrefix: sessionPrefix, unresolved: proposal.selectionRequestedUnresolved ?? proposal.unresolved,
                    needsAudioReview: proposal.needsAudioReview, reasonCode: proposal.reasonCode)
                guard checked.previewText == proposal.previewText, checked.stableText == proposal.stableText, Set(checked.sourceCandidateIDs) == sourceIDs else { throw FusionError.invalidSelection }
                if mode == .highestQuality && proposal.stableText != sessionPrefix {
                    let required: [RecognitionPurpose] = [.chineseASR, .englishASR]
                    let end = try proposal.selections.map { span -> Double in
                        guard let source = sources.first(where: { $0.id == span.candidateID }) else { throw FusionError.invalidSelection }
                        return try PrecisionFusion.audioInterval(span: span, candidate: source).end
                    }.max() ?? 0
                    guard required.allSatisfy({ purpose in
                        current.contains { $0.run.purpose == purpose && $0.stableUTF16Length > 0 && ($0.isComplete || PrecisionFusion.stableAudioEnd($0) + 0.1 >= end) }
                    }) else { throw FusionError.insufficientAlignment }
                }
            } else if proposal.stableText != sessionPrefix {
                guard !sources.isEmpty, RecognitionUTF16.hasExactPrefix(proposal.stableText, prefix: sessionPrefix),
                      sources.allSatisfy({ RecognitionUTF16.hasExactPrefix($0.stableText, prefix: proposal.stableText) }),
                      mode != .highestQuality || Set(sources.map { $0.run.purpose }).isSuperset(of: [.chineseASR, .englishASR]) else { throw FusionError.invalidSelection }
            }
            // Preview must also be evidence, including when the stable prefix cannot advance.
            guard proposal.previewText.isEmpty || proposal.previewText == sessionPrefix || !proposal.selections.isEmpty || sources.contains(where: { $0.text == proposal.previewText }) else { throw FusionError.invalidSelection }
            let old = try latestDispatchableRevision(recordingID: ticket.recordingID)
            let prior = old?.text ?? ""
            let cursors = try db.rows("SELECT prefix FROM cursors WHERE recording_id=? AND end_utf16>0", [.text(ticket.recordingID.uuidString)]).compactMap { $0["prefix"] }
            let growsSession = RecognitionUTF16.hasExactPrefix(proposal.stableText, prefix: sessionPrefix)
            let requiredPresent = mode == .fast || Set(current.filter { $0.run.purpose.isStreaming }.map { $0.run.purpose }).isSuperset(of: [.chineseASR, .englishASR])
            let completeSources = !sources.isEmpty && sources.allSatisfy(\.isComplete) && requiredPresent
            let previousAttempt = try old.flatMap { revision in
                try db.rows("SELECT attempt FROM revisions WHERE id=?", [.text(revision.id.uuidString)]).first?["attempt"]
            }
            // A new complete generation may correct a never-reserved version. Once any target
            // owns a UTF-16 cursor, that immutable external prefix remains protected.
            let replacesUnsentGeneration = cursors.isEmpty && previousAttempt != ticket.id.uuidString && completeSources
            let growsPublished = RecognitionUTF16.hasExactPrefix(proposal.stableText, prefix: prior) || replacesUnsentGeneration
            let growsCursors = cursors.allSatisfy { RecognitionUTF16.hasExactPrefix(proposal.stableText, prefix: $0) }
            let safe = growsSession && growsPublished && growsCursors
            let shouldPublish = safe && !proposal.stableText.isEmpty && proposal.stableText != prior
            var published: TranscriptRevision?
            if shouldPublish {
                let revision = TranscriptRevision(id: UUID(), recordingID: ticket.recordingID, text: proposal.stableText, origin: .final, createdAt: Date())
                try insertRevision(revision, attempt: ticket.id, base: old?.id)
                try db.execute("INSERT INTO fusion_dispatch_heads(recording_id,revision_id) VALUES(?,?) ON CONFLICT(recording_id) DO UPDATE SET revision_id=excluded.revision_id", [.text(ticket.recordingID.uuidString), .text(revision.id.uuidString)])
                try db.execute("UPDATE fusion_sessions SET stable_text=? WHERE id=?", [.text(proposal.stableText), .text(ticket.id.uuidString)])
                published = revision
                try selectAutomaticRevision(revision)
            }
            // Preserve the best complete alternate without making it eligible for external insertion.
            var archiveID: UUID?
            if !proposal.previewText.isEmpty, proposal.previewText != (published?.text ?? prior) {
                let previous = try db.rows("SELECT v.text,v.origin FROM fusion_archives a JOIN revisions v ON v.id=a.revision_id WHERE a.recording_id=? ORDER BY v.created_at DESC,v.rowid DESC LIMIT 1", [.text(ticket.recordingID.uuidString)]).first
                if previous?["text"] != proposal.previewText || completeSources && previous?["origin"] == "partial" {
                    let archive = TranscriptRevision(id: UUID(), recordingID: ticket.recordingID, text: proposal.previewText,
                        origin: completeSources ? .final : .partial, createdAt: Date())
                    try insertRevision(archive, attempt: ticket.id, base: old?.id)
                    try db.execute("INSERT INTO fusion_archives(revision_id,recording_id,recognition_id) VALUES(?,?,?)", [.text(archive.id.uuidString), .text(ticket.recordingID.uuidString), .text(ticket.id.uuidString)])
                    try selectAutomaticRevision(archive)
                    archiveID = archive.id
                    try pruneFusionPreviews(ticket: ticket, keeping: archive.id)
                }
            }
            let deferred = !safe || proposal.unresolved || proposal.needsAudioReview
            let decision = FusionDecisionRecord(id: UUID(), recognitionID: ticket.id, proposal: proposal,
                revisionID: published?.id ?? archiveID, outcome: shouldPublish ? "published" : deferred ? "deferred" : "unchanged", createdAt: Date())
            try db.execute("INSERT INTO fusion_decisions(id,recognition_id,recording_id,payload,created_at) VALUES(?,?,?,?,?)", [.text(decision.id.uuidString), .text(ticket.id.uuidString), .text(ticket.recordingID.uuidString), .text(try Self.encodeEvidence(decision)), .double(decision.createdAt.timeIntervalSince1970)])
            return FusionPublication(revision: published ?? old, published: shouldPublish, deferred: deferred)
        }
    }
    public func fusionDecisions(recordingID: UUID) throws -> [FusionDecisionRecord] {
        _ = try requireRecording(recordingID)
        return try db.rows("SELECT payload FROM fusion_decisions WHERE recording_id=? ORDER BY created_at,rowid", [.text(recordingID.uuidString)]).map { try Self.decodeEvidence(FusionDecisionRecord.self, $0["payload"]) }
    }
    public func recordModelUsage(_ usage: ModelUsageRecord) throws {
        guard let row = try db.rows("SELECT recording_id FROM model_runs WHERE id=?", [.text(usage.runID.uuidString)]).first,
              usage.audioSeconds.map({ $0.isFinite && $0 >= 0 }) ?? true,
              usage.estimatedCost.map({ $0.isFinite && $0 >= 0 }) ?? true,
              usage.elapsedSeconds.map({ $0.isFinite && $0 >= 0 }) ?? true,
              usage.inputTokens.map({ $0 >= 0 }) ?? true, usage.outputTokens.map({ $0 >= 0 }) ?? true else { throw FusionError.invalidCandidate }
        try db.execute("INSERT OR IGNORE INTO model_usage(id,run_id,recording_id,payload,created_at) VALUES(?,?,?,?,?)", [.text(usage.id.uuidString), .text(usage.runID.uuidString), .text(row["recording_id"]!), .text(try Self.encodeEvidence(usage)), .double(usage.createdAt.timeIntervalSince1970)])
    }
    public func recordModelUsage(run: ModelRunTicket, audioSeconds: Double, inputTokens: Int?, outputTokens: Int?,
                                 elapsedSeconds: Double, requestID: String?, estimatedCost: Double?, currency: String?) throws {
        guard elapsedSeconds.isFinite, elapsedSeconds >= 0 else { throw FusionError.invalidCandidate }
        try recordModelUsage(ModelUsageRecord(runID: run.id, requestID: requestID, audioSeconds: audioSeconds,
            inputTokens: inputTokens, outputTokens: outputTokens, estimatedCost: estimatedCost,
            currency: currency ?? "USD", elapsedSeconds: elapsedSeconds))
    }
    public func modelUsage(recordingID: UUID) throws -> [ModelUsageRecord] {
        _ = try requireRecording(recordingID)
        return try db.rows("SELECT payload FROM model_usage WHERE recording_id=? ORDER BY created_at,rowid", [.text(recordingID.uuidString)]).map { try Self.decodeEvidence(ModelUsageRecord.self, $0["payload"]) }
    }
    public func modelCallSummaries(limit: Int = 30) throws -> [String] {
        try db.rows("SELECT r.payload AS run_payload,r.state,r.last_error,u.payload AS usage_payload FROM model_runs r LEFT JOIN model_usage u ON u.run_id=r.id ORDER BY r.created_at DESC,r.rowid DESC LIMIT ?", [.int(Int64(max(1, min(limit, 500))))]).map { row in
            let run = try Self.decodeEvidence(ModelRunTicket.self, row["run_payload"])
            var summary = "\(run.provider) / \(run.model) · \(run.purpose.rawValue) · \(row["state"] ?? "unknown")"
            if let payload = row["usage_payload"] {
                let usage = try Self.decodeEvidence(ModelUsageRecord.self, payload)
                if let seconds = usage.audioSeconds { summary += String(format: " · %.1fs", seconds) }
                if let input = usage.inputTokens { summary += " · in \(input)" }
                if let output = usage.outputTokens { summary += " · out \(output)" }
                if let cost = usage.estimatedCost { summary += String(format: " · ≈ %.6f %@", cost, usage.currency) }
                else { summary += " · 费用未报告" }
            }
            if let error = row["last_error"] { summary += " · " + error }
            return summary
        }
    }
    private func validRun(_ run: ModelRunTicket) throws -> Bool {
        let ticket = RecognitionTicket(id: run.recognitionID, recordingID: run.recordingID, audioEpoch: run.audioEpoch)
        guard try validTicket(ticket), let row = try db.rows("SELECT payload FROM model_runs WHERE id=? AND recognition_id=? AND state='running'", [.text(run.id.uuidString), .text(run.recognitionID.uuidString)]).first else { return false }
        return try Self.decodeEvidence(ModelRunTicket.self, row["payload"]) == run
    }
    private func invalidateModelRuns(recordingID: UUID, sessionState: String = "cancelled") throws {
        try db.execute("UPDATE model_runs SET state='cancelled' WHERE recording_id=? AND state='running'", [.text(recordingID.uuidString)])
        try db.execute("UPDATE fusion_sessions SET state=? WHERE recording_id=? AND state='running'", [.text(sessionState), .text(recordingID.uuidString)])
    }
    private func pruneFusionPreviews(ticket: RecognitionTicket, keeping id: UUID) throws {
        let disposable = "recording_id=? AND origin='partial' AND attempt=? AND id<>? AND NOT EXISTS(SELECT 1 FROM dispatches d WHERE d.revision_id=revisions.id) AND NOT EXISTS(SELECT 1 FROM recordings r WHERE r.preferred_revision=revisions.id) AND NOT EXISTS(SELECT 1 FROM revisions base WHERE base.base_revision=revisions.id) AND NOT EXISTS(SELECT 1 FROM frozen_revisions frozen WHERE frozen.revision_id=revisions.id)"
        let values: [StoreDatabase.Value] = [.text(ticket.recordingID.uuidString), .text(ticket.id.uuidString), .text(id.uuidString)]
        try db.execute("DELETE FROM fusion_archives WHERE revision_id IN(SELECT id FROM revisions WHERE " + disposable + ")", values)
        try db.execute("DELETE FROM revisions WHERE " + disposable, values)
    }
    private func selectAutomaticRevision(_ revision: TranscriptRevision) throws {
        try db.execute("UPDATE recordings SET preferred_revision=? WHERE id=? AND NOT EXISTS(SELECT 1 FROM revisions WHERE id=recordings.preferred_revision AND origin='userEdit') AND NOT EXISTS(SELECT 1 FROM editing_drafts WHERE recording_id=recordings.id)", [.text(revision.id.uuidString), .text(revision.recordingID.uuidString)])
    }
    private static func safeModelError(_ message: String) -> String {
        let lower = message.lowercased()
        if lower.contains("auth") || lower.contains("401") || lower.contains("403") || message.contains("授权") { return "provider-authorization" }
        if lower.contains("quota") || lower.contains("429") || lower.contains("402") || message.contains("额度") { return "provider-quota" }
        if lower.contains("config") || message.contains("配置") { return "provider-configuration" }
        if lower.contains("cancel") || message.contains("取消") { return "provider-cancelled" }
        return "provider-failure"
    }
    private static func encodeEvidence<T: Encodable>(_ value: T) throws -> String {
        let data = try JSONEncoder().encode(value)
        guard let string = String(data: data, encoding: .utf8) else { throw FusionError.invalidCandidate }
        return string
    }
    private static func decodeEvidence<T: Decodable>(_ type: T.Type, _ string: String?) throws -> T {
        guard let data = string?.data(using: .utf8) else { throw FusionError.invalidCandidate }
        return try JSONDecoder().decode(type, from: data)
    }
}
