import AppKit
import ApplicationServices

/// Narrow AX adapter: never reads or replaces the entire target value, never activates an app,
/// and never generates Return. Page identifiers stay in memory and are not sent to storage.
@MainActor
final class AXInputAccess: InputAccess {
    var hasPermission: Bool { AXIsProcessTrusted() }
    private var rememberedElement: AXUIElement?
    private var rememberedWindow: AXUIElement?
    private var elementID = UUID()
    private var windowID = UUID()
    private var currentElement: AXUIElement?

    func snapshot() throws -> InputTargetSnapshot {
        guard hasPermission else { throw NativeInputError.permission }
        guard let app = NSWorkspace.shared.frontmostApplication,
              app.processIdentifier != ProcessInfo.processInfo.processIdentifier else { throw NativeInputError.noTarget }
        let root = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetMessagingTimeout(root, 0.12)
        guard let element = elementValue(root, kAXFocusedUIElementAttribute),
              let window = elementValue(root, kAXFocusedWindowAttribute),
              let range = selectedRange(element) else { throw NativeInputError.unsupported }
        // Verify the element belongs to the focused window, when the application exposes it.
        if let owningWindow = elementValue(element, kAXWindowAttribute), !CFEqual(owningWindow, window) {
            throw NativeInputError.targetChanged
        }
        let bundle = app.bundleIdentifier ?? ""
        let role = string(element, kAXRoleAttribute) ?? ""
        let subrole = string(element, kAXSubroleAttribute) ?? ""
        let description = string(element, kAXRoleDescriptionAttribute) ?? ""
        let identifier = string(element, kAXIdentifierAttribute) ?? ""
        let sensitive = InputSafetyPolicy.isSensitive(applicationID: bundle, role: role, subrole: subrole,
                                                       description: description, identifier: identifier)
        let editableRoles: Set<String> = [kAXTextFieldRole, kAXTextAreaRole, kAXComboBoxRole]
        let editable = editableRoles.contains(role) && (bool(element, kAXEnabledAttribute) ?? true)
        let (isWeb, page) = pageIdentity(element, window: window, appID: bundle)
        if rememberedElement == nil || !CFEqual(rememberedElement!, element) {
            elementID = UUID(); rememberedElement = element
        }
        if rememberedWindow == nil || !CFEqual(rememberedWindow!, window) {
            windowID = UUID(); rememberedWindow = window
        }
        currentElement = element
        var settable = DarwinBoolean(false)
        AXUIElementIsAttributeSettable(element, kAXSelectedTextAttribute as CFString, &settable)
        return InputTargetSnapshot(processID: app.processIdentifier, applicationID: bundle,
                                   applicationName: app.localizedName ?? "目标应用", windowID: windowID,
                                   elementID: elementID, pageIdentity: page, selectionLocation: range.location,
                                   selectionLength: range.length, isWeb: isWeb, isEditable: editable,
                                   isSensitive: sensitive, canSetSelectedText: settable.boolValue)
    }

