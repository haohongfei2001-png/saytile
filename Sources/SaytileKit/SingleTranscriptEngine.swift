import Foundation
import CryptoKit

/// The only cloud component that publishes transcript revisions. Providers never see Store.
actor SingleTranscriptEngine {
    private let store: SaytileStore
    private let ticket: RecognitionTicket
    private let configuration: RecognitionConfiguration
    private let dependencies: RecognitionPipelineDependencies
    private let reviewClient: GPTReviewSession?
    private var audio: RecognitionAudioFanout?
    private var latest: [UUID: RecognitionCandidate] = [:]
    private var sequences: [UUID: Int64] = [:]
    private var overflowed: Set<UUID> = []
    private var failures: [UUID: String] = [:]
    private var blockedConfigurations: Set<UUID> = []
    private var reviewFailures: [UUID: Int] = [:]
    private var reviewRetryAfter: [UUID: Date] = [:]
    private var requestIDs: [UUID: String] = [:]
    // Only durable external reservations are immutable, never merely displayed/stable text.
    private var committedPrefix = ""
    private var cancelled = false
    private var finalReviewAccepted = false
    private var ending = false
    private var evidenceVersion: UInt64 = 0
    private var reviewTask: Task<Void, Never>?
    private var lastReviewedSignature = ""
    private var lastProposal: FusionProposal?
    private var lastPublishedEvidenceVersion: UInt64?
    private var firstPreview: Date?
    private var firstStable: Date?
    private let began = Date()
    init(store: SaytileStore, ticket: RecognitionTicket, configuration: RecognitionConfiguration,
         dependencies: RecognitionPipelineDependencies) {
        self.store = store; self.ticket = ticket; self.configuration = configuration
        let client = dependencies.makeReviewClient?()
        self.reviewClient = client
        var scoped = dependencies
        if let client {
            scoped.arbitrate = { try await client.review(evidence: $0, prefix: $1, context: $2, configuration: $3, credential: $4) }
        }
        self.dependencies = scoped
    }
    func attach(_ audio: RecognitionAudioFanout) async throws {
        try await store.configureFusionRequirements(ticket: ticket, configurations: configuration.enabledModels)
        self.audio = audio
    }
    func cancel() async {
        cancelled = true
        // Keep the task owned across all cancellation callers until it exits.
        let drainingReview = reviewTask
        drainingReview?.cancel()
        // Close the persistent transport before awaiting its consumer. Otherwise
        // a receive that needs socket closure could deadlock the drain.
        await reviewClient?.cancel()
        await drainingReview?.value
    }
    /// On-demand acoustic evidence uses durable samples, never a lifetime buffer.
    func audioEvidence(startFrame: Int64, frameCount: Int) async throws -> Data {
        try await assertCurrent()
        return try await store.readPCMRange(ticket: ticket, startFrame: startFrame, frameCount: frameCount)
    }
    func audioOverflow(configurationID: UUID) { overflowed.insert(configurationID) }
    private var requiredPurposes: Set<RecognitionPurpose> {
        Set(configuration.enabledModels.filter { $0.purpose.isStreaming }.map(\.purpose))
    }
    private var requiredConfigurationIDs: Set<UUID> {
        Set(configuration.enabledModels.filter { $0.purpose.isStreaming }.map(\.id))
    }
    private func assertCurrent() async throws {
        try Task.checkCancellation()
        guard !cancelled, try await store.isRecognitionCurrent(ticket: ticket) else { throw FusionError.staleGeneration }
    }
    private func secret(for item: ModelConfiguration) throws -> String {
        guard item.cloudConsent else { throw ProviderFailure.authorization }
        try item.validate()
        guard let key = try dependencies.credential(item), !key.isEmpty else {
            throw ProviderFailure.configuration("\(item.purpose.label)缺少 API Key；原音继续保存。")
        }
        return key
    }
    func runStreaming(_ item: ModelConfiguration, audio stream: AsyncStream<Data>) async {
        var run: ModelRunTicket?
        let began = Date()
        do {
            try await assertCurrent()
            let created = try await store.beginModelRun(ticket: ticket, configuration: item)
            run = created
            let credential = try secret(for: item)
            var requestConfig = item
            requestConfig.context = [item.context, configuration.topicContext].filter { !$0.isEmpty }.joined(separator: "\n")
            let provider = try dependencies.streaming(item.provider)
            try await assertCurrent()
            try await provider.run(audio: stream, configuration: requestConfig, credential: credential) { event in
                try await self.receive(event, run: created)
            }
            try await assertCurrent()
            guard self.audio?.isFinished == true, !overflowed.contains(item.id), self.audio?.didOverflow(item.id) != true,
                  latest[item.id]?.isComplete == true else { throw ProviderFailure.incomplete }
            failures.removeValue(forKey: item.id)
            try await store.finishModelRun(created, error: nil, retryable: true)
            await logUsage(run: created, configuration: item, seconds: self.audio?.duration ?? 0,
                           usage: .init(requestID: requestIDs[created.id], inputTokens: nil, outputTokens: nil, elapsedSeconds: Date().timeIntervalSince(began)))
        } catch {
            let reason = MultiRecognitionSession.safeMessage(error)
            failures[item.id] = reason
            evidenceVersion &+= 1
            let retryable = (error as? ProviderFailure)?.canRetryAutomatically ?? true
            if let run {
                try? await store.finishModelRun(run, error: reason, retryable: retryable)
                await logUsage(run: run, configuration: item, seconds: self.audio?.duration ?? 0,
                               usage: .init(requestID: requestIDs[run.id], inputTokens: nil, outputTokens: nil, elapsedSeconds: Date().timeIntervalSince(began)), estimateAllowed: false)
            }
            if !retryable { try? await store.setRecognitionRetryable(ticket: ticket, retryable: false) }
            // Surface failure while other streams are still live. Retain their actual candidates;
            // a failed/missing expert never becomes an agreement vote.
            if !cancelled { try? await evaluateAndPublish() }
        }
    }
    private func receive(_ event: ProviderTranscriptEvent, run: ModelRunTicket) async throws {
        try await assertCurrent()
        guard !overflowed.contains(run.configurationID), audio?.didOverflow(run.configurationID) != true else { throw ProviderFailure.incomplete }
        let sequence = (sequences[run.id] ?? 0) + 1; sequences[run.id] = sequence
        let candidate = RecognitionCandidate(run: run, sequence: sequence, event: event)
        guard try await store.appendRecognitionCandidate(candidate) else { throw FusionError.staleGeneration }
        if let requestID = event.requestID { requestIDs[run.id] = requestID }
        latest[run.configurationID] = candidate
        evidenceVersion &+= 1
        try await evaluateAndPublish()
        scheduleLiveReview()
    }
    private func activeEvidence() -> [RecognitionCandidate] {
        let live = latest.values.filter { $0.run.purpose.isStreaming }
        // Completed review of an earlier prefix remains archived but must not cap all
        // subsequent live agreement or masquerade as coverage of later audio.
        let horizon = live.map(PrecisionFusion.reviewRetirementHorizon).min() ?? 0
        return latest.values.filter { item in
            item.run.purpose != .textFusion && (item.run.purpose.isStreaming || item.audioEndSeconds + 0.1 >= horizon)
        }.sorted { $0.id.uuidString < $1.id.uuidString }
    }
    private func stableAudioEnd(_ candidate: RecognitionCandidate) -> Double {
        PrecisionFusion.stableAudioEnd(candidate)
    }
    private func haveRequiredEvidence(_ candidates: [RecognitionCandidate]) -> Bool {
        let available = Set(candidates.filter { $0.stableUTF16Length > 0 }.map { $0.run.configurationID })
        return requiredConfigurationIDs.isSubset(of: available)
    }
    nonisolated static func reviewSignature(_ candidates: [RecognitionCandidate]) -> String {
        // Ignore notification identity/time, while retaining every semantic token/timing
        // change. Newly supplied alignment can turn an earlier abstention into a safe splice.
        let canonical = candidates.sorted { $0.run.configurationID.uuidString < $1.run.configurationID.uuidString }.map {
            RecognitionCandidate(id: $0.run.id, run: $0.run, sequence: 0, text: $0.text,
                stableUTF16Length: $0.stableUTF16Length, audioStartSeconds: $0.audioStartSeconds,
                audioEndSeconds: $0.audioEndSeconds, timingGranularity: $0.timingGranularity,
                language: $0.language, isComplete: $0.isComplete, tokens: $0.tokens,
                createdAt: Date(timeIntervalSince1970: 0))
        }
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(canonical) else {
            return candidates.map { $0.id.uuidString }.sorted().joined(separator: ":")
        }
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
    private func signature(_ candidates: [RecognitionCandidate]) -> String { Self.reviewSignature(candidates) }
    private func evaluateAndPublish() async throws {
        let candidates = activeEvidence()
        committedPrefix = try await store.fusionReservedPrefix(recordingID: ticket.recordingID)
        var proposal = PrecisionFusion.evaluate(candidates: candidates, mode: configuration.inputMode,
            committedPrefix: committedPrefix, requiredPurposes: requiredPurposes,
            requiredConfigurationIDs: requiredConfigurationIDs)
        if configuration.inputMode == .highestQuality,
           !requiredConfigurationIDs.isSubset(of: Set(candidates.map { $0.run.configurationID })) {
            proposal = FusionProposal(previewText: proposal.previewText, stableText: committedPrefix,
                sourceCandidateIDs: proposal.sourceCandidateIDs, unresolved: true, needsAudioReview: false,
                reasonCode: "waiting-all-enabled-experts")
        }
        let failedExperts = configuration.enabledModels.filter { $0.purpose.isStreaming && failures[$0.id] != nil }
        if configuration.inputMode == .highestQuality, !failedExperts.isEmpty {
            proposal = FusionProposal(previewText: proposal.previewText, stableText: committedPrefix,
                sourceCandidateIDs: proposal.sourceCandidateIDs, unresolved: true, needsAudioReview: proposal.needsAudioReview,
                reasonCode: "expert-failed-evidence-retained")
        }
        try await publish(proposal)
    }
    private func publish(_ proposal: FusionProposal) async throws {
        try await assertCurrent()
        guard !proposal.sourceCandidateIDs.isEmpty else { return }
        let publishingVersion = evidenceVersion
        if proposal == lastProposal && lastPublishedEvidenceVersion == publishingVersion { return }
        let result = try await store.publishFusion(ticket: ticket, proposal: proposal, audioSubmittedSeconds: audio?.duration)
        NotificationCenter.default.post(name: .init("SaytileRecognitionUpdated"), object: ticket.recordingID)
        // Store may reject stale evidence or retain more uncertainty after transaction
        // revalidation. A submitted proposal is not proof of an accepted decision.
        guard let accepted = result.acceptedProposal, publishingVersion == evidenceVersion else { return }
        lastProposal = accepted
        lastPublishedEvidenceVersion = publishingVersion
        if firstPreview == nil, !accepted.previewText.isEmpty { firstPreview = Date() }
        if result.published, let revision = result.revision, firstStable == nil, !revision.text.isEmpty { firstStable = Date() }
        committedPrefix = try await store.fusionReservedPrefix(recordingID: ticket.recordingID)
    }
    private var liveReviewCount = 0
    private func scheduleLiveReview() {
        if let limit = dependencies.maximumLiveReviews, liveReviewCount >= limit { return }
        guard !ending, !cancelled, reviewTask == nil,
              configuration.enabledModels.filter({ $0.purpose == .textFusion && reviewEligible($0, finalAttempt: false) }).count == 1 else { return }
        let candidates = activeEvidence()
        let present = Set(candidates.filter { !$0.text.isEmpty }.map { $0.run.configurationID })
        guard requiredConfigurationIDs.isSubset(of: present),
              signature(candidates) != lastReviewedSignature else { return }
        reviewTask = Task { [weak self] in
            do { try await Task.sleep(for: .milliseconds(280)) } catch { return }
            guard let self else { return }
            await self.performLatestTextReview()
            await self.reviewDidFinish()
        }
    }
    private func performLatestTextReview() async {
        let candidates = activeEvidence()
        let present = Set(candidates.filter { !$0.text.isEmpty }.map { $0.run.configurationID })
        guard requiredConfigurationIDs.isSubset(of: present),
              signature(candidates) != lastReviewedSignature else { return }
        if let limit = dependencies.maximumLiveReviews, liveReviewCount >= limit { return }
        liveReviewCount += 1
        await performTextReview(candidates: candidates, version: evidenceVersion)
    }
    private func reviewDidFinish() {
        reviewTask = nil
        // Coalesce all changes during a request into one current-evidence request.
        if !ending && !cancelled { scheduleLiveReview() }
    }
    private func reviewEligible(_ item: ModelConfiguration, finalAttempt: Bool) -> Bool {
        guard !blockedConfigurations.contains(item.id) else { return false }
        if finalAttempt { return true }
        return (reviewFailures[item.id] ?? 0) < 3 && (reviewRetryAfter[item.id] ?? .distantPast) <= Date()
    }
    private func recordReviewFailure(_ error: Error, item: ModelConfiguration) async {
        failures[item.id] = MultiRecognitionSession.safeMessage(error)
        let retryable = (error as? ProviderFailure)?.canRetryAutomatically ?? true
        if !retryable {
            blockedConfigurations.insert(item.id)
            try? await store.setRecognitionRetryable(ticket: ticket, retryable: false)
        } else {
            let count = (reviewFailures[item.id] ?? 0) + 1
            reviewFailures[item.id] = count
            reviewRetryAfter[item.id] = Date().addingTimeInterval(min(30, pow(2, Double(count))))
        }
    }
    private struct TextReviewResult: Sendable {
        let item: ModelConfiguration
        let run: ModelRunTicket
        let decision: PrecisionReviewDecision
    }
    private func requestTextReview(_ item: ModelConfiguration, candidates: [RecognitionCandidate]) async -> TextReviewResult? {
        var run: ModelRunTicket?
        let started = Date()
        do {
            try await assertCurrent()
            let created = try await store.beginModelRun(ticket: ticket, configuration: item); run = created
            let credential = try secret(for: item)
            let evidence = candidates.map { ReviewEvidence(candidate: $0) }
            let requestPrefix = try await store.fusionReservedPrefix(recordingID: ticket.recordingID)
            committedPrefix = requestPrefix
            try await assertCurrent()
            let (decision, usage) = try await dependencies.arbitrate(evidence, requestPrefix,
                configuration.topicContext, item, credential)
            await logUsage(run: created, configuration: item, seconds: 0, usage: usage,
                arbitrationResponse: .init(candidateIDs: candidates.map(\.id), confirmedPrefix: requestPrefix, decision: decision))
            try await assertCurrent()
            failures.removeValue(forKey: item.id); reviewFailures.removeValue(forKey: item.id)
            reviewRetryAfter.removeValue(forKey: item.id)
            return TextReviewResult(item: item, run: created, decision: decision)
        } catch {
            await recordReviewFailure(error, item: item)
            if let run {
                try? await store.finishModelRun(run, error: MultiRecognitionSession.safeMessage(error), retryable: (error as? ProviderFailure)?.canRetryAutomatically ?? true)
                await logUsage(run: run, configuration: item, seconds: 0,
                    usage: .init(requestID: nil, inputTokens: nil, outputTokens: nil, elapsedSeconds: Date().timeIntervalSince(started)), estimateAllowed: false)
            }
            return nil
        }
    }
    private func performTextReview(candidates: [RecognitionCandidate], version: UInt64, finalAttempt: Bool = false) async {
        let configured = configuration.enabledModels.filter { $0.purpose == .textFusion }
        guard configured.count == 1 else { return }
        let items = configured.filter { reviewEligible($0, finalAttempt: finalAttempt) }
        guard items.count == 1 else { return }
        let present = Set(candidates.filter { !$0.text.isEmpty }.map { $0.run.configurationID })
        guard requiredConfigurationIDs.isSubset(of: present) || configuration.inputMode == .fast else { return }
        lastReviewedSignature = signature(candidates)
        // Exactly one review request is in flight for this recording/generation.
        let reply = await requestTextReview(items[0], candidates: candidates)
        let replies = reply.map { [$0] } ?? []
        guard !cancelled else { return }
        let current = activeEvidence()
        guard let protectedPrefix = try? await store.fusionReservedPrefix(recordingID: ticket.recordingID) else { return }
        committedPrefix = protectedPrefix
        var checked: [(TextReviewResult, FusionProposal)] = []
        for reply in replies {
            do {
                try await assertCurrent()
                let spans = reply.decision.selections.map { CandidateSpan(candidateID: $0.candidateID, utf16Start: $0.utf16Start, utf16End: $0.utf16End) }
                let proposal = try PrecisionFusion.rebaseSelection(spans: spans,
                    previousCandidates: candidates, currentCandidates: current, committedPrefix: committedPrefix,
                    unresolved: reply.decision.unresolved, needsAudioReview: reply.decision.needsAudioReview,
                    reasonCode: reply.decision.reasonCode)
                checked.append((reply, proposal))
                try await store.finishModelRun(reply.run, error: nil, retryable: true)
            } catch {
                // The network call may have succeeded while its evidence became stale.
                // Record the rejected decision, rather than claiming a successful fusion.
                try? await store.finishModelRun(reply.run, error: MultiRecognitionSession.safeMessage(error), retryable: true)
                if let fusionError = error as? FusionError, case .staleGeneration = fusionError { /* New audio superseded evidence. */ }
                else { await recordReviewFailure(error, item: reply.item) }
            }
        }
        guard var proposal = checked.first?.1 else {
            return
        }
        do {
            let requiredHealthy = requiredConfigurationIDs.isSubset(of: Set(current.map { $0.run.configurationID })) &&
                configuration.enabledModels.filter { $0.purpose.isStreaming }.allSatisfy { failures[$0.id] == nil }
            let agrees = requiredHealthy && checked.count == configured.count && checked.allSatisfy {
                $0.1.previewText.utf16.elementsEqual(proposal.previewText.utf16) &&
                $0.1.stableText.utf16.elementsEqual(proposal.stableText.utf16) && !$0.1.needsAudioReview
            }
            if configuration.inputMode == .highestQuality && !agrees {
                proposal = try PrecisionFusion.validateSelection(spans: proposal.selections, candidates: current,
                    committedPrefix: committedPrefix, unresolved: true,
                    needsAudioReview: checked.contains { $0.1.needsAudioReview }, reasonCode: "arbiters-not-in-agreement")
            }
            if checked.contains(where: { $0.1.unresolved }) && !proposal.unresolved {
                proposal = FusionProposal(previewText: proposal.previewText, stableText: proposal.stableText,
                    sourceCandidateIDs: proposal.sourceCandidateIDs, unresolved: true,
                    needsAudioReview: proposal.needsAudioReview, reasonCode: "arbiter-retains-uncertainty",
                    selections: proposal.selections, selectionRequestedUnresolved: proposal.selectionRequestedUnresolved,
                    reviewedCandidateIDs: candidates.map(\.id))
            }
            let selectedEnd = try proposal.selections.map { span -> Double in
                guard let source = current.first(where: { $0.id == span.candidateID }) else { throw FusionError.staleGeneration }
                return try PrecisionFusion.audioInterval(span: span, candidate: source).end
            }.max() ?? 0
            let coverage = current.filter { $0.run.purpose.isStreaming }.map(stableAudioEnd).min() ?? 0
            if proposal.stableText == committedPrefix || configuration.inputMode == .fast ||
                selectedEnd <= coverage + 0.1 || ending && current.filter({ $0.run.purpose.isStreaming }).allSatisfy(\.isComplete) {
                try await publish(proposal)
                if finalAttempt, version == evidenceVersion, lastProposal?.unresolved == false,
                   lastPublishedEvidenceVersion == version, !proposal.needsAudioReview {
                    finalReviewAccepted = true
                }
            }
        } catch { /* Current candidate/epoch validation is authoritative; preserve alternatives. */ }
    }
    func finalize() async {
        ending = true
        dependencies.finalizationStarted()
        await reviewTask?.value
        reviewTask = nil
        guard !cancelled else { return }
        guard audio?.isFinished == true else {
            try? await store.failRecognition(ticket: ticket, message: "识别连接提前结束；当前原音继续保存，停顿后可恢复。")
            return
        }
        do {
            try await assertCurrent()
            try await evaluateAndPublish()
            let current = activeEvidence()
            // EOS forces a new review even after identical ASR agreement or a live review.
            await performTextReview(candidates: current, version: evidenceVersion, finalAttempt: true)
            try await assertCurrent()
            let live = latest.values.filter { $0.run.purpose.isStreaming }
            let missing = !requiredConfigurationIDs.isSubset(of: Set(live.filter(\.isComplete).map { $0.run.configurationID }))
            if !finalReviewAccepted || !failures.isEmpty || missing || lastProposal?.unresolved != false {
                let failed = configuration.enabledModels.compactMap { item in failures[item.id].map { "\(item.purpose.label)：\($0)" } }
                let reason = failed.isEmpty ? "模型仍存在分歧或证据未齐，已保留全部候选和原音；未确认内容留在 Saytile。" : failed.joined(separator: "；")
                if failures.isEmpty { try await store.setRecognitionRetryable(ticket: ticket, retryable: false) }
                try await store.failRecognition(ticket: ticket, message: reason)
            } else { try await store.finishRecognition(ticket: ticket) }
        } catch {
            try? await store.failRecognition(ticket: ticket, message: MultiRecognitionSession.safeMessage(error))
        }
        await reviewClient?.cancel()
    }
    private func logUsage(run: ModelRunTicket, configuration item: ModelConfiguration, seconds: Double,
                          usage: PrecisionReviewUsage, estimateAllowed: Bool = true,
                          arbitrationResponse: ArbitrationResponseEvidence? = nil) async {
        // AssemblyAI streaming bills connection duration; file services bill audio duration.
        let billedSeconds = item.provider == .assemblyAI ? usage.elapsedSeconds : seconds
        var estimate: Double?
        if estimateAllowed, let rate = item.audioHourRate, seconds > 0 { estimate = billedSeconds / 3600 * rate }
        if estimateAllowed, let input = usage.inputTokens, let rate = item.inputMillionTokenRate,
           let output = usage.outputTokens, let outputRate = item.outputMillionTokenRate {
            estimate = (estimate ?? 0) + Double(input) / 1_000_000 * rate + Double(output) / 1_000_000 * outputRate
        }
        try? await store.recordModelUsage(ModelUsageRecord(runID: run.id, requestID: usage.requestID,
            audioSeconds: seconds, inputTokens: usage.inputTokens, outputTokens: usage.outputTokens,
            estimatedCost: estimate, currency: item.currency,
            status: estimateAllowed ? "response-received" : "failed-usage-unknown", elapsedSeconds: usage.elapsedSeconds,
            arbitrationResponse: arbitrationResponse))
    }
}


/// Compatibility alias for existing tests and internal callers during migration.
typealias MultiRecognitionCoordinator = SingleTranscriptEngine
