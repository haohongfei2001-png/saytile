import AppKit
import ApplicationServices
import SaytileKit

/// AX work is serial and off the UI/audio queues. A stale plan cannot keep
/// moving windows after the user hides the panel or changes mode.
final class PanelArrangementCancellation: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false
    func cancel() { lock.lock(); cancelled = true; lock.unlock() }
    var isCancelled: Bool { lock.lock(); defer { lock.unlock() }; return cancelled }
}

final class PanelArrangementWorker: @unchecked Sendable {
    struct Request: Sendable {
        let panel: CGRect
        let preferred: CGRect
        let screen: CGRect
        let visible: CGRect
        let mainScreenTop: CGFloat
        let frontmostPID: pid_t
        let reserve: Bool
        let shown: Bool
        let canMovePanel: Bool
        let allowedPIDs: Set<pid_t>?
    }
    struct Result: Sendable {
        var fullscreen = false
        var panel: CGRect?
        var blocked = 0
        var adjusted = 0
        var trusted = false
        var watched: [PanelWindowAccess.Snapshot] = []
    }
    private struct Lease {
        let window: PanelWindowAccess.Snapshot
        let original: CGRect
        var applied: CGRect
    }
    // Accessed only by one in-flight work request. Never persist AX identities
    // across process launches, Spaces or app termination.
    private var leases: [String: Lease] = [:]
    private let access: PanelWindowAccess
    init(allowedPIDs: Set<pid_t>? = nil) { access = PanelWindowAccess(allowedPIDs: allowedPIDs) }
    private var refused: [String: (CGRect, CGRect)] = [:]
    private var unresolvedRestores: Set<String> = []

    func reconcile(_ request: Request, cancellation: PanelArrangementCancellation) -> Result {
        var result = Result()
        result.trusted = AXIsProcessTrusted()
        if request.shown {
            // WindowServer geometry works without screen capture permission.
            // This reads bounds and owner PID only, never a window image/title.
            result.fullscreen = fullscreenWindow(pid: request.frontmostPID, screen: request.screen,
                                                mainScreenTop: request.mainScreenTop)
        }
        let scope = request.reserve ? request.allowedPIDs : Set([request.frontmostPID])
        let snapshots = result.trusted && request.shown ? access.snapshots(allowedPIDs: scope) : []
        result.watched = snapshots
        let foreground = snapshots.filter { $0.pid == request.frontmostPID && $0.frame.intersects(request.screen) }
        if foreground.contains(where: { $0.isFullscreen && $0.frame.intersection(request.screen).width > request.screen.width * 0.6 }) {
            result.fullscreen = true
        } else if foreground.contains(where: { $0.standardWindow && !$0.isFullscreen &&
            abs($0.frame.width - request.screen.width) <= 2 && abs($0.frame.height - request.screen.height) <= 2 }) {
            // A trusted AX answer outranks the geometry fallback when menu bar
            // and Dock auto-hide let an ordinary maximized window fill a screen.
            result.fullscreen = false
        }
        let reserving = request.reserve && request.shown && !result.fullscreen
        // Restore only geometry still owned by us. A user's intervening move
        // transfers ownership back, so mode-off must never undo that move.
        for (key, lease) in leases {
            guard !cancellation.isCancelled else { return result }
            // Entering another Space or fullscreen temporarily hides/replaces
            // geometry. Keep the original until the same ordinary window returns.
            guard let current = access.read(lease.window), !current.isFullscreen else { continue }
            guard Self.same(current.frame, lease.applied) else {
                leases.removeValue(forKey: key); unresolvedRestores.remove(key); continue
            }
            let stillRequired = reserving && lease.original.intersects(request.panel.insetBy(dx: -8, dy: -8))
            if !stillRequired {
                guard !unresolvedRestores.contains(key) else { result.blocked += 1; continue }
                if let actual = access.setFrame(current, from: lease.applied, to: lease.original,
                                               shouldProceed: { !cancellation.isCancelled }) {
                    if Self.same(actual, lease.original) { leases.removeValue(forKey: key) }
                    else { leases[key]?.applied = actual; unresolvedRestores.insert(key); result.blocked += 1 }
                } else if !cancellation.isCancelled {
                    unresolvedRestores.insert(key); result.blocked += 1
                }
            }
        }
        guard !cancellation.isCancelled else { return result }
        if reserving {
            for snapshot in snapshots where snapshot.standardWindow && !snapshot.isFullscreen {
                guard !cancellation.isCancelled else { break }
                guard snapshot.frame.intersects(request.panel), snapshot.frame.intersects(request.visible) else { continue }
                let frame = snapshot.frame
                if let failed = refused[snapshot.stableKey], Self.same(frame, failed.0), Self.same(request.panel, failed.1) {
                    result.blocked += 1; continue
                }
                guard let target = PanelCoexistenceGeometry.ordinaryWindow(frame, excluding: request.panel,
                        visibleFrame: request.visible) else { result.blocked += 1; continue }
                guard !Self.same(frame, target) else { continue }
                let actual = access.setFrame(snapshot, from: frame, to: target,
                                             shouldProceed: { !cancellation.isCancelled })
                if let actual, !Self.same(frame, actual) {
                    let original = leases[snapshot.stableKey]?.original ?? frame
                    leases[snapshot.stableKey] = Lease(window: snapshot, original: original, applied: actual)
                    result.adjusted += 1
                }
                if actual.map({ !Self.same($0, target) || $0.intersects(request.panel) }) ?? true {
                    // Do not fight an application's minimum size with endless
                    // retries. A later genuine geometry change allows one plan.
                    refused[snapshot.stableKey] = (actual ?? frame, request.panel)
                    result.blocked += 1
                } else { refused.removeValue(forKey: snapshot.stableKey) }
            }
        } else { refused.removeAll() }
        // Keep leases from closed Spaces for conditional restoration if they
        // return, but discard terminated apps without touching a new PID owner.
        leases = leases.filter { NSRunningApplication(processIdentifier: $0.value.window.pid)?.isTerminated == false }
        if result.fullscreen && request.shown && request.canMovePanel && result.trusted && !cancellation.isCancelled {
            let controls = access.focusedFullscreenObstacles(near: request.preferred,
                allowedPIDs: request.allowedPIDs ?? [request.frontmostPID])
            result.panel = PanelCoexistenceGeometry.fullscreenPanel(preferred: request.preferred,
                current: request.panel, avoiding: controls, visibleFrame: request.visible)
        }
        return result
    }

