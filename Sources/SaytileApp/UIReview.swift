import AppKit
import SwiftUI
import AVFoundation
import SaytileKit

// Runs only with --ui-review AND an explicitly isolated data directory. All text/audio is synthetic.
extension AppDelegate {
    @MainActor func runUIReview(model: AppModel, output: URL) async -> Bool {
        NSApp.setActivationPolicy(.prohibited)
        do {
            try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
            await model.initialLoad()
            guard model.records.isEmpty else { throw NSError(domain: "Saytile.UIReview", code: 2, userInfo: [NSLocalizedDescriptionKey: "UI review requires an empty isolated data directory"]) }
            try await reviewWindow(InputPanelView(model: model), size: CGSize(width: 400, height: 550), name: "panel-empty", output: output)
            let examples = [
                "周五的产品讨论，先把重点记下来。保持表达自然，停顿之后还可以继续。",
                "这周想留一点时间，把散落的想法整理成一页清晰的计划。不要自动发送，确认之后再决定。",
                "API、Swift 与中文可以放在同一段表达里。测试 emoji 😀，只显示一份持续修正的文字。"
            ]
            for (index, text) in examples.enumerated() {
                let row = try await model.store.createRecording(createdAt: Date().addingTimeInterval(Double(index)))
                _ = try await model.store.saveEdit(recordingID: row.id, text: text)
                try await model.store.finishRecording(id: row.id)
                if index == 1 { try await model.store.setPinned(recordingID: row.id, pinned: true) }
                if index == 2 { try await model.store.deleteAudio(recordingID: row.id) }
            }
            await model.refresh()
            try await reviewWindow(InputPanelView(model: model), size: CGSize(width: 400, height: 550), name: "panel-content", output: output) { host in
                try await self.press("直接输入", in: host)
                guard model.directMode else { throw ReviewFailure("direct mode button did not change mode") }
                try await self.press("自由记录", in: host)
                guard !model.directMode else { throw ReviewFailure("free record button did not restore mode") }
                print("UI_CONTROL_PASS mode buttons through native control events")
            }
            try await reviewWindow(InputPanelView(model: model), size: CGSize(width: 400, height: 440), name: "panel-compact", output: output)
            try await reviewWindow(ArchiveView(model: model), size: CGSize(width: 1040, height: 720), name: "archive", output: output) { host in
                try await self.press("已收藏", in: host)
                await model.refresh()
                guard model.recordFilter == .pinned, model.records.count == 1 else { throw ReviewFailure("native archive filter action failed: filter=\(model.recordFilter), count=\(model.records.count)") }
                try await self.press("全部记录", in: host)
                await model.refresh()
                guard model.records.count == 3 else { throw ReviewFailure("native archive all-records action failed") }
                print("UI_CONTROL_PASS archive filters through native control events and SQLite")
            }
            if let row = model.records.first {
                await model.selectForEditing(row)
                model.updateEditorDraft(row.text + "\n这是会自动保留的编辑草稿。")
                _ = await model.flushEditorDrafts()
                try await reviewWindow(ArchiveView(model: model), size: CGSize(width: 1120, height: 720), name: "archive-detail", output: output) { host in
                    try await self.press("保存修改", in: host)
                    for _ in 0..<50 {
                        if (try await model.store.recording(id: row.id))?.text.contains("自动保留的编辑草稿") == true { break }
                        try await Task.sleep(for: .milliseconds(20))
                    }
                    guard (try await model.store.recording(id: row.id))?.text.contains("自动保留的编辑草稿") == true else { throw ReviewFailure("native save action did not commit edit") }
                    print("UI_CONTROL_PASS native Save action commits immutable edit")
                }
                try await reviewWindow(ArchiveView(model: model), size: CGSize(width: 1120, height: 570), name: "archive-detail-compact", output: output)
                model.closeDetail()
            }
            model.query = "找不到的合成关键词"; await model.refresh()
            try await reviewWindow(ArchiveView(model: model), size: CGSize(width: 1040, height: 720), name: "archive-no-results", output: output)
            model.query = ""; model.notice = nil
            await model.refresh()
            if let row = model.records.first(where: { $0.source.audioState == .available }) {
                let ticket = try await model.store.beginFusionRecognition(recordingID: row.id)
                let review = ModelConfiguration(purpose: .textFusion, provider: .openAIResponses, model: "gpt-6-astra")
                let run = try await model.store.beginModelRun(ticket: ticket, configuration: review)
                await model.refresh()
                guard let active = model.recent.first(where: { $0.id == row.id }),
                      model.recognitionPhaseLabel(for: active) == "正在核对文字",
                      active.text == row.text, model.recent.filter({ $0.id == row.id }).count == 1 else {
                    throw ReviewFailure("single transcript or generic processing state was not retained")
                }
                try await reviewWindow(InputPanelView(model: model), size: CGSize(width: 400, height: 550), name: "panel-ai-review", output: output)
                try await model.store.finishModelRun(run, error: "合成复核连接中断", retryable: true)
                try await model.store.failRecognition(ticket: ticket, message: "合成复核连接中断，原音与文字已保留")
                await model.refresh()
                guard let failed = model.recent.first(where: { $0.id == row.id }),
                      model.recognitionPhaseLabel(for: failed) == "识别待恢复", failed.text == row.text else {
                    throw ReviewFailure("failed review changed existing text or retained stale running phase")
                }
                try await reviewWindow(InputPanelView(model: model), size: CGSize(width: 400, height: 550), name: "panel-ai-recovery", output: output)
                print("UI_STATE_PASS one transcript survives single-core processing and failure; synthetic Store runs, no providers")
            }
            try await reviewWindow(SettingsView(model: model), size: CGSize(width: 650, height: 740), name: "settings", output: output)
            try await reviewWindow(SettingsView(model: model), size: CGSize(width: 560, height: 570), name: "settings-compact", output: output)
            try await reviewWindow(Form { RecognitionSettingsSection(model: model) }.formStyle(.grouped), size: CGSize(width: 650, height: 840), name: "ai-controls", output: output) { host in
                guard !model.connectionVerified, !model.recognitionConfiguration.cloudEnabled else {
                    throw ReviewFailure("unconfigured cloud connection was enabled")
                }
                try await self.press("recognition.configureServices", in: host)
                guard !model.connectionCheckAuthorized else { throw ReviewFailure("cost authorization was preselected") }
                try await self.press("connection.authorizeCheck", in: host)
                guard model.connectionCheckAuthorized, !model.checkingConnection,
                      !model.appliedRecognitionConfiguration.cloudEnabled else {
                    throw ReviewFailure("cost consent started a connection or enabled cloud without prepared services")
                }
                model.recognitionSettingsNotice = nil
                try await self.press("recognition.apply", in: host)
                for _ in 0..<100 {
                    if !model.applyingRecognitionSettings, model.recognitionSettingsNotice != nil { break }
                    try await Task.sleep(for: .milliseconds(20))
                }
                guard !model.appliedRecognitionConfiguration.cloudEnabled, model.recognitionSettingsNotice != nil else {
                    throw ReviewFailure("unconfigured settings enabled cloud")
                }
                try await self.setValue("合成界面测试话题", for: "recognition.topicContext", in: host)
                guard model.recognitionConfiguration.topicContext == "合成界面测试话题" else { throw ReviewFailure("native topic field did not update draft") }
                try await self.press("recognition.apply", in: host)
                for _ in 0..<100 {
                    if !model.applyingRecognitionSettings, model.appliedRecognitionConfiguration.topicContext == "合成界面测试话题" { break }
                    try await Task.sleep(for: .milliseconds(20))
                }
                guard model.appliedRecognitionConfiguration.topicContext == "合成界面测试话题",
                      !model.appliedRecognitionConfiguration.cloudEnabled, !model.hasUnappliedRecognitionSettings else {
                    throw ReviewFailure("native settings apply did not commit isolated local configuration")
                }
                print("UI_CONTROL_PASS recognition settings: unverified cloud disabled, explicit cost authorization, offline apply and native text edit")
            }
            try await reviewWindow(Form { RecognitionSettingsSection(model: model, initiallyExpanded: true) }.formStyle(.grouped), size: CGSize(width: 650, height: 840), name: "ai-services", output: output)
            if !model.recognitionConfiguration.models.isEmpty {
                try await reviewWindow(Form {
                    Section("中文专家设置") {
                        ModelConfigurationEditor(configuration: Binding(get: { model.recognitionConfiguration.models[0] }, set: { model.recognitionConfiguration.models[0] = $0 }), model: model, initiallyExpanded: true)
                    }
                }.formStyle(.grouped), size: CGSize(width: 650, height: 740), name: "ai-chinese-keychain", output: output) { host in
                    let prefix = "recognition.model." + model.recognitionConfiguration.models[0].id.uuidString.lowercased()
                    guard model.recognitionConfiguration.models[0].enabled else { throw ReviewFailure("required expert unexpectedly disabled") }
                    try await self.setValue("synthetic-workspace", for: prefix + ".workspace", in: host)
                    guard model.recognitionConfiguration.models[0].workspaceID == "synthetic-workspace" else { throw ReviewFailure("native workspace field failed") }
                    try await self.press(prefix + ".consent", in: host)
                    guard model.recognitionConfiguration.models[0].cloudConsent else { throw ReviewFailure("native processing consent toggle failed") }
                    try await self.press(prefix + ".consent", in: host)
                    guard !model.recognitionConfiguration.models[0].cloudConsent,
                          model.recognitionConfiguration.models[0].enabled else { throw ReviewFailure("native model controls did not restore safe defaults") }
                    print("UI_CONTROL_PASS fixed dual-expert setup: workspace and per-service consent; no model toggle, key read or cloud request")
                }
            }
            let setupRoot = output.appendingPathComponent("connection-setup-" + UUID().uuidString, isDirectory: true)
            let setup = try ConnectionSetupRequest(directory: setupRoot, output: setupRoot.appendingPathComponent("configuration.json"))
            var setupFinished = false
            try await reviewWindow(ConnectionSetupView(model: model, request: setup, finish: { setupFinished = true }), size: CGSize(width: 650, height: 840), name: "connection-setup", output: output) { host in
                try await self.press("connectionSetup.finish", in: host)
                guard !setupFinished, !FileManager.default.fileExists(atPath: setup.output.path) else {
                    throw ReviewFailure("unready connection setup exported configuration or finished")
                }
                print("UI_CONTROL_PASS isolated setup rejects unfinished configuration through native Finish action; no export or provider request")
            }
            try await reviewFirstConnection(output: output)
            if ProcessInfo.processInfo.environment["SAYTILE_UI_CONTROL_PROBE"] == nil { print("UI_CONTROLS_NOT_RUN remote AX helper not configured; rendering only") }
            let captures = ProcessInfo.processInfo.environment["SAYTILE_UI_CONTROL_PROBE"] == nil ? 16 : 22
            print("UI_REVIEW_PASS native SwiftUI attached to AppKit windows; \(captures) captures; synthetic data; no activation/microphone")
            return true
        } catch { print("UI_REVIEW_FAILED \(error.localizedDescription)"); return false }
    }

