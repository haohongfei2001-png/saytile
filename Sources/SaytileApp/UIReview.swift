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
            try await reviewWindow(InputPanelView(model: model), size: CGSize(width: 340, height: 240), name: "panel-empty", output: output)
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
            try await reviewWindow(InputPanelView(model: model), size: CGSize(width: 340, height: 240), name: "panel-content", output: output) { host in
                try await self.selectMenu("直接输入", in: host)
                try await self.reviewUntil { model.directMode }
                guard model.directMode else { throw ReviewFailure("direct mode button did not change mode") }
                print("UI_NATIVE_MENU_ACK direct_mode=true")
                try await self.selectMenu("自由记录", in: host)
                try await self.reviewUntil { !model.directMode }
                guard !model.directMode else { throw ReviewFailure("free record button did not restore mode") }
                print("UI_NATIVE_MENU_ACK direct_mode=false")
                print("UI_CONTROL_PASS modes through real native More menu actions")
            }
            try await reviewWindow(InputPanelView(model: model), size: CGSize(width: 320, height: 200), name: "panel-compact", output: output)
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
                try await reviewWindow(InputPanelView(model: model), size: CGSize(width: 360, height: 260), name: "panel-ai-review", output: output)
                try await model.store.finishModelRun(run, error: "合成复核连接中断", retryable: true)
                try await model.store.failRecognition(ticket: ticket, message: "合成复核连接中断，原音与文字已保留")
                await model.refresh()
                guard let failed = model.recent.first(where: { $0.id == row.id }),
                      model.recognitionPhaseLabel(for: failed) == "识别待恢复", failed.text == row.text else {
                    throw ReviewFailure("failed review changed existing text or retained stale running phase")
                }
                try await reviewWindow(InputPanelView(model: model), size: CGSize(width: 360, height: 260), name: "panel-ai-recovery", output: output)
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
            try await reviewCompactPanel(output: output)
            if ProcessInfo.processInfo.environment["SAYTILE_UI_CONTROL_PROBE"] == nil { print("UI_CONTROLS_NOT_RUN remote AX helper not configured; rendering only") }
            let captures = ProcessInfo.processInfo.environment["SAYTILE_UI_CONTROL_PROBE"] == nil ? 20 : 31
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
        _ = try await performControl(label, in: root)
    }
    @MainActor private func selectMenu(_ item: String, in root: NSView) async throws {
        _ = try await performControl("panel.more", in: root, arguments: ["select-menu", item])
    }
    @MainActor private func setValue(_ value: String, for label: String, in root: NSView, secure: Bool = false) async throws {
        _ = try await performControl(label, in: root, arguments: ["set-value", value])
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
              field.window === window else {
            throw ReviewFailure("unique native field unavailable for \(label)")
        }
        try checkKeyboardIsolation(window, phase: "before-field-edit")
        guard window.makeFirstResponder(field),
              let editor = window.fieldEditor(false, for: field) as? NSTextView else {
            throw ReviewFailure("unique native field editor unavailable for \(label)")
        }
        editor.insertText(value, replacementRange: NSRange(location: 0, length: editor.string.utf16.count))
        _ = window.makeFirstResponder(root)
        try await Task.sleep(for: .milliseconds(80))
        try checkKeyboardIsolation(window, phase: "after-field-edit")
        print("NATIVE_UI_FIELD_EDIT \(label) via owned NSTextView delegate; no global key events")
        if secure { print("NATIVE_UI_SECURE_FIELD_EDIT \(label) fixture credential only; value omitted") }
    }
    @MainActor private func performControl(_ label: String, in root: NSView, arguments: [String] = []) async throws -> String {
        guard let path = ProcessInfo.processInfo.environment["SAYTILE_UI_CONTROL_PROBE"], let window = root.window else { throw ReviewFailure("Native UI control helper not configured") }
        let process = Process(), pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = [String(ProcessInfo.processInfo.processIdentifier), label, window.title]
        process.arguments! += arguments
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
        return result.1
    }
    @MainActor private func reviewWindow<V: View>(_ content: V, size: CGSize, name: String, output: URL,
        interaction: (@MainActor (NSView) async throws -> Void)? = nil) async throws {
        // Keep legacy trailing closures unambiguously control-only. Rendering checks use
        // a distinct entry point so an optional closure cannot bind to validation.
        try await reviewValidatedWindow(content, size: size, name: name, output: output,
                                        validation: nil, interaction: interaction)
    }
    @MainActor private func reviewValidatedWindow<V: View>(_ content: V, size: CGSize, name: String, output: URL,
        validation: (@MainActor (NSView) async throws -> Void)? = nil,
        interaction: (@MainActor (NSView) async throws -> Void)? = nil) async throws {
        let before = NSWorkspace.shared.frontmostApplication?.processIdentifier
        let ownPID = ProcessInfo.processInfo.processIdentifier
        let activations = ReviewActivations(ownPID: ownPID)
        let observer = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { note in
            if let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication {
                activations.record(pid: app.processIdentifier)
            }
        }
        defer { NSWorkspace.shared.notificationCenter.removeObserver(observer) }
        let panel = ReviewPanel(contentRect: CGRect(origin: CGPoint(x: 0, y: 0), size: size),
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
        if name.hasPrefix("panel-") {
            guard (320...360).contains(host.bounds.width), (200...480).contains(host.bounds.height),
                  abs(host.bounds.width - size.width) < 1, abs(host.bounds.height - size.height) < 1 else {
                throw ReviewFailure("compact panel exceeded its requested native geometry")
            }
        }
        try checkKeyboardIsolation(panel, phase: "before-validation")
        if let validation { try await validation(host); host.layoutSubtreeIfNeeded() }
        try checkKeyboardIsolation(panel, phase: "after-validation")
        if let interaction, ProcessInfo.processInfo.environment["SAYTILE_UI_CONTROL_PROBE"] != nil { try await interaction(host); try await Task.sleep(for: .milliseconds(100)); host.layoutSubtreeIfNeeded() }
        try checkKeyboardIsolation(panel, phase: "after-interaction")
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

    @MainActor private func checkKeyboardIsolation(_ window: NSWindow, phase: String) throws {
        guard window is ReviewPanel, !window.canBecomeKey, !window.canBecomeMain,
              !window.isKeyWindow, !window.isMainWindow else {
            throw ReviewFailure("native review window violated keyboard isolation during \(phase)")
        }
        print("UI_KEYBOARD_ISOLATION \(phase) can_become_key=false can_become_main=false is_key=false is_main=false")
    }

    @MainActor private func captureReview(_ host: NSView, name: String, output: URL) throws {
        guard let window = host.window else { throw ReviewFailure("native capture window unavailable") }
        try checkKeyboardIsolation(window, phase: "capture")
        host.layoutSubtreeIfNeeded()
        guard let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { throw CocoaError(.fileWriteUnknown) }
        host.cacheDisplay(in: host.bounds, to: bitmap)
        guard let data = bitmap.representation(using: .png, properties: [:]) else { throw CocoaError(.fileWriteUnknown) }
        try data.write(to: output.appendingPathComponent(name + ".png"))
        let geometry: [String: Any] = ["name": name, "width_points": host.bounds.width, "height_points": host.bounds.height,
                                      "width_pixels": bitmap.pixelsWide, "height_pixels": bitmap.pixelsHigh]
        print("UI_IMAGE_GEOMETRY " + String(decoding: try JSONSerialization.data(withJSONObject: geometry, options: [.sortedKeys]), as: UTF8.self))
    }

    @MainActor private func reviewUntil(_ condition: () -> Bool) async throws {
        for _ in 0..<250 {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(20))
        }
        throw ReviewFailure("native UI controller did not acknowledge the expected state within five seconds")
    }

    @MainActor private func inspectCapture(_ label: String, in host: NSView) async throws {
        let output = try await performControl("panel.capture", in: host, arguments: ["inspect"])
        guard let line = output.split(separator: "\n").first(where: { $0.hasPrefix("NATIVE_UI_INSPECT ") }),
              let detail = try JSONSerialization.jsonObject(with: Data(line.dropFirst("NATIVE_UI_INSPECT ".count).utf8)) as? [String: Any],
              let width = detail["width"] as? Double, let height = detail["height"] as? Double,
              (34...38).contains(width), (34...38).contains(height),
              (detail["names"] as? [String])?.contains(label) == true else {
            throw ReviewFailure("capture button native size or action label did not match \(label)")
        }
    }

    @MainActor private func compactTranscript(in host: NSView) throws -> CompactTranscriptScrollView {
        var pending = [host], found: [CompactTranscriptScrollView] = []
        while !pending.isEmpty {
            let view = pending.removeFirst()
            if let transcript = view as? CompactTranscriptScrollView { found.append(transcript) }
            pending += view.subviews
        }
        guard found.count == 1, let result = found.first, result.window === host.window else {
            throw ReviewFailure("panel must contain one owned native transcript")
        }
        return result
    }

    @MainActor private func reviewCompactPanel(output: URL) async throws {
        let suite = "app.saytile.test.compact-panel." + UUID().uuidString
        let preferences = UserDefaults(suiteName: suite)!
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("saytile-ui-panel-" + UUID().uuidString)
        defer { preferences.removePersistentDomain(forName: suite); try? FileManager.default.removeItem(at: directory) }
        var configuration = RecognitionConfiguration(); configuration.automaticRecovery = false
        try configuration.save(to: preferences)
        let capture = UIPanelCaptureFixture(), connection = UIConnectionFixture()
        let model = try AppModel(directory: directory, preferences: preferences,
            connectionDependencies: connection.dependencies, captureDependencies: capture.dependencies)
        await model.initialLoad()
        let hasControls = ProcessInfo.processInfo.environment["SAYTILE_UI_CONTROL_PROBE"] != nil
        do {
            try await reviewWindow(InputPanelView(model: model), size: CGSize(width: 340, height: 240),
                name: "panel-capture-initial", output: output) { host in
                try await self.inspectCapture("开始收音", in: host)
            }
            if hasControls {
                try await reviewWindow(InputPanelView(model: model), size: CGSize(width: 340, height: 240),
                    name: "panel-capture-controls", output: output) { host in
                    try await self.press("panel.capture", in: host)
                    try await self.reviewUntil { capture.starts == 1 && capture.state == .listening }
                    try await self.inspectCapture("暂停收音", in: host)
                    try self.captureReview(host, name: "panel-capture-listening", output: output)
                    try await self.press("panel.capture", in: host)
                    try await self.reviewUntil { capture.pauses == 1 && capture.state == .paused }
                    try await self.inspectCapture("继续收音", in: host)
                    try self.captureReview(host, name: "panel-capture-paused", output: output)
                    try await self.press("panel.capture", in: host)
                    try await self.reviewUntil { capture.starts == 2 && capture.state == .listening && model.panelCaptureLabel == "聆听中" }
                    guard model.captureActionLabel == "暂停收音" else { throw ReviewFailure("resuming capture did not restore the pause action") }
                    print("UI_NATIVE_CAPTURE_ACK paused_to_listening starts=2; actual capture button, injected microphone boundary")
                    try await self.press("panel.capture", in: host)
                    try await self.reviewUntil { capture.pauses == 2 && capture.state == .paused }
                    capture.state = .starting; model.objectWillChange.send()
                    try await Task.sleep(for: .milliseconds(100))
                    try await self.inspectCapture("取消开启", in: host)
                    try self.captureReview(host, name: "panel-capture-starting", output: output)
                    try await self.press("panel.capture", in: host)
                    try await self.reviewUntil { capture.pauses == 3 && capture.state == .paused }
                    capture.state = .interrupted("合成设备暂不可用，原音与文字仍保留。")
                    model.objectWillChange.send()
                    try await Task.sleep(for: .milliseconds(100))
                    try await self.inspectCapture("恢复收音", in: host)
                    try self.captureReview(host, name: "panel-capture-interrupted", output: output)
                    try await self.press("panel.capture", in: host)
                    try await self.reviewUntil { capture.starts == 3 && capture.state == .listening }
                    try await self.press("panel.capture", in: host)
                    try await self.reviewUntil { capture.pauses == 4 && capture.state == .paused }
                    guard model.audio.state == .paused else { throw ReviewFailure("fixture capture reached the actual audio controller") }
                    print("UI_CONTROL_PASS one 34–38pt capture button: start, pause, resume, cancel preparation and recovery; injected actions, no microphone")
                }
            }
            let text = (0..<70).map { "第\($0 + 1)行：保留完整表达和原有否定词，不要支付15元。Swift API cafe\u{301} 😀。" }.joined(separator: "\n")
            let row = try await model.store.createRecording()
            _ = try await model.store.saveEdit(recordingID: row.id, text: text)
            try await model.store.finishRecording(id: row.id); await model.refresh()
            var archives = 0, settings = 0, hides = 0
            model.openArchive = { archives += 1 }; model.openSettings = { settings += 1 }; model.hidePanel = { hides += 1 }
            try await reviewValidatedWindow(InputPanelView(model: model), size: CGSize(width: 360, height: 480),
                name: "panel-long-text", output: output, validation: { host in
                let scroll = try self.compactTranscript(in: host)
                try await self.reviewUntil { scroll.transcriptView.string.utf16.elementsEqual(text.utf16) }
                guard !scroll.transcriptView.isEditable, scroll.transcriptView.isSelectable else { throw ReviewFailure("transcript selection contract changed") }
                let composed = text.precomposedStringWithCanonicalMapping
                guard composed == text, composed.utf16.count != text.utf16.count else { throw ReviewFailure("Unicode fixture did not differ in UTF-16 representation") }
                for replacement in [composed, text] {
                    _ = try await model.store.saveEdit(recordingID: row.id, text: replacement); await model.refresh()
                    try await self.reviewUntil { scroll.transcriptView.string.utf16.elementsEqual(replacement.utf16) }
                    guard scroll.transcriptView.string.utf16.count == replacement.utf16.count else { throw ReviewFailure("native Unicode replacement retained stale UTF-16 length") }
                }
                print("UI_NATIVE_UNICODE_PASS Store-driven NFD to NFC to NFD preserves exact UTF-16 text and length")
                scroll.contentView.scroll(to: .zero); scroll.reflectScrolledClipView(scroll.contentView)
                let selected = NSRange(location: 3, length: 9)
                scroll.transcriptView.setSelectedRange(selected)
                let origin = scroll.contentView.bounds.origin
                let updated = text.replacingOccurrences(of: "第1行：保留完整表达", with: "第1行：更新后仍保留完整表达😀")
                    + "\n新增表达：否定、数字和术语必须保持完整。"
                _ = try await model.store.saveEdit(recordingID: row.id, text: updated); await model.refresh()
                try await self.reviewUntil { scroll.latestText == updated }
                guard scroll.hasDeferredUpdate, scroll.transcriptView.string == text,
                      scroll.transcriptView.selectedRange() == selected,
                      abs(scroll.contentView.bounds.origin.y - origin.y) < 1 else {
                    throw ReviewFailure("live revision replaced selected text or stole its viewport")
                }
                try self.captureReview(host, name: "panel-selection-held", output: output)
                if hasControls { try await self.press("panel.latest", in: host) } else { scroll.jumpToLatest() }
                try await self.reviewUntil { scroll.transcriptView.string == updated && scroll.isFollowingLatest }
                guard scroll.transcriptView.selectedRange().length == 0,
                      scroll.documentVisibleRect.maxY >= scroll.transcriptView.bounds.maxY - 5 else { throw ReviewFailure("latest action did not apply pending text and reach the tail") }
                try self.captureReview(host, name: "panel-latest", output: output)
                scroll.contentView.scroll(to: NSPoint(x: 0, y: 120)); scroll.reflectScrolledClipView(scroll.contentView)
                try await self.reviewUntil { !scroll.isFollowingLatest }
                let readingOrigin = scroll.contentView.bounds.origin
                let appended = updated + "\n用户上滚阅读时继续接收的新一句。"
                _ = try await model.store.saveEdit(recordingID: row.id, text: appended); await model.refresh()
                try await self.reviewUntil { scroll.transcriptView.string == appended }
                guard !scroll.isFollowingLatest, abs(scroll.contentView.bounds.origin.y - readingOrigin.y) < 1 else {
                    throw ReviewFailure("append stole the user's native scroll position")
                }
                guard let layout = scroll.transcriptView.layoutManager, let container = scroll.transcriptView.textContainer else {
                    throw ReviewFailure("native text layout unavailable")
                }
                let beforePoint = NSPoint(x: 0, y: scroll.documentVisibleRect.minY - scroll.transcriptView.textContainerInset.height)
                let beforeCharacter = layout.characterIndexForGlyph(at: layout.glyphIndex(for: beforePoint, in: container))
                let prefix = "新增的合成开头只调整上方排版，不应改变正在阅读的位置。\n"
                let prepended = prefix + appended
                _ = try await model.store.saveEdit(recordingID: row.id, text: prepended); await model.refresh()
                try await self.reviewUntil { scroll.transcriptView.string == prepended }
                let afterPoint = NSPoint(x: 0, y: scroll.documentVisibleRect.minY - scroll.transcriptView.textContainerInset.height)
                let afterCharacter = layout.characterIndexForGlyph(at: layout.glyphIndex(for: afterPoint, in: container))
                guard !scroll.isFollowingLatest, afterCharacter == beforeCharacter + prefix.utf16.count else {
                    throw ReviewFailure("earlier text revision changed the visible reading anchor")
                }
                if hasControls { try await self.press("panel.latest", in: host) } else { scroll.jumpToLatest() }
                try await self.reviewUntil { scroll.isFollowingLatest }
                print("UI_NATIVE_TEXT_PASS actual read-only NSTextView selection, Store-driven updates, manual scroll retention and explicit latest; no focus or key events")
                if hasControls { print("UI_CONTROL_PASS native latest button resumes one continuous transcript after selection and scrolling") }
            }, interaction: { host in
                try await self.selectMenu("语音档案…", in: host)
                try await self.reviewUntil { archives == 1 }
                try await self.selectMenu("设置…", in: host)
                try await self.reviewUntil { settings == 1 }
                try await self.selectMenu("收起输入板", in: host)
                try await self.reviewUntil { archives == 1 && settings == 1 && hides == 1 }
                guard archives == 1, settings == 1, hides == 1 else { throw ReviewFailure("More menu navigation did not route to existing actions") }
                try await self.selectMenu("清空输入板（保留档案）", in: host)
                try await self.reviewUntil { model.recent.isEmpty }
                await model.refresh()
                guard model.recent.isEmpty, let saved = try await model.store.recording(id: row.id), saved.text.contains("用户上滚阅读") else {
                    throw ReviewFailure("More menu clear removed archive content")
                }
                model.stageInPanel(DisplayRecording(source: saved), showPanel: false); await model.refresh()
                print("UI_CONTROL_PASS More menu archive/settings/hide/clear actions; clearing retains saved text, no clipboard or external target")
            })
            await model.prepareForExit()
        } catch { await model.prepareForExit(); throw error }
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

/// Test windows cannot acquire keyboard focus, even when their owned field editor
/// is exercised programmatically. The consumer's actual VoicePanel is unchanged.
@MainActor private final class ReviewPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

@MainActor private final class UIPanelCaptureFixture {
    var state: CaptureState = .paused
    var starts = 0
    var pauses = 0
    var dependencies: AppCaptureDependencies {
        AppCaptureDependencies(state: { _ in self.state },
            start: { _ in self.starts += 1; self.state = .listening },
            pause: { _ in self.pauses += 1; self.state = .paused })
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
