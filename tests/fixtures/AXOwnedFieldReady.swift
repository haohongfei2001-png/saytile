import AppKit
@testable import SaytileKit

/// Only reads the disposable window during its single startup transition. Registering
/// an observer also lets pending WebKit focus, layout and selection events drain.
@MainActor func waitForOwnedField(_ access: AXInputAccess, original: String,
                                  caret: Int, pid: Int32,
                                  documentReady: (InputTargetSnapshot) -> Bool = { _ in true }) async throws {
    let clock = ContinuousClock(), deadline = clock.now.advanced(by: .seconds(5))
    var initial: InputTargetSnapshot?
    var observedChanges = 0, previousChanges = 0, consecutive = 0
    defer { access.stopObserving() }
    while clock.now < deadline {
        if let current = try? access.snapshot(), current.processID == pid,
           current.isEditable, !current.isSensitive, current.canSetSelectedText,
           current.selectionLocation == caret, current.selectionLength == 0,
           documentReady(current),
           !current.isWeb || (current.pageContextComplete && current.pageIdentity != nil),
           access.textWitness(at: current) == original {
            if let initial {
                guard current == initial else { throw NativeInputError.targetChanged }
            } else {
                let support = access.observe(current) { _ in observedChanges += 1 }
                guard support.focus && support.content && (!current.isWeb || support.page) else {
                    throw NativeInputError.unobservablePage
                }
                initial = current
            }
            consecutive = previousChanges == observedChanges ? consecutive + 1 : 1
            previousChanges = observedChanges
            if consecutive >= 3 {
                print("OWNED_READY complete_reads", consecutive, "startup_notifications", observedChanges)
                return
            }
        } else { consecutive = 0 }
        try await Task.sleep(for: .milliseconds(180))
    }
    throw CocoaError(.validationMissingMandatoryProperty)
}

/// Records the OS result for one attempt on the two allowlisted synthetic fields.
@MainActor final class FixtureAccessTrace: InputAccess {
    let base: AXInputAccess
    var stage = "bind"
    private(set) var writes = 0
    private var bound: InputTargetSnapshot?
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
        base.matchesText(text, utf16Start: utf16Start, at: expected)
    }
    func observe(_ expected: InputTargetSnapshot, onChange: @escaping @MainActor (InputTargetChange) -> Void) -> InputObservationSupport {
        bound = expected
        return base.observe(expected) { change in print("OWNED_EVENT", change); fflush(nil); onChange(change) }
    }
    func stopObserving() { base.stopObserving() }
    func replaceOwned(_ expectedText: String, with replacement: String, start: Int, witness: String, at expected: InputTargetSnapshot,
                      isCurrent: @MainActor () -> Bool) throws -> Bool {
        try base.replaceOwned(expectedText, with: replacement, start: start, witness: witness, at: expected, isCurrent: isCurrent)
    }
}
