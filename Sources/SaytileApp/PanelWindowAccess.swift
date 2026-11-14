import AppKit
import ApplicationServices

/// Public, geometry-only AX access for panel coexistence. No title, value, selection,
/// activation, keyboard events, private window-number API, or screenshot capture.
/// The host owns policy, debounce and restoration; this bridge never retries a write.
final class PanelWindowAccess: @unchecked Sendable {
    struct Snapshot: @unchecked Sendable {
        let pid: pid_t
        let windowID: CGWindowID
        let element: AXUIElement
        /// AppKit desktop coordinates (bottom-left origin on the primary screen).
        let frame: CGRect
        let isFullscreen: Bool
        let standardWindow: Bool
        var stableKey: String { "\(pid):\(windowID)" }
        fileprivate let application: NSRunningApplication
        fileprivate let launchDate: Date
    }

    private struct WindowInfo {
        let pid: pid_t
        let id: CGWindowID
        let quartzFrame: CGRect
    }

    private let queue = DispatchQueue(label: "app.saytile.panel-window-access", qos: .utility)
    private let allowedPIDs: Set<pid_t>?

    /// An allowlist is a capability boundary for acceptance: reads and writes both
    /// remain restricted to these fixture processes, including retained snapshots.
    init(allowedPIDs: Set<pid_t>? = nil) { self.allowedPIDs = allowedPIDs }

    func snapshots(allowedPIDs: Set<pid_t>? = nil) -> [Snapshot] {
        queue.sync { collect(allowedPIDs: allowedPIDs) }
    }

    func read(_ snapshot: Snapshot) -> Snapshot? {
        queue.sync { refreshed(snapshot) }
    }

    /// nil means refused or no longer observable. A returned frame is the actual
    /// readback, including a partial resize if the subsequent move is refused.
    /// The caller must compare with `to`, not treat any non-nil result as success.
    func setFrame(_ snapshot: Snapshot, from: CGRect, to: CGRect, shouldProceed: @Sendable () -> Bool = { true }) -> CGRect? {
        queue.sync {
            guard shouldProceed(), valid(to), same(snapshot.frame, from),
                  let current = refreshed(snapshot), same(current.frame, from),
                  current.standardWindow, !current.isFullscreen,
                  writable(current.element), !mouseHeld(),
                  remainsOnDisplay(from: from, to: to) else { return nil }
            let start = quartz(from), destination = quartz(to)
            var expected = start
            if !sameSize(start.size, destination.size) {
                guard let check = refreshed(current), same(quartz(check.frame), expected),
                      writable(check.element), !mouseHeld(), shouldProceed() else { return nil }
                var size = destination.size
                guard let value = AXValueCreate(.cgSize, &size) else { return nil }
                let status = AXUIElementSetAttributeValue(check.element, kAXSizeAttribute as CFString, value)
                var resized = expected; resized.size = destination.size
                guard let actual = awaitReadback(current, expectedQuartz: resized) else { return nil }
                guard status == .success, same(quartz(actual.frame), resized) else { return actual.frame }
                expected = resized
            }
            if !samePoint(expected.origin, destination.origin) {
                guard let check = refreshed(current), same(quartz(check.frame), expected),
                      writable(check.element), !mouseHeld(), shouldProceed() else {
                    // Cancellation after the resize may leave a known partial
                    // frame. Return it only while it is still exactly ours.
                    guard let partial = refreshed(current), same(quartz(partial.frame), expected) else { return nil }
                    return partial.frame
                }
                var point = destination.origin
                guard let value = AXValueCreate(.cgPoint, &point) else { return refreshed(current)?.frame }
                _ = AXUIElementSetAttributeValue(check.element, kAXPositionAttribute as CFString, value)
                return awaitReadback(current, expectedQuartz: destination)?.frame
            }
            return refreshed(current)?.frame
        }
    }

