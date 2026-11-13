import Testing
import Foundation
@testable import SaytileKit

@Suite("Audio controller shutdown")
struct AudioShutdownTests {
    @MainActor @Test func resourceFailureAndRetryPreservePausedAudioAndItsArchive() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("saytile-resource-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try SaytileStore(directory: root)
        let row = try await store.createRecording()
        _ = try await store.saveEdit(recordingID: row.id, text: "保留原稿")
        try await store.finishRecording(id: row.id)
        let controller = AudioController(store: store)
        let (started, start) = AsyncStream<Void>.makeStream()
        var reply: CheckedContinuation<String, Never>?
        let stale = controller.updateAvailability {
            await withCheckedContinuation { continuation in
                reply = continuation
                start.yield(())
                start.finish()
            }
        }
        var observed = started.makeAsyncIterator()
        _ = await observed.next()
        await controller.prepareSpeechAssets {
            #expect(controller.preparingAppleSpeech)
            throw AudioFailure.message("下载中断")
        }
        #expect(controller.appleResourceFailure == "下载中断" && !controller.preparingAppleSpeech && controller.issue != nil)
        await controller.prepareSpeechAssets { "中文识别已就绪" }
        // Release the older system read after the explicit preparation succeeds.
        let pending = try #require(reply)
        pending.resume(returning: "中文资源尚未安装")
        await stale.value
        #expect(controller.appleResourceFailure == nil && !controller.preparingAppleSpeech && controller.issue == nil)
        #expect(controller.speechStatus == "中文识别已就绪" && controller.state == .paused)
        #expect(try await store.recording(id: row.id)?.text == "保留原稿")
        await controller.shutdown(); try await store.close()
    }

    @MainActor @Test func finishingAppleAssetSetupCannotReplaceAnotherSelectedEnginesStatus() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("saytile-resource-route-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try SaytileStore(directory: root)
        let controller = AudioController(store: store)
        let service = LocalASRService(root: root.appending(path: "LocalModels"))
        await controller.prepareSpeechAssets {
            controller.selectLocalModels(live: .sherpa, archive: .sherpa, service: service)
            await controller.updateAvailability { LocalASRID.sherpa.title }.value
            return "Apple 已就绪"
        }
        #expect(controller.speechStatus == LocalASRID.sherpa.title)
        await controller.prepareSpeechAssets { throw AudioFailure.message("Apple 离线") }
        #expect(controller.appleResourceFailure == "Apple 离线")
        #expect(controller.issue == nil && controller.speechStatus == LocalASRID.sherpa.title)
        await controller.shutdown()
        try await store.close()
    }

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
