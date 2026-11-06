import AppKit
import SaytileKit

// Compiled together with the production AppModel.swift, using only isolated synthetic data.
@main
struct AppModelProbe {
    struct Failure: Error { let message: String }
    @MainActor static func main() async throws {
        NSApplication.shared.setActivationPolicy(.prohibited)
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("saytile-model-probe-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        var checks = 0
        func require(_ result: Bool, _ description: String) throws {
            guard result else { throw Failure(message: description) }
            checks += 1
            print("PASS " + description); fflush(nil)
        }
        let seed = try SaytileStore(directory: directory)
        let old = try await seed.createRecording(createdAt: .distantPast)
        try await seed.saveEdit(recordingID: old.id, text: "历史测试甲")
        try await seed.finishRecording(id: old.id)
        let other = try await seed.createRecording(createdAt: Date(timeIntervalSince1970: 1000))
        try await seed.saveEdit(recordingID: other.id, text: "历史测试乙")
        try await seed.finishRecording(id: other.id)
        try await seed.close()
        let preferenceSuite = "app.saytile.test." + UUID().uuidString
        let preferences = UserDefaults(suiteName: preferenceSuite)!
        defer { preferences.removePersistentDomain(forName: preferenceSuite) }
        preferences.set("synthetic-disconnected-microphone", forKey: "selectedDeviceUID")
        let model = try AppModel(directory: directory, preferences: preferences)
        try require(model.deviceID == UInt32.max && model.audio.selectedDeviceUID == "synthetic-disconnected-microphone", "missing remembered microphone never silently selects system default")
        model.deviceID = 0
        try require(model.audio.selectedDeviceUID == nil && preferences.string(forKey: "selectedDeviceUID") == nil, "explicit default device choice clears remembered hardware UID")
        let first = Task { await model.initialLoad() }
        let second = Task { await model.initialLoad() }
        await first.value; await second.value
        try require(model.records.count == 2, "coalesced initial load waits for populated archive")
        let initialPasses = model.refreshReadPasses
        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<40 { group.addTask { await model.refresh() } }
            await group.waitForAll()
        }
        let coalescedPasses = model.refreshReadPasses - initialPasses
        print("REFRESH_BURST callers=40 database_passes=\(coalescedPasses)"); fflush(nil)
        try require(coalescedPasses < 10 && model.records.count == 2, "overlapping refresh callers share database work without losing archive contents")
        try require(model.recent.isEmpty, "historical records do not enter current insertion panel")
        let oldRow = model.records.first { $0.id == old.id }!
        model.stageInPanel(oldRow, showPanel: false)
        await model.refresh()
        try require(model.recent.map(\.id) == [old.id], "only explicit historical reuse enters panel")
        model.clearPanel(); await model.refresh()
        try require(model.recent.isEmpty && model.records.count == 2, "clearing panel preserves archive")
        let new = try await model.store.createRecording()
        try await model.store.saveEdit(recordingID: new.id, text: "本次测试")
        try await model.store.finishRecording(id: new.id)
        await model.refresh()
        try require(model.recent.map(\.id) == [new.id], "new speech enters current session")
        try await model.store.setPinned(recordingID: old.id, pinned: true)
        model.recordFilter = .pinned
        await model.refresh()
        try require(model.records.map(\.id) == [old.id], "archive pinned filter reaches store")
        model.recordFilter = .all; model.query = "历史测试乙"
        await model.refresh()
        try require(model.records.map(\.id) == [other.id], "archive search reaches store without mixing pages")
        let cleanup = await model.previewCleanup()
        try require(!cleanup && model.cleanupCount == 0, "cleanup preview waits for candidates and protects unrecognized audio")
        model.query = ""; await model.refresh()
        let firstEditor = model.records.first { $0.id == old.id }!
        let secondEditor = model.records.first { $0.id == other.id }!
        await model.selectForEditing(firstEditor)
        model.updateEditorDraft("未保存的修改😀")
        await model.selectForEditing(secondEditor)
        try require(try await model.store.loadDraft(recordingID: old.id) == "未保存的修改😀", "switching records flushes pending draft without waiting for debounce")
        try require(model.editorDraft == secondEditor.text, "switching records does not show another record's draft")
        await model.selectForEditing(firstEditor)
        try require(model.editorDraft == "未保存的修改😀", "returning to record restores durable unsaved draft")
        await model.refresh(); await model.refresh()
        try require(model.editorDraft == "未保存的修改😀", "periodic refresh does not reset unsaved editor text")
        model.updateEditorDraft("正式修改版本")
        await model.saveEditorChanges()
        try require(try await model.store.recording(id: old.id)?.text == "正式修改版本", "save modification creates selected immutable version")
        try require(try await model.store.loadDraft(recordingID: old.id) == nil, "successful version save clears old editor draft")
        model.updateEditorDraft("版本保存期间的旧草稿")
        let saving = Task { await model.saveEditorChanges() }
        await Task.yield()
        model.updateEditorDraft("版本保存期间的新输入")
        await saving.value
        _ = await model.flushEditorDrafts()
        let savedText = try await model.store.recording(id: old.id)?.text
        let savedDraft = try await model.store.loadDraft(recordingID: old.id)
        try require(savedText == "版本保存期间的新输入" || savedDraft == "版本保存期间的新输入", "typing during version commit is retained as version or newer draft")
        // More than thirty new records must not silently disappear from the input panel.
        for index in 0..<115 {
            let row = try await model.store.createRecording(createdAt: Date().addingTimeInterval(Double(index) / 100))
            _ = try await model.store.saveEdit(recordingID: row.id, text: "连续表达第\(index)段")
            try await model.store.finishRecording(id: row.id)
        }
        await model.refresh()
        try require(model.panelCount == 116 && model.recent.count == 100 && model.panelHasMore, "panel exposes total and pagination instead of silently truncating after thirty")
        model.loadEarlierPanel()
        while model.loadingPanel { try await Task.sleep(for: .milliseconds(10)) }
        try require(model.recent.count == 116 && !model.panelHasMore, "earlier current-session expressions remain available for batch reuse")
        try require(model.recent.contains(where: { $0.id == new.id }), "earliest current-session expression survives prolonged input")
        // UI phase labels come from the same current-generation Store run state as production.
        let phaseRecord = try await model.store.createRecording(createdAt: Date().addingTimeInterval(60))
        try await model.store.finishRecording(id: phaseRecord.id)
        let phaseTicket = try await model.store.beginFusionRecognition(recordingID: phaseRecord.id, mode: .highestQuality)
        let phaseConfig = ModelConfiguration(purpose: .textFusion, provider: .openAIResponses, model: "synthetic-phase", cloudConsent: true)
        try await model.store.configureFusionRequirements(ticket: phaseTicket, configurations: [phaseConfig, .init(purpose: .chineseASR, provider: .qwenMessage, model: "synthetic-expert")])
        let phaseRun = try await model.store.beginModelRun(ticket: phaseTicket, configuration: phaseConfig)
        await model.refresh()
        guard let phaseItem = model.recent.first(where: { $0.id == phaseRecord.id }) else { throw Failure(message: "phase fixture not visible") }
        try require(model.recognitionPhaseLabel(for: phaseItem) == "正在核对文字", "production model exposes active text review without fabricated progress")
        try await model.store.finishModelRun(phaseRun)
        try await model.store.failRecognition(ticket: phaseTicket, message: "synthetic preserved failure")
        await model.refresh()
        guard let failedPhaseItem = model.recent.first(where: { $0.id == phaseRecord.id }) else { throw Failure(message: "failed phase fixture not visible") }
        try require(model.recognitionPhases[phaseRecord.id] == nil && model.recognitionPhaseLabel(for: failedPhaseItem) == "识别待恢复", "completed review phase disappears when logical recognition fails")
        model.updateEditorDraft("")
        await model.prepareForExit()
        let closedPasses = model.refreshReadPasses
        await model.refresh()
        try require(model.refreshReadPasses == closedPasses, "late refresh requests do not query the closed store after exit preparation")
        try await model.store.close()
        let reopened = try SaytileStore(directory: directory)
        try require(try await reopened.loadDraft(recordingID: old.id) == "", "exit flush persists an intentionally empty unsaved draft")
        try await reopened.close()
        checks += try await connectionChecks(directory: directory)
        print("APP_MODEL_PROBE_PASS \(checks) checks; no microphone, no external input, no window activation")
    }
}

