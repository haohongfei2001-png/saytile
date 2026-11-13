import Foundation
import AppKit
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
    var fieldWitness: String?
    func textWitness(at expected: InputTargetSnapshot) -> String? { expected == target ? fieldWitness : nil }
    var confirms = true
    var timesOutAfterTextWrite = false
    var throwsAfterAttempt = false
    var confirmationsToDelay = 0
    var localTextMatches: Bool? = true
    var afterDispatch: (@MainActor () -> Void)?
    var observedSupport = InputObservationSupport(focus: true, content: true, page: true)
    var onChange: (@MainActor (InputTargetChange) -> Void)?
    var onSnapshot: (@MainActor () throws -> Void)?
    func snapshot() throws -> InputTargetSnapshot { try onSnapshot?(); return target }
    func matchesText(_ text: String, utf16Start: Int, at expected: InputTargetSnapshot) -> Bool? { localTextMatches }
    func observe(_ expected: InputTargetSnapshot, onChange: @escaping @MainActor (InputTargetChange) -> Void) -> InputObservationSupport { self.onChange = onChange; return observedSupport }
    func stopObserving() { onChange = nil }
    func dispatch(_ text: String, to expected: InputTargetSnapshot) throws -> Bool {
        guard target == expected else { return false }
        attempts.append(text)
        target.selectionLocation += text.utf16.count
        afterDispatch?()
        if timesOutAfterTextWrite { throw AXTextWriteTimeout() }
        if throwsAfterAttempt { throw NativeInputError.unsupported }
        return true
    }
    func verify(_ text: String, at before: InputTargetSnapshot) -> InputTargetSnapshot? {
        if confirmationsToDelay > 0 { confirmationsToDelay -= 1; return nil }
        return confirms ? target : nil
    }
}

