import Foundation
import Testing
@testable import SaytileKit

private final class ConnectionCheckProbe: @unchecked Sendable {
    let lock = NSLock()
    private var reads = 0
    private var starts: [CloudProvider] = []
    private var stopped: [CloudProvider] = []
    private var bodies: [Data] = []
    private var contexts: [String] = []
    private var snapshots: [CloudConnectionReport] = []
    private var fallbacks = 0
    private var firstStart: ContinuousClock.Instant?
    private var lastStop: ContinuousClock.Instant?
    var readCount: Int { lock.withLock { reads } }
    var startCount: Int { lock.withLock { starts.count } }
    var stoppedCount: Int { lock.withLock { stopped.count } }
    var lifecycle: (started: Int, stopped: Int, active: Int, balanced: Bool) {
        lock.withLock {
            let startedByProvider = Dictionary(grouping: starts, by: { $0 }).mapValues { $0.count }
            let stoppedByProvider = Dictionary(grouping: stopped, by: { $0 }).mapValues { $0.count }
            return (starts.count, stopped.count, starts.count - stopped.count, startedByProvider == stoppedByProvider)
        }
    }
    var requests: [Data] { lock.withLock { bodies } }
    var observedContexts: [String] { lock.withLock { contexts } }
    var reports: [CloudConnectionReport] { lock.withLock { snapshots } }
    var fallbackCount: Int { lock.withLock { fallbacks } }
    var providerTiming: (firstStart: ContinuousClock.Instant?, lastStop: ContinuousClock.Instant?) {
        lock.withLock { (firstStart, lastStop) }
    }
    func read() { lock.withLock { reads += 1 } }
    func start(_ item: ModelConfiguration) {
        lock.withLock { if firstStart == nil { firstStart = .now }; starts.append(item.provider); contexts.append(item.context) }
    }
    func stop(_ provider: CloudProvider) { lock.withLock { stopped.append(provider); lastStop = .now } }
    func sent(_ data: Data) { lock.withLock { bodies.append(data) } }
    func update(_ report: CloudConnectionReport) { lock.withLock { snapshots.append(report) } }
    func fallback(_ context: String, item: ModelConfiguration) {
        lock.withLock { fallbacks += 1; contexts.append(context); contexts.append(item.context) }
    }
}

private struct ConnectionCheckProvider: StreamingASRProvider {
    let probe: ConnectionCheckProbe
    let ready: @Sendable () -> Void
    var failure: ProviderFailure?
    var silent = false
    var partialCount = 0
    func run(audio: AsyncStream<Data>, configuration: ModelConfiguration, credential: String,
             emit: @escaping @Sendable (ProviderTranscriptEvent) async throws -> Void) async throws {
        probe.start(configuration); defer { probe.stop(configuration.provider) }
        if let failure { throw failure }
        ready()
        if silent {
            while true { try await Task.sleep(for: .milliseconds(5)) }
        }
        var bytes = 0
        for await chunk in audio { try Task.checkCancellation(); bytes += chunk.count }
        try Task.checkCancellation()
        let text = "不要发送 send later"
        for index in 0..<partialCount {
            let partial = text + " \(index)"
            try await emit(.init(text: partial, stableUTF16Length: partial.utf16.count,
                                 audioEndSeconds: Double(bytes) / 32_000, isComplete: false))
            try await Task.sleep(for: .milliseconds(350))
        }
        try await emit(.init(text: text, stableUTF16Length: text.utf16.count,
                             audioEndSeconds: Double(bytes) / 32_000, isComplete: true))
    }
}