/// Entirely injected control-flow evidence. A live-shaped report below only tests
/// the receipt gate; it is never a real provider connection or recognition result.
@MainActor
private final class ConnectionControlFixture {
    var keys = Set<UUID>()
    var failSave = false
    var failDelete = false
    var verificationCalls = 0
    var activeVerifications = 0
    var maximumActiveVerifications = 0
    var verificationConfiguration: RecognitionConfiguration?
    var verificationProgress: (@Sendable (CloudConnectionReport) -> Void)?
    var verificationContinuation: CheckedContinuation<CloudConnectionReport, Error>?
    var holdCloudApply = false
    var applyContinuation: CheckedContinuation<Void, Never>?
    var applied: [Bool] = []
    var runtimeCloud = false
    var revocations = 0
    var saveCalls = 0
    var deleteCalls = 0
    var dependencies: AppConnectionDependencies {
        AppConnectionDependencies(
            presence: { self.keys.contains($0.id) ? .saved : .missing },
            save: { value, item in
                self.saveCalls += 1
                guard !self.failSave, value == "simulator-fixture-credential" else { throw ProviderFailure.authorization }
                self.keys.insert(item.id)
            },
            delete: { item in
                self.deleteCalls += 1
                guard !self.failDelete else { throw ProviderFailure.permission }
                self.keys.remove(item.id)
            },
            verify: { configuration, progress in
                self.verificationCalls += 1
                guard configuration.enabledModels.allSatisfy({ self.keys.contains($0.id) }) else { throw ProviderFailure.authorization }
                self.activeVerifications += 1
                self.maximumActiveVerifications = max(self.maximumActiveVerifications, self.activeVerifications)
                defer { self.activeVerifications -= 1 }
                self.verificationConfiguration = configuration; self.verificationProgress = progress
                progress(try Self.report(configuration, state: .connecting, live: false, completed: false))
                // Deliberately keep cancellation cleanup outstanding until the fixture
                // releases it: the production model must own and await this operation.
                return try await withCheckedThrowingContinuation { self.verificationContinuation = $0 }
            },
            applyConfiguration: { _, configuration in
                self.applied.append(configuration.cloudEnabled)
                self.runtimeCloud = configuration.cloudEnabled
                if configuration.cloudEnabled && self.holdCloudApply {
                    await withCheckedContinuation { self.applyContinuation = $0 }
                }
            },
            revokeCloud: { audio in self.runtimeCloud = false; self.revocations += 1; audio.revokeCloudRecognition() })
    }
    static func report(_ configuration: RecognitionConfiguration, state: ConnectionServiceState,
                       live: Bool, completed: Bool) throws -> CloudConnectionReport {
        let rows: [[String: Any]] = configuration.enabledModels.map {
            var row: [String: Any] = ["id": $0.id.uuidString, "provider": $0.provider.rawValue, "state": state.rawValue]
            if state == .failed { row["code"] = "quota_exhausted"; row["message"] = "TEST_ONLY synthetic quota failure" }
            return row
        }
        let object: [String: Any] = ["configurationFingerprint": CloudConnectionVerifier.fingerprint(configuration),
            "date": 0, "live": live, "services": rows, "transcript": completed ? "TEST_ONLY 不要支付15元。" : "",
            "pipelineCompleted": completed, "elapsedSeconds": 0, "reviewRequests": 0,
            "message": "TEST_ONLY injected controller evidence; no provider connection"]
        return try JSONDecoder().decode(CloudConnectionReport.self, from: JSONSerialization.data(withJSONObject: object))
    }
    func publish(_ state: ConnectionServiceState) throws {
        guard let configuration = verificationConfiguration else { throw AppModelProbe.Failure(message: "no pending fixture verification") }
        verificationProgress?(try Self.report(configuration, state: state, live: false, completed: false))
    }
    func publishMixedTerminalStates() throws {
        guard let configuration = verificationConfiguration else { throw AppModelProbe.Failure(message: "no pending fixture verification") }
        var report = try Self.report(configuration, state: .receiving, live: false, completed: false)
        report.services[0].state = .verified; report.services[1].state = .failed
        verificationProgress?(report)
    }
    func finish(_ state: ConnectionServiceState, live: Bool, completed: Bool) throws {
        guard let configuration = verificationConfiguration, let continuation = verificationContinuation else {
            throw AppModelProbe.Failure(message: "no pending fixture verification to finish")
        }
        verificationContinuation = nil
        continuation.resume(returning: try Self.report(configuration, state: state, live: live, completed: completed))
    }
    func releaseApply() { let pending = applyContinuation; applyContinuation = nil; pending?.resume() }
}

