import AppKit
import SwiftUI
import Combine
import Carbon
import Darwin
import SaytileKit

@main
struct SaytileMain {
    @MainActor static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        withExtendedLifetime(delegate) { app.run() }
    }
}

final class VoicePanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

final class VoiceEntryPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private var model: AppModel?
    private var status: NSStatusItem?
    private var panel: VoicePanel?
    private var voiceEntry: VoiceEntryPanel?
    private var archive: NSWindow?
    private var settings: NSWindow?
    private var connectionSetupWindow: NSWindow?
    private var hotKey: EventHotKeyRef?
    private var eventHandler: EventHandlerRef?
    private var shortcutObserver: NSObjectProtocol?
    private var entryObserver: NSObjectProtocol?
    private var screenObserver: NSObjectProtocol?
    private var statusSubscription: AnyCancellable?
    private var positioningPanel = false
    private var terminating = false
    private var shutdownStarted = false
    private var diagnosticPreferencesSuite: String?
    private var diagnosticExitStatus: Int32 = 0

    func applicationDidFinishLaunching(_ notification: Notification) {
        do {
            // An unsupported explicit-directory spelling must never fall back
            // to a normal launch against the user's default archive.
            guard !CommandLine.arguments.contains(where: { $0.hasPrefix("--data-directory=") }) else {
                print("DIAGNOSTICS_REQUIRE_SEPARATE_DATA_DIRECTORY_ARGUMENT")
                Darwin.exit(64)
            }
            let diagnostics = ["--smoke-test", "--device-probe", "--audio-probe", "--multi-asr-probe", "--render-preview", "--focus-probe", "--ui-review", "--connection-setup"]
            let isDiagnostic = diagnostics.contains(where: CommandLine.arguments.contains)
            let directoryIndex = CommandLine.arguments.firstIndex(of: "--data-directory")
            if isDiagnostic || directoryIndex != nil {
                guard let index = directoryIndex, CommandLine.arguments.count > index + 1,
                      !CommandLine.arguments[index + 1].trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                      !CommandLine.arguments[index + 1].hasPrefix("--") else {
                    print("DIAGNOSTICS_REQUIRE_EXPLICIT_ISOLATED_DATA_DIRECTORY")
                    Darwin.exit(64)
                }
            }
            let directory: URL
            if let index = directoryIndex {
                directory = URL(fileURLWithPath: CommandLine.arguments[index + 1], isDirectory: true)
            } else {
                directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Saytile", isDirectory: true)
            }
            if isDiagnostic || directoryIndex != nil {
                // Reject production aliases before AppModel/Store can migrate or
                // recover anything. A late "empty fixture" check is too late.
                do { try DiagnosticDirectory.validate(directory: directory) }
                catch { print("DIAGNOSTICS_REJECTED_DATA_DIRECTORY"); Darwin.exit(64) }
            }
            let setupRequest: ConnectionSetupRequest?
            if CommandLine.arguments.contains("--connection-setup") {
                guard !diagnostics.filter({ $0 != "--connection-setup" }).contains(where: CommandLine.arguments.contains),
                      let index = CommandLine.arguments.firstIndex(of: "--connection-output"),
                      CommandLine.arguments.count > index + 1,
                      CommandLine.arguments[index + 1].hasPrefix("/"),
                      directoryIndex.map({ CommandLine.arguments[$0 + 1].hasPrefix("/") }) == true else {
                    print("CONNECTION_SETUP_REQUIRES_ISOLATED_DIRECTORY_AND_OUTPUT")
                    Darwin.exit(64)
                }
                do {
                    setupRequest = try ConnectionSetupRequest(directory: directory,
                        output: URL(fileURLWithPath: CommandLine.arguments[index + 1]))
                } catch { print("CONNECTION_SETUP_REJECTED \(error.localizedDescription)"); Darwin.exit(64) }
            } else { setupRequest = nil }
            let preferences: UserDefaults
            if isDiagnostic || directoryIndex != nil {
                let suite = "app.saytile.diagnostics." + UUID().uuidString
                diagnosticPreferencesSuite = suite
                preferences = UserDefaults(suiteName: suite)!
                // Explicit test data also isolates preferences. Override only the
                // process argument domain, never inspect or alter the user's app
                // defaults, and prevent a normal held test process showing UI or
                // registering the user's global shortcut.
                preferences.setVolatileDomain(["hasLaunched": true, "shortcutChoice": "disabled", "floatingEntryEnabled": false], forName: UserDefaults.argumentDomain)
                // A research probe is one explicit attempt. The app's background
                // recovery must not start a different recognizer on its failed fixture.
                var diagnosticConfiguration = RecognitionConfiguration()
                diagnosticConfiguration.automaticRecovery = false
                try diagnosticConfiguration.save(to: preferences)
            } else { preferences = .standard }
            let model = try AppModel(directory: directory, preferences: preferences)
            self.model = model
            if let setupRequest {
                configureMainMenu()
                let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 680, height: 800),
                                      styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
                window.title = "Saytile · 连接识别服务"
                window.isReleasedWhenClosed = false; window.delegate = self
                window.contentView = NSHostingView(rootView: ConnectionSetupView(model: model, request: setupRequest) { NSApp.terminate(nil) })
                connectionSetupWindow = window
                window.center(); window.makeKeyAndOrderFront(nil); NSApp.activate()
                return
            }
            model.openPanel = { [weak self] in self?.showPanel() }
            model.hidePanel = { [weak self] in self?.hidePanel() }
            model.openArchive = { [weak self] in self?.showArchive() }
            model.openSettings = { [weak self] in self?.showSettings() }
            if let index = CommandLine.arguments.firstIndex(of: "--multi-asr-probe"), CommandLine.arguments.count > index + 1 {
                Task {
                    // Finish startup reconciliation before importing this new attempt.
                    await model.initialLoad()
                    do {
                        guard let configIndex = CommandLine.arguments.firstIndex(of: "--recognition-config"), CommandLine.arguments.count > configIndex + 1,
                              let reportIndex = CommandLine.arguments.firstIndex(of: "--report-dir"), CommandLine.arguments.count > reportIndex + 1 else {
                            throw AudioFailure.message("定向回放需要显式 --recognition-config 和 --report-dir。")
                        }
                        guard try await model.store.listRecordings(limit: 1).isEmpty else {
                            throw AudioFailure.message("定向回放须使用空的独立资料目录。")
                        }
                        let configuration = try JSONDecoder().decode(RecognitionConfiguration.self,
                            from: Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[configIndex + 1])))
                        let id = try await MultiRecognitionDiagnostics.transcribeFixture(
                            url: URL(fileURLWithPath: CommandLine.arguments[index + 1]), store: model.store, configuration: configuration,
                            allowSingleExpertBaseline: CommandLine.arguments.contains("--single-expert-baseline"))
                        let report = URL(fileURLWithPath: CommandLine.arguments[reportIndex + 1], isDirectory: true)
                        try FileManager.default.createDirectory(at: report, withIntermediateDirectories: true)
                        try await MultiRecognitionDiagnostics.exportTrace(store: model.store, recordingID: id,
                            to: report.appendingPathComponent(id.uuidString + ".json"))
                        let state = try await model.store.recording(id: id)?.recognitionState.rawValue ?? "unknown"
                        print("MULTI_ASR_PROBE_RECORDED recording=\(id) state=\(state); accuracy requires reference scoring")
                        if state != "completed" { self.diagnosticExitStatus = 2 }
                    } catch { self.diagnosticExitStatus = 1; print("MULTI_ASR_PROBE_FAILED \(error.localizedDescription)") }
                    await model.prepareForExit()
                    NSApp.terminate(nil)
                }
                return
            }
            if CommandLine.arguments.contains("--device-probe") {
                Task {
                    do { let result = try await AudioDiagnostics.probeInputDevice(seconds: 5); print("DEVICE_PROBE \(result)") }
                    catch { print("DEVICE_PROBE_ERROR \(error.localizedDescription)") }
                    await model.prepareForExit()
                    NSApp.terminate(nil)
                }
                return
            }
            if let index = CommandLine.arguments.firstIndex(of: "--audio-probe"), CommandLine.arguments.count > index + 1 {
                let fixture = URL(fileURLWithPath: CommandLine.arguments[index + 1])
                guard CommandLine.arguments.contains("--data-directory") else { print("PROBE_REQUIRES_ISOLATED_DATA_DIRECTORY"); NSApp.terminate(nil); return }
                Task {
                    let availability = await AppleSpeechService.availability()
                    print("SPEECH_AVAILABILITY \(availability.message)")
                    do {
                        if CommandLine.arguments.contains("--prepare-speech") { try await AppleSpeechService.prepare() }
                        let id = try await AudioDiagnostics.transcribeFixture(url: fixture, store: model.store)
                        if let record = try await model.store.recording(id: id) { print("SPEECH_RESULT \(record.recognitionState) \(record.text) error=\(record.lastError ?? "none")") }
                    } catch { print("SPEECH_PROBE_ERROR \(error)") }
                    await model.prepareForExit()
                    NSApp.terminate(nil)
                }
                return
            }
            if CommandLine.arguments.contains("--smoke-test") {
                Task {
                    await model.initialLoad()
                    do {
                        let sample = try CloudConnectionVerifier.bundledSample()
                        print("SAYTILE_SMOKE_OK records=\(model.records.count) microphone=\(model.microphoneLabel) bundled_sample_bytes=\(sample.count)")
                    } catch {
                        print("SAYTILE_SMOKE_FAILED bundled_connection_sample")
                        await model.prepareForExit(); exit(1)
                    }
                    await model.prepareForExit()
                    NSApp.terminate(nil)
                }
                return
            }
            if let index = CommandLine.arguments.firstIndex(of: "--render-preview"), CommandLine.arguments.count > index + 1 {
                let path = CommandLine.arguments[index + 1]
                Task {
                    await model.initialLoad()
                    if CommandLine.arguments.contains("--preview-detail"), let first = model.records.first {
                        model.selected = first
                        model.versions = (try? await model.store.revisions(recordingID: first.id).map { DisplayVersion(id: $0.id, text: $0.text, label: $0.origin == .userEdit ? "手动修改" : "语音识别") }) ?? []
                    }
                    if CommandLine.arguments.contains("--preview-content"), let first = model.records.first { model.stageInPanel(first, showPanel: false) }
                    renderPreview(model: model, path: path)
                    await model.prepareForExit()
                    NSApp.terminate(nil)
                }
                return
            }
            if let index = CommandLine.arguments.firstIndex(of: "--ui-review"), CommandLine.arguments.count > index + 1 {
                guard CommandLine.arguments.contains("--data-directory") else { print("UI_REVIEW_REQUIRES_ISOLATED_DIRECTORY"); NSApp.terminate(nil); return }
                let output = URL(fileURLWithPath: CommandLine.arguments[index + 1], isDirectory: true)
                Task { diagnosticExitStatus = await runUIReview(model: model, output: output) ? 0 : 1; await model.prepareForExit(); NSApp.terminate(nil) }
                return
            }
            configureMainMenu()
            configureStatusItem()
            registerHotKey()
            shortcutObserver = NotificationCenter.default.addObserver(forName: .init("SaytileShortcutChanged"), object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.registerHotKey() }
            }
            entryObserver = NotificationCenter.default.addObserver(forName: .init("SaytileFloatingEntryChanged"), object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.updateFloatingEntry() }
            }
            statusSubscription = model.audio.$state.combineLatest(model.$hasStarted).sink { [weak self] _ in
                // Published values emit before assignment. Read the derived
                // product state on the next main-actor turn, not a polling timer.
                Task { @MainActor in self?.updateStatus() }
            }
            if CommandLine.arguments.contains("--focus-probe") {
                // Exercise the actual optional window under the same isolated
                // startup. It is transparent and cannot accept keyboard focus.
                model.floatingEntryEnabled = true
                updateFloatingEntry(forIsolatedProbe: true)
                if let entry = voiceEntry {
                    let valid = entry.frame.size == NSSize(width: 42, height: 42)
                        && !entry.canBecomeKey && !entry.canBecomeMain
                        && !entry.isKeyWindow && !entry.isMainWindow
                        && entry.styleMask.contains(.nonactivatingPanel) && entry.alphaValue == 0
                    print("FOCUS_ENTRY_GEOMETRY valid=\(valid) visible=\(entry.isVisible) transparent=\(entry.alphaValue == 0) key=\(entry.isKeyWindow) main=\(entry.isMainWindow)")
                    if !valid { diagnosticExitStatus = 1 }
                } else { diagnosticExitStatus = 1; print("FOCUS_ENTRY_GEOMETRY missing=true") }
                showPanel()
                print("FOCUS_ENTRY_HIDDEN_WITH_PANEL \(voiceEntry?.isVisible == false)")
                if voiceEntry?.isVisible != false { diagnosticExitStatus = 1 }
                if let panel {
                    print("FOCUS_PANEL_GEOMETRY width=\(panel.frame.width) height=\(panel.frame.height) min_width=\(panel.minSize.width) min_height=\(panel.minSize.height) max_width=\(panel.maxSize.width) max_height=\(panel.maxSize.height) resizable=\(panel.styleMask.contains(.resizable)) nonactivating=\(panel.styleMask.contains(.nonactivatingPanel)) joins_spaces=\(panel.collectionBehavior.contains(.canJoinAllSpaces)) panel_key=\(panel.isKeyWindow) panel_main=\(panel.isMainWindow)")
                }
                Task {
                    try? await Task.sleep(for: .seconds(3))
                    print("FOCUS_PANEL_END panel_key=\(panel?.isKeyWindow == true) panel_main=\(panel?.isMainWindow == true)")
                    let captureUntouched = model.audio.state == .paused && !model.hasStarted
                    print("FOCUS_CAPTURE_UNTOUCHED \(captureUntouched)")
                    if !captureUntouched { diagnosticExitStatus = 1 }
                    await model.prepareForExit(); print("FOCUS_PROBE_FINISHED"); NSApp.terminate(nil)
                }
                return
            }
            screenObserver = NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.restoreVisibleWindows() }
            }
            // Relaunch never silently resumes the microphone or restores an input binding.
            if !preferences.bool(forKey: "hasLaunched") {
                preferences.set(true, forKey: "hasLaunched")
                showPanel()
            }
            updateFloatingEntry()
            if directoryIndex != nil {
                let configuration = model.appliedRecognitionConfiguration
                let report = "SAYTILE_ISOLATED_LAUNCH cloud_enabled=\(configuration.cloudEnabled) automatic_recovery=\(configuration.automaticRecovery) shortcut=\(model.shortcutChoice) visible_panel=\(panel?.isVisible == true) hotkey_registered=\(hotKey != nil)\n"
                FileHandle.standardOutput.write(Data(report.utf8))
            }
        } catch {
            if CommandLine.arguments.contains("--data-directory") {
                print("SAYTILE_STARTUP_FAILED \(error.localizedDescription)")
                Darwin.exit(1)
            }
            let alert = NSAlert()
            alert.messageText = "Saytile 暂时无法打开资料库"
            alert.informativeText = "已有资料不会被重置。\n\(error.localizedDescription)"
            alert.addButton(withTitle: "退出")
            alert.runModal()
            NSApp.terminate(nil)
        }
    }
    func windowWillClose(_ notification: Notification) {
        if let window = notification.object as? NSWindow, window === connectionSetupWindow { NSApp.terminate(nil) }
    }
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        guard sender === panel else { return true }
        hidePanel()
        return false // Closing the floating surface never changes capture state.
    }
    func windowWillResize(_ sender: NSWindow, to frameSize: NSSize) -> NSSize {
        guard sender === panel, let screen = sender.screen ?? NSScreen.main else { return frameSize }
        return WindowPlacement.panelSize(frameSize, visibleFrame: screen.visibleFrame)
    }
    func windowDidEndLiveResize(_ notification: Notification) {
        if let window = notification.object as? NSWindow, window === panel { restorePanel() }
    }
    func windowDidChangeScreen(_ notification: Notification) {
        if let window = notification.object as? NSWindow, window === panel { restorePanel() }
    }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if terminating { return .terminateNow }
        guard !shutdownStarted else { return .terminateCancel }
        shutdownStarted = true
        Task {
            await model?.prepareForExit()
            if model?.hasUnpersistedDrafts == true {
                shutdownStarted = false
                showPanel()
                return
            }
            terminating = true
            DispatchQueue.main.async { NSApp.terminate(nil) }
        }
        return .terminateCancel
    }
    func applicationWillTerminate(_ notification: Notification) {
        if let suite = diagnosticPreferencesSuite { UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite) }
        if diagnosticExitStatus != 0 { Darwin.exit(diagnosticExitStatus) }
    }
    private func configureMainMenu() {
        let main = NSMenu()
        let appItem = NSMenuItem(); let appMenu = NSMenu()
        let quit = NSMenuItem(title: "退出 Saytile", action: #selector(quitApp), keyEquivalent: "q"); quit.target = self
        appMenu.addItem(quit); appItem.submenu = appMenu; main.addItem(appItem)
        let edit = NSMenuItem(); let editMenu = NSMenu(title: "编辑")
        for (title, action, key) in [("撤销", "undo:", "z"), ("剪切", "cut:", "x"), ("复制", "copy:", "c"), ("粘贴", "paste:", "v"), ("全选", "selectAll:", "a")] {
            editMenu.addItem(NSMenuItem(title: title, action: Selector(action), keyEquivalent: key))
        }
        edit.submenu = editMenu; main.addItem(edit); NSApp.mainMenu = main
    }
    private func configureStatusItem() {
        let status = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        status.button?.image = NSImage(systemSymbolName: "waveform", accessibilityDescription: "Saytile")
        status.button?.target = self
        status.button?.action = #selector(statusClicked)
        status.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
        self.status = status
        updateStatus()
    }
    private func updateStatus() {
        guard let model else { return }
        let label = "Saytile · \(model.panelCaptureLabel)"
        status?.button?.image = NSImage(systemSymbolName: model.captureProblem ? "exclamationmark.circle" : (model.isListening ? "waveform" : "waveform.slash"), accessibilityDescription: label)
        status?.button?.toolTip = [label, model.panelCaptureDetail].compactMap { $0 }.joined(separator: " · ")
        status?.button?.setAccessibilityLabel(label)
        status?.button?.setAccessibilityHelp([model.panelCaptureDetail, "单击展开或收起输入板；右键打开收音、档案和设置菜单"].compactMap { $0 }.joined(separator: "。"))
    }
    @objc private func statusClicked() {
        if NSApp.currentEvent?.type == .rightMouseUp {
            let menu = NSMenu()
            let state = NSMenuItem(title: model?.panelCaptureLabel ?? "暂停", action: nil, keyEquivalent: "")
            state.isEnabled = false; menu.addItem(state)
            if let detail = model?.panelCaptureDetail {
                let reason = NSMenuItem(title: detail, action: nil, keyEquivalent: "")
                reason.isEnabled = false; reason.toolTip = detail; menu.addItem(reason)
            }
            menu.addItem(.separator())
            let items: [(String, Selector)] = [(panel?.isVisible == true ? "收起输入板" : "展开输入板", #selector(togglePanel)), (model?.captureActionLabel ?? "开始收音", #selector(toggleCapture)), ("语音档案", #selector(showArchive)), ("设置…", #selector(showSettings))]
            for (title, selector) in items { let item = NSMenuItem(title: title, action: selector, keyEquivalent: ""); item.target = self; menu.addItem(item) }
            menu.addItem(.separator())
            let quit = NSMenuItem(title: "退出 Saytile", action: #selector(quitApp), keyEquivalent: "q"); quit.target = self; menu.addItem(quit)
            status?.menu = menu; status?.button?.performClick(nil); status?.menu = nil
        } else { togglePanel() }
    }
    @objc private func toggleCapture() { model?.toggleCapture() }
    @objc private func quitApp() { NSApp.terminate(nil) }
    @objc func togglePanel() { if panel?.isVisible == true { hidePanel() } else { showPanel() } }
    private func hidePanel() {
        panel?.orderOut(nil)
        updateFloatingEntry()
    }
    func showPanel() {
        guard let model else { return }
        let firstPresentation = panel == nil
        if panel == nil {
            let panel = VoicePanel(contentRect: NSRect(origin: .zero, size: WindowPlacement.panelDefaultSize), styleMask: [.titled, .fullSizeContentView, .resizable, .nonactivatingPanel], backing: .buffered, defer: false)
            panel.title = "Saytile · 此刻"
            panel.titleVisibility = .hidden; panel.titlebarAppearsTransparent = true
            panel.standardWindowButton(.closeButton)?.isHidden = true
            panel.standardWindowButton(.miniaturizeButton)?.isHidden = true
            panel.standardWindowButton(.zoomButton)?.isHidden = true
            panel.isFloatingPanel = true; panel.level = .floating
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            panel.hidesOnDeactivate = false; panel.isReleasedWhenClosed = false
            panel.isOpaque = false; panel.backgroundColor = .clear; panel.hasShadow = true
            panel.becomesKeyOnlyIfNeeded = true; panel.delegate = self
            panel.isMovableByWindowBackground = true
            let content = NSHostingView(rootView: InputPanelView(model: model).preferredColorScheme(.light))
            // Streaming text must scroll inside the chosen window geometry, not
            // enlarge the NSPanel through SwiftUI's intrinsic-size propagation.
            content.sizingOptions = []
            panel.contentView = content
            self.panel = panel
        }
        let anchor = status?.button.flatMap { button in button.window.map { $0.convertToScreen(button.convert(button.bounds, to: nil)) } }
        if firstPresentation, let screen = status?.button?.window?.screen ?? NSScreen.main ?? NSScreen.screens.first {
            positioningPanel = true
            panel?.setFrame(WindowPlacement.panel(anchor: anchor, visibleFrame: screen.visibleFrame), display: true)
            positioningPanel = false
        }
        restorePanel()
        voiceEntry?.orderOut(nil)
        panel?.orderFrontRegardless()
    }
    private func updateFloatingEntry(forIsolatedProbe: Bool = false) {
        guard let model, model.floatingEntryEnabled, diagnosticPreferencesSuite == nil || forIsolatedProbe,
              panel?.isVisible != true else { voiceEntry?.orderOut(nil); return }
        if voiceEntry == nil {
            let entry = VoiceEntryPanel(contentRect: NSRect(x: 0, y: 0, width: 42, height: 42),
                styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            entry.title = "Saytile · 语音入口"
            entry.isFloatingPanel = true; entry.level = .floating
            entry.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            entry.isOpaque = false; entry.backgroundColor = .clear; entry.hasShadow = true
            if forIsolatedProbe { entry.alphaValue = 0; entry.ignoresMouseEvents = true }
            entry.hidesOnDeactivate = false; entry.isReleasedWhenClosed = false
            let content = NSHostingView(rootView: VoiceEntryView(model: model, open: { [weak self] in self?.showPanel() }).preferredColorScheme(.light))
            content.sizingOptions = []
            entry.contentView = content
            voiceEntry = entry
        }
        if let screen = panel?.screen ?? NSScreen.main ?? NSScreen.screens.first {
            let area = screen.visibleFrame
            let requested = NSRect(x: area.maxX - 58, y: area.minY + 16, width: 42, height: 42)
            voiceEntry?.setFrame(WindowPlacement.restored(requested, visibleFrames: [area]), display: false)
        }
        voiceEntry?.orderFrontRegardless()
    }
    @objc func showArchive() {
        guard let model else { return }
        if archive == nil {
            archive = makeWindow(title: "Saytile · 语音档案", width: 1040, height: 720, view: ArchiveView(model: model).preferredColorScheme(.light))
            archive?.minSize = NSSize(width: 800, height: 570)
        }
        archive?.minSize = NSSize(width: model.selected == nil ? 760 : 1040, height: 570)
        restoreVisibleWindows()
        NSApp.activate(ignoringOtherApps: true); archive?.makeKeyAndOrderFront(nil)
    }
    @objc func showSettings() {
        guard let model else { return }
        model.audio.refreshDevices()
        if settings == nil { settings = makeWindow(title: "Saytile · 设置", width: 650, height: 740, view: SettingsView(model: model).preferredColorScheme(.light)) }
        settings?.minSize = NSSize(width: 560, height: 570)
        restoreVisibleWindows()
        NSApp.activate(ignoringOtherApps: true); settings?.makeKeyAndOrderFront(nil)
    }
    private func makeWindow<V: View>(title: String, width: CGFloat, height: CGFloat, view: V) -> NSWindow {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: width, height: height), styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.title = title; window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: view); window.center()
        return window
    }
    private func restoreVisibleWindows() {
        let frames = NSScreen.screens.map(\.visibleFrame)
        restorePanel()
        updateFloatingEntry()
        for window in [archive, settings].compactMap({ $0 }) {
            let size = NSSize(width: max(window.frame.width, window.minSize.width), height: max(window.frame.height, window.minSize.height))
            window.setFrame(WindowPlacement.restored(NSRect(origin: window.frame.origin, size: size), visibleFrames: frames), display: true)
        }
    }
    private func restorePanel() {
        guard let panel, !positioningPanel else { return }
        let frames = NSScreen.screens.map(\.visibleFrame)
        guard !frames.isEmpty else { return }
        positioningPanel = true; defer { positioningPanel = false }
        let frame = WindowPlacement.restoredPanel(panel.frame, visibleFrames: frames)
        let center = CGPoint(x: frame.midX, y: frame.midY)
        let screen = frames.first(where: { $0.contains(center) }) ?? frames[0]
        let limits = WindowPlacement.panelLimits(visibleFrame: screen)
        panel.minSize = .zero
        panel.maxSize = limits.maximum; panel.minSize = limits.minimum
        if panel.frame != frame { panel.setFrame(frame, display: panel.isVisible) }
    }
    private func registerHotKey() {
        if let hotKey { UnregisterEventHotKey(hotKey); self.hotKey = nil }
        if let eventHandler { RemoveEventHandler(eventHandler); self.eventHandler = nil }
        guard model?.shortcutChoice != "disabled" else { return }
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let opaque = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(GetApplicationEventTarget(), { _, _, context in
            guard let context else { return OSStatus(eventNotHandledErr) }
            let delegate = Unmanaged<AppDelegate>.fromOpaque(context).takeUnretainedValue()
            MainActor.assumeIsolated { delegate.togglePanel() }
            return noErr
        }, 1, &spec, opaque, &eventHandler)
        let identifier = EventHotKeyID(signature: OSType(0x5359544C), id: 1)
        let modifiers: UInt32
        switch model?.shortcutChoice {
        case "control-option-space": modifiers = UInt32(controlKey | optionKey)
        case "command-shift-space": modifiers = UInt32(cmdKey | shiftKey)
        default: modifiers = UInt32(optionKey)
        }
        let result = RegisterEventHotKey(UInt32(kVK_Space), modifiers, identifier, GetApplicationEventTarget(), 0, &hotKey)
        if result != noErr { model?.notice = "所选快捷键已被其他功能占用，请选择另一组合，或通过菜单栏展开。" }
    }
    private func renderPreview(model: AppModel, path: String) {
        if CommandLine.arguments.contains("--preview-archive") {
            renderView(ArchiveView(model: model).preferredColorScheme(.light), width: 1040, height: 720, path: path)
        } else if CommandLine.arguments.contains("--preview-settings") {
            renderView(SettingsView(model: model).preferredColorScheme(.light), width: 650, height: 740, path: path)
        } else {
            renderView(InputPanelView(model: model).preferredColorScheme(.light), width: 400, height: 550, path: path)
        }
    }
    private func renderView<V: View>(_ content: V, width: CGFloat, height: CGFloat, path: String) {
        let view = NSHostingView(rootView: content)
        view.frame = NSRect(x: 0, y: 0, width: width, height: height)
        view.layoutSubtreeIfNeeded()
        guard let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
        view.cacheDisplay(in: view.bounds, to: bitmap)
        if let data = bitmap.representation(using: .png, properties: [:]) { try? data.write(to: URL(fileURLWithPath: path)); print("PREVIEW_WRITTEN \(path)") }
    }
}
