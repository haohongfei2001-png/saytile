import Foundation
import Testing
@testable import SaytileKit

private func rcDirectory() -> URL { FileManager.default.temporaryDirectory.appendingPathComponent("saytile-rc-storage-" + UUID().uuidString) }

@Suite("RC store ownership, migrations and archive")
struct StoreRCTests {
    @Test func secondOwnerCannotInvalidateActiveRecording() async throws {
        let root = rcDirectory(); defer { try? FileManager.default.removeItem(at:root) }
        let owner = try SaytileStore(directory:root)
        let record = try await owner.createRecording()
        #expect(throws:StoreError.self) { try SaytileStore(directory:root) }
        #expect(try await owner.recording(id:record.id)?.isRecording == true)
        try await owner.close()
        await #expect(throws:StoreError.self) { try await owner.listRecordings() }
        let reopened = try SaytileStore(directory:root)
        #expect(reopened.recovery.interruptedRecordings == 1)
        #expect(try await reopened.recording(id:record.id)?.isRecording == false)
    }
    @Test func failedMigrationRollsBackAllDDLAndKeepsVersion() throws {
        let root = rcDirectory(); defer { try? FileManager.default.removeItem(at:root) }
        try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)
        let file = root.appendingPathComponent("Saytile.sqlite")
        let fixture = try StoreDatabase(url:file)
        try fixture.script("CREATE TABLE recordings(id TEXT PRIMARY KEY); PRAGMA user_version=1;")
        try fixture.close()
        #expect(throws:StoreError.self) { try SaytileStore(directory:root) }
        let check = try StoreDatabase(url:file)
        #expect(try check.rows("PRAGMA user_version").first?["user_version"] == "1")
        #expect(try check.rows("SELECT name FROM sqlite_master WHERE type='table'").map { $0["name"]! } == ["recordings"])
    }
    @Test func futureDatabaseRefusedWithoutChangingJournalOrBytes() throws {
        let root = rcDirectory(); defer { try? FileManager.default.removeItem(at:root) }
        try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)
        let file = root.appendingPathComponent("Saytile.sqlite")
        let fixture = try StoreDatabase(url:file)
        try fixture.script("CREATE TABLE future_data(value TEXT); INSERT INTO future_data VALUES('保留'); PRAGMA user_version=99;")
        try fixture.close()
        let before = try Data(contentsOf:file)
        #expect(throws:StoreError.self) { try SaytileStore(directory:root) }
        #expect(try Data(contentsOf:file) == before)
        let check = try StoreDatabase(url:file)
        #expect(try check.rows("PRAGMA journal_mode").first?["journal_mode"] == "delete")
    }
    @Test func sqliteFullRollsBackWholeTransaction() throws {
        let root = rcDirectory(); defer { try? FileManager.default.removeItem(at:root) }
        try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)
        let db = try StoreDatabase(url:root.appendingPathComponent("fault.sqlite"))
        try db.configureForWriting()
        try db.script("CREATE TABLE entries(value TEXT); INSERT INTO entries VALUES('原始数据'); PRAGMA max_page_count=4;")
        #expect(throws:StoreError.self) {
            try db.transaction {
                try db.execute("INSERT INTO entries VALUES('不能部分提交')")
                try db.execute("INSERT INTO entries VALUES(?)",[.text(String(repeating:"测",count:100_000))])
            }
        }
        #expect(try db.rows("SELECT value FROM entries").map { $0["value"]! } == ["原始数据"])
        #expect(try db.rows("PRAGMA quick_check").first?["quick_check"] == "ok")
    }
    @Test func draftSearchAndHistorySurviveAudioErasure() async throws {
        let root = rcDirectory(); defer { try? FileManager.default.removeItem(at:root) }
        let store = try SaytileStore(directory:root), record = try await store.createRecording()
        try await store.saveEdit(recordingID:record.id,text:"最初版本")
        try await store.saveEdit(recordingID:record.id,text:"现在版本")
        try await store.saveDraft(recordingID:record.id,text:"尚未提交的100%草稿_")
        try await store.finishRecording(id:record.id)
        for query in ["最初","现在","100%","草稿_"] { #expect(try await store.listRecordings(query:query).first?.id == record.id) }
        try await store.deleteAudio(recordingID:record.id)
        #expect(try await store.listRecordings(query:"100%").first?.id == record.id)
        #expect(try await store.revisions(recordingID:record.id).count == 2)
        #expect(try await store.loadDraft(recordingID:record.id) == "尚未提交的100%草稿_")
    }
    @Test func panelIncludesAllSessionPagesAndExplicitHistoryOnlyOnce() async throws {
        let root = rcDirectory(); defer { try? FileManager.default.removeItem(at:root) }
        let store = try SaytileStore(directory:root)
        let history = try await store.createRecording(createdAt:Date(timeIntervalSince1970:1))
        _ = try await store.createRecording(createdAt:Date(timeIntervalSince1970:2))
        for index in 0..<135 { _ = try await store.createRecording(createdAt:Date(timeIntervalSince1970:1000 + Double(index))) }
        let since = Date(timeIntervalSince1970:1000)
        let count = try await store.panelRecordingCount(createdSince:since,includingIDs:[history.id,history.id])
        #expect(count == 136)
        let first = try await store.listPanelRecordings(createdSince:since,includingIDs:[history.id],limit:100)
        let second = try await store.listPanelRecordings(createdSince:since,includingIDs:[history.id],limit:100,offset:100)
        #expect(first.count == 100); #expect(second.count == 36)
        #expect(Set((first + second).map(\.id)).count == 136)
        #expect(second.last?.id == history.id)
    }
    @Test func corruptRowReturnsErrorInsteadOfCrashing() async throws {
        let root = rcDirectory(); defer { try? FileManager.default.removeItem(at:root) }
        let store = try SaytileStore(directory:root), record = try await store.createRecording()
        let corruptor = try StoreDatabase(url:root.appendingPathComponent("Saytile.sqlite"))
        try corruptor.execute("PRAGMA ignore_check_constraints=ON")
        try corruptor.execute("UPDATE recordings SET audio_state='invalid' WHERE id=?",[.text(record.id.uuidString)])
        await #expect(throws:StoreError.self) { try await store.recording(id:record.id) }
    }
}

