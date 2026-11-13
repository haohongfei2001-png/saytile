import AppKit
#if SAYTILE_PACKAGE_PROBE
@testable import SaytileKit
#endif
import ApplicationServices
import Darwin

private struct BatchFailure: Error { let message: String }
private func inputIdleSeconds() -> Double {
    // Only event ages are queried. No event tap, key codes, text, coordinates or payloads.
    let types: [CGEventType] = [.keyDown, .keyUp, .flagsChanged, .mouseMoved, .leftMouseDown, .leftMouseUp,
        .rightMouseDown, .rightMouseUp, .otherMouseDown, .otherMouseUp, .leftMouseDragged, .rightMouseDragged,
        .otherMouseDragged, .scrollWheel, .tabletPointer, .tabletProximity]
    return types.map { CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: $0) }.min() ?? 0
}
private func immediateAbort(_ message: String) -> Never {
    FileHandle.standardOutput.write(Data(("FOREGROUND_ABORT " + message + "; no focus restoration\n").utf8))
    Darwin._exit(70)
}

@MainActor private final class ForegroundSafety {
    let originalPID: pid_t
    let lastInputTime: Double
    var expectedPID: pid_t?
    private var activationObserver: NSObjectProtocol?
    private let timer: any DispatchSourceTimer
    init() throws {
        guard AXIsProcessTrusted() else { throw BatchFailure(message: "NOT_RUN existing AX permission unavailable; no prompt") }
        let idle = inputIdleSeconds()
        guard idle.isFinite, idle >= 60, let front = NSWorkspace.shared.frontmostApplication else {
            throw BatchFailure(message: "NOT_RUN keyboard/mouse idle must be at least 60 seconds")
        }
        print("FOREGROUND_STAGE ax_trusted=true idle_checked=true"); fflush(nil)
        originalPID = front.processIdentifier
        lastInputTime = ProcessInfo.processInfo.systemUptime - idle
        let baseline = lastInputTime
        timer = DispatchSource.makeTimerSource(queue: .global(qos: .userInteractive))
        timer.schedule(deadline: .now(), repeating: .milliseconds(20))
        timer.setEventHandler { @Sendable in
            if ProcessInfo.processInfo.systemUptime - inputIdleSeconds() > baseline + 0.002 {
                immediateAbort("keyboard/mouse activity")
            }
        }
        timer.resume()
        activationObserver = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] notification in
            let pid = (notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?.processIdentifier
            Task { @MainActor [weak self] in
                guard let self, let expected = self.expectedPID, let pid, pid != expected else { return }
                immediateAbort("foreground left fixture")
            }
        }
        print("FOREGROUND_STAGE safety_timer_and_activation_observer_installed"); fflush(nil)
        print("FOREGROUND_PREFLIGHT existing_AX=true idle_seconds=\(Int(idle)); original_pid=\(originalPID); contents_not_read=true"); fflush(nil)
    }
    func check(_ pid: pid_t) throws {
        guard ProcessInfo.processInfo.systemUptime - inputIdleSeconds() <= lastInputTime + 0.002 else { immediateAbort("keyboard/mouse activity") }
        guard NSWorkspace.shared.frontmostApplication?.processIdentifier == pid else { immediateAbort("foreground left fixture") }
    }
    func selectFixture(_ pid: pid_t) throws -> AXInputSelection {
        try check(pid)
        // The real production resolver chooses frontmost app/window/editor. The thin
        // allowlist rejects a different PID before AXInputAccess reads semantic text.
        let selection = try AXInputAccess.frontmostSelection()
        guard selection.application.processIdentifier == pid else { immediateAbort("resolver returned non-fixture PID") }
        try check(pid)
        return selection
    }
    @discardableResult func restoreIfSafe() async -> Bool {
        defer {
            timer.cancel()
            if let activationObserver { NSWorkspace.shared.notificationCenter.removeObserver(activationObserver) }
        }
        guard let expected = expectedPID else { return false }
        guard NSWorkspace.shared.frontmostApplication?.processIdentifier == expected,
              ProcessInfo.processInfo.systemUptime - inputIdleSeconds() <= lastInputTime + 0.002 else {
            print("FOREGROUND_NOT_RESTORED activity or foreign focus; no reactivation")
            return false
        }
        expectedPID = nil
        guard let original = NSRunningApplication(processIdentifier: originalPID), original.activate(options: []) else {
            print("FOREGROUND_NOT_RESTORED original PID unavailable or activation refused")
            return false
        }
        for _ in 0..<50 {
            let current = NSWorkspace.shared.frontmostApplication?.processIdentifier
            if current == originalPID {
                print("FOREGROUND_RESTORED original_pid=\(originalPID); confirmed_by_PID_only=true"); fflush(nil)
                return true
            }
            if current != expected {
                print("FOREGROUND_NOT_RESTORED another app gained focus; no retry")
                return false
            }
            try? await Task.sleep(for: .milliseconds(20))
        }
        print("FOREGROUND_NOT_RESTORED activation not confirmed; no retry")
        return false
    }
}

