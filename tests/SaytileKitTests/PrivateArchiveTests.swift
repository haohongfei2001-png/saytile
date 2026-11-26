import Foundation
import Testing
import AVFoundation
import CloudKit
@testable import SaytileKit

private actor IsolatedArchiveTransport: PrivateArchiveTransport {
    private var records: [UUID: PrivateArchive] = [:]
    private var log: [UUID] = []
    let files: URL
    var failDownload = false
    var failUpload = false
    var expired = false
    var recentCursors: [String?] = []
    func expire() { expired = true; recentCursors = [] }
    private(set) var uploads = 0
    init(_ directory: URL) { files = directory }
    func account() -> String { "isolated-fixture-account" }
    func setFailures(download: Bool = false, upload: Bool = false) {
        failDownload = download; failUpload = upload
    }
    func changes(after cursor: String?) throws -> (items: [PrivateArchive], cursor: String, more: Bool) {
        recentCursors.append(cursor)
        if expired { expired = false; throw ArchiveIssue.cursorExpired }
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
            let verified = try #require(try await reopened.exportArchive(id))
            #expect(try await first.exportArchive(id) == verified)
            #expect(verified.chunks.map(\.sha256) == ["260f7d54d110254c7931a0fd0d8c6bcf8dbac9f12747afef6144b624e6a382b9"])
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

extension PrivateArchiveTests {
    @Test @MainActor func paragraphsAndExplicitJoinRoundTripAcrossPagesAndPopulatedMac() async throws {
        let f = CloudArchiveFixture(); defer { f.clean() }
        let source = try f.store("source"), target = try f.store("target")
        let wire = IsolatedArchiveTransport(f.directory.appendingPathComponent("wire"))
        let a = PrivateArchiveSync(store: source, remote: wire), b = PrivateArchiveSync(store: target, remote: wire)
        let t = 1_700_000_000.0
        let first = try await f.append(source, time: t, text: "第一")
        let continued = try await f.append(source, time: t+6, text: "句")
        let next = try await f.append(source, time: t+37, text: "第二")
        let tail = try await f.append(source, time: t+40, text: "段")
        let different = try await f.append(source, time: t+120, text: "另一组")
        let own = try await f.append(target, time: t-2, text: "本机")
        try await a.synchronize { _ in }
        _ = try source.editTimeline([.init(id: next,before: "第二",after: "第二",paragraphBreakHidden: true,previousParagraphBreakHidden: false)], window: .latest)
        try await a.synchronize { _ in }
        try await b.synchronize { _ in }
        let rows = try await target.timelinePage().entries
        let entries = Dictionary(uniqueKeysWithValues: rows.map { ($0.id,$0) })
        #expect(rows.map(\.id) == [own, first, continued, next, tail, different])
        #expect(entries[first]?.paragraphID == entries[continued]?.paragraphID)
        #expect(entries[first]?.paragraphID != entries[own]?.paragraphID)
        #expect(entries[first]?.paragraphID != entries[next]?.paragraphID)
        #expect(entries[next]?.paragraphID == entries[tail]?.paragraphID)
        #expect(entries[next]?.paragraphBreakHidden == true && entries[tail]?.paragraphBreakHidden == true)
        #expect(entries[first]?.group == entries[next]?.group && entries[next]?.group != entries[different]?.group)
        _ = try target.editTimeline([.init(id: next,before: "第二",after: "第二",paragraphBreakHidden: false,previousParagraphBreakHidden: true)], window: .latest)
        try await b.synchronize { _ in }
        try await a.synchronize { _ in }
        #expect(try await source.exportArchive(tail)?.paragraph?.hidden == false)
        #expect(try await source.exportArchive(tail)?.paragraph?.id == next)
    }

    @Test func restoreCannotDispatchNewLocalRecognitionOrEraseMismatchedIdentity() async throws {
        let f = CloudArchiveFixture(); defer { f.clean() }
        let source = try f.store("source"), target = try f.store("target")
        let wire = IsolatedArchiveTransport(f.directory.appendingPathComponent("wire"))
        let id = try await f.append(source,time: 1_700_000_000,text: "原音")
        let binding = try await target.createBinding(label: "隔离目标",createdAt: .distantPast)
        try await PrivateArchiveSync(store: source,remote: wire).synchronize { _ in }
        try await PrivateArchiveSync(store: target,remote: wire).synchronize { _ in }
        let retry = try await target.beginRecognition(recordingID: id)
        try await target.applyRecognition(ticket: retry,text: "重新识别",isFinal: true)
        try await target.finishRecognition(ticket: retry)
        let revision = try #require(try await target.revisions(recordingID: id).first(where: { $0.text == "重新识别" }))
        #expect(try await target.directInputCandidates(bindingID: binding,createdSince: .distantPast).isEmpty)
        await #expect(throws: StoreError.self) {
            _ = try await target.reserveDispatch(bindingID: binding,recordingID: id,revisionID: revision.id,stableUTF16End: 4)
        }

        let original = try #require(try await target.exportArchive(id))
        let wrong = PrivateArchive(format: 1,id: id,started: original.started+1,ended: nil,day: original.day,offset: original.offset,
                                   group: original.group,sampleRate: original.sampleRate,head: nil,pinned: false,deleted: true,audioDeleted: true,versions: [],chunks: [])
        await #expect(throws: ArchiveIssue.self) { try await target.applyArchiveText(wrong) }
        #expect(try await target.exportArchive(id) == original)
    }

    @Test func developmentProfileOnlyAcceptsAResolvedIsolatedFixture() throws {
        let fixture = URL(fileURLWithPath: "/private/tmp/saytile-icloud-fixture-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: fixture, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: fixture) }
        #expect(PrivateArchiveSync.isDevelopmentFixture(fixture.appendingPathComponent("second")))
        #expect(!PrivateArchiveSync.isDevelopmentFixture(fixture.deletingLastPathComponent()))
        let escaped = fixture.appendingPathComponent("outside")
        try FileManager.default.createSymbolicLink(at: escaped, withDestinationURL: URL(fileURLWithPath: "/private/tmp"))
        #expect(!PrivateArchiveSync.isDevelopmentFixture(escaped))
        #expect(!PrivateArchiveSync.isDevelopmentFixture(fixture.appendingPathComponent("../unrelated")))
    }

    @Test func explicitLegacyMergeKeepsBothOriginalsAndChronologicalStagedResult() async throws {
        let f = CloudArchiveFixture(); defer { f.clean() }
        let fm = FileManager.default
        let base = try f.store("base"), old = try f.store("old")
        let time = 1_700_000_000.0
        let recent = try await f.append(base, time: time+125, text: "目前的记录")
        let early = try await f.append(old, time: time, text: "旧档")
        let tail = try await f.append(old, time: time+4, text: "接续")
        _ = try await old.saveEdit(recordingID: early, text: "旧版手改")
        try await old.setPinned(recordingID: early, pinned: true)
        try await old.saveDraft(recordingID: tail, text: "未提交")
        let baseDir = base.directory, oldDir = old.directory, result = f.directory.appendingPathComponent("checked")
        let extra = Data("本机资料".utf8)
        try extra.write(to: baseDir.appendingPathComponent("fixture-other-state"))
        await #expect(throws: StoreError.self) { _ = try await LegacyArchiveRecovery.prepare(base: baseDir, legacy: oldDir, output: result) }
        #expect(!fm.fileExists(atPath: result.path))
        try await old.close(); try await base.close()
        func snapshot(_ dir: URL) throws -> String { ArchiveCloudRecord.digest(try Data(contentsOf: dir.appendingPathComponent("Saytile.sqlite"))) }
        let before = try [snapshot(baseDir), snapshot(oldDir)]
        let receipt = try await LegacyArchiveRecovery.prepare(base: baseDir, legacy: oldDir, output: result)
        #expect(receipt.examined == 2 && receipt.added == 2 && receipt.verifiedOriginals == 2 && receipt.verifiedBytes == 6488)
        #expect(try [snapshot(baseDir), snapshot(oldDir)] == before)
        #expect(try Data(contentsOf: result.appendingPathComponent("fixture-other-state")) == extra)
        let staged = try SaytileStore(directory: result)
        let rows = try await staged.timelinePage().entries
        #expect(rows.map(\.id) == [early,tail,recent])
        #expect(rows[0].paragraphID == rows[1].paragraphID && rows[0].paragraphID != rows[2].paragraphID)
        #expect(rows[0].recording.isPinned && rows[0].recording.text == "旧版手改")
        #expect(try await staged.revisions(recordingID: early).count == 2)
        #expect(try await staged.loadDraft(recordingID: tail) == "未提交")
        #expect(try await staged.archiveState("owner") == nil)
        try await staged.deleteAudio(recordingID: early)
        try await staged.close()
        let twice = f.directory.appendingPathComponent("checked-again")
        let again = try await LegacyArchiveRecovery.prepare(base: result, legacy: oldDir, output: twice)
        #expect(again.added == 0 && again.overlapping == 2)
        let reopened = try SaytileStore(directory: twice)
        #expect(try await reopened.recording(id: early)?.audioState == .deleted)
        #expect(try await reopened.recording(id: early)?.text == "旧版手改")
        try await reopened.close()
        await #expect(throws: CocoaError.self) { _ = try await LegacyArchiveRecovery.prepare(base: baseDir, legacy: oldDir, output: result) }
        #expect(try [snapshot(baseDir), snapshot(oldDir)] == before)
    }

    @Test func expiredTokenRescansAnExistingZoneWithoutTreatingItAsFirstLaunch() async throws {
        let f = CloudArchiveFixture(); defer { f.clean() }
        let store = try f.store("local")
        let wire = IsolatedArchiveTransport(f.directory.appendingPathComponent("wire"))
        let sync = PrivateArchiveSync(store: store,remote: wire)
        _ = try await f.append(store,time: 1700000789,text: "已有档案")
        try await sync.synchronize { _ in }
        await wire.expire()
        try await sync.synchronize { _ in }
        let requested = await wire.recentCursors
        #expect(requested.count == 2 && requested[0] != nil && requested[1] == "")
        #expect(await wire.uploads == 1)
    }

    @Test func nativeCloudKitRecordRejectsCorruptDigestAndStoresLargeVersionsAsAssets() throws {
        let id = UUID()
        let zone = CKRecordZone.ID(zoneName: "isolated-record",ownerName: CKCurrentUserDefaultName)
        let record = CKRecord(recordType: ArchiveCloudRecord.type,recordID: .init(recordName: id.uuidString,zoneID: zone))
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir,withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: dir) }
        var manifest = PrivateArchive(format: 1,id: id,started: 1,ended: 2,day: "2001-01-01",offset: 0,
            group: .init(start: 1,day: "2001-01-01",offset: 0),sampleRate: 16000,head: nil,pinned: false,
            deleted: false,audioDeleted: false,versions: [],chunks: [])
        try ArchiveCloudRecord.setManifest(try manifest.encoded(),parts: 0,on: record,staging: dir)
        #expect(try ArchiveCloudRecord.manifest(in: record) == manifest)
        #expect(record["manifest"] is Data)
        let version = PrivateArchive.Version(id: UUID(),text: String(repeating: "隔离稿件",count: 40000),origin: .userEdit,created: 2,attempt: nil,base: nil)
        manifest.head = version.id; manifest.versions = [version]
        try ArchiveCloudRecord.setManifest(try manifest.encoded(),parts: 0,on: record,staging: dir)
        #expect(record["manifestFile"] is CKAsset)
        #expect(try ArchiveCloudRecord.manifest(in: record) == manifest)
        record["manifestSHA256"] = "corrupt"
        #expect(throws: ArchiveIssue.self) { try ArchiveCloudRecord.manifest(in: record) }
    }
}
