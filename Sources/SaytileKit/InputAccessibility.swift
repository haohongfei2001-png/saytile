import AppKit
import ApplicationServices
import CryptoKit

struct AXInputSelection {
    let application: NSRunningApplication
    let root: AXUIElement
    let window: AXUIElement
    let element: AXUIElement
}

/// The target did not answer the focus request. An explicit "no focus" or a
/// different editor is never represented by this error.
struct AXFocusReadTimeout: Error {}

/// Narrow AX adapter: never replaces the entire target value, never activates an app,
/// and never generates Return. Page identifiers stay in memory and are not sent to storage.
@MainActor
final class AXInputAccess: InputAccess {
    var hasPermission: Bool { permissionCheck() }
    // Optional fixture diagnostics: reason labels only, never text/page contents.
    var onProofUnavailable: (@MainActor (String) -> Void)?
    private func unavailable(_ reason: String) { onProofUnavailable?(reason) }
    private let selectionProvider: @MainActor () throws -> AXInputSelection
    private let permissionCheck: @MainActor () -> Bool
    private var currentSelection: AXInputSelection?
    private var currentWebArea: AXUIElement?
    private var observation: AXTargetObservation?
    init(selectionProvider: @escaping @MainActor () throws -> AXInputSelection = AXInputAccess.frontmostSelection,
         permissionCheck: @escaping @MainActor () -> Bool = { AXIsProcessTrusted() }) {
        self.selectionProvider = selectionProvider; self.permissionCheck = permissionCheck
    }
    // The default production path queries actual WindowServer foreground and AX focus on every use.
    // Tests inject only this target selection boundary; all AX mutation and coordinator logic is shared.
    static func frontmostSelection() throws -> AXInputSelection {
        guard let app = NSWorkspace.shared.frontmostApplication,
              app.processIdentifier != ProcessInfo.processInfo.processIdentifier else { throw NativeInputError.noTarget }
        let root = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetMessagingTimeout(root, 0.12)
        func element(_ name: String) throws -> AXUIElement? {
            var output: CFTypeRef?
            let status = AXUIElementCopyAttributeValue(root, name as CFString, &output)
            if name == kAXFocusedUIElementAttribute && status == .cannotComplete { throw AXFocusReadTimeout() }
            guard status == .success,
                  let output, CFGetTypeID(output) == AXUIElementGetTypeID() else { return nil }
            return unsafeDowncast(output, to: AXUIElement.self)
        }
        guard let focused = try element(kAXFocusedUIElementAttribute),
              let window = try element(kAXFocusedWindowAttribute) else { throw NativeInputError.unsupported }
        return AXInputSelection(application: app, root: root, window: window, element: focused)
    }
    private var rememberedElement: AXUIElement?
    private var rememberedWindow: AXUIElement?
    private var elementID = UUID()
    private var windowID = UUID()
    private var currentElement: AXUIElement?

    func snapshot() throws -> InputTargetSnapshot {
        try snapshot(verifyIssuedWebInsertion: false)
    }

    func snapshotAfterIssuedWebInsertion() throws -> InputTargetSnapshot {
        try snapshot(verifyIssuedWebInsertion: true)
    }

