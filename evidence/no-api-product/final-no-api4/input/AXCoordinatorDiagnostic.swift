import AppKit
#if SAYTILE_PACKAGE_PROBE
@testable import SaytileKit
#endif
import ApplicationServices

// Link the production SaytileKit package. The only injected boundary is
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
        let activationAudit = FixtureActivationAudit(fixturePID: pid)
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
        print("DIAGNOSTIC_STORE " + directory.path); fflush(nil)
        let store = try SaytileStore(directory: directory)
        let coordinator = NativeInputCoordinator(store: store, access: access)
        var checks = 0
        func expect(_ condition: Bool, _ message: String) throws {
            guard condition else { throw Failure(description: message) }
            checks += 1; print("PASS " + message); fflush(nil)
        }
        print("DIAGNOSTIC_BEFORE_BIND snapshot=\(String(describing: try? access.snapshot()))"); fflush(nil)
        let binding = try await coordinator.bindCurrentTarget()
        print("DIAGNOSTIC_BOUND binding=\(String(describing: coordinator.binding))"); fflush(nil)
        let recording = try await store.createRecording(createdAt: binding.boundAt.addingTimeInterval(1))
        let revision1 = try await store.saveEdit(recordingID: recording.id, text: "你好😀")
        print("DIAGNOSTIC_BEFORE_INSERT snapshot=\(String(describing: try? access.snapshot())) binding=\(String(describing: coordinator.binding))"); fflush(nil)
        let inserted = await coordinator.insertStable(recordingID: recording.id, revisionID: revision1.id, stableUTF16End: 4, recordingStartedAt: recording.createdAt)
        print("DIAGNOSTIC_RESULT result=\(String(describing: inserted)) binding=\(String(describing: coordinator.binding)) snapshot=\(String(describing: try? access.snapshot()))")
        for name in [kAXValueAttribute, kAXSelectedTextRangeAttribute, kAXSelectedTextAttribute, kAXNumberOfCharactersAttribute, kAXFocusedAttribute, kAXEnabledAttribute] {
            var value: CFTypeRef?
            let code = AXUIElementCopyAttributeValue(field, name as CFString, &value)
            print("DIAGNOSTIC_AX \(name) code=\(code.rawValue) value=\(String(describing: value))")
        }
        let activation = activationAudit.finish()
        print("DIAGNOSTIC_ACTIVATION owned=\(activation.ownedActivated) outside=\(activation.outsideActivations) unchanged=\(NSWorkspace.shared.frontmostApplication?.processIdentifier == frontmost)")
        try await store.close()
        fflush(nil)
    }
}
