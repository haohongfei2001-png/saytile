import AppKit
import ApplicationServices
import Darwin

/// Only traverses the AX tree of the specifically launched, paused fixture.
@main struct StatusMenuProbe {
    struct Failure: Error { let reason: String; init(_ reason: String) { self.reason = reason } }
    struct Owned: @unchecked Sendable { let element: AXUIElement }
    static func attr(_ node: AXUIElement, _ key: String) -> CFTypeRef? {
        var result: CFTypeRef?
        guard AXUIElementCopyAttributeValue(node, key as CFString, &result) == .success else { return nil }
        return result
    }
    static func children(_ node: AXUIElement, pid: pid_t) -> [AXUIElement] {
        (attr(node, kAXChildrenAttribute) as? [AXUIElement] ?? []).filter {
            var owner: pid_t = 0
            return AXUIElementGetPid($0, &owner) == .success && owner == pid
        }
    }
    static func status(_ pid: pid_t) -> AXUIElement? {
        let root = AXUIElementCreateApplication(pid)
        guard let raw = attr(root, "AXExtrasMenuBar"), CFGetTypeID(raw) == AXUIElementGetTypeID() else { return nil }
        let bar = unsafeDowncast(raw, to: AXUIElement.self)
        return children(bar, pid: pid).first { node in
            [kAXTitleAttribute, kAXDescriptionAttribute].contains { attr(node, $0) as? String == "Saytile 菜单" }
        }
    }
    static func find(_ roots: [AXUIElement], pid: pid_t, matching: (AXUIElement) -> Bool) -> AXUIElement? {
        var queue = roots, seen = Set<CFHashCode>()
        while seen.count < 200, !queue.isEmpty {
            let node = queue.removeFirst()
            guard seen.insert(CFHash(node)).inserted else { continue }
            if matching(node) { return node }
            queue += children(node, pid: pid)
        }
        return nil
    }
    @MainActor static func wait(_ target: String, _ ready: () -> Bool) async throws {
        let deadline = ContinuousClock.now + .seconds(5)
        while !ready() {
            guard ContinuousClock.now < deadline else { throw Failure(target) }
            try await Task.sleep(for: .milliseconds(35))
        }
    }