@main struct AXForegroundBatchProbe {
    @MainActor static func command(_ target: String, _ command: String) throws -> [String: Any] {
        let data = try JSONSerialization.data(withJSONObject: ["target": target, "command": command])
        FileHandle.standardOutput.write(Data("FIXTURE_RPC ".utf8) + data + Data([10]))
        guard let line = readLine(), let bytes = line.data(using: .utf8), let response = try JSONSerialization.jsonObject(with: bytes) as? [String: Any] else { throw BatchFailure(message: "Fixture IPC unavailable") }
        guard (response["error"] as? String ?? "").isEmpty else { throw BatchFailure(message: "Fixture IPC error") }
        if command == "state", let value = response["value"] as? String, let state = value.data(using: .utf8) { return (try JSONSerialization.jsonObject(with: state) as? [String: Any]) ?? [:] }
        return response
    }
    @MainActor private static func webRepairs(access: AXInputAccess, safety: ForegroundSafety, pid: pid_t) async throws {
        for scenario in ["longer", "shorter", "manualEdit", "blur", "restart"] {
            try safety.check(pid)
            _ = try command("web", "restore")
            try await Task.sleep(for: .milliseconds(200))
            let root = FileManager.default.temporaryDirectory.appendingPathComponent("saytile-owned-web-" + UUID().uuidString)
            defer { try? FileManager.default.removeItem(at: root) }
            let store = try SaytileStore(directory: root)
            let input = NativeInputCoordinator(store: store, access: access)
            let binding = try await input.bindCurrentTarget()
            let record = try await store.createRecording()
            let ticket = try await store.beginFusionRecognition(recordingID: record.id)
            let asr = ModelConfiguration(purpose: .chineseASR, provider: .qwenMessage, model: "owned-fixture-no-network")
            let reviewer = ModelConfiguration(purpose: .textFusion, provider: .openAIResponses, model: "fixture-text-review")
            try await store.configureFusionRequirements(ticket: ticket, configurations: [asr, reviewer])
            let run = try await store.beginModelRun(ticket: ticket, configuration: asr)
            func publish(_ text: String, sequence: Int64) async throws -> FusionPublication {
                let c = RecognitionCandidate(run: run, sequence: sequence, text: text,
                    stableUTF16Length: text.utf16.count, audioEndSeconds: 1, isComplete: true)
                guard try await store.appendRecognitionCandidate(c) else { throw BatchFailure(message: "fixture candidate stale") }
                let prefix = try await store.fusionReservedPrefix(recordingID: record.id)
                let proposal = try PrecisionFusion.validateSelection(spans: [.init(candidateID: c.id, utf16Start: 0, utf16End: text.utf16.count)],
                    candidates: [c], committedPrefix: prefix, unresolved: false)
                return try await store.publishFusion(ticket: ticket, proposal: proposal)
            }
            let original = scenario == "shorter" ? "500👩🏽‍💻" : "50😀"
            let replacement = scenario == "shorter" ? "50😀" : "500👩🏽‍💻"
            guard let first = try await publish(original, sequence: 1).revision,
                  await input.insertStable(recordingID: record.id, revisionID: first.id, stableUTF16End: original.utf16.count,
                                           recordingStartedAt: record.createdAt) == .confirmed,
                  try command("web", "state")["text"] as? String == "PREFIX|" + original + "SUFFIX" else {
                throw BatchFailure(message: "web " + scenario + " first owned range unconfirmed")
            }
            _ = try await publish(replacement, sequence: 2)
            guard let correction = try await store.ownedCorrectionCandidates(bindingID: binding.id).first else {
                throw BatchFailure(message: "web " + scenario + " no stored correction")
            }
            if scenario == "blur" || scenario == "manualEdit" { _ = try command("web", scenario) }
            let before = try command("web", "state")["text"] as? String
            let result: NativeInputResult
            if scenario == "restart" {
                guard try await store.reserveOwnedCorrection(bindingID: binding.id, revision: correction, targetStart: 7, expectedText: original) != nil else {
                    throw BatchFailure(message: "could not reserve interrupted correction")
                }
                input.invalidate()
                try await store.close()
                let reopened = try SaytileStore(directory: root)
                let restarted = NativeInputCoordinator(store: reopened, access: access)
                result = await restarted.repairOwned(revision: correction)
                try await reopened.close()
            } else {
                result = await input.repairOwned(revision: correction)
                input.invalidate()
                try await store.close()
            }
            let after = try command("web", "state")
            let allowed = scenario == "longer" || scenario == "shorter"
            let expected = allowed ? "PREFIX|" + replacement + "SUFFIX" : before
            guard allowed == (result == .confirmed), result != .unverified, after["text"] as? String == expected,
                  after["sends"] as? Int == 0 else { throw BatchFailure(message: "web " + scenario + " " + String(describing: result)) }
            print("PASS foreground WKWebView " + scenario + " exact DOM, intact prefix/suffix, zero sends")
        }
    }