/// Private no-network peer; production GPT framing, budget, coordinator and Store still run.
private final class ConnectionCheckSocket: GPTReviewSocket, @unchecked Sendable {
    let probe: ConnectionCheckProbe
    let unsupported: Bool
    let firstReplyDelay: Duration?
    let boundedRetrySeries: Bool
    private let lock = NSLock()
    private var events: [Data] = []
    private var closed = false
    private var number = 0
    private var candidatesByID: [String: [String: Any]] = [:]
    init(_ probe: ConnectionCheckProbe, unsupported: Bool = false, firstReplyDelay: Duration? = nil, boundedRetrySeries: Bool = false) {
        self.probe = probe; self.unsupported = unsupported; self.firstReplyDelay = firstReplyDelay; self.boundedRetrySeries = boundedRetrySeries
    }
    var isClosed: Bool { lock.withLock { closed } }
    func send(_ data: Data) async throws {
        probe.sent(data)
        if boundedRetrySeries {
            if [1, 3, 5].contains(probe.requests.count) { throw URLError(.networkConnectionLost) }
            if probe.requests.count == 6 { throw GPTSocketFailure.unsupported }
        }
        if unsupported { throw GPTSocketFailure.unsupported }
        if let firstReplyDelay, probe.requests.count == 1 { try await Task.sleep(for: firstReplyDelay) }
        try lock.withLock {
            if closed { throw CancellationError() }
            number += 1
            let root = try JSONSerialization.jsonObject(with: data) as! [String: Any]
            let input = root["input"] as! [[String: Any]]
            let payload = try JSONSerialization.jsonObject(with: Data((input[0]["content"] as! String).utf8)) as! [String: Any]
            let candidates = payload["candidates"] as! [[String: Any]]
            if payload["resetEvidence"] as? Bool == true { candidatesByID.removeAll() }
            for candidate in candidates { candidatesByID[candidate["candidateID"] as! String] = candidate }
            let manifest = payload["currentManifest"] as! [[String: Any]]
            let currentID = try #require(manifest.first?["candidateID"] as? String)
            let candidate = try #require(candidatesByID[currentID])
            let id = try #require(UUID(uuidString: candidate["candidateID"] as! String))
            let text = candidate["text"] as! String
            let decision = PrecisionReviewDecision(selections: [.init(candidateID: id, utf16Start: 0, utf16End: text.utf16.count)],
                unresolved: false, needsAudioReview: false, reasonCode: "synthetic-connection-peer")
            let body = String(decoding: try JSONEncoder().encode(decision), as: UTF8.self)
            let responseID = "owned-connection-\(number)", lane = root["stream_id"] as! String
            events.append(try JSONSerialization.data(withJSONObject: ["type": "response.created", "stream_id": lane,
                "response": ["id": responseID, "model": "gpt-6-astra"]]))
            events.append(try JSONSerialization.data(withJSONObject: ["type": "response.completed", "stream_id": lane,
                "response": ["id": responseID, "model": "gpt-6-astra", "status": "completed", "output": [["type": "message",
                    "status": "completed", "content": [["type": "output_text", "text": body]]]]]]))
        }
    }
    func receive() async throws -> Data {
        while true {
            try Task.checkCancellation()
            if isClosed { throw CancellationError() }
            if let value = lock.withLock({ events.isEmpty ? nil : events.removeFirst() }) { return value }
            try await Task.sleep(for: .milliseconds(2))
        }
    }
    func close() { lock.withLock { closed = true } }
}

@Suite("Connection authorization, bounded cost and truthful evidence; no network or Keychain")
struct CloudConnectionVerificationTests {
    private func configuration() -> RecognitionConfiguration {
        var value = RecognitionConfiguration()
        value.languagePreference = .chinese
        value.topicContext = "PRIVATE_TOPIC_SENTINEL"
        for index in value.models.indices where value.models[index].enabled {
            value.models[index].cloudConsent = true
            value.models[index].context = "PRIVATE_MODEL_CONTEXT_SENTINEL"
            if value.models[index].provider == .qwenMessage { value.models[index].workspaceID = "owned-test" }
        }
        return value // cloud stays OFF: an authorized check must not mutate this choice.
    }
    private func transport(_ probe: ConnectionCheckProbe, silent: Bool = false,
                           failing: CloudProvider? = nil, unsupported: Bool = false, partialCount: Int = 0,
                           firstReplyDelay: Duration? = nil, boundedRetrySeries: Bool = false) -> CloudConnectionTransport {
        CloudConnectionTransport(live: false, credential: { _ in probe.read(); return "NOT_A_REAL_KEY_SENTINEL" },
            streaming: { provider, ready in
                ConnectionCheckProvider(probe: probe, ready: ready, failure: provider == failing ? .permission : nil,
                                        silent: silent, partialCount: partialCount)
            }, socket: { _ in ConnectionCheckSocket(probe, unsupported: unsupported, firstReplyDelay: firstReplyDelay,
                                                   boundedRetrySeries: boundedRetrySeries) },
            fallback: { evidence, _, context, item, _ in
                probe.fallback(context, item: item)
                let first = try #require(evidence.first)
                return (.init(selections: [.init(candidateID: first.candidateID, utf16Start: 0, utf16End: first.text.utf16.count)],
                    unresolved: false, needsAudioReview: false, reasonCode: "synthetic-http-peer"), .init(elapsedSeconds: 0))
            })
    }

