import Testing
import Foundation
@testable import SaytileKit

@Suite("Audio controller shutdown")
struct AudioShutdownTests {
    @MainActor @Test func shutdownIsIdempotentAndCannotRestartAfterStoreClose() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("saytile-audio-exit-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try SaytileStore(directory: root)
        let controller = AudioController(store: store)
        await controller.shutdown()
        await controller.shutdown()
        try await store.close()
        await controller.start(requestPermission: false)
        await controller.retry(recordingID: UUID())
        await controller.prepareSpeechAssets()
        #expect(controller.state == .paused)
        #expect(controller.reprocessingID == nil)
        #expect(!controller.preparingSpeech)
    }
}
