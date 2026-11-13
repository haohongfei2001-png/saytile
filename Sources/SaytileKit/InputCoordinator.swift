import AppKit
import ApplicationServices

public enum InputBindingPurpose: Sendable { case manual, continuous }

public struct InputBindingInfo: Sendable, Equatable {
    public let id: UUID
    public let label: String
    public let boundAt: Date
}

public enum NativeInputResult: Sendable, Equatable {
    case confirmed, unverified, noNewText, cancelled, deferred, correctionPending, failed(String)
    public var message: String {
        switch self {
        case .confirmed: "已插入"
        case .correctionPending: "修正版已保留；目标范围无法安全确认，不会自动重试修正。"
        case .unverified: "已尝试插入，请在目标应用核对；不会自动重发"
        case .noNewText: "没有新的稳定文字"
        case .deferred: "较早一段的识别结果已保留在输入板，可手动取用；后续新表达继续输入。"
        case .cancelled: "目标已变化，文字保留在 Saytile"
        case .failed(let reason): reason
        }
    }
}

public enum NativeInputError: Error, LocalizedError {
    case permission, noTarget, unsupported, selection, sensitive, targetChanged, pageUnknown, unobservablePage, busy
    public var errorDescription: String? {
        switch self {
        case .permission: "请在系统设置中允许 Saytile 使用辅助功能；复制无需此权限。"
        case .noTarget: "请先在目标应用的输入框放好光标，再使用快捷键连接。"
        case .unsupported: "此输入框不支持安全插入，请使用复制。"
        case .selection: "目标中有选中文字，请先放置光标；Saytile 不会替换已有选区。"
        case .sensitive: "密码框和终端不支持自动插入，请使用复制。"
        case .targetChanged: "目标、页面或光标已变化，请重新连接。"
        case .pageUnknown: "无法辨认当前网页，已保留文字；请使用复制。"
        case .unobservablePage: "此网页没有提供足够的草稿变化信息，连续输入暂不可用；可以明确单次插入或复制。"
        case .busy: "上一项插入尚未完成。"
        }
    }
}

// Runtime identity is never persisted. Only the app display name enters the audit log.
struct InputTargetSnapshot: Equatable {
    var processID: Int32
    var applicationID: String
    var applicationName: String
    var windowID: UUID
    var elementID: UUID
    var pageIdentity: String?
    var selectionLocation: Int
    var selectionLength: Int
    var isWeb: Bool
    var isEditable: Bool
    var isSensitive: Bool
    var canSetSelectedText: Bool
    var pageContextComplete: Bool = true

    func checked() throws {
        guard !isSensitive else { throw NativeInputError.sensitive }
        guard isEditable, selectionLocation >= 0 else { throw NativeInputError.unsupported }
        guard selectionLength == 0 else { throw NativeInputError.selection }
        guard !isWeb || pageIdentity != nil else { throw NativeInputError.pageUnknown }
    }
    func sameTarget(as old: Self) -> Bool {
        processID == old.processID && applicationID == old.applicationID &&
        windowID == old.windowID && elementID == old.elementID && pageIdentity == old.pageIdentity
    }
}

enum InputTargetChange { case focusOrDocument, contentOrSelection, layout }
struct InputObservationSupport { let focus: Bool; let content: Bool; let page: Bool }

@MainActor
protocol InputAccess: AnyObject {
    var hasPermission: Bool { get }
    func snapshot() throws -> InputTargetSnapshot
    // One external attempt; a timeout is uncertain, never grounds for retry.
    func dispatch(_ text: String, to expected: InputTargetSnapshot) throws -> Bool
    func verify(_ text: String, at before: InputTargetSnapshot) -> InputTargetSnapshot?
    func matchesText(_ text: String, utf16Start: Int, at expected: InputTargetSnapshot) -> Bool?
    func observe(_ expected: InputTargetSnapshot, onChange: @escaping @MainActor (InputTargetChange) -> Void) -> InputObservationSupport
    func stopObserving()
    // Bounded, ephemeral witness; never persisted. Unknown text/boundaries forbid ownership.
    func textWitness(at expected: InputTargetSnapshot) -> String?
    func replaceOwned(_ expectedText: String, with replacement: String, start: Int,
                      witness: String, at expected: InputTargetSnapshot, isCurrent: @MainActor () -> Bool) throws -> Bool
}
extension InputAccess {
    func textWitness(at expected: InputTargetSnapshot) -> String? { nil }
    func replaceOwned(_ expectedText: String, with replacement: String, start: Int,
                      witness: String, at expected: InputTargetSnapshot, isCurrent: @MainActor () -> Bool) throws -> Bool { false }

