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
        originalPID = front.processIdentifier
        lastInputTime = ProcessInfo.processInfo.systemUptime - idle
        let baseline = lastInputTime
        timer = DispatchSource.makeTimerSource(queue: .global(qos: .userInteractive))
        timer.schedule(deadline: .now(), repeating: .milliseconds(20))
        timer.setEventHandler {
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
            let guardrail = try ForegroundSafety(); safety = guardrail
            var checks = 0, failures = 0
            func expect(_ condition: Bool, _ message: String) {
                if condition { checks += 1; print("PASS " + message) }
                else { failures += 1; print("FAIL " + message) }
                fflush(nil)
            }
            for (kind, pid) in [("native", nativePID), ("web", webPID)] {
                guardrail.expectedPID = pid
                _ = try command(kind, "activate")
                // Never retry activation. Wait only for the one requested transition.
                for _ in 0..<50 {
                    if NSWorkspace.shared.frontmostApplication?.processIdentifier == pid { break }
                    try await Task.sleep(for: .milliseconds(20))
                }
                try guardrail.check(pid)
                try await Task.sleep(for: .milliseconds(150))
                let access = AXInputAccess(selectionProvider: { try guardrail.selectFixture(pid) })
                let snapshot = try access.snapshot()
                guard snapshot.canSetSelectedText else { throw BatchFailure(message: "NOT_RUN fixture requires clipboard fallback; clipboard untouched") }
                let directory = FileManager.default.temporaryDirectory.appendingPathComponent("saytile-foreground-store-" + UUID().uuidString)
                defer { try? FileManager.default.removeItem(at: directory) }
                let store = try SaytileStore(directory: directory)
                let input = NativeInputCoordinator(store: store, access: access)
                try await input.bindCurrentTarget()
                let recording = try await store.createRecording()
                let revision = try await store.saveEdit(recordingID: recording.id, text: "你好😀")
                let first = await input.insertStable(recordingID: recording.id, revisionID: revision.id, stableUTF16End: revision.text.utf16.count, recordingStartedAt: recording.createdAt)
                print("FOREGROUND_INSERT kind=\(kind) result=\(first)"); fflush(nil)
                try guardrail.check(pid)
                let state = try command(kind, "state")
                expect(first == .confirmed && state["text"] as? String == "PREFIX|你好😀SUFFIX", kind + " real foreground insertion and local confirmation")
                if first == .confirmed {
                    let duplicate = await input.insertStable(recordingID: recording.id, revisionID: revision.id, stableUTF16End: revision.text.utf16.count, recordingStartedAt: recording.createdAt)
                    expect(duplicate == .noNewText, kind + " duplicate stable range suppressed")
                    let next = try await store.saveEdit(recordingID: recording.id, text: "你好😀，接着说")
                    let suffix = await input.insertStable(recordingID: recording.id, revisionID: next.id, stableUTF16End: next.text.utf16.count, recordingStartedAt: recording.createdAt)
                    let after = try command(kind, "state")
                    expect(suffix == .confirmed && after["text"] as? String == "PREFIX|你好😀，接着说SUFFIX", kind + " UTF16 suffix preserves surrounding text")
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
