import Foundation
import Testing
@testable import SaytileKit

private struct Fixture {
    let directory: URL
    let store: SaytileStore
    init() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("saytile-store-test-" + UUID().uuidString)
        store = try SaytileStore(directory:directory)
    }
    func clean() { try? FileManager.default.removeItem(at:directory) }
    func record(text: String = "你好，世界", date: Date = Date()) async throws -> Recording {
        let recording = try await store.createRecording(createdAt:date)
        let path = recording.id.uuidString + "/chunk.wav"
        let file = store.audioDirectory.appendingPathComponent(path)
        try FileManager.default.createDirectory(at:file.deletingLastPathComponent(),withIntermediateDirectories:true)
        try Data(repeating:0,count:32044).write(to:file)
        try await store.registerAudioChunk(recordingID:recording.id,relativePath:path,frames:16000)
        let ticket = try await store.beginRecognition(recordingID:recording.id)
        try await store.applyRecognition(ticket:ticket,text:text,isFinal:true)
        try await store.finishRecognition(ticket:ticket)
        try await store.finishRecording(id:recording.id)
        return try await store.recording(id:recording.id)!
    }
}

@Test func storePersistsAcrossReopen() async throws {
    let f = try Fixture(); defer { f.clean() }
    let r = try await f.record()
    let reopened = try SaytileStore(directory:f.directory)
    let loaded = try await reopened.recording(id:r.id)
    #expect(loaded?.text == "你好，世界")
    #expect(loaded?.duration == 1)
    #expect(loaded?.recognitionState == .completed)
}
@Test func storeAudioDeletionPreservesEveryTextRevision() async throws {
    let f = try Fixture(); defer { f.clean() }
    let r = try await f.record()
    try await f.store.saveEdit(recordingID:r.id,text:"用户修改")
    let before = try await f.store.revisions(recordingID:r.id)
    try await f.store.deleteAudio(recordingID:r.id)
    let after = try await f.store.revisions(recordingID:r.id)
    let record = try await f.store.recording(id:r.id)
    #expect(before == after)
    #expect(record?.text == "用户修改")
    #expect(record?.audioState == .deleted)
    #expect(record?.duration == 1)
    #expect(!FileManager.default.fileExists(atPath:f.store.audioDirectory.appendingPathComponent(r.id.uuidString).path))
    #expect(try await f.store.listRecordings(query:"你好").count == 1)
}
@Test func storeLateRecognitionCannotResurrectDeletedAudio() async throws {
    let f = try Fixture(); defer { f.clean() }
    let r = try await f.record()
    let ticket = try await f.store.beginRecognition(recordingID:r.id)
    try await f.store.deleteAudio(recordingID:r.id)
    #expect(try await !f.store.applyRecognition(ticket:ticket,text:"迟到",isFinal:true))
    #expect(try await f.store.recording(id:r.id)?.text == r.text)
}
@Test func storeNewAttemptRejectsOldCallback() async throws {
    let f = try Fixture(); defer { f.clean() }
    let r = try await f.record()
    let first = try await f.store.beginRecognition(recordingID:r.id)
    let second = try await f.store.beginRecognition(recordingID:r.id)
    #expect(try await !f.store.applyRecognition(ticket:first,text:"旧回调",isFinal:true))
    #expect(try await f.store.applyRecognition(ticket:second,text:"新回调",isFinal:true))
}
@Test func storePartialDraftCountIsBoundedAndFinalImmutable() async throws {
    let f = try Fixture(); defer { f.clean() }
    let r = try await f.store.createRecording()
    let ticket = try await f.store.beginRecognition(recordingID:r.id)
    for index in 0..<100 { try await f.store.applyRecognition(ticket:ticket,text:"部分 \(index)",isFinal:false) }
    #expect(try await f.store.revisions(recordingID:r.id).count == 1)
    try await f.store.applyRecognition(ticket:ticket,text:"最终",isFinal:true)
    #expect(try await f.store.revisions(recordingID:r.id).count == 1)
    try await f.store.finishRecognition(ticket:ticket)
    #expect(try await !f.store.applyRecognition(ticket:ticket,text:"不再接受",isFinal:true))
}
@Test func storeRecognitionPreservesSelectedUserEdit() async throws {
    let f = try Fixture(); defer { f.clean() }
    let r = try await f.record()
    try await f.store.saveEdit(recordingID:r.id,text:"修改稿")
    let ticket = try await f.store.beginRecognition(recordingID:r.id)
    try await f.store.applyRecognition(ticket:ticket,text:"重识别",isFinal:true)
    #expect(try await f.store.recording(id:r.id)?.text == "修改稿")
    let revisions = try await f.store.revisions(recordingID:r.id)
    #expect(revisions.count == 3)
    try await f.store.selectRevision(recordingID:r.id,revisionID:revisions.first!.id)
    #expect(try await f.store.recording(id:r.id)?.text == "重识别")
}
@Test func storeSearchEscapesLikeAndBindsSQL() async throws {
    let f = try Fixture(); defer { f.clean() }
    _ = try await f.record(text:"100% _ ' OR 1=1 --")
    _ = try await f.record(text:"普通文字")
    #expect(try await f.store.listRecordings(query:"%").count == 1)
    #expect(try await f.store.listRecordings(query:"_").count == 1)
    #expect(try await f.store.listRecordings(query:"' OR 1=1 --").count == 1)
    #expect(try await f.store.listRecordings(query:"不存在").isEmpty)
}
@Test func storeAudioLeaseDefersPhysicalErasure() async throws {
    let f = try Fixture(); defer { f.clean() }
    let r = try await f.record()
    let lease = try await f.store.acquireAudioLease(recordingID:r.id)
    try await f.store.deleteAudio(recordingID:r.id)
    #expect(try await f.store.recording(id:r.id)?.audioState == .deletePending)
    #expect(FileManager.default.fileExists(atPath:f.store.audioDirectory.appendingPathComponent(r.id.uuidString).path))
    #expect(try await f.store.audioChunks(recordingID:r.id).isEmpty)
    try await f.store.releaseAudioLease(lease)
    #expect(try await f.store.recording(id:r.id)?.audioState == .deleted)
}
@Test func storePendingErasureResumesAfterCrash() async throws {
    let f = try Fixture(); defer { f.clean() }
    let r = try await f.record()
    _ = try await f.store.acquireAudioLease(recordingID:r.id)
    try await f.store.deleteAudio(recordingID:r.id)
    let recovered = try SaytileStore(directory:f.directory)
    try await recovered.recoverPendingDeletions()
    #expect(try await recovered.recording(id:r.id)?.audioState == .deleted)
    #expect(try await recovered.recording(id:r.id)?.text == r.text)
}
@Test func storeDeletionRemovesUnregisteredCrashTail() async throws {
    let f = try Fixture(); defer { f.clean() }
    let r = try await f.record()
    let orphan = f.store.audioDirectory.appendingPathComponent(r.id.uuidString + "/orphan.part")
    try Data([0,1,2]).write(to:orphan)
    try await f.store.deleteAudio(recordingID:r.id)
    #expect(!FileManager.default.fileExists(atPath:orphan.path))
}
@Test func storeRecordDeletionRemovesTextAndSearch() async throws {
    let f = try Fixture(); defer { f.clean() }
    let r = try await f.record()
    try await f.store.saveEdit(recordingID:r.id,text:"修改稿")
    try await f.store.deleteRecord(recordingID:r.id)
    #expect(try await f.store.recording(id:r.id) == nil)
    #expect(try await f.store.listRecordings().isEmpty)
}
@Test func storeLiveDeletionIsRejected() async throws {
    let f = try Fixture(); defer { f.clean() }
    let r = try await f.store.createRecording()
    await #expect(throws:StoreError.self) { try await f.store.deleteAudio(recordingID:r.id) }
    #expect(try await f.store.recording(id:r.id)?.audioState == .available)
}
@Test func storeChunkUpdatesAreMonotonic() async throws {
    let f = try Fixture(); defer { f.clean() }
    let r = try await f.record()
    let chunks = try await f.store.audioChunks(recordingID:r.id)
    try await f.store.registerAudioChunk(recordingID:r.id,relativePath:chunks[0].relativePath,frames:32000)
    #expect(try await f.store.audioChunks(recordingID:r.id).count == 1)
    #expect(try await f.store.recording(id:r.id)?.duration == 2)
    await #expect(throws:StoreError.self) { try await f.store.registerAudioChunk(recordingID:r.id,relativePath:chunks[0].relativePath,frames:100) }
}
@Test func storeRejectsTraversalAndOtherRecordingOwnership() async throws {
    let f = try Fixture(); defer { f.clean() }
    let r = try await f.record()
    for path in ["../outside.wav","/tmp/outside.wav",UUID().uuidString + "/chunk.wav",r.id.uuidString + "/../outside.wav"] {
        await #expect(throws:StoreError.self) { try await f.store.registerAudioChunk(recordingID:r.id,relativePath:path,frames:10) }
    }
}
@Test func storeRejectsSymlinkEscape() async throws {
    let f = try Fixture(); defer { f.clean() }
    let r = try await f.store.createRecording()
    try FileManager.default.createSymbolicLink(at:f.store.audioDirectory.appendingPathComponent(r.id.uuidString),withDestinationURL:f.directory)
    await #expect(throws:StoreError.self) { try await f.store.registerAudioChunk(recordingID:r.id,relativePath:r.id.uuidString + "/escape.wav",frames:1) }
}
@Test func storeCleanupProtectsPinnedFailedAndActive() async throws {
    let f = try Fixture(); defer { f.clean() }
    let date = Date(timeIntervalSince1970:1)
    let good = try await f.record(date:date)
    let pinned = try await f.record(date:date)
    try await f.store.setPinned(recordingID:pinned.id,pinned:true)
    let failed = try await f.record(date:date)
    let ticket = try await f.store.beginRecognition(recordingID:failed.id)
    try await f.store.failRecognition(ticket:ticket,message:"测试故障")
    _ = try await f.store.createRecording(createdAt:date)
    let candidates = try await f.store.cleanupCandidates(olderThan:Date())
    #expect(candidates.map(\.id) == [good.id])
}
@Test func storeInterruptedCaptureAndASRRecover() async throws {
    let f = try Fixture(); defer { f.clean() }
    let r = try await f.store.createRecording()
    let ticket = try await f.store.beginRecognition(recordingID:r.id)
    let reopened = try SaytileStore(directory:f.directory)
    #expect(reopened.recovery.interruptedRecordings == 1)
    #expect(reopened.recovery.interruptedRecognitions == 1)
    #expect(try await reopened.recording(id:r.id)?.isRecording == false)
    #expect(try await reopened.recording(id:r.id)?.recognitionState == .queued)
    #expect(try await !reopened.applyRecognition(ticket:ticket,text:"旧进程",isFinal:true))
}
@Test func storeStorageSummaryUsesActualFiles() async throws {
    let f = try Fixture(); defer { f.clean() }
    _ = try await f.record()
    let summary = try await f.store.storageSummary()
    #expect(summary.audioBytes == 32044)
    #expect(summary.recordingCount == 1)
    #expect(summary.availableDiskBytes > 0)
}
@Test func storePreservesEmbeddedNULInEditedText() async throws {
    let f = try Fixture(); defer { f.clean() }
    let r = try await f.record()
    try await f.store.saveEdit(recordingID:r.id,text:"前\u{0}后")
    #expect(try await f.store.recording(id:r.id)?.text == "前\u{0}后")
}
@Test func storeCompletedTombstoneCleansResidualFilesOnRecovery() async throws {
    let f = try Fixture(); defer { f.clean() }
    let r = try await f.record()
    try await f.store.deleteAudio(recordingID:r.id)
    let residual = f.store.audioDirectory.appendingPathComponent(r.id.uuidString + "/resurrected.wav")
    try FileManager.default.createDirectory(at:residual.deletingLastPathComponent(),withIntermediateDirectories:true)
    try Data([0,1,2,3]).write(to:residual)
    let reopened = try SaytileStore(directory:f.directory)
    try await reopened.recoverPendingDeletions()
    #expect(!FileManager.default.fileExists(atPath:residual.path))
    #expect(try await reopened.recording(id:r.id)?.text == r.text)
}
@Test func storeMultipleFinalRangesCompleteOnlyAfterDrain() async throws {
    let f = try Fixture(); defer { f.clean() }
    let r = try await f.store.createRecording()
    let ticket = try await f.store.beginRecognition(recordingID:r.id)
    #expect(try await f.store.applyRecognition(ticket:ticket,text:"你好",isFinal:true))
    #expect(try await f.store.applyRecognition(ticket:ticket,text:"你好，世界",isFinal:true))
    #expect(try await f.store.recording(id:r.id)?.recognitionState == .running)
    try await f.store.finishRecognition(ticket:ticket)
    #expect(try await f.store.recording(id:r.id)?.recognitionState == .completed)
    #expect(try await f.store.revisions(recordingID:r.id).count == 2)
}
@Test func storeFiltersBeforePagination() async throws {
    let f = try Fixture(); defer { f.clean() }
    let old = try await f.record(date:Date(timeIntervalSince1970:1))
    try await f.store.setPinned(recordingID:old.id,pinned:true)
    _ = try await f.record()
    let filtered = try await f.store.listRecordings(limit:1,filter:.pinned)
    #expect(filtered.first?.id == old.id)
}
@Test func storeCleanupRevalidatesPreview() async throws {
    let f = try Fixture(); defer { f.clean() }
    let r = try await f.record(date:Date(timeIntervalSince1970:1))
    let preview = try await f.store.cleanupCandidates(olderThan:Date())
    #expect(preview.count == 1)
    try await f.store.setPinned(recordingID:r.id,pinned:true)
    #expect(try await f.store.cleanupAudio(recordingIDs:preview.map(\.id),olderThan:Date()) == 0)
    #expect(try await f.store.recording(id:r.id)?.audioState == .available)
}
@Test func storeLatestStableRevisionSurvivesVolatileUpdate() async throws {
    let f = try Fixture(); defer { f.clean() }
    let r = try await f.store.createRecording()
    let ticket = try await f.store.beginRecognition(recordingID:r.id)
    try await f.store.applyRecognition(ticket:ticket,text:"稳定部分",isFinal:true)
    try await f.store.applyRecognition(ticket:ticket,text:"稳定部分和草稿",isFinal:false)
    #expect(try await f.store.latestFinalRevision(recordingID:r.id)?.text == "稳定部分")
    #expect(try await f.store.recording(id:r.id)?.text == "稳定部分和草稿")
}
@Test func storeRecoveryReconcilesTruncatedDurableAudio() async throws {
    let f = try Fixture(); defer { f.clean() }
    let r = try await f.record()
    let chunk = try await f.store.audioChunks(recordingID:r.id)[0]
    try await f.store.reconcileAudioChunk(recordingID:r.id,path:chunk.relativePath,actualFrames:8000)
    #expect(try await f.store.recording(id:r.id)?.duration == 0.5)
    #expect(try await f.store.recording(id:r.id)?.lastError != nil)
    #expect(try await f.store.recording(id:r.id)?.text == r.text)
}
@Test func storeMissingAudioStatePreservesTextAndRejectsStaleASR() async throws {
    let f = try Fixture(); defer { f.clean() }
    let r = try await f.record()
    let ticket = try await f.store.beginRecognition(recordingID:r.id)
    try await f.store.markAudioMissing(recordingID:r.id,message:"文件缺失")
    #expect(try await f.store.recording(id:r.id)?.audioState == .missing)
    #expect(try await f.store.recording(id:r.id)?.text == r.text)
    #expect(try await !f.store.applyRecognition(ticket:ticket,text:"迟到回调",isFinal:true))
    try await f.store.deleteAudio(recordingID:r.id)
    #expect(try await f.store.recording(id:r.id)?.audioState == .deleted)
}