    func matchesText(_ text: String, utf16Start: Int, at expected: InputTargetSnapshot) -> Bool? { nil }
    func observe(_ expected: InputTargetSnapshot, onChange: @escaping @MainActor (InputTargetChange) -> Void) -> InputObservationSupport { .init(focus: false, content: false, page: false) }
    func stopObserving() {}
}

/// Swift String equality is canonically equivalent, which is too weak for ownership.
/// Both old and resulting boundaries must be extended-grapheme boundaries in context.
enum OwnedInputText {
    static func replacing(_ witness: String, start: Int, expected: String, replacement: String) -> String? {
        guard start >= 0, start <= witness.utf16.count,
              expected.utf16.count <= witness.utf16.count - start else { return nil }
        let end = start + expected.utf16.count
        guard let before = RecognitionUTF16.slice(witness, start: 0, end: start),
              let owned = RecognitionUTF16.slice(witness, start: start, end: end),
              owned.utf8.elementsEqual(expected.utf8),
              let after = RecognitionUTF16.slice(witness, start: end, end: witness.utf16.count) else { return nil }
        let result = before + replacement + after
        guard RecognitionUTF16.slice(result, start: 0, end: start) != nil,
              RecognitionUTF16.slice(result, start: start, end: start + replacement.utf16.count) != nil else { return nil }
        return result
    }
}

@MainActor
public final class NativeInputCoordinator {
    private let store: SaytileStore
    private let access: any InputAccess
    private var target: InputTargetSnapshot?
    public private(set) var binding: InputBindingInfo?
    private var isDispatching = false
    private var hasIssuedDispatch = false
    private var inFlightInsertion: (target: InputTargetSnapshot, text: String, expectedField: String?)?
    private var boundPurpose: InputBindingPurpose = .continuous
    private struct Ownership {
        let recordingID: UUID
        let start: Int
        var text: String
        var witness: String
    }
    private var owned: Ownership?
    private var observedEditSequence: UInt64 = 0
    private var canObserveOwnership = false
    private var inFlightCorrection: (before: InputTargetSnapshot, selected: InputTargetSnapshot,
                                     after: InputTargetSnapshot, oldText: String, newText: String)?
    private var confirmedTail: (text: String, start: Int)?
    private let activationNotificationCenter: NotificationCenter?
    private var activationObserver: NSObjectProtocol?
    private var generation = 0
    public var onBindingInvalidated: (@MainActor () -> Void)?
    public var hasPermission: Bool { access.hasPermission }

