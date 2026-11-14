import AppKit
@preconcurrency import ApplicationServices
import SwiftUI
import ImageIO
import UniformTypeIdentifiers
import ScreenCaptureKit
@testable import SaytileVoiceUI

struct Row: VoiceTranscriptEntry {
    let id: UUID
    let position: Int64
    var displayText: String
}

private enum Failure: Error { case args, window, edit, capture, press }
@MainActor final class AppModel: ObservableObject {
    let access = PanelTranscriptAccess<Row>()
    let id = UUID(), nextID = UUID()
    @Published var late = ""
    @Published var text = "缩放窗口仍应保留这段可以编辑的文字，数字 24 和手写换行。\n继续记录。"
    @Published var state = VoicePanelState.standby
    @Published var panelBorderVisible = true
    @Published var panelOverFullscreen = false
    var toggles = 0, edits = 0, copies = 0
    var doc: PanelTimelineDocument<Row> {
        var rows = [Row(id:id,position:1,displayText:text)]
        if !late.isEmpty { rows.append(.init(id:nextID,position:2,displayText:late)) }
        return .init(entries:rows)
    }
    func toggle() { toggles += 1; state = state == .paused ? .standby : .paused }
    func commit(_ change: [VoicePanelEdit]) throws -> PanelTimelineDocument<Row> {
        guard change.count == 1, change[0].id == id, change[0].before == text else { throw Failure.edit }
        edits += 1; text = change[0].after; return doc
    }
}

// Product InputPanelWindowView supplies the real rail, border and clipping.
struct InputPanelView: View {
    @ObservedObject var model: AppModel
    var onExpand: (@MainActor () -> Void)?
    var body: some View {
        VoiceSurfacePanel(document: model.doc, access: model.access,
            capture: .init(state: model.state, level: model.state == .recognizing ? 0.7 : nil,
                           actionLabel: model.state == .paused ? "恢复" : "暂停",
                           accessibilityValue: model.state == .paused ? "已暂停" : "待命"),
            canCopy: true, selectedText: "", onCopy: { model.copies += 1 }, onToggle: model.toggle,
            applyEdits: model.commit) { EmptyView() }
    }
}

@MainActor private final class KeepFixtureOpen: NSObject, NSApplicationDelegate {
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply { .terminateCancel }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
}

@MainActor private final class GlassBackdropFixture: NSView {
    override func draw(_ dirtyRect: NSRect) {
        NSColor(srgbRed: 0.16, green: 0.21, blue: 0.38, alpha: 1).setFill()
        bounds.fill()
        NSColor(srgbRed: 0.63, green: 0.72, blue: 0.92, alpha: 1).setFill()
        for x in stride(from: CGFloat(0), to: bounds.width, by: 20) {
            NSRect(x: x, y: 0, width: 10, height: bounds.height).fill()
        }
    }
}

