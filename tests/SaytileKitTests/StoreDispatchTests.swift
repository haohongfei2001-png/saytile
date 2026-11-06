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
    try await f.store.close()
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

@Test func storeDirectCandidatesDrainBacklogBeyondLatestThirtyWithoutReplay() async throws {
    let f = try DispatchFixture(); defer { f.clean() }
    let historical = try await f.store.createRecording(createdAt:Date(timeIntervalSince1970:1))
    let historicalTicket = try await f.store.beginRecognition(recordingID:historical.id)
    try await f.store.applyRecognition(ticket:historicalTicket,text:"旧讲话不应发送",isFinal:true)
    let binding = try await f.store.createBinding(label:"慢识别测试目标")
    var created: [UUID] = []
    for index in 0..<65 {
        let record = try await f.store.createRecording()
        let ticket = try await f.store.beginRecognition(recordingID:record.id)
        try await f.store.applyRecognition(ticket:ticket,text:"第\(index)段",isFinal:true)
        try await f.store.finishRecording(id:record.id)
        created.append(record.id)
    }
    var dispatched: [UUID] = []
    while true {
        let page = try await f.store.directInputCandidates(bindingID:binding,createdSince:.distantPast,limit:20)
        if page.isEmpty { break }
        for record in page {
            let stable = try await f.store.latestFinalRevision(recordingID:record.id)!
            let operation = try await f.store.reserveDispatch(bindingID:binding,recordingID:record.id,revisionID:stable.id,stableUTF16End:stable.text.utf16.count)!
            try await f.store.completeDispatch(id:operation.id,state:.unverified)
            dispatched.append(record.id)
        }
    }
    #expect(dispatched == created)
    #expect(try await f.store.directInputCandidates(bindingID:binding,createdSince:.distantPast).isEmpty)
    try await f.store.close()
    let reopened = try SaytileStore(directory:f.directory)
    #expect(try await reopened.directInputCandidates(bindingID:binding,createdSince:.distantPast).isEmpty)
}
@Test func storeDirectCandidatesIncludeChangedPrefixButSkipDuplicateLatestFinal() async throws {
    let f = try DispatchFixture(); defer { f.clean() }
    let binding = try await f.store.createBinding(label:"范围测试")
    let record = try await f.store.createRecording()
    let ticket = try await f.store.beginRecognition(recordingID:record.id)
    try await f.store.applyRecognition(ticket:ticket,text:"你好",isFinal:true)
    let first = try await f.store.latestFinalRevision(recordingID:record.id)!
    _ = try await f.store.reserveDispatch(bindingID:binding,recordingID:record.id,revisionID:first.id,stableUTF16End:2)
    try await f.store.applyRecognition(ticket:ticket,text:"你好",isFinal:true)
    #expect(try await f.store.directInputCandidates(bindingID:binding,createdSince:.distantPast).isEmpty)
    try await f.store.applyRecognition(ticket:ticket,text:"你们好",isFinal:true)
    #expect(try await f.store.directInputCandidates(bindingID:binding,createdSince:.distantPast).map(\.id) == [record.id])
    let changed = try await f.store.latestFinalRevision(recordingID:record.id)!
    await #expect(throws:StoreError.self) {
        try await f.store.reserveDispatch(bindingID:binding,recordingID:record.id,revisionID:changed.id,stableUTF16End:3)
    }
    #expect(try await f.store.directInputCandidates(bindingID:binding,createdSince:.distantPast).isEmpty)
}
@Test func storeDirectCandidatesIgnoreVolatileAndEmptyFinalText() async throws {
    let f = try DispatchFixture(); defer { f.clean() }
    let binding = try await f.store.createBinding(label:"稳定稿测试")
    let record = try await f.store.createRecording(), ticket = try await f.store.beginRecognition(recordingID:record.id)
    try await f.store.applyRecognition(ticket:ticket,text:"尚未稳定",isFinal:false)
    #expect(try await f.store.directInputCandidates(bindingID:binding,createdSince:.distantPast).isEmpty)
    try await f.store.applyRecognition(ticket:ticket,text:"",isFinal:true)
    #expect(try await f.store.directInputCandidates(bindingID:binding,createdSince:.distantPast).isEmpty)
}