@Suite("Owned store path boundaries")
struct StorePathRCTests {
    @Test func audioRootSymlinkIsRejectedWithoutTouchingDestination() throws {
        let root = rcDirectory(), outside = rcDirectory()
        defer { try? FileManager.default.removeItem(at:root);try? FileManager.default.removeItem(at:outside) }
        try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)
        try FileManager.default.createDirectory(at:outside,withIntermediateDirectories:true)
        let sentinel = outside.appendingPathComponent("keep.txt")
        try Data("保持原样".utf8).write(to:sentinel)
        try FileManager.default.createSymbolicLink(at:root.appendingPathComponent("Audio"),withDestinationURL:outside)
        #expect(throws:StoreError.self) { try SaytileStore(directory:root) }
        #expect(try String(contentsOf:sentinel,encoding:.utf8) == "保持原样")
        #expect(try FileManager.default.contentsOfDirectory(atPath:outside.path) == ["keep.txt"])
    }
    @Test func databaseSymlinkIsRejectedWithoutModifyingExternalFile() throws {
        let root = rcDirectory(), outside = rcDirectory()
        defer { try? FileManager.default.removeItem(at:root);try? FileManager.default.removeItem(at:outside) }
        try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)
        try FileManager.default.createDirectory(at:outside,withIntermediateDirectories:true)
        let target = outside.appendingPathComponent("other.sqlite")
        try Data("不是Saytile资料".utf8).write(to:target)
        try FileManager.default.createSymbolicLink(at:root.appendingPathComponent("Saytile.sqlite"),withDestinationURL:target)
        #expect(throws:StoreError.self) { try SaytileStore(directory:root) }
        #expect(try String(contentsOf:target,encoding:.utf8) == "不是Saytile资料")
    }
}
