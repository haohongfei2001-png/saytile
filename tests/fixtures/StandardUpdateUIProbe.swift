import AppKit
import Sparkle

#if arch(arm64)
private let probeArchitecture = "arm64"
#elseif arch(x86_64)
private let probeArchitecture = "x86_64"
#else
#error("Standard Sparkle UI supports only arm64 and x86_64")
#endif

private func progress(_ output: URL, _ phase: String, _ details: [String: Any] = [:]) {
    var value = details
    value["phase"] = phase
    value["pid"] = ProcessInfo.processInfo.processIdentifier
    value["architecture"] = probeArchitecture
    value["uptime_seconds"] = ProcessInfo.processInfo.systemUptime
    if let data = try? JSONSerialization.data(withJSONObject: value, options: [.prettyPrinted, .sortedKeys]) {
        try? data.write(to: output.appendingPathComponent("native-progress.json"), options: .atomic)
    }
    FileHandle.standardError.write(Data(("STANDARD_UPDATE_UI " + phase + "\n").utf8))
}

// Presentation-only substitute, as in AppUpdateControllerProbe. The production
// controller is compiled unchanged and creates its own default Sparkle driver.
@MainActor final class AppModel {
    var updateConfigured = false, canCheckForUpdates = false, automaticUpdateChecks = false
    var expectsUpdateRelaunch = false
    var updateStatus = "", updateActionTitle = ""
    var checkForUpdates: (() -> Void)?
    var setAutomaticUpdateChecks: (Bool) -> Void = { _ in }
}

@MainActor final class StandardUpdateUIProbe: NSObject, NSApplicationDelegate {
    let output: URL
    let notes: String
    let model = AppModel()
    var controller: AppUpdateController?
    var receipt: [String: Any] = ["status": "FAIL", "architecture": probeArchitecture, "scope": "unchanged product controller + presentation-only model + SDK default user driver; not the complete Saytile application", "download_or_install_requested": false]

    init(output: URL, notes: String) { self.output = output; self.notes = notes }
    func applicationWillFinishLaunching(_ notification: Notification) { progress(output, "will_finish_launching") }
    func applicationDidFinishLaunching(_ notification: Notification) {
        progress(output, "did_finish_launching")
        Task { @MainActor in
            do { try await exercise(); finish(0) }
            catch { receipt["error"] = String(describing: error); finish(1) }
        }
    }
    func require(_ ok: Bool, _ message: String) throws {
        if !ok { throw NSError(domain: "StandardUpdateUIProbe", code: 1, userInfo: [NSLocalizedDescriptionKey: message]) }
    }
    func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(descendants) }
    func until(_ condition: () -> Bool) async throws {
        let deadline = ContinuousClock.now + .seconds(20)
        while !condition() {
            try require(ContinuousClock.now < deadline, "Timed out: \(model.updateStatus)")
            try await Task.sleep(for: .milliseconds(50))
        }
    }
    func exercise() async throws {
        progress(output, "exercise_entered")
        try require(Bundle.main.bundleIdentifier?.hasPrefix("app.saytile.update-fixture.") == true, "Fixture identity required")
        progress(output, "controller_init_begin")
        controller = AppUpdateController(model: model, isolatedFixture: true)
        progress(output, "controller_init_returned", ["configured": model.updateConfigured, "ready": model.canCheckForUpdates, "status": model.updateStatus])
        try await until { self.model.updateConfigured && self.model.canCheckForUpdates }
        progress(output, "check_for_updates_begin")
        model.checkForUpdates?()
        progress(output, "check_for_updates_returned")
        func updateWindow() -> NSWindow? {
            NSApp.windows.first { $0.isVisible && $0.windowController.map { NSStringFromClass(type(of: $0)) == "SUUpdateAlert" } == true }
        }
        try await until { updateWindow() != nil }
        progress(output, "default_update_window_visible")
        guard let window = updateWindow(), let content = window.contentView else {
            throw NSError(domain: "StandardUpdateUIProbe", code: 2)
        }
        var texts: [String] { descendants(content).compactMap { ($0 as? NSTextView)?.string ?? ($0 as? NSTextField)?.stringValue } }
        try await until { texts.contains { $0.trimmingCharacters(in: .whitespacesAndNewlines) == self.notes } }
        progress(output, "inline_notes_exact_match")
        let buttons = descendants(content).compactMap { $0 as? NSButton }.filter { !$0.isHiddenOrHasHiddenAncestor }
        receipt["buttons"] = buttons.map { ["title": $0.title, "action": $0.action.map(NSStringFromSelector) ?? "", "enabled": $0.isEnabled] as [String: Any] }
        guard let install = buttons.first(where: { $0.action == NSSelectorFromString("installUpdate:") }),
              let later = buttons.first(where: { $0.action == NSSelectorFromString("remindMeLater:") }) else {
            throw NSError(domain: "StandardUpdateUIProbe", code: 3, userInfo: [NSLocalizedDescriptionKey: "Default Install/Later controls missing"])
        }
        try require(install.isEnabled && later.isEnabled, "Default controls disabled")
        try require(texts.contains { $0.contains("1.0.0") && $0.contains("1.0.1") }, "Both release versions must be visible")
        try require(NSApp.isActive && window.isVisible, "Expected an actual visible default dialog in the isolated CI desktop")
        content.layoutSubtreeIfNeeded()
        guard let bitmap = content.bitmapImageRepForCachingDisplay(in: content.bounds) else { throw NSError(domain: "StandardUpdateUIProbe", code: 4) }
        content.cacheDisplay(in: content.bounds, to: bitmap)
        guard let png = bitmap.representation(using: .png, properties: [:]) else { throw NSError(domain: "StandardUpdateUIProbe", code: 5) }
        try png.write(to: output.appendingPathComponent("standard-update-dialog.png"), options: .atomic)
        receipt["window_controller"] = NSStringFromClass(type(of: window.windowController!))
        receipt["native_visible"] = window.isVisible
        receipt["ci_application_activated"] = NSApp.isActive
        receipt["versions_displayed"] = ["1.0.0", "1.0.1"]
        receipt["inline_notes_exact_match"] = true
        receipt["screenshot_pixels"] = [bitmap.pixelsWide, bitmap.pixelsHigh]
        progress(output, "later_click_begin")
        later.performClick(nil) // Actual SDK button/target/action, not a replacement user driver.
        progress(output, "later_click_returned")
        try await until { !window.isVisible && self.model.canCheckForUpdates }
        try require(!model.expectsUpdateRelaunch, "Dismiss must not prepare installation or relaunch")
        receipt["later_action"] = "NSButton.performClick -> SUUpdateAlert.remindMeLater:"
        receipt["dialog_closed"] = true
        receipt["controller_ready_after_dismissal"] = model.canCheckForUpdates
        receipt["status"] = "PASS"
    }
    func finish(_ code: Int32) {
        progress(output, "finished", ["exit_code": code, "status": receipt["status"] ?? "FAIL", "error": receipt["error"] ?? ""])
        if let data = try? JSONSerialization.data(withJSONObject: receipt, options: [.prettyPrinted, .sortedKeys]) {
            try? data.write(to: output.appendingPathComponent("native-receipt.json"), options: .atomic)
        }
        exit(code)
    }
}

