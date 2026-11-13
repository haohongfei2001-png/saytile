import AppKit
import ApplicationServices

// Only a supplied synthetic --ui-review PID is inspected. Never select the
// frontmost app, activate a window, post input events, or request permission.
@main struct NativeUIControlProbe {
    @MainActor static func main() async {
        NSApplication.shared.setActivationPolicy(.prohibited)
        guard CommandLine.arguments.count >= 3, let pid = Int32(CommandLine.arguments[1]),
              NSRunningApplication(processIdentifier: pid) != nil else {
            print("USAGE fixturePID label [windowTitle] [set-value value | select-context-menu id title]"); exit(64)
        }
        guard AXIsProcessTrusted() else { print("NOT_RUN accessibility permission unavailable; no prompt"); exit(5) }
        let before = NSWorkspace.shared.frontmostApplication?.processIdentifier
        guard before != pid else { print("REFUSED fixture is frontmost"); exit(6) }
        let label = CommandLine.arguments[2], title = CommandLine.arguments.count > 3 ? CommandLine.arguments[3] : nil
        let setValue = CommandLine.arguments.count == 6 && CommandLine.arguments[4] == "set-value" ? CommandLine.arguments[5] : nil
        let paragraph = CommandLine.arguments.count == 6 && CommandLine.arguments[4] == "read-paragraph" ? CommandLine.arguments[5] : nil
        let menuItem = CommandLine.arguments.count == 7 && CommandLine.arguments[4] == "select-context-menu" ? CommandLine.arguments[5] : nil
        let menuTitle = menuItem == nil ? nil : CommandLine.arguments[6]
        let inspect = CommandLine.arguments.count == 5 && CommandLine.arguments[4] == "inspect"
        let inspectPanel = CommandLine.arguments.count == 5 && CommandLine.arguments[4] == "inspect-panel"
        let inspectSettings = CommandLine.arguments.count == 5 && CommandLine.arguments[4] == "inspect-settings"
        guard CommandLine.arguments.count <= 4 || setValue != nil || menuItem != nil || inspect || inspectPanel || inspectSettings || paragraph != nil else { print("FAIL invalid control action"); exit(64) }
        let root = AXUIElementCreateApplication(pid)
        func value(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
            AXUIElementSetMessagingTimeout(element, name == kAXWindowsAttribute || name == kAXTitleAttribute ? 0.7 : 0.2)
            var result: CFTypeRef?
            return AXUIElementCopyAttributeValue(element, name as CFString, &result) == .success ? result : nil
        }
        func frame(_ node: AXUIElement) -> CGRect? {
            guard let position = value(node, kAXPositionAttribute), CFGetTypeID(position) == AXValueGetTypeID(),
                  let dimensions = value(node, kAXSizeAttribute), CFGetTypeID(dimensions) == AXValueGetTypeID() else { return nil }
            var point = CGPoint.zero, size = CGSize.zero
            guard AXValueGetValue(unsafeDowncast(position, to: AXValue.self), .cgPoint, &point),
                  AXValueGetValue(unsafeDowncast(dimensions, to: AXValue.self), .cgSize, &size) else { return nil }
            return CGRect(origin: point, size: size)
        }
        func availableActions(_ node: AXUIElement) -> [String] {
            var actions: CFArray?
            guard AXUIElementCopyActionNames(node, &actions) == .success else { return [] }
            return actions as? [String] ?? []
        }
        func ancestorRoles(_ node: AXUIElement) -> [String] {
            var current = node, roles: [String] = [], visited = Set<CFHashCode>()
            while visited.insert(CFHash(current)).inserted, roles.count < 20,
                  let reference = value(current, kAXParentAttribute), CFGetTypeID(reference) == AXUIElementGetTypeID() {
                let parent = unsafeDowncast(reference, to: AXUIElement.self)
                var owner: pid_t = 0
                guard AXUIElementGetPid(parent, &owner) == .success, owner == pid,
                      let role = value(parent, kAXRoleAttribute) as? String else { break }
                roles.append(role); current = parent
                if role == kAXWindowRole || role == kAXApplicationRole { break }
            }
            return roles
        }
        func isPanelMenuID(_ id: String) -> Bool {
            id.hasPrefix("panel.menu.") || id.hasPrefix("panel.more.") || ["panel.edit", "panel.latest"].contains(id)
        }
        let nodeAttributes = [kAXRoleAttribute, kAXTitleAttribute, kAXDescriptionAttribute,
            kAXHelpAttribute, kAXIdentifierAttribute, kAXChildrenAttribute] as CFArray
        func inspectNode(_ node: AXUIElement) -> (role: String, names: [String], children: [AXUIElement])? {
            // A form can re-layout between separate AX IPCs. Get structure and
            // identity in one observation of this owned node, without field values.
            AXUIElementSetMessagingTimeout(node, 0.5)
            var result: CFArray?
            guard AXUIElementCopyMultipleAttributeValues(node, nodeAttributes, [], &result) == .success,
                  let properties = result as? [Any], properties.count == 6 else { return nil }
            return (properties[0] as? String ?? "unknown", properties[1...4].compactMap { $0 as? String },
                    properties[5] as? [AXUIElement] ?? [])
        }
        var lastTree = [String]()
        for _ in 0..<10 {
            let windows = (value(root, kAXWindowsAttribute) as? [AXUIElement] ?? []).filter {
                title == nil || value($0, kAXTitleAttribute) as? String == title
            }
            var incomplete = false
            var queue = windows, visited = Set<CFHashCode>(), tree = [String]()
            var inspectedControls = [[String: Any]]()
            var panelControls = [[String: Any]](), scrollbarParts = [[String: Any]](), transcriptAreas = [[String: Any]](), staticStateText = [String](), obsoleteStateIDs = [String]()
            var settingsNames = Set<String>()
            let captureActions = Set(["开始收音", "暂停收音", "继续收音", "取消开启", "恢复收音"])
            let deadline = ProcessInfo.processInfo.systemUptime + 1
            while !queue.isEmpty, visited.count < 1000, ProcessInfo.processInfo.systemUptime < deadline {
                let node = queue.removeFirst(); guard visited.insert(CFHash(node)).inserted else { continue }
                guard let observed = inspectNode(node) else { incomplete = true; continue }
                let role = observed.role, names = observed.names
                tree.append(role + " " + names.joined(separator: " | "))
                let canPress = [kAXButtonRole, kAXCheckBoxRole, kAXRadioButtonRole, kAXDisclosureTriangleRole, kAXMenuButtonRole, kAXPopUpButtonRole].contains(role)
                let canSet = [kAXTextFieldRole, kAXTextAreaRole].contains(role)
                if inspectSettings {
                    settingsNames.formUnion(names)
                    if role == kAXStaticTextRole, let text = value(node, kAXValueAttribute) as? String {
                        settingsNames.insert(text)
                    }
                    queue += observed.children
                    continue
                }
                if inspectPanel {
                    let identifier = value(node, kAXIdentifierAttribute) as? String ?? ""
                    let content = value(node, kAXValueAttribute) as? String ?? ""
                    // The fixture window title is native AppKit chrome. All other
                    // visible text belongs exclusively to the editable transcript.
                    if role == kAXStaticTextRole, let title, !names.contains(title), content != title {
                        staticStateText += (names + [content]).filter { !$0.isEmpty }
                    }
                    if ["panel.status", "panel.activity", "panel.more", "panel.edit", "panel.latest", "panel.placeholder", "panel.notice", "panel.target"].contains(identifier) {
                        obsoleteStateIDs.append(identifier)
                    }
                    // Include unnamed or accidentally added controls. Window chrome
                    // has its own system subroles and is outside the panel content.
                    let chrome = ["AXCloseButton", "AXMinimizeButton", "AXZoomButton", "AXFullScreenButton"]
                    let subrole = value(node, kAXSubroleAttribute) as? String ?? ""
                    let isTranscript = role == kAXTextAreaRole && identifier == "panel.transcript" && ancestorRoles(node).first == kAXScrollAreaRole
                    if !chrome.contains(subrole), canPress || isTranscript || availableActions(node).contains(kAXPressAction) {
                        guard let bounds = frame(node) else { print("FAIL native panel control geometry unavailable"); exit(1) }
                        let ancestors = ancestorRoles(node)
                        let detail: [String: Any] = ["identifier": identifier, "role": role, "subrole": subrole,
                            "ancestor_roles": ancestors, "width": bounds.width, "height": bounds.height,
                            "x": bounds.minX, "y": bounds.minY, "names": names, "value": content,
                            "capture_action": names.contains(where: { captureActions.contains($0) }),
                            "enabled": (value(node, kAXEnabledAttribute) as? Bool) ?? false]
                        // AppKit exposes its scroll bar's arrows/pages as AXButtons.
                        // Their verified parentage, never size, name or enabled state,
                        // separates native scrolling from permanent panel actions.
                        if ancestors.contains(kAXScrollBarRole) { scrollbarParts.append(detail) }
                        // Some macOS versions also expose AXPress on the editable
                        // text area. Keep that single document independently accounted
                        // for; all other pressable elements still count as panel actions.
                        else if isTranscript { transcriptAreas.append(detail) }
                        else { panelControls.append(detail) }
                    }
                    queue += observed.children
                    continue
                }
                if let paragraph, names.contains(label), label.hasPrefix("archive.text.") {
                    let text = value(node, kAXValueAttribute) as? String
                    guard (names.contains(paragraph) || text == paragraph),
                          let geometry = frame(node), geometry.height > 70,
                          NSWorkspace.shared.frontmostApplication?.processIdentifier == before else {
                        print("FAIL five-line archive paragraph was missing or clipped"); exit(1)
                    }
                    print("NATIVE_ARCHIVE_PARAGRAPH full_text=true height=\(geometry.height)"); exit(0)
                }
                if paragraph != nil { queue += observed.children; continue }
                let applicable = menuItem != nil ? (role == kAXTextAreaRole || canPress) : (setValue == nil ? canPress : canSet)
                if names.contains(label), applicable {
                    guard NSWorkspace.shared.frontmostApplication?.processIdentifier == before else { print("REFUSED foreground changed before action"); exit(6) }
                    if inspect {
                        guard let sizeValue = value(node, kAXSizeAttribute), CFGetTypeID(sizeValue) == AXValueGetTypeID() else {
                            print("FAIL native control size unavailable"); exit(1)
                        }
                        var size = CGSize.zero
                        guard AXValueGetValue(unsafeDowncast(sizeValue, to: AXValue.self), .cgSize, &size) else { print("FAIL invalid native control size"); exit(1) }
                        let detail: [String: Any] = ["identifier": label, "role": role, "width": size.width, "height": size.height, "names": names]
                        inspectedControls.append(detail)
                        queue += observed.children
                        continue
                    }
                    // SwiftUI may commit state and lay out a form before returning
                    // AXPress; the short traversal timeout is not an action deadline.
                    AXUIElementSetMessagingTimeout(node, 1.0)
                    if let menuItem {
                        // Native menu tracking can keep the opening AX action busy
                        // until selection. A second owned connection inspects only
                        // this fixture process while that action is outstanding.
                        guard availableActions(node).contains(kAXShowMenuAction) else {
                            print("FAIL owned transcript does not advertise AXShowMenu"); exit(1)
                        }
                        let target = OwnedAXElement(node)
                        let opening = Task.detached {
                            AXUIElementSetMessagingTimeout(target.value, 5.0)
                            return AXUIElementPerformAction(target.value, kAXShowMenuAction as CFString).rawValue
                        }
                        var selected = false
                        var ownedMenu: AXUIElement?
                        var projectItemIDs = Set<String>()
                        for _ in 0..<30 {
                            var pending = (value(root, kAXChildrenAttribute) as? [AXUIElement] ?? []) + [node]
                            var inspected = Set<CFHashCode>()
                            var match: AXUIElement?
                            while !pending.isEmpty, inspected.count < 1500 {
                                let element = pending.removeFirst()
                                guard inspected.insert(CFHash(element)).inserted else { continue }
                                var itemOwner: pid_t = 0
                                guard AXUIElementGetPid(element, &itemOwner) == .success, itemOwner == pid else { continue }
                                let itemRole = value(element, kAXRoleAttribute) as? String ?? ""
                                if itemRole == kAXMenuRole { ownedMenu = element }
                                if itemRole == kAXMenuItemRole,
                                   let id = value(element, kAXIdentifierAttribute) as? String, isPanelMenuID(id) {
                                    // Ignore unrelated system services before reading
                                    // their titles. Evidence contains only project IDs.
                                    projectItemIDs.insert(id)
                                    if id == menuItem, value(element, kAXTitleAttribute) as? String == menuTitle {
                                        match = element
                                    }
                                }
                                pending += value(element, kAXChildrenAttribute) as? [AXUIElement] ?? []
                            }
                            if let match {
                                var owner: pid_t = 0
                                guard AXUIElementGetPid(match, &owner) == .success, owner == pid,
                                      NSWorkspace.shared.frontmostApplication?.processIdentifier == before else { print("REFUSED unexpected menu owner or foreground"); exit(6) }
                                AXUIElementSetMessagingTimeout(match, 1.0)
                                let selectedResult = AXUIElementPerformAction(match, kAXPressAction as CFString)
                                guard selectedResult == .success else { print("FAIL menu selection error \(selectedResult.rawValue)"); exit(1) }
                                selected = true; break
                            }
                            try? await Task.sleep(for: .milliseconds(50))
                        }
                        if !selected, let ownedMenu { _ = AXUIElementPerformAction(ownedMenu, kAXCancelAction as CFString) }
                        let opened = await opening.value
                        guard selected, opened == AXError.success.rawValue else {
                            print("FAIL exact project menu ID/title unavailable: \(menuItem), open=\(opened), project_ids=\(projectItemIDs.sorted())"); exit(1)
                        }
                        let menuData = try! JSONSerialization.data(withJSONObject: projectItemIDs.sorted())
                        print("NATIVE_UI_CONTEXT_ITEMS " + String(decoding: menuData, as: UTF8.self))
                        guard NSWorkspace.shared.frontmostApplication?.processIdentifier == before else { print("FAIL menu changed foreground"); exit(6) }
                        print("NATIVE_UI_MENU_SELECT \(menuItem) via=AXShowMenu menu=\(label) fixture_pid=\(pid) foreground_unchanged=true"); exit(0)
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
                queue += observed.children
            }
            if (inspectPanel || inspect || inspectSettings) && incomplete { continue }
            if inspectSettings {
                guard windows.count == 1, queue.isEmpty, !settingsNames.isEmpty,
                      NSWorkspace.shared.frontmostApplication?.processIdentifier == before else { continue }
                let data = try! JSONSerialization.data(withJSONObject: settingsNames.sorted())
                print("NATIVE_UI_SETTINGS_INSPECT " + String(decoding: data, as: UTF8.self)); exit(0)
            }
            if inspectPanel {
                guard windows.count == 1, queue.isEmpty, !panelControls.isEmpty else { print("FAIL incomplete native panel inspection"); exit(1) }
                guard NSWorkspace.shared.frontmostApplication?.processIdentifier == before else { print("REFUSED foreground changed during inspection"); exit(6) }
                guard let bounds = frame(windows[0]) else { print("FAIL native panel window geometry unavailable"); exit(1) }
                guard transcriptAreas.count == 1 else { print("FAIL expected one native panel.transcript AXTextArea in the document scroll area, found \(transcriptAreas.count)"); exit(1) }
                let detail: [String: Any] = ["controls": panelControls, "transcript_areas": transcriptAreas, "native_scrollbar_parts": scrollbarParts, "window_x": bounds.minX, "window_y": bounds.minY,
                    "window_width": bounds.width, "window_height": bounds.height, "static_state_text": staticStateText,
                    "obsolete_state_identifiers": obsoleteStateIDs, "visited_nodes": visited.count]
                let data = try! JSONSerialization.data(withJSONObject: detail, options: [.sortedKeys])
                print("NATIVE_UI_PANEL_INSPECT " + String(decoding: data, as: UTF8.self)); exit(0)
            }
            if inspect, !inspectedControls.isEmpty {
                guard queue.isEmpty, inspectedControls.count == 1 else { print("FAIL incomplete or duplicate native control \(label)"); exit(1) }
                let data = try! JSONSerialization.data(withJSONObject: inspectedControls[0], options: [.sortedKeys])
                print("NATIVE_UI_INSPECT " + String(decoding: data, as: UTF8.self)); exit(0)
            }
            if tree.count > lastTree.count { lastTree = tree }
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