    private func fullscreenWindow(pid: pid_t, screen: CGRect, mainScreenTop: CGFloat) -> Bool {
        guard pid > 0,
              let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else { return false }
        return windows.contains { row in
            guard row[kCGWindowOwnerPID as String] as? pid_t == pid,
                  row[kCGWindowLayer as String] as? Int == 0,
                  let bounds = row[kCGWindowBounds as String] as? [String: Any],
                  let cg = CGRect(dictionaryRepresentation: bounds as CFDictionary) else { return false }
            let frame = CGRect(x: cg.minX, y: mainScreenTop - cg.maxY, width: cg.width, height: cg.height)
            // A maximized ordinary window leaves menu/Dock space and does not
            // qualify. Native fullscreen and borderless fullscreen do.
            return abs(frame.minX - screen.minX) <= 2 && abs(frame.minY - screen.minY) <= 2
                && abs(frame.width - screen.width) <= 2 && abs(frame.height - screen.height) <= 2
        }
    }
    static func same(_ a: CGRect, _ b: CGRect) -> Bool {
        abs(a.minX-b.minX) <= 0.25 && abs(a.minY-b.minY) <= 0.25 && abs(a.width-b.width) <= 0.25 && abs(a.height-b.height) <= 0.25
    }
}

/// Per-panel coexistence. No input events, window activation, screenshot
/// collection, window titles, document text or microphone access.
@MainActor
final class PanelCoexistenceController {
    private weak var panel: VoicePanel?
    private weak var model: AppModel?
    private let worker: PanelArrangementWorker
    private let applyPanel: (CGRect) -> Void
    private let allowedPIDs: Set<pid_t>?
    private var observers: [(NotificationCenter, NSObjectProtocol)] = []
    private var windowEvents: PanelWindowEvents?
    private var timer: Timer?
    private var pending: Task<Void, Never>?
    private var inFlight: Task<Void, Never>?
    private var cancellation = PanelArrangementCancellation()
    private var generation = 0
    private var stopped = false
    private var rerun = false
    private var preferred: CGRect
    private var lastExternalPID: pid_t = 0
    private var lastMovedAt = Date.distantPast
    private var applying = false
    private var automaticallyDisplaced = false

