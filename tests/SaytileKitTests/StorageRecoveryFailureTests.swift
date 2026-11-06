import Foundation
import Testing
@testable import SaytileKit

@Suite("Storage failure state remains recoverable")
struct StorageRecoveryFailureTests {
    @Test(arguments: [false, true]) func recordingAndRunTerminalChangesRollbackTogether(markMissing: Bool) async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("saytile-state-rollback-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try SaytileStore(directory: root)
        let record = try await store.createRecording()
        try await store.finishRecording(id: record.id)
        let ticket = try await store.beginFusionRecognition(recordingID: record.id)
        let config = ModelConfiguration(purpose: .englishASR, provider: .assemblyAI, model: "fixture")
        let run = try await store.beginModelRun(ticket: ticket, configuration: config)
        let fault = try StoreDatabase(url: root.appendingPathComponent("Saytile.sqlite"))
        try fault.script("CREATE TRIGGER reject_record_failure BEFORE UPDATE ON recordings BEGIN SELECT RAISE(ABORT,'synthetic write interruption'); END;")
        do {
            if markMissing { try await store.markAudioMissing(recordingID: record.id, message: "synthetic failure") }
            else { try await store.recordCaptureFailure(recordingID: record.id, message: "synthetic failure") }
            Issue.record("record update should fail at the injected SQLite boundary")
        } catch { }
        #expect(try fault.rows("SELECT state FROM model_runs WHERE id=?", [.text(run.id.uuidString)]).first?["state"] == "running")
        #expect(try fault.rows("SELECT state FROM fusion_sessions WHERE id=?", [.text(ticket.id.uuidString)]).first?["state"] == "running")
        #expect(try await store.fusionTerminal(recognitionID: ticket.id) == nil)
        #expect(try await store.recording(id: record.id)?.recognitionState == .running)
        try fault.script("DROP TRIGGER reject_record_failure")
        if markMissing { try await store.markAudioMissing(recordingID: record.id, message: "synthetic failure") }
        else { try await store.recordCaptureFailure(recordingID: record.id, message: "synthetic failure") }
        #expect(try await store.recording(id: record.id)?.recognitionState == .failed)
        #expect(try fault.rows("SELECT state FROM model_runs WHERE id=?", [.text(run.id.uuidString)]).first?["state"] == "cancelled")
        try fault.close(); try await store.close()
    }