@Test func storeDelayedEarlierSpeechIsDeferredWithoutBlockingLaterSpeech() async throws {
    let f = try DispatchFixture(); defer { f.clean() }
    let binding = try await f.store.createBinding(label:"顺序测试")
    let a = try await f.store.createRecording(), aTicket = try await f.store.beginRecognition(recordingID:a.id)
    try await f.store.applyRecognition(ticket:aTicket,text:"较早讲话草稿",isFinal:false)
    let b = try await f.store.createRecording(), bTicket = try await f.store.beginRecognition(recordingID:b.id)
    try await f.store.applyRecognition(ticket:bTicket,text:"先识别完成的B",isFinal:true)
    let bFinal = try await f.store.latestFinalRevision(recordingID:b.id)!
    let bOperation = try await f.store.reserveDispatch(bindingID:binding,recordingID:b.id,revisionID:bFinal.id,stableUTF16End:bFinal.text.utf16.count)!
    try await f.store.completeDispatch(id:bOperation.id,state:.confirmed)
    try await f.store.applyRecognition(ticket:aTicket,text:"较早讲话的迟到结果",isFinal:true)
    let aFinal = try await f.store.latestFinalRevision(recordingID:a.id)!
    #expect(try await f.store.directInputCandidates(bindingID:binding,createdSince:.distantPast).isEmpty)
    do {
        _ = try await f.store.reserveDispatch(bindingID:binding,recordingID:a.id,revisionID:aFinal.id,stableUTF16End:aFinal.text.utf16.count)
        Issue.record("Earlier speech must remain available for manual reuse")
    } catch StoreError.lateRecognitionDeferred {}
    #expect(try await f.store.recording(id:a.id)?.text == aFinal.text)
    #expect(try await f.store.deferredDirectInputRecordings(bindingID:binding,createdSince:.distantPast) == [a.id])
    let c = try await f.store.createRecording(), cTicket = try await f.store.beginRecognition(recordingID:c.id)
    try await f.store.applyRecognition(ticket:cTicket,text:"C继续正常输入",isFinal:true)
    let cFinal = try await f.store.latestFinalRevision(recordingID:c.id)!
    #expect(try await f.store.directInputCandidates(bindingID:binding,createdSince:.distantPast).map(\.id) == [c.id])
    #expect(try await f.store.reserveDispatch(bindingID:binding,recordingID:c.id,revisionID:cFinal.id,stableUTF16End:cFinal.text.utf16.count) != nil)
}
@Test func storeEarlierTailCannotFollowLaterReservationEvenWhenDeliveryUnverified() async throws {
    let f = try DispatchFixture(); defer { f.clean() }
    let binding = try await f.store.createBinding(label:"尾部顺序测试")
    let a = try await f.store.createRecording(), aTicket = try await f.store.beginRecognition(recordingID:a.id)
    let aFirst = try await f.revision(a.id,aTicket,"你好")
    let first = try await f.store.reserveDispatch(bindingID:binding,recordingID:a.id,revisionID:aFirst,stableUTF16End:2)!
    try await f.store.completeDispatch(id:first.id,state:.failed)
    let b = try await f.store.createRecording(), bTicket = try await f.store.beginRecognition(recordingID:b.id)
    let bFinal = try await f.revision(b.id,bTicket,"B")
    let later = try await f.store.reserveDispatch(bindingID:binding,recordingID:b.id,revisionID:bFinal,stableUTF16End:1)!
    try await f.store.completeDispatch(id:later.id,state:.unverified)
    #expect(try await f.store.deferredDirectInputRecordings(bindingID:binding,createdSince:.distantPast).isEmpty)
    // Exactly the previous reservation is still a harmless duplicate.
    #expect(try await f.store.reserveDispatch(bindingID:binding,recordingID:a.id,revisionID:aFirst,stableUTF16End:2) == nil)
    let tail = try await f.revision(a.id,aTicket,"你好，这是A迟到的尾部")
    do {
        _ = try await f.store.reserveDispatch(bindingID:binding,recordingID:a.id,revisionID:tail,stableUTF16End:"你好，这是A迟到的尾部".utf16.count)
        Issue.record("A tail must not be appended after B")
    } catch StoreError.lateRecognitionDeferred {}
    let c = try await f.store.createRecording(), cTicket = try await f.store.beginRecognition(recordingID:c.id)
    let cFinal = try await f.revision(c.id,cTicket,"C")
    #expect(try await f.store.reserveDispatch(bindingID:binding,recordingID:c.id,revisionID:cFinal,stableUTF16End:1) != nil)
}
@Test func storeDeletedLaterRecordKeepsTextFreeOrderingWatermark() async throws {
    let f = try DispatchFixture(); defer { f.clean() }
    let binding = try await f.store.createBinding(label:"删除顺序测试")
    let a = try await f.store.createRecording(), aTicket = try await f.store.beginRecognition(recordingID:a.id)
    let b = try await f.store.createRecording(), bTicket = try await f.store.beginRecognition(recordingID:b.id)
    let bVersion = try await f.revision(b.id,bTicket,"将删除的正文")
    _ = try await f.store.reserveDispatch(bindingID:binding,recordingID:b.id,revisionID:bVersion,stableUTF16End:6)
    try await f.store.finishRecording(id:b.id)
    try await f.store.deleteRecord(recordingID:b.id)
    try await f.store.applyRecognition(ticket:aTicket,text:"A迟到",isFinal:true)
    #expect(try await f.store.directInputCandidates(bindingID:binding,createdSince:.distantPast).isEmpty)
    let aVersion = try await f.store.latestFinalRevision(recordingID:a.id)!
    do {
        _ = try await f.store.reserveDispatch(bindingID:binding,recordingID:a.id,revisionID:aVersion.id,stableUTF16End:3)
        Issue.record("Deleting B must not rewind this binding")
    } catch StoreError.lateRecognitionDeferred {}
    let raw = try StoreDatabase(url:f.directory.appendingPathComponent("Saytile.sqlite"))
    #expect(try raw.rows("SELECT prefix FROM cursors WHERE recording_id=?",[.text(b.id.uuidString)]).first?["prefix"] == "")
    #expect(try raw.rows("SELECT text FROM revisions WHERE recording_id=?",[.text(b.id.uuidString)]).isEmpty)
    #expect(try raw.rows("SELECT text FROM dispatches WHERE recording_id=?",[.text(b.id.uuidString)]).isEmpty)
}
@Test func storeEqualTimestampOrderingUsesCreationSequenceForCandidateAndReservation() async throws {
    let f = try DispatchFixture(); defer { f.clean() }
    let binding = try await f.store.createBinding(label:"同时间顺序测试")
    let date = Date().addingTimeInterval(1)
    let high = try await f.store.createRecording(id:UUID(uuidString:"FFFFFFFF-FFFF-4FFF-8FFF-FFFFFFFFFFFF")!,createdAt:date)
    let low = try await f.store.createRecording(id:UUID(uuidString:"00000000-0000-4000-8000-000000000001")!,createdAt:date)
    for record in [high,low] {
        let ticket = try await f.store.beginRecognition(recordingID:record.id)
        try await f.store.applyRecognition(ticket:ticket,text:"稳定稿",isFinal:true)
    }
    #expect(try await f.store.directInputCandidates(bindingID:binding,createdSince:.distantPast).map(\.id) == [high.id,low.id])
    let lowVersion = try await f.store.latestFinalRevision(recordingID:low.id)!
    _ = try await f.store.reserveDispatch(bindingID:binding,recordingID:low.id,revisionID:lowVersion.id,stableUTF16End:3)
    #expect(try await f.store.directInputCandidates(bindingID:binding,createdSince:.distantPast).isEmpty)
    let highVersion = try await f.store.latestFinalRevision(recordingID:high.id)!
    do {
        _ = try await f.store.reserveDispatch(bindingID:binding,recordingID:high.id,revisionID:highVersion.id,stableUTF16End:3)
        Issue.record("Equal-time earlier recording must be deferred regardless of UUID ordering")
    } catch StoreError.lateRecognitionDeferred {}
}

