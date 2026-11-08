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
        let access = BufferedDiagnosticAccess(AXInputAccess(selectionProvider: selector))
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("saytile-rc-input-store-" + UUID().uuidString)
        // Diagnostic retains its own isolated Store after completion.
        let store = try SaytileStore(directory: directory)
        let coordinator = NativeInputCoordinator(store: store, access: access)
        coordinator.onBindingInvalidated = { access.record("bindingInvalidated", "") }
        var checks = 0
        func expect(_ condition: Bool, _ message: String) throws {
            guard condition else { throw Failure(description: message) }
            checks += 1; print("PASS " + message); fflush(nil)
        }
        let binding = try await coordinator.bindCurrentTarget()
        let recording = try await store.createRecording(createdAt: binding.boundAt.addingTimeInterval(1))
        let revision1 = try await store.saveEdit(recordingID: recording.id, text: "你好😀")
        let inserted = await coordinator.insertStable(recordingID: recording.id, revisionID: revision1.id, stableUTF16End: 4, recordingStartedAt: recording.createdAt)
        access.record("result", String(describing: inserted))
        let postText = attribute(field, kAXValueAttribute) as? String
        let postSelection = attribute(field, kAXSelectedTextRangeAttribute)
        let activation = activationAudit.finish()
        try await store.close()
        print("DIAGNOSTIC_POSTTEXT \(String(describing: postText)) utf16=\(postText.map { Array($0.utf16) } ?? []) scalars=\(postText.map { $0.unicodeScalars.map { $0.value } } ?? []) selection=\(String(describing: postSelection))")
        print("DIAGNOSTIC_STORE " + directory.path)
        for event in access.events { print(event) }
        print("DIAGNOSTIC_RESULT result=\(String(describing: inserted)) binding=\(String(describing: coordinator.binding)) owned_activated=\(activation.ownedActivated) outside=\(activation.outsideActivations) unchanged=\(NSWorkspace.shared.frontmostApplication?.processIdentifier == frontmost)")
    }
}
@MainActor final class BufferedDiagnosticAccess: InputAccess {
    let base: AXInputAccess
    let began = ProcessInfo.processInfo.systemUptime
    var events: [String] = []
    init(_ base: AXInputAccess) { self.base = base; events.reserveCapacity(128) }
    func record(_ name: String, _ value: String) { events.append("EVENT t=\(ProcessInfo.processInfo.systemUptime-began) kind=\(name) \(value)") }
    var hasPermission: Bool { base.hasPermission }
    func snapshot() throws -> InputTargetSnapshot { do { let value = try base.snapshot(); record("snapshot",String(describing:value)); return value } catch { record("snapshotError",String(describing:error)); throw error } }
    func dispatch(_ text: String, to expected: InputTargetSnapshot) throws -> Bool {
        record("dispatchBegin", String(describing:expected))
        do { let value = try base.dispatch(text,to:expected); record("dispatchReturn",String(value)); return value } catch { record("dispatchError",String(describing:error)); throw error }
    }
    func verify(_ text: String, at before: InputTargetSnapshot) -> InputTargetSnapshot? { let value=base.verify(text,at:before); record("verify",String(describing:value));return value }
    func matchesText(_ text: String, utf16Start: Int, at expected: InputTargetSnapshot) -> Bool? { let value=base.matchesText(text,utf16Start:utf16Start,at:expected);record("matchesText",String(describing:value));return value }
    func observe(_ expected: InputTargetSnapshot, onChange: @escaping @MainActor (InputTargetChange) -> Void) -> InputObservationSupport {
        record("observe", "")
        return base.observe(expected) { [weak self] change in self?.record("change",String(describing:change)); onChange(change) }
    }
    func stopObserving() { record("stopObserving", "");base.stopObserving() }
    func textWitness(at expected: InputTargetSnapshot) -> String? { let value=base.textWitness(at:expected);record("textWitness",value ?? "nil");return value }
    func replaceOwned(_ expectedText: String, with replacement: String, start: Int, witness: String, at expected: InputTargetSnapshot, isCurrent: @MainActor () -> Bool) throws -> Bool { try base.replaceOwned(expectedText,with:replacement,start:start,witness:witness,at:expected,isCurrent:isCurrent) }
}