    @Test func transientHeaderRepairFailureDoesNotPermanentlyDiscardReadableOriginal() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("saytile-repair-retry-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try SaytileStore(directory: root)
        let record = try await store.createRecording()
        let journal = try PCMJournal(directory: store.audioDirectory, recordingID: record.id)
        try journal.openChunk()
        try await store.registerAudioChunk(recordingID: record.id, relativePath: journal.relativePath, frames: 0)
        try journal.append(Data(repeating: 0x12, count: 640))
        // Simulate a process exit before the next header checkpoint.
        journal.abandonOpenHandle()
        let url = store.audioDirectory.appendingPathComponent(journal.relativePath)
        try await store.finishRecording(id: record.id)
        let before = try Data(contentsOf: url)
        try FileManager.default.setAttributes([.posixPermissions: 0o400], ofItemAtPath: url.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path) }
        _ = try await AudioDiagnostics.recoverAudio(store: store)
        #expect(try Data(contentsOf: url) == before)
        #expect(try await store.recording(id: record.id)?.audioState == .available)
        try await store.close()
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        let reopened = try SaytileStore(directory: root)
        #expect(try await AudioDiagnostics.recoverAudio(store: reopened) == 1)
        #expect(try await reopened.audioChunks(recordingID: record.id).first?.frames == 320)
        #expect(try await AudioDiagnostics.recoverAudio(store: reopened) == 0)
        try await reopened.close()
    }

    @Test func interruptedIndexUpdateKeepsOriginalAndRetriesAfterReopen() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("saytile-repair-sql-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try SaytileStore(directory: root)
        let record = try await store.createRecording()
        let journal = try PCMJournal(directory: store.audioDirectory, recordingID: record.id)
        try journal.openChunk()
        try await store.registerAudioChunk(recordingID: record.id, relativePath: journal.relativePath, frames: 0)
        let samples = Data(repeating: 0x34, count: 640)
        try journal.append(samples); try journal.closeChunk()
        try await store.finishRecording(id: record.id)
        _ = try await store.saveEdit(recordingID: record.id, text: "保留用户修改稿")
        let url = store.audioDirectory.appendingPathComponent(journal.relativePath)
        let original = try Data(contentsOf: url)
        let fault = try StoreDatabase(url: root.appendingPathComponent("Saytile.sqlite"))
        let originalEpoch = try fault.rows("SELECT audio_epoch FROM recordings WHERE id=?", [.text(record.id.uuidString)]).first?["audio_epoch"]
        try fault.script("CREATE TRIGGER reject_chunk_repair BEFORE UPDATE ON chunks BEGIN SELECT RAISE(ABORT,'synthetic index write interruption'); END;")
        #expect(try await AudioDiagnostics.recoverAudio(store: store) == 0)
        let pending = try #require(try await store.recording(id: record.id))
        #expect(pending.audioState == .available)
        #expect(try fault.rows("SELECT audio_epoch FROM recordings WHERE id=?", [.text(record.id.uuidString)]).first?["audio_epoch"] == originalEpoch)
        #expect(pending.text == "保留用户修改稿")
        #expect(try Data(contentsOf: url) == original)
        #expect(try await store.audioChunks(recordingID: record.id).first?.frames == 0)
        try fault.script("DROP TRIGGER reject_chunk_repair")
        try fault.close(); try await store.close()
        let reopened = try SaytileStore(directory: root)
        #expect(try await AudioDiagnostics.recoverAudio(store: reopened) == 1)
        #expect(try await reopened.audioChunks(recordingID: record.id).first?.frames == 320)
        #expect(try await reopened.recording(id: record.id)?.text == "保留用户修改稿")
        #expect(try await AudioDiagnostics.recoverAudio(store: reopened) == 0)
        #expect(try Data(contentsOf: url) == original)
        try await reopened.close()
    }

    @Test func inaccessibleRecordingDirectoryDoesNotBlockIndependentRecovery() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("saytile-repair-directory-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try SaytileStore(directory: root)
        func makeRecord(at timestamp: Double) async throws -> (Recording, URL) {
            let record = try await store.createRecording(createdAt: Date(timeIntervalSince1970: timestamp))
            let journal = try PCMJournal(directory: store.audioDirectory, recordingID: record.id)
            try journal.openChunk()
            try await store.registerAudioChunk(recordingID: record.id, relativePath: journal.relativePath, frames: 0)
            try journal.append(Data(repeating: 0x56, count: 640)); try journal.closeChunk()
            try await store.finishRecording(id: record.id)
            return (record, store.audioDirectory.appendingPathComponent(journal.relativePath))
        }
        let (healthy, _) = try await makeRecord(at: 1)
        let (blocked, url) = try await makeRecord(at: 2)
        _ = try await store.saveEdit(recordingID: blocked.id, text: "受保护的修改稿")
        let before = try Data(contentsOf: url)
        let blockedDirectory = url.deletingLastPathComponent()
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: blockedDirectory.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: blockedDirectory.path) }
        // The inaccessible newest record is examined before the healthy older one.
        #expect(try await store.listRecordings().first?.id == blocked.id)
        #expect(try await AudioDiagnostics.recoverAudio(store: store) == 1)
        #expect(try await store.audioChunks(recordingID: healthy.id).first?.frames == 320)
        #expect(try await store.recording(id: blocked.id)?.audioState == .available)
        #expect(try await store.recording(id: blocked.id)?.text == "受保护的修改稿")
        #expect(try await store.recording(id: blocked.id)?.lastError?.contains("原音恢复暂未完成") == true)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: blockedDirectory.path)
        #expect(try Data(contentsOf: url) == before)
        try await store.close()
        let reopened = try SaytileStore(directory: root)
        #expect(try await AudioDiagnostics.recoverAudio(store: reopened) == 1)
        #expect(try await reopened.audioChunks(recordingID: blocked.id).first?.frames == 320)
        #expect(try await AudioDiagnostics.recoverAudio(store: reopened) == 0)
        #expect(try Data(contentsOf: url) == before)
        try await reopened.close()
    }

    @Test func inaccessiblePendingDeletionDoesNotBlockStartupOrIndependentRecords() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("saytile-erasure-isolation-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try SaytileStore(directory: root)
        let (blocked, blockedURL) = try await makeDeletionFixture(store: store)
        let (deletable, _) = try await makeDeletionFixture(store: store)
        let (healthy, _) = try await makeDeletionFixture(store: store)
        let previousAttempt = try await store.beginRecognition(recordingID: deletable.id)
        try await store.failRecognition(ticket: previousAttempt, message: "先前识别失败")
        _ = try await store.saveEdit(recordingID: blocked.id, text: "删除原音仍保留修改稿")
        // Persist deletion intents while leases defer physical removal, then close
        // the process owner before startup to simulate an interrupted deletion.
        _ = try await store.acquireAudioLease(recordingID: blocked.id)
        _ = try await store.acquireAudioLease(recordingID: deletable.id)
        try await store.deleteAudio(recordingID: blocked.id)
        try await store.deleteAudio(recordingID: deletable.id)
        let original = try Data(contentsOf: blockedURL)
        let blockedDirectory = blockedURL.deletingLastPathComponent()
        try await store.close()
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: blockedDirectory.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: blockedDirectory.path) }
        let reopened = try SaytileStore(directory: root)
        // This is the same awaited recovery boundary used to authorize AppModel startup.
        #expect(try await AudioDiagnostics.recoverAudio(store: reopened) == 1)
        let pending = try #require(try await reopened.recording(id: blocked.id))
        #expect(pending.audioState == .deletePending)
        #expect(pending.text == "删除原音仍保留修改稿")
        #expect(pending.lastError?.contains("原音删除暂未完成") == true)
        #expect(try await reopened.audioChunks(recordingID: blocked.id).isEmpty)
        await #expect(throws: StoreError.self) { try await reopened.beginRecognition(recordingID: blocked.id) }
        await #expect(throws: StoreError.self) { try await reopened.acquireAudioLease(recordingID: blocked.id) }
        #expect(try await reopened.pendingRecordings().allSatisfy { $0.id != blocked.id })
        #expect(try await reopened.recording(id: deletable.id)?.audioState == .deleted)
        #expect(try await reopened.recording(id: deletable.id)?.lastError == "先前识别失败")
        #expect(try await reopened.audioChunks(recordingID: healthy.id).first?.frames == 320)
        let audit = try StoreDatabase(url: root.appendingPathComponent("Saytile.sqlite"))
        #expect(try audit.rows("SELECT completed FROM erasures WHERE recording_id=?", [.text(blocked.id.uuidString)]).first?["completed"] == "0")
        try audit.close()
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: blockedDirectory.path)
        #expect(try Data(contentsOf: blockedURL) == original)
        try await reopened.close()
        let retried = try SaytileStore(directory: root)
        #expect(try await AudioDiagnostics.recoverAudio(store: retried) == 0)
        #expect(try await retried.recording(id: blocked.id)?.audioState == .deleted)
        #expect(try await retried.recording(id: blocked.id)?.lastError == nil)
        #expect(try await retried.recording(id: blocked.id)?.text == "删除原音仍保留修改稿")
        #expect(!FileManager.default.fileExists(atPath: blockedDirectory.path))
        #expect(try await AudioDiagnostics.recoverAudio(store: retried) == 0)
        try await retried.close()
    }

    @Test func pendingDeletionDatabaseFailureStillStopsStartupAndCanRetry() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("saytile-erasure-sql-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try SaytileStore(directory: root)
        let (record, _) = try await makeDeletionFixture(store: store)
        _ = try await store.acquireAudioLease(recordingID: record.id)
        try await store.deleteAudio(recordingID: record.id)
        try await store.close()
        let reopened = try SaytileStore(directory: root)
        let fault = try StoreDatabase(url: root.appendingPathComponent("Saytile.sqlite"))
        try fault.script("CREATE TRIGGER reject_erasure_completion BEFORE UPDATE ON erasures BEGIN SELECT RAISE(ABORT,'synthetic deletion database interruption'); END;")
        await #expect(throws: StoreError.self) { try await AudioDiagnostics.recoverAudio(store: reopened) }
        #expect(try await reopened.recording(id: record.id)?.audioState == .deletePending)
        #expect(try fault.rows("SELECT completed FROM erasures WHERE recording_id=?", [.text(record.id.uuidString)]).first?["completed"] == "0")
        try fault.script("DROP TRIGGER reject_erasure_completion")
        try fault.close(); try await reopened.close()
        let retried = try SaytileStore(directory: root)
        #expect(try await AudioDiagnostics.recoverAudio(store: retried) == 0)
        #expect(try await retried.recording(id: record.id)?.audioState == .deleted)
        try await retried.close()
    }

    @Test(arguments: [false, true])
    func inaccessibleAudioParentNeverCertifiesPendingOrResidualErasure(completed: Bool) async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("saytile-erasure-parent-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try SaytileStore(directory: root)
        let (record, url) = try await makeDeletionFixture(store: store)
        let original = try Data(contentsOf: url)
        if !completed { _ = try await store.acquireAudioLease(recordingID: record.id) }
        try await store.deleteAudio(recordingID: record.id)
        if completed {
            // A completed tombstone must also clean an owned residual after a crash.
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try original.write(to: url)
        }
        try await store.close()
        let reopened = try SaytileStore(directory: root)
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: reopened.audioDirectory.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: reopened.audioDirectory.path) }
        #expect(try await AudioDiagnostics.recoverAudio(store: reopened) == 0)
        #expect(try await reopened.recording(id: record.id)?.audioState == .deletePending)
        let audit = try StoreDatabase(url: root.appendingPathComponent("Saytile.sqlite"))
        #expect(try audit.rows("SELECT completed FROM erasures WHERE recording_id=?", [.text(record.id.uuidString)]).first?["completed"] == "0")
        try audit.close()
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: reopened.audioDirectory.path)
        #expect(try Data(contentsOf: url) == original)
        try await reopened.close()
        let retried = try SaytileStore(directory: root)
        #expect(try await AudioDiagnostics.recoverAudio(store: retried) == 0)
        #expect(try await retried.recording(id: record.id)?.audioState == .deleted)
        #expect(!FileManager.default.fileExists(atPath: url.path))
        try await retried.close()
    }

    private func makeDeletionFixture(store: SaytileStore) async throws -> (Recording, URL) {
        let record = try await store.createRecording()
        let journal = try PCMJournal(directory: store.audioDirectory, recordingID: record.id)
        try journal.openChunk()
        try await store.registerAudioChunk(recordingID: record.id, relativePath: journal.relativePath, frames: 0)
        try journal.append(Data(repeating: 0x78, count: 640)); try journal.closeChunk()
        try await store.finishRecording(id: record.id)
        return (record, store.audioDirectory.appendingPathComponent(journal.relativePath))
    }

    @Test func intactReadOnlyAudioNeedsNoRepairWritePermission() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("saytile-readonly-wav-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("synthetic.wav")
        let original = PCMJournal.header(frames: 320) + Data(repeating: 0, count: 640)
        try original.write(to: url)
        try FileManager.default.setAttributes([.posixPermissions: 0o400], ofItemAtPath: url.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path) }
        #expect(try PCMJournal.repair(url) == 320)
        #expect(try Data(contentsOf: url) == original)
    }
}
