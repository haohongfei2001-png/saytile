import AppKit
@testable import SaytileKit

/// Start one ordinary binding when the disposable editor has reported its full
/// identity three times. The production observer remains attached through the
/// quiet period and the subsequent test edit.
@MainActor func bindOwnedField(_ input: NativeInputCoordinator, trace: FixtureAccessTrace,
                               original: String, caret: Int, pid: Int32, expectingWeb: Bool,
                               documentReady: (InputTargetSnapshot) -> Bool = { _ in true }) async throws {
    let access = trace.base
    let clock = ContinuousClock(), deadline = clock.now.advanced(by: .seconds(5))
    // Only booleans/reason labels enter the fixture log. Keep the original AX read
    // count and short-circuit order: diagnosis must not add another witness read.
    func difference(_ current: InputTargetSnapshot, from expected: InputTargetSnapshot, phase: String) {
        print("OWNED_READY_DIFFERENCE", trace.stage, phase,
              "pid", current.processID == expected.processID, "app", current.applicationID == expected.applicationID,
              "appLabel", current.applicationName == expected.applicationName, "window", current.windowID == expected.windowID,
              "editor", current.elementID == expected.elementID, "page", current.pageIdentity == expected.pageIdentity,
              "complete", current.pageContextComplete == expected.pageContextComplete,
              "caret", current.selectionLocation == expected.selectionLocation, "range", current.selectionLength == expected.selectionLength,
              "web", current.isWeb == expected.isWeb, "editable", current.isEditable == expected.isEditable,
              "sensitive", current.isSensitive == expected.isSensitive, "setter", current.canSetSelectedText == expected.canSetSelectedText)
    }
    func ready(_ current: InputTargetSnapshot, phase: String) -> Bool {
        guard current.processID == pid && current.isWeb == expectingWeb && current.isEditable && !current.isSensitive && current.canSetSelectedText &&
              current.selectionLocation == caret && current.selectionLength == 0 else {
            print("OWNED_READY_REJECT", trace.stage, phase, "field_requirements",
                  "pid", current.processID == pid, "web", current.isWeb == expectingWeb,
                  "editable", current.isEditable, "sensitive", current.isSensitive, "setter", current.canSetSelectedText,
                  "caret", current.selectionLocation == caret, "collapsed", current.selectionLength == 0)
            return false
        }
        guard documentReady(current) else {
            print("OWNED_READY_REJECT", trace.stage, phase, "document_requirements"); return false
        }
        guard !current.isWeb || (current.pageContextComplete && current.pageIdentity != nil) else {
            print("OWNED_READY_REJECT", trace.stage, phase, "page_proof",
                  "complete", current.pageContextComplete, "identityPresent", current.pageIdentity != nil)
            return false
        }
        let witness = access.textWitness(at: current)
        guard witness == original else {
            print("OWNED_READY_REJECT", trace.stage, phase, witness == nil ? "witness_missing" : "witness_mismatch")
            return false
        }
        return true
    }
    // WKWebView can temporarily expose an editable AX object before its web area
    // is readable. Only the known editor kind may start this three-read interval.
    var first: InputTargetSnapshot?
    var consecutive = 0
    while clock.now < deadline {
        let current = try? access.snapshot()
        if let current, ready(current, phase: "initial") {
            if let first, first != current {
                difference(current, from: first, phase: "initial_identity")
                throw NativeInputError.targetChanged
            }
            first = current
            consecutive += 1
            if consecutive == 3 { break }
        } else {
            if current == nil { print("OWNED_READY_REJECT", trace.stage, "initial", "snapshot_unavailable") }
            consecutive = 0
        }
        try await Task.sleep(for: .milliseconds(180))
    }
    guard consecutive == 3, let expected = first else {
        print("OWNED_READY_REJECT", trace.stage, "initial", "deadline", "complete_reads", consecutive)
        throw CocoaError(.validationMissingMandatoryProperty)
    }
    let binding: InputBindingInfo
    do { binding = try await input.bindCurrentTarget() }
    catch {
        print("OWNED_READY_REJECT", trace.stage, "bind_call", "failed")
        throw error
    }
    var verified = false
    var abortReason = "bound_exception"
    defer {
        if !verified {
            print("OWNED_READY_ABORT", trace.stage, abortReason, "bindingStillCurrent", input.binding?.id == binding.id,
                  "observed_notifications", trace.notifications)
            input.invalidate()
        }
    }
    guard trace.bound == expected, let support = trace.support,
          support.focus && support.content && (!expected.isWeb || support.page) else {
        abortReason = "observer_requirements"
        if let bound = trace.bound { difference(bound, from: expected, phase: "observer_identity") }
        print("OWNED_READY_REJECT", trace.stage, abortReason, "boundPresent", trace.bound != nil,
              "focus", trace.support?.focus == true, "content", trace.support?.content == true, "page", trace.support?.page == true)
        throw NativeInputError.unobservablePage
    }
    var events = trace.notifications
    var quiet = 0
    while clock.now < deadline {
        guard input.binding?.id == binding.id else {
            abortReason = "binding_invalidated_before_read"
            throw NativeInputError.targetChanged
        }
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
        } catch {
            abortReason = "bound_snapshot_error"
            print("OWNED_READY_REJECT", trace.stage, abortReason)
            throw error
        }
        guard current == expected else {
            abortReason = "bound_snapshot_difference"
            difference(current, from: expected, phase: "bound")
            throw NativeInputError.targetChanged
        }
        guard ready(current, phase: "bound") else {
            abortReason = "bound_readiness_rejected"
            throw NativeInputError.targetChanged
        }
        quiet = trace.notifications == events ? quiet + 1 : 1
        if quiet == 3 {
            verified = true
            print("OWNED_READY complete_reads", consecutive, "bound_quiet_reads", quiet, "observed_notifications", trace.notifications)
            return
        }
        events = trace.notifications
        try await Task.sleep(for: .milliseconds(180))
    }
    abortReason = "bound_deadline"
    print("OWNED_READY_REJECT", trace.stage, abortReason, "quiet_reads", quiet)
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
    // Hosted Chrome can interrupt only the application-level reply to the
    // first post-write read. The system-wide focus still comes from macOS.
    var interruptFirstWebFocusRead: (() -> Void)?
    private(set) var provedInterruptedFocus = false
    init(_ base: AXInputAccess) { self.base = base }
    var hasPermission: Bool { base.hasPermission }
    func snapshot() throws -> InputTargetSnapshot {
        try tracedSnapshot(base.snapshot)
    }
    func snapshotAfterIssuedWebInsertion() throws -> InputTargetSnapshot {
        let interrupt = interruptFirstWebFocusRead
        interruptFirstWebFocusRead = nil
        interrupt?()
        let result = try tracedSnapshot(base.snapshotAfterIssuedWebInsertion)
        if interrupt != nil { provedInterruptedFocus = true }
        return result
    }
    private func tracedSnapshot(_ read: () throws -> InputTargetSnapshot) throws -> InputTargetSnapshot {
        try beforeSnapshot?()
        do {
            let current = try read()
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
