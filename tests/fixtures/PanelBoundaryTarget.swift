import AppKit

/// Synthetic owned windows only. Commands are confined to the run's private directory.
@main struct PanelBoundaryTarget {
    @MainActor static func main() {
        guard CommandLine.arguments.count == 2 else { exit(64) }
        let app = NSApplication.shared
        let delegate = Fixture(directory: URL(fileURLWithPath: CommandLine.arguments[1]))
        app.setActivationPolicy(.regular); app.delegate = delegate
        withExtendedLifetime(delegate) { app.run() }
    }
}
private final class BoundaryWindow: NSWindow {
    var strictMinimum = false
    var refusedSizeWrites = 0
    override func setAccessibilityFrame(_ frame: NSRect) {
        if strictMinimum && (frame.width < minSize.width || frame.height < minSize.height) { refusedSizeWrites += 1; return }
        super.setAccessibilityFrame(frame)
    }
    override func accessibilitySetValue(_ value: Any?, forAttribute attribute: NSAccessibility.Attribute) {
        let requestedSize: CGSize? = attribute == .size ? (value as? NSValue)?.sizeValue : nil
        if Thread.isMainThread {
            let refused = MainActor.assumeIsolated {
                if strictMinimum, let size = requestedSize,
                   size.width < minSize.width || size.height < minSize.height { refusedSizeWrites += 1; return true }
                return false
            }
            if refused { return }
        }
        super.accessibilitySetValue(value, forAttribute: attribute)
    }
}
@MainActor private final class Fixture: NSObject, NSApplicationDelegate, NSToolbarDelegate, NSWindowDelegate {
    let directory: URL
    var window: BoundaryWindow!
    var duplicate: NSWindow?
    var keeper: NSWindow?
    var timer: Timer?
    var lastCommand = -1
    init(directory: URL) { self.directory = directory }
    func applicationDidFinishLaunching(_ notification: Notification) {
        guard let screen = NSScreen.screens.first else { exit(70) }
        let v = screen.visibleFrame
        window = makeWindow(CGRect(x: v.maxX - min(620, v.width * 0.6), y: v.maxY - min(400, v.height * 0.6),
                                   width: min(620, v.width * 0.6), height: min(400, v.height * 0.6)))
        let toolbar = NSToolbar(identifier: "SaytileBoundaryFixtureToolbar")
        toolbar.delegate = self; toolbar.displayMode = .iconOnly
        window.toolbar = toolbar
        window.collectionBehavior = [.fullScreenPrimary]
        window.delegate = self
        window.orderFront(nil)
        _ = Timer.scheduledTimer(withTimeInterval: 120, repeats: false) { _ in
            MainActor.assumeIsolated { NSApp.terminate(nil) }
        }
        write(["pid": getpid(), "windowID": window.windowNumber, "screen": rect(screen.frame),
               "visible": rect(v), "frame": rect(window.frame)], "ready.json")
        timer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.poll() }
        }
    }
    func makeWindow(_ frame: CGRect) -> BoundaryWindow {
        let w = BoundaryWindow(contentRect: frame, styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        w.title = "Saytile synthetic boundary fixture"
        w.isReleasedWhenClosed = false; w.setFrame(frame, display: false)
        let text = NSTextField(labelWithString: "隔离测试文字。此窗口没有用户资料。")
        text.frame = CGRect(x: 25, y: 30, width: 350, height: 30)
        w.contentView?.addSubview(text)
        return w
    }
    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] { [.flexibleSpace, .init("fixtureAction")] }
    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] { [.flexibleSpace, .init("fixtureAction")] }
    func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier id: NSToolbarItem.Identifier, willBeInsertedIntoToolbar: Bool) -> NSToolbarItem? {
        guard id.rawValue == "fixtureAction" else { return nil }
        let item = NSToolbarItem(itemIdentifier: id)
        item.label = "Fixture"
        item.view = NSButton(title: "测试控件", target: nil, action: nil)
        return item
    }
    func window(_ window: NSWindow, willUseFullScreenPresentationOptions proposedOptions: NSApplication.PresentationOptions) -> NSApplication.PresentationOptions {
        proposedOptions.subtracting(.autoHideToolbar)
    }
    func poll() {
        guard let data = try? Data(contentsOf: directory.appendingPathComponent("command.json")),
              let command = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let id = command["id"] as? Int, id > lastCommand,
              let action = command["action"] as? String else { return }
        lastCommand = id
        switch action {
        case "prepare":
            if directory.lastPathComponent == "target" {
                NSApp.activate(ignoringOtherApps: true)
                window.makeKeyAndOrderFront(nil)
            }
            if let screen = NSScreen.screens.first {
                let v = screen.visibleFrame
                window.setFrame(CGRect(x: v.maxX - min(620, v.width * 0.6) - 12, y: v.maxY - min(400, v.height * 0.6) - 12,
                                       width: min(620, v.width * 0.6), height: min(400, v.height * 0.6)), display: true)
                write(["pid": getpid(), "windowID": window.windowNumber, "screen": rect(screen.frame),
                       "visible": rect(v), "frame": rect(window.frame)], "ready.json")
            }
        case "frame":
            if let values = command["frame"] as? [Double], values.count == 4 {
                window.setFrame(CGRect(x: values[0], y: values[1], width: values[2], height: values[3]), display: true)
            }
        case "strictMinimum": window.strictMinimum = command["enabled"] as? Bool ?? false
        case "minimum":
            if let values = command["size"] as? [Double], values.count == 2 { window.minSize = CGSize(width: values[0], height: values[1]) }
        case "hide":
            // Keep the fixture app foreground while its primary target is hidden;
            // otherwise Stage Manager legitimately thumbnails the app on re-show.
            keeper = makeWindow(CGRect(x: window.frame.minX - 120, y: window.frame.minY, width: 120, height: 120))
            keeper?.makeKeyAndOrderFront(nil)
            window.orderOut(nil)
        case "show":
            window.makeKeyAndOrderFront(nil)
            keeper?.close(); keeper = nil
        case "duplicate": duplicate = makeWindow(window.frame); duplicate?.orderFront(nil)
        case "removeDuplicate": duplicate?.close(); duplicate = nil
        case "fullscreen":
            NSApp.activate(ignoringOtherApps: false)
            window.makeKeyAndOrderFront(nil)
            window.toggleFullScreen(nil)
        case "quit": NSApp.terminate(nil)
        default: break
        }
        write(["id": id, "frame": rect(window.frame), "visible": window.isVisible,
               "fullscreen": window.styleMask.contains(.fullScreen), "windowID": window.windowNumber,
               "minSize": [window.minSize.width, window.minSize.height], "refusedSizeWrites": window.refusedSizeWrites], "ack.json")
    }
    func write(_ value: [String: Any], _ filename: String) {
        guard let data = try? JSONSerialization.data(withJSONObject: value, options: [.sortedKeys]) else { return }
        try? data.write(to: directory.appendingPathComponent(filename), options: .atomic)
    }
    func rect(_ r: CGRect) -> [Double] { [r.minX, r.minY, r.width, r.height] }
}
