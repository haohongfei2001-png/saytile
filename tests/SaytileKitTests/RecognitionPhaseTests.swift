import Foundation
import Testing
@testable import SaytileKit

@Suite("Actual current-generation recognition presentation")
struct RecognitionPhaseTests {
    @Test func runningReviewPriorityClearsAsAttemptsFinish() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("saytile-phase-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try SaytileStore(directory: root)
        let recording = try await store.createRecording()
        let ticket = try await store.beginFusionRecognition(recordingID: recording.id)
        #expect(try await store.activeRecognitionPhases(recordingIDs: [recording.id]).isEmpty)
        let zh = try await store.beginModelRun(ticket: ticket, configuration: .init(purpose: .chineseASR, provider: .qwenMessage, model: "fixture"))
        let ai = try await store.beginModelRun(ticket: ticket, configuration: .init(purpose: .textFusion, provider: .openAIResponses, model: "fixture"))
        #expect(try await store.activeRecognitionPhases(recordingIDs: [recording.id])[recording.id] == .textFusion)
        let audio = try await store.beginModelRun(ticket: ticket, configuration: .init(purpose: .audioReview, provider: .gemini, model: "fixture"))
        #expect(try await store.activeRecognitionPhases(recordingIDs: [recording.id])[recording.id] == .audioReview)
        let final = try await store.beginModelRun(ticket: ticket, configuration: .init(purpose: .finalASR, provider: .elevenLabsFile, model: "fixture"))
        #expect(try await store.activeRecognitionPhases(recordingIDs: [recording.id])[recording.id] == .finalASR)
        try await store.finishModelRun(final, error: "synthetic unavailable")
        #expect(try await store.activeRecognitionPhases(recordingIDs: [recording.id])[recording.id] == .audioReview)
        try await store.finishModelRun(audio)
        try await store.finishModelRun(ai)
        #expect(try await store.activeRecognitionPhases(recordingIDs: [recording.id])[recording.id] == .chineseASR)
        try await store.finishModelRun(zh)
        #expect(try await store.activeRecognitionPhases(recordingIDs: [recording.id]).isEmpty)
        try await store.close()
    }

    @Test func staleGenerationsRestartAndUnrequestedRecordsNeverSupplyPhase() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("saytile-phase-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try SaytileStore(directory: root)
        let recording = try await store.createRecording(), other = try await store.createRecording()
        let first = try await store.beginFusionRecognition(recordingID: recording.id)
        _ = try await store.beginModelRun(ticket: first, configuration: .init(purpose: .finalASR, provider: .elevenLabsFile, model: "old"))
        let next = try await store.beginFusionRecognition(recordingID: recording.id)
        _ = try await store.beginModelRun(ticket: next, configuration: .init(purpose: .englishASR, provider: .assemblyAI, model: "new"))
        let otherTicket = try await store.beginFusionRecognition(recordingID: other.id)
        _ = try await store.beginModelRun(ticket: otherTicket, configuration: .init(purpose: .textFusion, provider: .openAIResponses, model: "other"))
        // Cross the SQL batch boundary without creating hundreds of unused records.
        let many = (0..<501).map { _ in UUID() } + [recording.id, recording.id]
        #expect(try await store.activeRecognitionPhases(recordingIDs: many) == [recording.id: .englishASR])
        #expect(try await store.activeRecognitionPhases(recordingIDs: []).isEmpty)
        try await store.close()
        let reopened = try SaytileStore(directory: root)
        #expect(try await reopened.activeRecognitionPhases(recordingIDs: [recording.id, other.id]).isEmpty)
        try await reopened.close()
    }
}