    @MainActor static func run() async throws {
        let takeScreenshots = CommandLine.arguments.count == 4 && CommandLine.arguments[3] == "--screenshots"
        guard (CommandLine.arguments.count == 3 || takeScreenshots), AXIsProcessTrusted() else { throw Failure("expected isolated app, new directory and existing AX permission") }
        let url = URL(fileURLWithPath: CommandLine.arguments[1]).resolvingSymlinksInPath()
        let base = URL(fileURLWithPath: CommandLine.arguments[2]).resolvingSymlinksInPath()
        let identifier = "app.saytile.test.menu." + base.lastPathComponent
        guard base.lastPathComponent.hasPrefix("menuprobe-"),
              base.deletingLastPathComponent().resolvingSymlinksInPath().path == URL(fileURLWithPath: "/private/tmp").resolvingSymlinksInPath().path,
              url.deletingLastPathComponent().resolvingSymlinksInPath().path == base.path, Bundle(url: url)?.bundleIdentifier == identifier,
              NSRunningApplication.runningApplications(withBundleIdentifier: identifier).isEmpty else { throw Failure("target outside unique test directory") }
        let data = base.appending(path: "new-data")
        guard !FileManager.default.fileExists(atPath: data.path) else { throw Failure("expected fresh directory") }
        NSApplication.shared.setActivationPolicy(.prohibited)
        let config = NSWorkspace.OpenConfiguration()
        config.createsNewApplicationInstance = true; config.activates = false; config.addsToRecentItems = false
        config.arguments = ["--data-directory", data.path]
        let syntheticHome = base.appending(path: "ordinary-home")
        try FileManager.default.createDirectory(at: syntheticHome, withIntermediateDirectories: false)
        config.environment = ["CFFIXED_USER_HOME": syntheticHome.path]
        func launch() async throws -> NSRunningApplication {
            let next = try await NSWorkspace.shared.openApplication(at: url, configuration: config)
            guard next.bundleIdentifier == identifier, next.bundleURL?.resolvingSymlinksInPath() == url else { throw Failure("unexpected launch identity") }
            return next
        }
        var app = try await launch()
        func kernelExited(_ processID: pid_t) -> Bool {
            processID > 0 && Darwin.kill(processID, 0) == -1 && errno == ESRCH
        }
        defer { if !kernelExited(app.processIdentifier) && !app.isTerminated { app.terminate() } }
        var pid = app.processIdentifier, root = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(root, 0.4)
        func stop() async throws {
            let stoppingPID = app.processIdentifier
            guard stoppingPID > 0, stoppingPID == pid, app.bundleIdentifier == identifier,
                  app.bundleURL?.resolvingSymlinksInPath() == url else { throw Failure("unexpected termination target") }
            guard app.terminate() else { throw Failure("fixture could not close cleanly") }
            do {
                try await wait("fixture did not terminate") { kernelExited(stoppingPID) }
            } catch {
                // Read only this disposable process's window levels. Do not read titles.
                let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
                let levels = windows.filter { $0[kCGWindowOwnerPID as String] as? pid_t == stoppingPID }
                    .compactMap { $0[kCGWindowLayer as String] as? Int }
                let result = Darwin.kill(stoppingPID, 0)
                let kernelError = result == -1 ? errno : 0
                throw Failure("fixture exit timeout pid=\(stoppingPID) signalZero=\(result) errno=\(kernelError) appKitTerminated=\(app.isTerminated) ownedWindowLevels=\(levels)")
            }
        }
        func coldLaunch(_ extra: [String] = []) async throws {
            try await stop()
            config.arguments = ["-shortcutChoice", "disabled", "-floatingEntryEnabled", "NO"] + extra
            app = try await launch()
            pid = app.processIdentifier
            root = AXUIElementCreateApplication(pid)
            AXUIElementSetMessagingTimeout(root, 0.4)
            try await wait("ordinary fixture status") { status(pid) != nil }
        }
        let initialFront = NSWorkspace.shared.frontmostApplication?.processIdentifier
        func panel() -> AXUIElement? {
            (attr(root, kAXWindowsAttribute) as? [AXUIElement])?.first { (attr($0, kAXTitleAttribute) as? String) == "Saytile · 此刻" }
        }
        func editor() -> AXUIElement? {
            guard let window = panel() else { return nil }
            return find([window], pid: pid) { attr($0, kAXIdentifierAttribute) as? String == "panel.transcript" }
        }
        func rect(of element: AXUIElement) -> CGRect? {
            guard let position = attr(element, kAXPositionAttribute), CFGetTypeID(position) == AXValueGetTypeID(),
                  let size = attr(element, kAXSizeAttribute), CFGetTypeID(size) == AXValueGetTypeID() else { return nil }
            var origin = CGPoint.zero
            var extent = CGSize.zero
            guard AXValueGetValue(unsafeDowncast(position, to: AXValue.self), .cgPoint, &origin),
                  AXValueGetValue(unsafeDowncast(size, to: AXValue.self), .cgSize, &extent) else { return nil }
            return CGRect(origin: origin, size: extent)
        }
        func captureButton() -> AXUIElement? {
            guard let window = panel() else { return nil }
            return find([window], pid: pid) { attr($0, kAXIdentifierAttribute) as? String == "panel.capture" }
        }
        func paused() -> Bool {
            guard let capture = captureButton() else { return false }
            return attr(capture, kAXValueAttribute) as? String == "暂停"
        }
        var capturedStates: Set<Bool> = []
        var opened = 0, cancelled = 0, shown = 0, hidden = 0
        func round(_ command: String?, visible: Bool) async throws {
            let expected = visible ? "收起语音板" : "展开语音板"
            guard command == nil || command == expected else { throw Failure("invalid fixture command") }
            guard let button = status(pid) else { throw Failure("fixed status item missing") }
            let initialFrame = panel().flatMap(rect(of:))
            guard visible == (initialFrame != nil), !visible || paused() else { throw Failure("unexpected panel before menu") }
            let owner = Owned(element: button)
            async let open: Int32 = Task.detached {
                AXUIElementSetMessagingTimeout(owner.element, 8)
                return AXUIElementPerformAction(owner.element, kAXPressAction as CFString).rawValue
            }.value
            // Only the popup corresponding to this AX menu must close. The app can
            // have other floating or help windows at the same WindowServer level.
            func elevatedWindows() -> [(number: UInt32, bounds: CGRect)] {
                let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
                return windows.compactMap { item in
                    guard (item[kCGWindowOwnerPID as String] as? Int32) == pid,
                          (item[kCGWindowLayer as String] as? Int ?? 0) >= CGWindowLevelForKey(.mainMenuWindow),
                          let number = item[kCGWindowNumber as String] as? UInt32,
                          let bounds = item[kCGWindowBounds as String] as? NSDictionary,
                          let frame = CGRect(dictionaryRepresentation: bounds), frame.height > 55 else { return nil }
                    return (number, frame)
                }
            }
            var menu: AXUIElement?
            var menuWindow: UInt32?
            try await wait("single status press failed to open the matching menu on screen") {
                menu = find([button] + children(root, pid: pid), pid: pid) { attr($0, kAXRoleAttribute) as? String == kAXMenuRole }
                guard let menu, let frame = rect(of: menu) else { return false }
                let matches = elevatedWindows().filter { window in
                    let overlap = frame.intersection(window.bounds)
                    return !overlap.isNull && frame.width > 0 && frame.height > 0
                        && overlap.width * overlap.height >= frame.width * frame.height * 0.85
                        && abs(frame.width - window.bounds.width) < 24 && abs(frame.height - window.bounds.height) < 24
                }
                guard matches.count == 1 else { return false }
                menuWindow = matches[0].number
                return true
            }
            guard let menu, let menuWindow else { throw Failure("missing owned menu window") }
            var dismissed = false
            defer { if !dismissed { _ = AXUIElementPerformAction(menu, kAXCancelAction as CFString) } }
            let items = children(menu, pid: pid)
            let titles = items.compactMap { attr($0, kAXTitleAttribute) as? String }
            let destinations = Set([expected, "语音档案与设置…", "退出 Saytile"])
            let visibleTitles = titles.filter { !$0.isEmpty }
            let menuTitles = Set(visibleTitles)
            guard visibleTitles.count == menuTitles.count, destinations.isSubset(of: menuTitles),
                  menuTitles.isSubset(of: destinations.union(["检查更新…"])),
                  panel().flatMap(rect(of:)) == initialFrame, !visible || paused() else {
                throw Failure("incorrect menu actions, panel frame or capture state: " + titles.joined(separator: " / "))
            }
            if takeScreenshots, !capturedStates.contains(visible) {
                // Capture only the exact window previously matched to this fixture's AX
                // menu. Never fall back to a desktop capture or select by window title.
                guard elevatedWindows().contains(where: { $0.number == menuWindow }) else {
                    throw Failure("the owned popup disappeared before its capture")
                }
                let name = visible ? "panel-visible.png" : "panel-hidden.png"
                let image = base.appending(path: name)
                let exitStatus = try await Task.detached {
                    let tool = Process()
                    tool.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
                    tool.arguments = ["-x", "-o", "-l", String(menuWindow), image.path]
                    try tool.run()
                    tool.waitUntilExit()
                    return tool.terminationStatus
                }.value
                guard exitStatus == 0, let bitmap = NSBitmapImageRep(data: try Data(contentsOf: image)),
                      bitmap.pixelsWide > 0, bitmap.pixelsHigh > 0 else { throw Failure("owned window capture failed") }
                capturedStates.insert(visible)
                print("STATUS_NATIVE_SCREENSHOT", name, "pixels=\(bitmap.pixelsWide)x\(bitmap.pixelsHigh)")
            }
            if let command {
                guard let chosen = items.first(where: { attr($0, kAXTitleAttribute) as? String == command }),
                      AXUIElementPerformAction(chosen, kAXPressAction as CFString) == .success else { throw Failure("explicit command failed") }
            } else {
                guard AXUIElementPerformAction(menu, kAXCancelAction as CFString) == .success else { throw Failure("menu cancellation failed") }
            }
            let pressResult = await open
            // On macOS 27 AXPress can finish with AXError.failure after a separately
            // issued menu-item press has already completed. WindowServer and the
            // actual action outcome are verified independently; do not retry.
            print("STATUS_TRIGGER_AX", pressResult)
            try await wait("the menu's own window is still on screen") {
                !elevatedWindows().contains { $0.number == menuWindow }
            }
            dismissed = true
            if command == nil {
                guard panel().flatMap(rect(of:)) == initialFrame, !visible || paused() else { throw Failure("cancel changed panel") }
                cancelled += 1
            } else if visible { hidden += 1 } else { shown += 1 }
            opened += 1
            print("STATUS_NATIVE_ROUND command=\(command ?? "cancel") visibleWhileOpen=\(visible) solePanelAction=\(expected) captureCommands=0")
        }
        /// Exercise the panel's own native context menu independently of the status item.
        func restoreReadingSize() async throws {
            guard let capture = captureButton(), paused() else { throw Failure("paused compact control missing") }
            let owner = Owned(element: capture)
            let opening = Task.detached {
                AXUIElementSetMessagingTimeout(owner.element, 8)
                return AXUIElementPerformAction(owner.element, kAXShowMenuAction as CFString).rawValue
            }
            var context: AXUIElement?
            var chosen: AXUIElement?
            do {
                try await wait("compact control context menu did not offer a reading size command") {
                    context = find([capture] + children(root, pid: pid), pid: pid) { attr($0, kAXRoleAttribute) as? String == kAXMenuRole }
                    guard let context else { return false }
                    let items = children(context, pid: pid)
                    let matches = items.filter { attr($0, kAXTitleAttribute) as? String == "恢复阅读尺寸" }
                    guard matches.count == 1, !items.contains(where: {
                        ["收起输入板", "收起语音板", "展开语音板"].contains(attr($0, kAXTitleAttribute) as? String ?? "")
                    }) else { return false }
                    chosen = matches[0]
                    return true
                }
                guard let chosen, AXUIElementPerformAction(chosen, kAXPressAction as CFString) == .success else {
                    throw Failure("failed to select the reading size command")
                }
            } catch {
                if let context { _ = AXUIElementPerformAction(context, kAXCancelAction as CFString) }
                let result = await opening.value
                throw Failure("\(error) AXShowMenu=\(result)")
            }
            print("CONTEXT_TRIGGER_AX", await opening.value)
        }
        try await wait("fixture status menu item unavailable") { status(pid) != nil }
        try await round(nil, visible: false)
        guard panel() == nil, status(pid) != nil else { throw Failure("opening menu changed capture or visibility") }
        try await round("展开语音板", visible: false)
        try await wait("panel was not shown") { editor() != nil }
        let sample = "菜单打开前的隔离编辑"
        guard let text = editor(), AXUIElementSetAttributeValue(text, kAXValueAttribute as CFString, sample as CFString) == .success else { throw Failure("fixture editing unavailable") }
        var range = CFRange(location: 1, length: 3)
        guard let value = AXValueCreate(.cfRange, &range),
              AXUIElementSetAttributeValue(text, kAXSelectedTextRangeAttribute as CFString, value) == .success else { throw Failure("fixture selection unavailable") }
        try await round(nil, visible: true)
        var actual = CFRange()
        guard let text = editor(), attr(text, kAXValueAttribute) as? String == sample,
              let selected = attr(text, kAXSelectedTextRangeAttribute), CFGetTypeID(selected) == AXValueGetTypeID(),
              AXValueGetValue(unsafeDowncast(selected, to: AXValue.self), .cfRange, &actual),
              actual.location == range.location && actual.length == range.length else { throw Failure("open/cancel disturbed edit or selection") }
        try await round("收起语音板", visible: true)
        try await wait("explicit hide did not close panel") { panel() == nil }
        try await round(nil, visible: false)
        guard status(pid) != nil, initialFront == NSWorkspace.shared.frontmostApplication?.processIdentifier else { throw Failure("capture or foreground changed") }
        try await coldLaunch()
        try await wait("ordinary first launch must show the board") { panel() != nil }
        let ordinaryDatabase = syntheticHome.appending(path: "Library/Application Support/Saytile/Saytile.sqlite")
        guard FileManager.default.fileExists(atPath: ordinaryDatabase.path) else { throw Failure("ordinary fixture database outside synthetic home") }
        try await coldLaunch()
        try await wait("visible board disappeared on a normal relaunch") { panel() != nil }
        try await round("收起语音板", visible: true)
        try await wait("explicit ordinary hide") { panel() == nil }
        try await coldLaunch()
        try await round("展开语音板", visible: false)
        try await wait("explicit ordinary show") { panel() != nil }
        try await coldLaunch()
        try await wait("explicit show was not remembered") { panel() != nil }
        // Start the real product with a minimum placement, as for a user already stuck
        // on 0.8. Argument-domain data doesn't touch any production preferences.
        struct PlacementSeed: Encodable {
            let displayID: String
            let frame, visibleFrame: CGRect
            let expandedHeight: CGFloat
            let expandedWidth: CGFloat?
            let anchorsRightOnExpand: Bool?
        }
        guard let screen = NSScreen.screens.first, let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber,
              let uuid = CGDisplayCreateUUIDFromDisplayID(number.uint32Value)?.takeRetainedValue() else { throw Failure("missing fixture screen") }
        let visible = screen.visibleFrame
        func panelSize() -> CGSize? {
            guard let w = panel(), let raw = attr(w, kAXSizeAttribute), CFGetTypeID(raw) == AXValueGetTypeID() else { return nil }
            var sz = CGSize.zero
            return AXValueGetValue(unsafeDowncast(raw, to: AXValue.self), .cgSize, &sz) ? sz : nil
        }
        let oldSize = CGSize(width: 72, height: 44)
        let seeds = [(legacy: true, size: oldSize), (false, oldSize),
                     (false, CGSize(width: 28, height: 26)), (false, CGSize(width: 54, height: 218)),
                     (false, CGSize(width: 208, height: 32))]
        for (legacy, size) in seeds {
            let small = CGRect(x: visible.maxX - size.width, y: visible.maxY - size.height,
                               width: size.width, height: size.height)
            let height: CGFloat = legacy ? 171 : 176
            let width: CGFloat = legacy ? max(128, 0.125 * visible.width) : 304
            let seed = PlacementSeed(displayID: CFUUIDCreateString(nil, uuid) as String,
                                     frame: small, visibleFrame: visible, expandedHeight: height,
                                     expandedWidth: legacy ? nil : width, anchorsRightOnExpand: legacy ? nil : true)
            let bytes = try JSONEncoder().encode(seed)
            try await coldLaunch(["-panel.userPlacement.v4", "<" + bytes.map { String(format: "%02x", $0) }.joined() + ">"])
            try await wait("minimum placement on real launch") { panelSize() == small.size }
            try await wait("capture target must stay on the lower right at the saved size") {
                guard let window = panel(), let frame = rect(of: window),
                      let button = find([window], pid: pid, matching: { attr($0, kAXIdentifierAttribute) as? String == "panel.capture" }),
                      let target = rect(of: button) else { return false }
                // AX positions measure down from the top of the display.
                let bottom = frame.maxY - target.maxY
                let right = frame.maxX - target.maxX
                return abs(target.width - min(54, frame.width)) <= 1 && abs(target.height - 26) <= 1
                    && (-1...24).contains(right) && (-1...18).contains(bottom)
            }
            guard let narrow = panel().flatMap(rect(of:)) else { throw Failure("missing compact frame") }
            try await round(nil, visible: true)
            try await round("收起语音板", visible: true)
            try await wait("compact board stayed on screen") { panel() == nil }
            try await round("展开语音板", visible: false)
            try await wait("reopening changed compact placement or capture") { panel().flatMap(rect(of:)) == narrow && paused() }
            try await restoreReadingSize()
            func expanded() -> Bool {
                guard let sz = panelSize() else { return false }
                return abs(sz.width - width) <= 1 && abs(sz.height - height) <= 1 && editor() != nil
            }
            try await wait("menu must restore a readable panel without touching capture") { expanded() && paused() && status(pid) != nil }
            try await coldLaunch()
            try await wait("restored reading size must persist on ordinary launch") { expanded() && paused() && status(pid) != nil }
            print("COMPACT_CONTEXT_RESTORE_PASS legacy=\(legacy) start=\(size.width)x\(size.height) restored=\(width)x\(height) reopenedSameFrame=true relaunched=true paused=true")
        }
        guard initialFront == NSWorkspace.shared.frontmostApplication?.processIdentifier else { throw Failure("expanding unexpectedly activated another app") }
        if takeScreenshots, capturedStates != [true, false] { throw Failure("missing one menu screenshot") }
        try await stop()
        print("STATUS_MENU_RELAUNCH_PASS ordinaryFirstVisible=true subsequentVisible=true explicitHidePersisted=true explicitShowPersisted=true isolatedData=true")
        print("STATUS_MENU_PASS opened=\(opened) panelContextExpansions=\(seeds.count) cancelled=\(cancelled) explicitShow=\(shown) explicitHide=\(hidden) selectedEditPreserved=true paused=true foregroundPreserved=true")
    }
    @MainActor static func main() async {
        do { try await run() } catch { print("STATUS_MENU_FAILED", error); exit(1) }
    }
}
