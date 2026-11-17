import XCTest
import Foundation
import CSQLite
@testable import RiftletFeedback

private actor ScriptedTransport: FeedbackTransport {
    nonisolated let configured = true
    var calls: [Data] = []
    var tokens: [String] = []
    var failFirst = false
    var wrongReceipt = false
    func configure(fail: Bool = false, wrong: Bool = false) { failFirst=fail;wrongReceipt=wrong }
    func perform(_ action:FeedbackRequest,record:FeedbackRecord,secret:String) async throws -> FeedbackReceipt {
        calls.append(record.bytes);tokens.append(secret)
        if failFirst { failFirst=false;throw FeedbackFailure.transport }
        return FeedbackReceipt(id: wrongReceipt ? UUID().uuidString.lowercased() : record.id)
    }
}
final class FeedbackTests: XCTestCase {
    func directory() throws -> URL {
        let url=FileManager.default.temporaryDirectory.appendingPathComponent("feedback-tests-"+UUID().uuidString)
        try FileManager.default.createDirectory(at:url,withIntermediateDirectories:true)
        addTeardownBlock {try? FileManager.default.removeItem(at:url)}
        return url
    }
    func testDiagnosticAllowlistIsBoundedAndKeepsVisibilityUnknownAndSuccessDistinct() throws {
        let diagnostics=FeedbackDiagnostics()
        for _ in 0..<100 { diagnostics.record(.queueUnknown) }
        diagnostics.record(.visibilitySwallowed);diagnostics.record(.phaseSucceeded)
        let snapshot=diagnostics.snapshot();XCTAssertEqual(snapshot.events.count,64);XCTAssertEqual(snapshot.dropped,38)
        let json=try snapshot.preview();XCTAssertTrue(json.contains("queueUnknown"));XCTAssertTrue(json.contains("visibilitySwallowed"));XCTAssertTrue(json.contains("phaseSucceeded"))
        for excluded in ["assetID","operationID","sha256","path","url","clipboard","target"] {XCTAssertFalse(json.contains(excluded))}
    }
    func testDraftCloseRestartRevisionAndConsentSnapshot() async throws {
        let url=try directory();let store=try FeedbackStore(directory:url)
        let draft=FeedbackDraft(text:"第一行\n第二行秘密只来自用户正文",diagnostic:FeedbackDiagnostic(events:[FeedbackEvent(.queueUnknown)]),revision:2)
        try await store.saveDraft(draft)
        try await store.saveDraft(FeedbackDraft(text:"旧的异步回调",revision:1))
        let saved=try await store.draft();XCTAssertEqual(saved,draft)
        try await store.closeForTesting(clean:true)
        let reopened=try FeedbackStore(directory:url);let restored=try await reopened.draft()
        XCTAssertEqual(restored,draft);XCTAssertFalse(reopened.wasUnclean)
    }
    func testEnqueueIsAtomicFrozenAndIdempotentForOneDraft() async throws {
        let store=try FeedbackStore(directory:directory());let secrets=MemoryFeedbackSecrets()
        let engine=FeedbackEngine(store:store,secrets:secrets,transport:DisabledFeedbackTransport())
        let draft=FeedbackDraft(text:"a\n\u{0000}b",revision:1)
        async let first=engine.enqueue(draft,appVersion:"0.1.0")
        async let second=engine.enqueue(draft,appVersion:"0.1.0")
        let ids=try await [first,second];XCTAssertEqual(ids[0],ids[1])
        let records=try await store.records();XCTAssertEqual(records.count,1);XCTAssertEqual(records[0].envelope.text,draft.text)
        let empty=try await store.draft();XCTAssertEqual(empty.text,"");XCTAssertNil(empty.diagnostic)
        await engine.pump();let after=try await store.records();XCTAssertEqual(after[0].attempts,0)
        await engine.stop()
    }
    func testNetworkLossRetriesExactFrozenBytesAndSecretWithoutDuplicateReport() async throws {
        let store=try FeedbackStore(directory:directory());let transport=ScriptedTransport();await transport.configure(fail:true)
        let engine=FeedbackEngine(store:store,secrets:MemoryFeedbackSecrets(),transport:transport)
        let id=try await engine.enqueue(FeedbackDraft(text:"网络中断不能丢文字",revision:1),appVersion:"0.1.0")
        await engine.pump();var records=try await store.records();XCTAssertEqual(records[0].state,.queued)
        try await store.reschedule(id:id,expected:.queued,after:1)
        try await Task.sleep(nanoseconds:1_100_000_000)
        await engine.pump();records=try await store.records()
        XCTAssertEqual(records.count,1);XCTAssertEqual(records[0].state,.received)
        let calls=await transport.calls;let tokens=await transport.tokens
        XCTAssertEqual(calls.count,2);XCTAssertEqual(calls[0],calls[1]);XCTAssertEqual(tokens[0],tokens[1])
        await engine.stop()
    }
    func testWrongOrNonDurableReceiptCannotAnnounceSuccess() async throws {
        XCTAssertThrowsError(try FeedbackReceipt(id:"x",durable:false).validate(for:"x"))
        let store=try FeedbackStore(directory:directory());let transport=ScriptedTransport();await transport.configure(wrong:true)
        let engine=FeedbackEngine(store:store,secrets:MemoryFeedbackSecrets(),transport:transport)
        _=try await engine.enqueue(FeedbackDraft(text:"must remain queued",revision:1),appVersion:"0.1.0")
        await engine.pump();let records=try await store.records();XCTAssertEqual(records[0].state,.queued)
        await engine.stop()
    }
    func testDeletionWinsLateReceiptAndUnattemptedCancellationNeedsNoNetwork() async throws {
        let store=try FeedbackStore(directory:directory());let engine=FeedbackEngine(store:store,secrets:MemoryFeedbackSecrets(),transport:DisabledFeedbackTransport())
        let id=try await engine.enqueue(FeedbackDraft(text:"retain my text",revision:1),appVersion:"0.1.0")
        _=try await store.beginAttempt(id:id,expected:.queued)
        try await store.requestDeletion(id:id);try await store.apply(FeedbackReceipt(id:id))
        var records=try await store.records();XCTAssertEqual(records[0].state,.deletionQueued)
        try await store.apply(FeedbackReceipt(id:id,state:"deletion_pending"));records=try await store.records()
        XCTAssertEqual(records[0].state,.deletionPending);XCTAssertEqual(records[0].envelope.text,"retain my text")
        let id2=try await engine.enqueue(FeedbackDraft(text:"never submit",revision:3),appVersion:"0.1.0")
        try await store.requestDeletion(id:id2);records=try await store.records();XCTAssertEqual(records.first{$0.id==id2}?.state,.cancelled)
    }
    func testMissingKeychainCapabilityCannotBeReplacedOnRetry() async throws {
        let url=try directory();let store=try FeedbackStore(directory:url)
        let original=FeedbackEngine(store:store,secrets:MemoryFeedbackSecrets(),transport:DisabledFeedbackTransport())
        _=try await original.enqueue(FeedbackDraft(text:"original credential required",revision:1),appVersion:"0.1.0")
        let transport=ScriptedTransport();let restart=FeedbackEngine(store:store,secrets:MemoryFeedbackSecrets(),transport:transport)
        await restart.pump();let calls=await transport.calls;XCTAssertEqual(calls.count,0)
        let records=try await store.records();XCTAssertEqual(records[0].state,.blocked)
        XCTAssertEqual(records[0].attempts,0)
        // The missing capability must not strand text that was never sent.
        try await restart.requestDeletion(id:records[0].id)
        let cancelled=try await store.records();XCTAssertEqual(cancelled[0].state,.cancelled)
        try await restart.forgetResolved(id:records[0].id)
        let remaining=try await store.records(),afterCalls=await transport.calls
        XCTAssertTrue(remaining.isEmpty);XCTAssertTrue(afterCalls.isEmpty)
        await restart.stop()
    }
    func testMissingCredentialAfterAttemptCannotBeLocallyCancelled() async throws {
        let store=try FeedbackStore(directory:directory())
        let original=FeedbackEngine(store:store,secrets:MemoryFeedbackSecrets(),transport:DisabledFeedbackTransport())
        let id=try await original.enqueue(FeedbackDraft(text:"old request may have reached server",revision:1),appVersion:"0.1.0")
        _=try await store.beginAttempt(id:id,expected:.queued)
        let transport=ScriptedTransport()
        let restart=FeedbackEngine(store:store,secrets:MemoryFeedbackSecrets(),transport:transport)
        await restart.pump()
        try await restart.requestDeletion(id:id)
        let records=try await store.records(),calls=await transport.calls
        XCTAssertEqual(records.first?.state,.deletionBlocked)
        XCTAssertEqual(records.first?.attempts,1);XCTAssertTrue(calls.isEmpty)
        do { try await restart.forgetResolved(id:id);XCTFail("Cloud obligation must remain") }
        catch FeedbackFailure.conflict {}
        await restart.stop()
    }
    func testStoreLocksAndFutureSchemaCannotTouchScreenshotDatabase() async throws {
        let url=try directory();let sentinel=url.appendingPathComponent("queue.sqlite")
        try Data("untouched core".utf8).write(to:sentinel)
        let store=try FeedbackStore(directory:url)
        XCTAssertThrowsError(try FeedbackStore(directory:url))
        try await store.closeForTesting(clean:false)
        var db:OpaquePointer?;sqlite3_open(url.appendingPathComponent("feedback.sqlite").path,&db)
        sqlite3_exec(db,"PRAGMA user_version=99",nil,nil,nil);sqlite3_close(db)
        XCTAssertThrowsError(try FeedbackStore(directory:url))
        XCTAssertEqual(try Data(contentsOf:sentinel),Data("untouched core".utf8))
    }
    func testUncleanSessionIsNotDeclaredACrashAndSubmissionBoundsPreserveDraft() async throws {
        let url=try directory();let store=try FeedbackStore(directory:url)
        let long=FeedbackDraft(text:String(repeating:"字",count:4001),revision:1)
        try await store.saveDraft(long)
        XCTAssertThrowsError(try FeedbackEnvelope(draft:long,appVersion:"secret/path"))
        try await store.closeForTesting(clean:false)
        let next=try FeedbackStore(directory:url);XCTAssertTrue(next.wasUnclean)
        let saved=try await next.draft();XCTAssertEqual(saved.text,long.text)
    }
    func testEndpointRejectsHTTPSecretsAndQueryAndUnknownDiagnostics() throws {
        for value in ["http://feedback.test/v1/feedback","https://a:b@feedback.test/v1/feedback","https://feedback.test/v1/feedback?key=x","https://feedback.test/wrong"] {XCTAssertThrowsError(try HTTPSFeedbackTransport(endpoint:URL(string:value)!))}
        let malicious=Data(#"{"schema":1,"coverage":"session-sampled-v1","dropped":0,"events":[{"fact":"rawPath","count":1}]}"#.utf8)
        XCTAssertThrowsError(try JSONDecoder().decode(FeedbackDiagnostic.self,from:malicious))
    }
}
