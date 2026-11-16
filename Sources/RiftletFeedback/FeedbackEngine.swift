import Foundation

/// Only explicitly enqueued reports may perform HTTP. The single flight covers
/// submit, status and deletion; a request arriving during any flight is not lost.
public actor FeedbackEngine {
    public let store: FeedbackStore
    private let secrets: any FeedbackSecretStorage
    private let transport: any FeedbackTransport
    private var activeCredentialIDs = Set<String>()
    private var running = false
    private var pumpRequested = false
    private var wake: Task<Void, Never>?
    private var scheduleGeneration: UInt64 = 0
    private var stopped = false
    public nonisolated let configured: Bool

    public init(store: FeedbackStore, secrets: any FeedbackSecretStorage, transport: any FeedbackTransport) {
        self.store = store; self.secrets = secrets; self.transport = transport
        configured = transport.configured
    }

    public func enqueue(_ draft: FeedbackDraft, appVersion: String, product: FeedbackProduct? = nil) async throws -> String {
        await cleanupAbandonedCredentials()
        if let existing = try await store.submittedID(revision: draft.revision) { return existing }
        try await store.saveDraft(draft)
        let envelope = try FeedbackEnvelope(draft: draft, appVersion: appVersion, product: product)
        activeCredentialIDs.insert(envelope.id)
        defer { activeCredentialIDs.remove(envelope.id) }
        try await store.registerCredentialIntent(id: envelope.id)
        do {
            _ = try secrets.secret(for: envelope.id, create: true)
            let committedID = try await store.enqueue(envelope, from: draft)
            if committedID != envelope.id { await cleanupCredential(id: envelope.id) }
            return committedID
        } catch {
            // Query the durable ledger first; an ambiguous commit must never
            // discard a capability belonging to a persisted report.
            await cleanupCredential(id: envelope.id)
            throw error
        }
    }

    private func cleanupCredential(id: String) async {
        do {
            guard try await store.uncommittedCredentialIDs().contains(id) else { return }
            try secrets.remove(for: id)
            try await store.finishCredentialCleanup(id: id)
        } catch { /* Keep the intent for retry; never touch screenshot storage. */ }
    }
    private func cleanupAbandonedCredentials() async {
        guard let ids = try? await store.uncommittedCredentialIDs() else { return }
        for id in ids where !activeCredentialIDs.contains(id) {
            await cleanupCredential(id: id)
        }
    }

    public func pump() async {
        guard !stopped else { return }
        await cleanupAbandonedCredentials() // Local cleanup also works with the endpoint disabled.
        guard configured, !stopped else { return }
        guard !running else { pumpRequested = true; return }
        running = true; invalidateWake()
        repeat {
            pumpRequested = false
            do {
                let due = try await store.records().filter {
                    ($0.state == .queued || $0.state == .deletionQueued) && $0.nextAttempt <= Date()
                }.prefix(4)
                for record in due {
                    guard !stopped, !Task.isCancelled else { break }
                    let action: FeedbackRequest = record.state == .deletionQueued ? .delete : .submit
                    do {
                        let secret = try secrets.secret(for: record.id, create: false)
                        guard try await store.beginAttempt(id: record.id, expected: record.state) else { continue }
                        guard !stopped, !Task.isCancelled else { break }
                        let response = try await transport.perform(action, record: record, secret: secret)
                        try response.validate(for: record.id)
                        try await store.apply(response)
                    } catch {
                        let blocked: Bool
                        let delay: Double
                        switch error {
                        case FeedbackFailure.rejected, FeedbackFailure.conflict, FeedbackFailure.secretUnavailable:
                            blocked = true; delay = 3600
                        case FeedbackFailure.rateLimited(let seconds):
                            blocked = false; delay = Double(seconds)
                        default:
                            blocked = false; delay = min(3600, 5 * pow(2, Double(min(record.attempts, 9))))
                        }
                        try? await store.reschedule(id: record.id, expected: record.state, after: delay, blocked: blocked)
                    }
                }
            } catch { /* Retain the outbox; no error escapes into screenshot work. */ }
        } while pumpRequested && !stopped && !Task.isCancelled
        running = false
        try? await scheduleNext()
    }

    private func invalidateWake() {
        scheduleGeneration &+= 1
        wake?.cancel(); wake = nil
    }

    private func scheduleNext() async throws {
        guard !stopped, !running else { return }
        let generation = scheduleGeneration
        let pending = try await store.records().filter { $0.state == .queued || $0.state == .deletionQueued }
        // Another flight may have begun while SQLite was being read.
        guard !stopped, !running, generation == scheduleGeneration,
              let date = pending.map(\.nextAttempt).min() else { return }
        let delay = max(1, min(3600, date.timeIntervalSinceNow))
        wake?.cancel()
        wake = Task { [weak self] in
            do { try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000)) } catch { return }
            guard !Task.isCancelled else { return }
            await self?.scheduledWake(generation: generation)
        }
    }

    private func scheduledWake(generation: UInt64) async {
        guard !stopped, generation == scheduleGeneration else { return }
        // The timer task is now the caller of pump(). Release its handle before
        // pump invalidates any pending timer, or it cancels its own network work.
        wake = nil
        await pump()
    }

    public func refresh(id: String) async throws {
        guard configured, !running, !stopped else { return }
        // Acquire before the first await, including the local record read.
        running = true; invalidateWake()
        var failure: Error?
        do {
            if let record = try await store.records().first(where: { $0.id == id }),
               record.state != .cancelled, record.state != .deleted, !stopped {
                let secret = try secrets.secret(for: id, create: false)
                let receipt = try await transport.perform(.status, record: record, secret: secret)
                try receipt.validate(for: id)
                try await store.apply(receipt)
            }
        } catch { failure = error }
        running = false
        // Includes deletion/new sends and an expired timer that arrived during
        // GET. Also run after a failed GET; no second user action is required.
        await pump()
        if let failure { throw failure }
    }

    public func requestDeletion(id: String) async throws {
        try await store.requestDeletion(id: id)
        await pump()
    }

    /// Local forgetting is allowed only after no-send cancellation or confirmed
    /// server deletion. Remove the exact capability FIRST; if Keychain fails,
    /// keep the body and retryable cleanup entry. If SQLite fails afterwards,
    /// removal of a now-missing capability is idempotent on the next user retry.
    public func forgetResolved(id: String) async throws {
        guard let record = try await store.records().first(where: { $0.id == id }) else { return }
        guard record.state == .cancelled || record.state == .deleted else { throw FeedbackFailure.conflict }
        try secrets.remove(for: id)
        try await store.forgetResolved(id: id)
    }

    public func stop() { stopped = true; pumpRequested = false; invalidateWake() }
}