    /// Only the current full-screen window's focused control and nearby toolbar
    /// controls. No document/web/scroll/text subtree is traversed. Unknown is empty.
    func focusedFullscreenObstacles(near panel: CGRect, allowedPIDs: Set<pid_t>? = nil) -> [CGRect] {
        queue.sync {
            guard valid(panel) else { return [] }
            let candidates = collect(allowedPIDs: allowedPIDs)
                .filter { $0.isFullscreen && $0.application.isActive }
            guard candidates.count == 1, let window = candidates.first,
                  let current = refreshed(window), current.isFullscreen else { return [] }
            let root = applicationElement(current.pid)
            guard let focusedWindow = element(root, kAXFocusedWindowAttribute),
                  CFEqual(focusedWindow, current.element) else { return [] }
            let neighborhood = panel.insetBy(dx: -240, dy: -240)
            var result = [CGRect]()
            if let focused = element(root, kAXFocusedUIElementAttribute),
               let owner = element(focused, kAXWindowAttribute), CFEqual(owner, current.element),
               let role = string(focused, kAXRoleAttribute), actionableRoles.contains(role),
               let frame = frame(focused).map(cocoa), frame.intersects(neighborhood) {
                result.append(frame)
            }
            // Only shallow structural containers can lead to a toolbar. Never walk
            // AXWebArea/AXDocument/AXScrollArea merely to search for buttons.
            var pending: [(AXUIElement, Int, Bool)] = [(current.element, 0, false)]
            var visited = 0
            let deadline = ProcessInfo.processInfo.systemUptime + 0.20
            while !pending.isEmpty, visited < 100, ProcessInfo.processInfo.systemUptime < deadline {
                let (node, depth, inToolbar) = pending.removeFirst()
                visited += 1
                guard let role = string(node, kAXRoleAttribute) else { continue }
                let toolbar = inToolbar || role == kAXToolbarRole
                if toolbar, actionableRoles.contains(role), let rect = frame(node).map(cocoa), rect.intersects(neighborhood) {
                    result.append(rect)
                }
                guard depth < 5, structuralRoles.contains(role),
                      (depth == 0 || frame(node).map(cocoa)?.intersects(neighborhood) == true),
                      let children = elements(node, kAXChildrenAttribute, maximum: min(100 - visited, 32)) else { continue }
                pending.append(contentsOf: children.map { ($0, depth + 1, toolbar) })
            }
            // A focus/Space change while reading invalidates every collected obstacle.
            guard let final = refreshed(current), final.isFullscreen, final.application.isActive,
                  let focusedWindow = element(root, kAXFocusedWindowAttribute),
                  CFEqual(focusedWindow, final.element) else { return [] }
            return result.reduce(into: []) { values, next in
                if !values.contains(where: { same($0, next) }) { values.append(next) }
            }
        }
    }

    private let structuralRoles: Set<String> = [kAXWindowRole, kAXGroupRole, kAXSplitGroupRole, kAXToolbarRole]
    private let actionableRoles: Set<String> = [kAXButtonRole, kAXCheckBoxRole, kAXRadioButtonRole,
        kAXPopUpButtonRole, kAXMenuButtonRole, kAXTextFieldRole, kAXTextAreaRole, kAXComboBoxRole,
        kAXSliderRole, kAXIncrementorRole, kAXTabGroupRole]

    private func collect(allowedPIDs requested: Set<pid_t>?) -> [Snapshot] {
        guard allowedPIDs?.isEmpty != true, requested?.isEmpty != true,
              AXIsProcessTrusted(), let visible = visibleWindows() else { return [] }
        let grouped = Dictionary(grouping: visible.filter { permitted($0.pid, requested: requested) }, by: \.pid)
        var result = [Snapshot]()
        for pid in grouped.keys.sorted() {
            guard let app = regularApplication(pid), let launched = app.launchDate,
                  let windows = elements(applicationElement(pid), kAXWindowsAttribute, maximum: 64),
                  let cgWindows = grouped[pid] else { continue }
            let observed = windows.compactMap { window -> (AXUIElement, CGRect)? in
                guard bool(window, kAXMinimizedAttribute) == false, let frame = frame(window) else { return nil }
                return (window, frame)
            }
            for (window, axFrame) in observed {
                let cg = cgWindows.filter { same($0.quartzFrame, axFrame) }
                guard cg.count == 1, let info = cg.first,
                      observed.filter({ same($0.1, axFrame) }).count == 1,
                      let fullscreen = bool(window, "AXFullScreen"), string(window, kAXRoleAttribute) == kAXWindowRole else { continue }
                result.append(Snapshot(pid: pid, windowID: info.id, element: window, frame: cocoa(axFrame),
                    isFullscreen: fullscreen, standardWindow: string(window, kAXSubroleAttribute) == kAXStandardWindowSubrole,
                    application: app, launchDate: launched))
            }
        }
        return result
    }

