import AppKit

@MainActor
final class FixtureTextView: NSTextView {
    var returnEvents = 0
    override func keyDown(with event: NSEvent) {
        if event.keyCode == 36 || event.keyCode == 76 { returnEvents += 1; return }
        super.keyDown(with: event)
    }
}

@MainActor
final class TextFixtureController {
    let window: NSPanel
    let text: FixtureTextView
    let foregroundArmed: Bool
    private var activated = false
    private var commandBytes = Data()
    init(foregroundArmed: Bool) {
        self.foregroundArmed = foregroundArmed
        window = NSPanel(contentRect: NSRect(x: -20_000, y: -20_000, width: 320, height: 180),
                         styleMask: foregroundArmed ? [.titled] : [.titled, .nonactivatingPanel], backing: .buffered, defer: false)
        window.title = "Saytile isolated AX fixture"
        window.isReleasedWhenClosed = false
        text = FixtureTextView(frame: NSRect(x: 0, y: 0, width: 320, height: 180))
        text.isEditable = true; text.isSelectable = true
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
                NSApp.setActivationPolicy(.accessory)
                window.center(); window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true)
                window.makeFirstResponder(text)
            case "restore": text.string = "PREFIX|SUFFIX"; text.setSelectedRange(NSRange(location: 7, length: 0)); window.makeFirstResponder(text)
            case "select": text.setSelectedRange(NSRange(location: 0, length: 6))
            case "diagnostic-settings":
                let flags: [String: Any] = ["spellingCorrection": text.isAutomaticSpellingCorrectionEnabled,
                    "textReplacement": text.isAutomaticTextReplacementEnabled, "quoteSubstitution": text.isAutomaticQuoteSubstitutionEnabled,
                    "dashSubstitution": text.isAutomaticDashSubstitutionEnabled, "linkDetection": text.isAutomaticLinkDetectionEnabled,
                    "dataDetection": text.isAutomaticDataDetectionEnabled, "textCompletion": text.isAutomaticTextCompletionEnabled,
                    "smartInsertDelete": text.smartInsertDeleteEnabled, "continuousSpellChecking": text.isContinuousSpellCheckingEnabled,
                    "grammarChecking": text.isGrammarCheckingEnabled]
                if let data = try? JSONSerialization.data(withJSONObject: flags, options: [.sortedKeys]) { value = String(decoding: data, as: UTF8.self) }
            case "state":
                if let data = try? JSONSerialization.data(withJSONObject: ["text": text.string, "sends": text.returnEvents]) { value = String(decoding: data, as: UTF8.self) }
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
        FileHandle.standardOutput.write(Data("FIXTURE_READY\n".utf8))
        withExtendedLifetime(controller) { app.run() }
    }
}
