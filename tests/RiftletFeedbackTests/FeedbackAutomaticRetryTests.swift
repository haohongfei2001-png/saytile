import Foundation
import XCTest
@testable import RiftletFeedback

private actor AutomaticallyRetryingTransport: FeedbackTransport {
    nonisolated let configured = true
    private var retrySubmit: Bool
    private var retryDelete: Bool
    private(set) var submissions: [(Data, String)] = []
    private(set) var deletions: [String] = []
    private(set) var cancelledCalls = 0

    init(retrySubmit: Bool, retryDelete: Bool) {
        self.retrySubmit = retrySubmit; self.retryDelete = retryDelete
    }
    func perform(_ action: FeedbackRequest, record: FeedbackRecord, secret: String) async throws -> FeedbackReceipt {
        if Task.isCancelled { cancelledCalls += 1 }
        try Task.checkCancellation()
        switch action {
        case .submit:
            submissions.append((record.bytes, secret))
            if retrySubmit { retrySubmit = false; throw FeedbackFailure.rateLimited(1) }
            return FeedbackReceipt(id: record.id)
        case .delete:
            deletions.append(secret)
            if retryDelete { retryDelete = false; throw FeedbackFailure.rateLimited(1) }
            return FeedbackReceipt(id: record.id, state: "deleted")
        case .status: return FeedbackReceipt(id: record.id)
        }
    }
}

final class FeedbackAutomaticRetryTests: XCTestCase {
    private func fixture(retrySubmit: Bool, retryDelete: Bool) throws -> (FeedbackStore, AutomaticallyRetryingTransport, FeedbackEngine) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("feedback-auto-retry-" + UUID().uuidString)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        let store = try FeedbackStore(directory: root)
        let transport = AutomaticallyRetryingTransport(retrySubmit: retrySubmit, retryDelete: retryDelete)
        return (store, transport, FeedbackEngine(store: store, secrets: MemoryFeedbackSecrets(), transport: transport))
    }
    private func waitForState(_ expected: FeedbackLocalState, store: FeedbackStore) async throws -> [FeedbackRecord] {
        let deadline = Date().addingTimeInterval(4)
        var records = try await store.records()
        while records.first?.state != expected && Date() < deadline {
            try await Task.sleep(nanoseconds: 20_000_000)
            records = try await store.records()
        }
        return records
    }
    func testTimerRetriesWithoutAnotherUserActionAndPreservesEnvelopeAndCredential() async throws {
        let (store, transport, engine) = try fixture(retrySubmit: true, retryDelete: false)
        let id = try await engine.enqueue(FeedbackDraft(text: "自动重试不能取消自己", revision: 1), appVersion: "0.1.0")
        await engine.pump()
        // No second pump, refresh or app restart: the actual timer must recover.
        let records = try await waitForState(.received, store: store)
        let calls = await transport.submissions, cancelled = await transport.cancelledCalls
        XCTAssertEqual(records.count, 1); XCTAssertEqual(records.first?.id, id)
        XCTAssertEqual(records.first?.state, .received); XCTAssertEqual(calls.count, 2)
        if calls.count == 2 {
            XCTAssertEqual(calls[0].0, calls[1].0); XCTAssertEqual(calls[0].1, calls[1].1)
        }
        XCTAssertEqual(cancelled, 0)
        await engine.stop()
    }
    func testTimerRetriesDeletionWithoutResendingBody() async throws {
        let (store, transport, engine) = try fixture(retrySubmit: false, retryDelete: true)
        let id = try await engine.enqueue(FeedbackDraft(text: "删除恢复不得重发正文", revision: 1), appVersion: "0.1.0")
        await engine.pump()
        try await engine.requestDeletion(id: id)
        let records = try await waitForState(.deleted, store: store)
        let posts = await transport.submissions, deletes = await transport.deletions
        let cancelled = await transport.cancelledCalls
        XCTAssertEqual(records.first?.state, .deleted); XCTAssertEqual(posts.count, 1)
        XCTAssertEqual(deletes.count, 2); XCTAssertEqual(cancelled, 0)
        if deletes.count == 2 { XCTAssertEqual(deletes[0], deletes[1]) }
        await engine.stop()
    }
    func testStopPreventsScheduledRetryFromDispatching() async throws {
        let (store, transport, engine) = try fixture(retrySubmit: true, retryDelete: false)
        _ = try await engine.enqueue(FeedbackDraft(text: "退出后保留待发送", revision: 1), appVersion: "0.1.0")
        await engine.pump(); await engine.stop()
        try await Task.sleep(nanoseconds: 1_200_000_000)
        let records = try await store.records(), calls = await transport.submissions
        XCTAssertEqual(calls.count, 1); XCTAssertEqual(records.first?.state, .queued)
    }
}
