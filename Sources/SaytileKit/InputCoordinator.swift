import AppKit
import ApplicationServices

public enum InputBindingPurpose: Sendable { case manual, continuous }

public struct InputBindingInfo: Sendable, Equatable {
    public let id: UUID
    public let label: String
    public let boundAt: Date
}

public enum NativeInputResult: Sendable, Equatable {
    case confirmed, unverified, noNewText, cancelled, failed(String)
    public var message: String {
        switch self {
        case .confirmed: "已插入"
        case .unverified: "已尝试插入，请在目标应用核对；不会自动重发"
        case .noNewText: "没有新的稳定文字"
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
}
extension InputAccess {
    func matchesText(_ text: String, utf16Start: Int, at expected: InputTargetSnapshot) -> Bool? { nil }
    func observe(_ expected: InputTargetSnapshot, onChange: @escaping @MainActor (InputTargetChange) -> Void) -> InputObservationSupport { .init(focus: false, content: false, page: false) }
    func stopObserving() {}
}

@MainActor
public final class NativeInputCoordinator {
    private let store: SaytileStore
    private let access: any InputAccess
    private var target: InputTargetSnapshot?
    public private(set) var binding: InputBindingInfo?
    private var isDispatching = false
    private var hasIssuedDispatch = false
    private var inFlightInsertion: (target: InputTargetSnapshot, text: String)?
    private var boundPurpose: InputBindingPurpose = .continuous
    private var confirmedTail: (text: String, start: Int)?
    private var activationObserver: NSObjectProtocol?
    private var generation = 0
    public var onBindingInvalidated: (@MainActor () -> Void)?
    public var hasPermission: Bool { access.hasPermission }

    public convenience init(store: SaytileStore) { self.init(store: store, access: AXInputAccess()) }
    init(store: SaytileStore, access: any InputAccess) {
        self.store = store
        self.access = access
        activationObserver = NSWorkspace.shared.notificationCenter.addObserver(
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
        let id = try await store.createBinding(label: snapshot.applicationName)
        guard !Task.isCancelled, generation == bindGeneration,
              let current = try? access.snapshot(), current == snapshot else {
            try? await store.invalidateBinding(id)
            throw NativeInputError.targetChanged
        }
        let info = InputBindingInfo(id: id, label: snapshot.applicationName, boundAt: Date())
        target = snapshot
        binding = info; boundPurpose = purpose
        let support = access.observe(snapshot) { [weak self] change in
            guard let self, self.binding != nil else { return }
            switch change {
            case .focusOrDocument: self.invalidate()
            case .contentOrSelection:
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
                // A structural webpage change can reuse its editor and URL.
                // Until an engine-specific context can distinguish self-layout, stop automatic input.
                if self.target?.isWeb == true { self.invalidate() }
            }
        }
        if purpose == .continuous, snapshot.isWeb,
           !(snapshot.pageContextComplete && support.focus && support.content && support.page && access.matchesText("", utf16Start: snapshot.selectionLocation, at: snapshot) == true) {
            invalidate()
            throw NativeInputError.unobservablePage
        }
        return info
    }

    public func invalidate() {
        generation += 1
        let id = binding?.id
        binding = nil
        target = nil
        confirmedTail = nil
        access.stopObserving()
        if let id { Task { try? await store.invalidateBinding(id) } }
        if id != nil { onBindingInvalidated?() }
    }

    public func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
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
        if let startedAt, startedAt <= binding.boundAt { return .noNewText }
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
                // Any thrown AX timeout is treated as unverified, never retried.
                guard !Task.isCancelled else {
                    try? await store.completeDispatch(id: reservation.id, state: .cancelled)
                    return .cancelled
                }
                inFlightInsertion = (target, reservation.text)
                hasIssuedDispatch = true
                let dispatched = try access.dispatch(reservation.text, to: target)
                if !dispatched {
                    try? await store.completeDispatch(id: reservation.id, state: .cancelled)
                    invalidate()
                    return .cancelled
                }
                // Confirm the one attempt over a bounded window. This loop never dispatches again.
                for delay in [80, 80, 160, 240] {
                    do { try await Task.sleep(for: .milliseconds(delay)) } catch { break }
                    guard startGeneration == generation else { break }
                    if let after = access.verify(reservation.text, at: target) {
                        self.target = after
                        let tail = String(reservation.text.suffix(32))
                        confirmedTail = (tail, target.selectionLocation + reservation.text.utf16.count - tail.utf16.count)
                        try await store.completeDispatch(id: reservation.id, state: .confirmed)
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
        } catch {
            invalidate()
            return .failed(error.localizedDescription)
        }
    }

    private func validate(_ target: InputTargetSnapshot) throws {
        guard hasPermission else { throw NativeInputError.permission }
        let current = try access.snapshot()
        try current.checked()
        guard current == target else { throw NativeInputError.targetChanged }
        if let confirmedTail, access.matchesText(confirmedTail.text, utf16Start: confirmedTail.start, at: target) != true {
            throw NativeInputError.targetChanged
        }
    }
}
