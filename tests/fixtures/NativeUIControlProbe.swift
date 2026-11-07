import AppKit
import ApplicationServices

// Only a supplied synthetic --ui-review PID is inspected. Never select the
// frontmost app, activate a window, post input events, or request permission.
@main struct NativeUIControlProbe {
    @MainActor static func main() async {
        NSApplication.shared.setActivationPolicy(.prohibited)
        guard CommandLine.arguments.count >= 3, let pid = Int32(CommandLine.arguments[1]),
              NSRunningApplication(processIdentifier: pid) != nil else {
            print("USAGE fixturePID label [windowTitle] [set-value value | select-menu item]"); exit(64)
        }
        guard AXIsProcessTrusted() else { print("NOT_RUN accessibility permission unavailable; no prompt"); exit(5) }
        let before = NSWorkspace.shared.frontmostApplication?.processIdentifier
        guard before != pid else { print("REFUSED fixture is frontmost"); exit(6) }
        let label = CommandLine.arguments[2], title = CommandLine.arguments.count > 3 ? CommandLine.arguments[3] : nil
        let setValue = CommandLine.arguments.count == 6 && CommandLine.arguments[4] == "set-value" ? CommandLine.arguments[5] : nil
        let menuItem = CommandLine.arguments.count == 6 && CommandLine.arguments[4] == "select-menu" ? CommandLine.arguments[5] : nil
        let inspect = CommandLine.arguments.count == 5 && CommandLine.arguments[4] == "inspect"
        let inspectPanel = CommandLine.arguments.count == 5 && CommandLine.arguments[4] == "inspect-panel"
        guard CommandLine.arguments.count <= 4 || setValue != nil || menuItem != nil || inspect || inspectPanel else { print("FAIL invalid control action"); exit(64) }
        let root = AXUIElementCreateApplication(pid)
        func value(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
            AXUIElementSetMessagingTimeout(element, 0.08)
            var result: CFTypeRef?
            return AXUIElementCopyAttributeValue(element, name as CFString, &result) == .success ? result : nil
        }
        var lastTree = [String]()
        for _ in 0..<10 {
            let windows = (value(root, kAXWindowsAttribute) as? [AXUIElement] ?? []).filter {
                title == nil || value($0, kAXTitleAttribute) as? String == title
            }
            var queue = windows, visited = Set<CFHashCode>(), tree = [String]()
            var inspectedControls = [[String: Any]]()
            var panelControls = [[String: Any]](), staticStateText = [String](), obsoleteStateIDs = [String]()
            let stateText = Set(["未开启", "待命", "待命中", "聆听中", "正在识别", "正在接收讲话", "正在核对文字", "正在修正", "已暂停", "正在准备", "需要恢复"])
            let captureActions = Set(["开始收音", "暂停收音", "继续收音", "取消开启", "恢复收音"])
            let deadline = ProcessInfo.processInfo.systemUptime + 1
            while !queue.isEmpty, visited.count < 1000, ProcessInfo.processInfo.systemUptime < deadline {
                let node = queue.removeFirst(); guard visited.insert(CFHash(node)).inserted else { continue }
                let role = value(node, kAXRoleAttribute) as? String ?? "unknown"
                let names = [kAXTitleAttribute, kAXDescriptionAttribute, kAXHelpAttribute, kAXIdentifierAttribute].compactMap { value(node, $0) as? String }
                tree.append(role + " " + names.joined(separator: " | "))
                let canPress = [kAXButtonRole, kAXCheckBoxRole, kAXRadioButtonRole, kAXDisclosureTriangleRole, kAXMenuButtonRole, kAXPopUpButtonRole].contains(role)
                let canSet = [kAXTextFieldRole, kAXTextAreaRole].contains(role)
                if inspectPanel {
                    let identifier = value(node, kAXIdentifierAttribute) as? String ?? ""
                    let content = value(node, kAXValueAttribute) as? String ?? ""
                    if role == kAXStaticTextRole, (names + [content]).contains(where: { stateText.contains($0) }) {
                        staticStateText.append(contentsOf: (names + [content]).filter { stateText.contains($0) })
                    }
                    if ["panel.status", "panel.activity"].contains(identifier) { obsoleteStateIDs.append(identifier) }
                    if canPress, identifier.hasPrefix("panel.") || names.contains(where: { captureActions.contains($0) }) {
                        guard let sizeValue = value(node, kAXSizeAttribute), CFGetTypeID(sizeValue) == AXValueGetTypeID(),
                              let pointValue = value(node, kAXPositionAttribute), CFGetTypeID(pointValue) == AXValueGetTypeID() else {
                            print("FAIL native panel control geometry unavailable"); exit(1)
                        }
                        var size = CGSize.zero, point = CGPoint.zero
                        guard AXValueGetValue(unsafeDowncast(sizeValue, to: AXValue.self), .cgSize, &size),
                              AXValueGetValue(unsafeDowncast(pointValue, to: AXValue.self), .cgPoint, &point) else {
                            print("FAIL native panel control geometry invalid"); exit(1)
                        }
                        panelControls.append(["identifier": identifier, "role": role, "width": size.width,
                            "height": size.height, "x": point.x, "y": point.y, "names": names, "value": content,
                            "capture_action": names.contains(where: { captureActions.contains($0) }),
                            "enabled": (value(node, kAXEnabledAttribute) as? Bool) ?? false])
                    }
                    queue += value(node, kAXChildrenAttribute) as? [AXUIElement] ?? []
                    continue
                }
                if names.contains(label), setValue == nil ? canPress : canSet {
                    guard NSWorkspace.shared.frontmostApplication?.processIdentifier == before else { print("REFUSED foreground changed before action"); exit(6) }
                    if inspect {
                        guard let sizeValue = value(node, kAXSizeAttribute), CFGetTypeID(sizeValue) == AXValueGetTypeID() else {
                            print("FAIL native control size unavailable"); exit(1)
                        }
                        var size = CGSize.zero
                        guard AXValueGetValue(unsafeDowncast(sizeValue, to: AXValue.self), .cgSize, &size) else { print("FAIL invalid native control size"); exit(1) }
                        let detail: [String: Any] = ["identifier": label, "role": role, "width": size.width, "height": size.height, "names": names]
                        inspectedControls.append(detail)
                        queue += value(node, kAXChildrenAttribute) as? [AXUIElement] ?? []
                        continue
                    }
                    // SwiftUI may commit state and lay out a form before returning
                    // AXPress; the short traversal timeout is not an action deadline.
                    AXUIElementSetMessagingTimeout(node, 1.0)
                    if let menuItem {
                        // Native menu tracking can keep the opening AX action busy
                        // until selection. A second owned connection inspects only
                        // this fixture process while that action is outstanding.
                        let target = OwnedAXElement(node)
                        let opening = Task.detached {
                            AXUIElementSetMessagingTimeout(target.value, 5.0)
                            return AXUIElementPerformAction(target.value, kAXPressAction as CFString).rawValue
                        }
                        var selected = false
                        for _ in 0..<30 {
                            var pending = (value(root, kAXChildrenAttribute) as? [AXUIElement] ?? []) + [node]
                            var inspected = Set<CFHashCode>()
                            while !pending.isEmpty, inspected.count < 1500 {
                                let element = pending.removeFirst()
                                guard inspected.insert(CFHash(element)).inserted else { continue }
                                let itemRole = value(element, kAXRoleAttribute) as? String ?? ""
                                let itemNames = [kAXTitleAttribute, kAXDescriptionAttribute, kAXIdentifierAttribute].compactMap { value(element, $0) as? String }
                                if itemRole == kAXMenuItemRole, itemNames.contains(menuItem) {
                                    guard NSWorkspace.shared.frontmostApplication?.processIdentifier == before else { print("REFUSED foreground changed before menu selection"); exit(6) }
                                    AXUIElementSetMessagingTimeout(element, 1.0)
                                    let selectedResult = AXUIElementPerformAction(element, kAXPressAction as CFString)
                                    guard selectedResult == .success else { print("FAIL menu selection error \(selectedResult.rawValue)"); exit(1) }
                                    selected = true; break
                                }
                                pending += value(element, kAXChildrenAttribute) as? [AXUIElement] ?? []
                            }
                            if selected { break }
                            try? await Task.sleep(for: .milliseconds(50))
                        }
                        let opened = await opening.value
                        guard selected, opened == AXError.success.rawValue else {
                            // Cancel only the menu owned by the selected fixture;
                            // never synthesize Escape or touch another application.
                            _ = AXUIElementPerformAction(node, kAXCancelAction as CFString)
                            print("FAIL native menu item unavailable: \(menuItem), open=\(opened)"); exit(1)
                        }
                        guard NSWorkspace.shared.frontmostApplication?.processIdentifier == before else { print("FAIL menu changed foreground"); exit(6) }
                        print("NATIVE_UI_MENU_SELECT \(menuItem) menu=\(label) fixture_pid=\(pid) foreground_unchanged=true"); exit(0)
                    }
                    let result: AXError
                    if let setValue {
                        result = AXUIElementSetAttributeValue(node, kAXValueAttribute as CFString, setValue as CFString)
                        if result == .success {
                            var actions: CFArray?
                            if AXUIElementCopyActionNames(node, &actions) == .success,
                               (actions as? [String] ?? []).contains(kAXConfirmAction) {
                                let confirmed = AXUIElementPerformAction(node, kAXConfirmAction as CFString)
                                guard confirmed == .success else { print("FAIL native text commit error \(confirmed.rawValue)"); exit(1) }
                            }
                        }
                    }
                    else { result = AXUIElementPerformAction(node, kAXPressAction as CFString) }
                    guard result == .success else { print("FAIL native control action error \(result.rawValue)"); exit(1) }
                    guard NSWorkspace.shared.frontmostApplication?.processIdentifier == before else { print("FAIL AXPress changed foreground"); exit(6) }
                    print("NATIVE_UI_\(setValue == nil ? "AXPRESS" : "AXSETVALUE") \(label) fixture_pid=\(pid) foreground_unchanged=true"); exit(0)
                }
                queue += value(node, kAXChildrenAttribute) as? [AXUIElement] ?? []
            }
            if inspectPanel {
                guard windows.count == 1, queue.isEmpty, !panelControls.isEmpty else { print("FAIL incomplete native panel inspection"); exit(1) }
                guard NSWorkspace.shared.frontmostApplication?.processIdentifier == before else { print("REFUSED foreground changed during inspection"); exit(6) }
                let detail: [String: Any] = ["controls": panelControls, "static_state_text": staticStateText,
                    "obsolete_state_identifiers": obsoleteStateIDs, "visited_nodes": visited.count]
                let data = try! JSONSerialization.data(withJSONObject: detail, options: [.sortedKeys])
                print("NATIVE_UI_PANEL_INSPECT " + String(decoding: data, as: UTF8.self)); exit(0)
            }
            if inspect, !inspectedControls.isEmpty {
                guard queue.isEmpty, inspectedControls.count == 1 else { print("FAIL incomplete or duplicate native control \(label)"); exit(1) }
                let data = try! JSONSerialization.data(withJSONObject: inspectedControls[0], options: [.sortedKeys])
                print("NATIVE_UI_INSPECT " + String(decoding: data, as: UTF8.self)); exit(0)
            }
            lastTree = tree
            try? await Task.sleep(for: .milliseconds(100))
        }
        print("FAIL accessible fixture control not found: \(label); \(lastTree.count) nodes")
        for node in lastTree { print(node) }
        exit(1)
    }
}

private final class OwnedAXElement: @unchecked Sendable {
    let value: AXUIElement
    init(_ value: AXUIElement) { self.value = value }
}
