import Foundation
import XCTest
import CSQLite
@testable import RiftletFeedback

final class FeedbackDurabilityTests: XCTestCase {
    private func fixture() throws -> (URL, FeedbackStore, FeedbackEngine) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("feedback-durable-" + UUID().uuidString)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        let store = try FeedbackStore(directory: root)
        return (root, store, FeedbackEngine(store: store, secrets: MemoryFeedbackSecrets(), transport: DisabledFeedbackTransport()))
    }
    private func execute(_ sql: String, in root: URL) throws {
        var db: OpaquePointer?
        guard sqlite3_open(root.appendingPathComponent("feedback.sqlite").path, &db) == SQLITE_OK else { throw FeedbackFailure.storageUnavailable }
        defer { sqlite3_close(db) }
        guard sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK else { throw FeedbackFailure.storageUnavailable }
    }
    func testActualInsertFailureRollsBackSubmissionAndKeepsLatestDraft() async throws {
        let (root, store, engine) = try fixture()
        try execute("CREATE TRIGGER reject_feedback BEFORE INSERT ON reports BEGIN SELECT RAISE(ABORT,'injected'); END;", in: root)
        let draft = FeedbackDraft(text: "SQLite 写入失败也保留的文字", revision: 1)
        do { _ = try await engine.enqueue(draft, appVersion: "0.1.0"); XCTFail("must reject") }
        catch FeedbackFailure.storageUnavailable {}
        let retained = try await store.draft(), rows = try await store.records()
        let submitted = try await store.submittedID(revision: 1)
        XCTAssertEqual(retained, draft); XCTAssertTrue(rows.isEmpty); XCTAssertNil(submitted)
        try execute("DROP TRIGGER reject_feedback", in: root)
        _ = try await engine.enqueue(draft, appVersion: "0.1.0")
        let recovered = try await store.records(); XCTAssertEqual(recovered.count, 1)
        XCTAssertEqual(recovered.first?.envelope.text, draft.text)
    }
    func testOutboxCapacityNeverEvictsTextAndKeepsTheNewDraft() async throws {
        let (_, store, engine) = try fixture()
        for i in 0..<20 {
            _ = try await engine.enqueue(FeedbackDraft(text: "synthetic-\(i)", revision: Int64(i * 2 + 1)), appVersion: "0.1.0")
        }
        let overflow = FeedbackDraft(text: "第二十一份必须保留为草稿", revision: 41)
        do { _ = try await engine.enqueue(overflow, appVersion: "0.1.0"); XCTFail("must refuse rather than evict") }
        catch FeedbackFailure.capacity {}
        let rows = try await store.records(), retained = try await store.draft()
        XCTAssertEqual(rows.count, 20); XCTAssertEqual(retained, overflow)
        XCTAssertEqual(Set(rows.map(\.envelope.text)), Set((0..<20).map { "synthetic-\($0)" }))
    }
    func testReadFailureDoesNotMasqueradeAsMissingIdempotencyRecord() async throws {
        let (root, store, _) = try fixture()
        try execute("DROP TABLE submissions", in: root)
        do { _ = try await store.submittedID(revision: 1); XCTFail("must report storage failure") }
        catch FeedbackFailure.storageUnavailable {}
    }
    func testSidecarAndLockHavePrivatePermissions() async throws {
        let (root, store, _) = try fixture()
        for (path, wanted) in [(root.path, 0o700), (root.appendingPathComponent("feedback.sqlite").path, 0o600), (root.appendingPathComponent("feedback.lock").path, 0o600)] {
            let attrs = try FileManager.default.attributesOfItem(atPath: path)
            XCTAssertEqual((attrs[.posixPermissions] as? NSNumber)?.intValue, wanted)
        }
        try await store.closeForTesting(clean: true)
    }
}
