import AppKit
import ApplicationServices

// Only a supplied synthetic --ui-review PID is inspected. Never select the
// frontmost app, activate a window, post input events, or request permission.
@main struct NativeUIControlProbe {
    @MainActor static func main() async {
        NSApplication.shared.setActivationPolicy(.prohibited)
        guard CommandLine.arguments.count >= 3, let pid = Int32(CommandLine.arguments[1]),
              NSRunningApplication(processIdentifier: pid) != nil else {
            print("USAGE fixturePID label [windowTitle] [set-value value]"); exit(64)
        }
        guard AXIsProcessTrusted() else { print("NOT_RUN accessibility permission unavailable; no prompt"); exit(5) }
        let before = NSWorkspace.shared.frontmostApplication?.processIdentifier
        guard before != pid else { print("REFUSED fixture is frontmost"); exit(6) }
        let label = CommandLine.arguments[2], title = CommandLine.arguments.count > 3 ? CommandLine.arguments[3] : nil
        let setValue = CommandLine.arguments.count == 6 && CommandLine.arguments[4] == "set-value" ? CommandLine.arguments[5] : nil
        guard CommandLine.arguments.count <= 4 || setValue != nil else { print("FAIL invalid control action"); exit(64) }
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
            let deadline = ProcessInfo.processInfo.systemUptime + 1
            while !queue.isEmpty, visited.count < 1000, ProcessInfo.processInfo.systemUptime < deadline {
                let node = queue.removeFirst(); guard visited.insert(CFHash(node)).inserted else { continue }
                let role = value(node, kAXRoleAttribute) as? String ?? "unknown"
                let names = [kAXTitleAttribute, kAXDescriptionAttribute, kAXHelpAttribute, kAXIdentifierAttribute].compactMap { value(node, $0) as? String }
                tree.append(role + " " + names.joined(separator: " | "))
                let canPress = [kAXButtonRole, kAXCheckBoxRole, kAXRadioButtonRole, kAXDisclosureTriangleRole].contains(role)
                let canSet = [kAXTextFieldRole, kAXTextAreaRole].contains(role)
                if names.contains(label), setValue == nil ? canPress : canSet {
                    guard NSWorkspace.shared.frontmostApplication?.processIdentifier == before else { print("REFUSED foreground changed before action"); exit(6) }
                    // SwiftUI may commit state and lay out a form before returning
                    // AXPress; the short traversal timeout is not an action deadline.
                    AXUIElementSetMessagingTimeout(node, 1.0)
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
            lastTree = tree
            try? await Task.sleep(for: .milliseconds(100))
        }
        print("FAIL accessible fixture control not found: \(label); \(lastTree.count) nodes")
        for node in lastTree { print(node) }
        exit(1)
    }
}
