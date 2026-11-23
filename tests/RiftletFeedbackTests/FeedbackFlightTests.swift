import Foundation
import XCTest
@testable import RiftletFeedback

private actor HeldStatusTransport: FeedbackTransport {
    nonisolated let configured = true
    private var held: CheckedContinuation<FeedbackReceipt, Error>?
    private var entered: CheckedContinuation<Void, Never>?
    private var originalID = ""
    private(set) var submissions = 0
    private(set) var deletions = 0
    func perform(_ action: FeedbackRequest, record: FeedbackRecord, secret: String) async throws -> FeedbackReceipt {
        switch action {
        case .submit: submissions += 1; return FeedbackReceipt(id: record.id)
        case .delete: deletions += 1; return FeedbackReceipt(id: record.id, state: "deleted")
        case .status:
            originalID = record.id
            return try await withCheckedThrowingContinuation { continuation in
                held = continuation; entered?.resume(); entered = nil
            }
        }
    }
    func waitForStatus() async {
        if held != nil { return }
        await withCheckedContinuation { entered = $0 }
    }
    func release(failed: Bool = false) {
        let continuation = held; held = nil
        if failed { continuation?.resume(throwing: FeedbackFailure.transport) }
        else { continuation?.resume(returning: FeedbackReceipt(id: originalID)) }
    }
}

final class FeedbackFlightTests: XCTestCase {
    private func fixture() throws -> (FeedbackStore, HeldStatusTransport, FeedbackEngine) {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("feedback-flight-" + UUID().uuidString)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let store = try FeedbackStore(directory: directory)
        let transport = HeldStatusTransport()
        return (store, transport, FeedbackEngine(store: store, secrets: MemoryFeedbackSecrets(), transport: transport))
    }
    func testDeletionDuringStatusAutomaticallyDrainsAfterSuccessAndError() async throws {
        for failed in [false, true] {
            let (store, transport, engine) = try fixture()
            let id = try await engine.enqueue(FeedbackDraft(text: "delete while status is suspended", revision: 1), appVersion: "0.1.0")
            await engine.pump()
            let refresh = Task { try await engine.refresh(id: id) }
            await transport.waitForStatus()
            try await engine.requestDeletion(id: id)
            let pending = try await store.records(); XCTAssertEqual(pending.first?.state, .deletionQueued)
            await transport.release(failed: failed)
            do { try await refresh.value; XCTAssertFalse(failed) }
            catch { XCTAssertTrue(failed) }
            let records = try await store.records()
            let posts = await transport.submissions, deletes = await transport.deletions
            XCTAssertEqual(records.first?.state, .deleted); XCTAssertEqual(posts, 1); XCTAssertEqual(deletes, 1)
            await engine.stop()
        }
    }
    func testNewFrozenSubmissionDuringStatusIsNotStranded() async throws {
        let (store, transport, engine) = try fixture()
        let id = try await engine.enqueue(FeedbackDraft(text: "first", revision: 1), appVersion: "0.1.0")
        await engine.pump()
        let refresh = Task { try await engine.refresh(id: id) }
        await transport.waitForStatus()
        _ = try await engine.enqueue(FeedbackDraft(text: "second", revision: 3), appVersion: "0.1.0")
        await engine.pump()
        await transport.release(); try await refresh.value
        let records = try await store.records(), posts = await transport.submissions
        XCTAssertEqual(posts, 2); XCTAssertEqual(records.count, 2)
        XCTAssertTrue(records.allSatisfy { $0.state == .received })
        await engine.stop()
    }
    func testStopDuringStatusDoesNotDispatchQueuedDeletion() async throws {
        let (store, transport, engine) = try fixture()
        let id = try await engine.enqueue(FeedbackDraft(text: "stop before follow-up", revision: 1), appVersion: "0.1.0")
        await engine.pump()
        let refresh = Task { try await engine.refresh(id: id) }
        await transport.waitForStatus(); try await engine.requestDeletion(id: id)
        await engine.stop(); await transport.release(); try await refresh.value
        let records = try await store.records(), deletes = await transport.deletions
        XCTAssertEqual(deletes, 0); XCTAssertEqual(records.first?.state, .deletionQueued)
    }
    func testLateExpiryOrDeliveryCannotEraseDeletionIntentOrReviveDeletedRecord() async throws {
        let (store, _, engine) = try fixture()
        let id = try await engine.enqueue(FeedbackDraft(text: "retain deletion", revision: 1), appVersion: "0.1.0")
        _ = try await store.beginAttempt(id: id, expected: .queued)
        try await store.requestDeletion(id: id)
        try await store.reschedule(id: id, expected: .deletionQueued, after: 1, blocked: true)
        for state in ["received", "delivered", "delivery_expired"] {
            try await store.apply(FeedbackReceipt(id: id, state: state))
            let records = try await store.records(); XCTAssertEqual(records.first?.state, .deletionBlocked)
        }
        try await store.apply(FeedbackReceipt(id: id, state: "deleted"))
        try await store.apply(FeedbackReceipt(id: id, state: "deletion_pending"))
        let records = try await store.records(); XCTAssertEqual(records.first?.state, .deleted)
        await engine.stop()
    }
    func testDanglingSidecarSymlinkRefusesWithoutCreatingItsDestination() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let destination = root.appendingPathComponent("do-not-create")
        try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("feedback.sqlite-journal"), withDestinationURL: destination)
        XCTAssertThrowsError(try FeedbackStore(directory: root))
        XCTAssertFalse(FileManager.default.fileExists(atPath: destination.path))
    }
}
