import AppKit
import Foundation

@MainActor final class BackgroundPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}
@MainActor final class Transcript: NSTextView {
    var menuRequests = 0
    override func menu(for event: NSEvent) -> NSMenu? { menuRequests += 1; return menu }
}
@MainActor final class Fixture: NSObject {
    let nonce: String
    let panel = BackgroundPanel(contentRect: NSRect(x: -9000, y: -9000, width: 300, height: 180),
                                styleMask: [.titled, .nonactivatingPanel], backing: .buffered, defer: false)
    let editor = Transcript(frame: NSRect(x: 0, y: 0, width: 300, height: 180))
    let menu = NSMenu(title: "Owned transcript commands")
    let foregroundAtStart = NSWorkspace.shared.frontmostApplication?.processIdentifier
    var actions = 0
    var keyboardEvents = 0
    var activated = false
    var monitor: Any?
    var activationObserver: NSObjectProtocol?
    init(nonce: String) { self.nonce = nonce; super.init() }
    func emit(_ event: String) {
        let row: [String: Any] = ["event":event, "pid":ProcessInfo.processInfo.processIdentifier,
            "nonce":nonce, "actions":actions, "key":panel.isKeyWindow, "main":panel.isMainWindow,
            "canKey":panel.canBecomeKey, "canMain":panel.canBecomeMain, "alpha":panel.alphaValue,
            "keyboardEvents":keyboardEvents, "menuRequests":editor.menuRequests, "activated":activated || NSApp.isActive,
            "foregroundUnchanged":NSWorkspace.shared.frontmostApplication?.processIdentifier == foregroundAtStart]
        let bytes = try! JSONSerialization.data(withJSONObject:row,options:[.sortedKeys])
        print(String(decoding:bytes,as:UTF8.self)); fflush(nil)
    }
    @objc func edit(_ sender: NSMenuItem) { actions += 1; emit("realMenuItemAction") }
    func start() {
        monitor = NSEvent.addLocalMonitorForEvents(matching:[.keyDown,.keyUp,.flagsChanged]) { [weak self] _ in
            MainActor.assumeIsolated { self?.keyboardEvents += 1 }
            return nil
        }
        activationObserver = NotificationCenter.default.addObserver(forName:NSApplication.didBecomeActiveNotification,
            object:NSApp,queue:.main) { [weak self] _ in
                MainActor.assumeIsolated { self?.activated = true; self?.menu.cancelTracking() }
            }
        panel.title = "Saytile own context " + nonce
        panel.alphaValue = 0; panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false; panel.isReleasedWhenClosed = false
        editor.string = "仅用于本进程的合成文字。"; editor.isEditable = false; editor.isSelectable = true
        editor.setAccessibilityIdentifier("fixture.transcript")
        menu.autoenablesItems = false
        let item = NSMenuItem(title:"编辑合成段落 " + nonce, action:#selector(edit(_:)), keyEquivalent:"")
        item.target = self; item.isEnabled = true; menu.addItem(item)
        editor.menu = menu
        panel.contentView = editor; panel.makeFirstResponder(editor); panel.orderBack(nil)
        FileHandle.standardInput.readabilityHandler = { [weak self] stream in
            let data = stream.availableData; guard !data.isEmpty else { return }
            let command = String(decoding:data,as:UTF8.self).trimmingCharacters(in:.whitespacesAndNewlines)
            Task { @MainActor in
                guard let self else { return }
                switch command {
                case "fallback": self.editor.menu?.performActionForItem(at:0); self.emit("directAttachedNSMenu")
                case "finish": self.menu.cancelTracking(); self.emit("finished"); self.panel.orderOut(nil); NSApp.terminate(nil)
                default: self.emit("unknownCommand")
                }
            }
        }
        emit("ready")
    }
}
@main struct Main {
    @MainActor static func main() {
        guard CommandLine.arguments.count == 2 else { exit(64) }
        NSApplication.shared.setActivationPolicy(.prohibited)
        let fixture = Fixture(nonce:CommandLine.arguments[1]); fixture.start()
        withExtendedLifetime(fixture) { NSApp.run() }
    }
}
