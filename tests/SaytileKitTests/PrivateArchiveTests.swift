import Foundation
import Testing
import AVFoundation
@testable import SaytileKit

private actor IsolatedArchiveTransport: PrivateArchiveTransport {
    private var records: [UUID: PrivateArchive] = [:]
    private var log: [UUID] = []
    let files: URL
    var failDownload = false
    var failUpload = false
    private(set) var uploads = 0
    init(_ directory: URL) { files = directory }
    func account() -> String { "isolated-fixture-account" }
    func setFailures(download: Bool = false, upload: Bool = false) {
        failDownload = download; failUpload = upload
    }
    func changes(after cursor: String?) throws -> (items: [PrivateArchive], cursor: String, more: Bool) {
        let at = Int(cursor ?? "0") ?? 0
        let end = min(at + 2,log.count)
        return (log[at..<end].compactMap { records[$0] },String(end),end < log.count)
    }
    func upload(_ local: PrivateArchive, baseline: PrivateArchive?, files: [URL]) throws -> PrivateArchive {
        if failUpload { throw CocoaError(.fileWriteOutOfSpace) }
        let saved = try records[local.id].map { try local.merged(with: $0, baseline: baseline) } ?? local
        if let old = records[local.id], saved.audioDeleted {
            for item in old.chunks { try? FileManager.default.removeItem(at: self.files.appendingPathComponent(item.id.uuidString)) }
        }
        for (c,url) in zip(local.chunks,files) where !saved.audioDeleted {
            try FileManager.default.createDirectory(at: self.files, withIntermediateDirectories: true)
            let destination = self.files.appendingPathComponent(c.id.uuidString)
            if !FileManager.default.fileExists(atPath: destination.path) { try FileManager.default.copyItem(at: url, to: destination) }
        }
        records[saved.id] = saved; log.append(saved.id); uploads += 1
        return saved
    }
    func download(_ manifest: PrivateArchive) throws -> [URL] {
        if failDownload { throw URLError(.networkConnectionLost) }
        return manifest.chunks.map { files.appendingPathComponent($0.id.uuidString) }
    }
}

private struct CloudArchiveFixture {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("saytile-icloud-test-" + UUID().uuidString)
    func store(_ name: String) throws -> SaytileStore { try SaytileStore(directory: directory.appendingPathComponent(name)) }
    func clean() { try? FileManager.default.removeItem(at: directory) }
    func append(_ store: SaytileStore, time: Double, text: String) async throws -> UUID {
        let record = try await store.createRecording(createdAt: Date(timeIntervalSince1970: time))
        let journal = try PCMJournal(directory: store.audioDirectory, recordingID: record.id)
        try journal.openChunk()
        try journal.append(Data(repeating:0x02,count: 3200))
        try journal.closeChunk()
        try await store.registerAudioChunk(recordingID: record.id, relativePath: journal.relativePath, frames: journal.frames)
        let ticket = try await store.beginRecognition(recordingID: record.id)
        try await store.applyRecognition(ticket: ticket,text: text,isFinal: true)
        try await store.finishRecognition(ticket: ticket)
        try await store.finishRecording(id: record.id,speechEndedAt: Date(timeIntervalSince1970: time + 0.1))
        return record.id
    }
}

@Suite struct PrivateArchiveTests {
    @Test func diskFullThenOfflineRestoreRecoversAllVersionsAndPlayableWAVInOriginalGroup() async throws {
        let f = CloudArchiveFixture(); defer { f.clean() }
        let first = try f.store("first")
        let cloud = IsolatedArchiveTransport(f.directory.appendingPathComponent("fake-transport"))
        let a = PrivateArchiveSync(store: first, remote: cloud)
        let id1 = try await f.append(first, time: 1700000000, text: "查看二十条")
        let id2 = try await f.append(first, time: 1700000003, text: "不删除")
        _ = try await first.saveEdit(recordingID: id1, text: "查看十二条")
        try await first.setPinned(recordingID: id1,pinned: true)
        try await first.saveDraft(recordingID: id1,text: "未提交的手工草稿")
        await cloud.setFailures(upload: true)
        await #expect(throws: CocoaError.self) { try await a.synchronize { _ in } }
        #expect(try await first.archivePending().count == 2)
        await cloud.setFailures()
        try await a.synchronize { _ in }
        let attempts = await cloud.uploads
        try await a.synchronize { _ in }
        #expect(await cloud.uploads == attempts)
        let target = try f.store("fresh")
        let binding = try await target.createBinding(label: "isolated-target",createdAt: .distantPast)
        await cloud.setFailures(download: true)
        await #expect(throws: URLError.self) { try await PrivateArchiveSync(store: target,remote: cloud).synchronize { _ in } }
        #expect(try await target.recording(id: id1)?.text == "查看十二条")
        #expect(try await target.recording(id: id1)?.audioState == .missing)
        #expect(try await target.directInputCandidates(bindingID: binding,createdSince: .distantPast).isEmpty)
        try await target.close()
        let reopened = try f.store("fresh")
        await cloud.setFailures()
        try await PrivateArchiveSync(store: reopened,remote: cloud).synchronize { _ in }
        let timeline = try await reopened.timelinePage()
        #expect(timeline.entries.map(\.id) == [id1,id2])
        #expect(timeline.entries[0].group == timeline.entries[1].group)
        #expect(timeline.entries[0].recording.isPinned)
        #expect(try await reopened.loadDraft(recordingID: id1) == "未提交的手工草稿")
        for id in [id1,id2] {
            #expect(try await first.exportArchive(id) == reopened.exportArchive(id))
            let chunks = try await reopened.audioChunks(recordingID: id)
            #expect(chunks.count == 1)
            let file = try AVAudioFile(forReading: await reopened.audioURL(for: chunks[0]))
            #expect(file.length == 1600)
        }
        #expect(try await reopened.revisions(recordingID: id1).count == 2)
    }

