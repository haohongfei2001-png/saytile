import Foundation
import CoreGraphics
@preconcurrency import AVFoundation

struct AudioSessionSnapshot: Sendable, Equatable {
    let onConsole: Bool
    let loginComplete: Bool
    let screenLocked: Bool
    static func current() -> AudioSessionSnapshot? {
        guard let session = CGSessionCopyCurrentDictionary() as? [String: Any],
              let onConsole = session[kCGSessionOnConsoleKey as String] as? Bool,
              let loginComplete = session[kCGSessionLoginDoneKey as String] as? Bool else { return nil }
        // WindowServer compatibility field; not a documented stable dictionary key.
        // Only these booleans are read; account names and other session metadata are never retained.
        let locked = (session["CGSSessionScreenIsLocked"] as? Bool) ?? false
        return .init(onConsole: onConsole, loginComplete: loginComplete, screenLocked: locked)
    }
}

/// Independent stop reasons prevent wake or a stale unlock event from cancelling
/// another stop reason. A missing WindowServer snapshot never authorizes resume.
struct AudioLifecycleGate: Sendable, Equatable {
    var sleeping = false
    var sessionInactive = false
    private(set) var snapshot: AudioSessionSnapshot?
    private(set) var lockNotification = false
    var permitsCapture: Bool {
        guard let snapshot else { return false }
        return !sleeping && !sessionInactive && !lockNotification && snapshot.onConsole && snapshot.loginComplete && !snapshot.screenLocked
    }
    mutating func refresh(_ value: AudioSessionSnapshot?) {
        // Recover a missed unlock only after an independently observed locked →
        // unlocked WindowServer transition, not from an arbitrary notification.
        if snapshot?.screenLocked == true, let value,
           value.onConsole && value.loginComplete && !value.screenLocked { lockNotification = false }
        snapshot = value
    }
    mutating func receivedLock() { lockNotification = true }
    mutating func receivedUnlock(snapshot value: AudioSessionSnapshot?) {
        snapshot = value
        // Treat the notification as a hint, not as authority to turn the mic on.
        if let value, value.onConsole && value.loginComplete && !value.screenLocked { lockNotification = false }
    }
    var reason: String {
        if sleeping { return "Mac 已睡眠" }
        if lockNotification || snapshot?.screenLocked == true { return "屏幕已锁定" }
        return "当前用户会话不可用"
    }
    static func requiresPermissionSuspension(state: CaptureState, authorization: AVAuthorizationStatus) -> Bool {
        // The first system prompt may legitimately remain open longer than the
        // polling interval. Only this pending start may await an undecided result;
        // a reset/revocation during actual capture must still stop immediately.
        state.isRunning && authorization != .authorized && !(state == .starting && authorization == .notDetermined)
    }
}

@MainActor
final class AudioLockEventBridge {
    static let locked = Notification.Name("com.apple.screenIsLocked")
    static let unlocked = Notification.Name("com.apple.screenIsUnlocked")
    private let center: NotificationCenter
    private var observers: [NSObjectProtocol] = []
    init(center: NotificationCenter = DistributedNotificationCenter.default(), handler: @escaping @MainActor @Sendable (Bool) async -> Void) {
        self.center = center
        for (name, isLocked) in [(Self.locked, true), (Self.unlocked, false)] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { @Sendable _ in
                Task { @MainActor in await handler(isLocked) }
            })
        }
    }
    func invalidate() { observers.forEach(center.removeObserver); observers.removeAll() }
}