@Test func storeBindingSequenceDistinguishesOldAndNewRecordingsAtSameTimestamp() async throws {
    let f = try DispatchFixture(); defer { f.clean() }
    let date = Date(timeIntervalSince1970:1_793_952_000.1234567)
    let old = try await f.store.createRecording(createdAt:date)
    let binding = try await f.store.createBinding(label:"同时间绑定边界",createdAt:date)
    let new = try await f.store.createRecording(createdAt:date)
    // A capture that started before binding but only registers afterward is old too.
    let delayedOld = try await f.store.createRecording(createdAt:date.addingTimeInterval(-1))
    for record in [old,new,delayedOld] {
        let ticket = try await f.store.beginRecognition(recordingID:record.id)
        try await f.store.applyRecognition(ticket:ticket,text:"稳定稿",isFinal:true)
    }
    #expect(try await f.store.directInputCandidates(bindingID:binding,createdSince:date).map(\.id) == [new.id])
    for record in [old,delayedOld] {
        let revision = try await f.store.latestFinalRevision(recordingID:record.id)!
        do {
            _ = try await f.store.reserveDispatch(bindingID:binding,recordingID:record.id,revisionID:revision.id,stableUTF16End:3)
            Issue.record("Only speech created after the binding boundary may be dispatched")
        } catch StoreError.bindingInvalid {}
    }
    let revision = try await f.store.latestFinalRevision(recordingID:new.id)!
    let dispatch = try await f.store.reserveDispatch(bindingID:binding,recordingID:new.id,revisionID:revision.id,stableUTF16End:3)
    #expect(dispatch?.text == "稳定稿")
    #expect(try await f.store.reserveDispatch(bindingID:binding,recordingID:new.id,revisionID:revision.id,stableUTF16End:3) == nil)
}

