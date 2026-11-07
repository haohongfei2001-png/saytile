import Foundation
import CryptoKit
import Testing
@testable import SaytileKit

@Suite("Explicit local single-ASR probe boundaries")
struct MultiRecognitionDiagnosticsTests {
    @Test func selectedASRIsUniqueAndCannotBypassConsentOrRoleValidation() throws {
        var config = RecognitionConfiguration()
        config.cloudEnabled = true
        config.models = [
            .init(purpose: .englishASR, provider: .assemblyAI, model: "universal-3-6-pro"),
            .init(purpose: .textFusion, provider: .openAIResponses, model: "gpt-6-astra")
        ]
        #expect(throws: ProviderFailure.self) { try config.validateForCloud() }
        config.models[0].cloudConsent = true
        config.models[1].cloudConsent = true
        try config.validateForCloud()
        config.models.append(.init(purpose: .chineseASR, provider: .qwenMessage, model: "qwen-audio-3.1-asr-flash-message",
                                   cloudConsent: true, region: "cn-beijing", workspaceID: "fixture"))
        try config.validateForCloud()
        config.models = [.init(purpose: .textFusion, provider: .openAIResponses, model: "gpt-6-astra", cloudConsent: true)]
        #expect(throws: ProviderFailure.self) { try config.validateForCloud() }
    }

    @Test func sourceHashCoversEntireDeclaredFixtureAndSingleASRModeIsExplicit() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("saytile-fixture-hash-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("synthetic-hash-only.wav")
        // Hash utility coverage only; this is not passed to the validated audio replay.
        var bytes = Data(repeating: 7, count: 130_001); bytes[130_000] = 9
        try bytes.write(to: url)
        let identity = try MultiRecognitionDiagnostics.fixtureIdentity(url: url, frameCount: 16_000)
        #expect(identity.fixtureID == "synthetic-hash-only")
        #expect(identity.audioSHA256 == SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined())
        var configuration = RecognitionConfiguration()
        configuration.models = [.init(purpose: .englishASR, provider: .meta, model: "muse-voice-transcribe-1.0")]
        let baseline = try MultiRecognitionDiagnostics.identity(configuration: configuration)
        let fused = try MultiRecognitionDiagnostics.identity(configuration: configuration)
        #expect(baseline.evaluationMode == "single-asr-plus-gpt6")
        #expect(fused.evaluationMode == "single-asr-plus-gpt6")
        #expect(baseline.sha256 == fused.sha256)
        configuration.models[0].model = "different-model"
        #expect(try MultiRecognitionDiagnostics.identity(configuration: configuration).sha256 != baseline.sha256)
    }

    @Test func exportsPersistedGenerationTerminalAndExactConfigurationWithoutInventingSessionCompletion() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("saytile-terminal-trace-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try SaytileStore(directory: directory)
        let record = try await store.createRecording()
        try await store.finishRecording(id: record.id)
        var configuration = RecognitionConfiguration()
        configuration.cloudEnabled = true
        configuration.models = [
            .init(purpose: .chineseASR, provider: .qwenMessage, model: "fixture-qwen", cloudConsent: true, region: "cn-beijing", workspaceID: "fixture"),
            .init(purpose: .englishASR, provider: .assemblyAI, model: "fixture-assembly", cloudConsent: true)
        ]
        let ticket = try await store.beginFusionRecognition(recordingID: record.id)
        var candidates: [RecognitionCandidate] = []
        for model in configuration.models {
            let run = try await store.beginModelRun(ticket: ticket, configuration: model)
            let candidate = RecognitionCandidate(run: run, sequence: 1, text: "测试", stableUTF16Length: 2,
                                                 audioEndSeconds: 1, isComplete: true)
            try await store.appendRecognitionCandidate(candidate)
            candidates.append(candidate)
        }
        _ = try await store.publishFusion(ticket: ticket, proposal: PrecisionFusion.evaluate(candidates: candidates, mode: .highestQuality))
        try await store.finishRecognition(ticket: ticket)
        let terminal = try #require(await store.fusionTerminal(recognitionID: ticket.id))
        let replay = MultiRecognitionDiagnostics.ReplayMetadata(
            recordingID: record.id, recognitionID: ticket.id, mode: .highestQuality, frameCount: 16_000,
            replayStartedAt: Date(timeIntervalSince1970: 100), firstAudioSubmittedAt: Date(timeIntervalSince1970: 100.02),
            lastAudioSubmittedAt: Date(timeIntervalSince1970: 101), sessionEndedAt: Date(timeIntervalSince1970: 102),
            source: .init(fixtureID: "synthetic-only", audioSHA256: String(repeating: "a", count: 64), sampleRate: 16_000, frameCount: 16_000),
            configuration: configuration,
            configurationIdentity: try MultiRecognitionDiagnostics.identity(configuration: configuration))
        let owned = store.audioDirectory.appendingPathComponent(record.id.uuidString)
        try FileManager.default.createDirectory(at: owned, withIntermediateDirectories: true)
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .millisecondsSince1970
        try encoder.encode(replay).write(to: owned.appendingPathComponent("single-asr-replay.json"))
        // A later live attempt changes record-level state, but not the replayed generation's result.
        _ = try await store.beginFusionRecognition(recordingID: record.id)
        let url = directory.appendingPathComponent("trace.json")
        try await MultiRecognitionDiagnostics.exportTrace(store: store, recordingID: record.id, to: url)
        let object = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        let final = try #require(object["finalization"] as? [String: Any])
        #expect(final["state"] as? String == "completed")
        #expect(final["selectedText"] as? String == "测试")
        #expect(final["recognitionID"] as? String == ticket.id.uuidString)
        let completed = try #require(final["completedAt"] as? Double)
        #expect(abs(completed - terminal.occurredAt.timeIntervalSince1970 * 1000) < 0.001)
        #expect(completed != 102_000) // Session termination must never masquerade as completion.
        #expect((object["source"] as? [String: Any])?["fixtureID"] as? String == "synthetic-only")
        #expect((object["configurationIdentity"] as? [String: Any])?["evaluationMode"] as? String == "single-asr-plus-gpt6")
        #expect(object["sourceRevision"] == nil)
        try await store.close()
    }

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
            .init(purpose: .englishASR, provider: .assemblyAI, model: "universal-3-6-pro"),
            .init(purpose: .textFusion, provider: .openAIResponses, model: "gpt-6-astra")
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
