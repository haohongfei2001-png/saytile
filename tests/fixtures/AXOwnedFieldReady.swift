import AppKit
@testable import SaytileKit

/// Start one ordinary binding when the disposable editor has reported its full
/// identity three times. The production observer remains attached through the
/// quiet period and the subsequent test edit.
@MainActor func bindOwnedField(_ input: NativeInputCoordinator, trace: FixtureAccessTrace,
                               original: String, caret: Int, pid: Int32,
                               documentReady: (InputTargetSnapshot) -> Bool = { _ in true }) async throws {
    let access = trace.base
    let clock = ContinuousClock(), deadline = clock.now.advanced(by: .seconds(5))
    func ready(_ current: InputTargetSnapshot) -> Bool {
        current.processID == pid && current.isEditable && !current.isSensitive && current.canSetSelectedText &&
        current.selectionLocation == caret && current.selectionLength == 0 && documentReady(current) &&
        (!current.isWeb || (current.pageContextComplete && current.pageIdentity != nil)) &&
        access.textWitness(at: current) == original
    }
    var first: InputTargetSnapshot?
    var consecutive = 0
    while clock.now < deadline {
        if let current = try? access.snapshot(), ready(current) {
            if let first, first != current { throw NativeInputError.targetChanged }
            first = current
            consecutive += 1
            if consecutive == 3 { break }
        } else { consecutive = 0 }
        try await Task.sleep(for: .milliseconds(180))
    }
    guard consecutive == 3, let expected = first else { throw CocoaError(.validationMissingMandatoryProperty) }
    let binding = try await input.bindCurrentTarget()
    var verified = false
    defer { if !verified { input.invalidate() } }
    guard trace.bound == expected, let support = trace.support,
          support.focus && support.content && (!expected.isWeb || support.page) else {
        throw NativeInputError.unobservablePage
    }
    var events = trace.notifications
    var quiet = 0
    while clock.now < deadline {
        guard input.binding?.id == binding.id else { throw NativeInputError.targetChanged }
        let current: InputTargetSnapshot
        do {
            current = try access.snapshot()
        } catch NativeInputError.unsupported {
            // The focused native or web editor and its range can be unreadable between
            // notifications. An unreadable sample cannot establish a quiet interval.
            quiet = 0
            print("OWNED_READ_UNAVAILABLE", trace.stage, "bound snapshot")
            try await clock.sleep(until: min(deadline, clock.now.advanced(by: .milliseconds(180))))
            continue
        }
        guard current == expected, ready(current) else { throw NativeInputError.targetChanged }
        quiet = trace.notifications == events ? quiet + 1 : 1
        if quiet == 3 {
            verified = true
            print("OWNED_READY complete_reads", consecutive, "bound_quiet_reads", quiet, "observed_notifications", trace.notifications)
            return
        }
        events = trace.notifications
        try await Task.sleep(for: .milliseconds(180))
    }
    throw CocoaError(.validationMissingMandatoryProperty)
}

/// Records the OS result for one attempt on the two allowlisted synthetic fields.
@MainActor final class FixtureAccessTrace: InputAccess {
    let base: AXInputAccess
    var stage = "bind"
    private(set) var writes = 0
    private(set) var bound: InputTargetSnapshot?
    private(set) var support: InputObservationSupport?
    private(set) var notifications = 0
    // Optional test action between reservation and the last ownership check.
    var beforeSnapshot: (() throws -> Void)?
    init(_ base: AXInputAccess) { self.base = base }
    var hasPermission: Bool { base.hasPermission }
    func snapshot() throws -> InputTargetSnapshot {
        try beforeSnapshot?()
        do {
            let current = try base.snapshot()
            if let bound {
                print("OWNED_SNAPSHOT", stage, "pid", current.processID == bound.processID,
                      "app", current.applicationID == bound.applicationID, "window", current.windowID == bound.windowID,
                      "editor", current.elementID == bound.elementID, "page", current.pageIdentity == bound.pageIdentity,
                      "complete", current.pageContextComplete, "caret", current.selectionLocation,
                      "length", current.selectionLength, "editable", current.isEditable, "sensitive", current.isSensitive,
                      "setter", current.canSetSelectedText, "appLabel", current.applicationName == bound.applicationName)
            }
            return current
        } catch { print("OWNED_SNAPSHOT_ERROR", stage, error); throw error }
    }
    func textWitness(at expected: InputTargetSnapshot) -> String? { base.textWitness(at: expected) }
    func dispatch(_ text: String, to expected: InputTargetSnapshot) throws -> Bool {
        writes += 1
        let start = ProcessInfo.processInfo.systemUptime
        defer { print("OWNED_WRITE elapsed_ms", Int(1000 * (ProcessInfo.processInfo.systemUptime - start))); fflush(nil) }
        do { let issued = try base.dispatch(text, to: expected); print("OWNED_WRITE issued", issued); return issued }
        catch { print("OWNED_WRITE error", error); throw error }
    }
    func verify(_ text: String, at before: InputTargetSnapshot) -> InputTargetSnapshot? {
        let after = base.verify(text, at: before)
        print("OWNED_VERIFY", after != nil); fflush(nil)
        return after
    }
    func matchesText(_ text: String, utf16Start: Int, at expected: InputTargetSnapshot) -> Bool? {
        let matched = base.matchesText(text, utf16Start: utf16Start, at: expected)
        if text.isEmpty { print("OWNED_CARET_READBACK", stage, matched == true) }
        return matched
    }
    func observe(_ expected: InputTargetSnapshot, onChange: @escaping @MainActor (InputTargetChange) -> Void) -> InputObservationSupport {
        bound = expected
        notifications = 0
        let capabilities = base.observe(expected) { [weak self] change in
            self?.notifications += 1
            print("OWNED_EVENT", change); fflush(nil); onChange(change)
        }
        support = capabilities
        print("OWNED_OBSERVER", stage, "focus", capabilities.focus, "content", capabilities.content, "page", capabilities.page)
        return capabilities
    }
    func stopObserving() { base.stopObserving() }
    func replaceOwned(_ expectedText: String, with replacement: String, start: Int, witness: String, at expected: InputTargetSnapshot,
                      isCurrent: @MainActor () -> Bool) throws -> Bool {
        try base.replaceOwned(expectedText, with: replacement, start: start, witness: witness, at: expected, isCurrent: isCurrent)
    }
}
