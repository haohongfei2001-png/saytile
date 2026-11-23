import Foundation
import XCTest
import CSQLite
@testable import RiftletFeedback

private final class FailingRemovalSecrets: FeedbackSecretStorage, @unchecked Sendable {
    private let memory = MemoryFeedbackSecrets()
    private let lock = NSLock()
    private var shouldFail = false
    func failNextRemoval() { lock.lock(); shouldFail = true; lock.unlock() }
    func secret(for id: String, create: Bool) throws -> String { try memory.secret(for: id, create: create) }
    func remove(for id: String) throws {
        lock.lock(); let fail = shouldFail; shouldFail = false; lock.unlock()
        if fail { throw FeedbackFailure.secretUnavailable }
        try memory.remove(for: id)
    }
}
final class FeedbackPrivacyCleanupTests: XCTestCase {
    private func fixture() throws -> (URL, FeedbackStore, FailingRemovalSecrets, FeedbackEngine) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("feedback-cleanup-" + UUID().uuidString)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        let store = try FeedbackStore(directory: root)
        let secrets = FailingRemovalSecrets()
        return (root, store, secrets, FeedbackEngine(store: store, secrets: secrets, transport: DisabledFeedbackTransport()))
    }
    func testResolvedForgetRemovesOnlyItsCapabilityAndKeepsUnresolvedReport() async throws {
        let (_, store, secrets, engine) = try fixture()
        let removed = try await engine.enqueue(FeedbackDraft(text: "cancelled text", revision: 1), appVersion: "0.1.0")
        let retained = try await engine.enqueue(FeedbackDraft(text: "not yet received", revision: 3), appVersion: "0.1.0")
        let retainedSecret = try secrets.secret(for: retained, create: false)
        try await engine.requestDeletion(id: removed)
        try await engine.forgetResolved(id: removed)
        XCTAssertThrowsError(try secrets.secret(for: removed, create: false))
        XCTAssertEqual(try secrets.secret(for: retained, create: false), retainedSecret)
        let remaining = try await store.records()
        XCTAssertEqual(remaining.map(\.id), [retained])
        do { try await engine.forgetResolved(id: retained); XCTFail("Unresolved records must keep their capability") }
        catch FeedbackFailure.conflict {}
        XCTAssertEqual(try secrets.secret(for: retained, create: false), retainedSecret)
        // Synthetic server receipt: no real cloud or Keychain acceptance claimed.
        try await store.apply(FeedbackReceipt(id: retained, state: "deleted"))
        try await engine.forgetResolved(id: retained)
        XCTAssertThrowsError(try secrets.secret(for: retained, create: false))
        let final = try await store.records(); XCTAssertTrue(final.isEmpty)
    }
    func testKeychainFailurePreservesCleanupRecordAndRetryDoesNotResend() async throws {
        let (_, store, secrets, engine) = try fixture()
        let id = try await engine.enqueue(FeedbackDraft(text: "keep until both removals complete", revision: 1), appVersion: "0.1.0")
        let token = try secrets.secret(for: id, create: false)
        try await engine.requestDeletion(id: id)
        secrets.failNextRemoval()
        do { try await engine.forgetResolved(id: id); XCTFail("Removal failure must be visible") }
        catch FeedbackFailure.secretUnavailable {}
        let retained = try await store.records()
        XCTAssertEqual(retained.first?.state, .cancelled)
        XCTAssertEqual(retained.first?.attempts, 0)
        XCTAssertEqual(try secrets.secret(for: id, create: false), token)
        try await engine.forgetResolved(id: id)
        let final = try await store.records(); XCTAssertTrue(final.isEmpty)
        XCTAssertThrowsError(try secrets.secret(for: id, create: false))
    }
    func testSQLiteFailureAfterCapabilityRemovalCanResumeWithoutRecreatingSecret() async throws {
        let (root, store, secrets, engine) = try fixture()
        let id = try await engine.enqueue(FeedbackDraft(text: "recoverable cleanup", revision: 1), appVersion: "0.1.0")
        try await engine.requestDeletion(id: id)
        var db: OpaquePointer?
        XCTAssertEqual(sqlite3_open(root.appendingPathComponent("feedback.sqlite").path, &db), SQLITE_OK)
        defer { sqlite3_close(db) }
        XCTAssertEqual(sqlite3_exec(db, "CREATE TRIGGER deny_forget BEFORE DELETE ON reports BEGIN SELECT RAISE(ABORT,'injected'); END", nil, nil, nil), SQLITE_OK)
        do { try await engine.forgetResolved(id: id); XCTFail("Transaction failed") }
        catch FeedbackFailure.storageUnavailable {}
        XCTAssertThrowsError(try secrets.secret(for: id, create: false))
        let retained = try await store.records(); XCTAssertEqual(retained.first?.state, .cancelled)
        XCTAssertEqual(sqlite3_exec(db, "DROP TRIGGER deny_forget", nil, nil, nil), SQLITE_OK)
        try await engine.forgetResolved(id: id)
        let final = try await store.records(); XCTAssertTrue(final.isEmpty)
        XCTAssertThrowsError(try secrets.secret(for: id, create: false))
    }

    func testForgottenBodyIsScrubbedFromLiveDatabaseWithoutRemovingOtherFeedback() async throws {
        let (root, store, secrets, engine) = try fixture()
        let marker = "ERASE-FEEDBACK-" + UUID().uuidString
        let removed = try await engine.enqueue(FeedbackDraft(text: String(repeating: marker, count: 40), revision: 1), appVersion: "0.1.0")
        let retained = try await engine.enqueue(FeedbackDraft(text: "keep this separate report", revision: 3), appVersion: "0.1.0")
        let database = root.appendingPathComponent("feedback.sqlite")
        XCTAssertNotNil(try Data(contentsOf: database).range(of: Data(marker.utf8)))
        try await engine.requestDeletion(id: removed)
        try await engine.forgetResolved(id: removed)
        XCTAssertNil(try Data(contentsOf: database).range(of: Data(marker.utf8)))
        XCTAssertThrowsError(try secrets.secret(for: removed, create: false))
        let remaining = try await store.records()
        XCTAssertEqual(remaining.map(\.id), [retained])
        XCTAssertEqual(remaining.first?.envelope.text, "keep this separate report")
        await engine.stop()
    }
}
