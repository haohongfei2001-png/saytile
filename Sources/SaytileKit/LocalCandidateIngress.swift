import Foundation

/// Apple SpeechAnalyzer results share the Candidate/Store boundary with cloud ASRs.
/// Local evidence is explicitly local; it never claims GPT review or enables cloud recovery.
actor LocalCandidateIngress {
    private let store: SaytileStore
    private let ticket: RecognitionTicket
    private let model: LocalASRID
    private let review: LocalTextReview?
    private var last: RecognitionCandidate?
    private var run: ModelRunTicket?
    private var sequence: Int64 = 0
    private var complete = false
    init(store: SaytileStore, ticket: RecognitionTicket, model: LocalASRID = .apple, review: LocalTextReview? = nil) {
        self.store = store; self.ticket = ticket; self.model = model; self.review = review
    }
    func receive(_ event: ProviderTranscriptEvent) async throws {
        if run == nil { run = try await store.beginLocalCandidateRun(ticket: ticket, model: model) }
        guard let run else { throw FusionError.staleGeneration }
        sequence += 1
        let candidate = RecognitionCandidate(run: run, sequence: sequence, event: event)
        guard try await store.appendRecognitionCandidate(candidate) else { throw FusionError.staleGeneration }
        complete = event.isComplete
        let prefix = try await store.fusionReservedPrefix(recordingID: ticket.recordingID)
        let proposal = PrecisionFusion.evaluate(candidates: [candidate], mode: .highestQuality,
            committedPrefix: prefix, requiredPurposes: [.multilingualASR], requiredConfigurationIDs: [run.configurationID])
        let publication = try await store.publishFusion(ticket: ticket, proposal: proposal)
        last = candidate
        complete = event.isComplete && !publication.deferred
        NotificationCenter.default.post(name: .init("SaytileRecognitionUpdated"), object: ticket.recordingID)
    }
    func finish() async throws {
        guard let run, complete else { throw ProviderFailure.incomplete }
        try await store.finishModelRun(run, error: nil, retryable: true)
        if let review, let last { await review.apply(last, store: store, ticket: ticket) }
        try await store.finishRecognition(ticket: ticket)
    }
}

extension SaytileStore {
    /// Generation check and mutation share the Store actor turn, so a settings
    /// update while waiting for Store cannot queue over a newer admitted ticket.
    func beginLocalFailover(recordingID: UUID, epoch: RecognitionFailoverEpoch) throws -> RecognitionTicket {
        try epoch.check()
        return try beginRecognition(recordingID: recordingID)
    }
    func queueLocalFailover(recordingID: UUID, epoch: RecognitionFailoverEpoch) throws {
        try epoch.check()
        try queueRecognition(recordingID: recordingID)
    }
}
