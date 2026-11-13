import AppKit
import SwiftUI
import SaytileKit
import SaytileVoiceUI

/// Uses the product's VoicePanel.sendEvent with AppKit mouse events sent only to
/// this process's own window. No global input, clipboard, defaults or archive.
@main
struct VoiceRailGestureProbe {
    struct Problem: Error { let reason: String; init(_ reason: String) { self.reason = reason } }

    @MainActor static func main() {
        do { try run() }
        catch {
            FileHandle.standardError.write(Data("FAIL \(error)\n".utf8))
            exit(1)
        }
    }

    @MainActor static func run() throws {
        guard CommandLine.arguments.count == 3 else { throw Problem("Expected write|restore and an isolated JSON file") }
        let output = URL(fileURLWithPath: CommandLine.arguments[2])
        let app = NSApplication.shared
        app.setActivationPolicy(.prohibited)
        guard let screen = NSScreen.screens.first else { throw Problem("No physical screen") }
        let available = screen.visibleFrame
        let initial = WindowPlacement.initialPanel(visibleFrame: available)
        let panel = VoicePanel(contentRect: initial, styleMask: [.borderless, .resizable, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isReleasedWhenClosed = false
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        let host = NSHostingView(rootView: FramedVoiceSlot { Color.white }.background { VoiceRailGlass(width: initial.width) })
        host.sizingOptions = []
        panel.contentView = host
        panel.setFrame(initial, display: true)
        panel.orderFrontRegardless()
        defer { panel.orderOut(nil); panel.close() }

        func matches(_ a: CGRect, _ b: CGRect) -> Bool {
            abs(a.minX - b.minX) < 0.01 && abs(a.minY - b.minY) < 0.01 &&
            abs(a.width - b.width) < 0.01 && abs(a.height - b.height) < 0.01
        }
        var completions = 0
        panel.didChoosePosition = { completions += 1 }
        func footerGap(in frame: CGRect) -> CGPoint {
            let card = VoiceRailMetrics(width: frame.width).cardFrame(in: CGRect(origin: .zero, size: frame.size))
            let controls = VoicePanelMetrics(width: card.width, inRail: true)
            let copyEnd = card.minX + controls.footerLeading + controls.copyWidth
            let voiceStart = card.maxX - ReferencePanelStyle.footerTrailing * controls.scale - controls.voiceWidth
            return CGPoint(x: (copyEnd + voiceStart) / 2, y: card.minY + controls.footerBottom + controls.controlHeight / 2)
        }
        func drag(_ name: String, from: CGPoint, delta: CGPoint, expect: CGRect) throws {
            let start = panel.convertPoint(toScreen: from)
            let end = CGPoint(x: start.x + delta.x, y: start.y + delta.y)
            let count = completions
            func send(_ type: NSEvent.EventType, at point: CGPoint) throws {
                guard let event = NSEvent.mouseEvent(with: type, location: panel.convertPoint(fromScreen: point),
                    modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: panel.windowNumber,
                    context: nil, eventNumber: 1, clickCount: 1, pressure: 1) else { throw Problem("Mouse event creation") }
                panel.sendEvent(event)
            }
            try send(.leftMouseDown, at: start)
            for step in 1...8 {
                let fraction = CGFloat(step) / 8
                try send(.leftMouseDragged, at: CGPoint(x: start.x + delta.x * fraction, y: start.y + delta.y * fraction))
                guard NSScreen.screens.contains(where: { $0.visibleFrame.contains(panel.frame) }) else {
                    throw Problem(name + " escaped during drag at step " + String(step) + ": " + String(describing: panel.frame))
                }
            }
            guard matches(panel.frame, expect), completions == count else {
                throw Problem("\(name) before mouse-up expected \(expect), got \(panel.frame), completion delta \(completions-count)")
            }
            try send(.leftMouseUp, at: end)
            guard completions == count + 1, matches(panel.frame, expect), !panel.isKeyWindow else { throw Problem(name + " failed; observed " + String(describing: panel.frame)) }
            print("PASS \(name) frame=\(panel.frame)")
        }
        if CommandLine.arguments[1] == "restore" {
            let stored = try JSONDecoder().decode(SavedPanelPlacement.self, from: Data(contentsOf: output))
            guard let frame = stored.restored(on: [("primary", available)]), let height = stored.expandedHeight else { throw Problem("Restore rejected") }
            panel.expandedHeight = height
            panel.applyPlacement(frame, on: available)
            guard matches(frame, stored.frame), matches(panel.frame, frame), !panel.isKeyWindow else { throw Problem("Relaunch geometry/focus") }
            let width = min(128, available.width)
            let end = CGRect(x: frame.maxX - width, y: frame.maxY - height, width: width, height: height)
            try drag("reopen compact and drag left edge out", from: CGPoint(x: 2, y: frame.height / 2),
                     delta: CGPoint(x: frame.width - width, y: 0), expect: end)
            print("PASS restored in fresh process pid=\(getpid()) frame=\(panel.frame)")
            return
        }
        guard CommandLine.arguments[1] == "write", !FileManager.default.fileExists(atPath: output.path) else {
            throw Problem("Requires an unused fixture file")
        }
        // The 1024-point CI desktop has a 128 × 69 factory panel. Its upper
        // text margin is too narrow to assume a draggable strip above the editor.
        let compact = CGRect(x: available.midX.rounded() - 64, y: available.midY.rounded() - 34, width: 128, height: 69)
        panel.setFrame(compact, display: true)
        guard matches(panel.frame, compact) else { throw Problem("Compact fixture did not start at 128 × 69") }
        let compactEnd = WindowPlacement.restoredPanel(compact.offsetBy(dx: -32, dy: -16), visibleFrames: [available])
        try drag("128 × 69 footer gap drag", from: footerGap(in: compact), delta: CGPoint(x: -32, y: -16), expect: compactEnd)
        panel.applyPlacement(initial, on: available)
        let f = panel.frame
        try drag("factory footer gap drag", from: footerGap(in: f), delta: CGPoint(x: -80, y: -60), expect: f.offsetBy(dx: -80, dy: -60))
        let moved = panel.frame
        try drag("left edge resize", from: CGPoint(x: 2, y: moved.height / 2), delta: CGPoint(x: -45, y: 0),
                 expect: CGRect(x: moved.minX - 45, y: moved.minY, width: moved.width + 45, height: moved.height))
        let wide = panel.frame
        try drag("bottom corner resize", from: CGPoint(x: wide.width - 3, y: 3), delta: CGPoint(x: 22, y: -30),
                 expect: CGRect(x: wide.minX, y: wide.minY - 30, width: wide.width + 22, height: wide.height + 30))
        func dragGutter(to pointer: CGPoint, on target: NSScreen, name: String) throws {
            let before = panel.frame
            let gutter = footerGap(in: before)
            let start = panel.convertPoint(toScreen: gutter)
            // NSWindow snaps its origin to the display grid. Use whole-point
            // travel so exact end-frame comparisons work at both 1x and 2x.
            let delta = CGPoint(x: (pointer.x - start.x).rounded(), y: (pointer.y - start.y).rounded())
            let proposed = before.offsetBy(dx: delta.x, dy: delta.y)
            let expected = WindowPlacement.restoredPanel(proposed, visibleFrames: [target.visibleFrame])
            try drag(name, from: gutter, delta: delta, expect: expected)
        }
        try dragGutter(to: CGPoint(x: screen.frame.minX + 1, y: screen.frame.minY + 1), on: screen, name: "live left and bottom containment")
        try dragGutter(to: CGPoint(x: screen.frame.maxX - 1, y: screen.frame.maxY - 1), on: screen, name: "live right and top containment")
        let pinned = panel.frame
        try drag("extend bottom-left corner to available bounds", from: CGPoint(x: 2, y: 2),
                 delta: CGPoint(x: -available.width * 2, y: -available.height * 2), expect: available)
        try drag("shrink from full screen", from: CGPoint(x: 2, y: 2),
                 delta: CGPoint(x: available.width - pinned.width, y: available.height - pinned.height), expect: pinned)
        if let other = NSScreen.screens.first(where: { $0.frame != screen.frame }) {
            try dragGutter(to: CGPoint(x: other.visibleFrame.midX, y: other.visibleFrame.midY), on: other, name: "cross to second display")
            try dragGutter(to: CGPoint(x: available.midX, y: available.midY), on: screen, name: "return to original display")
        } else {
            print("NOT_RUN physical second-display drag (one display connected)")
        }
        let beforeFold = panel.frame
        let compactSize = SaytileVoiceUI.VoicePanelFootprint.minimumSize
        let folded = CGRect(x: beforeFold.maxX - compactSize.width, y: beforeFold.maxY - compactSize.height,
                            width: compactSize.width, height: compactSize.height)
        try drag("fold left edge to the single control", from: CGPoint(x: 2, y: beforeFold.height / 2),
                 delta: CGPoint(x: beforeFold.width - compactSize.width, y: 0), expect: folded)
        try drag("reopen left edge keeping top and previous height", from: CGPoint(x: 2, y: folded.height / 2),
                 delta: CGPoint(x: compactSize.width - beforeFold.width, y: 0), expect: beforeFold)
        let rightFold = CGRect(x: beforeFold.minX, y: folded.minY, width: folded.width, height: folded.height)
        try drag("fold from the right", from: CGPoint(x: beforeFold.width - 2, y: beforeFold.height / 2),
                 delta: CGPoint(x: compactSize.width - beforeFold.width, y: 0), expect: rightFold)
        try drag("reopen from the right", from: CGPoint(x: rightFold.width - 2, y: rightFold.height / 2),
                 delta: CGPoint(x: beforeFold.width - compactSize.width, y: 0), expect: beforeFold)
        try drag("fold again for restart", from: CGPoint(x: 2, y: beforeFold.height / 2),
                 delta: CGPoint(x: beforeFold.width - compactSize.width, y: 0), expect: folded)
        try drag("move narrow control from its top margin", from: CGPoint(x: folded.width / 2, y: folded.height - 3),
                 delta: CGPoint(x: -24, y: -22), expect: folded.offsetBy(dx: -24, dy: -22))
        try drag("return narrow control using the bottom margin", from: CGPoint(x: folded.width / 2, y: 3),
                 delta: CGPoint(x: 24, y: 22), expect: folded)
        let final = panel.frame
        panel.orderOut(nil); panel.orderFrontRegardless()
        guard matches(panel.frame, final), let saved = SavedPanelPlacement(frame: final, visibleFrame: available, displayID: "primary", expandedHeight: panel.expandedHeight) else {
            throw Problem("Hide/show")
        }
        try JSONEncoder().encode(saved).write(to: output, options: .withoutOverwriting)
        print("PASS hide/show and persisted geometry pid=\(getpid())")
    }
}
