import Foundation

/// Explicit opt-in for new local utterances. The request object can carry text
/// evidence only. Audio replay and cloud-failover sessions never receive a grant.
public final class LocalTextReview: @unchecked Sendable {
    private let model: ModelConfiguration
    private let dependencies: RecognitionPipelineDependencies
    private let lock = NSLock()
    private var active = true
    private var tasks: [UUID: Task<Void, Never>] = [:]
    public convenience init?(model: ModelConfiguration) {
        self.init(model: model, dependencies: .live)
    }
    init?(model: ModelConfiguration, dependencies: RecognitionPipelineDependencies) {
        guard model.enabled, model.purpose == .textFusion, model.provider == .openAIResponses,
              model.model == "gpt-6-astra" else { return nil }
        var consented = model
        consented.cloudConsent = true
        self.model = consented; self.dependencies = dependencies
    }
    public func revoke() {
        let pending = lock.withLock { active = false; return Array(tasks.values) }
        pending.forEach { $0.cancel() }
    }
    func apply(_ candidate: RecognitionCandidate, store: SaytileStore, ticket: RecognitionTicket) async {
        let id = UUID()
        let work = lock.withLock { () -> Task<Void, Never>? in
            guard active, tasks.count < 8 else { return nil }
            let work = Task { await review(candidate, store: store, ticket: ticket) }
            tasks[id] = work
            return work
        }
        guard let work else { return }
        await withTaskCancellationHandler { await work.value } onCancel: { work.cancel() }
        _ = lock.withLock { tasks.removeValue(forKey: id) }
    }
    private func review(_ candidate: RecognitionCandidate, store: SaytileStore, ticket: RecognitionTicket) async {
        var run: ModelRunTicket?
        do {
            try Task.checkCancellation()
            guard try await store.isRecognitionCurrent(ticket: ticket) else { return }
            let started = try await store.beginModelRun(ticket: ticket, configuration: model)
            run = started
            guard let credential = try dependencies.credential(model) else { throw CloudCredentialError.empty }
            let prefix = try await store.fusionReservedPrefix(recordingID: ticket.recordingID)
            try Task.checkCancellation()
            let (decision, usage) = try await dependencies.arbitrate([ReviewEvidence(candidate: candidate)], prefix, "", model, credential)
            try Task.checkCancellation()
            let protected = try await store.fusionReservedPrefix(recordingID: ticket.recordingID)
            let spans = decision.selections.map { CandidateSpan(candidateID: $0.candidateID, utf16Start: $0.utf16Start, utf16End: $0.utf16End) }
            let proposal = try PrecisionFusion.validateSelection(spans: spans, candidates: [candidate], committedPrefix: protected,
                unresolved: decision.unresolved, needsAudioReview: decision.needsAudioReview, reasonCode: decision.reasonCode)
            try await store.recordModelUsage(.init(runID: started.id, requestID: usage.requestID, audioSeconds: 0,
                inputTokens: usage.inputTokens, outputTokens: usage.outputTokens, cachedInputTokens: usage.cachedInputTokens,
                reasoningTokens: usage.reasoningTokens, elapsedSeconds: usage.elapsedSeconds,
                arbitrationResponse: .init(candidateIDs: [candidate.id], confirmedPrefix: prefix, decision: decision)))
            if !proposal.unresolved && !proposal.needsAudioReview {
                try Task.checkCancellation()
                _ = try await store.publishFusion(ticket: ticket, proposal: proposal)
            }
            try await store.finishModelRun(started, error: nil, retryable: true)
            NotificationCenter.default.post(name: .init("SaytileRecognitionUpdated"), object: ticket.recordingID)
        } catch {
            if let run { try? await store.finishModelRun(run, error: "文字复核未采用，保留本机原稿", retryable: false) }
        }
    }
}
