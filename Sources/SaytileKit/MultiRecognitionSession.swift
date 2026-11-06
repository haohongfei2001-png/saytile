import Foundation
import CryptoKit

/// Dependency injection exercises the real coordinator without credentials or cloud traffic.
struct RecognitionPipelineDependencies: Sendable {
    var credential: @Sendable (ModelConfiguration) throws -> String?
    var streaming: @Sendable (CloudProvider) throws -> any StreamingASRProvider
    var transcribe: @Sendable (Data, ModelConfiguration, String) async throws -> ProviderTranscriptEvent
    var arbitrate: @Sendable ([ReviewEvidence], String, String, ModelConfiguration, String) async throws -> (PrecisionReviewDecision, PrecisionReviewUsage)
    var listen: @Sendable (Data, ModelConfiguration, String) async throws -> (AudioReviewTranscript, PrecisionReviewUsage)
    var finalizationStarted: @Sendable () -> Void = {}
    static let live = RecognitionPipelineDependencies(
        credential: { try CloudCredentialStore.read(configurationID: $0.id, provider: $0.provider) },
        streaming: { provider in
            switch provider {
            case .qwenMessage: return QwenMessageProvider()
            case .assemblyAI: return AssemblyStreamingProvider()
            case .soniox: return SonioxStreamingProvider()
            case .meta: return MetaStreamingProvider()
            case .elevenLabsRealtime: throw ProviderFailure.configuration("本轮未启用 ElevenLabs 实时适配；可使用 Scribe v2 文件复核。")
            default: throw ProviderFailure.configuration("所选服务不是实时识别接口。")
            }
        },
        transcribe: { try await FinalASRProvider().transcribe(pcm: $0, configuration: $1, credential: $2) },
        arbitrate: { try await PrecisionReviewClient().arbitrate(evidence: $0, confirmedPrefix: $1, context: $2, configuration: $3, credential: $4) },
        listen: { try await PrecisionReviewClient().listen(pcm: $0, configuration: $1, credential: $2) })
}

final class MultiRecognitionSession: RecognitionSession, @unchecked Sendable {
    let recordingID: UUID
    private let completion = RecognitionSessionCompletion()
    private let fanout: RecognitionAudioFanout
    private let coordinator: MultiRecognitionCoordinator
    private let task: Task<Void, Never>
    private let finalizationTimeout: Duration
    var isComplete: Bool { completion.isComplete }
    init(store: SaytileStore, ticket: RecognitionTicket, configuration: RecognitionConfiguration,
         dependencies: RecognitionPipelineDependencies = .live,
         allowSingleExpertBaseline: Bool = false,
         finalizationTimeout: Duration = .seconds(480),
         onComplete: @escaping @Sendable () -> Void = {}) {
        self.recordingID = ticket.recordingID
        self.finalizationTimeout = finalizationTimeout
        let configs = configuration.enabledModels.filter { $0.purpose.isStreaming }
        let coordinator = MultiRecognitionCoordinator(store: store, ticket: ticket, configuration: configuration, dependencies: dependencies)
        self.coordinator = coordinator
        let fanout = RecognitionAudioFanout(ids: configs.map(\.id)) { id in
            Task { await coordinator.audioOverflow(configurationID: id) }
        }
        self.fanout = fanout
        let completion = completion
        task = Task {
            defer { completion.finish(); onComplete() }
            do {
                try configuration.validateForCloud(allowSingleExpertBaseline: allowSingleExpertBaseline)
                try await coordinator.attach(fanout)
                try Task.checkCancellation()
                try await withTaskCancellationHandler {
                    await withTaskGroup(of: Void.self) { group in
                        for (index, item) in configs.enumerated() {
                            let stream = fanout.channels[index].audio
                            group.addTask { await coordinator.runStreaming(item, audio: stream) }
                        }
                        await group.waitForAll()
                    }
                    try Task.checkCancellation()
                    // Live review is an independently scheduled task. Keep its
                    // finalization wait inside the same cancellation ownership.
                    await coordinator.finalize()
                    try Task.checkCancellation()
                } onCancel: {
                    fanout.finish()
                    Task { await coordinator.cancel() }
                }
            } catch {
                await coordinator.cancel()
                try? await store.failRecognition(ticket: ticket, message: error is CancellationError ? "识别已暂停，原音和候选已保留。" : Self.safeMessage(error))
            }
        }
    }
    func append(_ data: Data) { fanout.append(data) }
    func finish() {
        fanout.finish()
        let task = task, timeout = finalizationTimeout
        completion.watch(Task {
            // A liveness deadline never turns incomplete evidence into stable text.
            do { try await Task.sleep(for: timeout) } catch { return }
            task.cancel()
        })
    }
    func cancel() { fanout.finish(); task.cancel(); Task { await coordinator.cancel() } }
    func wait() async { await task.value }
    static func safeMessage(_ error: Error) -> String {
        if let error = error as? ProviderFailure { return error.localizedDescription }
        if let error = error as? FusionError { return error.localizedDescription }
        return "模型连接或处理失败；原音和候选已保留。"
    }
}