    @MainActor private static func webReservationBoundaries(access: AXInputAccess, safety: ForegroundSafety, pid: pid_t) async throws {
        for change in ["silentContext", "holdAX"] {
            try safety.check(pid)
            _ = try command("web", "restore") // Start a new case with no live binding.
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            defer { try? FileManager.default.removeItem(at: directory) }
            let store = try SaytileStore(directory: directory)
            let trace = FixtureAccessTrace(access)
            let input = NativeInputCoordinator(store: store, access: trace)
            try await bindOwnedField(input, trace: trace, original: "PREFIX|SUFFIX", caret: 7, pid: pid)
            let record = try await store.createRecording()
            let revision = try await store.saveEdit(recordingID: record.id, text: "你好😀")
            var reads = 0
            trace.stage = change
            trace.beforeSnapshot = {
                reads += 1
                if reads == 2 { _ = try command("web", change) }
            }
            let result = await input.insertStable(recordingID: record.id, revisionID: revision.id,
                stableUTF16End: revision.text.utf16.count, recordingStartedAt: record.createdAt)
            trace.beforeSnapshot = nil
            let state = try command("web", "state")
            guard reads == 2, result == .cancelled, input.binding == nil, trace.writes == 0,
                  state["text"] as? String == "PREFIX|SUFFIX", state["selectionStart"] as? Int == 7,
                  state["selectionEnd"] as? Int == 7, state["sends"] as? Int == 0 else {
                throw BatchFailure(message: "WKWebView pre-write protection " + change + " " + String(describing: result))
            }
            try await store.close()
            print("PASS foreground WKWebView", change, "cancelled after reservation; zero writes, original DOM and caret, zero sends")
        }
    }