    private func snapshot(verifyIssuedWebInsertion: Bool) throws -> InputTargetSnapshot {
        guard hasPermission else { throw NativeInputError.permission }
        let selection: AXInputSelection
        do { selection = try selectionProvider() }
        catch is AXFocusReadTimeout {
            guard verifyIssuedWebInsertion, let currentSelection, currentWebArea != nil else {
                throw NativeInputError.unsupported
            }
            selection = try systemFocus(matching: currentSelection)
        }
        let app = selection.application, root = selection.root, element = selection.element, window = selection.window
        currentSelection = selection
        AXUIElementSetMessagingTimeout(root, 0.12)
        guard let range = selectedRange(element) else { throw NativeInputError.unsupported }
        // Verify the element belongs to the focused window, when the application exposes it.
        if let owningWindow = elementValue(element, kAXWindowAttribute), !CFEqual(owningWindow, window) {
            throw NativeInputError.targetChanged
        }
        let bundle = app.bundleIdentifier ?? ""
        let role = string(element, kAXRoleAttribute)
        let subrole = string(element, kAXSubroleAttribute) ?? ""
        let description = string(element, kAXRoleDescriptionAttribute) ?? ""
        let identifier = string(element, kAXIdentifierAttribute) ?? ""
        let sensitive = InputSafetyPolicy.isSensitive(applicationID: bundle, role: role ?? "", subrole: subrole,
                                                       description: description, identifier: identifier)
        // Never read text from a secure field, even for local confirmation.
        guard !sensitive else { throw NativeInputError.sensitive }
        let enabled = bool(element, kAXEnabledAttribute)
        let editable: Bool
        do { editable = try InputSafetyPolicy.isEditable(role: role, enabled: enabled) }
        catch { unavailable("editor-role-unavailable"); throw error }
        if !editable { unavailable(enabled == false ? "editor-disabled" : "editor-role-not-editable") }
        let (isWeb, page, contextComplete) = try pageIdentity(element, window: window, appID: bundle)
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
                                   isSensitive: sensitive, canSetSelectedText: isWeb ? supportsRangeReplacement(element) : settable.boolValue, pageContextComplete: contextComplete)
    }

    /// Prove an already-issued write against system-wide focus when the application
    /// timed out. A cached element alone never proves focus. Require every independent
    /// observation to point to the same already-bound web field and window.
    private func systemFocus(matching previous: AXInputSelection) throws -> AXInputSelection {
        let pid = previous.application.processIdentifier
        guard NSWorkspace.shared.frontmostApplication?.processIdentifier == pid else { throw NativeInputError.targetChanged }
        let system = AXUIElementCreateSystemWide()
        AXUIElementSetMessagingTimeout(system, 0.12)
        let root = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(root, 0.12)
        guard let focused = elementValue(system, kAXFocusedUIElementAttribute),
              let window = elementValue(root, kAXFocusedWindowAttribute),
              let owner = elementValue(focused, kAXWindowAttribute),
              let isFocused = bool(focused, kAXFocusedAttribute) else { throw NativeInputError.unsupported }
        var actualPID: pid_t = 0
        guard AXUIElementGetPid(focused, &actualPID) == .success, actualPID == pid, isFocused,
              CFEqual(focused, previous.element), CFEqual(window, previous.window), CFEqual(window, owner),
              NSWorkspace.shared.frontmostApplication?.processIdentifier == pid else { throw NativeInputError.targetChanged }
        return AXInputSelection(application: previous.application, root: root, window: window, element: focused)
    }

    func dispatch(_ text: String, to expected: InputTargetSnapshot) throws -> Bool {
        let current = try snapshot()
        guard current == expected, let element = currentElement, let selection = currentSelection else { return false }
        try current.checked()
        if current.canSetSelectedText {
            guard focusStillMatches(selection, expected: expected) else { return false }
            if current.isWeb {
                guard supportsRangeReplacement(element), let witness = textWitness(at: current),
                      OwnedInputText.replacing(witness, start: current.selectionLocation, expected: "", replacement: text) != nil,
                      (try? snapshot()) == current, focusStillMatches(selection, expected: expected) else { return false }
                return try replaceWebRange(on: element, start: current.selectionLocation, length: 0, text: text)
            }
            let result = AXUIElementSetAttributeValue(element, kAXSelectedTextAttribute as CFString, text as CFString)
            try Self.checkTextWrite(result)
            return true
        }
        guard !current.isWeb else { return false }
        // Deliberate clipboard fallback. Do not inspect private clipboard data to preserve it.
        // Do not restore asynchronously: that could overwrite a newer user copy.
        guard let source = CGEventSource(stateID: .privateState),
              let down = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: false) else { return false }
        down.flags = .maskCommand
        up.flags = .maskCommand
        NSPasteboard.general.clearContents()
        guard NSPasteboard.general.setString(text, forType: .string) else { return false }
        let pasteboardGeneration = NSPasteboard.general.changeCount
        // A final focus/page/selection check follows the clipboard mutation.
        guard try snapshot() == expected, focusStillMatches(selection, expected: expected),
              NSPasteboard.general.changeCount == pasteboardGeneration else { return false }
        // Process-specific events avoid redirecting a paste to an app activated in the dispatch race.
        down.postToPid(expected.processID)
        up.postToPid(expected.processID)
        return true
    }

    private static func checkTextWrite(_ result: AXError) throws {
        if result == .cannotComplete { throw AXTextWriteTimeout() }
        guard result == .success else { throw AXDispatchFailure(code: result.rawValue) }
    }

    private func supportsRangeReplacement(_ element: AXUIElement) -> Bool {
        var names: CFArray?
        return AXUIElementCopyParameterizedAttributeNames(element, &names) == .success &&
            (names as? [String])?.contains("AXReplaceRangeWithText") == true
    }

    /// Ask the already identified editor to replace only this UTF-16 range. An
    /// acknowledged write still requires independent readback by the coordinator.
    private func replaceWebRange(on element: AXUIElement, start: Int, length: Int, text: String) throws -> Bool {
        var range = CFRange(location: start, length: length)
        guard let value = AXValueCreate(.cfRange, &range) else { return false }
        let parameters: [String: Any] = ["AXReplacementRange": value, "AXReplacementText": text]
        var response: CFTypeRef?
        let result = AXUIElementCopyParameterizedAttributeValue(element, "AXReplaceRangeWithText" as CFString,
                                                                 parameters as CFDictionary, &response)
        try Self.checkTextWrite(result)
        return true
    }

    private func focusStillMatches(_ selection: AXInputSelection, expected: InputTargetSnapshot) -> Bool {
        // Semantic tree inspection may involve IPC. Re-read actual focus afterwards,
        // immediately before the one write; never rely on its earlier root snapshot.
        guard let latest = try? selectionProvider(), latest.application.processIdentifier == expected.processID,
              CFEqual(latest.window, selection.window), CFEqual(latest.element, selection.element),
              let range = selectedRange(latest.element), range.location == expected.selectionLocation,
              range.length == 0 else { return false }
        return true
    }

    func verify(_ text: String, at before: InputTargetSnapshot) -> InputTargetSnapshot? {
        guard let after = try? snapshot(), after.sameTarget(as: before), after.selectionLength == 0,
              after.selectionLocation == before.selectionLocation + text.utf16.count else { return nil }
        guard matchesText(text, utf16Start: before.selectionLocation, at: after) == true else { return nil }
        return after
    }

    func matchesText(_ text: String, utf16Start: Int, at expected: InputTargetSnapshot) -> Bool? {
        if expected.isWeb {
            // textWitness proves the full target and caret both before and after
            // reading the field. A third tree walk before those two reads can
            // needlessly time out while Chrome is processing selection changes.
            guard let witness = textWitness(at: expected), utf16Start >= 0,
                  utf16Start <= witness.utf16.count, text.utf16.count <= witness.utf16.count - utf16Start,
                  let readback = RecognitionUTF16.slice(witness, start: utf16Start, end: utf16Start + text.utf16.count) else { return nil }
            return readback.utf8.elementsEqual(text.utf8)
        }
        guard let current = try? snapshot(), current == expected, let element = currentElement else { return false }
        var range = CFRange(location: utf16Start, length: text.utf16.count)
        guard let value = AXValueCreate(.cfRange, &range) else { return nil }
        var output: CFTypeRef?
        guard AXUIElementCopyParameterizedAttributeValue(element, kAXStringForRangeParameterizedAttribute as CFString,
                                                         value, &output) == .success, let inserted = output as? String else { return nil }
        return inserted.utf8.elementsEqual(text.utf8)
    }

    /// Bounded runtime witness includes surrounding text so insertion/replacement can
    /// prove grapheme boundaries and preserve the user's prefix and suffix. Never stored.
    func textWitness(at expected: InputTargetSnapshot) -> String? {
        try? checkedTextWitness(at: expected)
    }

    func checkedTextWitness(at expected: InputTargetSnapshot) throws -> String? {
        let current: InputTargetSnapshot
        do { current = try snapshot() }
        catch { unavailable("witness.before_snapshot"); throw error }
        guard current == expected, !current.isSensitive, current.isEditable,
              let element = currentElement else { unavailable("witness.before_identity"); return nil }
        guard let count = attribute(element, kAXNumberOfCharactersAttribute) as? NSNumber,
              (0...65_536).contains(count.intValue) else { unavailable("witness.character_count"); return nil }
        var range = CFRange(location: 0, length: count.intValue)
        guard let value = AXValueCreate(.cfRange, &range) else { return nil }
        var output: CFTypeRef?
        let status = AXUIElementCopyParameterizedAttributeValue(element, kAXStringForRangeParameterizedAttribute as CFString,
                                                                value, &output)
        let ranged = status == .success ? output as? String : nil
        let text: String?
        if let ranged, ranged.utf16.count == range.length {
            text = ranged
        } else if current.isWeb {
            // A bounded plain text control may expose its value but omit the full-range string.
            text = attribute(element, kAXValueAttribute) as? String
        } else { text = nil }
        guard let text, text.utf16.count == range.length else { unavailable("witness.text_range"); return nil }
        let after: InputTargetSnapshot
        do { after = try snapshot() }
        catch { unavailable("witness.after_snapshot"); throw error }
        guard after == expected else { unavailable("witness.after_identity"); return nil }
        return text
    }

    func replaceOwned(_ expectedText: String, with replacement: String, start: Int,
                      witness: String, at expected: InputTargetSnapshot, isCurrent: @MainActor () -> Bool) throws -> Bool {
        try expected.checked()
        guard isCurrent(), !expectedText.isEmpty, expected.selectionLocation == start + expectedText.utf16.count,
              expected.canSetSelectedText, (try? snapshot()) == expected,
              let element = currentElement, let selection = currentSelection,
              let updated = OwnedInputText.replacing(witness, start: start, expected: expectedText, replacement: replacement),
              updated.utf16.count <= 65_536,
              let currentText = textWitness(at: expected), currentText.utf8.elementsEqual(witness.utf8) else { return false }
        if expected.isWeb {
            guard supportsRangeReplacement(element), (try? snapshot()) == expected,
                  textWitness(at: expected)?.utf8.elementsEqual(witness.utf8) == true,
                  focusStillMatches(selection, expected: expected), isCurrent() else { return false }
            return try replaceWebRange(on: element, start: start, length: expectedText.utf16.count, text: replacement)
        }
        var rangeSettable = DarwinBoolean(false), textSettable = DarwinBoolean(false)
        guard AXUIElementIsAttributeSettable(element, kAXSelectedTextRangeAttribute as CFString, &rangeSettable) == .success,
              AXUIElementIsAttributeSettable(element, kAXSelectedTextAttribute as CFString, &textSettable) == .success,
              rangeSettable.boolValue, textSettable.boolValue,
              focusStillMatches(selection, expected: expected), isCurrent() else { return false }
        var range = CFRange(location: start, length: expectedText.utf16.count)
        guard let value = AXValueCreate(.cfRange, &range) else { return false }
        // The first side effect follows Store reservation. Neither failure nor timeout
        // is retried. There is no clipboard, key-event or AXValue replacement fallback.
        let selected = AXUIElementSetAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, value)
        guard selected == .success else { throw AXDispatchFailure(code: selected.rawValue) }
        var selectedSnapshot = expected
        selectedSnapshot.selectionLocation = start; selectedSnapshot.selectionLength = expectedText.utf16.count
        guard (try? snapshot()) == selectedSnapshot,
              let immediateText = textWitness(at: selectedSnapshot), immediateText.utf8.elementsEqual(witness.utf8),
              let latest = try? selectionProvider(), latest.application.processIdentifier == expected.processID,
              CFEqual(latest.window, selection.window), CFEqual(latest.element, element),
              let immediateRange = selectedRange(element), immediateRange.location == range.location,
              immediateRange.length == range.length, isCurrent() else { throw NativeInputError.targetChanged }
        let result = AXUIElementSetAttributeValue(element, kAXSelectedTextAttribute as CFString, replacement as CFString)
        try Self.checkTextWrite(result)
        return true
    }

    func observe(_ expected: InputTargetSnapshot, onChange: @escaping @MainActor (InputTargetChange) -> Void) -> InputObservationSupport {
        stopObserving()
        guard let current = try? snapshot(), current == expected, let selection = currentSelection else {
            return .init(focus: false, content: false, page: false)
        }
        guard let observation = AXTargetObservation(pid: expected.processID, handler: onChange) else { return .init(focus: false, content: false, page: false) }
        self.observation = observation
        let focus = observation.add(selection.root, kAXFocusedUIElementChangedNotification) && observation.add(selection.root, kAXFocusedWindowChangedNotification)
        _ = observation.add(selection.window, kAXTitleChangedNotification)
        _ = observation.add(selection.element, kAXUIElementDestroyedNotification)
        let content = observation.add(selection.element, kAXValueChangedNotification) && observation.add(selection.element, kAXSelectedTextChangedNotification)
        let page = currentWebArea.map { observation.add($0, kAXLayoutChangedNotification) } ?? false
        observation.start()
        return .init(focus: focus, content: content, page: page)
    }
    func stopObserving() { observation = nil }

    private func pageIdentity(_ element: AXUIElement, window: AXUIElement, appID: String) throws -> (Bool, String?, Bool) {
        currentWebArea = nil
        var node: AXUIElement? = element
        var isWeb = InputSafetyPolicy.isBrowser(applicationID: appID)
        var url: String?
        var pageTitle: String?
        for _ in 0..<24 {
            guard let current = node else { break }
            guard let ancestry = contextAttributes(current, names: [kAXRoleAttribute, kAXParentAttribute]) else {
                unavailable("page.ancestry"); throw NativeInputError.unsupported
            }
            if ancestry[kAXRoleAttribute] as? String == "AXWebArea" {
                isWeb = true
                currentWebArea = current
                guard let page = contextAttributes(current, names: [kAXURLAttribute, kAXDocumentAttribute, kAXTitleAttribute]) else {
                    unavailable("page.metadata"); return (true, nil, false)
                }
                url = attributeString(page[kAXURLAttribute]) ?? attributeString(page[kAXDocumentAttribute])
                pageTitle = page[kAXTitleAttribute] as? String
                break
            }
            if CFEqual(current, window) { break }
            if let parent = ancestry[kAXParentAttribute], CFGetTypeID(parent) == AXUIElementGetTypeID() {
                node = unsafeDowncast(parent, to: AXUIElement.self)
            } else { node = nil }
        }
        guard let windowValues = contextAttributes(window, names: [kAXDocumentAttribute, kAXTitleAttribute]) else {
            unavailable("page.window_metadata"); throw NativeInputError.unsupported
        }
        let document = attributeString(windowValues[kAXDocumentAttribute])
        let title = windowValues[kAXTitleAttribute] as? String ?? ""
        if isWeb {
            let identity = url ?? document
            guard let identity, !identity.isEmpty else { return (true, nil, false) }
            let context = currentWebArea.flatMap { pageContext($0, excluding: element) }
            return (true, identity + "\u{1f}" + (pageTitle ?? title) + "\u{1f}" + (context ?? ""), context != nil)
        }
        // Native document changes in the same window also expire a binding.
        return (false, (document ?? "") + "\u{1f}" + title, true)
    }

    /// A page can change conversations without changing URL, editor, value or caret,
    /// and WebKit does not always emit layout notifications. Compare bounded accessible
    /// semantic context before every write. Exclude the editor subtree and retain only
    /// its in-memory digest; neither page text nor identifiers enter the database.
    /// Exhausted budget / unreadable structure is unknown, never evidence of stability.
    private func pageContext(_ webArea: AXUIElement, excluding editor: AXUIElement) -> String? {
        let deadline = ProcessInfo.processInfo.systemUptime + 0.15
        var queue = [webArea], visited = Set<CFHashCode>(), tokens: [String] = []
        var textBytes = 0, semanticAnchors = 0, count = 0
        while !queue.isEmpty {
            guard count < 128, ProcessInfo.processInfo.systemUptime < deadline else {
                unavailable("page.context_budget"); return nil
            }
            let node = queue.removeFirst(), identity = CFHash(node)
            guard visited.insert(identity).inserted else { return nil }
            count += 1
            // Batch role and non-value context. Value/URL is read only after
            // classifying an anchor/link; editable fields remain excluded.
            guard var values = contextAttributes(node, names: [kAXRoleAttribute, kAXTitleAttribute,
                      kAXIdentifierAttribute, kAXSelectedAttribute, kAXChildrenAttribute]),
                  let role = values[kAXRoleAttribute] as? String else {
                unavailable("page.context_attributes"); return nil
            }
            tokens.append("\(identity):\(role)")
            if CFEqual(node, editor) { tokens.append("bound-editor"); continue }
            if [kAXTextFieldRole, kAXTextAreaRole, kAXComboBoxRole].contains(role) { continue }
            let isAnchor = role == kAXStaticTextRole || role == "AXHeading"
            if isAnchor || role == "AXLink" {
                let name = isAnchor ? kAXValueAttribute : kAXURLAttribute
                guard let semantic = contextAttributes(node, names: [name]) else {
                    unavailable("page.context_semantic"); return nil
                }
                values[name] = semantic[name]
            }
            for name in [kAXTitleAttribute, kAXIdentifierAttribute] {
                if let value = values[name] as? String, !value.isEmpty {
                    textBytes += value.utf8.count; guard textBytes <= 32_768 else { return nil }
                    tokens.append(name + ":" + value)
                }
            }
            if isAnchor, let value = values[kAXValueAttribute] as? String, !value.isEmpty {
                textBytes += value.utf8.count; guard textBytes <= 32_768 else { return nil }
                semanticAnchors += 1; tokens.append("text:" + value)
            }
            if let selected = values[kAXSelectedAttribute] as? Bool { tokens.append("selected:\(selected)") }
            if role == "AXLink", let url = attributeString(values[kAXURLAttribute]) { tokens.append("url:" + url) }
            guard let children = values[kAXChildrenAttribute] as? [AXUIElement] else {
                // Leaf accessibility objects may legitimately omit children.
                if [kAXStaticTextRole, kAXButtonRole, kAXImageRole, "AXLink"].contains(role) { continue }
                return nil
            }
            guard queue.count + children.count + count <= 128 else { return nil }
            tokens.append("children:\(children.count)")
            queue.append(contentsOf: children)
        }
        guard semanticAnchors > 0 else { return nil }
        return SHA256.hash(data: Data(tokens.joined(separator: "\u{1e}").utf8)).map { String(format: "%02x", $0) }.joined()
    }

    /// Unsupported optional attributes and missing values represent normal AX leaves.
    /// Transport errors and incomplete batches cannot establish page identity.
    private func contextAttributes(_ node: AXUIElement, names: [String]) -> [String: AnyObject]? {
        AXUIElementSetMessagingTimeout(node, 0.12)
        var results: CFArray?
        guard AXUIElementCopyMultipleAttributeValues(node, names as CFArray, [], &results) == .success,
              let items = results as? [AnyObject], items.count == names.count else { return nil }
        var values: [String: AnyObject] = [:]
        for (name, item) in zip(names, items) {
            if CFGetTypeID(item) == CFNullGetTypeID() { continue }
            if CFGetTypeID(item) == AXValueGetTypeID() {
                let value = unsafeDowncast(item, to: AXValue.self)
                if AXValueGetType(value) == .axError {
                    var error = AXError.failure
                    guard AXValueGetValue(value, .axError, &error),
                          error == .attributeUnsupported || error == .noValue else { return nil }
                    continue
                }
            }
            values[name] = item
        }
        return values
    }

    private func attribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
        AXUIElementSetMessagingTimeout(element, 0.12)
        var output: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &output) == .success else { return nil }
        return output
    }
    private func string(_ element: AXUIElement, _ name: String) -> String? {
        attributeString(attribute(element, name))
    }
    private func attributeString(_ raw: CFTypeRef?) -> String? {
        guard let value = raw else { return nil }
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

struct AXTextWriteTimeout: Error {}
struct AXDispatchFailure: Error { let code: Int32 }

enum InputSafetyPolicy {
    /// An unreadable role is missing proof, not proof of a non-editable target.
    /// A known disabled field still refuses immediately, even if its role is absent.
    /// The coordinator may only settle an already-issued write after this unknown;
    /// initial binding and every new write continue to require a complete snapshot.
    static func isEditable(role: String?, enabled: Bool?) throws -> Bool {
        if enabled == false { return false }
        guard let role, !role.isEmpty else { throw NativeInputError.unsupported }
        return [kAXTextFieldRole, kAXTextAreaRole, kAXComboBoxRole].contains(role)
    }
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

// The callback source is registered only on the main run loop. Removing the source
// before releasing its context prevents callbacks into a released coordinator.
private final class AXTargetObservation {
    private let observer: AXObserver
    private let relay: AXObservationRelay
    init?(pid: Int32, handler: @escaping @MainActor (InputTargetChange) -> Void) {
        var result: AXObserver?
        guard AXObserverCreate(pid, { _, _, notification, context in
            guard let context else { return }
            let relay = Unmanaged<AXObservationRelay>.fromOpaque(context).takeUnretainedValue()
            let name = notification as String
            MainActor.assumeIsolated {
                switch name {
                case kAXValueChangedNotification, kAXSelectedTextChangedNotification: relay.handler(.contentOrSelection)
                case kAXLayoutChangedNotification: relay.handler(.layout)
                default: relay.handler(.focusOrDocument)
                }
            }
        }, &result) == .success, let result else { return nil }
        observer = result; relay = AXObservationRelay(handler: handler)
    }
    func add(_ element: AXUIElement, _ name: String) -> Bool {
        let result = AXObserverAddNotification(observer, element, name as CFString, Unmanaged.passUnretained(relay).toOpaque())
        return result == .success || result == .notificationAlreadyRegistered
    }
    func start() { CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .commonModes) }
    deinit { CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .commonModes) }
}
// Immutable callback holder; the closure itself requires MainActor at invocation.
private final class AXObservationRelay: @unchecked Sendable {
    let handler: @MainActor (InputTargetChange) -> Void
    init(handler: @escaping @MainActor (InputTargetChange) -> Void) { self.handler = handler }
}
