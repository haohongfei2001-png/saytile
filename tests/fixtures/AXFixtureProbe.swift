import AppKit
import ApplicationServices

// This test accesses only an explicitly supplied fixture PID, never the user's active app.
@main
struct AXFixtureProbe {
    @MainActor static func main() throws {
        guard CommandLine.arguments.count == 2, let pid = Int32(CommandLine.arguments[1]) else { exit(2) }
        guard AXIsProcessTrusted() else { print("AX_FIXTURE_NOT_AUTHORIZED_NO_PROMPT"); exit(5) }
        let originalFrontmost = NSWorkspace.shared.frontmostApplication?.processIdentifier
        guard originalFrontmost != pid else { print("FIXTURE_UNEXPECTEDLY_FRONTMOST"); exit(3) }
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 0.2)
        func attribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
            var result: CFTypeRef?
            guard AXUIElementCopyAttributeValue(element, name as CFString, &result) == .success else { return nil }
            return result
        }
        var target: AXUIElement?
        var nodes = (attribute(app, kAXWindowsAttribute) as? [AXUIElement]) ?? []
        var inspected = 0
        while !nodes.isEmpty, inspected < 200 {
            let node = nodes.removeFirst(); inspected += 1
            if attribute(node, kAXRoleAttribute) as? String == kAXTextAreaRole { target = node; break }
            nodes += (attribute(node, kAXChildrenAttribute) as? [AXUIElement]) ?? []
        }
        guard let target else { print("AX_FIXTURE_TEXTAREA_UNAVAILABLE"); exit(4) }
        var selected = CFRange(location: 7, length: 0)
        guard let selectedValue = AXValueCreate(.cfRange, &selected),
              AXUIElementSetAttributeValue(target, kAXSelectedTextRangeAttribute as CFString, selectedValue) == .success else {
            print("AX_FIXTURE_RANGE_UNSUPPORTED"); exit(4)
        }
        let inserted = "你好😀"
        guard AXUIElementSetAttributeValue(target, kAXSelectedTextAttribute as CFString, inserted as CFString) == .success else {
            print("AX_FIXTURE_LOCAL_INSERT_UNSUPPORTED"); exit(4)
        }
        guard attribute(target, kAXValueAttribute) as? String == "PREFIX|你好😀SUFFIX" else {
            print("AX_FIXTURE_TEXT_MISMATCH"); exit(1)
        }
        var insertedRange = CFRange(location: 7, length: inserted.utf16.count)
        let rangeValue = AXValueCreate(.cfRange, &insertedRange)!
        var result: CFTypeRef?
        guard AXUIElementCopyParameterizedAttributeValue(target, kAXStringForRangeParameterizedAttribute as CFString, rangeValue, &result) == .success,
              result as? String == inserted else { print("AX_FIXTURE_SUBSTRING_MISMATCH"); exit(1) }
        guard let rawRange = attribute(target, kAXSelectedTextRangeAttribute), CFGetTypeID(rawRange) == AXValueGetTypeID() else { exit(1) }
        var caret = CFRange()
        guard AXValueGetValue(unsafeDowncast(rawRange, to: AXValue.self), .cfRange, &caret),
              caret.location == 11, caret.length == 0 else { print("AX_FIXTURE_CARET_MISMATCH"); exit(1) }
        guard NSWorkspace.shared.frontmostApplication?.processIdentifier == originalFrontmost else { print("AX_FIXTURE_FRONTMOST_CHANGED"); exit(1) }
        print("AX_FIXTURE_PASS local insertion + UTF16 caret + exact substring + preserved prefix/suffix + no focus change")
    }
}