    init(panel: VoicePanel, model: AppModel, allowedPIDs: Set<pid_t>? = nil, applyPanel: @escaping (CGRect) -> Void) {
        self.panel = panel; self.model = model; self.allowedPIDs = allowedPIDs
        self.applyPanel = applyPanel; preferred = panel.frame
        worker = PanelArrangementWorker(allowedPIDs: allowedPIDs)
    }
    func start() {
        windowEvents = PanelWindowEvents { [weak self] in self?.windowGeometryChanged() }
        let workspace = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didActivateApplicationNotification, NSWorkspace.activeSpaceDidChangeNotification,
                     NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification,
                     NSWorkspace.didWakeNotification] {
            observe(workspace, name)
        }
        observe(.default, .init("SaytilePanelPlacementChanged"))
        observe(.default, NSApplication.didChangeScreenParametersNotification)
        // Events handle ordinary changes; a tolerant low-frequency fallback
        // detects AX permission restoration and apps without notifications.
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
        timer?.tolerance = 0.5
        refresh()
    }
    private func observe(_ center: NotificationCenter, _ name: Notification.Name) {
        let token = center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.changed() }
        }
        observers.append((center, token))
    }
    private func windowGeometryChanged() {
        // AX emits moved/resized for our own writes too. Such observations
        // schedule a new read, never cancel the resize/move halfway through.
        // User mode, visibility and Space decisions still invalidate immediately.
        guard !stopped else { return }
        if inFlight != nil { rerun = true; return }
        pending?.cancel()
        pending = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(140))
            guard !Task.isCancelled else { return }
            self?.refresh()
        }
    }
    func changed(userPlacement: Bool = false) {
        guard !stopped else { return }
        if userPlacement, !applying, let panel {
            preferred = panel.frame
            automaticallyDisplaced = false
            lastMovedAt = Date()
        }
        generation += 1
        cancellation.cancel()
        pending?.cancel()
        pending = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(140))
            guard !Task.isCancelled else { return }
            self?.refresh()
        }
    }
    private func refresh() {
        guard !stopped, let panel, let model, let screen = panel.screen ?? NSScreen.main else { return }
        guard !panel.draggingPlacement, !panel.inLiveResize, NSEvent.pressedMouseButtons == 0 else { return }
        guard inFlight == nil else { rerun = true; return }
        let pid = NSWorkspace.shared.frontmostApplication?.processIdentifier ?? 0
        if pid != ProcessInfo.processInfo.processIdentifier { lastExternalPID = pid }
        let token = PanelArrangementCancellation(); cancellation = token
        let currentGeneration = generation
        let request = PanelArrangementWorker.Request(panel: panel.frame, preferred: preferred,
            screen: screen.frame, visible: screen.visibleFrame, mainScreenTop: NSScreen.screens.first?.frame.maxY ?? 0,
            frontmostPID: lastExternalPID, reserve: model.panelPlacementMode == .boundary,
            shown: panel.isVisible, canMovePanel: !panel.isKeyWindow && !panel.frame.contains(NSEvent.mouseLocation)
                && Date().timeIntervalSince(lastMovedAt) > 0.8, allowedPIDs: allowedPIDs)
        let worker = worker
        inFlight = Task { [weak self] in
            let result = await Task.detached(priority: .utility) { worker.reconcile(request, cancellation: token) }.value
            guard let self else { return }
            self.inFlight = nil
            if !self.stopped, self.generation == currentGeneration, !token.isCancelled {
                self.apply(result, request: request)
            }
            if self.rerun || self.generation != currentGeneration {
                self.rerun = false; self.refresh()
            }
        }
    }
    private func apply(_ result: PanelArrangementWorker.Result, request: PanelArrangementWorker.Request) {
        guard let panel, let model else { return }
        if model.panelOverFullscreen != result.fullscreen { model.panelOverFullscreen = result.fullscreen }
        let status: String?
        if model.panelPlacementMode == .boundary {
            status = !result.trusted ? "需要辅助功能权限，当前仍为浮板。"
                : result.blocked > 0 ? "部分窗口不支持调整，或可用空间不足。"
                : result.fullscreen ? "全屏时保留浮板，自动避让可确认的控件。" : nil
        } else {
            status = result.blocked > 0 ? "部分窗口未能自动恢复，可手动调整。" : nil
        }
        // Idle polling must not publish identical values and re-render the live
        // transcript. The monitor has no reason to wake the text view at rest.
        if model.panelArrangementStatus != status { model.panelArrangementStatus = status }
        if !panel.draggingPlacement && !panel.inLiveResize && NSEvent.pressedMouseButtons == 0 && !panel.isKeyWindow {
            var target = result.panel
            if automaticallyDisplaced && !result.fullscreen { target = preferred }
            if let target, !PanelArrangementWorker.same(panel.frame, target),
               PanelArrangementWorker.same(panel.frame, request.panel) {
                applying = true; applyPanel(target); applying = false
                automaticallyDisplaced = result.fullscreen
                lastMovedAt = Date()
            }
        }
        windowEvents?.update(result.watched)
    }
    func stop() async {
        stopped = true; cancellation.cancel(); pending?.cancel(); timer?.invalidate()
        for (center, observer) in observers { center.removeObserver(observer) }
        observers.removeAll()
        await windowEvents?.stop()
        windowEvents = nil
        await inFlight?.value
        if let panel, let screen = panel.screen ?? NSScreen.main {
            let request = PanelArrangementWorker.Request(panel: panel.frame, preferred: preferred,
                screen: screen.frame, visible: screen.visibleFrame, mainScreenTop: NSScreen.screens.first?.frame.maxY ?? 0,
                frontmostPID: 0, reserve: false, shown: false, canMovePanel: false, allowedPIDs: allowedPIDs)
            let worker = worker
            _ = await Task.detached(priority: .utility) { worker.reconcile(request, cancellation: .init()) }.value
        }
    }
}
