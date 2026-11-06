import AppKit
import ApplicationServices

// Compile with the production Store/Input sources. The only injected boundary is
// selecting the supplied background fixture instead of the user's foreground app.
@main
struct AXCoordinatorProbe {
    struct Failure: Error { let description: String }
    @MainActor static func main() async throws {
        NSApplication.shared.setActivationPolicy(.prohibited)
        guard CommandLine.arguments.count == 2, let pid = Int32(CommandLine.arguments[1]),
              let app = NSRunningApplication(processIdentifier: pid) else { exit(2) }
        guard AXIsProcessTrusted() else { print("NO_ACCESSIBILITY_PERMISSION_NO_PROMPT"); exit(5) }
        let frontmost = NSWorkspace.shared.frontmostApplication?.processIdentifier
        guard frontmost != pid else { throw Failure(description: "Fixture unexpectedly owns foreground") }
        func attribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
            var result: CFTypeRef?
            guard AXUIElementCopyAttributeValue(element, name as CFString, &result) == .success else { return nil }
            return result
        }
        let root = AXUIElementCreateApplication(pid)
        let windows = (attribute(root, kAXWindowsAttribute) as? [AXUIElement]) ?? []
        guard let window = windows.first else { throw Failure(description: "Fixture window unavailable") }
        var nodes = windows, textField: AXUIElement?
        while !nodes.isEmpty {
            let node = nodes.removeFirst()
            if attribute(node, kAXRoleAttribute) as? String == kAXTextAreaRole { textField = node; break }
            nodes += (attribute(node, kAXChildrenAttribute) as? [AXUIElement]) ?? []
        }
        guard let field = textField else { throw Failure(description: "Fixture field unavailable") }
        let selector = { @MainActor in AXInputSelection(application: app, root: root, window: window, element: field) }
        let access = AXInputAccess(selectionProvider: selector)
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("saytile-rc-input-store-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try SaytileStore(directory: directory)
        let coordinator = NativeInputCoordinator(store: store, access: access)
        var checks = 0
        func expect(_ condition: Bool, _ message: String) throws {
            guard condition else { throw Failure(description: message) }
            checks += 1; print("PASS " + message); fflush(nil)
        }
        let binding = try await coordinator.bindCurrentTarget()
        let recording = try await store.createRecording(createdAt: binding.boundAt.addingTimeInterval(1))
        let revision1 = try await store.saveEdit(recordingID: recording.id, text: "你好😀")
        let inserted = await coordinator.insertStable(recordingID: recording.id, revisionID: revision1.id, stableUTF16End: 4, recordingStartedAt: recording.createdAt)
        try expect(inserted == .confirmed, "production coordinator + SQLite reservation + real AX insertion confirms")
        try expect(attribute(field, kAXValueAttribute) as? String == "PREFIX|你好😀SUFFIX", "preserves synthetic prefix and suffix")
        let duplicate = await coordinator.insertStable(recordingID: recording.id, revisionID: revision1.id, stableUTF16End: 4, recordingStartedAt: recording.createdAt)
        try expect(duplicate == .noNewText, "same stable range is not inserted twice")
        let revision2 = try await store.saveEdit(recordingID: recording.id, text: "你好😀，接着说")
        let suffix = await coordinator.insertStable(recordingID: recording.id, revisionID: revision2.id, stableUTF16End: revision2.text.utf16.count, recordingStartedAt: recording.createdAt)
        try expect(suffix == .confirmed, "next stable suffix inserts after actual UTF16 caret")
        try expect(attribute(field, kAXValueAttribute) as? String == "PREFIX|你好😀，接着说SUFFIX", "no duplicate prefix or whole-field replacement")
        var selection = CFRange(location: 0, length: 6)
        let range = AXValueCreate(.cfRange, &selection)!
        guard AXUIElementSetAttributeValue(field, kAXSelectedTextRangeAttribute as CFString, range) == .success else { throw Failure(description: "Fixture selection not settable") }
        try await Task.sleep(for: .milliseconds(100))
        try expect(coordinator.binding == nil, "real AX selection notification invalidates binding before next operation")
        let selectedResult = await coordinator.insert(recordingID: recording.id, revisionID: revision1.id)
        try expect(selectedResult != .confirmed && attribute(field, kAXValueAttribute) as? String == "PREFIX|你好😀，接着说SUFFIX", "real selected range prevents replacement")
        selection = CFRange(location: 7, length: 0)
        let caret = AXValueCreate(.cfRange, &selection)!
        _ = AXUIElementSetAttributeValue(field, kAXSelectedTextRangeAttribute as CFString, caret)
        try await Task.sleep(for: .milliseconds(100))
        try await coordinator.bindCurrentTarget(purpose: .manual)
        let cancelled = Task { await coordinator.insert(recordingID: recording.id, revisionID: revision1.id) }
        cancelled.cancel()
        try expect(await cancelled.value == .cancelled, "cancelled production insertion has no external attempt")
        coordinator.invalidate()
        try expect(NSWorkspace.shared.frontmostApplication?.processIdentifier == frontmost, "fixture and insertion never change foreground application")
        print("RC_AX_COORDINATOR_PASS \(checks) checks; background target selection injected; no production foreground or browser claim")
    }
}
