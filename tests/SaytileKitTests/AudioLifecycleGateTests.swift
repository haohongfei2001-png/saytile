import Testing
import Foundation
@testable import SaytileKit

@Suite("Independent lifecycle stop reasons")
struct AudioLifecycleGateTests {
    let unlocked = AudioSessionSnapshot(onConsole: true, loginComplete: true, screenLocked: false)
    let locked = AudioSessionSnapshot(onConsole: true, loginComplete: true, screenLocked: true)
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
