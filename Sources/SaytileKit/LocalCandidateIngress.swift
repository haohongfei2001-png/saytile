import Foundation

/// Apple SpeechAnalyzer results share the Candidate/Store boundary with cloud ASRs.
/// Local evidence is explicitly local; it never claims GPT review or enables cloud recovery.
actor LocalCandidateIngress {
    private let store: SaytileStore
    private let ticket: RecognitionTicket
    private var run: ModelRunTicket?
    private var sequence: Int64 = 0
    private var complete = false
    init(store: SaytileStore, ticket: RecognitionTicket) { self.store = store; self.ticket = ticket }
    func receive(_ event: ProviderTranscriptEvent) async throws {
        if run == nil { run = try await store.beginLocalCandidateRun(ticket: ticket) }
        guard let run else { throw FusionError.staleGeneration }
        sequence += 1
        let candidate = RecognitionCandidate(run: run, sequence: sequence, event: event)
        guard try await store.appendRecognitionCandidate(candidate) else { throw FusionError.staleGeneration }
        complete = event.isComplete
        let prefix = try await store.fusionReservedPrefix(recordingID: ticket.recordingID)
        let proposal = PrecisionFusion.evaluate(candidates: [candidate], mode: .highestQuality,
            committedPrefix: prefix, requiredPurposes: [.multilingualASR], requiredConfigurationIDs: [run.configurationID])
        _ = try await store.publishFusion(ticket: ticket, proposal: proposal)
        NotificationCenter.default.post(name: .init("SaytileRecognitionUpdated"), object: ticket.recordingID)
    }
    func finish() async throws {
        guard let run, complete else { throw ProviderFailure.incomplete }
        try await store.finishModelRun(run, error: nil, retryable: true)
        try await store.finishRecognition(ticket: ticket)
    }
}
