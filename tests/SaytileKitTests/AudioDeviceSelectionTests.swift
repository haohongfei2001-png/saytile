import Foundation
import Testing
import SaytileKit

@Suite("Persistent microphone selection")
struct AudioDeviceSelectionTests {
    @MainActor @Test func staleDeviceIDCannotTurnAPinnedMicrophoneIntoSystemDefault() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("saytile-device-selection-\(UUID())")
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try SaytileStore(directory: directory)
        let audio = AudioController(store: store, startupRecoveryReady: false)
        let pinned = "saytile-test-disconnected-\(UUID())"
        audio.selectDevice(uid: pinned)
        let staleID = UInt32.max - 37
        try #require(!audio.devices.contains(where: { $0.id == staleID }))
        audio.selectedDeviceID = staleID

        // Settings persist this UID. A rejected menu item must not erase it.
        #expect(audio.selectedDeviceUID == pinned)
        #expect(audio.issue != nil)
        #expect(audio.state == .paused)
        audio.selectedDeviceID = 0
        #expect(audio.selectedDeviceUID == nil)
        #expect(audio.issue == nil)
        await audio.shutdown()
        try await store.close()
    }
}
