import AppKit

@MainActor
final class FixturePanel: NSPanel {
    var keyboardAllowed = false
    var keyboardEvents = 0
    override var canBecomeKey: Bool { keyboardAllowed }
    override var canBecomeMain: Bool { keyboardAllowed }
    override func sendEvent(_ event: NSEvent) {
        if !keyboardAllowed, [.keyDown, .keyUp, .flagsChanged].contains(event.type) {
            keyboardEvents += 1; return // Never inspect or forward keyboard characters.
        }
        super.sendEvent(event)
    }
}

@MainActor
final class FixtureTextView: NSTextView {
    var returnEvents = 0
    var keyboardEvents = 0
    var keyboardAllowed = false
    override func keyDown(with event: NSEvent) {
        keyboardEvents += 1
        guard keyboardAllowed else { return }
        if event.keyCode == 36 || event.keyCode == 76 { returnEvents += 1; return }
        super.keyDown(with: event)
    }
}

@MainActor
final class TextFixtureController {
    let window: FixturePanel
    let text: FixtureTextView
    let foregroundArmed: Bool
    private var activated = false
    private var commandBytes = Data()
    init(foregroundArmed: Bool) {
        self.foregroundArmed = foregroundArmed
        window = FixturePanel(contentRect: NSRect(x: -20_000, y: -20_000, width: 320, height: 180),
                         styleMask: foregroundArmed ? [.titled] : [.titled, .nonactivatingPanel], backing: .buffered, defer: false)
        window.title = "Saytile isolated AX fixture"
        window.alphaValue = 0; window.ignoresMouseEvents = true
        window.isReleasedWhenClosed = false
        text = FixtureTextView(frame: NSRect(x: 0, y: 0, width: 320, height: 180))
        text.isEditable = true; text.isSelectable = true
        // An insertion fixture must not inherit automatic rewriting behavior.
        text.isAutomaticSpellingCorrectionEnabled = false
        text.isAutomaticTextReplacementEnabled = false
        text.isAutomaticTextCompletionEnabled = false
        text.isAutomaticQuoteSubstitutionEnabled = false
        text.isAutomaticDashSubstitutionEnabled = false
        text.isAutomaticLinkDetectionEnabled = false
        text.isAutomaticDataDetectionEnabled = false
        text.isContinuousSpellCheckingEnabled = false
        text.isGrammarCheckingEnabled = false
        text.smartInsertDeleteEnabled = false
        text.string = "PREFIX|SUFFIX"; text.setSelectedRange(NSRange(location: 7, length: 0))
        window.contentView = text; window.makeFirstResponder(text); window.orderBack(nil)
        FileHandle.standardInput.readabilityHandler = { [weak self] handle in
            let bytes = handle.availableData
            if bytes.isEmpty { handle.readabilityHandler = nil; return }
            Task { @MainActor [weak self] in self?.consume(bytes) }
        }
    }
    private func consume(_ bytes: Data) {
        commandBytes.append(bytes)
        while let newline = commandBytes.firstIndex(of: 10) {
            let line = commandBytes.prefix(upTo: newline); commandBytes.removeSubrange(...newline)
            guard let object = try? JSONSerialization.jsonObject(with: line) as? [String: String], let command = object["command"] else { continue }
            var error = "", value = ""
            switch command {
            case "activate":
                guard foregroundArmed, !activated else { reply(command, error: "Foreground activation is not armed or was already used"); continue }
                activated = true
                window.keyboardAllowed = true; text.keyboardAllowed = true
                window.alphaValue = 1; window.ignoresMouseEvents = false
                NSApp.setActivationPolicy(.accessory)
                window.center(); window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true)
                window.makeFirstResponder(text)
            case "restore": text.string = "PREFIX|SUFFIX"; text.setSelectedRange(NSRange(location: 7, length: 0)); window.makeFirstResponder(text)
            case "select": text.setSelectedRange(NSRange(location: 0, length: 6))
            case "state":
                let known = ["PREFIX|SUFFIX", "PREFIX|你好😀SUFFIX", "PREFIX|你好😀，接着说SUFFIX", "PREFIX|新句 你好😀，接着说SUFFIX"].contains(text.string)
                let state: [String: Any] = ["text": known ? text.string : "UNEXPECTED_TEXT_OMITTED",
                    "knownSyntheticText": known, "utf16Length": text.string.utf16.count, "sends": text.returnEvents,
                    "keyWindow": window.isKeyWindow, "mainWindow": window.isMainWindow,
                    "keyboardEvents": window.keyboardEvents + text.keyboardEvents]
                if let data = try? JSONSerialization.data(withJSONObject: state) { value = String(decoding: data, as: UTF8.self) }
            default: error = "Unknown fixture command"
            }
            reply(command, value: value, error: error)
        }
    }
    private func reply(_ command: String, value: String = "", error: String = "") {
        if let data = try? JSONSerialization.data(withJSONObject: ["command": command, "value": value, "error": error]) { FileHandle.standardOutput.write(data + Data([10])) }
    }
}

// Default remains prohibited and offscreen. The opt-in foreground mode is armed
// only; it still cannot activate until the guarded batch sends one activation.
@main struct AXTextFixture {
    @MainActor static func main() {
        let app = NSApplication.shared; app.setActivationPolicy(.prohibited)
        let controller = TextFixtureController(foregroundArmed: CommandLine.arguments.contains("--foreground-armed"))
        let initial = controller.text.string == "PREFIX|SUFFIX" && controller.text.selectedRange() == NSRange(location: 7, length: 0)
        let isolated = !controller.window.isKeyWindow && !controller.window.isMainWindow && controller.window.keyboardEvents == 0 && controller.text.keyboardEvents == 0
        guard initial && isolated else { print("FIXTURE_ISOLATION_FAILED"); exit(3) }
        print("FIXTURE_ISOLATION initial_expected=true key=false main=false keyboard_events=0 background=\(!controller.foregroundArmed)")
        fflush(nil)
        FileHandle.standardOutput.write(Data("FIXTURE_READY\n".utf8))
        withExtendedLifetime(controller) { app.run() }
    }
}
