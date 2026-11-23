import AppKit
import ApplicationServices

/// Observer registration can block on an unresponsive target. Keep it off the
/// main actor, and install callbacks on the main run loop without activating apps.
final class PanelWindowEvents: @unchecked Sendable {
    private let queue = DispatchQueue(label: "app.saytile.panel-window-events", qos: .utility)
    private let changed: @MainActor @Sendable () -> Void
    private var observers: [pid_t: AXObserver] = [:]
    private var registered: Set<String> = []
    private var stopped = false
    init(changed: @escaping @MainActor @Sendable () -> Void) { self.changed = changed }

    func update(_ windows: [PanelWindowAccess.Snapshot]) {
        queue.async { [self] in
            guard !stopped else { return }
            let wanted = Set(windows.map(\.pid))
            for pid in Set(observers.keys).subtracting(wanted) {
                if let observer = observers.removeValue(forKey: pid) {
                    CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .commonModes)
                }
                registered = registered.filter { !$0.hasPrefix("\(pid):") }
            }
            for pid in wanted where observers[pid] == nil {
                var observer: AXObserver?
                let callback: AXObserverCallback = { _, _, _, context in
                    guard let context else { return }
                    let owner = Unmanaged<PanelWindowEvents>.fromOpaque(context).takeUnretainedValue()
                    let changed = owner.changed
                    Task { @MainActor in changed() }
                }
                guard AXObserverCreate(pid, callback, &observer) == .success, let observer else { continue }
                observers[pid] = observer
                CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .commonModes)
                let app = AXUIElementCreateApplication(pid)
                AXUIElementSetMessagingTimeout(app, 0.06)
                AXObserverAddNotification(observer, app, kAXWindowCreatedNotification as CFString,
                    Unmanaged.passUnretained(self).toOpaque())
            }
            for window in windows where !registered.contains(window.stableKey) {
                guard let observer = observers[window.pid] else { continue }
                for notification in [kAXMovedNotification, kAXResizedNotification, kAXUIElementDestroyedNotification] {
                    AXObserverAddNotification(observer, window.element, notification as CFString,
                        Unmanaged.passUnretained(self).toOpaque())
                }
                registered.insert(window.stableKey)
            }
        }
    }
    func stop() async {
        await withCheckedContinuation { continuation in
            queue.async { [self] in
                stopped = true
                for observer in observers.values {
                    CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .commonModes)
                }
                observers.removeAll(); registered.removeAll()
                continuation.resume()
            }
        }
    }
}
