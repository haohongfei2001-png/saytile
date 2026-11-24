import AppKit
import Sparkle

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
    var receipt: [String: Any] = ["status": "FAIL", "scope": "unchanged product controller + presentation-only model + SDK default user driver; not the complete Saytile application", "download_or_install_requested": false]

    init(output: URL, notes: String) { self.output = output; self.notes = notes }
    func applicationDidFinishLaunching(_ notification: Notification) {
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
        try require(Bundle.main.bundleIdentifier?.hasPrefix("app.saytile.update-fixture.") == true, "Fixture identity required")
        controller = AppUpdateController(model: model, isolatedFixture: true)
        try await until { self.model.updateConfigured && self.model.canCheckForUpdates }
        model.checkForUpdates?()
        func updateWindow() -> NSWindow? {
            NSApp.windows.first { $0.isVisible && $0.windowController.map { NSStringFromClass(type(of: $0)) == "SUUpdateAlert" } == true }
        }
        try await until { updateWindow() != nil }
        guard let window = updateWindow(), let content = window.contentView else {
            throw NSError(domain: "StandardUpdateUIProbe", code: 2)
        }
        var texts: [String] { descendants(content).compactMap { ($0 as? NSTextView)?.string ?? ($0 as? NSTextField)?.stringValue } }
        try await until { texts.contains { $0.trimmingCharacters(in: .whitespacesAndNewlines) == self.notes } }
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
        later.performClick(nil) // Actual SDK button/target/action, not a replacement user driver.
        try await until { !window.isVisible && self.model.canCheckForUpdates }
        try require(!model.expectsUpdateRelaunch, "Dismiss must not prepare installation or relaunch")
        receipt["later_action"] = "NSButton.performClick -> SUUpdateAlert.remindMeLater:"
        receipt["dialog_closed"] = true
        receipt["controller_ready_after_dismissal"] = model.canCheckForUpdates
        receipt["status"] = "PASS"
    }
    func finish(_ code: Int32) {
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
        let notes = try String(contentsOfFile: CommandLine.arguments[2], encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines)
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        let delegate = StandardUpdateUIProbe(output: output, notes: notes)
        app.delegate = delegate
        withExtendedLifetime(delegate) { app.run() }
    }
}
