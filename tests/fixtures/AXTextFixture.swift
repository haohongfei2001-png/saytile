import AppKit

// Dedicated nonactivating native AX fixture. All text is synthetic.
// Launch directly, never through an activating `open` command.
@main
struct AXTextFixture {
    @MainActor static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.prohibited)
        let window = NSPanel(contentRect: NSRect(x: -20_000, y: -20_000, width: 320, height: 180),
                              styleMask: [.titled, .nonactivatingPanel], backing: .buffered, defer: false)
        window.title = "Saytile isolated AX fixture"
        window.isReleasedWhenClosed = false
        let text = NSTextView(frame: NSRect(x: 0, y: 0, width: 320, height: 180))
        text.isEditable = true; text.isSelectable = true
        text.string = "PREFIX|SUFFIX"
        text.setSelectedRange(NSRange(location: 7, length: 0))
        window.contentView = text
        window.makeFirstResponder(text)
        window.orderBack(nil)
        // Never make key or activate. The controller accesses this specific process only.
        FileHandle.standardOutput.write(Data("FIXTURE_READY\n".utf8))
        withExtendedLifetime(window) { app.run() }
    }
}
