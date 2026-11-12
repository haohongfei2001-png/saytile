import AppKit
import Combine
import AVFoundation
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
        do {
            let home = directory.appendingPathComponent("first-use")
            let name = "app.saytile.first-use." + UUID().uuidString
            let prefs = UserDefaults(suiteName: name)!
            defer { prefs.removePersistentDomain(forName: name) }
            var authority: AVAuthorizationStatus = .notDetermined
            var session = CaptureState.paused
            var openedSettings = 0
            let capture = AppCaptureDependencies(state: { _ in session }, start: { _ in session = .starting },
                pause: { _ in session = .paused }, microphoneAuthorization: { authority }, openMicrophonePreferences: { openedSettings += 1 })
            let guide = try AppModel(directory: home, preferences: prefs, captureDependencies: capture)
            await guide.initialLoad()
            try require(!guide.isListening && !guide.completedFirstTranscript && guide.deviceOnly && !guide.microphoneDenied, "first launch remains offline, paused, with no permission request")
            authority = .denied; session = .interrupted("麦克风未获授权")
            try require(guide.microphoneDenied && guide.captureProblem && !guide.completedFirstTranscript, "denial preserves the start guide and identifies microphone recovery")
            guide.toggleCapture()
            try require(openedSettings == 1 && guide.captureActionLabel == "打开麦克风权限设置" && !guide.isListening, "denied capsule opens recovery directly without a second start request")
            session = .paused; authority = .authorized
            let segment = try await guide.store.createRecording()
            await guide.refresh()
            try require(!guide.completedFirstTranscript, "a cancelled start or empty saved recording is not first recognition")
            let ticket = try await guide.store.beginRecognition(recordingID: segment.id)
            let accepted = try await guide.store.applyRecognition(ticket: ticket, text: "第一句话", isFinal: false)
            await guide.refreshRecognition()
            try require(guide.panelTimelinePage.entries.last?.recording.text == "第一句话",
                        "a partial reaches the board before a full archive refresh")
            try require(accepted && guide.completedFirstTranscript && prefs.bool(forKey: "firstTranscript.v1"), "an actual nonempty stored partial completes first use before end of speech")
            try await guide.store.finishRecording(id: segment.id)
            await guide.prepareForExit()
            let reopened = try AppModel(directory: home, preferences: prefs, captureDependencies: capture)
            try require(reopened.completedFirstTranscript && !reopened.isListening, "relaunch retains completion without starting capture")
            await reopened.prepareForExit()
        }
        do {
            let suite = "app.saytile.scroll-pages." + UUID().uuidString
            let prefs = UserDefaults(suiteName: suite)!
            defer { prefs.removePersistentDomain(forName: suite) }
            let reader = try AppModel(directory: directory.appendingPathComponent("reading"), preferences: prefs)
            // Recordings without a transcript remain available in the archive. They
            // cannot serve as character anchors when the board's backing page advances.
            for i in 1...160 {
                let row = try await reader.store.createRecording()
                if i <= 64 || i > 144 {
                    try await reader.store.saveEdit(recordingID: row.id, text: "可阅读的文字" + String(i))
                }
                try await reader.store.finishRecording(id: row.id)
            }
            await reader.refreshRecognition()
            let latest = reader.panelTimelinePage.entries
            reader.pinTimeline()
            reader.moveTimeline(older: true)
            await reader.refreshRecognition()
            let older = reader.panelTimelinePage.entries
            let latestIDs = Set(latest.filter { !$0.recording.text.isEmpty }.map(\.id))
            let olderIDs = Set(older.filter { !$0.recording.text.isEmpty }.map(\.id))
            try require(!olderIDs.isEmpty && !olderIDs.isDisjoint(with: latestIDs) && older.first?.position == 1,
                        "manual paging keeps visible overlap across eighty consecutive untranscribed recordings")
            let future = try await reader.store.createRecording()
            try await reader.store.saveEdit(recordingID: future.id, text: "正在说的下一句")
            await reader.refreshRecognition()
            try require(reader.panelTimelinePage.entries.map(\.id) == older.map(\.id) && reader.timelineTail?.id == future.id,
                        "new speech advances the live tail without taking over the pinned history page")
            reader.followTimeline()
            await reader.refreshRecognition()
            try require(reader.panelTimelinePage.entries.last?.id == future.id,
                        "returning to latest after manual paging reveals the actual newest live row")
            await reader.prepareForExit()
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
        try require(model.deviceOnly && !model.hosted.selected, "fresh install starts offline")
        model.setLoginItem(true)
        try require(!model.canManageLoginItem && !model.launchAtLogin,
                    "an isolated instance cannot change the production login item or display an enabled state")
        model.selectSource("hosted")
        try require(!model.deviceOnly && model.hosted.selected && !model.hosted.consent, "Cloud selection grants no upload consent")
        model.selectSource("byok")
        try require(!model.deviceOnly && !model.hosted.selected, "BYOK can be selected independently")
        model.selectSource("local")
        try require(model.deviceOnly && !model.hosted.selected && !model.localTextAllowed, "return to local has no cloud review")
        try require(model.deviceUID == "synthetic-disconnected-microphone" && model.devices.contains(where: { $0.id == model.deviceUID && $0.name.contains("未连接") }),
                    "missing remembered microphone keeps its own UID in the input picker")
        model.deviceUID = "another-disconnected-synthetic-uid"
        try require(model.audio.selectedDeviceUID == "another-disconnected-synthetic-uid" &&
                    preferences.string(forKey: "selectedDeviceUID") == model.audio.selectedDeviceUID && model.devices.filter({ $0.id == nil }).count == 1,
                    "selecting an absent device by stable UID never falls back to the default input")
        model.deviceUID = nil
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
        try require(model.hasPanelInsertionScope && (try model.panelInsertionSnapshots()).map(\.recordingID) == [other.id],
                    "a fresh app session can manually insert only the last time group from its archive")
        let oldRow = model.records.first { $0.id == old.id }!
        model.stageInPanel(oldRow)
        await model.refresh()
        try await until("explicit archive focus") { model.insertionArchiveEntry?.id == old.id }
        try require(model.recent.map(\.id) == [old.id], "only explicit historical reuse enters panel")
        try require((try model.panelInsertionSnapshots()).map(\.recordingID) == [old.id],
                    "bringing one archive entry to the panel offers that record alone for manual reuse")
        model.followTimeline()
        try require((try model.panelInsertionSnapshots()).map(\.recordingID) == [other.id],
                    "returning to latest drops the archive-specific insertion scope")
        model.clearPanel(); await model.refresh()
        try require(model.recent.isEmpty && model.records.count == 2, "clearing panel preserves archive")
        try require(!model.canCopyLatestGroup, "clearing the panel removes its implicit copy target")
        try require(!model.hasPanelInsertionScope && (try model.panelInsertionSnapshots()).isEmpty,
                    "an explicitly cleared panel cannot manually dispatch the cleared group")
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
        let largeGroup = try model.panelInsertionSnapshots()
        try require(largeGroup.count == 116 && largeGroup.first?.recordingID == new.id,
                    "manual group insertion spans multiple virtual pages in capture order")
        guard let last = model.timelineTail else { throw Failure(message: "missing timeline tail for group insertion") }
        let newGroupStart = last.speechEnd.addingTimeInterval(121)
        let nextGroup = try await model.store.createRecording(createdAt: newGroupStart)
        try await model.store.saveEdit(recordingID: nextGroup.id, text: "最新组唯一内容")
        try await model.store.finishRecording(id: nextGroup.id, speechEndedAt: newGroupStart)
        await model.refresh()
        guard let rendered = model.timelineTail else { throw Failure(message: "new group was not visible") }
        let backgroundRevision = try await model.store.saveEdit(recordingID: nextGroup.id, text: "较晚才显示的修订")
        await model.refresh()
        let beforeRedraw = try model.panelInsertionSnapshots(rendered: [rendered], displayed: [rendered.position: "最新组唯一内容"])
        try require(beforeRedraw.map(\.recordingID) == [nextGroup.id] && beforeRedraw.first?.text == "最新组唯一内容" &&
                    beforeRedraw.first?.revisionID != backgroundRevision.id,
                    "manual click excludes the previous 116 records and freezes the version actually drawn")
        try require((try model.panelInsertionSnapshots(displayed: [rendered.position: ""])).isEmpty,
                    "a just-arrived revision cannot be manually sent before its first visible text")
        var redundant = 0
        let observers = [
            model.$hasMore.dropFirst().sink { _ in redundant += 1 },
            model.$panelCount.dropFirst().sink { _ in redundant += 1 },
            model.$panelHasMore.dropFirst().sink { _ in redundant += 1 },
            model.$insertionLabels.dropFirst().sink { _ in redundant += 1 },
            model.$modelCallSummary.dropFirst().sink { _ in redundant += 1 },
            model.$editorDraft.dropFirst().sink { _ in redundant += 1 }
        ]
        try await Task.sleep(for: .milliseconds(2150))
        await model.refresh()
        try require(redundant == 0, "unchanged paused timeline, archive, editor and model status do not publish redundant UI updates")
        withExtendedLifetime(observers) {}
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
        let endedPhases = try await model.store.activeRecognitionPhases(recordingIDs: [phaseRecord.id])
        try require(endedPhases[phaseRecord.id] == nil && model.recognitionPhaseLabel(for: failedPhaseItem) == "识别待恢复", "completed review phase disappears when logical recognition fails")
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
        checks += try await capturePresentationChecks(directory: directory)
        print("APP_MODEL_PROBE_PASS \(checks) checks; no microphone, no external input, no window activation")
    }
}