    func dispatch(_ text: String, to expected: InputTargetSnapshot) throws -> Bool {
        let current = try snapshot()
        guard current == expected, let element = currentElement else { return false }
        try current.checked()
        if current.canSetSelectedText {
            let result = AXUIElementSetAttributeValue(element, kAXSelectedTextAttribute as CFString, text as CFString)
            guard result == .success else { throw AXDispatchFailure(code: result.rawValue) }
            return true
        }
        // Deliberate clipboard fallback. Do not inspect private clipboard data to preserve it.
        // Do not restore asynchronously: that could overwrite a newer user copy.
        guard let source = CGEventSource(stateID: .privateState),
              let down = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: false) else { return false }
        down.flags = .maskCommand
        up.flags = .maskCommand
        NSPasteboard.general.clearContents()
        guard NSPasteboard.general.setString(text, forType: .string) else { return false }
        // A final focus/page/selection check follows the clipboard mutation.
        guard try snapshot() == expected else { return false }
        // Process-specific events avoid redirecting a paste to an app activated in the dispatch race.
        down.postToPid(expected.processID)
        up.postToPid(expected.processID)
        return true
    }

    func verify(_ text: String, at before: InputTargetSnapshot) -> InputTargetSnapshot? {
        guard let after = try? snapshot(), after.sameTarget(as: before), after.selectionLength == 0,
              after.selectionLocation == before.selectionLocation + text.utf16.count,
              let element = currentElement else { return nil }
        var range = CFRange(location: before.selectionLocation, length: text.utf16.count)
        guard let value = AXValueCreate(.cfRange, &range) else { return nil }
        var output: CFTypeRef?
        guard AXUIElementCopyParameterizedAttributeValue(element, kAXStringForRangeParameterizedAttribute as CFString,
                                                         value, &output) == .success,
              let inserted = output as? String, inserted == text else { return nil }
        return after
    }

    private func pageIdentity(_ element: AXUIElement, window: AXUIElement, appID: String) -> (Bool, String?) {
        var node: AXUIElement? = element
        var isWeb = InputSafetyPolicy.isBrowser(applicationID: appID)
        var url: String?
        var pageTitle: String?
        for _ in 0..<24 {
            guard let current = node else { break }
            if string(current, kAXRoleAttribute) == "AXWebArea" {
                isWeb = true
                url = string(current, kAXURLAttribute) ?? string(current, kAXDocumentAttribute)
                pageTitle = string(current, kAXTitleAttribute)
                break
            }
            if CFEqual(current, window) { break }
            node = elementValue(current, kAXParentAttribute)
        }
        let document = string(window, kAXDocumentAttribute)
        let title = string(window, kAXTitleAttribute) ?? ""
        if isWeb {
            let identity = url ?? document
            guard let identity, !identity.isEmpty else { return (true, nil) }
            // URL plus title catches SPA navigation even when its editable node is reused.
            return (true, identity + "\u{1f}" + (pageTitle ?? title))
        }
        // Native document changes in the same window also expire a binding.
        return (false, (document ?? "") + "\u{1f}" + title)
    }

    private func attribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
        AXUIElementSetMessagingTimeout(element, 0.12)
        var output: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &output) == .success else { return nil }
        return output
    }
    private func string(_ element: AXUIElement, _ name: String) -> String? {
        guard let value = attribute(element, name) else { return nil }
        if let text = value as? String { return text }
        if CFGetTypeID(value) == CFURLGetTypeID(), let url = value as? URL { return url.absoluteString }
        return nil
    }
    private func bool(_ element: AXUIElement, _ name: String) -> Bool? { attribute(element, name) as? Bool }
    private func elementValue(_ element: AXUIElement, _ name: String) -> AXUIElement? {
        guard let value = attribute(element, name), CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return unsafeDowncast(value, to: AXUIElement.self)
    }
    private func selectedRange(_ element: AXUIElement) -> CFRange? {
        guard let value = attribute(element, kAXSelectedTextRangeAttribute), CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        let axValue = unsafeDowncast(value, to: AXValue.self)
        guard AXValueGetType(axValue) == .cfRange else { return nil }
        var range = CFRange()
        guard AXValueGetValue(axValue, .cfRange, &range) else { return nil }
        return range
    }
}

struct AXDispatchFailure: Error { let code: Int32 }

enum InputSafetyPolicy {
    static func isBrowser(applicationID: String) -> Bool {
        let id = applicationID.lowercased()
        return ["safari", "chrome", "chromium", "firefox", "microsoft.edgemac", "brave", "vivaldi", "thebrowser", "opera"].contains { id.contains($0) }
    }
    static func isSensitive(applicationID: String, role: String, subrole: String, description: String, identifier: String) -> Bool {
        let id = applicationID.lowercased()
        let terminals = ["com.apple.terminal", "com.googlecode.iterm2", "dev.warp.warp-stable", "com.mitchellh.ghostty", "org.alacritty", "net.kovidgoyal.kitty", "com.github.wez.wezterm"]
        let semantics = [role, subrole, description, identifier].joined(separator: " ").lowercased()
        return terminals.contains(where: { id.hasPrefix($0) }) ||
            ["secure", "password", "terminal", "密码", "终端"].contains { semantics.contains($0) }
    }
}
