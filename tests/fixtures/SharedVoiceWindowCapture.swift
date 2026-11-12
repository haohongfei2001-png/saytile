@preconcurrency import ApplicationServices
import AppKit
import ScreenCaptureKit

/// Exports the two identified windows of one explicitly launched fixture process.
/// WindowServer never receives a screen-wide capture request.
@main struct SharedVoiceWindowCapture {
    enum Failure: Error { case arguments, identity, permission, bounds, image }
    @MainActor static func main() async {
        do { try await capture() } catch { print("capture failed: \(error)"); exit(2) }
    }
    @MainActor static func capture() async throws {
        let a = Array(CommandLine.arguments.dropFirst())
        guard a.count == 9, ["Saytile", "Nearpane"].contains(a[0]), let pid = Int32(a[2]),

              let fgID = UInt32(a[3]), let bgID = UInt32(a[4]) else { throw Failure.arguments }
        let box = NSRectFromString(a[5])
        guard !box.isEmpty else { throw Failure.bounds }
        let bundle = URL(fileURLWithPath: a[1], isDirectory: true).resolvingSymlinksInPath()
        let ids = a[0] == "Saytile" ? ["app.saytile.mac.design-experience", "app.saytile.mac.shared-voice-preview"] :
            ["com.holdsnow.nearpane.host", "com.holdsnow.nearpane.alpha", "com.holdsnow.nearpane.voice-preview"]
        guard let id = Bundle(url: bundle)?.bundleIdentifier, ids.contains(id),
              let app = NSRunningApplication(processIdentifier: pid), !app.isTerminated,
              app.executableURL?.resolvingSymlinksInPath() == Bundle(url: bundle)?.executableURL?.resolvingSymlinksInPath()
              else { throw Failure.identity }
        _ = NSApplication.shared.setActivationPolicy(.prohibited)
        guard CGPreflightScreenCaptureAccess() else { throw Failure.permission }
        let sc = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true)
        let ours = sc.windows.filter { $0.owningApplication?.processID == pid }
        guard let fg = ours.first(where: { $0.windowID == fgID }),
              let bg = ours.first(where: { $0.windowID == bgID && $0.title == a[0] + " controlled visual environment" }),
              bg.frame == fg.frame, let screen = NSScreen.screens.first,
              let display = sc.displays.first(where: { $0.displayID == CGMainDisplayID() })
        else { throw Failure.identity }
        let cg = CGRect(x: box.minX, y: screen.frame.maxY - box.maxY, width: box.width, height: box.height)
        let requested = a[0] == "Saytile" ? cg : fg.frame
        guard fg.frame.insetBy(dx: -1,dy: -1).contains(cg), display.frame.insetBy(dx:-1,dy:-1).contains(requested)
        else {
            print("WindowServer bounds mismatch: window=\(fg.frame) display=\(display.frame) glass=\(cg) source=\(requested) AppKit=\(screen.frame)")
            throw Failure.bounds
        }
        let s = SCStreamConfiguration()
        s.captureResolution = .best
        s.showsCursor = false
        s.sourceRect = requested.offsetBy(dx: -display.frame.minX, dy: -display.frame.minY)
        s.width = Int((requested.width * 2).rounded()); s.height = Int((requested.height * 2).rounded())
        let filter = SCContentFilter(display: display, including: [fg, bg])
        filter.includeMenuBar = false
        let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: s)
        guard image.width == s.width, image.height == s.height,
              let data = NSBitmapImageRep(cgImage: image).representation(using:.png, properties:[:])
        else { throw Failure.image }
        try data.write(to: URL(fileURLWithPath: a[6]), options: .withoutOverwriting)
        let region = [cg.minX-requested.minX, cg.minY-requested.minY, cg.width, cg.height]
        var report: [String:Any] = ["ownedWindows":2, "widthPX":image.width, "heightPX":image.height,
          "contentRelativePoints":region, "sourceCG":[requested.minX, requested.minY, requested.width, requested.height],
          "windowCG":[fg.frame.minX,fg.frame.minY,fg.frame.width,fg.frame.height],
          "backingScale":screen.backingScaleFactor, "screens":NSScreen.screens.count]
        report["accessibility"] = inspect(pid: pid, host: a[0], captureState: a[7], fixture: a[8], glass: cg)
        let dataJSON = try JSONSerialization.data(withJSONObject:report,options:.sortedKeys)
        print(String(decoding:dataJSON,as:UTF8.self))
    }
    /// Target-local readback and press, using the fixture's private pasteboard. No events are posted globally.
    @MainActor static func inspect(pid: pid_t, host: String, captureState: String, fixture: String, glass: CGRect) -> [String:Any] {
        guard AXIsProcessTrusted() else { return ["status":"BLOCKED_AX_AUTHORIZATION"] }
        let root = AXUIElementCreateApplication(pid)
        func value(_ node: AXUIElement, _ name: String) -> CFTypeRef? {
            var v: CFTypeRef?
            return AXUIElementCopyAttributeValue(node, name as CFString, &v) == .success ? v : nil
        }
        var nodes = [String:AXUIElement]()
        var next = value(root, kAXWindowsAttribute) as? [AXUIElement] ?? []
        var seen = Set<CFHashCode>()
        while let node = next.popLast(), seen.count < 1500 {
            guard seen.insert(CFHash(node)).inserted else { continue }
            if let id = value(node, kAXIdentifierAttribute) as? String, ["panel.copy","panel.capture","panel.transcript"].contains(id) { nodes[id] = node }
            next += value(node, kAXChildrenAttribute) as? [AXUIElement] ?? []
        }
        guard let copy = nodes["panel.copy"], let voice = nodes["panel.capture"], let editor = nodes["panel.transcript"] else {
            return ["status":"FAIL_MISSING_NATIVE_ELEMENTS","elements":nodes.keys.sorted()]
        }
        let text = "把今天的讨论记下来。\n下午三点继续。"
        var result: [String:Any] = ["status":"PASS","nativeTextMatches":(value(editor,kAXValueAttribute) as? String)?.contains(text) == true,
                                    "voiceAXValue":value(voice,kAXValueAttribute) as? String ?? ""]
        var frames: [String:[CGFloat]] = [:]
        for (name, node) in nodes {
            guard let pv = value(node, kAXPositionAttribute), CFGetTypeID(pv) == AXValueGetTypeID(),
                  let sv = value(node, kAXSizeAttribute), CFGetTypeID(sv) == AXValueGetTypeID() else { continue }
            var point = CGPoint.zero, size = CGSize.zero
            guard AXValueGetValue(unsafeDowncast(pv, to:AXValue.self), .cgPoint, &point),
                  AXValueGetValue(unsafeDowncast(sv, to:AXValue.self), .cgSize, &size) else { continue }
            frames[name] = [point.x-glass.minX,point.y-glass.minY,size.width,size.height]
        }
        result["framesRelativeToGlassTopLeft"] = frames
        var atStart = CFRange(location:0, length:1)
        if let first = AXValueCreate(.cfRange, &atStart) {
            var attr: CFTypeRef?
            if AXUIElementCopyParameterizedAttributeValue(editor, kAXAttributedStringForRangeParameterizedAttribute as CFString,
                first, &attr) == .success, let attr = attr as? NSAttributedString, attr.length > 0,
               let font = attr.attributes(at:0, effectiveRange:nil)[.init(kAXFontTextAttribute.takeUnretainedValue() as String)] as? [String:Any] {
                if let n = font[kAXFontSizeKey.takeUnretainedValue() as String] as? NSNumber { result["observedTextPointSize"] = n }
                if let n = font[kAXFontNameKey.takeUnretainedValue() as String] as? String { result["observedTextFont"] = n }
            }
        }
        if captureState == "panel-speaking" {
            let board: NSPasteboard
            if host == "Nearpane" {
                guard UUID(uuidString: fixture)?.uuidString.lowercased() == fixture else { return ["status":"FAIL_SESSION"] }
                board = NSPasteboard(name:.init("com.holdsnow.nearpane.acceptance." + fixture))
            } else { board = NSPasteboard(name:.init("app.saytile.voice-comparison." + String(pid))) }
            func pressed(_ expected: String) -> Bool {
                guard AXUIElementPerformAction(copy, kAXPressAction as CFString) == .success else { return false }
                for _ in 0..<20 {
                    if board.string(forType:.string) == expected { return true }
                    Thread.sleep(forTimeInterval:0.025)
                }
                return false
            }
            result["copyGroup"] = pressed(text)
            let actual = (value(editor,kAXValueAttribute) as? String ?? "") as NSString
            let selection = actual.range(of:"下午")
            if selection.location != NSNotFound {
                var r = CFRange(location:selection.location,length:selection.length)
                let selected = AXValueCreate(.cfRange,&r).map {
                    AXUIElementSetAttributeValue(editor,kAXSelectedTextRangeAttribute as CFString,$0) == .success
                } ?? false
                result["copySelection"] = selected && pressed("下午")
            } else { result["copySelection"] = false }
        }
        if result["nativeTextMatches"] as? Bool != true || result["copyGroup"] as? Bool == false || result["copySelection"] as? Bool == false {
            result["status"] = "FAIL"
        }
        return result
    }

}