/// The only cloud component that publishes transcript revisions. Providers never see Store.
actor MultiRecognitionCoordinator {
    private let store: SaytileStore
    private let ticket: RecognitionTicket
    private let configuration: RecognitionConfiguration
    private let dependencies: RecognitionPipelineDependencies
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
    private var completedReviewAudioDigests: [UUID: String] = [:]
    private var cancelled = false
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
        self.store = store; self.ticket = ticket; self.configuration = configuration; self.dependencies = dependencies
    }
    func attach(_ audio: RecognitionAudioFanout) async throws {
        try await store.configureFusionRequirements(ticket: ticket, configurations: configuration.enabledModels)
        self.audio = audio
    }
    func cancel() async {
        cancelled = true
        // Retain ownership until the independent live review actually exits. An
        // overlapping cancellation must await the same task, not see an empty slot.
        let drainingReview = reviewTask
        drainingReview?.cancel()
        await drainingReview?.value
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
    private func scheduleLiveReview() {
        guard !ending, !cancelled, reviewTask == nil,
              configuration.enabledModels.contains(where: { $0.purpose == .textFusion && reviewEligible($0, finalAttempt: false) }) else { return }
        let candidates = activeEvidence()
        let present = Set(candidates.filter { !$0.text.isEmpty }.map { $0.run.configurationID })
        // A previous publish may have suspended while the other expert arrived. Decide
        // whether review is needed from this snapshot, not that older proposal.
        let current = PrecisionFusion.evaluate(candidates: candidates, mode: configuration.inputMode,
            committedPrefix: committedPrefix, requiredPurposes: requiredPurposes,
            requiredConfigurationIDs: requiredConfigurationIDs)
        guard current.unresolved, requiredConfigurationIDs.isSubset(of: present),
              signature(candidates) != lastReviewedSignature else { return }
        let version = evidenceVersion
        reviewTask = Task { [weak self] in
            guard let self else { return }
            await self.performTextReview(candidates: candidates, version: version)
            await self.reviewDidFinish()
        }
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
    private func performTextReview(candidates: [RecognitionCandidate], version: UInt64) async {
        let configured = configuration.enabledModels.filter { $0.purpose == .textFusion }
        let items = configured.filter { reviewEligible($0, finalAttempt: ending) }
        guard !items.isEmpty else { return }
        let present = Set(candidates.filter { !$0.text.isEmpty }.map { $0.run.configurationID })
        guard requiredConfigurationIDs.isSubset(of: present) || configuration.inputMode == .fast else { return }
        lastReviewedSignature = signature(candidates)
        // Every enabled arbiter runs. A failed or dissenting arbiter cannot silently
        // become an agreement vote in highest-quality mode.
        let replies = await withTaskGroup(of: TextReviewResult?.self) { group in
            for item in items { group.addTask { await self.requestTextReview(item, candidates: candidates) } }
            var result: [TextReviewResult] = []
            for await reply in group { if let reply { result.append(reply) } }
            return result.sorted { $0.item.id.uuidString < $1.item.id.uuidString }
        }
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
            if replies.contains(where: { $0.decision.needsAudioReview }), !ending {
                await performAcousticReviews(onlyIfNeeded: true)
            }
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
            }
            if checked.contains(where: { $0.1.needsAudioReview || $0.0.decision.needsAudioReview }), !ending {
                await performAcousticReviews(onlyIfNeeded: true)
            }
        } catch { /* Current candidate/epoch validation is authoritative; preserve alternatives. */ }
    }
    private func performAcousticReviews(onlyIfNeeded: Bool) async {
        let items = configuration.enabledModels.filter { [.audioReview, .finalASR].contains($0.purpose) && reviewEligible($0, finalAttempt: !onlyIfNeeded) }
        guard let pcm = audio?.snapshot, !pcm.isEmpty else {
            for item in items { failures[item.id] = "复核音频暂不可用；本次高精度复核未完成，原音仍可恢复。" }
            return
        }
        // Each acoustic source receives exactly the same bounded PCM snapshot. A completed
        // review of identical bytes is reusable at EOS; do not bill the same review twice.
        let digest = SHA256.hash(data: pcm).map { String(format: "%02x", $0) }.joined()
        await withTaskGroup(of: Void.self) { group in
            for item in items {
                if completedReviewAudioDigests[item.id] == digest, latest[item.id]?.isComplete == true { continue }
                if onlyIfNeeded, let previous = latest[item.id], previous.audioEndSeconds >= Double(pcm.count) / 32_000 - 0.1 { continue }
                group.addTask { await self.runAcousticReview(item, pcm: pcm, digest: digest) }
            }
            await group.waitForAll()
        }
    }
    private func runAcousticReview(_ item: ModelConfiguration, pcm: Data, digest: String) async {
        var run: ModelRunTicket?
        let began = Date(), seconds = Double(pcm.count) / 32_000
        do {
            try await assertCurrent()
            let created = try await store.beginModelRun(ticket: ticket, configuration: item); run = created
            let credential = try secret(for: item)
            let event: ProviderTranscriptEvent
            let usage: PrecisionReviewUsage
            try await assertCurrent()
            if item.purpose == .audioReview {
                let (result, measured) = try await dependencies.listen(pcm, item, credential)
                usage = measured
                event = .init(text: result.text, stableUTF16Length: result.uncertain ? 0 : result.text.utf16.count,
                              audioEndSeconds: seconds, timingGranularity: "utterance", isComplete: !result.uncertain,
                              requestID: measured.requestID)
            } else {
                event = try await dependencies.transcribe(pcm, item, credential)
                usage = .init(requestID: event.requestID, inputTokens: nil, outputTokens: nil, elapsedSeconds: Date().timeIntervalSince(began))
            }
            try await assertCurrent()
            let candidate = RecognitionCandidate(run: created, sequence: 1, event: event)
            guard try await store.appendRecognitionCandidate(candidate) else { throw FusionError.staleGeneration }
            latest[item.id] = candidate; evidenceVersion &+= 1
            if candidate.isComplete { completedReviewAudioDigests[item.id] = digest }
            failures.removeValue(forKey: item.id); reviewFailures.removeValue(forKey: item.id)
            reviewRetryAfter.removeValue(forKey: item.id)
            try await store.finishModelRun(created, error: nil, retryable: true)
            await logUsage(run: created, configuration: item, seconds: seconds, usage: usage)
            try await evaluateAndPublish()
        } catch {
            await recordReviewFailure(error, item: item)
            if let run {
                try? await store.finishModelRun(run, error: MultiRecognitionSession.safeMessage(error), retryable: (error as? ProviderFailure)?.canRetryAutomatically ?? true)
                await logUsage(run: run, configuration: item, seconds: seconds,
                    usage: .init(requestID: nil, inputTokens: nil, outputTokens: nil, elapsedSeconds: Date().timeIntervalSince(began)), estimateAllowed: false)
            }
        }
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
        await performAcousticReviews(onlyIfNeeded: false)
        do {
            try await assertCurrent()
            try await evaluateAndPublish()
            let current = activeEvidence()
            if lastProposal?.unresolved == true { await performTextReview(candidates: current, version: evidenceVersion) }
            try await assertCurrent()
            let live = latest.values.filter { $0.run.purpose.isStreaming }
            let missing = !requiredConfigurationIDs.isSubset(of: Set(live.filter(\.isComplete).map { $0.run.configurationID }))
            if !failures.isEmpty || missing || lastProposal?.unresolved != false {
                let failed = configuration.enabledModels.compactMap { item in failures[item.id].map { "\(item.purpose.label)：\($0)" } }
                let reason = failed.isEmpty ? "模型仍存在分歧或证据未齐，已保留全部候选和原音；未确认内容留在 Saytile。" : failed.joined(separator: "；")
                if failures.isEmpty { try await store.setRecognitionRetryable(ticket: ticket, retryable: false) }
                try await store.failRecognition(ticket: ticket, message: reason)
            } else { try await store.finishRecognition(ticket: ticket) }
        } catch {
            try? await store.failRecognition(ticket: ticket, message: MultiRecognitionSession.safeMessage(error))
        }
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
