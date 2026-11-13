import AppKit
import ApplicationServices

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
            [kAXTitleAttribute, kAXDescriptionAttribute].contains { (attr(node, $0) as? String)?.hasPrefix("Saytile · 暂停") == true }
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
        guard CommandLine.arguments.count == 3, AXIsProcessTrusted() else { throw Failure("expected isolated app, new directory and existing AX permission") }
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
        defer { if !app.isTerminated { app.terminate() } }
        var pid = app.processIdentifier, root = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(root, 0.4)
        func stop() async throws {
            guard app.terminate() else { throw Failure("fixture could not close cleanly") }
            try await wait("fixture did not terminate") { app.isTerminated }
        }
        func coldLaunch() async throws {
            try await stop()
            config.arguments = ["-shortcutChoice", "disabled", "-floatingEntryEnabled", "NO"]
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
        func round(_ command: String?, visible: Bool, expected: String) async throws {
            guard let button = status(pid) else { throw Failure("paused status unavailable") }
            let owner = Owned(element: button)
            async let open: Int32 = Task.detached {
                AXUIElementSetMessagingTimeout(owner.element, 8)
                return AXUIElementPerformAction(owner.element, kAXPressAction as CFString).rawValue
            }.value
            func openWindowExists() -> Bool {
                let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
                return windows.contains { item in
                    (item[kCGWindowOwnerPID as String] as? Int32) == pid &&
                        (item[kCGWindowLayer as String] as? Int ?? 0) >= CGWindowLevelForKey(.mainMenuWindow) &&
                        (item[kCGWindowBounds as String] as? [String: CGFloat])?["Height"] ?? 0 > 55
                }
            }
            var menu: AXUIElement?
            try await wait("single status press failed to open menu on screen") {
                guard openWindowExists() else { return false }
                menu = find([button] + children(root, pid: pid), pid: pid) { attr($0, kAXRoleAttribute) as? String == kAXMenuRole }
                return menu != nil
            }
            guard let menu else { throw Failure("missing owned menu") }
            var dismissed = false
            defer { if !dismissed { _ = AXUIElementPerformAction(menu, kAXCancelAction as CFString) } }
            let items = children(menu, pid: pid)
            let titles = items.compactMap { attr($0, kAXTitleAttribute) as? String }
            let destinations: Set<String> = [expected, "语音档案与设置…", "退出 Saytile"]
            let menuTitles = Set(titles.filter { !$0.isEmpty })
            guard destinations.isSubset(of: menuTitles),
                  menuTitles.isSubset(of: destinations.union(["检查更新…"])),
                  (panel() != nil) == visible else {
                throw Failure("menu incomplete or opening toggled the panel: " + titles.joined(separator: " / "))
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
            try await wait("menu still on screen") { !openWindowExists() }
            dismissed = true
            print("STATUS_NATIVE_ROUND command=\(command ?? "cancel") visibleWhileOpen=\(visible) fullMenu=true captureCommands=0")
        }
        try await wait("fixture did not launch paused") { status(pid) != nil }
        try await round(nil, visible: false, expected: "显示语音板")
        guard panel() == nil, status(pid) != nil else { throw Failure("opening menu changed capture or visibility") }
        try await round("显示语音板", visible: false, expected: "显示语音板")
        try await wait("panel was not shown") { editor() != nil }
        let sample = "菜单打开前的隔离编辑"
        guard let text = editor(), AXUIElementSetAttributeValue(text, kAXValueAttribute as CFString, sample as CFString) == .success else { throw Failure("fixture editing unavailable") }
        var range = CFRange(location: 1, length: 3)
        guard let value = AXValueCreate(.cfRange, &range),
              AXUIElementSetAttributeValue(text, kAXSelectedTextRangeAttribute as CFString, value) == .success else { throw Failure("fixture selection unavailable") }
        try await round(nil, visible: true, expected: "收起语音板")
        var actual = CFRange()
        guard let text = editor(), attr(text, kAXValueAttribute) as? String == sample,
              let selected = attr(text, kAXSelectedTextRangeAttribute), CFGetTypeID(selected) == AXValueGetTypeID(),
              AXValueGetValue(unsafeDowncast(selected, to: AXValue.self), .cfRange, &actual),
              actual.location == range.location && actual.length == range.length else { throw Failure("open/cancel disturbed edit or selection") }
        try await round("收起语音板", visible: true, expected: "收起语音板")
        try await wait("explicit hide did not close panel") { panel() == nil }
        try await round(nil, visible: false, expected: "显示语音板")
        guard status(pid) != nil, initialFront == NSWorkspace.shared.frontmostApplication?.processIdentifier else { throw Failure("capture or foreground changed") }
        try await coldLaunch()
        try await wait("ordinary first launch must show the board") { panel() != nil }
        let ordinaryDatabase = syntheticHome.appending(path: "Library/Application Support/Saytile/Saytile.sqlite")
        guard FileManager.default.fileExists(atPath: ordinaryDatabase.path) else { throw Failure("ordinary fixture database outside synthetic home") }
        try await coldLaunch()
        try await wait("visible board disappeared on a normal relaunch") { panel() != nil }
        try await round("收起语音板", visible: true, expected: "收起语音板")
        try await wait("explicit ordinary hide") { panel() == nil }
        try await coldLaunch()
        try await round("显示语音板", visible: false, expected: "显示语音板")
        try await wait("explicit ordinary show") { panel() != nil }
        try await coldLaunch()
        try await wait("explicit show was not remembered") { panel() != nil }
        try await stop()
        print("STATUS_MENU_RELAUNCH_PASS ordinaryFirstVisible=true subsequentVisible=true explicitHidePersisted=true explicitShowPersisted=true isolatedData=true")
        print("STATUS_MENU_PASS opened=7 cancelled=3 explicitShow=2 explicitHide=2 selectedEditPreserved=true paused=true foregroundPreserved=true")
    }
    @MainActor static func main() async {
        do { try await run() } catch { print("STATUS_MENU_FAILED", error); exit(1) }
    }
}