@main struct StandardUpdateUIEntry {
    @MainActor static func main() throws {
        guard ProcessInfo.processInfo.environment["GITHUB_ACTIONS"] == "true",
              ProcessInfo.processInfo.environment["SAYTILE_ALLOW_STANDARD_UPDATE_UI"] == "1",
              CommandLine.arguments.count == 3 else { exit(78) }
        let output = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        progress(output, "main_entered")
        let notes = try String(contentsOfFile: CommandLine.arguments[2], encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines)
        progress(output, "application_shared_begin")
        let app = NSApplication.shared
        progress(output, "application_shared_returned")
        progress(output, "accessory_policy_begin")
        app.setActivationPolicy(.accessory)
        progress(output, "accessory_policy_returned", ["active": app.isActive])
        // Sparkle 2.10.1 asks NSImage for the main application's icon before it
        // creates its checking window. Preload the real bundled product icon so
        // this UI fixture does not depend on the hosted VM's IconServices XPC.
        // The SDK's driver, image lookup, windows and controls remain unchanged.
        progress(output, "product_icon_load_begin")
        guard let iconURL = Bundle.main.url(forResource: "Saytile", withExtension: "icns"),
              let icon = NSImage(contentsOf: iconURL), icon.isValid,
              icon.setName(NSImage.applicationIconName),
              NSImage(named: NSImage.applicationIconName) === icon else {
            throw NSError(domain: "StandardUpdateUIProbe", code: 6,
                          userInfo: [NSLocalizedDescriptionKey: "Bundled product icon must satisfy the SDK's original named-image lookup"])
        }
        progress(output, "product_icon_registered")
        progress(output, "delegate_init_begin")
        let delegate = StandardUpdateUIProbe(output: output, notes: notes)
        delegate.receipt["host_icon_name_cached"] = true
        delegate.receipt["host_icon_scope"] = "real product .icns preloaded in fixture; dynamic system IconServices not accepted by this test"
        app.delegate = delegate
        progress(output, "before_app_run")
        withExtendedLifetime((delegate, icon)) { app.run() }
    }
}