    public convenience init(store: SaytileStore) {
        self.init(store: store, access: AXInputAccess(),
                  activationNotificationCenter: NSWorkspace.shared.notificationCenter)
    }
    // Simulated InputAccess must not observe the user's real desktop. Tests can
    // supply their own center to exercise the same activation protection.
    init(store: SaytileStore, access: any InputAccess,
         activationNotificationCenter: NotificationCenter? = nil) {
        self.store = store
        self.access = access
        self.activationNotificationCenter = activationNotificationCenter
        activationObserver = activationNotificationCenter?.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] note in
            let pid = (note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?.processIdentifier
            Task { @MainActor [weak self] in
                guard let self, let target = self.target, pid != target.processID else { return }
                self.invalidate()
            }
        }
    }

    /// Invoke only from an explicit user action. This is the sole prompt site.
    @discardableResult public func requestPermission() -> Bool {
        AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
    }

    @discardableResult public func bindCurrentTarget(purpose: InputBindingPurpose = .continuous) async throws -> InputBindingInfo {
        try Task.checkCancellation()
        guard !isDispatching else { throw NativeInputError.busy }
        guard hasPermission else { throw NativeInputError.permission }
        let snapshot = try access.snapshot()
        try snapshot.checked()
        invalidate()
        let bindGeneration = generation
        // One timestamp is shared by the runtime and SQLite boundary. The store also
        // captures a creation-sequence boundary, so equal clock ticks cannot admit history.
        let boundAt = Date()
        let id = try await store.createBinding(label: snapshot.applicationName, createdAt: boundAt)
        guard !Task.isCancelled, generation == bindGeneration,
              let current = try? access.snapshot(), current == snapshot else {
            try? await store.invalidateBinding(id)
            throw NativeInputError.targetChanged
        }
        let info = InputBindingInfo(id: id, label: snapshot.applicationName, boundAt: boundAt)
        target = snapshot
        binding = info; boundPurpose = purpose
        let support = access.observe(snapshot) { [weak self] change in
            guard let self, self.binding != nil else { return }
            switch change {
            case .focusOrDocument: self.invalidate()
            case .contentOrSelection:
                self.observedEditSequence &+= 1
                if let pending = self.inFlightCorrection, let current = try? self.access.snapshot(),
                   let witness = self.access.textWitness(at: current),
                   ((current == pending.selected && witness.utf8.elementsEqual(pending.oldText.utf8)) ||
                    (current == pending.after && witness.utf8.elementsEqual(pending.newText.utf8))) { break }
                if self.target?.isWeb == true {
                    if !self.observedOwnWebEdit() { self.invalidate() }
                    break
                }
                if self.hasIssuedDispatch, let pending = self.inFlightInsertion,
                   let current = try? self.access.snapshot(), current.sameTarget(as: pending.target),
                   current.selectionLength == 0,
                   current.selectionLocation == pending.target.selectionLocation + pending.text.utf16.count,
                   self.access.matchesText(pending.text, utf16Start: pending.target.selectionLocation, at: current) == true {
                    // An observed edit is ignored only when it is exactly our expected
                    // insertion. User selection/content changes during confirmation expire it.
                    break
                }
                self.invalidate()
            case .layout:
                // An unrelated page layout can reuse the same editor and URL.
                if self.target?.isWeb == true { self.invalidate() }
            }
        }
        canObserveOwnership = support.focus && support.content && (!snapshot.isWeb || support.page && snapshot.pageContextComplete)
        if purpose == .continuous, snapshot.isWeb,
           !(snapshot.pageContextComplete && support.focus && support.content && support.page && access.matchesText("", utf16Start: snapshot.selectionLocation, at: snapshot) == true) {
            invalidate()
            throw NativeInputError.unobservablePage
        }
        return info
    }

    private func observedOwnWebEdit() -> Bool {
        guard let current = try? access.snapshot(), current.isWeb, current.pageContextComplete,
              current.selectionLength == 0, let field = access.textWitness(at: current) else { return false }
        if let pending = inFlightCorrection {
            return current == pending.after && field.utf8.elementsEqual(pending.newText.utf8)
        }
        guard hasIssuedDispatch, let pending = inFlightInsertion, let expectedField = pending.expectedField else { return false }
        var expected = pending.target
        expected.selectionLocation += pending.text.utf16.count
        return current == expected && field.utf8.elementsEqual(expectedField.utf8)
    }

    /// Wait for pending notifications of this one write, while the binding can still
    /// be revoked. After returning, even an edit followed by Undo expires ownership.
    private func settledWrite(at target: InputTargetSnapshot, witness: String, generation expectedGeneration: Int) async -> Bool {
        var gapSequence: UInt64?
        var matchingReadsAfterGap = 0
        for _ in 0..<4 {
            let sequence = observedEditSequence
            do { try await Task.sleep(for: .milliseconds(220)) } catch { return false }
            guard generation == expectedGeneration, gapSequence == nil || gapSequence == observedEditSequence else { return false }
            do {
                guard try access.snapshot() == target,
                      access.textWitness(at: target)?.utf8.elementsEqual(witness.utf8) == true else { return false }
            } catch NativeInputError.unsupported {
                // No mutation while the AX field is unreadable. After any gap the
                // same binding must give two new full witnesses without an edit,
                // focus, selection or document observation anywhere in between.
                guard observedEditSequence == sequence else { return false }
                gapSequence = sequence
                matchingReadsAfterGap = 0
                continue
            } catch { return false }
            guard generation == expectedGeneration else { return false }
            if gapSequence != nil {
                guard observedEditSequence == sequence else { return false }
                matchingReadsAfterGap += 1
                if matchingReadsAfterGap == 2 { return true }
            } else if observedEditSequence == sequence { return true }
        }
        return false
    }

    public func invalidate() {
        generation += 1
        let id = binding?.id
        binding = nil
        target = nil
        confirmedTail = nil
        owned = nil
        canObserveOwnership = false
        access.stopObserving()
        if let id { Task { try? await store.invalidateBinding(id) } }
        if id != nil { onBindingInvalidated?() }
    }

    public func copy(_ text: String) {
        copy(text, to: .general)
    }

    @discardableResult public func copy(_ text: String, to pasteboard: NSPasteboard) -> Bool {
        pasteboard.clearContents()
        return pasteboard.setString(text, forType: .string)
    }

    /// Explicit manual reuse still requires an existing live target. It never activates another app.
    public func insert(recordingID: UUID, revisionID: UUID) async -> NativeInputResult {
        await perform(recordingID: recordingID, revisionID: revisionID, stableEnd: nil, startedAt: nil)
    }

    /// Only provider-stable ranges of speech begun after this binding are eligible.
    public func insertStable(recordingID: UUID, revisionID: UUID, stableUTF16End: Int,
                             recordingStartedAt: Date) async -> NativeInputResult {
        await perform(recordingID: recordingID, revisionID: revisionID,
                      stableEnd: stableUTF16End, startedAt: recordingStartedAt)
    }

    private func perform(recordingID: UUID, revisionID: UUID, stableEnd: Int?, startedAt: Date?) async -> NativeInputResult {
        guard !Task.isCancelled else { return .cancelled }
        guard !isDispatching else { return .failed(NativeInputError.busy.localizedDescription) }
        guard let target, let binding else { return .cancelled }
        if stableEnd != nil, boundPurpose != .continuous { return .failed(NativeInputError.unobservablePage.localizedDescription) }
        // Dates loaded from SQLite are represented as Unix-epoch Double values.
        // Compare in that same precision; equal ticks are decided by the store's
        // recording-creation boundary, not an unreliable strict wall-clock ordering.
        if let startedAt, startedAt.timeIntervalSince1970 < binding.boundAt.timeIntervalSince1970 { return .noNewText }
        let startGeneration = generation
        do {
            try validate(target)
            isDispatching = true
            defer { isDispatching = false; hasIssuedDispatch = false; inFlightInsertion = nil }
            let reservation: DispatchReservation?
            if let stableEnd {
                reservation = try await store.reserveDispatch(bindingID: binding.id, recordingID: recordingID,
                                                               revisionID: revisionID, stableUTF16End: stableEnd)
            } else {
                reservation = try await store.reserveManual(recordingID: recordingID, revisionID: revisionID,
                                                             label: binding.label)
            }
            guard let reservation else { return .noNewText }
            // A record can be deleted while the reservation transaction is awaited.
            // Its removed/cancelled operation must never reach the external application.
            guard try await store.dispatchState(id: reservation.id) == .dispatching else { return .cancelled }
            guard !Task.isCancelled, startGeneration == generation else {
                try? await store.completeDispatch(id: reservation.id, state: .cancelled)
                return .cancelled
            }
            do { try validate(target) } catch {
                try? await store.completeDispatch(id: reservation.id, state: .cancelled)
                invalidate()
                return .cancelled
            }
            do {
                // dispatch returns false only before any external side effect.
                // A timeout on the text mutation may be settled by readback only.
                guard !Task.isCancelled else {
                    try? await store.completeDispatch(id: reservation.id, state: .cancelled)
                    return .cancelled
                }
                let beforeText = (canObserveOwnership || target.isWeb) ? access.textWitness(at: target) : nil
                let priorOwned = owned
                guard startGeneration == generation, !Task.isCancelled else {
                    try? await store.completeDispatch(id: reservation.id, state: .cancelled)
                    return .cancelled
                }
                owned = nil // Any unconfirmed or noncontiguous attempt consumes prior ownership.
                let expectedField = beforeText.flatMap {
                    OwnedInputText.replacing($0, start: target.selectionLocation, expected: "", replacement: reservation.text)
                }
                inFlightInsertion = (target, reservation.text, expectedField)
                hasIssuedDispatch = true
                var needsFullReadback = target.isWeb && boundPurpose == .continuous
                do {
                    guard try access.dispatch(reservation.text, to: target) else {
                        try? await store.completeDispatch(id: reservation.id, state: .cancelled)
                        invalidate()
                        return .cancelled
                    }
                } catch is AXTextWriteTimeout {
                    // The OS can time out after actually modifying the field.
                    // Only independently observed exact field, caret and identity can settle it.
                    needsFullReadback = true
                }
                // Confirm the one attempt over a bounded window. This loop never dispatches again.
                for delay in [80, 80, 160, 240] {
                    do { try await Task.sleep(for: .milliseconds(delay)) } catch { break }
                    guard startGeneration == generation else { break }
                    if let after = access.verify(reservation.text, at: target),
                       !needsFullReadback || expectedField.map({ access.textWitness(at: after)?.utf8.elementsEqual($0.utf8) == true }) == true,
                       startGeneration == generation {
                        if needsFullReadback {
                            guard let expectedField, await settledWrite(at: after, witness: expectedField, generation: startGeneration) else {
                                invalidate()
                                break
                            }
                        }
                        self.target = after
                        let tail = String(reservation.text.suffix(32))
                        confirmedTail = (tail, target.selectionLocation + reservation.text.utf16.count - tail.utf16.count)
                        try await store.completeDispatch(id: reservation.id, state: .confirmed)
                        if stableEnd != nil, startGeneration == generation, let beforeText,
                           let afterText = access.textWitness(at: after),
                           let expectedAfter = OwnedInputText.replacing(beforeText, start: target.selectionLocation,
                               expected: "", replacement: reservation.text),
                           afterText.utf8.elementsEqual(expectedAfter.utf8) {
                            let candidate: Ownership?
                            if reservation.utf16Start == 0 {
                                candidate = Ownership(recordingID: recordingID, start: target.selectionLocation,
                                                      text: reservation.text, witness: afterText)
                            } else if let priorOwned, priorOwned.recordingID == recordingID,
                                      priorOwned.start + priorOwned.text.utf16.count == target.selectionLocation,
                                      priorOwned.witness.utf8.elementsEqual(beforeText.utf8) {
                                candidate = Ownership(recordingID: recordingID, start: priorOwned.start,
                                    text: priorOwned.text + reservation.text, witness: afterText)
                            } else { candidate = nil }
                            if let candidate, try await store.recordOwnedInsertion(reservation, bindingID: binding.id,
                                targetStart: candidate.start, text: candidate.text), startGeneration == generation {
                                owned = candidate
                            }
                        }
                        return .confirmed
                    }
                    if let current = try? access.snapshot(), !current.sameTarget(as: target) { break }
                }
                try? await store.completeDispatch(id: reservation.id, state: .unverified)
                // A failed confirmation does not globally freeze independent future speech.
                // Keep binding only if identity is unchanged and caret moved by exactly our range.
                if let after = try? access.snapshot(), after.sameTarget(as: target),
                   after.selectionLength == 0,
                   after.selectionLocation == target.selectionLocation + reservation.text.utf16.count,
                   startGeneration == generation {
                    self.target = after
                } else { invalidate() }
                return .unverified
            } catch {
                try? await store.completeDispatch(id: reservation.id, state: .unverified)
                invalidate()
                return .unverified
            }
        } catch StoreError.lateRecognitionDeferred {
            // A later recording has already reserved input. Keep this late text local,
            // without expiring the live target or blocking independent future speech.
            return .deferred
        } catch {
            invalidate()
            return .failed(error.localizedDescription)
        }
    }

    /// Direct-mode correction of a Store-approved archive, never a local draft/preview.
    public func repairOwned(revision: TranscriptRevision) async -> NativeInputResult {
        guard !isDispatching, !Task.isCancelled, let binding, let target else { return .correctionPending }
        let startGeneration = generation
        guard let owned, owned.recordingID == revision.recordingID, canObserveOwnership,
              target.selectionLength == 0, target.selectionLocation == owned.start + owned.text.utf16.count,
              let replacementWitness = OwnedInputText.replacing(owned.witness, start: owned.start,
                  expected: owned.text, replacement: revision.text) else {
            try? await store.pendOwnedCorrection(bindingID: binding.id, revision: revision)
            return .correctionPending
        }
        if owned.text.utf8.elementsEqual(revision.text.utf8) { return .noNewText }
        isDispatching = true
        defer { isDispatching = false; inFlightCorrection = nil }
        var operation: OwnedCorrectionReservation?
        do {
            try validate(target)
            guard let op = try await store.reserveOwnedCorrection(bindingID: binding.id, revision: revision,
                targetStart: owned.start, expectedText: owned.text) else {
                try? await store.pendOwnedCorrection(bindingID: binding.id, revision: revision)
                return .correctionPending
            }
            operation = op
            guard try await store.ownedCorrectionMayExecute(op), !Task.isCancelled,
                  startGeneration == generation else { throw NativeInputError.targetChanged }
            try validate(target)
            var selected = target
            selected.selectionLocation = owned.start; selected.selectionLength = owned.text.utf16.count
            var after = target
            after.selectionLocation = owned.start + revision.text.utf16.count
            inFlightCorrection = (target, selected, after, owned.witness, replacementWitness)
            self.owned = nil
            do {
                guard try access.replaceOwned(owned.text, with: revision.text, start: owned.start,
                    witness: owned.witness, at: target, isCurrent: {
                        self.generation == startGeneration && self.binding?.id == binding.id && !Task.isCancelled
                    }) else {
                    try await store.completeOwnedCorrection(op, confirmed: false, notAttempted: true)
                    return .correctionPending
                }
            } catch is AXTextWriteTimeout {
                // Read back the one already issued mutation and never send it again.
            }
            // One write, bounded confirmation only. Never a second mutation on uncertainty.
            for delay in [40, 80, 160] {
                try await Task.sleep(for: .milliseconds(delay))
                guard startGeneration == generation else { break }
                if let current = try? access.snapshot(), current == after,
                   let witness = access.textWitness(at: current), witness.utf8.elementsEqual(replacementWitness.utf8) {
                    if current.isWeb, !(await settledWrite(at: after, witness: replacementWitness, generation: startGeneration)) { break }
                    try await store.completeOwnedCorrection(op, confirmed: true)
                    guard startGeneration == generation else { return .correctionPending }
                    self.target = after
                    self.owned = Ownership(recordingID: revision.recordingID, start: owned.start,
                                           text: revision.text, witness: witness)
                    let tail = String(revision.text.suffix(32))
                    confirmedTail = (tail, after.selectionLocation - tail.utf16.count)
                    return .confirmed
                }
            }
            try await store.completeOwnedCorrection(op, confirmed: false)
            invalidate()
            return .correctionPending
        } catch {
            if let operation { try? await store.completeOwnedCorrection(operation, confirmed: false) }
            else { try? await store.pendOwnedCorrection(bindingID: binding.id, revision: revision) }
            invalidate()
            return .correctionPending
        }
    }

    private func validate(_ target: InputTargetSnapshot) throws {
        guard hasPermission else { throw NativeInputError.permission }
        let current = try access.snapshot()
        try current.checked()
        guard current == target else { throw NativeInputError.targetChanged }
        if let owned {
            guard let witness = access.textWitness(at: target), witness.utf8.elementsEqual(owned.witness.utf8) else {
                throw NativeInputError.targetChanged
            }
        }
        if let confirmedTail, access.matchesText(confirmedTail.text, utf16Start: confirmedTail.start, at: target) != true {
            throw NativeInputError.targetChanged
        }
    }
}