    private struct ReviewFailure: LocalizedError {
        let message: String
        init(_ message: String) { self.message = message }
        var errorDescription: String? { message }
    }
    @MainActor private func press(_ label: String, in root: NSView) async throws {
        try await performControl(label, in: root)
    }
    @MainActor private func setValue(_ value: String, for label: String, in root: NSView, secure: Bool = false) async throws {
        try await performControl(label, in: root, value: value)
        // AXSetValue changes the AppKit presentation but does not necessarily send
        // SwiftUI's editing delegate events. Exercise the real, window-owned editor
        // to commit the same synthetic value; never call the model or post keys.
        var queue = [root], matching: [NSTextField] = []
        while !queue.isEmpty {
            let view = queue.removeFirst()
            if let field = view as? NSTextField, (field is NSSecureTextField) == secure, field.stringValue == value {
                matching.append(field)
            }
            queue += view.subviews
        }
        guard matching.count == 1, let field = matching.first, let window = root.window,
              field.window === window, window.makeFirstResponder(field),
              let editor = window.fieldEditor(false, for: field) as? NSTextView else {
            throw ReviewFailure("unique native field editor unavailable for \(label)")
        }
        editor.insertText(value, replacementRange: NSRange(location: 0, length: editor.string.utf16.count))
        _ = window.makeFirstResponder(root)
        try await Task.sleep(for: .milliseconds(80))
        print("NATIVE_UI_FIELD_EDIT \(label) via owned NSTextView delegate; no global key events")
        if secure { print("NATIVE_UI_SECURE_FIELD_EDIT \(label) fixture credential only; value omitted") }
    }
    @MainActor private func performControl(_ label: String, in root: NSView, value: String? = nil) async throws {
        guard let path = ProcessInfo.processInfo.environment["SAYTILE_UI_CONTROL_PROBE"], let window = root.window else { throw ReviewFailure("Native UI control helper not configured") }
        let process = Process(), pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = [String(ProcessInfo.processInfo.processIdentifier), label, window.title]
        if let value { process.arguments! += ["set-value", value] }
        process.standardOutput = pipe; process.standardError = pipe
        try process.run()
        let result = await Task.detached {
            let output = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            return (process.terminationStatus, String(decoding: output, as: UTF8.self))
        }.value
        print(result.1.trimmingCharacters(in: .whitespacesAndNewlines))
        guard result.0 == 0 else { throw ReviewFailure("Remote native AX action failed for \(label), code=\(result.0)") }
        try await Task.sleep(for: .milliseconds(80))
    }
    @MainActor private func reviewWindow<V: View>(_ content: V, size: CGSize, name: String, output: URL, interaction: (@MainActor (NSView) async throws -> Void)? = nil) async throws {
        let before = NSWorkspace.shared.frontmostApplication?.processIdentifier
        let ownPID = ProcessInfo.processInfo.processIdentifier
        let activations = ReviewActivations(ownPID: ownPID)
        let observer = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { note in
            if let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication {
                activations.record(pid: app.processIdentifier)
            }
        }
        defer { NSWorkspace.shared.notificationCenter.removeObserver(observer) }
        let panel = NSPanel(contentRect: CGRect(origin: CGPoint(x: 0, y: 0), size: size),
                            styleMask: [.titled, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.title = "Saytile UI Review " + name
        panel.alphaValue = 0
        panel.ignoresMouseEvents = true
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        let host = NSHostingView(rootView: content.preferredColorScheme(.light))
        panel.contentView = host
        panel.setContentSize(size)
        panel.makeFirstResponder(host)
        panel.orderBack(nil)
        defer { panel.orderOut(nil); panel.close() }
        try await Task.sleep(for: .milliseconds(200))
        host.layoutSubtreeIfNeeded()
        if let interaction, ProcessInfo.processInfo.environment["SAYTILE_UI_CONTROL_PROBE"] != nil { try await interaction(host); try await Task.sleep(for: .milliseconds(100)); host.layoutSubtreeIfNeeded() }
        try captureReview(host, name: name, output: output)
        let after = NSWorkspace.shared.frontmostApplication?.processIdentifier
        guard !activations.candidateActivated, after != ownPID else {
            throw ReviewFailure("candidate activated during \(name); other_activation_events=\(activations.otherActivations)")
        }
        if before != after || activations.otherActivations > 0 {
            print("UI_FOREGROUND_OBSERVATION \(name) candidate_activated=false outside_activation_events=\(activations.otherActivations); unrelated transition retained, no cause inferred")
        }
        print("UI_CAPTURE \(name) \(Int(host.bounds.width))x\(Int(host.bounds.height)) foreground_unchanged=\(before == after) candidate_activated=false")
    }

    @MainActor private func captureReview(_ host: NSView, name: String, output: URL) throws {
        host.layoutSubtreeIfNeeded()
        guard let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { throw CocoaError(.fileWriteUnknown) }
        host.cacheDisplay(in: host.bounds, to: bitmap)
        guard let data = bitmap.representation(using: .png, properties: [:]) else { throw CocoaError(.fileWriteUnknown) }
        try data.write(to: output.appendingPathComponent(name + ".png"))
    }

    @MainActor private func reviewUntil(_ condition: () -> Bool) async throws {
        for _ in 0..<250 {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(20))
        }
        throw ReviewFailure("first-connection controller did not reach the expected state")
    }

    @MainActor private func reviewFirstConnection(output: URL) async throws {
        let suite = "app.saytile.test.ui-connection." + UUID().uuidString
        let preferences = UserDefaults(suiteName: suite)!
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("saytile-ui-connection-" + UUID().uuidString)
        defer { preferences.removePersistentDomain(forName: suite); try? FileManager.default.removeItem(at: directory) }
        let fixture = UIConnectionFixture()
        let model = try AppModel(directory: directory, preferences: preferences, connectionDependencies: fixture.dependencies)
        await model.initialLoad()
        do {
            guard model.records.isEmpty, fixture.saved.isEmpty, !model.connectionVerified,
                  !model.recognitionConfiguration.cloudEnabled else { throw ReviewFailure("first connection fixture was not empty") }
            try await reviewWindow(Form { RecognitionSettingsSection(model: model) }.formStyle(.grouped),
                size: CGSize(width: 650, height: 840), name: "connection-first-empty", output: output)
            if ProcessInfo.processInfo.environment["SAYTILE_UI_CONTROL_PROBE"] != nil {
                try await reviewWindow(Form { RecognitionSettingsSection(model: model) }.formStyle(.grouped),
                    size: CGSize(width: 650, height: 840), name: "connection-first-success", output: output) { host in
                    try await self.press("recognition.configureServices", in: host)
                    for item in model.recognitionConfiguration.enabledModels {
                        let prefix = "recognition.model." + item.id.uuidString.lowercased()
                        try await self.press(prefix + ".header", in: host)
                        if item.provider == .qwenMessage { try await self.setValue("fixture-workspace", for: prefix + ".workspace", in: host) }
                        try await self.setValue(UIConnectionFixture.credential, for: prefix + ".secret", in: host, secure: true)
                        try await self.press(prefix + ".saveKey", in: host)
                        guard model.hasCredential(item) else { throw ReviewFailure("native save-key action failed") }
                        try await self.press(prefix + ".consent", in: host)
                        guard model.recognitionConfiguration.models.first(where: { $0.id == item.id })?.cloudConsent == true else {
                            throw ReviewFailure("native service consent did not update configuration")
                        }
                        try await self.press(prefix + ".header", in: host)
                    }
                    try await self.reviewUntil { !model.applyingRecognitionSettings }
                    guard fixture.saved.count == 3, !model.connectionCheckAuthorized, fixture.requests == 0,
                          model.recognitionConfiguration.models[0].workspaceID == "fixture-workspace" else {
                        throw ReviewFailure("first setup silently connected or did not save native fields")
                    }
                    try self.captureReview(host, name: "connection-first-ready", output: output)
                    print("UI_STATE_CAPTURE connection-first-ready after native secure fields/save/consent; no network")
                    try await self.press("connection.checkCosts", in: host)
                    try self.captureReview(host, name: "connection-first-costs", output: output)
                    print("UI_STATE_CAPTURE connection-first-costs after native disclosure action")
                    try await self.press("connection.checkCosts", in: host)
                    try await self.press("connection.authorizeCheck", in: host)
                    try await self.press("connection.startCheck", in: host)
                    try await self.reviewUntil { !model.checkingConnection && !model.applyingRecognitionSettings }
                    guard fixture.requests == 1, model.connectionVerified, model.appliedRecognitionConfiguration.cloudEnabled,
                          model.recognitionConfiguration.cloudEnabled else { throw ReviewFailure("native first connection did not pass the receipt-enable branch") }
                    print("UI_CONTROL_PASS first connection via native Workspace/three secure fields/save/consent/cost/start; TEST_ONLY injected receipt, no live verification")
                }
                fixture.outcome = .failure
                try await reviewWindow(Form { RecognitionSettingsSection(model: model, initiallyExpanded: true) }.formStyle(.grouped),
                    size: CGSize(width: 650, height: 840), name: "connection-first-failure", output: output) { host in
                    try await self.press("connection.authorizeCheck", in: host)
                    try await self.press("connection.startCheck", in: host)
                    try await self.reviewUntil { !model.checkingConnection }
                    guard fixture.requests == 2, !model.connectionVerified, !model.appliedRecognitionConfiguration.cloudEnabled,
                          model.connectionReport?.services.allSatisfy({ $0.state == .failed }) == true else { throw ReviewFailure("failed check did not keep local recognition") }
                    print("UI_CONTROL_PASS native retry displays isolated service failure and keeps cloud disabled")
                }
                fixture.outcome = .waitForCancellation
                try await reviewWindow(Form { RecognitionSettingsSection(model: model, initiallyExpanded: true) }.formStyle(.grouped),
                    size: CGSize(width: 650, height: 840), name: "connection-first-cancelled", output: output) { host in
                    try await self.press("connection.authorizeCheck", in: host)
                    try await self.press("connection.startCheck", in: host)
                    try await self.reviewUntil { model.connectionReport?.services.allSatisfy({ $0.state == .receiving }) == true }
                    try self.captureReview(host, name: "connection-first-progress", output: output)
                    print("UI_STATE_CAPTURE connection-first-progress from injected backend progress through actual AppModel")
                    try await self.press("connection.cancelCheck", in: host)
                    try await self.reviewUntil { !model.checkingConnection && fixture.active == 0 }
                    guard fixture.requests == 3, !model.connectionVerified, !model.appliedRecognitionConfiguration.cloudEnabled,
                          model.connectionReport?.services.allSatisfy({ $0.state == .cancelled }) == true else { throw ReviewFailure("native cancellation left stale connection cards") }
                    print("UI_CONTROL_PASS native cancel closes injected verification and settles all service cards")
                }
            }
            await model.prepareForExit()
        } catch { await model.prepareForExit(); throw error }
    }
}

/// Same AppModel dependency seam as the controller probe; only the peer outcome is
/// injected. Never read Keychain, upload audio or instantiate a provider transport.
@MainActor private final class UIConnectionFixture {
    enum Outcome { case success, failure, waitForCancellation }
    static let credential = "simulator-fixture-credential"
    var saved = Set<UUID>()
    var requests = 0
    var active = 0
    var outcome: Outcome = .success
    var dependencies: AppConnectionDependencies {
        AppConnectionDependencies(presence: { self.saved.contains($0.id) ? .saved : .missing },
            save: { value, item in
                guard value == Self.credential else { throw ProviderFailure.authorization }
                self.saved.insert(item.id)
            }, delete: { self.saved.remove($0.id) }, verify: { configuration, progress in
                guard configuration.enabledModels.allSatisfy({ self.saved.contains($0.id) && $0.cloudConsent }) else { throw ProviderFailure.authorization }
                self.requests += 1; self.active += 1; defer { self.active -= 1 }
                progress(try Self.report(configuration, state: .accountAccepted))
                try await Task.sleep(for: .milliseconds(150))
                progress(try Self.report(configuration, state: .receiving))
                if self.outcome == .waitForCancellation { try await Task.sleep(for: .seconds(30)); throw CancellationError() }
                try await Task.sleep(for: .milliseconds(150))
                return try Self.report(configuration, state: self.outcome == .success ? .verified : .failed)
            }, applyConfiguration: { _, _ in }, revokeCloud: { $0.revokeCloudRecognition() })
    }
    private static func report(_ configuration: RecognitionConfiguration, state: ConnectionServiceState) throws -> CloudConnectionReport {
        let success = state == .verified
        let rows: [[String: Any]] = configuration.enabledModels.map {
            var value: [String: Any] = ["id": $0.id.uuidString, "provider": $0.provider.rawValue, "state": state.rawValue]
            if state == .failed { value["code"] = "quota_exhausted"; value["message"] = "测试情形：服务余额不足，请在服务商账户处理后重新检查。" }
            return value
        }
        let value: [String: Any] = ["configurationFingerprint": CloudConnectionVerifier.fingerprint(configuration), "date": 0,
            "live": success, "services": rows, "transcript": success ? "TEST_ONLY：不要支付15元，send the report。" : "",
            "pipelineCompleted": success, "elapsedSeconds": 0, "reviewRequests": 0,
            "message": "TEST_ONLY 原生交互替身；未连接真实服务。"]
        return try JSONDecoder().decode(CloudConnectionReport.self, from: JSONSerialization.data(withJSONObject: value))
    }
}

// Records process identity transitions only, never another app's UI or contents.
private final class ReviewActivations: @unchecked Sendable {
    private let lock = NSLock()
    private let ownPID: pid_t
    private var own = false
    private var others = 0
    init(ownPID: pid_t) { self.ownPID = ownPID }
    func record(pid: pid_t) {
        lock.lock(); defer { lock.unlock() }
        if pid == ownPID { own = true } else { others += 1 }
    }
    var candidateActivated: Bool { lock.lock(); defer { lock.unlock() }; return own }
    var otherActivations: Int { lock.lock(); defer { lock.unlock() }; return others }
}
