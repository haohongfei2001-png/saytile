import Testing
import Foundation
import AVFoundation
@testable import SaytileKit

@Suite("Independent lifecycle stop reasons")
struct AudioLifecycleGateTests {
    let unlocked = AudioSessionSnapshot(onConsole: true, loginComplete: true, screenLocked: false)
    let locked = AudioSessionSnapshot(onConsole: true, loginComplete: true, screenLocked: true)
    @Test func initialPermissionPromptDoesNotCancelPendingStart() {
        #expect(!AudioLifecycleGate.requiresPermissionSuspension(state: .starting, authorization: .notDetermined))
        #expect(!AudioLifecycleGate.requiresPermissionSuspension(state: .starting, authorization: .authorized))
        #expect(AudioLifecycleGate.requiresPermissionSuspension(state: .starting, authorization: .denied))
        #expect(AudioLifecycleGate.requiresPermissionSuspension(state: .starting, authorization: .restricted))
    }
    @Test func permissionResetWhileCapturingStillRequiresSuspension() {
        #expect(AudioLifecycleGate.requiresPermissionSuspension(state: .listening, authorization: .notDetermined))
        #expect(AudioLifecycleGate.requiresPermissionSuspension(state: .speaking, authorization: .denied))
        #expect(!AudioLifecycleGate.requiresPermissionSuspension(state: .paused, authorization: .notDetermined))
        #expect(!AudioLifecycleGate.requiresPermissionSuspension(state: .interrupted("fixture"), authorization: .denied))
    }
    @Test func systemSleepDoesNotReplaceAnIntentionalUserPause() {
        #expect(!AudioLifecycleGate.shouldSuspendForSystemLifecycle(state: .paused, requestedRunning: false))
        #expect(!AudioLifecycleGate.shouldSuspendForSystemLifecycle(state: .paused, requestedRunning: true))
        #expect(AudioLifecycleGate.shouldSuspendForSystemLifecycle(state: .listening, requestedRunning: true))
        #expect(AudioLifecycleGate.shouldSuspendForSystemLifecycle(state: .interrupted("device"), requestedRunning: true))
    }
    @Test func lockedAtLaunchCannotCapture() {
        var gate = AudioLifecycleGate(); gate.refresh(locked)
        #expect(!gate.permitsCapture)
        gate.receivedUnlock(snapshot: locked)
        #expect(!gate.permitsCapture)
    }
    @Test func wakeDoesNotOverrideLockOrSessionSwitch() {
        var gate = AudioLifecycleGate(); gate.refresh(unlocked)
        gate.sleeping = true; gate.receivedLock(); gate.sleeping = false
        #expect(!gate.permitsCapture)
        gate.sessionInactive = true; gate.receivedUnlock(snapshot: unlocked)
        #expect(!gate.permitsCapture)
        gate.sessionInactive = false
        #expect(gate.permitsCapture)
    }
    @Test func unknownSessionOrUntrustedUnlockCannotResume() {
        var gate = AudioLifecycleGate(); gate.refresh(unlocked); gate.receivedLock()
        gate.receivedUnlock(snapshot: nil)
        #expect(!gate.permitsCapture)
        gate.receivedUnlock(snapshot: locked)
        #expect(!gate.permitsCapture)
        gate.receivedUnlock(snapshot: unlocked)
        #expect(gate.permitsCapture)
    }
    @MainActor @Test func localNotificationBridgeObservesLockAndUnlockWithoutSystemSideEffects() async throws {
        let center = NotificationCenter()
        var events: [Bool] = []
        let bridge = AudioLockEventBridge(center: center) { events.append($0) }
        center.post(name: AudioLockEventBridge.locked, object: nil)
        center.post(name: AudioLockEventBridge.unlocked, object: nil)
        try await Task.sleep(for: .milliseconds(20))
        #expect(events == [true, false])
        bridge.invalidate()
        center.post(name: AudioLockEventBridge.locked, object: nil)
        try await Task.sleep(for: .milliseconds(20))
        #expect(events == [true, false])
    }
}
