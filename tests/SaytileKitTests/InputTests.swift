import Foundation
import Testing
@testable import SaytileKit

@Suite("Input identity and safety")
struct InputPolicyTests {
    @Test func testnoSelectedReplacement() throws {
        var snapshot = sampleTarget()
        snapshot.selectionLength = 3
        #expect(throws: NativeInputError.self) { try snapshot.checked() }
    }
    @Test func testunidentifiableWebPageRejected() throws {
        var snapshot = sampleTarget()
        snapshot.isWeb = true
        snapshot.pageIdentity = nil
        #expect(throws: NativeInputError.self) { try snapshot.checked() }
    }
    @Test func testreusedEditorDoesNotMakeSamePage() {
        let old = sampleTarget()
        var new = old
        new.pageIdentity = "https://example.test/conversation/new"
        #expect(!new.sameTarget(as: old))
    }
    @Test func testcursorMovementMakesBindingStale() {
        let old = sampleTarget()
        var new = old
        new.selectionLocation += 1
        #expect(new.sameTarget(as: old))
        #expect(new != old)
    }
    @Test func testpasswordsTerminalsAndEmbeddedTerminalBlocked() {
        #expect(InputSafetyPolicy.isSensitive(applicationID: "com.apple.Terminal", role: "AXTextArea", subrole: "", description: "", identifier: ""))
        #expect(InputSafetyPolicy.isSensitive(applicationID: "com.example.editor", role: "AXTextArea", subrole: "AXSecureTextField", description: "", identifier: ""))
        #expect(InputSafetyPolicy.isSensitive(applicationID: "com.microsoft.VSCode", role: "AXTextArea", subrole: "", description: "", identifier: "terminal-input"))
        #expect(!InputSafetyPolicy.isSensitive(applicationID: "com.apple.TextEdit", role: "AXTextArea", subrole: "", description: "text area", identifier: ""))
    }
}

@MainActor
private final class FakeInputAccess: InputAccess {
    var hasPermission = true
    var target = sampleTarget()
    var attempts: [String] = []
    var confirms = true
    var throwsAfterAttempt = false
    func snapshot() throws -> InputTargetSnapshot { target }
    func dispatch(_ text: String, to expected: InputTargetSnapshot) throws -> Bool {
        guard target == expected else { return false }
        attempts.append(text)
        target.selectionLocation += text.utf16.count
        if throwsAfterAttempt { throw NativeInputError.unsupported }
        return true
    }
    func verify(_ text: String, at before: InputTargetSnapshot) -> InputTargetSnapshot? { confirms ? target : nil }
}

@Suite("Input coordinator with isolated SQLite and simulated OS")
@MainActor
struct InputCoordinatorTests {
    @Test func teststableSuffixOnlyOnce() async throws {
        let directory = testDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try SaytileStore(directory: directory)
        let access = FakeInputAccess()
        let coordinator = NativeInputCoordinator(store: store, access: access)
        let binding = try await coordinator.bindCurrentTarget()
        let record = try await store.createRecording(createdAt: binding.boundAt.addingTimeInterval(1))
        let first = try await store.saveEdit(recordingID: record.id, text: "你好")
        #expect(await coordinator.insertStable(recordingID: record.id, revisionID: first.id, stableUTF16End: 2, recordingStartedAt: record.createdAt) == .confirmed)
        let second = try await store.saveEdit(recordingID: record.id, text: "你好，世界😀")
        #expect(await coordinator.insertStable(recordingID: record.id, revisionID: second.id, stableUTF16End: 7, recordingStartedAt: record.createdAt) == .confirmed)
        #expect(await coordinator.insertStable(recordingID: record.id, revisionID: second.id, stableUTF16End: 7, recordingStartedAt: record.createdAt) == .noNewText)
        #expect(access.attempts == ["你好", "，世界😀"])
    }