@Test func storeDeferredStatusOnlyMarksUndispatchedEarlierFinalSuffix() async throws {
    let f = try DispatchFixture(); defer { f.clean() }
    let binding = try await f.store.createBinding(label:"迟到状态测试")
    let a = try await f.store.createRecording(), aTicket = try await f.store.beginRecognition(recordingID:a.id)
    try await f.store.applyRecognition(ticket:aTicket,text:"完整A",isFinal:true)
    let aFirst = try await f.store.latestFinalRevision(recordingID:a.id)!
    _ = try await f.store.reserveDispatch(bindingID:binding,recordingID:a.id,revisionID:aFirst.id,stableUTF16End:3)
    let b = try await f.store.createRecording(), bTicket = try await f.store.beginRecognition(recordingID:b.id)
    try await f.store.applyRecognition(ticket:bTicket,text:"完整B",isFinal:true)
    let bFinal = try await f.store.latestFinalRevision(recordingID:b.id)!
    _ = try await f.store.reserveDispatch(bindingID:binding,recordingID:b.id,revisionID:bFinal.id,stableUTF16End:3)
    #expect(try await f.store.deferredDirectInputRecordings(bindingID:binding,createdSince:.distantPast).isEmpty)
    try await f.store.applyRecognition(ticket:aTicket,text:"完整A，还有迟到部分",isFinal:true)
    #expect(try await f.store.deferredDirectInputRecordings(bindingID:binding,createdSince:.distantPast) == [a.id])
    try await f.store.invalidateBinding(binding)
    #expect(try await f.store.deferredDirectInputRecordings(bindingID:binding,createdSince:.distantPast).isEmpty)
}
