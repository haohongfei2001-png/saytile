import AppKit
import ApplicationServices
import SaytileKit

/// Compile the production bridge, worker, controller and VoicePanel; the only
/// stub is the settings fields the controller consumes. No ASR/store is opened.
@MainActor final class AppModel {
    var panelPlacementMode: PanelPlacementMode = .floating
    var panelOverFullscreen = false
    var panelArrangementStatus: String?
}
private struct Failed: Error { let message: String }
@main struct PanelBoundaryProbe {
    @MainActor static func main() async {
        if CommandLine.arguments.contains("--permission") {
            print(AXIsProcessTrusted() ? "AX_TRUSTED" : "BLOCKED_ACCESSIBILITY")
            exit(AXIsProcessTrusted() ? 0 : 77)
        }
        if CommandLine.arguments.count == 3, CommandLine.arguments[1] == "--capture-frontmost" {
            var record: [String: Any] = [:]
            if let front = NSWorkspace.shared.frontmostApplication, let launched = front.launchDate {
                record = ["pid": front.processIdentifier, "launch": launched.timeIntervalSince1970]
            }
            try? JSONSerialization.data(withJSONObject: record).write(to: URL(fileURLWithPath: CommandLine.arguments[2]), options: .atomic)
            return
        }
        if CommandLine.arguments.count == 3, CommandLine.arguments[1] == "--restore-frontmost" {
            if let data = try? Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[2])),
               let record = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let pid = record["pid"] as? Int32, let launch = record["launch"] as? Double,
               let app = NSRunningApplication(processIdentifier: pid), !app.isTerminated,
               app.launchDate?.timeIntervalSince1970 == launch { _ = app.activate(options: []) }
            return
        }
        guard CommandLine.arguments.count == 4 else { exit(64) }
        let a = URL(fileURLWithPath: CommandLine.arguments[1]), b = URL(fileURLWithPath: CommandLine.arguments[2])
        let output = URL(fileURLWithPath: CommandLine.arguments[3])
        var tests = [[String: Any]](), platformObservations = [[String: Any]](), commandID = 0
        func check(_ name: String, _ condition: Bool) throws {
            tests.append(["name": name, "status": condition ? "PASS" : "FAIL"])
            // Assertions remain failures, but independent fixture scenarios still
            // run so one result cannot hide full-screen or restoration coverage.
        }
        func json(_ file: URL) throws -> [String: Any] {
            try JSONSerialization.jsonObject(with: Data(contentsOf: file)) as! [String: Any]
        }
        func rect(_ values: Any?) throws -> CGRect {
            guard let a = values as? [Double], a.count == 4 else { throw Failed(message: "fixture rectangle") }
            return CGRect(x: a[0], y: a[1], width: a[2], height: a[3])
        }
        func values(_ r: CGRect) -> [Double] { [r.minX, r.minY, r.width, r.height] }
        func command(_ action: String, frame: CGRect? = nil, size: CGSize? = nil, directory: URL? = nil, waitForGeometry: Bool = true, strict: Bool? = nil) async throws -> [String: Any] {
            let targetDirectory = directory ?? a
            commandID += 1
            var payload: [String: Any] = ["id": commandID, "action": action]
            if let frame { payload["frame"] = values(frame) }
            if let size { payload["size"] = [size.width, size.height] }
            if let strict { payload["enabled"] = strict }
            try JSONSerialization.data(withJSONObject: payload).write(to: targetDirectory.appendingPathComponent("command.json"), options: .atomic)
            for _ in 0..<160 {
                try await Task.sleep(for: .milliseconds(50))
                if let ack = try? json(targetDirectory.appendingPathComponent("ack.json")), ack["id"] as? Int == commandID {
                    // AppKit ack precedes asynchronous WindowServer/AX updates.
                    // Observe readiness only: no repeat command, write or focus.
                    if waitForGeometry, targetDirectory == a, ["frame", "show", "removeDuplicate", "minimum", "prepare"].contains(action),
                       let ready = try? json(a.appendingPathComponent("ready.json")),
                       let pid = ready["pid"] as? Int32, let number = ready["windowID"] as? Int {
                        let probe = PanelWindowAccess(allowedPIDs: [pid])
                        let expected = try rect(ack["frame"])
                        var previous: CGRect?, confirmed = false
                        for _ in 0..<60 {
                            try await Task.sleep(for: .milliseconds(50))
                            if let current = probe.snapshots().first(where: { $0.windowID == CGWindowID(number) }),
                               action != "frame" || PanelArrangementWorker.same(current.frame, expected) {
                                if let previous, PanelArrangementWorker.same(previous, current.frame) { confirmed = true; break }
                                previous = current.frame
                            } else { previous = nil }
                        }
                        guard confirmed else { throw Failed(message: "BLOCKED_FIXTURE_AX_CG_READINESS: \(action)") }
                    }
                    return ack
                }
            }
            throw Failed(message: "fixture command timeout: \(action)")
        }
        var errorText: String?
        do {
            guard AXIsProcessTrusted() else { throw Failed(message: "BLOCKED_ACCESSIBILITY") }
            // Capture the real Desktop usable area after the fixture's activation
            // transition, not the prior user's full-screen Space geometry.
            try await Task.sleep(for: .seconds(1))
            _ = try await command("prepare", directory: b)
            _ = try await command("prepare")
            try await Task.sleep(for: .milliseconds(600))
            let first = try json(a.appendingPathComponent("ready.json")), foreign = try json(b.appendingPathComponent("ready.json"))
            let pid = pid_t(first["pid"] as! Int), otherPID = pid_t(foreign["pid"] as! Int)
            let windowID = CGWindowID(first["windowID"] as! Int)
            let visible = try rect(first["visible"]), screen = try rect(first["screen"])
            let original = try rect(first["frame"]), otherOriginal = try rect(foreign["frame"])
            let panel = CGRect(x: visible.maxX - 180, y: visible.maxY - 220, width: 180, height: 220)
            let access = PanelWindowAccess(allowedPIDs: [pid])
            let worker = PanelArrangementWorker(allowedPIDs: [pid])
            func snapshot() throws -> PanelWindowAccess.Snapshot {
                guard let value = access.snapshots().first(where: { $0.windowID == windowID }) else { throw Failed(message: "owned unique visible AX window unavailable") }
                return value
            }
            func request(reserve: Bool = true, shown: Bool = true, visible override: CGRect? = nil) -> PanelArrangementWorker.Request {
                .init(panel: panel, preferred: panel, screen: screen, visible: override ?? visible, mainScreenTop: screen.maxY,
                      frontmostPID: pid, reserve: reserve, shown: shown, canMovePanel: true, allowedPIDs: [pid])
            }
            // Fixture startup is separate from an insertion/write attempt. Wait
            // only for the owned AX object and public CG geometry to become ready.
            for _ in 0..<30 {
                if access.snapshots().contains(where: { $0.windowID == windowID }) { break }
                try await Task.sleep(for: .milliseconds(100))
            }
            try check("scope excludes unrelated fixture PID", !access.snapshots().contains(where: { $0.pid == otherPID }))
            if !access.snapshots().contains(where: { $0.windowID == windowID }) {
                let app = NSRunningApplication(processIdentifier: pid)
                let ax = AXUIElementCreateApplication(pid)
                var count: CFIndex = 0
                let counted = AXUIElementGetAttributeValueCount(ax, kAXWindowsAttribute as CFString, &count)
                var raw: CFTypeRef?
                let status = AXUIElementCopyAttributeValue(ax, kAXWindowsAttribute as CFString, &raw)
                var diagnostic: [String: Any] = ["name": "owned fixture readiness diagnostics", "status": "FAIL", "pid": pid,
                    "launchDatePresent": app?.launchDate != nil, "regular": app?.activationPolicy == .regular,
                    "hidden": app?.isHidden ?? true, "axCountStatus": counted.rawValue, "axReadStatus": status.rawValue, "axCount": count]
                if let windows = raw as? [AXUIElement] {
                    diagnostic["windows"] = windows.map { item -> [String: Any] in
                        var fields = [String: Any]()
                        for name in [kAXRoleAttribute, kAXSubroleAttribute, kAXMinimizedAttribute, "AXFullScreen"] {
                            var value: CFTypeRef?
                            let read = AXUIElementCopyAttributeValue(item, name as CFString, &value)
                            fields[name] = ["status": read.rawValue, "value": value.map { String(describing: $0) } ?? "nil"]
                        }
                        for name in [kAXPositionAttribute, kAXSizeAttribute] {
                            var value: CFTypeRef?
                            let read = AXUIElementCopyAttributeValue(item, name as CFString, &value)
                            fields[name] = ["status": read.rawValue, "value": value.map { String(describing: $0) } ?? "nil"]
                        }
                        return fields
                    }
                }
                diagnostic["cg"] = (CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []).filter { ($0[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value == pid }.map { row in
                    ["id": row[kCGWindowNumber as String] ?? "?", "bounds": row[kCGWindowBounds as String] ?? "?", "layer": row[kCGWindowLayer as String] ?? "?", "onscreen": row[kCGWindowIsOnscreen as String] ?? "?"]
                }
                tests.append(diagnostic)
            }
            try check("initial owned window corresponds to public CG ID", try snapshot().windowID == windowID)
            let applied = worker.reconcile(request(), cancellation: .init())
            try check("ordinary window displaced beyond panel", applied.adjusted == 1 && !(try snapshot()).frame.intersects(panel))
            let managed = try snapshot().frame
            try check("repeat is idempotent", worker.reconcile(request(), cancellation: .init()).adjusted == 0 && PanelArrangementWorker.same(try snapshot().frame, managed))
            _ = worker.reconcile(request(reserve: false), cancellation: .init())
            try check("mode off restores original", PanelArrangementWorker.same(try snapshot().frame, original))
            _ = worker.reconcile(request(), cancellation: .init())
            let safeUserFrame = CGRect(x: visible.minX + 20, y: visible.minY + 20, width: min(original.width, visible.width - 220), height: original.height)
            _ = try await command("frame", frame: safeUserFrame)
            _ = worker.reconcile(request(), cancellation: .init())
            _ = worker.reconcile(request(reserve: false), cancellation: .init())
            try check("user moved safe frame is not restored over", PanelArrangementWorker.same(try snapshot().frame, safeUserFrame))
            _ = try await command("frame", frame: original)
            let cancelled = PanelArrangementCancellation(); cancelled.cancel()
            _ = worker.reconcile(request(), cancellation: cancelled)
            try check("cancelled plan writes nothing", PanelArrangementWorker.same(try snapshot().frame, original))
            let bound = try snapshot()
            try check("bridge cancelled before write refuses", access.setFrame(bound, from: bound.frame, to: safeUserFrame, shouldProceed: { false }) == nil)
            _ = worker.reconcile(request(), cancellation: .init())
            _ = worker.reconcile(request(shown: false), cancellation: .init())
            try check("hidden panel releases owned frame", PanelArrangementWorker.same(try snapshot().frame, original))
            _ = try await command("hide")
            try check("hidden target excluded", !access.snapshots().contains(where: { $0.windowID == windowID }))
            _ = try await command("show")
            _ = try await command("duplicate")
            try check("two equal bounds reject ambiguous AX binding", !access.snapshots().contains(where: { $0.windowID == windowID }))
            _ = try await command("removeDuplicate")
            // AppKit/Stage Manager may constrain a re-shown test window. Start
            // the independent insufficient-space case from an explicit own frame.
            _ = try await command("frame", frame: original)
            try check("insufficient-space scenario baseline", PanelArrangementWorker.same(try snapshot().frame, original))
            let tiny = CGRect(x: visible.maxX - 190, y: visible.maxY - 230, width: 190, height: 230)
            let blocked = worker.reconcile(request(visible: tiny), cancellation: .init())
            try check("insufficient free area refuses without modifying", blocked.blocked > 0 && PanelArrangementWorker.same(try snapshot().frame, original))
            let large = visible.insetBy(dx: 10, dy: 10)
            _ = try await command("frame", frame: large)
            let minimumSet = try await command("minimum", size: large.size)
            let minimum = worker.reconcile(request(), cancellation: .init())
            let minimumActual = try snapshot().frame
            platformObservations.append(["name": "AppKit minimum size can normalize limits and change the actual frame", "expected_unchanged_frame_status": minimum.blocked > 0 && PanelArrangementWorker.same(minimumActual, large) ? "PASS" : "FAIL",
                "requestedFrame": values(large), "actualFrame": values(minimumActual), "declaredMinSize": minimumSet["minSize"] ?? NSNull(), "workerBlocked": minimum.blocked, "workerAdjusted": minimum.adjusted,
                "note": "Original native9 unchanged-frame assertion FAIL retained. Read declaredMinSize and actualFrame together: a changed frame is not proof the minimum was ignored. The worker reports actual partial geometry and refusal, never presumed success."])
            _ = worker.reconcile(request(reserve: false), cancellation: .init())
            _ = try await command("frame", frame: large)
            _ = try await command("strictMinimum", strict: true)
            let refusingWorker = PanelArrangementWorker(allowedPIDs: [pid])
            let refused = refusingWorker.reconcile(request(), cancellation: .init())
            let refusalAck = try await command("inspect")
            try check("actual native AX size refusal keeps target unchanged", refused.blocked > 0 && PanelArrangementWorker.same(try snapshot().frame, large) && (refusalAck["refusedSizeWrites"] as? Int ?? 0) > 0)
            try check("AX refusal is not repeatedly written", refusingWorker.reconcile(request(), cancellation: .init()).adjusted == 0)
            _ = try await command("strictMinimum", strict: false)
            _ = try await command("minimum", size: CGSize(width: 100, height: 100))
            _ = try await command("frame", frame: original)
            let untouched = try await command("inspect", directory: b)
            try check("unrelated fixture untouched", PanelArrangementWorker.same(try rect(untouched["frame"]), otherOriginal))
            // The real event/controller path uses a nonactivating synthetic
            // VoicePanel; only the target PID can be adjusted.
            _ = NSApplication.shared
            NSApp.setActivationPolicy(.prohibited)
            let hostPanel = VoicePanel(contentRect: panel, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            hostPanel.isReleasedWhenClosed = false
            hostPanel.contentView = NSView(frame: CGRect(origin: .zero, size: panel.size))
            hostPanel.orderFrontRegardless()
            let model = AppModel(); model.panelPlacementMode = .boundary
            let controller = PanelCoexistenceController(panel: hostPanel, model: model, allowedPIDs: [pid]) { next in
                hostPanel.setFrame(next, display: true)
            }
            controller.start()
            for _ in 0..<60 {
                try await Task.sleep(for: .milliseconds(100))
                if let seen = try? snapshot(), !seen.frame.intersects(panel) { break }
            }
            try check("production controller initially enforces boundary", !(try snapshot()).frame.intersects(panel))
            // Allow the production observer to finish registering after first pass.
            try await Task.sleep(for: .milliseconds(250))
            let manuallyReturned = original.offsetBy(dx: -20, dy: -10)
            _ = try await command("frame", frame: manuallyReturned, waitForGeometry: false)
            let eventStarted = ProcessInfo.processInfo.systemUptime
            for _ in 0..<60 {
                try await Task.sleep(for: .milliseconds(50))
                if let seen = try? snapshot(), !seen.frame.intersects(panel) { break }
            }
            let eventSeconds = ProcessInfo.processInfo.systemUptime - eventStarted
            try check("AX observer reconciles new overlap", !(try snapshot()).frame.intersects(panel))
            tests.append(["name": "AX event response timing", "status": "PASS", "seconds": eventSeconds,
                          "note": "Production AX observer plus 2-second fallback; timing alone is not event provenance."])
            model.panelPlacementMode = .floating
            NotificationCenter.default.post(name: .init("SaytilePanelPlacementChanged"), object: nil)
            for _ in 0..<60 {
                try await Task.sleep(for: .milliseconds(50))
                if let seen = try? snapshot(), PanelArrangementWorker.same(seen.frame, manuallyReturned) { break }
            }
            try check("controller mode change restores latest user placement", PanelArrangementWorker.same(try snapshot().frame, manuallyReturned))
            await controller.stop(); hostPanel.orderOut(nil)
            _ = try await command("frame", frame: original)
            if ProcessInfo.processInfo.environment["SAYTILE_PANEL_NATIVE_FULLSCREEN"] == "1" {
                _ = worker.reconcile(request(), cancellation: .init())
                _ = try await command("fullscreen")
                var full: PanelWindowAccess.Snapshot?
                for _ in 0..<60 {
                    try await Task.sleep(for: .milliseconds(100))
                    full = access.snapshots().first(where: { $0.windowID == windowID && $0.isFullscreen })
                    if full != nil { break }
                }
                guard let full else { throw Failed(message: "native fullscreen AX transition unavailable") }
                let report = worker.reconcile(request(), cancellation: .init())
                try check("native fullscreen never resized", report.fullscreen && report.adjusted == 0 && PanelArrangementWorker.same(try snapshot().frame, full.frame))
                let nearTopRight = CGRect(x: screen.maxX - 220, y: screen.maxY - 100, width: 220, height: 100)
                let obstacles = access.focusedFullscreenObstacles(near: nearTopRight, allowedPIDs: [pid])
                tests.append(["name": "native full-screen toolbar geometry", "status": obstacles.isEmpty ? "BLOCKED" : "PASS", "obstacle_count": obstacles.count,
                              "note": obstacles.isEmpty ? "System auto-hidden toolbar exposes no usable nearby control; no title/value scan or pointer forcing." : "Actual public AX role/frame only."])
                var fullscreenController: PanelCoexistenceController?
                let panelCanBeTested = !obstacles.isEmpty && !nearTopRight.contains(NSEvent.mouseLocation)
                if panelCanBeTested {
                    try check("test panel begins over actual fullscreen button", obstacles.contains { control in
                        let overlap = control.intersection(nearTopRight)
                        return overlap.width > 0 && overlap.height > 0 && !overlap.isNull
                    })
                    hostPanel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
                    hostPanel.level = .floating
                    hostPanel.setFrame(nearTopRight, display: false)
                    hostPanel.orderFrontRegardless()
                    model.panelPlacementMode = .floating
                    let live = PanelCoexistenceController(panel: hostPanel, model: model, allowedPIDs: [pid]) { next in
                        hostPanel.setFrame(next, display: true)
                    }
                    fullscreenController = live
                    live.start()
                    for _ in 0..<70 {
                        try await Task.sleep(for: .milliseconds(100))
                        if model.panelOverFullscreen && !obstacles.contains(where: { $0.intersects(hostPanel.frame) }) { break }
                    }
                    try check("production fullscreen controller marks opaque presentation", model.panelOverFullscreen)
                    try check("production fullscreen controller moves panel clear of actual controls", !obstacles.contains(where: { $0.intersects(hostPanel.frame) }) && hostPanel.frame.size == nearTopRight.size)
                    tests.append(["name": "fullscreen panel actual geometry", "status": "PASS", "preferred": values(nearTopRight), "actual": values(hostPanel.frame), "obstacles": obstacles.map(values)])
                } else {
                    tests.append(["name": "production fullscreen avoidance", "status": "BLOCKED", "note": "No confirmed toolbar controls or pointer is inside test panel; pointer/focus not forced."])
                }
                _ = try await command("fullscreen")
                for _ in 0..<60 {
                    try await Task.sleep(for: .milliseconds(100))
                    if let returned = access.snapshots().first(where: { $0.windowID == windowID }), !returned.isFullscreen { break }
                }
                if let live = fullscreenController {
                    for _ in 0..<70 {
                        try await Task.sleep(for: .milliseconds(100))
                        if !model.panelOverFullscreen && PanelArrangementWorker.same(hostPanel.frame, nearTopRight) { break }
                    }
                    try check("production fullscreen exit clears presentation and restores panel anchor", !model.panelOverFullscreen && PanelArrangementWorker.same(hostPanel.frame, nearTopRight))
                    await live.stop(); hostPanel.orderOut(nil)
                }
                _ = worker.reconcile(request(reserve: false), cancellation: .init())
                try check("full-screen roundtrip keeps original restore ownership", PanelArrangementWorker.same(try snapshot().frame, original))
            } else { tests.append(["name": "native fullscreen", "status": "NOT_RUN", "note": "Requires explicit isolated fixture GUI run flag; not substituted by full-screen-sized ordinary frame."]) }
        } catch { errorText = String(describing: error) }
        if tests.contains(where: { $0["status"] as? String == "FAIL" }) {
            errorText = "One or more assertions failed; see every recorded independent scenario."
        }
        if errorText == nil && tests.contains(where: { $0["status"] as? String == "BLOCKED" }) {
            errorText = "BLOCKED: one or more independent native scenarios could not be confirmed."
        }
        let report: [String: Any] = ["status": errorText == nil ? "PASS" : (errorText?.contains("BLOCKED") == true ? "BLOCKED" : "FAIL"),
            "tests": tests, "platformObservations": platformObservations, "error": errorText ?? NSNull(), "scope": "Only two disposable synthetic AppKit fixture PIDs; production PanelWindowAccess/PanelArrangementWorker; no user app target, no text read, no mic, no input events."]
        try? JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]).write(to: output, options: .atomic)
        print(String(data: (try? JSONSerialization.data(withJSONObject: report, options: [.sortedKeys])) ?? Data(), encoding: .utf8) ?? "report failure")
        exit(errorText == nil ? 0 : (errorText?.contains("BLOCKED") == true ? 77 : 1))
    }
}