    @Test(arguments: ["unauthorized", "no-consent", "empty-audio", "odd-audio", "oversized-audio"])
    func rejectsBeforeReadingCredentialsOrStartingNetwork(reason: String) async throws {
        let probe = ConnectionCheckProbe()
        var config = configuration(), pcm = Data(repeating: 0, count: 640)
        if reason == "no-consent" { config.models[0].cloudConsent = false }
        if reason == "empty-audio" { pcm = Data() }
        if reason == "odd-audio" { pcm = Data([0]) }
        if reason == "oversized-audio" { pcm = Data(repeating: 0, count: 384_002) }
        let chosen = config, sample = pcm
        await #expect(throws: (any Error).self) {
            try await CloudConnectionVerifier.run(configuration: chosen, authorized: reason != "unauthorized", pcm: sample,
                transport: transport(probe), paced: false, progress: { probe.update($0) })
        }
        #expect(probe.readCount == 0 && probe.startCount == 0 && probe.requests.isEmpty && probe.reports.isEmpty)
    }

    @Test func alreadyCancelledAttemptDoesNotReadCredentials() async throws {
        let probe = ConnectionCheckProbe(), config = configuration(), client = transport(probe)
        let task = Task {
            try? await Task.sleep(for: .seconds(10))
            return try await CloudConnectionVerifier.run(configuration: config, authorized: true, pcm: Data(repeating: 0, count: 640),
                transport: client, paced: false, progress: { probe.update($0) })
        }
        task.cancel()
        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(probe.readCount == 0 && probe.startCount == 0 && probe.requests.isEmpty)
    }

    @Test func missingCredentialFailsOnlyThatServiceWithoutConnectingOthers() async throws {
        let probe = ConnectionCheckProbe(), config = configuration()
        var client = transport(probe)
        client.credential = { item in probe.read(); return item.provider == .qwenMessage ? nil : "NOT_A_REAL_KEY_SENTINEL" }
        let report = try await CloudConnectionVerifier.run(configuration: config, authorized: true, pcm: Data(repeating: 0, count: 640),
            transport: client, paced: false, progress: { probe.update($0) })
        #expect(report.services.first { $0.provider == .qwenMessage }?.code == "authorization_failed")
        #expect(report.services.filter { $0.provider != .qwenMessage }.allSatisfy { $0.state == .waiting })
        #expect(probe.startCount == 0 && probe.requests.isEmpty && !report.canEnableCloud)
    }

    @Test func arbitraryUnderlyingErrorDoesNotLeakItsDescriptionIntoReports() async throws {
        let probe = ConnectionCheckProbe()
        var client = transport(probe)
        client.credential = { _ in
            throw NSError(domain: "OwnedCredentialFixture", code: 1,
                userInfo: [NSLocalizedDescriptionKey: "PRIVATE_ERROR_BODY_AND_KEY_SENTINEL"])
        }
        let report = try await CloudConnectionVerifier.run(configuration: configuration(), authorized: true, pcm: Data(repeating: 0, count: 640),
            transport: client, paced: false, progress: { probe.update($0) })
        let encoded = String(decoding: try JSONEncoder().encode(probe.reports + [report]), as: UTF8.self)
        #expect(!encoded.contains("PRIVATE_ERROR_BODY_AND_KEY_SENTINEL"))
        #expect(report.services.first?.code == "connection_failed" && probe.startCount == 0)
    }

    @Test func emptyOrIncompleteReportNeverAuthorizesCloud() {
        let config = configuration()
        var report = CloudConnectionReport(configurationFingerprint: CloudConnectionVerifier.fingerprint(config), date: Date(), live: true, services: [])
        #expect(report.readiness == .liveConnectionPending && !report.canEnableCloud)
        report.pipelineCompleted = true
        #expect(!report.canEnableCloud)
        report.services = config.activeModels.map { .init(id: $0.id, provider: $0.provider, state: .verified) }
        #expect(!report.canEnableCloud) // A completed flag with no transcription is not usable evidence.
        report.transcript = "owned synthetic result"
        #expect(report.readiness == .liveTranscriptionVerified && report.canEnableCloud)
        report.services[1] = report.services[0]
        #expect(!report.canEnableCloud)
    }

    @Test func identityChangesInvalidateButOfflineSwitchAndLocalTopicDoNot() {
        let config = configuration()
        let report = CloudConnectionReport(configurationFingerprint: CloudConnectionVerifier.fingerprint(config), date: Date(), live: false, services: [])
        var sameAccount = config
        sameAccount.cloudEnabled = true; sameAccount.topicContext = "new local topic"; sameAccount.automaticRecovery = false
        #expect(report.matches(sameAccount))
        for field in ["id", "model", "region", "workspace", "consent", "enabled", "credential"] {
            var changed = config
            switch field {
            case "id": changed.models[0].id = UUID()
            case "model": changed.models[0].model += "-changed"
            case "region": changed.models[0].region = "ap-southeast-1"
            case "workspace": changed.models[0].workspaceID = "other-owned-workspace"
            case "consent": changed.models[0].cloudConsent = false
            case "credential": changed.models[0].credentialGeneration = UUID()
            default: changed.models[0].enabled = false
            }
            #expect(!report.matches(changed))
        }
    }

    @Test func atomicBudgetAllowsExactlySixEvenWhenContended() async {
        let budget = ConnectionRequestBudget()
        let accepted = await withTaskGroup(of: Bool.self) { group in
            for _ in 0..<24 { group.addTask { do { try budget.reserve(); return true } catch { return false } } }
            var count = 0
            for await value in group where value { count += 1 }
            return count
        }
        #expect(accepted == 6 && budget.count == 6)
        #expect(ConnectionCheckLimits.maximumOutputTokens == 4096 && ConnectionCheckLimits.maximumDuration == .seconds(90))
    }

    @Test(arguments: [false, true])
    func completeSyntheticPipelineRemainsNonLiveAndDoesNotExportSecrets(unsupportedSocket: Bool) async throws {
        let probe = ConnectionCheckProbe(), config = configuration()
        let report = try await CloudConnectionVerifier.run(configuration: config, authorized: true, pcm: Data(repeating: 0, count: 6400),
            transport: transport(probe, unsupported: unsupportedSocket), paced: false, progress: { probe.update($0) })
        #expect(report.pipelineCompleted && report.services.allSatisfy { $0.state == .verified })
        #expect(report.transcript == "不要发送 send later" && report.readiness == .noAPIEngineeringReady && !report.canEnableCloud)
        #expect(!config.cloudEnabled && config.topicContext == "PRIVATE_TOPIC_SENTINEL")
        #expect(probe.observedContexts.allSatisfy { $0.isEmpty })
        #expect(report.reviewRequests == probe.requests.count + probe.fallbackCount && (1...6).contains(report.reviewRequests))
        #expect(unsupportedSocket ? probe.fallbackCount > 0 && probe.requests.count == 1 : probe.fallbackCount == 0)
        let encoded = String(decoding: try JSONEncoder().encode(probe.reports + [report]), as: UTF8.self)
        for secret in ["NOT_A_REAL_KEY_SENTINEL", "PRIVATE_TOPIC_SENTINEL", "PRIVATE_MODEL_CONTEXT_SENTINEL"] {
            #expect(!encoded.contains(secret))
            #expect(probe.requests.allSatisfy { !String(decoding: $0, as: UTF8.self).contains(secret) })
        }
        for body in probe.requests {
            let value = try JSONSerialization.jsonObject(with: body) as! [String: Any]
            #expect(value["max_output_tokens"] as? Int == 4096)
        }
    }

    @Test func selectedASRFailureDoesNotStartAnUnselectedProvider() async throws {
        let probe = ConnectionCheckProbe()
        let report = try await CloudConnectionVerifier.run(configuration: configuration(), authorized: true, pcm: Data(repeating: 0, count: 6400),
            transport: transport(probe, failing: .qwenMessage), paced: false, progress: { probe.update($0) })
        #expect(report.services.first { $0.provider == .qwenMessage }?.code == "permission_denied")
        #expect(report.services.filter { $0.provider.isStreaming }.count == 1)
        #expect(!report.services.contains { $0.provider == .assemblyAI })
        #expect(probe.startCount == 1 && !report.canEnableCloud)
    }

    @Test(arguments: [false, true])
    func fastPartialReviewsCannotConsumeFinalConfirmationBudget(withRetrySeries: Bool) async throws {
        let probe = ConnectionCheckProbe()
        let report = try await CloudConnectionVerifier.run(configuration: configuration(), authorized: true, pcm: Data(repeating: 0, count: 6400),
            transport: transport(probe, partialCount: 8, boundedRetrySeries: withRetrySeries),
            deadline: .seconds(5), paced: false, progress: { probe.update($0) })
        #expect(report.pipelineCompleted && report.services.allSatisfy { $0.state == .verified })
        #expect(report.transcript == "不要发送 send later" && report.reviewRequests <= 6)
        #expect(report.reviewRequests == probe.requests.count + probe.fallbackCount)
    }

    @Test func stalePartialReviewDoesNotInvalidateLaterAcceptedFinal() async throws {
        let probe = ConnectionCheckProbe()
        let report = try await CloudConnectionVerifier.run(configuration: configuration(), authorized: true, pcm: Data(repeating: 0, count: 6400),
            transport: transport(probe, partialCount: 2, firstReplyDelay: .milliseconds(450)),
            deadline: .seconds(5), paced: false, progress: { probe.update($0) })
        #expect(report.pipelineCompleted && report.transcript == "不要发送 send later")
        #expect(probe.requests.count >= 2)
        #expect(report.services.first { $0.provider == .openAIResponses }?.state == .verified)
        let fusionRuns = (report.runs ?? []).filter { $0.ticket.purpose == .textFusion }
        #expect(fusionRuns.contains { $0.state == .failed })
        #expect(fusionRuns.last?.state == .completed)
        #expect((report.usage ?? []).contains { $0.arbitrationResponse != nil })
    }

    @Test func deadlineAndExplicitCancellationEndOwnedProviders() async throws {
        func seconds(_ duration: Duration) -> Double {
            let parts = duration.components
            return Double(parts.seconds) + Double(parts.attoseconds) / 1e18
        }
        for explicit in [false, true] {
            let probe = ConnectionCheckProbe(), config = configuration(), client = transport(probe, silent: true)
            let began = ContinuousClock.now
            let task = Task {
                try await CloudConnectionVerifier.run(configuration: config, authorized: true, pcm: Data(repeating: 0, count: 640),
                    transport: client, deadline: explicit ? .seconds(2) : .milliseconds(40), paced: false, progress: { probe.update($0) })
            }
            defer { task.cancel() }
            var cancelRequestedAt: ContinuousClock.Instant?
            if explicit {
                // SQLite creation and runner scheduling precede the production
                // watchdog. They are setup, not cancellation latency.
                while probe.startCount < 1 && began.duration(to: .now) < .seconds(10) { try await Task.sleep(for: .milliseconds(2)) }
                #expect(probe.startCount == 1)
                #expect(probe.stoppedCount == 0)
                cancelRequestedAt = .now
                task.cancel()
                await #expect(throws: CancellationError.self) { try await task.value }
            } else {
                let report = try await task.value
                #expect(!report.pipelineCompleted && !report.canEnableCloud && report.reviewRequests == 0)
                // Silent providers have no normal completion path: cancellation
                // after the injected deadline must actually terminate this check.
                #expect(report.elapsedSeconds >= 0.040)
                #expect(report.services.contains { $0.code == "cancelled" })
            }
            let timing = probe.providerTiming
            let firstStarted = try #require(timing.firstStart), lastStopped = try #require(timing.lastStop)
            let stopAnchor = cancelRequestedAt ?? firstStarted
            #expect(stopAnchor.duration(to: lastStopped) >= .zero)
            #expect(stopAnchor.duration(to: lastStopped) < .seconds(2))
            // A watchdog may cancel before the second provider starts. The owner
            // must drain every provider that did start, not start extra work just
            // to satisfy an expected total of two.
            let ended = probe.lifecycle
            #expect(ended.started == 1)
            #expect(ended.stopped == ended.started && ended.active == 0 && ended.balanced)
            try await Task.sleep(for: .milliseconds(50))
            let settled = probe.lifecycle
            #expect(settled.started == ended.started && settled.stopped == ended.stopped && settled.active == 0 && settled.balanced)
            print("CONNECTION_LIFECYCLE mode=\(explicit ? "explicit-cancel" : "deadline") started=\(settled.started) stopped=\(settled.stopped) active=\(settled.active) per_provider_balanced=\(settled.balanced) setup_seconds=\(seconds(began.duration(to: firstStarted))) stop_anchor=\(explicit ? "cancel-request" : "first-provider-start") stop_seconds=\(seconds(stopAnchor.duration(to: lastStopped))) total_seconds=\(seconds(began.duration(to: .now)))")
        }
    }
}