@main private struct AdaptiveVoicePanelProbe {
    @MainActor static func main() {
        if CommandLine.arguments.count == 6 && CommandLine.arguments[1] == "--ax-owned-window" { inspectOwnedWindow(); return }
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        Task { @MainActor in
            do {
                if CommandLine.arguments.dropFirst().first == "--glass-only" { try await glassSnapshots() }
                else { try await run() }
                exit(0)
            } catch { print("Adaptive panel probe: \(error)"); exit(2) }
        }
        app.run()
    }
    /// Uses only two owned, nonactivating windows with synthetic text and a
    /// deterministic backdrop. No installed app, microphone or desktop capture.
    @MainActor static func glassSnapshots() async throws {
        let args = CommandLine.arguments
        guard args.count == 4, let screen = NSScreen.screens.first else { throw Failure.args }
        let folder = URL(fileURLWithPath: args[3])
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let receipt = folder.appendingPathComponent("glass-receipt.json")
        guard CGPreflightScreenCaptureAccess() else {
            try JSONSerialization.data(withJSONObject: ["source": args[2], "status": "BLOCKED",
                "reason": "Screen capture is not already authorized; no permission prompt was requested."])
                .write(to: receipt)
            return
        }
        let frame = NSRect(x: screen.visibleFrame.minX + 48, y: screen.visibleFrame.minY + 48, width: 344, height: 190)
        let backdrop = NSPanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        let panel = NSPanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        let model = AppModel(), host = NSHostingView(rootView: InputPanelWindowView(model: model))
        model.state = .paused
        model.text = "同一段隔离测试文字。\n全屏时加强毛玻璃，字号、按钮和排版保持一致。"
        host.sizingOptions = []
        backdrop.contentView = GlassBackdropFixture(frame: .init(origin: .zero, size: frame.size))
        backdrop.backgroundColor = .white
        backdrop.isOpaque = true
        panel.contentView = host
        panel.backgroundColor = .clear
        panel.isOpaque = false
        for window in [backdrop, panel] {
            window.hasShadow = false; window.ignoresMouseEvents = true
            window.isReleasedWhenClosed = false; window.hidesOnDeactivate = false
        }
        backdrop.orderBack(nil)
        panel.order(.above, relativeTo: backdrop.windowNumber)
        defer { panel.orderOut(nil); backdrop.orderOut(nil); panel.close(); backdrop.close() }
        var variants = [[String: Any]]()
        var originalEditor: NSTextView?
        for border in [true, false] {
            model.panelBorderVisible = border
            for fullscreen in [false, true] {
                model.panelOverFullscreen = fullscreen
                try await Task.sleep(for: .milliseconds(300))
                host.layoutSubtreeIfNeeded(); panel.displayIfNeeded()
                let content = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: false)
                guard let own = content.windows.first(where: { $0.owningApplication?.processID == getpid() && $0.windowID == CGWindowID(panel.windowNumber) }),
                      let back = content.windows.first(where: { $0.owningApplication?.processID == getpid() && $0.windowID == CGWindowID(backdrop.windowNumber) }),
                      own.frame == back.frame, let display = content.displays.first(where: { $0.frame.contains(own.frame) })
                else { throw Failure.window }
                let filter = SCContentFilter(display: display, including: [back, own])
                filter.includeMenuBar = false
                let configuration = SCStreamConfiguration()
                configuration.showsCursor = false
                configuration.sourceRect = own.frame.offsetBy(dx: -display.frame.minX, dy: -display.frame.minY)
                configuration.width = 688; configuration.height = 380
                let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration)
                guard let png = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) else { throw Failure.capture }
                let name = (border ? "border-on-" : "border-off-") + (fullscreen ? "fullscreen" : "desktop")
                try png.write(to: folder.appendingPathComponent(name + ".png"))
                let editor = model.access.view?.transcriptView
                if originalEditor == nil { originalEditor = editor }
                let actualFont: CGFloat?
                if let storage = editor?.textStorage, storage.length > 0 {
                    actualFont = (storage.attribute(.font, at: 0, effectiveRange: nil) as? NSFont)?.pointSize
                } else { actualFont = nil }
                let layout = VoicePanelLayout(size: host.bounds.size)
                guard editor != nil, editor === originalEditor, editor?.string == model.text,
                      !panel.isKeyWindow, !backdrop.isKeyWindow else { throw Failure.window }
                variants.append(["name": name, "windowPt": array(panel.frame), "cardPt": array(layout.cardFrame),
                    "capturePt": array(layout.captureFrame), "copyPt": array(layout.copyFrame),
                    "fontPt": actualFont as Any? ?? NSNull(), "sameEditor": true, "unchangedText": true,
                    "sourceWindows": 2, "everTookKey": false])
            }
        }
        try JSONSerialization.data(withJSONObject: ["source": args[2], "status": "PASS", "variants": variants,
            "capture": "WindowServer composition of exactly two owned fixture windows; context is injected, not actual system fullscreen."],
            options: [.prettyPrinted, .sortedKeys]).write(to: receipt)
    }
    // Separate client process addresses exactly the parent it was spawned by.
    // No system-wide hit tests, no desktop input and no interaction with other apps.
    @MainActor static func inspectOwnedWindow() {
        let args = CommandLine.arguments
        guard let pid = Int32(args[2]), pid == getppid(), let expectedWindow = Int(args[3]) else { exit(2) }
        func value(_ node: AXUIElement, _ name: String) -> CFTypeRef? {
            var v: CFTypeRef?
            guard AXUIElementCopyAttributeValue(node,name as CFString,&v) == .success else { return nil }
            return v
        }
        let app = AXUIElementCreateApplication(pid)
        _ = AXUIElementSetAttributeValue(app, "AXManualAccessibility" as CFString, kCFBooleanTrue)
        _ = AXUIElementSetAttributeValue(app, "AXEnhancedUserInterface" as CFString, kCFBooleanTrue)
        let windows = value(app,kAXWindowsAttribute) as? [AXUIElement] ?? []
        let title = "Saytile adaptive fixture " + String(expectedWindow)
        guard let own = windows.first(where: { value($0,kAXTitleAttribute) as? String == title }) else { print("Missing owned AX window: \(windows.count); trusted=\(AXIsProcessTrusted())"); exit(3) }
        var todo = [own], seen = Set<CFHashCode>(), controls = [String:[[CGFloat]]](), pressed = false
        while let node = todo.popLast(), seen.count < 500 {
            guard seen.insert(CFHash(node)).inserted else { continue }
            if let id = value(node,kAXIdentifierAttribute) as? String, id.hasPrefix("panel."),
               let pos = value(node,kAXPositionAttribute), let size = value(node,kAXSizeAttribute),
               CFGetTypeID(pos) == AXValueGetTypeID(), CFGetTypeID(size) == AXValueGetTypeID() {
                var pt = CGPoint.zero, sz = CGSize.zero
                if AXValueGetValue(unsafeDowncast(pos,to:AXValue.self),.cgPoint,&pt), AXValueGetValue(unsafeDowncast(size,to:AXValue.self),.cgSize,&sz) {
                    controls[id, default:[]].append([pt.x,pt.y,sz.width,sz.height])
                }
                if id == "panel.capture", args[4] == "press" { pressed = AXUIElementPerformAction(node,kAXPressAction as CFString) == .success }
            }
            todo += value(node,kAXChildrenAttribute) as? [AXUIElement] ?? []
        }
        let obj: [String:Any] = ["controls":controls,"pressed":pressed]
        guard let data = try? JSONSerialization.data(withJSONObject:obj), (try? data.write(to:URL(fileURLWithPath:args[5]))) != nil else { exit(4) }
    }
    @MainActor static func inspect(_ panel: NSPanel, output: URL, press: Bool = false) async throws -> ([String:[[CGFloat]]], Bool) {
        let process = Process(); process.executableURL = URL(fileURLWithPath:CommandLine.arguments[0]); process.arguments = ["--ax-owned-window",String(getpid()),String(panel.windowNumber),press ? "press" : "read",output.path]
        try process.run(); while process.isRunning { try await Task.sleep(for:.milliseconds(4)) }
        guard process.terminationStatus == 0, let obj = try JSONSerialization.jsonObject(with: Data(contentsOf:output)) as? [String:Any], let controls = obj["controls"] as? [String:[[CGFloat]]] else { throw Failure.window }
        let top = (NSScreen.screens.first?.frame.maxY ?? 0) - panel.frame.maxY
        return (controls.mapValues { $0.map { [$0[0]-panel.frame.minX,$0[1]-top,$0[2],$0[3]] } }, obj["pressed"] as? Bool ?? false)
    }
    static func array(_ r: CGRect) -> [CGFloat] { [r.minX,r.minY,r.width,r.height] }
    @MainActor static func capture(host: NSView, target: URL) throws {
        guard let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { throw Failure.capture }
        host.cacheDisplay(in: host.bounds, to: bitmap)
        guard let png = bitmap.representation(using: .png, properties: [:]) else { throw Failure.capture }
        try png.write(to: target)
    }
    // Analyze only the rendered test view. Purple columns distinguish the
    // pointed triangle, circular dot and separated bars at any display scale.
    static func glyph(in bitmap: NSBitmapImageRep, state: VoicePanelState) -> Bool {
        var heights = [Int](repeating: 0, count: bitmap.pixelsWide)
        for x in heights.indices {
            for y in 0..<bitmap.pixelsHigh {
                guard let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.sRGB),
                      color.alphaComponent > 0.5, color.blueComponent - color.redComponent > 0.15,
                      color.blueComponent - color.greenComponent > 0.3 else { continue }
                heights[x] += 1
            }
        }
        let groups = zip([0] + heights, heights).filter { $0.0 == 0 && $0.1 > 0 }.count
        let painted = heights.filter { $0 > 0 }
        guard let first = painted.first, let last = painted.last, let peak = painted.max() else { return false }
        switch state {
        case .paused:
            let third = max(1, painted.count / 3)
            let base = painted.prefix(third).reduce(0, +)
            let tip = painted.suffix(third).reduce(0, +)
            return groups == 1 && base > 2 * tip && painted.prefix(third).contains(peak)
        case .standby: return groups == 1 && abs(first - last) <= 2 && painted[painted.count / 2] == peak && peak > first
        case .recognizing: return groups == 5
        default: return false
        }
    }
    @MainActor static func pointer(_ window: VoicePanel, kind: NSEvent.EventType, local: CGPoint) throws {
        guard let event = NSEvent.mouseEvent(with: kind, location: local, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: window.windowNumber, context: nil, eventNumber: 8, clickCount: 1, pressure: kind == .leftMouseUp ? 0 : 1) else { throw Failure.press }
        window.sendEvent(event)
    }

    /// A single physical-coordinate gesture per edge. Sample the resulting window
    /// frame at every point and capture the hosted view without any desktop pixels.
    @MainActor static func recordSweep(window: VoicePanel, host: NSView, folder: URL) async throws -> [[String: Any]] {
        guard let screen = window.screen, let gif = CGImageDestinationCreateWithURL(folder.appendingPathComponent("resize.gif") as CFURL,
            UTType.gif.identifier as CFString, 134, nil) else { throw Failure.capture }
        CGImageDestinationSetProperties(gif, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0]] as CFDictionary)
        let start = CGRect(x: screen.visibleFrame.midX-80, y: screen.visibleFrame.midY-79, width: 156, height: 158)
        window.applyPlacement(start, on: screen.visibleFrame)
        var results = [[String: Any]]()
        for (axis, signedTravel) in [("left",128),("top",-132),("top",132),("left",-128)] {
            let origin = window.frame
            let local = axis == "left" ? CGPoint(x: 2, y: origin.height/2) : CGPoint(x: origin.width/2, y: origin.height-2)
            let mouse = window.convertPoint(toScreen: local)
            try pointer(window, kind: .leftMouseDown, local: local)
            var samples = [Double]()
            let sweepStarted = ProcessInfo.processInfo.systemUptime
            var last = mouse
            var maxWidthError: CGFloat = 0, maxHeightError: CGFloat = 0, maxRightError: CGFloat = 0, maxBottomError: CGFloat = 0
            for step in 0...abs(signedTravel) {
                let delta = CGFloat(step * signedTravel.signum())
                last = CGPoint(x: mouse.x + (axis == "left" ? delta : 0), y: mouse.y + (axis == "top" ? delta : 0))
                if step > 0 { try pointer(window, kind: .leftMouseDragged, local: window.convertPoint(fromScreen: last)) }
                let frame = window.frame
                maxWidthError = max(maxWidthError,abs(frame.width - (origin.width - (axis == "left" ? delta : 0))))
                maxHeightError = max(maxHeightError,abs(frame.height - (origin.height + (axis == "top" ? delta : 0))))
                maxRightError = max(maxRightError,abs(frame.maxX-origin.maxX))
                maxBottomError = max(maxBottomError,abs(frame.minY-origin.minY))
                if step % 4 == 0 || step == abs(signedTravel) {
                    try await Task.sleep(for: .milliseconds(18))
                    host.layoutSubtreeIfNeeded()
                    guard let image = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { throw Failure.capture }
                    host.cacheDisplay(in: host.bounds, to: image)
                    guard let actual = image.cgImage,
                          let context = CGContext(data:nil,width:336,height:340,bitsPerComponent:8,bytesPerRow:0,
                            space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue) else { throw Failure.capture }
                    context.setFillColor(red:0.25,green:0.29,blue:0.35,alpha:1)
                    context.fill(CGRect(x:0,y:0,width:336,height:340))
                    context.draw(actual, in:CGRect(x:12 + (frame.minX - start.minX)*2, y:12 + (frame.minY - start.minY)*2,
                                                   width:frame.width*2, height:frame.height*2))
                    samples.append(ProcessInfo.processInfo.systemUptime - sweepStarted)
                    guard let composed = context.makeImage() else { throw Failure.capture }
                    let delay = (step == 0 || step == abs(signedTravel)) ? 0.35 : 0.035
                    CGImageDestinationAddImage(gif, composed, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: delay]] as CFDictionary)
                }
            }
            try pointer(window, kind: .leftMouseUp, local: window.convertPoint(fromScreen: last))
            results.append(["axis":axis, "travel":signedTravel, "steps":abs(signedTravel), "start":array(origin), "end":array(window.frame),
                "paintTimesSeconds":samples, "widthError":maxWidthError,"heightError":maxHeightError,"rightError":maxRightError,"bottomError":maxBottomError])
        }
        guard CGImageDestinationFinalize(gif) else { throw Failure.capture }
        return results
    }

    @MainActor static func run() async throws {
        let args = CommandLine.arguments
        guard args.count == 3 else { throw Failure.args }
        let folder = URL(fileURLWithPath: args[2])
        let delegate = KeepFixtureOpen()
        NSApplication.shared.delegate = delegate
        NSApplication.shared.setActivationPolicy(.accessory)
        defer { withExtendedLifetime(delegate) {} }
        let model = AppModel(), host = NSHostingView(rootView: InputPanelWindowView(model: model))
        let w = VoicePanel(contentRect: NSRect(x: 0, y: 0, width: 240, height: 126), styleMask: [.borderless,.nonactivatingPanel], backing: .buffered, defer: false)
        w.isFloatingPanel = true; w.becomesKeyOnlyIfNeeded = true
        w.backgroundColor = .clear; w.isOpaque = false; w.hasShadow = false; w.hidesOnDeactivate = false; w.isReleasedWhenClosed = false
        host.sizingOptions = []
        w.contentView = host
        #if SAYTILE_COMPACT_ACTION
        w.compactCaptureAction = model.toggle
        #endif
        // Keep the hit-test fixture below the system menu bar's reveal zone.
        // The gesture probe exercises the actual visibleFrame boundaries.
        if let frame = NSScreen.main?.visibleFrame {
            w.setFrameTopLeftPoint(.init(x: frame.maxX - 376, y: frame.maxY - 48))
        }
        w.title = "Saytile adaptive fixture " + String(w.windowNumber)
        w.orderBack(nil)
        defer { w.orderOut(nil); w.close() }
        try await Task.sleep(for: .milliseconds(260))
        let sizes: [(String,CGFloat,CGFloat)] = [("wide",344,190),("default",178,90),("short",178,64),("smaller",128,82),
            ("narrow",108,158),("edge82",82,158),("edge81",81,158),("edge80",80,158),("edge79",79,158),
            ("tall72",72,158),("control55",55,158),("control54",54,158),("control53",53,158),("tall42",42,158),
            ("tall28",28,158),("mid28",28,76),("short28",28,38),("minimum",28,26),
            ("lowWide",178,26),("restored",344,190)]
        var facts = [[String: Any]](), originalEditor: NSTextView?, syntheticEditOK = false
        var compactClicks = [String: Bool](), compactTestToggles = 0
        var pressed = false, resumed = false, everKey = false, selectedRange: NSRange?, normalHadEditorFocus = false
        let marker = "手工编辑✅"
        var controlsBeforeCornerClicks = 0
        var compactPixels = [String: [String: CGFloat]](), glyphs = [String: Bool]()
        var clicked = false, hitChecks = [String: String](), buttonCorners = [String: Bool]()
        var imeStarted = false, imeSurvivedResize = false, imeSurvivedMinimum = false, imeCommittedOnce = false, lateAppeared = false, compactRejectedKeyFocus = false
        let late = "新到的实时文字。"
        for (label,width,height) in sizes {
            w.setContentSize(.init(width: width, height: height)); host.layoutSubtreeIfNeeded(); w.displayIfNeeded()
            try await Task.sleep(for: .milliseconds(110))
            host.layoutSubtreeIfNeeded(); w.displayIfNeeded(); everKey = everKey || w.isKeyWindow
            let axOutput = folder.appendingPathComponent("ax-" + label + ".json")
            let (controls, _) = try await inspect(w, output: axOutput)
            let view = model.access.view, editor = view?.transcriptView
            if label == "wide", let editor { originalEditor = editor }
            if label == "narrow", let editor {
                let range = NSRange(location: (editor.string as NSString).length, length: 0)
                editor.insertText(" 手工编辑✅", replacementRange: range)
                try await Task.sleep(for: .milliseconds(70))
                syntheticEditOK = model.edits == 1 && model.text.hasSuffix(marker) && editor.string == model.text
                let selected = (editor.string as NSString).range(of: marker)
                editor.setSelectedRange(selected); selectedRange = selected
            }
            if label == "tall72" {
                let old = model.toggles
                // The outer edge is outside both the voice button and the editor.
                try pointer(w, kind: .leftMouseDown, local: .init(x: 2, y: 83))
                try pointer(w, kind: .leftMouseUp, local: .init(x: 2, y: 83))
                compactClicks["upperGlassDoesNotToggle"] = model.toggles == old
            }
            var fontSize: CGFloat?
            if let storage = editor?.textStorage, storage.length > 0 { fontSize = (storage.attribute(.font, at: 0, effectiveRange: nil) as? NSFont)?.pointSize }
            if label == "edge81", let editor {
                normalHadEditorFocus = w.makeFirstResponder(editor) && w.firstResponder === editor
            }
            if label == "minimum" {
                compactRejectedKeyFocus = normalHadEditorFocus && editor.map { !$0.acceptsFirstResponder && w.firstResponder !== $0 } == true
                // Use a private opaque underlay and interrogate WindowServer's
                // mouse-down target at the actual on-screen points. Only record
                // ownership (panel / own backdrop / other), never other IDs.
                let back = NSPanel(contentRect:w.frame,styleMask:[.borderless,.nonactivatingPanel],backing:.buffered,defer:false)
                back.isReleasedWhenClosed = false; back.backgroundColor = .white; back.isOpaque = true; back.hasShadow = false
                w.level = .floating; back.level = .floating; back.orderFront(nil); w.order(.above,relativeTo:back.windowNumber)
                w.displayIfNeeded(); try await Task.sleep(for:.milliseconds(150))
                let probes: [(String, CGPoint)] = [("left",.init(x:2,y:13)),("right",.init(x:26,y:13)),("top",.init(x:14,y:24)),("bottom",.init(x:14,y:2)),("voice",.init(x:14,y:13))]
                for (name,point) in probes {
                    let screen = w.convertPoint(toScreen:point)
                    let top = NSWindow.windowNumber(at:screen,belowWindowWithWindowNumber:0)
                    let under = NSWindow.windowNumber(at:screen,belowWindowWithWindowNumber:w.windowNumber)
                    hitChecks[name] = top == w.windowNumber ? "panel" : (top == back.windowNumber ? "backdrop" : "other")
                    hitChecks[name+"BackdropControl"] = under == back.windowNumber ? "backdrop" : "other"
                }
                back.orderOut(nil); back.close(); w.level = .normal; w.orderBack(nil)
                model.late = late
                pressed = try await inspect(w, output: folder.appendingPathComponent("press-pause.json"), press: true).1

                try await Task.sleep(for: .milliseconds(80))
                pressed = pressed && model.toggles == 1 && model.state == .paused
                resumed = try await inspect(w, output: folder.appendingPathComponent("press-resume.json"), press: true).1

                try await Task.sleep(for: .milliseconds(80))
                resumed = resumed && model.toggles == 2 && model.state == .standby
                // Deliver an ordinary mouse down/up sequence directly to the
                // isolated window, at the *measured* button center. Never post
                // global events, move the real pointer or activate another app.
                if let frame = controls["panel.capture"]?.first {
                    let point = CGPoint(x:frame[0]+frame[2]/2, y:height-frame[1]-frame[3]/2)
                    for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
                        guard let event = NSEvent.mouseEvent(with:type,location:point,modifierFlags:[],timestamp:ProcessInfo.processInfo.systemUptime,windowNumber:w.windowNumber,context:nil,eventNumber:2,clickCount:1,pressure:type == .leftMouseDown ? 1 : 0) else { throw Failure.press }
                        w.sendEvent(event)
                    }
                    try await Task.sleep(for:.milliseconds(120)); clicked = model.toggles == 3 && model.state == .paused
                }
            }
            if label == "minimum" {
                let count = model.toggles
                let points: [(String, CGPoint)] = [
                    ("leftEdge", .init(x: 2, y: height/2)), ("rightEdge", .init(x: width-2, y: height/2)),
                    ("topEdge", .init(x: width/2, y: height-2)), ("bottomEdge", .init(x: width/2, y: 2)),
                    ("leftGlass", .init(x: 6, y: height/2)), ("rightGlass", .init(x: width-6, y: height/2)),
                    ("topGlass", .init(x: width/2, y: height-6)), ("bottomGlass", .init(x: width/2, y: 6))]
                for (name, point) in points {
                    let before = model.toggles, frame = w.frame
                    for kind in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
                        guard let event = NSEvent.mouseEvent(with: kind, location: point, modifierFlags: [],
                            timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: w.windowNumber,
                            context: nil, eventNumber: 4, clickCount: 1, pressure: kind == .leftMouseDown ? 1 : 0)
                            else { throw Failure.press }
                        w.sendEvent(event)
                    }
                    try await Task.sleep(for: .milliseconds(35))
                    compactClicks[name] = model.toggles == before + 1 && w.frame == frame
                }
                compactTestToggles = model.toggles - count
                for border in [true, false] {
                    model.panelBorderVisible = border
                    for (name, state) in [("paused", VoicePanelState.paused), ("standby", .standby), ("recognizing", .recognizing)] {
                        model.state = state
                        try await Task.sleep(for: .milliseconds(220))
                        host.layoutSubtreeIfNeeded()
                        let variant = name + (border ? "" : "-border-off")
                        let target = folder.appendingPathComponent("minimum-" + variant + ".png")
                        try capture(host: host, target: target)
                        guard let bitmap = NSBitmapImageRep(data: try Data(contentsOf: target)) else { throw Failure.capture }
                        func alpha(at x: Double, _ y: Double) -> CGFloat {
                            bitmap.colorAt(x: Int(x * Double(bitmap.pixelsWide) / width),
                                           y: Int(y * Double(bitmap.pixelsHigh) / height))?.alphaComponent ?? 0
                        }
                        // The old floating capsule was transparent on the four
                        // mid-edge samples. The surrounding glass is now the control.
                        compactPixels[variant] = ["left": alpha(at: 3, height/2), "right": alpha(at: width-3, height/2),
                                                  "top": alpha(at: width/2, 3), "bottom": alpha(at: width/2, height-3),
                                                  "corner": alpha(at: 0, 0), "rim": alpha(at: width/2, 0)]
                        glyphs[variant] = glyph(in: bitmap, state: state)
                    }
                }
                model.panelBorderVisible = true
                model.state = .paused
            }
            if label == "restored" {
                controlsBeforeCornerClicks = model.toggles - compactTestToggles
                for id in ["panel.capture", "panel.copy"] {
                    guard let rect = controls[id]?.first else { throw Failure.window }
                    for (name, x, y) in [("topLeft", 1.5, 1.5), ("topRight", rect[2] - 1.5, 1.5),
                                         ("bottomLeft", 1.5, rect[3] - 1.5), ("bottomRight", rect[2] - 1.5, rect[3] - 1.5)] {
                        let point = NSPoint(x: rect[0] + x, y: height - rect[1] - y)
                        let before = (model.toggles, model.copies)
                        for kind in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
                            guard let event = NSEvent.mouseEvent(with: kind, location: point, modifierFlags: [],
                                timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: w.windowNumber,
                                context: nil, eventNumber: 3, clickCount: 1, pressure: kind == .leftMouseDown ? 1 : 0) else { throw Failure.press }
                            w.sendEvent(event)
                        }
                        try await Task.sleep(for: .milliseconds(50))
                        buttonCorners[id + "/" + name] = model.toggles - before.0 == (id == "panel.capture" ? 1 : 0)
                            && model.copies - before.1 == (id == "panel.copy" ? 1 : 0)
                    }
                }
            }
            let rect = view.map { $0.convert($0.bounds, to: nil) } ?? .zero
            let textExposed = controls["panel.transcript"]?.isEmpty == false
            facts.append(["stage": label, "windowPt": array(w.frame), "contentPt": array(host.bounds), "controls": controls,
                "fontPt": fontSize as Any? ?? NSNull(), "editorFramePt": array(rect), "textExposedInAccessibilityTree": textExposed, "sameEditor": editor === originalEditor,
                "editorHasAllText": editor?.string == model.text, "editedTextRetained": model.text.hasSuffix(marker), "selectionRetained": selectedRange.map { editor?.selectedRange() == $0 && view?.selectionSnapshot == marker } ?? false])
            if ["wide","narrow","tall72","control54","tall28","minimum","restored"].contains(label) { try capture(host: host,target: folder.appendingPathComponent(label+".png")) }
        }
        if let scroll = model.access.view {
            let editor = scroll.transcriptView
            editor.setSelectedRange(NSRange(location:0,length:0)); scroll.jumpToLatest()
            try await Task.sleep(for:.milliseconds(60)); lateAppeared = editor.string.hasSuffix(late)
            w.setContentSize(.init(width:108,height:72)); try await Task.sleep(for:.milliseconds(80))
            w.makeFirstResponder(editor); let baseline = model.edits
            editor.setMarkedText("pinyin", selectedRange:.init(location:6,length:0), replacementRange:.init(location:0,length:0))
            imeStarted = editor.hasMarkedText() && model.edits == baseline
            w.setContentSize(.init(width:28,height:26)); try await Task.sleep(for:.milliseconds(80))
            imeSurvivedMinimum = editor.hasMarkedText() && editor.markedRange().length == 6 && model.edits == baseline
            w.setContentSize(.init(width:240,height:140)); try await Task.sleep(for:.milliseconds(95))
            imeSurvivedResize = editor.hasMarkedText() && model.edits == baseline && editor.markedRange().length == 6
            editor.insertText("拼音",replacementRange:editor.markedRange()); try await Task.sleep(for:.milliseconds(90))
            imeCommittedOnce = model.edits == baseline + 1 && model.text.hasPrefix("拼音") && !editor.hasMarkedText()
        }
        let sweep = try await recordSweep(window: w, host: host, folder: folder)
        let report: [String: Any] = ["resizeSweep": sweep, "glyphs": glyphs, "compactPixels": compactPixels, "compactClicks": compactClicks, "buttonCorners": buttonCorners, "perimeterHits":hitChecks,"imeStarted":imeStarted,"imeSurvivedMinimum":imeSurvivedMinimum,"imeSurvivedResize":imeSurvivedResize,"imeCommittedOnce":imeCommittedOnce,"lateCandidateAfterSelectionReleased":lateAppeared,"compactRejectedKeyFocus":compactRejectedKeyFocus,"source":args[1], "stages":facts, "editPersisted":syntheticEditOK, "pausePressed":pressed, "resumePressed":resumed,
                                     "toggleCount":controlsBeforeCornerClicks, "centerClickPaused":clicked, "everTookKey":everKey, "backingScale":w.backingScaleFactor]
        try JSONSerialization.data(withJSONObject: report, options: [.sortedKeys,.prettyPrinted]).write(to: folder.appendingPathComponent("receipt.json"))
    }
}