extension AppModelProbe {
    @MainActor private static func until(_ message: String, _ condition: () -> Bool) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(5))
        while !condition() {
            guard ContinuousClock.now < deadline else { throw Failure(message: "timeout: " + message) }
            try await Task.sleep(for: .milliseconds(5))
        }
    }
    @MainActor private static func connectionChecks(directory: URL) async throws -> Int {
        var count = 0
        func check(_ condition: Bool, _ message: String) throws {
            guard condition else { throw Failure(message: message) }
            count += 1; print("PASS CONNECTION " + message); fflush(nil)
        }
        let suite = "app.saytile.test.connections." + UUID().uuidString
        let preferences = UserDefaults(suiteName: suite)!
        defer { preferences.removePersistentDomain(forName: suite) }
        var configuration = RecognitionConfiguration(); configuration.automaticRecovery = false
        for index in configuration.models.indices where configuration.models[index].enabled {
            configuration.models[index].cloudConsent = true
            if configuration.models[index].provider == .qwenMessage { configuration.models[index].workspaceID = "fixture-workspace" }
        }
        try configuration.save(to: preferences)
        let fixture = ConnectionControlFixture()
        let model = try AppModel(directory: directory.appendingPathComponent("connections"), preferences: preferences,
                                 connectionDependencies: fixture.dependencies)
        await model.initialLoad()
        try check(configuration.enabledModels.allSatisfy({ !model.hasCredential($0) }), "missing keys are shown through metadata-only injected presence")
        model.checkRecognitionConnections()
        try check(fixture.verificationCalls == 0 && !model.checkingConnection, "no upload authorization means no verification invocation")
        model.recognitionConfiguration.cloudEnabled = true; model.applyRecognitionSettings()
        try check(!model.appliedRecognitionConfiguration.cloudEnabled && !fixture.runtimeCloud,
                  "unverified settings cannot enable cloud recognition")
        model.connectionCheckAuthorized = true; model.checkRecognitionConnections()
        try await until("missing-key failure") { !model.checkingConnection && !model.applyingRecognitionSettings }
        try check(!model.connectionVerified && fixture.activeVerifications == 0 && !fixture.runtimeCloud,
                  "authorized check with missing keys fails before any mocked provider starts")
        let first = configuration.enabledModels[0]
        fixture.failSave = true
        try check(!model.saveCredential("simulator-fixture-credential", for: first) && !model.hasCredential(first),
                  "failed credential save does not claim saved or connected")
        fixture.failSave = false
        for item in configuration.enabledModels {
            try check(model.saveCredential("simulator-fixture-credential", for: item), "fixture credential saved without Keychain access for " + item.provider.rawValue)
        }
        try await until("local configuration drain") { !model.applyingRecognitionSettings }
        model.connectionCheckAuthorized = true; model.checkRecognitionConnections()
        try await until("simulated verification entry") { fixture.verificationContinuation != nil }
        try check(model.checkingConnection, "check remains active while actual controller awaits backend")
        try fixture.publish(.accountAccepted)
        try await until("account accepted progress") { model.connectionReport?.services.allSatisfy({ $0.state == .accountAccepted }) == true }
        try check(!model.connectionVerified && model.checkingConnection, "three accepted accounts are not final connection success")
        try fixture.publish(.receiving)
        try await until("receiving progress") { model.connectionReport?.services.allSatisfy({ $0.state == .receiving }) == true }
        try check(!model.connectionVerified && !fixture.runtimeCloud, "visible partial progress does not enable cloud")
        try fixture.finish(.verified, live: false, completed: true)
        try await until("simulator report returned") { !model.checkingConnection }
        try check(model.connectionReport?.readiness == .noAPIEngineeringReady && !model.connectionVerified &&
                    preferences.data(forKey: "cloudConnectionReceipt.v1") == nil && !model.appliedRecognitionConfiguration.cloudEnabled,
                  "simulated completed report remains NO_API_ENGINEERING_READY and cannot persist a live receipt")
        model.connectionCheckAuthorized = true; model.checkRecognitionConnections()
        try await until("failed verification entry") { fixture.verificationContinuation != nil }
        try fixture.finish(.failed, live: true, completed: false)
        try await until("failed report returned") { !model.checkingConnection }
        try check(model.connectionReport?.services.allSatisfy({ $0.state == .failed }) == true && !model.connectionVerified && !fixture.runtimeCloud,
                  "service failures remain visible and retain local recognition")
        // The live bit here is intentionally fabricated ONLY to exercise the production
        // receipt admission branch. This is not evidence of a live cloud connection.
        model.connectionCheckAuthorized = true; model.checkRecognitionConnections()
        try await until("test-only live-shaped report entry") { fixture.verificationContinuation != nil }
        try fixture.finish(.verified, live: true, completed: true)
        try await until("test-only receipt applied") { !model.checkingConnection && !model.applyingRecognitionSettings }
        try check(model.connectionVerified && model.appliedRecognitionConfiguration.cloudEnabled && fixture.runtimeCloud &&
                    preferences.data(forKey: "cloudConnectionReceipt.v1") != nil,
                  "TEST_ONLY live-shaped injected receipt exercises success-to-enable branch; no cloud call")
        fixture.failDelete = true
        try check(!model.removeCredential(for: first) && model.hasCredential(first) && model.connectionVerified,
                  "failed credential removal preserves the prior receipt and key metadata")
        fixture.failDelete = false
        model.recognitionConfiguration.cloudEnabled = false; model.applyRecognitionSettings()
        try await until("explicit local mode applied") { !model.applyingRecognitionSettings }
        fixture.holdCloudApply = true
        model.recognitionConfiguration.cloudEnabled = true; model.applyRecognitionSettings()
        try await until("cloud apply drain held") { fixture.applyContinuation != nil }
        try check(fixture.runtimeCloud && !model.appliedRecognitionConfiguration.cloudEnabled,
                  "fixture holds first cloud apply before its visible applied snapshot")
        try check(model.removeCredential(for: first) && !fixture.runtimeCloud && !model.connectionVerified &&
                    !model.appliedRecognitionConfiguration.cloudEnabled && preferences.data(forKey: "cloudConnectionReceipt.v1") == nil,
                  "credential revocation synchronously stops an unpublished in-flight cloud apply")
        fixture.releaseApply(); fixture.holdCloudApply = false
        try await until("revoked apply drained") { !model.applyingRecognitionSettings }
        try check(!fixture.runtimeCloud && !model.appliedRecognitionConfiguration.cloudEnabled &&
                    !RecognitionConfiguration.load(from: preferences).cloudEnabled,
                  "late completion of revoked apply cannot restore cloud state or persisted settings")
        _ = model.saveCredential("simulator-fixture-credential", for: first)
        try await until("restored fixture credential local drain") { !model.applyingRecognitionSettings }
        model.connectionCheckAuthorized = true; model.checkRecognitionConnections()
        try await until("cancelled check entry") { fixture.verificationContinuation != nil }
        try await until("cancelled check progress visible") { model.connectionReport?.services.count == 3 }
        let callsBeforeReplacement = fixture.verificationCalls
        model.cancelConnectionCheck()
        try check(model.connectionReport?.services.allSatisfy({ $0.state == .cancelled }) == true,
                  "cancelled check resolves every unfinished service card to a stopped state")
        try fixture.publish(.verified)
        model.connectionCheckAuthorized = true; model.checkRecognitionConnections()
        try await Task.sleep(for: .milliseconds(30))
        try check(fixture.verificationCalls == callsBeforeReplacement && !model.connectionVerified,
                  "replacement check waits for cancelled predecessor cleanup and ignores late progress")
        try fixture.finish(.verified, live: true, completed: true)
        try await until("replacement check entered after cleanup") { fixture.verificationCalls == callsBeforeReplacement + 1 && fixture.verificationContinuation != nil }
        try check(fixture.maximumActiveVerifications == 1 && !model.connectionVerified,
                  "cancelled successful response cannot enable cloud or overlap a replacement check")
        try fixture.publishMixedTerminalStates()
        try await until("mixed service progress visible") { model.connectionReport?.services.first?.state == .verified }
        model.cancelConnectionCheck()
        try check(model.connectionReport?.services.map(\.state) == [.verified, .failed, .cancelled],
                  "cancelling preserves verified and failed service outcomes while stopping the remaining service")
        _ = model.removeCredential(for: first)
        try fixture.finish(.verified, live: true, completed: true)
        try await until("credential revocation while checking drained") { fixture.activeVerifications == 0 && !model.applyingRecognitionSettings }
        try check(!model.connectionVerified && !fixture.runtimeCloud && model.connectionReport == nil,
                  "credential removal invalidates an active check and every late response")
        _ = model.saveCredential("simulator-fixture-credential", for: first)
        try await until("exit fixture local drain") { !model.applyingRecognitionSettings }
        model.connectionCheckAuthorized = true; model.checkRecognitionConnections()
        try await until("exit check entry") { fixture.verificationContinuation != nil }
        var exited = false
        let exit = Task { await model.prepareForExit(); exited = true }
        try await Task.sleep(for: .milliseconds(30))
        try check(!exited && fixture.activeVerifications == 1, "exit waits until an outstanding connection task has closed")
        let callsAtExit = fixture.verificationCalls
        model.connectionCheckAuthorized = true; model.checkRecognitionConnections()
        try fixture.finish(.verified, live: true, completed: true)
        await exit.value
        try check(exited && fixture.activeVerifications == 0 && !fixture.runtimeCloud && !model.connectionVerified && fixture.verificationCalls == callsAtExit,
                  "exit ignores cancelled success and finishes with no active cloud task")
        let beforeClosedCalls = fixture.verificationCalls
        model.connectionCheckAuthorized = true; model.cancelConnectionCheck()
        model.connectionCheckAuthorized = true; model.checkRecognitionConnections()
        try await Task.sleep(for: .milliseconds(30))
        let lateAdmitted = fixture.verificationCalls != beforeClosedCalls
        model.cancelConnectionCheck()
        if fixture.verificationContinuation != nil { try fixture.finish(.verified, live: true, completed: true) }
        try await until("late action cleanup") { fixture.activeVerifications == 0 }
        try check(!lateAdmitted, "closed model rejects late connection actions instead of opening new tasks")
        let savesAtExit = fixture.saveCalls, deletesAtExit = fixture.deleteCalls
        try check(!model.saveCredential("simulator-fixture-credential", for: first) && !model.removeCredential(for: first) &&
                    fixture.saveCalls == savesAtExit && fixture.deleteCalls == deletesAtExit,
                  "closed model rejects stale credential mutations")
        // A second isolated model holds an apply itself, rather than verification.
        // Its receipt is the same explicit TEST_ONLY fixture, never a live claim.
        try configuration.save(to: preferences)
        preferences.set(try JSONEncoder().encode(ConnectionControlFixture.report(configuration, state: .verified, live: true, completed: true)),
                        forKey: "cloudConnectionReceipt.v1")
        let applyingFixture = ConnectionControlFixture()
        applyingFixture.keys = Set(configuration.enabledModels.map(\.id)); applyingFixture.holdCloudApply = true
        let applyingModel = try AppModel(directory: directory.appendingPathComponent("connections-exit-apply"), preferences: preferences,
                                         connectionDependencies: applyingFixture.dependencies)
        await applyingModel.initialLoad()
        applyingModel.recognitionConfiguration.cloudEnabled = true; applyingModel.applyRecognitionSettings()
        try await until("exit apply barrier entered") { applyingFixture.applyContinuation != nil }
        var applyExited = false, secondExitReturned = false
        let firstExit = Task { await applyingModel.prepareForExit(); applyExited = true }
        try await Task.sleep(for: .milliseconds(30))
        let repeatedExit = Task { await applyingModel.prepareForExit(); secondExitReturned = true }
        try await Task.sleep(for: .milliseconds(30))
        try check(!applyExited && !secondExitReturned && !applyingFixture.runtimeCloud,
                  "exit revokes cloud immediately and both exit callers await the same pending apply")
        try check(!applyingModel.saveCredential("simulator-fixture-credential", for: first),
                  "credential changes are rejected while exit is waiting for cleanup")
        applyingFixture.releaseApply()
        await firstExit.value; await repeatedExit.value
        try check(applyExited && secondExitReturned && !applyingFixture.runtimeCloud && !applyingModel.applyingRecognitionSettings &&
                    !applyingModel.appliedRecognitionConfiguration.cloudEnabled,
                  "late apply completion cannot publish cloud settings during exit")
        print("CONNECTION_EVIDENCE_SCOPE injected controller workflow only; no Keychain, provider sockets, microphone or live verification")
        return count
    }
}
