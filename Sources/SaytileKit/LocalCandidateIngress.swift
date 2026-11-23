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
    func start() async throws {
        if run == nil { run = try await store.beginLocalCandidateRun(ticket: ticket, model: model) }
    }
    func fail(_ message: String) async {
        if let run { try? await store.finishModelRun(run, error: message) }
        try? await store.failRecognition(ticket: ticket, message: message)
    }
    /// An empty final is not silence certification and must never complete or
    /// clear a recording. Keep previews, user drafts and original PCM retryable.
    func finishWithoutTranscript() async {
        await fail(last == nil
            ? "未识别到文字，原音已保存，可回听或重新识别。"
            : "未获得最终文字，已有文字和原音已保留，可重新识别。")
    }
    func receive(_ event: ProviderTranscriptEvent) async throws {
        if run == nil { try await start() }
        guard let run else { throw FusionError.staleGeneration }
        sequence += 1
        let started = FixturePerformanceTrace.enabled ? ProcessInfo.processInfo.systemUptime : 0
        FixturePerformanceTrace.record("candidate.received", recordingID: ticket.recordingID)
        let candidate = RecognitionCandidate(run: run, sequence: sequence, event: event)
        guard try await store.appendRecognitionCandidate(candidate) else { throw FusionError.staleGeneration }
        FixturePerformanceTrace.record("candidate.persisted", recordingID: ticket.recordingID, since: started)
        complete = event.isComplete
        let prefix = try await store.fusionReservedPrefix(recordingID: ticket.recordingID)
        let proposal = PrecisionFusion.evaluate(candidates: [candidate], mode: .highestQuality,
            committedPrefix: prefix, requiredPurposes: [.multilingualASR], requiredConfigurationIDs: [run.configurationID])
        let publicationStart = FixturePerformanceTrace.enabled ? ProcessInfo.processInfo.systemUptime : 0
        let publication = try await store.publishFusion(ticket: ticket, proposal: proposal)
        FixturePerformanceTrace.record("transcript.persisted", recordingID: ticket.recordingID, since: publicationStart,
            decision: publication.deferred ? "protected" : "published")
        last = candidate
        // An exact acoustic final may be archived while an external owned-range
        // correction is pending. That is completed recognition, not permission
        // to append or overwrite a target whose ownership has changed.
        let accepted = publication.acceptedProposal
        complete = event.isComplete && (!publication.deferred ||
            (accepted?.unresolved == false && accepted?.needsAudioReview == false &&
             accepted?.stableText.utf8.elementsEqual(event.text.utf8) == true))
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