    @MainActor private static func nativeBoundaries(access: AXInputAccess, safety: ForegroundSafety, pid: pid_t) async throws {
        for scenario in ["ignored-write", "manual-edit", "cancel", "other-window"] {
            _ = try command("native", "restore")
            try await Task.sleep(for: .milliseconds(180))
            try safety.check(pid)
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent("saytile-foreground-fence-" + UUID().uuidString)
            defer { try? FileManager.default.removeItem(at: directory) }
            let store = try SaytileStore(directory: directory)
            let coordinator = NativeInputCoordinator(store: store, access: access)
            try await coordinator.bindCurrentTarget()
            let initial = try access.snapshot()
            let record = try await store.createRecording()
            let rev = try await store.saveEdit(recordingID: record.id, text: "你好😀")
            let before = try command("native", "state")
            switch scenario {
            case "other-window": _ = try command("native", "otherWindow")
            case "manual-edit": _ = try command("native", "manualEdit")
            case "cancel": coordinator.invalidate()
            default: _ = try command("native", "ignoreNextWrite")
            }
            if scenario == "other-window" {
                try await Task.sleep(for: .milliseconds(200))
                guard try access.snapshot().windowID != initial.windowID else { throw BatchFailure(message: "owned window did not change") }
            }
            func attempt() async -> NativeInputResult {
                await coordinator.insertStable(recordingID: record.id, revisionID: rev.id,
                    stableUTF16End: rev.text.utf16.count, recordingStartedAt: record.createdAt)
            }
            let first = await attempt(), second = await attempt()
            let after = try command("native", "state")
            let delta = (after["selectedTextWrites"] as? Int ?? -100) - (before["selectedTextWrites"] as? Int ?? 100)
            let ignored = scenario == "ignored-write"
            guard first != .confirmed, (first == .unverified) == ignored, second != .confirmed, second != .unverified,
                  delta == (ignored ? 1 : 0), after["text"] as? String == (scenario == "manual-edit" ? "PREFIX|我的改字SUFFIX" : "PREFIX|SUFFIX"),
                  after["sends"] as? Int == 0, scenario != "other-window" || after["otherIntact"] as? Bool == true else { throw BatchFailure(message: "native " + scenario + " safety failed") }
            coordinator.invalidate(); try await store.close()
            print("PASS foreground native " + scenario + " no replay, no wrong window, zero sends")
        }
    }

