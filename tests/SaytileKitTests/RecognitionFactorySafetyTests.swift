import Foundation
import Testing
@testable import SaytileKit

@Suite("Recognition settings generation admission")
struct RecognitionFactorySafetyTests {
    @Test(arguments: [false, true]) func settingsChangeDuringTicketCreationCannotStartEitherPipeline(initialCloud: Bool) async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("saytile-factory-" + UUID().uuidString)
        let store = try SaytileStore(directory: directory)
        defer { try? FileManager.default.removeItem(at: directory) }
        let record = try await store.createRecording()
        var config = RecognitionConfiguration(); config.cloudEnabled = initialCloud
        let factory = RecognitionSessionFactory(configuration: config)
        let snapshot = factory.snapshot
        let ticket = try await (initialCloud ? store.beginFusionRecognition(recordingID: record.id, mode: .highestQuality)
                                            : store.beginRecognition(recordingID: record.id))
        config.cloudEnabled.toggle(); factory.update(config)
        let session = factory.make(store: store, ticket: ticket, snapshot: snapshot)
        session.append(Data(repeating: 0, count: 640)); session.finish(); await session.wait()
        #expect(session.isComplete)
        let result = try #require(await store.recording(id: record.id))
        #expect(result.recognitionState == .failed)
        #expect(result.lastError?.contains("设置已更新") == true)
        #expect(try await store.modelRuns(recordingID: record.id).isEmpty)
    }
    @Test func sameConfigurationUpdateAlsoInvalidatesPendingAdmission() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("saytile-factory-revoke-" + UUID().uuidString)
        let store = try SaytileStore(directory: directory)
        defer { try? FileManager.default.removeItem(at: directory) }
        var config = RecognitionConfiguration(); config.cloudEnabled = true
        let factory = RecognitionSessionFactory(configuration: config)
        let snapshot = factory.snapshot
        let record = try await store.createRecording()
        let ticket = try await store.beginFusionRecognition(recordingID: record.id, mode: .highestQuality)
        // Removing a key invalidates in-flight work even when model settings are identical.
        factory.update(config)
        let session = factory.make(store: store, ticket: ticket, snapshot: snapshot)
        await session.wait()
        #expect(session.isComplete)
        #expect(try await store.modelRuns(recordingID: record.id).isEmpty)
    }
}
