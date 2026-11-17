import Foundation
import XCTest
@testable import RiftletFeedback

private final class JournalTestSecrets: FeedbackSecretStorage, @unchecked Sendable {
    private let lock = NSLock()
    private var values: [String: String] = [:]
    private var refuseRemoval = false
    func setRemovalFailure(_ value: Bool) { lock.lock(); refuseRemoval = value; lock.unlock() }
    var count: Int { lock.lock(); defer { lock.unlock() }; return values.count }
    func secret(for id: String, create: Bool) throws -> String {
        lock.lock(); defer { lock.unlock() }
        if let secret = values[id] { return secret }
        guard create else { throw FeedbackFailure.secretUnavailable }
        let secret = (UUID().uuidString + UUID().uuidString).replacingOccurrences(of: "-", with: "").lowercased()
        values[id] = secret; return secret
    }
    func remove(for id: String) throws {
        lock.lock(); defer { lock.unlock() }
        guard !refuseRemoval else { throw FeedbackFailure.secretUnavailable }
        values.removeValue(forKey: id)
    }
}
final class FeedbackCredentialIntentTests: XCTestCase {
    private func fixture() throws -> (URL, FeedbackStore, JournalTestSecrets, FeedbackEngine) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("feedback-intents-" + UUID().uuidString)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        let store = try FeedbackStore(directory: root), secrets = JournalTestSecrets()
        return (root, store, secrets, FeedbackEngine(store: store, secrets: secrets, transport: DisabledFeedbackTransport()))
    }
    func testOverlappingSameDraftLeavesOnlyWinningReportCapability() async throws {
        let (_, store, secrets, engine) = try fixture()
        let draft = FeedbackDraft(text: "same deliberate send", revision: 1)
        async let a = engine.enqueue(draft, appVersion: "0.1.0")
        async let b = engine.enqueue(draft, appVersion: "0.1.0")
        let ids = try await [a, b]
        XCTAssertEqual(ids[0], ids[1]); XCTAssertEqual(secrets.count, 1)
        let rows = try await store.records(), abandoned = try await store.uncommittedCredentialIDs()
        XCTAssertEqual(rows.count, 1); XCTAssertTrue(abandoned.isEmpty)
        XCTAssertNoThrow(try secrets.secret(for: ids[0], create: false))
    }
    func testRepeatedCapacityFailuresKeepDraftAndDoNotAccumulateSecrets() async throws {
        let (_, store, secrets, engine) = try fixture()
        for i in 0..<20 {
            _ = try await engine.enqueue(FeedbackDraft(text: "sample-\(i)", revision: Int64(i * 2 + 1)), appVersion: "0.1.0")
        }
        let draft = FeedbackDraft(text: "never evict my failed send", revision: 41)
        for _ in 0..<3 {
            do { _ = try await engine.enqueue(draft, appVersion: "0.1.0"); XCTFail("capacity must refuse") }
            catch FeedbackFailure.capacity {}
        }
        let retained = try await store.draft(), abandoned = try await store.uncommittedCredentialIDs()
        XCTAssertEqual(retained, draft); XCTAssertEqual(secrets.count, 20); XCTAssertTrue(abandoned.isEmpty)
    }
    func testAbandonedCredentialCleanupResumesAfterRestartWithoutTouchingCommittedSecret() async throws {
        let (root, store, secrets, engine) = try fixture()
        let committed = try await engine.enqueue(FeedbackDraft(text: "committed report", revision: 1), appVersion: "0.1.0")
        let token = try secrets.secret(for: committed, create: false)
        let abandonedID = UUID().uuidString.lowercased()
        try await store.registerCredentialIntent(id: abandonedID)
        _ = try secrets.secret(for: abandonedID, create: true)
        // Model a crash between Keychain creation and report commit. Secrets are
        // injected, not a claim that a real Keychain restart was exercised.
        secrets.setRemovalFailure(true); await engine.pump()
        let before = try await store.uncommittedCredentialIDs(); XCTAssertEqual(before, [abandonedID])
        await engine.stop(); try await store.closeForTesting(clean: false)
        let reopened = try FeedbackStore(directory: root)
        let resumed = FeedbackEngine(store: reopened, secrets: secrets, transport: DisabledFeedbackTransport())
        secrets.setRemovalFailure(false); await resumed.pump()
        XCTAssertEqual(secrets.count, 1); XCTAssertEqual(try secrets.secret(for: committed, create: false), token)
        XCTAssertThrowsError(try secrets.secret(for: abandonedID, create: false))
        let after = try await reopened.uncommittedCredentialIDs(), rows = try await reopened.records()
        XCTAssertTrue(after.isEmpty); XCTAssertEqual(rows.map(\.id), [committed])
        await resumed.stop()
    }
}