@MainActor
private final class CaptureControlFixture {
    var state = CaptureState.paused
    var startResult = CaptureState.listening
    var startIssue: String?
    var starts = 0
    var pauses = 0
    var measuredLevel: Float? = nil
    var floatingChanges = 0
    var dependencies: AppCaptureDependencies {
        AppCaptureDependencies(state: { _ in self.state },
            start: { audio in self.starts += 1; self.state = self.startResult; audio.issue = self.startIssue },
            pause: { _ in self.pauses += 1; self.state = .paused }, level: { _ in self.measuredLevel },
            microphoneAuthorization: { .authorized }, openMicrophonePreferences: { preconditionFailure("device fixture cannot request system settings") })
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
    var mutationObservedCloudRuntime = false
    var dependencies: AppConnectionDependencies {
        AppConnectionDependencies(
            presence: { self.keys.contains($0.id) ? .saved : .missing },
            save: { value, item in
                self.saveCalls += 1
                self.mutationObservedCloudRuntime = self.mutationObservedCloudRuntime || self.runtimeCloud
                guard !self.failSave, value == "simulator-fixture-credential" else { throw ProviderFailure.authorization }
                self.keys.insert(item.id)
            },
            delete: { item in
                self.deleteCalls += 1
                self.mutationObservedCloudRuntime = self.mutationObservedCloudRuntime || self.runtimeCloud
                guard !self.failDelete else { throw ProviderFailure.permission }
                self.keys.remove(item.id)
            },
            verify: { configuration, progress in
                self.verificationCalls += 1
                guard configuration.activeModels.allSatisfy({ self.keys.contains($0.id) }) else { throw ProviderFailure.authorization }
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
        let rows: [[String: Any]] = configuration.activeModels.map {
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
    @MainActor private static func capturePresentationChecks(directory: URL) async throws -> Int {
        let suite = "app.saytile.test.capture." + UUID().uuidString
        let preferences = UserDefaults(suiteName: suite)!
        defer { preferences.removePersistentDomain(forName: suite) }
        var configuration = RecognitionConfiguration(); configuration.automaticRecovery = false; configuration.languagePreference = .chinese
        try configuration.save(to: preferences)
        let capture = CaptureControlFixture(), connection = ConnectionControlFixture()
        let model = try AppModel(directory: directory.appendingPathComponent("capture-presentation"), preferences: preferences,
            connectionDependencies: connection.dependencies, captureDependencies: capture.dependencies)
        await model.initialLoad()
        var count = 0
        func check(_ condition: Bool, _ message: String) throws {
            guard condition else { throw Failure(message: message) }
            count += 1; print("PASS " + message); fflush(nil)
        }
        try check(model.panelCapturePresentation.state == .paused && model.captureActionLabel == "开始收音" &&
            model.panelCapturePresentation.symbolName == "play.fill" && !model.isListening && model.panelCapturePresentation.accessibilityValue == "暂停",
            "first launch shares the paused play triangle and offers the start action")
        let observer = NotificationCenter.default.addObserver(forName: .init("SaytileFloatingEntryChanged"), object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { capture.floatingChanges += 1 }
        }
        defer { NotificationCenter.default.removeObserver(observer) }
        try check(!model.floatingEntryEnabled && preferences.object(forKey: "floatingEntryEnabled") == nil,
            "desktop entry defaults off in an isolated preference domain")
        model.floatingEntryEnabled = true
        try check(preferences.bool(forKey: "floatingEntryEnabled") && capture.floatingChanges == 1,
            "explicit desktop entry setting persists and notifies window owner")
        let preparing = CaptureControlFixture(); preparing.startResult = .starting
        let reopened = try AppModel(directory: directory.appendingPathComponent("capture-preference-reopen"), preferences: preferences,
            connectionDependencies: connection.dependencies, captureDependencies: preparing.dependencies)
        try check(reopened.floatingEntryEnabled && capture.floatingChanges == 1,
            "saved desktop entry choice reloads without sending a spurious setting change")
        reopened.floatingEntryEnabled = false
        try check(!preferences.bool(forKey: "floatingEntryEnabled") && capture.floatingChanges == 2,
            "turning desktop entry off persists and sends one change notification")
        reopened.toggleCapture(); try await until("first capture preparation") { preparing.starts == 1 }
        try check(!reopened.hasStarted && reopened.panelCapturePresentation.state == .starting,
            "preparation alone does not mark the microphone as successfully started")
        reopened.toggleCapture(); try await until("cancel first preparation") { preparing.pauses == 1 }
        try check(reopened.panelCapturePresentation.state == .paused && reopened.captureActionLabel == "开始收音",
            "cancelling before the first successful start retains the paused start action")
        await reopened.prepareForExit()

        let saved = try await model.store.createRecording()
        _ = try await model.store.saveEdit(recordingID: saved.id, text: "已保存的文字😀")
        try await model.store.finishRecording(id: saved.id); await model.refresh()
        model.toggleCapture(); try await until("capture fixture starts") { capture.starts == 1 }
        capture.measuredLevel = 0.4
        try check(model.panelCapturePresentation.state == .standby && model.panelCaptureLabel == "待命" &&
            model.panelCapturePresentation.symbolName == "circle.fill" && model.panelCapturePresentation.liveVoiceLevel == nil && model.hasStarted,
            "successful start is quiet standby even when the raw meter contains ambient energy")
        capture.state = .speaking; capture.measuredLevel = 0.25
        try check(model.panelCapturePresentation.state == .recognizing && model.panelCapturePresentation.liveVoiceLevel == 0.25 &&
            model.panelCapturePresentation.accessibilityLabel == "暂停收音" && model.panelCapturePresentation.accessibilityValue == "正在识别",
            "VAD speech uses the single recognition state and only its measured amplitude")
        capture.measuredLevel = 0.75
        try check(model.panelCapturePresentation.liveVoiceLevel == 0.75,
            "real meter changes propagate without a timer or fabricated oscillator")
        for invalid in [nil, Float.nan, .infinity, -0.5] as [Float?] {
            capture.measuredLevel = invalid
            try check(model.panelCapturePresentation.liveVoiceLevel == nil,
                "absent or invalid amplitude never becomes a manufactured speech level")
        }
        capture.measuredLevel = 2
        try check(model.panelCapturePresentation.liveVoiceLevel == 1, "finite speech amplitude is clamped to the documented display range")
        let first = try await model.store.createRecording()
        let firstTicket = try await model.store.beginRecognition(recordingID: first.id)
        let previewAccepted = try await model.store.applyRecognition(ticket: firstTicket, text: "第一段临时文字", isFinal: false)
        try check(previewAccepted && model.panelCapturePresentation.state == .recognizing,
            "current speech stays active while its provisional text is saved")
        capture.state = .listening
        try check(model.panelCapturePresentation.state == .standby && model.panelCapturePresentation.liveVoiceLevel == nil &&
            model.isListening && capture.starts == 1 && capture.pauses == 0,
            "VAD end returns to quiet standby immediately before any Store refresh or finalization")
        try await model.store.finishRecording(id: first.id); await model.refresh()
        let pending = try await model.store.recording(id: first.id)
        try check(pending?.recognitionState == .running && pending?.isRecording == false && pending?.text == "第一段临时文字" &&
            model.panelCapturePresentation.state == .standby,
            "sealed first audio and pending ASR retain text during quiet standby")
        let quietRevision = try await model.store.applyRecognition(ticket: firstTicket, text: "第一段等待定稿", isFinal: false)
        await model.refresh()
        try check(quietRevision && model.recent.first(where: { $0.id == first.id })?.text == "第一段等待定稿" &&
            model.panelCapturePresentation.state == .standby && model.panelCapturePresentation.liveVoiceLevel == nil,
            "a background correction updates the same visible text in quiet standby")
        let queued = try await model.store.createRecording(); try await model.store.finishRecording(id: queued.id)
        await model.refresh()
        let queuedRow = try await model.store.recording(id: queued.id)
        try check(queuedRow?.recognitionState == .queued && model.panelCapturePresentation.state == .standby,
            "a queued saved segment cannot animate the voice control")
        let reviewTicket = try await model.store.beginFusionRecognition(recordingID: queued.id)
        let reviewer = ModelConfiguration(purpose: .textFusion, provider: .openAIResponses, model: "synthetic-review")
        let reviewRun = try await model.store.beginModelRun(ticket: reviewTicket, configuration: reviewer)
        await model.refresh()
        let phases = try await model.store.activeRecognitionPhases(recordingIDs: [queued.id])
        try check(phases[queued.id] == .textFusion && model.panelCapturePresentation.state == .standby &&
            model.panelCapturePresentation.liveVoiceLevel == nil, "real pending fusion remains independent of silent VAD")

        capture.state = .speaking; capture.measuredLevel = 0.625
        let second = try await model.store.createRecording()
        let secondTicket = try await model.store.beginRecognition(recordingID: second.id)
        let secondPreview = try await model.store.applyRecognition(ticket: secondTicket, text: "第二段独立文字", isFinal: false)
        try check(secondPreview && model.panelCapturePresentation.state == .recognizing &&
            model.panelCapturePresentation.liveVoiceLevel == 0.625, "new speech becomes active while the previous segment is pending")
        let accepted = try await model.store.applyRecognition(ticket: firstTicket, text: "第一段迟到定稿", isFinal: true)
        try await model.store.finishRecognition(ticket: firstTicket); await model.refresh()
        let firstRows = model.recent.filter { $0.id == first.id }, secondRows = model.recent.filter { $0.id == second.id }
        try check(accepted && firstRows.count == 1 && firstRows.first?.text == "第一段迟到定稿" &&
            secondRows.count == 1 && secondRows.first?.text == "第二段独立文字" &&
            model.panelCapturePresentation.state == .recognizing && model.panelCapturePresentation.liveVoiceLevel == 0.625,
            "late final changes only its original text and preserves the new speech waveform")
        let retryTicket = try await model.store.beginFusionRecognition(recordingID: first.id)
        let retryRun = try await model.store.beginModelRun(ticket: retryTicket, configuration: reviewer)
        try await model.store.finishModelRun(retryRun)
        try await model.store.failRecognition(ticket: retryTicket, message: "合成迟到的旧段重识别失败"); await model.refresh()
        let failedRetry = try await model.store.recording(id: first.id)
        try check(failedRetry?.recognitionState == .failed && failedRetry?.text == "第一段迟到定稿" &&
            model.panelCapturePresentation.state == .recognizing && model.panelCapturePresentation.liveVoiceLevel == 0.625,
            "failure of an older retry preserves newer speech and the old segment's saved text")
        model.clearPanel(); await model.refresh()
        try check(model.recent.isEmpty && model.panelCapturePresentation.state == .recognizing && capture.pauses == 0,
            "clearing visible text leaves current voice capture active")
        model.toggleCapture(); try await until("pause speaking") { capture.pauses == 1 }
        try check(model.panelCapturePresentation.state == .paused && model.panelCapturePresentation.symbolName == "play.fill" &&
            model.panelCapturePresentation.accessibilityValue == "暂停" && model.captureActionLabel == "继续收音" && model.panelCapturePresentation.liveVoiceLevel == nil,
            "user pause shares the first-launch triangle and now offers resume")
        try await model.store.finishModelRun(reviewRun)
        try await model.store.failRecognition(ticket: reviewTicket, message: "合成旧任务失败")
        try await model.store.finishRecording(id: second.id)
        let secondFinal = try await model.store.applyRecognition(ticket: secondTicket, text: "第二段暂停后定稿", isFinal: true)
        try await model.store.finishRecognition(ticket: secondTicket); await model.refresh()
        let finalRow = try await model.store.recording(id: second.id)
        try check(secondFinal && finalRow?.text == "第二段暂停后定稿" && capture.starts == 1 && !model.isListening &&
            model.panelCapturePresentation.state == .paused && model.panelCapturePresentation.liveVoiceLevel == nil,
            "late old failure and final text cannot restart user-paused capture")
        let archive = try await model.store.createRecording(createdAt: .distantPast)
        try await model.store.finishRecording(id: archive.id)
        let archiveTicket = try await model.store.beginFusionRecognition(recordingID: archive.id)
        let archiveRun = try await model.store.beginModelRun(ticket: archiveTicket, configuration: reviewer)
        model.toggleCapture(); try await until("resume") { capture.starts == 2 }
        let pendingArchive = try await model.store.recording(id: archive.id)
        try check(pendingArchive?.recognitionState == .running && model.panelCapturePresentation.state == .standby &&
            model.captureActionLabel == "暂停收音" && model.isListening,
            "explicit resume returns to standby while an earlier job is still running")
        let quietRetry = try await model.store.beginFusionRecognition(recordingID: first.id)
        let quietRetryRun = try await model.store.beginModelRun(ticket: quietRetry, configuration: reviewer)
        await model.refresh()
        let retryingRow = try await model.store.recording(id: first.id)
        try check(retryingRow?.recognitionState == .running && model.panelCapturePresentation.state == .standby &&
            model.panelCapturePresentation.liveVoiceLevel == nil, "re-recognition of a settled record leaves standby quiet")
        model.stageInPanel(DisplayRecording(source: try await model.store.recording(id: archive.id)!), showPanel: false)
        await model.refresh()
        try check(model.recent.contains(where: { $0.id == archive.id }) && model.panelCapturePresentation.state == .standby,
            "explicitly restoring an archive with running fusion does not simulate speech")
        model.clearPanel(); await model.refresh()
        let newest = try await model.store.createRecording(); await model.refresh()
        try check(model.panelCapturePresentation.state == .standby && model.recent.contains(where: { $0.id == newest.id }),
            "an open Store row alone cannot manufacture VAD activity after panel clearing")
        try await model.store.finishRecording(id: newest.id); try await model.store.deleteRecord(recordingID: newest.id)
        await model.refresh()
        let activeAfterDelete = try await model.store.activeRecognitionPhases(recordingIDs: [archive.id])
        try check(activeAfterDelete[archive.id] == .textFusion && model.panelCapturePresentation.state == .standby &&
            model.panelCapturePresentation.liveVoiceLevel == nil, "deleting the newest row cannot surface older background work as speech")
        model.toggleCapture(); try await until("pause standby") { capture.pauses == 2 }
        try await model.store.finishModelRun(quietRetryRun); try await model.store.finishRecognition(ticket: quietRetry)
        try await model.store.finishModelRun(archiveRun); try await model.store.finishRecognition(ticket: archiveTicket); await model.refresh()
        try check(model.panelCapturePresentation.state == .paused && capture.starts == 2,
            "pausing from standby is independent from completion of a historical job")
        let retained = try await model.store.recording(id: saved.id)
        try check(retained?.text == "已保存的文字😀", "pause, finalization and panel clearing preserve saved text")

        capture.state = .interrupted("合成输入设备断开")
        try check(model.captureProblem && model.panelCapturePresentation.state == .recoveryNeeded &&
            model.panelCapturePresentation.accessibilityValue.contains("合成输入设备断开") && model.panelCapturePresentation.liveVoiceLevel == nil,
            "interruption remains actionable outside the three ordinary states")
        model.toggleCapture(); try await until("capture fixture explicit recovery") { capture.starts == 3 }
        capture.state = .starting
        try check(model.panelCapturePresentation.state == .starting && model.captureActionLabel == "取消开启" &&
            model.panelCapturePresentation.liveVoiceLevel == nil, "startup remains a cancellable exception")
        model.toggleCapture(); try await until("capture fixture cancels startup") { capture.pauses == 3 }
        try check(model.panelCapturePresentation.state == .paused && model.panelCaptureDetail == nil,
            "the single control cancels preparation into static pause")
        try check(model.audio.state == .paused && connection.verificationCalls == 0,
            "all presentation and preference checks avoid the actual microphone and provider network")
        model.notice = "独立资料库提示"
        capture.startResult = .interrupted("合成麦克风权限不足")
        capture.startIssue = "合成麦克风权限恢复路径"
        model.toggleCapture()
        try await until("capture error detail") { model.panelCaptureDetail == capture.startIssue }
        try check(model.notice == "独立资料库提示", "an actionable capture interruption preserves an unrelated board notice")
        capture.startResult = .listening; capture.startIssue = nil
        model.toggleCapture()
        try await until("capture recovered without stale notice") { model.panelCapturePresentation.state == .standby }
        try check(model.panelCaptureDetail == nil && model.notice == "独立资料库提示",
                  "a successful resume removes the former microphone error and restores the unrelated notice")
        await model.prepareForExit()
        return count
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
        var configuration = RecognitionConfiguration(); configuration.automaticRecovery = false; configuration.languagePreference = .chinese
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
        try check(model.recognitionConfiguration.models.first(where: { $0.id == first.id })?.credentialGeneration == nil,
                  "failed credential save cannot change the account authorization generation")
        fixture.failSave = false
        for item in configuration.enabledModels {
            try check(model.saveCredential("simulator-fixture-credential", for: item), "fixture credential saved without Keychain access for " + item.provider.rawValue)
            let generation = model.recognitionConfiguration.models.first(where: { $0.id == item.id })?.credentialGeneration
            try check(generation != nil && model.appliedRecognitionConfiguration.models.first(where: { $0.id == item.id })?.credentialGeneration == generation &&
                        RecognitionConfiguration.load(from: preferences).models.first(where: { $0.id == item.id })?.credentialGeneration == generation,
                      "successful credential save persists a new opaque account generation in draft and runtime configuration for " + item.provider.rawValue)
        }
        let savedGeneration = model.recognitionConfiguration.models.first(where: { $0.id == first.id })?.credentialGeneration
        try check(model.saveCredential("simulator-fixture-credential", for: first) &&
                    model.recognitionConfiguration.models.first(where: { $0.id == first.id })?.credentialGeneration != savedGeneration,
                  "replacing a saved key rotates authorization even when the synthetic value is unchanged")
        var staleItem = first; staleItem.id = UUID()
        try check(!model.saveCredential("simulator-fixture-credential", for: staleItem) && !model.removeCredential(for: staleItem),
                  "stale UI credential actions cannot mutate an untracked account identity")
        staleItem = first; staleItem.provider = .meta
        try check(!model.saveCredential("simulator-fixture-credential", for: staleItem) && !model.removeCredential(for: staleItem),
                  "a stale provider editor cannot change another credential namespace")
        let disabled = configuration.models.first(where: { !$0.enabled })!
        try check(model.saveCredential("simulator-fixture-credential", for: disabled) &&
                    model.recognitionConfiguration.models.first(where: { $0.id == disabled.id })?.credentialGeneration != nil &&
                    RecognitionConfiguration.load(from: preferences).models.first(where: { $0.id == disabled.id })?.credentialGeneration ==
                        model.recognitionConfiguration.models.first(where: { $0.id == disabled.id })?.credentialGeneration,
                  "disabled services persist credential identity even when absent from connection fingerprints")
        try await until("local configuration drain") { !model.applyingRecognitionSettings }
        model.connectionCheckAuthorized = true; model.checkRecognitionConnections()
        try await until("simulated verification entry") { fixture.verificationContinuation != nil }
        try check(model.checkingConnection, "check remains active while actual controller awaits backend")
        try fixture.publish(.accountAccepted)
        try await until("account accepted progress") { model.connectionReport?.services.allSatisfy({ $0.state == .accountAccepted }) == true }
        try check(!model.connectionVerified && model.checkingConnection, "the two selected services are not final connection success")
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
        let beforeDeleteGeneration = model.recognitionConfiguration.models.first(where: { $0.id == first.id })?.credentialGeneration
        try check(!model.removeCredential(for: first) && model.hasCredential(first) && !model.connectionVerified && !fixture.runtimeCloud,
                  "failed credential removal preserves key metadata but keeps runtime local and receipt revoked")
        try check(model.recognitionConfiguration.models.first(where: { $0.id == first.id })?.credentialGeneration == beforeDeleteGeneration,
                  "failed credential removal preserves its authorization generation")
        try check(!fixture.mutationObservedCloudRuntime,
                  "cloud runtime is synchronously revoked before any credential mutation can expose another account")
        fixture.failDelete = false
        try await until("failed credential removal local drain") { !model.applyingRecognitionSettings }
        model.connectionCheckAuthorized = true; model.checkRecognitionConnections()
        try await until("test-only reconnection after failed mutation") { fixture.verificationContinuation != nil }
        try fixture.finish(.verified, live: true, completed: true)
        try await until("reconnected test-only receipt applied") { !model.checkingConnection && !model.applyingRecognitionSettings }
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
        let deletedGeneration = model.recognitionConfiguration.models.first(where: { $0.id == first.id })?.credentialGeneration
        try check(deletedGeneration != nil && deletedGeneration != beforeDeleteGeneration &&
                    RecognitionConfiguration.load(from: preferences).models.first(where: { $0.id == first.id })?.credentialGeneration == deletedGeneration,
                  "successful key deletion durably changes account identity before any later connection")
        fixture.releaseApply(); fixture.holdCloudApply = false
        try await until("revoked apply drained") { !model.applyingRecognitionSettings }
        try check(!fixture.runtimeCloud && !model.appliedRecognitionConfiguration.cloudEnabled &&
                    !RecognitionConfiguration.load(from: preferences).cloudEnabled,
                  "late completion of revoked apply cannot restore cloud state or persisted settings")
        _ = model.saveCredential("simulator-fixture-credential", for: first)
        try await until("restored fixture credential local drain") { !model.applyingRecognitionSettings }
        model.connectionCheckAuthorized = true; model.checkRecognitionConnections()
        try await until("cancelled check entry") { fixture.verificationContinuation != nil }
        try await until("cancelled check progress visible") { model.connectionReport?.services.count == 2 }
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
        try check(model.connectionReport?.services.map(\.state) == [.verified, .failed],
                  "cancelling preserves the selected ASR and GPT service outcomes")
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
