import AppKit
import ScreenCaptureKit

// Only two explicitly named windows of our launched, isolated review process are allowed.
@main struct ProductWindowCapture {
    @MainActor static func main() async throws {
        guard CommandLine.arguments.count == 7, let pid = Int32(CommandLine.arguments[1]),
              let win = UInt32(CommandLine.arguments[3]), let back = UInt32(CommandLine.arguments[4]),
              let app = NSRunningApplication(processIdentifier:pid), app.bundleIdentifier == "app.saytile.mac",
              app.bundleURL?.resolvingSymlinksInPath() == URL(fileURLWithPath:CommandLine.arguments[2],isDirectory:true).resolvingSymlinksInPath(),
              CGPreflightScreenCaptureAccess() else { print("BLOCKED capture access or candidate identity"); exit(2) }
        let content = try await SCShareableContent.excludingDesktopWindows(true,onScreenWindowsOnly:true)
        guard let fg = content.windows.first(where: { $0.windowID == win && $0.owningApplication?.processID == pid && ["Saytile · 此刻","语音档案与设置"].contains($0.title ?? "") }),
              let bg = content.windows.first(where: { $0.windowID == back && $0.owningApplication?.processID == pid && $0.title == "Saytile controlled visual environment" }),
              fg.frame == bg.frame, let display = content.displays.first(where:{ $0.frame.contains(fg.frame) }) else { print("FAIL named owned windows not aligned"); exit(3) }
        let config = SCStreamConfiguration(); config.showsCursor = false; config.captureResolution = .best
        config.sourceRect = fg.frame.offsetBy(dx:-display.frame.minX,dy:-display.frame.minY)
        config.width = Int(fg.frame.width*2); config.height = Int(fg.frame.height*2)
        let pair = SCContentFilter(display:display,including:[fg,bg])
        pair.includeMenuBar = false
        let image = try await SCScreenshotManager.captureImage(contentFilter:pair,configuration:config)
        guard let png = NSBitmapImageRep(cgImage:image).representation(using:.png,properties:[:]) else { exit(4) }
        try png.write(to:URL(fileURLWithPath:CommandLine.arguments[5]))
        print("WINDOWSERVER_ONLY fixture="+CommandLine.arguments[6]+" sources=2 width=\(image.width) height=\(image.height)")
    }
}