    @Test func testexistingSpeechNeverAutomaticallyReplayed() async throws {
        let directory = testDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try SaytileStore(directory: directory)
        let record = try await store.createRecording(createdAt: .distantPast)
        let revision = try await store.saveEdit(recordingID: record.id, text: "历史")
        let access = FakeInputAccess()
        let coordinator = NativeInputCoordinator(store: store, access: access)
        try await coordinator.bindCurrentTarget()
        #expect(await coordinator.insertStable(recordingID: record.id, revisionID: revision.id, stableUTF16End: 2, recordingStartedAt: record.createdAt) == .noNewText)
        #expect(access.attempts.isEmpty)
    }

    @Test func testchangedPageStopsBeforeDispatch() async throws {
        let directory = testDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try SaytileStore(directory: directory)
        let access = FakeInputAccess()
        let coordinator = NativeInputCoordinator(store: store, access: access)
        try await coordinator.bindCurrentTarget()
        let record = try await store.createRecording()
        let revision = try await store.saveEdit(recordingID: record.id, text: "原页面文字")
        access.target.pageIdentity = "https://example.test/new-chat"
        _ = await coordinator.insert(recordingID: record.id, revisionID: revision.id)
        #expect(access.attempts.isEmpty)
        #expect(coordinator.binding == nil)
    }

    @Test func testuncertainDeliveryDoesNotReplayOrBlockNewSpeech() async throws {
        let directory = testDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try SaytileStore(directory: directory)
        let access = FakeInputAccess()
        access.confirms = false
        let coordinator = NativeInputCoordinator(store: store, access: access)
        let binding = try await coordinator.bindCurrentTarget()
        let record = try await store.createRecording(createdAt: binding.boundAt.addingTimeInterval(1))
        let revision = try await store.saveEdit(recordingID: record.id, text: "第一段")
        #expect(await coordinator.insertStable(recordingID: record.id, revisionID: revision.id, stableUTF16End: 3, recordingStartedAt: record.createdAt) == .unverified)
        #expect(await coordinator.insertStable(recordingID: record.id, revisionID: revision.id, stableUTF16End: 3, recordingStartedAt: record.createdAt) == .noNewText)
        let next = try await store.createRecording(createdAt: binding.boundAt.addingTimeInterval(2))
        let nextRevision = try await store.saveEdit(recordingID: next.id, text: "第二段")
        #expect(await coordinator.insertStable(recordingID: next.id, revisionID: nextRevision.id, stableUTF16End: 3, recordingStartedAt: next.createdAt) == .unverified)
        #expect(access.attempts == ["第一段", "第二段"])
    }

    @Test func testtimeoutIsUncertainAndNeverRetried() async throws {
        let directory = testDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try SaytileStore(directory: directory)
        let access = FakeInputAccess()
        access.throwsAfterAttempt = true
        let coordinator = NativeInputCoordinator(store: store, access: access)
        try await coordinator.bindCurrentTarget()
        let record = try await store.createRecording()
        let revision = try await store.saveEdit(recordingID: record.id, text: "一次")
        #expect(await coordinator.insert(recordingID: record.id, revisionID: revision.id) == .unverified)
        #expect(await coordinator.insert(recordingID: record.id, revisionID: revision.id) == .cancelled)
        #expect(access.attempts == ["一次"])
    }

    @Test func testunavailablePermissionHasNoPromptOrSideEffect() async throws {
        let directory = testDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try SaytileStore(directory: directory)
        let access = FakeInputAccess()
        access.hasPermission = false
        let coordinator = NativeInputCoordinator(store: store, access: access)
        do {
            try await coordinator.bindCurrentTarget()
            Issue.record("Expected missing permission")
        } catch { #expect(error is NativeInputError) }
        #expect(access.attempts.isEmpty)
    }
}

private func sampleTarget() -> InputTargetSnapshot {
    InputTargetSnapshot(processID: 123456, applicationID: "com.example.fixture", applicationName: "Synthetic Fixture",
                        windowID: UUID(), elementID: UUID(), pageIdentity: "https://example.test/chat/one",
                        selectionLocation: 4, selectionLength: 0, isWeb: false,
                        isEditable: true, isSensitive: false, canSetSelectedText: true)
}
private func testDirectory() -> URL {
    FileManager.default.temporaryDirectory.appendingPathComponent("Saytile-input-tests-" + UUID().uuidString)
}
