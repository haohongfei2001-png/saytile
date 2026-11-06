import AppKit

/// Observe identity transitions only, never another application's UI or text.
final class FixtureActivationAudit: @unchecked Sendable {
    private let lock = NSLock()
    private let owned: Set<pid_t>
    private var ownedActivated = false
    private var outsideActivations = 0
    private var token: NSObjectProtocol?
    @MainActor init(fixturePID: pid_t) {
        owned = [fixturePID, ProcessInfo.processInfo.processIdentifier]
        token = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didActivateApplicationNotification,
            object: nil, queue: .main) { [weak self] notification in
            guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
            self?.record(app.processIdentifier)
        }
    }
    private func record(_ pid: pid_t) {
        lock.lock(); defer { lock.unlock() }
        if owned.contains(pid) { ownedActivated = true } else { outsideActivations += 1 }
    }
    @MainActor func finish() -> (ownedActivated: Bool, outsideActivations: Int) {
        if let token { NSWorkspace.shared.notificationCenter.removeObserver(token); self.token = nil }
        let now = NSWorkspace.shared.frontmostApplication?.processIdentifier
        lock.lock(); defer { lock.unlock() }
        return (ownedActivated || now.map { owned.contains($0) } == true, outsideActivations)
    }
}