    private func refreshed(_ snapshot: Snapshot) -> Snapshot? {
        guard AXIsProcessTrusted(), permitted(snapshot.pid, requested: nil),
              let app = regularApplication(snapshot.pid), app.isEqual(snapshot.application), app.launchDate == snapshot.launchDate,
              let windows = elements(applicationElement(snapshot.pid), kAXWindowsAttribute, maximum: 64),
              windows.filter({ CFEqual($0, snapshot.element) }).count == 1,
              bool(snapshot.element, kAXMinimizedAttribute) == false,
              string(snapshot.element, kAXRoleAttribute) == kAXWindowRole,
              let fullscreen = bool(snapshot.element, "AXFullScreen"),
              let axFrame = frame(snapshot.element), let visible = visibleWindows() else { return nil }
        let matches = visible.filter { $0.pid == snapshot.pid && same($0.quartzFrame, axFrame) }
        guard matches.count == 1, matches.first?.id == snapshot.windowID,
              windows.compactMap({ frame($0) }).filter({ same($0, axFrame) }).count == 1 else { return nil }
        return Snapshot(pid: snapshot.pid, windowID: snapshot.windowID, element: snapshot.element, frame: cocoa(axFrame),
            isFullscreen: fullscreen, standardWindow: string(snapshot.element, kAXSubroleAttribute) == kAXStandardWindowSubrole,
            application: app, launchDate: snapshot.launchDate)
    }