@Suite("Input coordinator with isolated SQLite and simulated OS")
@MainActor
struct InputCoordinatorTests {
    @Test(arguments: ["restored", "persistent", "late-focus", "observed-edit", "bad-caret", "field-changed"])
    func uncertainWebReadbackNeedsTwoSubsequentFullWitnesses(_ scenario: String) async throws {
        let directory = testDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try SaytileStore(directory: directory), access = FakeInputAccess()
        access.target.isWeb = true
        access.target.selectionLocation = 2
        access.fieldWitness = "abz"
        let input = NativeInputCoordinator(store: store, access: access)
        try await input.bindCurrentTarget()
        let record = try await store.createRecording()
        let revision = try await store.saveEdit(recordingID: record.id, text: "你好😀")
        var readsAfterWrite = 0
        access.afterDispatch = {
            access.fieldWitness = "ab你好😀z"
            access.onChange?(.contentOrSelection)
            access.onSnapshot = {
                readsAfterWrite += 1
                if readsAfterWrite == 1 || scenario == "persistent" { throw NativeInputError.unsupported }
                if readsAfterWrite == 2 {
                    switch scenario {
                    case "late-focus": access.onChange?(.focusOrDocument)
                    case "observed-edit": access.onChange?(.contentOrSelection)
                    case "bad-caret": access.target.selectionLength = 1
                    case "field-changed": access.fieldWitness = "cb你好😀z"
                    default: break
                    }
                }
            }
        }
        let result = await input.insertStable(recordingID: record.id, revisionID: revision.id,
                                               stableUTF16End: 4, recordingStartedAt: record.createdAt)
        #expect(result == (scenario == "restored" ? .confirmed : .unverified))
        #expect((input.binding != nil) == (scenario == "restored"))
        if scenario == "restored" { #expect(readsAfterWrite >= 3) }
        #expect(access.attempts == ["你好😀"])
    }

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
    @Test func cancellationBeforeStartDoesNotWrite() async throws {
        let directory = testDirectory(); defer { try? FileManager.default.removeItem(at: directory) }
        let store = try SaytileStore(directory: directory), access = FakeInputAccess()
        let coordinator = NativeInputCoordinator(store: store, access: access)
        try await coordinator.bindCurrentTarget()
        let record = try await store.createRecording()
        let revision = try await store.saveEdit(recordingID: record.id, text: "不要派发")
        let task = Task { await coordinator.insert(recordingID: record.id, revisionID: revision.id) }
        task.cancel()
        #expect(await task.value == .cancelled)
        #expect(access.attempts.isEmpty)
    }
    @Test func cancellationDuringReservationNeverReachesAX() async throws {
        let directory = testDirectory(); defer { try? FileManager.default.removeItem(at: directory) }
        let store = try SaytileStore(directory: directory), access = FakeInputAccess()
        let coordinator = NativeInputCoordinator(store: store, access: access)
        try await coordinator.bindCurrentTarget()
        let record = try await store.createRecording()
        let revision = try await store.saveEdit(recordingID: record.id, text: "仍不派发")
        var task: Task<NativeInputResult, Never>?
        access.onSnapshot = { task?.cancel() }
        task = Task { await coordinator.insert(recordingID: record.id, revisionID: revision.id) }
        #expect(await task!.value == .cancelled)
        #expect(access.attempts.isEmpty)
    }
    @Test func slowAcknowledgementIsConfirmedWithoutResending() async throws {
        let directory = testDirectory(); defer { try? FileManager.default.removeItem(at: directory) }
        let store = try SaytileStore(directory: directory), access = FakeInputAccess()
        let coordinator = NativeInputCoordinator(store: store, access: access)
        try await coordinator.bindCurrentTarget()
        access.confirmationsToDelay = 2
        let record = try await store.createRecording()
        let revision = try await store.saveEdit(recordingID: record.id, text: "只尝试一次")
        #expect(await coordinator.insert(recordingID: record.id, revisionID: revision.id) == .confirmed)
        #expect(access.attempts == ["只尝试一次"])
    }
    @Test func focusAwayAndBackExpiresBinding() async throws {
        let directory = testDirectory(); defer { try? FileManager.default.removeItem(at: directory) }
        let store = try SaytileStore(directory: directory), access = FakeInputAccess()
        let coordinator = NativeInputCoordinator(store: store, access: access)
        try await coordinator.bindCurrentTarget()
        // The final snapshot is unchanged, but the lifecycle event must still expire its session.
        access.onChange?(.focusOrDocument)
        #expect(coordinator.binding == nil)
    }
    @Test func injectedWorkspaceActivationExpiresBindingWithoutChangingFakeSnapshot() async throws {
        let directory = testDirectory(); defer { try? FileManager.default.removeItem(at: directory) }
        let store = try SaytileStore(directory: directory), access = FakeInputAccess()
        let activatedApplication = NSRunningApplication.current
        // A command-line runner can report -1. Choose relative to the actual
        // notification payload instead of assuming any sentinel is distinct.
        access.target.processID = activatedApplication.processIdentifier == 123456 ? 123457 : 123456
        try #require(access.target.processID != activatedApplication.processIdentifier)
        let expectedTarget = access.target
        let center = NotificationCenter()
        let coordinator = NativeInputCoordinator(store: store, access: access,
                                                  activationNotificationCenter: center)
        try await coordinator.bindCurrentTarget()
        let record = try await store.createRecording()
        let revision = try await store.saveEdit(recordingID: record.id, text: "目标切换后不派发")
        let invalidations = AsyncStream<Void>.makeStream()
        defer { invalidations.continuation.finish() }
        coordinator.onBindingInvalidated = { invalidations.continuation.yield(()) }

        // Post only to the isolated center, using the production notification and
        // payload type. No real activation, accessibility action or draft is involved.
        center.post(name: NSWorkspace.didActivateApplicationNotification, object: nil,
                    userInfo: [NSWorkspace.applicationUserInfoKey: activatedApplication])
        let invalidated = await withTaskGroup(of: Bool.self) { group in
            group.addTask {
                for await _ in invalidations.stream { return true }
                return false
            }
            group.addTask {
                try? await Task.sleep(for: .seconds(2))
                return false
            }
            let observed = await group.next() ?? false
            group.cancelAll()
            return observed
        }
        #expect(invalidated)
        #expect(coordinator.binding == nil)
        #expect(access.target == expectedTarget)
        #expect(await coordinator.insert(recordingID: record.id, revisionID: revision.id) == .cancelled)
        #expect(access.attempts.isEmpty)
    }
    @Test func sameURLReusedWebEditorLayoutExpiresBinding() async throws {
        let directory = testDirectory(); defer { try? FileManager.default.removeItem(at: directory) }
        let store = try SaytileStore(directory: directory), access = FakeInputAccess()
        access.target.isWeb = true
        let coordinator = NativeInputCoordinator(store: store, access: access)
        try await coordinator.bindCurrentTarget()
        access.onChange?(.layout)
        #expect(coordinator.binding == nil)
    }
    @Test(arguments: ["own-edit", "changed-prefix", "other-page", "changed-caret"])
    func webTimedOutTextWriteNeedsExactReadback(scenario: String) async throws {
        let directory = testDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try SaytileStore(directory: directory)
        let access = FakeInputAccess()
        access.target.isWeb = true
        access.target.selectionLocation = 2
        access.fieldWitness = "abz"
        access.timesOutAfterTextWrite = true
        let input = NativeInputCoordinator(store: store, access: access)
        try await input.bindCurrentTarget()
        let record = try await store.createRecording()
        let revision = try await store.saveEdit(recordingID: record.id, text: "你好😀")
        access.afterDispatch = {
            access.fieldWitness = scenario == "changed-prefix" ? "cb你好😀z" : "ab你好😀z"
            if scenario == "other-page" { access.target.pageIdentity = "second synthetic document" }
            if scenario == "changed-caret" { access.target.selectionLocation -= 1 }
            access.onChange?(.contentOrSelection)
        }
        let result = await input.insertStable(recordingID: record.id, revisionID: revision.id,
                                              stableUTF16End: 4, recordingStartedAt: record.createdAt)
        #expect(result == (scenario == "own-edit" ? .confirmed : .unverified))
        #expect((input.binding != nil) == (scenario == "own-edit"))
        #expect(access.attempts == ["你好😀"])
        if scenario == "own-edit" {
            access.onChange?(.contentOrSelection)
            #expect(input.binding == nil) // after return a new edit/undo notification expires ownership
        }
    }
    @Test func unobservableWebOnlyAllowsExplicitManualInsertion() async throws {
        let directory = testDirectory(); defer { try? FileManager.default.removeItem(at: directory) }
        let store = try SaytileStore(directory: directory), access = FakeInputAccess()
        access.target.isWeb = true
        access.observedSupport = .init(focus: true, content: true, page: false)
        let coordinator = NativeInputCoordinator(store: store, access: access)
        do { try await coordinator.bindCurrentTarget(); Issue.record("Expected unsupported page lifecycle") } catch { #expect(error is NativeInputError) }
        try await coordinator.bindCurrentTarget(purpose: .manual)
        let record = try await store.createRecording()
        let revision = try await store.saveEdit(recordingID: record.id, text: "明确单次")
        #expect(await coordinator.insert(recordingID: record.id, revisionID: revision.id) == .confirmed)
        #expect(access.attempts == ["明确单次"])
    }
    @Test func incompleteSemanticContextRejectsContinuousButKeepsManual() async throws {
        let directory = testDirectory(); defer { try? FileManager.default.removeItem(at: directory) }
        let store = try SaytileStore(directory: directory), access = FakeInputAccess()
        access.target.isWeb = true; access.target.pageContextComplete = false
        let coordinator = NativeInputCoordinator(store: store, access: access)
        do { try await coordinator.bindCurrentTarget(); Issue.record("Expected incomplete context refusal") }
        catch { #expect(error is NativeInputError) }
        #expect(coordinator.binding == nil)
        try await coordinator.bindCurrentTarget(purpose: .manual)
        #expect(coordinator.binding != nil)
    }
    @Test func userSelectionDuringConfirmationStopsBinding() async throws {
        let directory = testDirectory(); defer { try? FileManager.default.removeItem(at: directory) }
        let store = try SaytileStore(directory: directory), access = FakeInputAccess()
        let coordinator = NativeInputCoordinator(store: store, access: access)
        try await coordinator.bindCurrentTarget()
        let record = try await store.createRecording()
        let revision = try await store.saveEdit(recordingID: record.id, text: "一次插入")
        access.afterDispatch = { access.target.selectionLength = 1; access.onChange?(.contentOrSelection) }
        #expect(await coordinator.insert(recordingID: record.id, revisionID: revision.id) == .unverified)
        #expect(coordinator.binding == nil)
        #expect(access.attempts == ["一次插入"])
    }
    @Test func ownInsertionNotificationKeepsContinuousBinding() async throws {
        let directory = testDirectory(); defer { try? FileManager.default.removeItem(at: directory) }
        let store = try SaytileStore(directory: directory), access = FakeInputAccess()
        let coordinator = NativeInputCoordinator(store: store, access: access)
        try await coordinator.bindCurrentTarget()
        let record = try await store.createRecording()
        let revision = try await store.saveEdit(recordingID: record.id, text: "自身通知")
        access.afterDispatch = { access.onChange?(.contentOrSelection) }
        #expect(await coordinator.insert(recordingID: record.id, revisionID: revision.id) == .confirmed)
        #expect(coordinator.binding != nil)
    }
    @Test func lostLocalReadCapabilityStopsNextAppend() async throws {
        let directory = testDirectory(); defer { try? FileManager.default.removeItem(at: directory) }
        let store = try SaytileStore(directory: directory), access = FakeInputAccess()
        let coordinator = NativeInputCoordinator(store: store, access: access)
        try await coordinator.bindCurrentTarget()
        let record = try await store.createRecording()
        let revision = try await store.saveEdit(recordingID: record.id, text: "已确认")
        #expect(await coordinator.insert(recordingID: record.id, revisionID: revision.id) == .confirmed)
        access.localTextMatches = nil
        _ = await coordinator.insert(recordingID: record.id, revisionID: revision.id)
        #expect(access.attempts.count == 1)
        #expect(coordinator.binding == nil)
    }
    @Test func newRecordingAtExactBindingTimestampUsesCreationBoundary() async throws {
        let directory = testDirectory(); defer { try? FileManager.default.removeItem(at: directory) }
        let store = try SaytileStore(directory: directory), access = FakeInputAccess()
        let coordinator = NativeInputCoordinator(store: store, access: access)
        let binding = try await coordinator.bindCurrentTarget()
        // Persist an actual new recording on the same clock tick, then use its decoded
        // createdAt. No fake startedAt override or scheduling sleep is involved.
        let record = try await store.createRecording(createdAt: binding.boundAt)
        #expect(record.createdAt.timeIntervalSince1970 == binding.boundAt.timeIntervalSince1970)
        let ticket = try await store.beginRecognition(recordingID: record.id)
        try await store.applyRecognition(ticket: ticket, text: "同一时刻的新表达", isFinal: true)
        let revision = try #require(await store.latestFinalRevision(recordingID: record.id))
        let result = await coordinator.insertStable(recordingID: record.id, revisionID: revision.id, stableUTF16End: revision.text.utf16.count, recordingStartedAt: record.createdAt)
        #expect(result == .confirmed)
        #expect(access.attempts == ["同一时刻的新表达"])
    }
    @Test func lateEarlierRecordingIsDeferredWithoutBlockingNextSpeech() async throws {
        let directory = testDirectory(); defer { try? FileManager.default.removeItem(at: directory) }
        let store = try SaytileStore(directory: directory), access = FakeInputAccess()
        let coordinator = NativeInputCoordinator(store: store, access: access)
        let binding = try await coordinator.bindCurrentTarget()
        let first = try await store.createRecording()
        let second = try await store.createRecording()
        let third = try await store.createRecording()
        let a = try await store.beginRecognition(recordingID: first.id)
        let b = try await store.beginRecognition(recordingID: second.id)
        let c = try await store.beginRecognition(recordingID: third.id)
        try await store.applyRecognition(ticket: b, text: "后说先到。", isFinal: true)
        let bFinal = try #require(await store.latestFinalRevision(recordingID: second.id))
        #expect(await coordinator.insertStable(recordingID: second.id, revisionID: bFinal.id, stableUTF16End: bFinal.text.utf16.count, recordingStartedAt: second.createdAt) == .confirmed)
        try await store.applyRecognition(ticket: a, text: "先说迟到。", isFinal: true)
        let aFinal = try #require(await store.latestFinalRevision(recordingID: first.id))
        let aResult = await coordinator.insertStable(recordingID: first.id, revisionID: aFinal.id, stableUTF16End: aFinal.text.utf16.count, recordingStartedAt: first.createdAt)
        if aResult != .deferred { print("ORDER_BOUNDARY decoded=\(first.createdAt.timeIntervalSince1970) binding=\(binding.boundAt.timeIntervalSince1970) delta_us=\(first.createdAt.timeIntervalSince(binding.boundAt) * 1_000_000) decodedRef=\(first.createdAt.timeIntervalSinceReferenceDate) bindingRef=\(binding.boundAt.timeIntervalSinceReferenceDate) result=\(aResult)") }
        #expect(aResult == .deferred)
        #expect(coordinator.binding?.id == binding.id)
        #expect(try await store.recording(id: first.id)?.text == "先说迟到。")
        try await store.applyRecognition(ticket: c, text: "新的一段。", isFinal: true)
        let cFinal = try #require(await store.latestFinalRevision(recordingID: third.id))
        #expect(await coordinator.insertStable(recordingID: third.id, revisionID: cFinal.id, stableUTF16End: cFinal.text.utf16.count, recordingStartedAt: third.createdAt) == .confirmed)
        #expect(access.attempts == ["后说先到。", "新的一段。"])
    }
    @Test func lateTailCannotBeAppendedAfterAnotherRecording() async throws {
        let directory = testDirectory(); defer { try? FileManager.default.removeItem(at: directory) }
        let store = try SaytileStore(directory: directory), access = FakeInputAccess()
        let coordinator = NativeInputCoordinator(store: store, access: access)
        let binding = try await coordinator.bindCurrentTarget()
        let first = try await store.createRecording()
        let second = try await store.createRecording()
        let third = try await store.createRecording()
        let a = try await store.beginRecognition(recordingID: first.id)
        let b = try await store.beginRecognition(recordingID: second.id)
        let c = try await store.beginRecognition(recordingID: third.id)
        try await store.applyRecognition(ticket: a, text: "首段前缀", isFinal: true)
        let aPrefix = try #require(await store.latestFinalRevision(recordingID: first.id))
        let prefixResult = await coordinator.insertStable(recordingID: first.id, revisionID: aPrefix.id, stableUTF16End: aPrefix.text.utf16.count, recordingStartedAt: first.createdAt)
        if prefixResult != .confirmed { print("ORDER_BOUNDARY decoded=\(first.createdAt.timeIntervalSince1970) binding=\(binding.boundAt.timeIntervalSince1970) delta_us=\(first.createdAt.timeIntervalSince(binding.boundAt) * 1_000_000) decodedRef=\(first.createdAt.timeIntervalSinceReferenceDate) bindingRef=\(binding.boundAt.timeIntervalSinceReferenceDate) result=\(prefixResult)") }
        #expect(prefixResult == .confirmed)
        try await store.applyRecognition(ticket: b, text: "第二段。", isFinal: true)
        let bFinal = try #require(await store.latestFinalRevision(recordingID: second.id))
        #expect(await coordinator.insertStable(recordingID: second.id, revisionID: bFinal.id, stableUTF16End: bFinal.text.utf16.count, recordingStartedAt: second.createdAt) == .confirmed)
        try await store.applyRecognition(ticket: a, text: "首段前缀，迟到尾部。", isFinal: true)
        let aFull = try #require(await store.latestFinalRevision(recordingID: first.id))
        let tailResult = await coordinator.insertStable(recordingID: first.id, revisionID: aFull.id, stableUTF16End: aFull.text.utf16.count, recordingStartedAt: first.createdAt)
        #expect(tailResult == .deferred)
        #expect(coordinator.binding?.id == binding.id)
        try await store.applyRecognition(ticket: c, text: "第三段。", isFinal: true)
        let cFinal = try #require(await store.latestFinalRevision(recordingID: third.id))
        #expect(await coordinator.insertStable(recordingID: third.id, revisionID: cFinal.id, stableUTF16End: cFinal.text.utf16.count, recordingStartedAt: third.createdAt) == .confirmed)
        #expect(access.attempts == ["首段前缀", "第二段。", "第三段。"])
    }
    @Test func mutationOfConfirmedTailStopsNextAppend() async throws {
        let directory = testDirectory(); defer { try? FileManager.default.removeItem(at: directory) }
        let store = try SaytileStore(directory: directory), access = FakeInputAccess()
        let coordinator = NativeInputCoordinator(store: store, access: access)
        try await coordinator.bindCurrentTarget()
        let record = try await store.createRecording()
        let revision = try await store.saveEdit(recordingID: record.id, text: "已插入")
        #expect(await coordinator.insert(recordingID: record.id, revisionID: revision.id) == .confirmed)
        access.localTextMatches = false
        _ = await coordinator.insert(recordingID: record.id, revisionID: revision.id)
        #expect(access.attempts == ["已插入"])
        #expect(coordinator.binding == nil)
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

extension InputCoordinatorTests {
    private func fusionPair(store: SaytileStore, ticket: RecognitionTicket, text: String) async throws -> [RecognitionCandidate] {
        var result: [RecognitionCandidate] = []
        for purpose in [RecognitionPurpose.chineseASR, .englishASR] {
            let run = try await store.beginModelRun(ticket: ticket, configuration: .init(purpose: purpose,
                provider: purpose == .chineseASR ? .qwenMessage : .assemblyAI, model: "isolated-input-fixture"))
            let candidate = RecognitionCandidate(run: run, sequence: 0, text: text,
                stableUTF16Length: text.utf16.count, audioEndSeconds: 1, isComplete: true)
            _ = try await store.appendRecognitionCandidate(candidate)
            result.append(candidate)
        }
        return result
    }

    @Test func productionFusionPublicationReachesIncrementalCoordinatorOnce() async throws {
        let directory = testDirectory(); defer { try? FileManager.default.removeItem(at: directory) }
        let store = try SaytileStore(directory: directory), access = FakeInputAccess()
        let coordinator = NativeInputCoordinator(store: store, access: access)
        try await coordinator.bindCurrentTarget()
        let record = try await store.createRecording(), ticket = try await store.beginFusionRecognition(recordingID: record.id)
        let original = "不要改成 50 mg。😀"
        let first = try await fusionPair(store: store, ticket: ticket, text: original)
        let publication = try await store.publishFusion(ticket: ticket, proposal: PrecisionFusion.evaluate(candidates: first, mode: .highestQuality))
        let head = try #require(publication.revision)
        #expect(await coordinator.insertStable(recordingID: record.id, revisionID: head.id,
            stableUTF16End: original.utf16.count, recordingStartedAt: record.createdAt) == .confirmed)
        #expect(await coordinator.insertStable(recordingID: record.id, revisionID: head.id,
            stableUTF16End: original.utf16.count, recordingStartedAt: record.createdAt) == .noNewText)
        let updatedText = original + " 再说一次。"
        let newer = first.map { RecognitionCandidate(run: $0.run, sequence: 1, text: updatedText,
            stableUTF16Length: updatedText.utf16.count, audioEndSeconds: 2, isComplete: true) }
        for candidate in newer { _ = try await store.appendRecognitionCandidate(candidate) }
        let revised = try await store.publishFusion(ticket: ticket, proposal: PrecisionFusion.evaluate(
            candidates: newer, mode: .highestQuality, committedPrefix: original))
        let newHead = try #require(revised.revision)
        #expect(await coordinator.insertStable(recordingID: record.id, revisionID: newHead.id,
            stableUTF16End: updatedText.utf16.count, recordingStartedAt: record.createdAt) == .confirmed)
        #expect(access.attempts == [original, " 再说一次。"])
        #expect(try await store.fusionReservedPrefix(recordingID: record.id) == updatedText)
        try await store.close()
    }

    @Test func failedFusionExpertPreventsStaleExternalAttemptWithoutBlockingNextSpeech() async throws {
        let directory = testDirectory(); defer { try? FileManager.default.removeItem(at: directory) }
        let store = try SaytileStore(directory: directory), access = FakeInputAccess()
        let coordinator = NativeInputCoordinator(store: store, access: access)
        try await coordinator.bindCurrentTarget()
        let record = try await store.createRecording(), ticket = try await store.beginFusionRecognition(recordingID: record.id)
        let candidates = try await fusionPair(store: store, ticket: ticket, text: "等待核对的文字")
        let proposal = try await store.publishFusion(ticket: ticket, proposal: PrecisionFusion.evaluate(candidates: candidates, mode: .highestQuality))
        let head = try #require(proposal.revision)
        try await store.finishModelRun(candidates[0].run, error: "isolated timeout")
        #expect(await coordinator.insertStable(recordingID: record.id, revisionID: head.id,
            stableUTF16End: head.text.utf16.count, recordingStartedAt: record.createdAt) == .noNewText)
        #expect(access.attempts.isEmpty)
        #expect(coordinator.binding != nil)
        let next = try await store.createRecording(), nextTicket = try await store.beginFusionRecognition(recordingID: next.id)
        let independent = try await fusionPair(store: store, ticket: nextTicket, text: "后续独立表达")
        let ready = try await store.publishFusion(ticket: nextTicket, proposal: PrecisionFusion.evaluate(candidates: independent, mode: .highestQuality))
        let nextHead = try #require(ready.revision)
        #expect(await coordinator.insertStable(recordingID: next.id, revisionID: nextHead.id,
            stableUTF16End: nextHead.text.utf16.count, recordingStartedAt: next.createdAt) == .confirmed)
        #expect(access.attempts == ["后续独立表达"])
        try await store.close()
    }
}
