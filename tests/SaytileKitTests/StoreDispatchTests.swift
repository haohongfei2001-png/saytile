import Foundation
import Testing
@testable import SaytileKit

private struct DispatchFixture {
    let directory: URL
    let store: SaytileStore
    init() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("saytile-dispatch-test-" + UUID().uuidString)
        store = try SaytileStore(directory:directory)
    }
    func clean() { try? FileManager.default.removeItem(at:directory) }
    func revision(_ record: UUID, _ ticket: RecognitionTicket, _ text: String) async throws -> UUID {
        try await store.applyRecognition(ticket:ticket,text:text,isFinal:false)
        return try await store.recording(id:record)!.preferredRevisionID!
    }
}
@Test func storeDispatchOnlyNewStableSuffixAndNeverDuplicate() async throws {
    let f = try DispatchFixture(); defer { f.clean() }
    let binding = try await f.store.createBinding(label:"测试编辑器")
    let record = try await f.store.createRecording()
    let ticket = try await f.store.beginRecognition(recordingID:record.id)
    let v1 = try await f.revision(record.id,ticket,"你好")
    let one = try await f.store.reserveDispatch(bindingID:binding,recordingID:record.id,revisionID:v1,stableUTF16End:2)
    #expect(one?.text == "你好")
    try await f.store.completeDispatch(id:one!.id,state:.unverified)
    let v2 = try await f.revision(record.id,ticket,"你好，世界")
    let two = try await f.store.reserveDispatch(bindingID:binding,recordingID:record.id,revisionID:v2,stableUTF16End:5)
    #expect(two?.text == "，世界")
    #expect(two?.utf16Start == 2)
    #expect(try await f.store.reserveDispatch(bindingID:binding,recordingID:record.id,revisionID:v2,stableUTF16End:5) == nil)
    #expect(try await f.store.revisions(recordingID:record.id).count == 2)
}
@Test func storeDispatchRejectsPrefixRewriteAndInvalidatesBinding() async throws {
    let f = try DispatchFixture(); defer { f.clean() }
    let binding = try await f.store.createBinding(label:"测试")
    let r = try await f.store.createRecording()
    let ticket = try await f.store.beginRecognition(recordingID:r.id)
    let old = try await f.revision(r.id,ticket,"你好")
    _ = try await f.store.reserveDispatch(bindingID:binding,recordingID:r.id,revisionID:old,stableUTF16End:2)
    let rewrite = try await f.revision(r.id,ticket,"你们好")
    await #expect(throws:StoreError.self) { try await f.store.reserveDispatch(bindingID:binding,recordingID:r.id,revisionID:rewrite,stableUTF16End:3) }
    let future = try await f.store.createRecording()
    let futureTicket = try await f.store.beginRecognition(recordingID:future.id)
    let version = try await f.revision(future.id,futureTicket,"下一段")
    await #expect(throws:StoreError.self) { try await f.store.reserveDispatch(bindingID:binding,recordingID:future.id,revisionID:version,stableUTF16End:3) }
}
@Test func storeDispatchUTF16RejectsSurrogateAndGraphemeSplit() async throws {
    for (text,invalid,valid) in [("你😀",2,3),("e\u{301}",1,2),("👨‍👩‍👧‍👦",2,11)] {
        let f = try DispatchFixture(); defer { f.clean() }
        let binding = try await f.store.createBinding(label:"测试")
        let r = try await f.store.createRecording()
        let ticket = try await f.store.beginRecognition(recordingID:r.id)
        let revision = try await f.revision(r.id,ticket,text)
        await #expect(throws:StoreError.self) { try await f.store.reserveDispatch(bindingID:binding,recordingID:r.id,revisionID:revision,stableUTF16End:invalid) }
        let operation = try await f.store.reserveDispatch(bindingID:binding,recordingID:r.id,revisionID:revision,stableUTF16End:valid)
        #expect(operation?.text == text)
    }
}
@Test func storeDispatchRestartInvalidatesTargetAndDoesNotReplay() async throws {
    let f = try DispatchFixture(); defer { f.clean() }
    let binding = try await f.store.createBinding(label:"测试")
    let r = try await f.store.createRecording()
    let ticket = try await f.store.beginRecognition(recordingID:r.id)
    let revision = try await f.revision(r.id,ticket,"你好")
    let operation = try await f.store.reserveDispatch(bindingID:binding,recordingID:r.id,revisionID:revision,stableUTF16End:2)!
    let reopened = try SaytileStore(directory:f.directory)
    #expect(reopened.recovery.unverifiedDispatches == 1)
    #expect(try await reopened.dispatchState(id:operation.id) == .unverified)
    await #expect(throws:StoreError.self) { try await reopened.reserveDispatch(bindingID:binding,recordingID:r.id,revisionID:revision,stableUTF16End:2) }
    let newBinding = try await reopened.createBinding(label:"新目标")
    await #expect(throws:StoreError.self) { try await reopened.reserveDispatch(bindingID:newBinding,recordingID:r.id,revisionID:revision,stableUTF16End:2) }
}
@Test func storeDispatchUnverifiedDoesNotBlockIndependentSegment() async throws {
    let f = try DispatchFixture(); defer { f.clean() }
    let binding = try await f.store.createBinding(label:"测试")
    for text in ["第一段","第二段"] {
        let r = try await f.store.createRecording()
        let ticket = try await f.store.beginRecognition(recordingID:r.id)
        let revision = try await f.revision(r.id,ticket,text)
        let operation = try await f.store.reserveDispatch(bindingID:binding,recordingID:r.id,revisionID:revision,stableUTF16End:text.utf16.count)
        #expect(operation?.text == text)
        try await f.store.completeDispatch(id:operation!.id,state:.unverified)
    }
}
@Test func storeManualInsertionIsExplicitNewOperationEachTime() async throws {
    let f = try DispatchFixture(); defer { f.clean() }
    let r = try await f.store.createRecording()
    let revision = try await f.store.saveEdit(recordingID:r.id,text:"手动复用")
    let first = try await f.store.reserveManual(recordingID:r.id,revisionID:revision.id,label:"测试")
    let second = try await f.store.reserveManual(recordingID:r.id,revisionID:revision.id,label:"测试")
    #expect(first.id != second.id)
    #expect(first.text == "手动复用")
    try await f.store.completeDispatch(id:first.id,state:.failed)
    try await f.store.completeDispatch(id:first.id,state:.confirmed)
    #expect(try await f.store.dispatchState(id:first.id) == .failed)
}
@Test func storeDeletingRecordAlsoDeletesDispatchTextSnapshots() async throws {
    let f = try DispatchFixture(); defer { f.clean() }
    let r = try await f.store.createRecording()
    let revision = try await f.store.saveEdit(recordingID:r.id,text:"删除内容")
    let dispatch = try await f.store.reserveManual(recordingID:r.id,revisionID:revision.id,label:"测试")
    try await f.store.finishRecording(id:r.id)
    try await f.store.deleteRecord(recordingID:r.id)
    #expect(try await f.store.dispatchState(id:dispatch.id) == nil)
}
