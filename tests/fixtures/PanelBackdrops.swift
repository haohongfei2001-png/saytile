import AppKit
import ScreenCaptureKit

// Capture only the launched candidate's panel and our own two-color backdrop.
@main struct PanelBackdrops {
    @MainActor static func main() async throws {
        NSApplication.shared.setActivationPolicy(.prohibited)
        guard CommandLine.arguments.count == 3, let pid = Int32(CommandLine.arguments[1]) else { exit(64) }
        guard CGPreflightScreenCaptureAccess(),
              let app = NSRunningApplication(processIdentifier: pid), app.bundleIdentifier == "app.saytile.mac",
              let path = app.bundleURL?.resolvingSymlinksInPath().path,
              (path.hasPrefix("/private/tmp/saytile-local-final.") || path.hasPrefix("/tmp/saytile-local-final.")), path.hasSuffix("/Applications/Saytile.app") else { exit(2) }
        let dest = URL(fileURLWithPath: CommandLine.arguments[2])
        var target: SCWindow?
        for _ in 0..<40 {
            let content = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true)
            target = content.windows.first { $0.owningApplication?.processID == pid && $0.frame.width >= 280 && $0.frame.height >= 160 }
            if target != nil { break }
            try await Task.sleep(for: .milliseconds(100))
        }
        guard let target, let primary = NSScreen.screens.first else { throw CocoaError(.fileNoSuchFile) }
        let frame = NSRect(x: target.frame.minX, y: primary.frame.maxY - target.frame.maxY, width: target.frame.width, height: target.frame.height)
        let back = NSPanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        back.isReleasedWhenClosed = false
        back.level = NSWindow.Level(rawValue: target.windowLayer)
        back.ignoresMouseEvents = true
        defer { back.orderOut(nil); back.close() }
        for (name, color) in [("light", NSColor(srgbRed: 0.72, green: 0.78, blue: 1, alpha: 1)), ("dark", NSColor(srgbRed: 0.13, green: 0.14, blue: 0.22, alpha: 1))] {
            back.backgroundColor = color
            back.order(.below, relativeTo: Int(target.windowID))
            try await Task.sleep(for: .milliseconds(350))
            let content = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true)
            guard let own = content.windows.first(where: { $0.windowID == target.windowID && $0.owningApplication?.processID == pid }),
                  let bg = content.windows.first(where: { $0.windowID == CGWindowID(back.windowNumber) && $0.owningApplication?.processID == getpid() }),
                  let display = content.displays.first(where: { $0.frame.contains(own.frame) }) else { throw CocoaError(.fileReadUnknown) }
            let config = SCStreamConfiguration()
            config.showsCursor = false
            config.sourceRect = own.frame.offsetBy(dx: -display.frame.minX, dy: -display.frame.minY)
            config.width = Int(own.frame.width * 2); config.height = Int(own.frame.height * 2)
            let filter = SCContentFilter(display: display, including: [own, bg])
            let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
            guard let png = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) else { throw CocoaError(.fileWriteUnknown) }
            try png.write(to: dest.appending(path: name + ".png"))
        }
    }
}
