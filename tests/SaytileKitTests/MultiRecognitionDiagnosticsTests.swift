import Foundation
import Testing
@testable import SaytileKit

@Suite("Explicit local multi-ASR probe boundaries")
struct MultiRecognitionDiagnosticsTests {
    @Test func rejectsDisabledCloudMissingConsentAndInvalidWAVWithoutCreatingRecords() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("saytile-multi-probe-" + UUID().uuidString)
        let store = try SaytileStore(directory: directory)
        defer { try? FileManager.default.removeItem(at: directory) }
        let invalid = directory.appendingPathComponent("not-a-wave.wav")
        try Data("This is not an audio fixture".utf8).write(to: invalid)
        var configuration = RecognitionConfiguration()
        configuration.models = [
            .init(purpose: .chineseASR, provider: .qwenMessage, model: "qwen-audio-3.1-asr-flash-message",
                  region: "cn-beijing", workspaceID: "offline-fixture"),
            .init(purpose: .englishASR, provider: .assemblyAI, model: "universal-3-6-pro")
        ]
        await #expect(throws: ProviderFailure.self) {
            try await MultiRecognitionDiagnostics.transcribeFixture(url: invalid, store: store, configuration: configuration)
        }
        configuration.cloudEnabled = true
        await #expect(throws: ProviderFailure.self) {
            try await MultiRecognitionDiagnostics.transcribeFixture(url: invalid, store: store, configuration: configuration)
        }
        for index in configuration.models.indices { configuration.models[index].cloudConsent = true }
        // The malformed source is rejected before any Keychain lookup or live session.
        await #expect(throws: AudioFailure.self) {
            try await MultiRecognitionDiagnostics.transcribeFixture(url: invalid, store: store, configuration: configuration)
        }
        #expect(try await store.listRecordings().isEmpty)
        try await store.close()
    }

    @Test func exportingEmptyRecordCannotInventLatencyAccuracyOrUsage() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("saytile-multi-trace-" + UUID().uuidString)
        let store = try SaytileStore(directory: directory)
        defer { try? FileManager.default.removeItem(at: directory) }
        let record = try await store.createRecording()
        try await store.finishRecording(id: record.id)
        let output = directory.appendingPathComponent("report/trace.json")
        try await MultiRecognitionDiagnostics.exportTrace(store: store, recordingID: record.id, to: output)
        let object = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: output)) as? [String: Any])
        #expect(object["accuracyMeasurement"] as? String == "not-measured-no-reference-transcript")
        #expect((object["candidates"] as? [Any])?.isEmpty == true)
        #expect((object["modelUsage"] as? [Any])?.isEmpty == true)
        let timing = try #require(object["timing"] as? [String: Any])
        #expect(timing["firstStableSeconds"] == nil)
        #expect(timing["logicalRecognitionCompletedAt"] == nil)
        #expect(object["replay"] == nil)
        try await store.close()
    }
}