    private func permitted(_ pid: pid_t, requested: Set<pid_t>?) -> Bool {
        pid > 0 && pid != getpid() && (allowedPIDs?.contains(pid) ?? true) && (requested?.contains(pid) ?? true)
    }
    private func regularApplication(_ pid: pid_t) -> NSRunningApplication? {
        guard let app = NSRunningApplication(processIdentifier: pid), !app.isTerminated, !app.isHidden,
              app.activationPolicy == .regular else { return nil }
        return app
    }
    private func applicationElement(_ pid: pid_t) -> AXUIElement {
        let value = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(value, 0.06)
        return value
    }
    private func visibleWindows() -> [WindowInfo]? {
        guard let rows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else { return nil }
        return rows.compactMap { row in
            guard (row[kCGWindowLayer as String] as? NSNumber)?.intValue == 0,
                  (row[kCGWindowIsOnscreen as String] as? NSNumber)?.boolValue == true,
                  let pid = (row[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value,
                  let id = (row[kCGWindowNumber as String] as? NSNumber)?.uint32Value,
                  let bounds = row[kCGWindowBounds as String] as? [String: Any],
                  let rect = CGRect(dictionaryRepresentation: bounds as CFDictionary), valid(rect) else { return nil }
            return WindowInfo(pid: pid, id: id, quartzFrame: rect)
        }
    }
    private func writable(_ window: AXUIElement) -> Bool {
        guard string(window, kAXSubroleAttribute) == kAXStandardWindowSubrole,
              bool(window, "AXFullScreen") == false, bool(window, kAXMinimizedAttribute) == false,
              bool(window, kAXModalAttribute) != true else { return false }
        return [kAXPositionAttribute, kAXSizeAttribute].allSatisfy { name in
            var settable = DarwinBoolean(false)
            return AXUIElementIsAttributeSettable(window, name as CFString, &settable) == .success && settable.boolValue
        }
    }
    private func awaitReadback(_ snapshot: Snapshot, expectedQuartz: CGRect) -> Snapshot? {
        for index in 0..<5 {
            if index > 0 { Thread.sleep(forTimeInterval: 0.02) }
            if let actual = refreshed(snapshot) {
                if same(quartz(actual.frame), expectedQuartz) { return actual }
            }
        }
        // Never return a cached earlier frame after the window disappeared or its
        // identity became ambiguous. The host retains its unresolved journal.
        return refreshed(snapshot)
    }
    private func remainsOnDisplay(from: CGRect, to: CGRect) -> Bool {
        var ids = [CGDirectDisplayID](repeating: 0, count: 32), count: UInt32 = 0
        guard CGGetActiveDisplayList(UInt32(ids.count), &ids, &count) == .success else { return false }
        let old = quartz(from), new = quartz(to)
        let owners = ids.prefix(Int(count)).map(CGDisplayBounds).filter { $0.contains(CGPoint(x: old.midX, y: old.midY)) }
        return owners.count == 1 && owners[0].contains(new)
    }
    private func mouseHeld() -> Bool {
        [CGMouseButton.left, .right, .center].contains { CGEventSource.buttonState(.combinedSessionState, button: $0) }
    }
    private func value(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
        var result: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &result) == .success else { return nil }
        return result
    }
    private func string(_ element: AXUIElement, _ name: String) -> String? { value(element, name) as? String }
    private func bool(_ element: AXUIElement, _ name: String) -> Bool? {
        guard let raw = value(element, name), CFGetTypeID(raw) == CFBooleanGetTypeID() else { return nil }
        return CFBooleanGetValue(unsafeDowncast(raw, to: CFBoolean.self))
    }
    private func element(_ source: AXUIElement, _ name: String) -> AXUIElement? {
        guard let raw = value(source, name), CFGetTypeID(raw) == AXUIElementGetTypeID() else { return nil }
        return unsafeDowncast(raw, to: AXUIElement.self)
    }
    private func elements(_ source: AXUIElement, _ name: String, maximum: Int) -> [AXUIElement]? {
        guard maximum > 0 else { return nil }
        var count: CFIndex = 0
        guard AXUIElementGetAttributeValueCount(source, name as CFString, &count) == .success,
              count >= 0, count <= maximum else { return nil }
        if count == 0 { return [] }
        var raw: CFArray?
        guard AXUIElementCopyAttributeValues(source, name as CFString, 0, count, &raw) == .success,
              let values = raw as? [AXUIElement], values.count == count else { return nil }
        return values
    }
    private func frame(_ element: AXUIElement) -> CGRect? {
        guard let position = value(element, kAXPositionAttribute), CFGetTypeID(position) == AXValueGetTypeID(),
              let size = value(element, kAXSizeAttribute), CFGetTypeID(size) == AXValueGetTypeID() else { return nil }
        var p = CGPoint.zero, s = CGSize.zero
        guard AXValueGetValue(unsafeDowncast(position, to: AXValue.self), .cgPoint, &p),
              AXValueGetValue(unsafeDowncast(size, to: AXValue.self), .cgSize, &s) else { return nil }
        let rect = CGRect(origin: p, size: s)
        return valid(rect) ? rect : nil
    }
    private func valid(_ frame: CGRect) -> Bool {
        [frame.minX, frame.minY, frame.width, frame.height].allSatisfy(\.isFinite) && frame.width > 0 && frame.height > 0
    }
    private func cocoa(_ frame: CGRect) -> CGRect {
        CGRect(x: frame.minX, y: CGDisplayBounds(CGMainDisplayID()).height - frame.maxY, width: frame.width, height: frame.height)
    }
    private func quartz(_ frame: CGRect) -> CGRect { cocoa(frame) }
    // Half a physical pixel on a 2x display; never accepts a whole-point move.
    private func close(_ a: CGFloat, _ b: CGFloat) -> Bool { abs(a - b) <= 0.25 }
    private func samePoint(_ a: CGPoint, _ b: CGPoint) -> Bool { close(a.x, b.x) && close(a.y, b.y) }
    private func sameSize(_ a: CGSize, _ b: CGSize) -> Bool { close(a.width, b.width) && close(a.height, b.height) }
    private func same(_ a: CGRect, _ b: CGRect) -> Bool { samePoint(a.origin, b.origin) && sameSize(a.size, b.size) }
}
