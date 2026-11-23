import Foundation
import Testing
@testable import SaytileKit

@Suite("Decoded arbitration response audit")
struct ArbitrationAuditTests {
    private struct Fixture {
        let directory: URL
        let store: SaytileStore
        let recordingID: UUID
        let run: ModelRunTicket
        let evidence: ArbitrationResponseEvidence
        init() async throws {
            directory = FileManager.default.temporaryDirectory.appendingPathComponent("saytile-arbiter-audit-" + UUID().uuidString)
            store = try SaytileStore(directory: directory)
            let record = try await store.createRecording()
            recordingID = record.id
            let path = record.id.uuidString + "/chunk.wav"
            let file = store.audioDirectory.appendingPathComponent(path)
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try (PCMJournal.header(frames: 1600) + Data(repeating: 0, count: 3200)).write(to: file)
            try await store.registerAudioChunk(recordingID: record.id, relativePath: path, frames: 1600)
            try await store.finishRecording(id: record.id)
            let ticket = try await store.beginFusionRecognition(recordingID: record.id)
            let sourceRun = try await store.beginModelRun(ticket: ticket,
                configuration: .init(purpose: .chineseASR, provider: .qwenMessage, model: "fixture-source"))
            let source = RecognitionCandidate(run: sourceRun, sequence: 1, text: "不要支付15元😀", stableUTF16Length: 0,
                audioEndSeconds: 0.1)
            _ = try await store.appendRecognitionCandidate(source)
            run = try await store.beginModelRun(ticket: ticket,
                configuration: .init(purpose: .textFusion, provider: .openAIResponses, model: "fixture-arbiter"))
            // Deliberately invalid source/range: an audit must retain the rejected
            // decoded response verbatim without assigning it publication authority.
            evidence = .init(candidateIDs: [source.id], confirmedPrefix: "不要",
                decision: .init(selections: [.init(candidateID: UUID(), utf16Start: -1, utf16End: 90)],
                    unresolved: false, needsAudioReview: true, reasonCode: "fixture-invalid-source"))
        }
        func usage() -> ModelUsageRecord {
            .init(runID: run.id, requestID: "fixture-request", inputTokens: 17, outputTokens: 23,
                estimatedCost: 0.001, status: "response-received", elapsedSeconds: 0.25, arbitrationResponse: evidence)
        }
        func remove() { try? FileManager.default.removeItem(at: directory) }
    }

    @Test func oldUsagePayloadWithoutAuditStillDecodes() throws {
        let old = ModelUsageRecord(runID: UUID(), inputTokens: 5, outputTokens: 6)
        var payload = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(old)) as? [String: Any])
        payload.removeValue(forKey: "arbitrationResponse")
        let decoded = try JSONDecoder().decode(ModelUsageRecord.self, from: JSONSerialization.data(withJSONObject: payload))
        #expect(decoded == old)
        #expect(decoded.arbitrationResponse == nil)
    }

    @Test func rejectedResponseAndRequestSnapshotSurviveRestartWithoutPublishing() async throws {
        let f = try await Fixture(); defer { f.remove() }
        let usage = f.usage()
        try await f.store.recordModelUsage(usage)
        try await f.store.finishModelRun(f.run, error: FusionError.invalidSelection.localizedDescription)
        #expect(try await f.store.latestDispatchableRevision(recordingID: f.recordingID) == nil)
        try await f.store.close()
        let reopened = try SaytileStore(directory: f.directory)
        #expect(try await reopened.modelUsage(recordingID: f.recordingID) == [usage])
        #expect(try await reopened.modelRuns(recordingID: f.recordingID).first { $0.id == f.run.id }?.state == .failed)
        #expect(try await reopened.revisions(recordingID: f.recordingID).isEmpty)
        try await reopened.close()
    }

    @Test func deletingOnlyAudioPreservesDecodedResponseAndUsage() async throws {
        let f = try await Fixture(); defer { f.remove() }
        let usage = f.usage()
        try await f.store.recordModelUsage(usage)
        try await f.store.deleteAudio(recordingID: f.recordingID)
        #expect(try await f.store.modelUsage(recordingID: f.recordingID) == [usage])
        #expect(try await f.store.recording(id: f.recordingID)?.audioState == .deleted)
        #expect(try await f.store.recognitionCandidates(recordingID: f.recordingID).count == 1)
        #expect(try await f.store.latestDispatchableRevision(recordingID: f.recordingID) == nil)
        try await f.store.close()
    }

    @Test func wholeRecordDeletionErasesResponseAndBlocksLateAuditResurrection() async throws {
        let f = try await Fixture(); defer { f.remove() }
        let usage = f.usage()
        try await f.store.recordModelUsage(usage)
        try await f.store.deleteRecord(recordingID: f.recordingID)
        await #expect(throws: Error.self) { try await f.store.recordModelUsage(f.usage()) }
        try await f.store.close()
        let db = try StoreDatabase(url: f.directory.appendingPathComponent("Saytile.sqlite"))
        let rows = try db.rows("SELECT payload FROM model_usage WHERE recording_id=?", [.text(f.recordingID.uuidString)])
        #expect(rows.count == 1)
        let payload = try #require(rows.first?["payload"])
        let remaining = try JSONDecoder().decode(ModelUsageRecord.self, from: Data(payload.utf8))
        #expect(remaining.arbitrationResponse == nil)
        #expect(remaining.id == usage.id)
        #expect(remaining.inputTokens == 17 && remaining.outputTokens == 23)
        #expect(remaining.estimatedCost == usage.estimatedCost)
        #expect(!payload.contains("不要"))
        #expect(!payload.contains("fixture-invalid-source"))
        try db.close()
        let reopened = try SaytileStore(directory: f.directory)
        await #expect(throws: Error.self) { try await reopened.recordModelUsage(f.usage()) }
        #expect(try await reopened.recording(id: f.recordingID) == nil)
        try await reopened.close()
    }
}
