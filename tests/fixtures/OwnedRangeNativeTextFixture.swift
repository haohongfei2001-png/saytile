import AppKit

// Instrument the receiving native NSTextView, not Saytile's production AX adapter.
// Super implements the successful AX setters. No synthetic AX implementation.
@MainActor
final class OwnedRangeTextView: NSTextView {
    var textAttempts: [[String: Any]] = []
    var rangeAttempts: [[String: Int]] = []
    var fullValueAttempts = 0
    var keyEvents = 0
    var pasteAttempts = 0
    var rejectReplacement = false
    var unexpectedPayload = false

    override func setAccessibilitySelectedText(_ value: String?) {
        let range = selectedRange()
        let allowed = ["50😀", "500👩🏽‍💻", "，后续。"]
        let accepted = value.map { allowed.contains($0) } == true
        textAttempts.append(["location": range.location, "length": range.length,
                             "text": accepted ? value! : "UNEXPECTED_OMITTED"])
        guard accepted else { unexpectedPayload = true; return }
        if rejectReplacement && range.length > 0 { return }
        super.setAccessibilitySelectedText(value)
    }
    override func setAccessibilitySelectedTextRange(_ range: NSRange) {
        rangeAttempts.append(["location": range.location, "length": range.length])
        super.setAccessibilitySelectedTextRange(range)
    }
    override func setAccessibilityValue(_ value: Any?) {
        fullValueAttempts += 1 // Reject forbidden whole-value writes, but record the attempt.
    }
    override func keyDown(with event: NSEvent) { keyEvents += 1 }
    override func paste(_ sender: Any?) { pasteAttempts += 1 }
}

@MainActor
final class OwnedRangeFixtureController {
    let window: NSPanel
    let primary = OwnedRangeTextView(frame: NSRect(x: 0, y: 0, width: 320, height: 90))
    let alternate = OwnedRangeTextView(frame: NSRect(x: 0, y: 90, width: 320, height: 90))
    let nonce: String
    var commandBytes = Data()
    init(nonce: String) {
        self.nonce = nonce
        window = NSPanel(contentRect: NSRect(x: -20_000, y: -20_000, width: 320, height: 180),
                         styleMask: [.titled, .nonactivatingPanel], backing: .buffered, defer: false)
        window.title = "Saytile owned-range " + nonce
        window.isReleasedWhenClosed = false
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 320, height: 180))
        for (index, view) in [primary, alternate].enumerated() {
            view.isEditable = true; view.isSelectable = true
            view.setAccessibilityIdentifier("owned-range-\(nonce)-\(index)")
            container.addSubview(view)
        }
        window.contentView = container
        reset()
        window.makeFirstResponder(primary); window.orderBack(nil)
        FileHandle.standardInput.readabilityHandler = { [weak self] handle in
            let bytes = handle.availableData
            if bytes.isEmpty { handle.readabilityHandler = nil; return }
            Task { @MainActor [weak self] in self?.consume(bytes) }
        }
    }
    func reset() {
        for view in [primary, alternate] {
            view.string = "用户前缀😀｜用户后缀🚀"
            view.setSelectedRange(NSRange(location: "用户前缀😀｜".utf16.count, length: 0))
            view.textAttempts = []; view.rangeAttempts = []
            view.fullValueAttempts = 0; view.keyEvents = 0; view.pasteAttempts = 0
            view.rejectReplacement = false; view.unexpectedPayload = false
        }
    }
    func consume(_ bytes: Data) {
        commandBytes.append(bytes)
        guard commandBytes.count <= 8192 else { exit(3) }
        while let newline = commandBytes.firstIndex(of: 10) {
            let line = commandBytes.prefix(upTo: newline); commandBytes.removeSubrange(...newline)
            guard let request = try? JSONSerialization.jsonObject(with: line) as? [String: String],
                  request["nonce"] == nonce, let command = request["command"] else { exit(3) }
            switch command {
            case "reset": reset()
            case "manual-edit":
                let caret = primary.selectedRange()
                // Same UTF-16 length and caret: text witness/notifications must detect it.
                primary.textStorage?.replaceCharacters(in: NSRange(location: "用户前缀😀｜".utf16.count, length: 2), with: "99")
                primary.setSelectedRange(caret); primary.didChangeText()
            case "select": primary.setSelectedRange(NSRange(location: 0, length: 2))
            case "reject-replacement": primary.rejectReplacement = true
            case "state": break
            default: exit(3)
            }
            reply(command)
        }
    }
    func state(_ view: OwnedRangeTextView) -> [String: Any] {
        ["text": view.string, "location": view.selectedRange().location, "length": view.selectedRange().length,
         "textAttempts": view.textAttempts, "rangeAttempts": view.rangeAttempts,
         "fullValueAttempts": view.fullValueAttempts, "keyEvents": view.keyEvents,
         "pasteAttempts": view.pasteAttempts, "unexpectedPayload": view.unexpectedPayload]
    }
    func reply(_ command: String) {
        let result: [String: Any] = ["command": command, "nonce": nonce,
            "pid": ProcessInfo.processInfo.processIdentifier,
            "primary": state(primary), "alternate": state(alternate)]
        let bytes = try! JSONSerialization.data(withJSONObject: result, options: [.sortedKeys])
        FileHandle.standardOutput.write(bytes + Data([10]))
    }
}

@main struct OwnedRangeNativeTextFixture {
    @MainActor static func main() {
        guard CommandLine.arguments.count == 2, UUID(uuidString: CommandLine.arguments[1]) != nil else { exit(2) }
        let app = NSApplication.shared
        app.setActivationPolicy(.prohibited)
        let controller = OwnedRangeFixtureController(nonce: CommandLine.arguments[1])
        controller.reply("ready")
        withExtendedLifetime(controller) { app.run() }
    }
}