    @Test func staleDeviceCannotRecreateErasedAudioOrDeletedTextAndAccountSwitchIsRefused() async throws {
        let f = CloudArchiveFixture(); defer { f.clean() }
        let first = try f.store("one"), other = try f.store("two")
        let cloud = IsolatedArchiveTransport(f.directory.appendingPathComponent("wire"))
        let a = PrivateArchiveSync(store: first,remote: cloud), b = PrivateArchiveSync(store: other,remote: cloud)
        let id = try await f.append(first,time: 1700000010,text: "不删除文字")
        try await a.synchronize { _ in }; try await b.synchronize { _ in }
        _ = try await other.saveEdit(recordingID: id,text: "保留修改")
        try await first.deleteAudio(recordingID: id)
        try await a.synchronize { _ in }; try await b.synchronize { _ in }; try await a.synchronize { _ in }
        #expect(try await first.recording(id: id)?.text == "保留修改")
        #expect(try await other.recording(id: id)?.audioState == .deleted)
        #expect(try await other.revisions(recordingID: id).count == 2)
        #expect(try FileManager.default.contentsOfDirectory(atPath: cloud.files.path).isEmpty)
        try await first.deleteRecord(recordingID: id)
        _ = try await other.saveEdit(recordingID: id,text: "离线编辑")
        try await a.synchronize { _ in }; try await b.synchronize { _ in }
        #expect(try await other.recording(id: id) == nil)
        #expect(try await other.exportArchive(id)?.versions.isEmpty == true)
        await #expect(throws: ArchiveIssue.self) { try await other.enablePrivateArchive(owner: "wrong-account") }
    }

    @Test func damagedDownloadIsNeverIndexedAndLiveRecordingIsNotSent() async throws {
        let f = CloudArchiveFixture(); defer { f.clean() }
        let a = try f.store("a"), b = try f.store("b")
        let cloud = IsolatedArchiveTransport(f.directory.appendingPathComponent("wire"))
        let first = PrivateArchiveSync(store: a, remote: cloud), second = PrivateArchiveSync(store: b, remote: cloud)
        let active = try await a.createRecording()
        let id = try await f.append(a,time: 1700000020,text: "未完成的录音不要上传")
        try await first.synchronize { _ in }
        let manifest = try #require(try await a.exportArchive(id))
        let file = try #require(try await cloud.download(manifest).first)
        let saved = try Data(contentsOf: file)
        try Data(repeating: 0xEE,count: saved.count).write(to:file)
        await #expect(throws: ArchiveIssue.self) { try await second.synchronize { _ in } }
        #expect(try await b.audioChunks(recordingID: id).isEmpty)
        #expect(try await b.recording(id: active.id) == nil)
        try saved.write(to:file)
        try await second.synchronize { _ in }
        #expect(try await b.audioChunks(recordingID: id).count == 1)
    }
}

extension PrivateArchiveTests {
    @Test func concurrentDraftsRemainRecoverableAndClockReversalKeepsSourceOrder() async throws {
        let f = CloudArchiveFixture(); defer { f.clean() }
        let a = try f.store("a"), b = try f.store("b")
        let cloud = IsolatedArchiveTransport(f.directory.appendingPathComponent("wire"))
        let first = PrivateArchiveSync(store: a,remote: cloud), second = PrivateArchiveSync(store: b,remote: cloud)
        let id = try await f.append(a,time: 1700000020,text: "第一个原句")
        let later = try await f.append(a,time: 1700000010,text: "调时后的下一句")
        try await first.synchronize { _ in }; try await second.synchronize { _ in }
        #expect(try await b.timelinePage().entries.map(\.id) == [id,later])
        try await a.saveDraft(recordingID: id,text: "甲的草稿")
        try await b.saveDraft(recordingID: id,text: "乙的草稿")
        try await first.synchronize { _ in }; try await second.synchronize { _ in }; try await first.synchronize { _ in }
        for store in [a,b] {
            let copies = try await store.revisions(recordingID: id).map(\.text) + [store.loadDraft(recordingID: id) ?? ""]
            #expect(Set(copies).isSuperset(of: ["甲的草稿","乙的草稿"]))
            #expect(try await store.recording(id: id)?.text == "第一个原句")
        }
    }
}