    @MainActor static func main() async {
        NSApplication.shared.setActivationPolicy(.prohibited)
        guard CommandLine.arguments.count == 4, CommandLine.arguments[1] == "--allow-foreground",
              ProcessInfo.processInfo.environment["SAYTILE_ALLOW_FOREGROUND_INPUT_FIXTURES"] == "1",
              let nativePID = Int32(CommandLine.arguments[2]), let webPID = Int32(CommandLine.arguments[3]), nativePID != webPID else {
            print("NOT_RUN explicit --allow-foreground and environment opt-in required"); exit(64)
        }
        // The parent runner supplies only its two just-created, known fixture executables.
        for (pid, name) in [(nativePID, "AXTextFixture"), (webPID, "AXWebFixture")] {
            guard NSRunningApplication(processIdentifier: pid)?.executableURL?.lastPathComponent == name else {
                print("NOT_RUN fixture PID executable mismatch"); exit(64)
            }
        }
        var safety: ForegroundSafety?
        do {
            print("FOREGROUND_STAGE safety_guardrail_init_begin"); fflush(nil)
            let guardrail = try ForegroundSafety(); safety = guardrail
            print("FOREGROUND_STAGE safety_guardrail_init_complete"); fflush(nil)
            var checks = 0, failures = 0
            func expect(_ condition: Bool, _ message: String) {
                if condition { checks += 1; print("PASS " + message) }
                else { failures += 1; print("FAIL " + message) }
                fflush(nil)
            }
            for (kind, pid) in [("web", webPID), ("native", nativePID)] {
                print("FOREGROUND_STAGE target=\(kind) pid=\(pid) activate_begin"); fflush(nil)
                let ownRoot = AXUIElementCreateApplication(pid)
                var ownedWindows: CFTypeRef?
                _ = AXUIElementCopyAttributeValue(ownRoot, kAXWindowsAttribute as CFString, &ownedWindows)
                guardrail.expectedPID = pid
                _ = try command(kind, "activate")
                // Never retry activation. Wait only for the one requested transition.
                for _ in 0..<50 {
                    if NSWorkspace.shared.frontmostApplication?.processIdentifier == pid { break }
                    try await Task.sleep(for: .milliseconds(20))
                }
                try guardrail.check(pid)
                print("FOREGROUND_STAGE target=\(kind) activated frontmost_pid_verified"); fflush(nil)
                try await Task.sleep(for: .milliseconds(150))
                print("FOREGROUND_STAGE target=\(kind) resolver_begin"); fflush(nil)
                let access = AXInputAccess(selectionProvider: { try guardrail.selectFixture(pid) })
                var ready: InputTargetSnapshot?
                for _ in 0..<40 {
                    try guardrail.check(pid)
                    if let candidate = try? access.snapshot(), candidate.isEditable,
                       candidate.selectionLocation == 7, candidate.selectionLength == 0 { ready = candidate; break }
                    try await Task.sleep(for: .milliseconds(50))
                }
                guard let snapshot = ready else {
                    for key in [kAXFocusedWindowAttribute, kAXFocusedUIElementAttribute] {
                        var item: CFTypeRef?, role: CFTypeRef?
                        let state = AXUIElementCopyAttributeValue(ownRoot, key as CFString, &item)
                        if let item, CFGetTypeID(item) == AXUIElementGetTypeID() {
                            _ = AXUIElementCopyAttributeValue(unsafeDowncast(item, to: AXUIElement.self), kAXRoleAttribute as CFString, &role)
                        }
                        print("OWNED_FOCUS", key, state.rawValue, role as? String ?? "none")
                    }
                    throw BatchFailure(message: "Fixture did not publish its focused editor")
                }
                print("FOREGROUND_STAGE target=\(kind) snapshot_complete can_set=\(snapshot.canSetSelectedText)"); fflush(nil)
                guard snapshot.canSetSelectedText else { throw BatchFailure(message: "NOT_RUN fixture requires clipboard fallback; clipboard untouched") }
                let preflight = try access.snapshot()
                let ownedSelection = try guardrail.selectFixture(pid)
                var number: CFTypeRef?, initialText: CFTypeRef?
                let countStatus = AXUIElementCopyAttributeValue(ownedSelection.element, kAXNumberOfCharactersAttribute as CFString, &number)
                let valueStatus = AXUIElementCopyAttributeValue(ownedSelection.element, kAXValueAttribute as CFString, &initialText)
                print("OWNED_WITNESS", kind, "count", countStatus.rawValue, number as? Int ?? -1, "valueMatches", valueStatus.rawValue, initialText as? String == "PREFIX|SUFFIX", "rangeMatches", access.textWitness(at: preflight) == "PREFIX|SUFFIX")
                let directory = FileManager.default.temporaryDirectory.appendingPathComponent("saytile-foreground-store-" + UUID().uuidString)
                defer { try? FileManager.default.removeItem(at: directory) }
                let store = try SaytileStore(directory: directory)
                let trace = FixtureAccessTrace(access)
                let input = NativeInputCoordinator(store: store, access: trace)
                input.onBindingInvalidated = { print("OWNED_BINDING_INVALIDATED", kind, ProcessInfo.processInfo.systemUptime); fflush(nil) }
                try await bindOwnedField(input, trace: trace, original: "PREFIX|SUFFIX", caret: 7, pid: pid)
                let recording = try await store.createRecording()
                let revision = try await store.saveEdit(recordingID: recording.id, text: "你好😀")
                print("FOREGROUND_STAGE target=\(kind) first_insert_begin"); fflush(nil)
                trace.stage = "first"
                let first = await input.insertStable(recordingID: recording.id, revisionID: revision.id, stableUTF16End: revision.text.utf16.count, recordingStartedAt: recording.createdAt)
                print("FOREGROUND_STAGE target=\(kind) first_insert_complete result=\(first)"); fflush(nil)
                print("FOREGROUND_INSERT kind=\(kind) result=\(first)"); fflush(nil)
                try guardrail.check(pid)
                let state = try command(kind, "state")
                let observed = try? access.snapshot()
                print("OWNED_FIRST_STATE", kind, state["text"] as? String ?? "unavailable", "utf16", state["utf16Length"] as? Int ?? -1, "caret", observed?.selectionLocation ?? -1, "range", observed?.selectionLength ?? -1, "attempts", state["selectedTextWrites"] as? Int ?? -1, "bound", input.binding != nil)
                if let observed {
                    print("OWNED_READBACK", kind, "sameTarget", observed.sameTarget(as: preflight),
                          "pageComplete", observed.pageContextComplete, "substring", access.matchesText("你好😀", utf16Start: 7, at: observed) == true,
                          "whole", access.textWitness(at: observed) == "PREFIX|你好😀SUFFIX")
                }
                expect(first == .confirmed && trace.writes == 1 && state["text"] as? String == "PREFIX|你好😀SUFFIX", kind + " real foreground insertion and local confirmation")
                if first == .confirmed {
                    let duplicate = await input.insertStable(recordingID: recording.id, revisionID: revision.id, stableUTF16End: revision.text.utf16.count, recordingStartedAt: recording.createdAt)
                    expect(duplicate == .noNewText, kind + " duplicate stable range suppressed")
                    let next = try await store.saveEdit(recordingID: recording.id, text: "你好😀，接着说")
                    trace.stage = "append"
                    let suffix = await input.insertStable(recordingID: recording.id, revisionID: next.id, stableUTF16End: next.text.utf16.count, recordingStartedAt: recording.createdAt)
                    let after = try command(kind, "state")
                    expect(suffix == .confirmed && trace.writes == 2 && after["text"] as? String == "PREFIX|你好😀，接着说SUFFIX", kind + " UTF16 suffix preserves surrounding text")
                }
                input.invalidate()
                _ = try command(kind, "restore"); try await Task.sleep(for: .milliseconds(250))
                try await input.bindCurrentTarget()
                _ = try command(kind, kind == "web" ? "silentContext" : "select")
                try await Task.sleep(for: .milliseconds(100))
                let before = try command(kind, "state")
                let stale = await input.insert(recordingID: recording.id, revisionID: revision.id)
                let after = try command(kind, "state")
                expect(stale != .confirmed && stale != .unverified && before["text"] as? String == after["text"] as? String && input.binding == nil, kind + " target mutation rejects stale insertion")
                expect(after["sends"] as? Int == 0, kind + " no Return or send")
                input.invalidate(); try await store.close()
                if kind == "web" {
                    try await webRepairs(access: access, safety: guardrail, pid: pid)
                    try await webReservationBoundaries(access: access, safety: guardrail, pid: pid)
                }
                if kind == "native" { try await nativeBoundaries(access: access, safety: guardrail, pid: pid) }
                try guardrail.check(pid)
            }
            let restored = await guardrail.restoreIfSafe()
            if !restored { failures += 1 }
            print("FOREGROUND_BATCH_COMPLETE checks=\(checks) failures=\(failures); production frontmost resolver + fixture PID guard; not a third-party browser claim")
            exit(failures == 0 ? 0 : 1)
        } catch {
            print("FOREGROUND_BATCH_STOP \(error)"); fflush(nil)
            await safety?.restoreIfSafe()
            exit(1)
        }
    }
}
