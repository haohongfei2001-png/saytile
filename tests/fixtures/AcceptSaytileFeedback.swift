import CryptoKit
import Darwin
import Foundation
import RiftletFeedback

private let syntheticText = "Synthetic Saytile feedback delivery acceptance. No user content or diagnostics."

private enum ProbeError: Error { case invalidState, invalidArguments, invalidWire }

// The capability is random, report-scoped and held only in this private acceptance directory.
private struct FixtureSecret: FeedbackSecretStorage {
    let value: String
    func secret(for id: String, create: Bool) throws -> String { value }
    func remove(for id: String) throws {}
}

private func capability(at directory: URL, prepare: Bool, offline: Bool) throws -> (FixtureSecret, Bool) {
    let file = directory.appendingPathComponent(offline ? "offline-probe.cap" : "live-probe.cap")
    let created = prepare && mkdir(directory.path, 0o700) == 0
    if created {
        var random = SystemRandomNumberGenerator()
        let value = (0..<32).map { _ in String(format: "%02x", UInt8.random(in: .min ... .max, using: &random)) }.joined()
        try Data(value.utf8).write(to: file, options: .withoutOverwriting)
    }
    var info = stat()
    guard lstat(directory.path, &info) == 0, info.st_mode & S_IFMT == S_IFDIR,
          info.st_uid == getuid(), info.st_mode & 0o777 == 0o700,
          lstat(file.path, &info) == 0, info.st_mode & S_IFMT == S_IFREG,
          info.st_uid == getuid(), info.st_mode & 0o777 == 0o600, info.st_size == 64 else { throw ProbeError.invalidState }
    let value = try String(contentsOf: file, encoding: .utf8)
    guard value.range(of: "^[a-f0-9]{64}$", options: .regularExpression) != nil else { throw ProbeError.invalidState }
    return (FixtureSecret(value: value), created)
}

private func verifyWire(_ record: FeedbackRecord) throws {
    let wire = try JSONSerialization.jsonObject(with: record.bytes) as? [String: Any]
    let envelope = record.envelope
    guard let wire, Set(wire.keys) == ["schema", "id", "appVersion", "createdAt", "kind", "product", "text"],
          envelope.schema == 1, envelope.product == .saytile, envelope.id == record.id,
          UUID(uuidString: record.id) != nil, envelope.kind == .problem, envelope.text == syntheticText,
          envelope.diagnostic == nil, try envelope.encoded() == record.bytes else { throw ProbeError.invalidWire }
}

// No offline request creates a URLSession. Production HTTPS is selected only by explicit live commands.
private struct OfflineWire: FeedbackTransport {
    let configured = true
    let loseReply: Bool
    func perform(_ action: FeedbackRequest, record: FeedbackRecord, secret: String) async throws -> FeedbackReceipt {
        try verifyWire(record)
        if loseReply { throw FeedbackFailure.transport }
        switch action {
        case .submit: return FeedbackReceipt(id: record.id)
        case .status: return FeedbackReceipt(id: record.id, state: "delivered")
        case .delete: throw ProbeError.invalidArguments
        }
    }
}

private actor SingleSubmission: FeedbackTransport {
    nonisolated let configured = true
    private let underlying: any FeedbackTransport
    private var used = false
    private(set) var receipt: FeedbackReceipt?
    init(_ underlying: any FeedbackTransport) { self.underlying = underlying }

    func perform(_ action: FeedbackRequest, record: FeedbackRecord, secret: String) async throws -> FeedbackReceipt {
        guard case .submit = action, !used, record.attempts == 0 else { throw ProbeError.invalidState }
        used = true
        try verifyWire(record)
        let response = try await underlying.perform(action, record: record, secret: secret)
        receipt = response
        return response
    }
}

@main private struct AcceptSaytileFeedback {
    static func main() async {
        do { exit(try await run()) }
        catch { fputs("Probe could not verify isolated state, arguments, or response. Use the original prepared directory.\n", stderr); exit(1) }
    }

    @MainActor static func run() async throws -> Int32 {
        umask(0o077)
        let args = CommandLine.arguments
        guard args.count == 4 else { throw ProbeError.invalidArguments }
        let offline = args[1].hasPrefix("offline-")
        let action = offline ? String(args[1].dropFirst("offline-".count)) : args[1]
        // Preserve the original leaf for lstat. Standardizing it can follow an existing
        // symlink, and Foundation can spell /private/tmp as /tmp on macOS.
        let directory = URL(fileURLWithPath: args[2])
        let temporaryRoot = URL(fileURLWithPath: "/private/tmp").resolvingSymlinksInPath().path
        let parent = directory.deletingLastPathComponent().resolvingSymlinksInPath().path
        let directTempChild = args[2].wholeMatch(of: #/\/(private\/)?tmp\/saytile-feedback-[A-Za-z0-9._-]+/#) != nil
        guard ["prepare", "submit", "status"].contains(action) || (offline && action == "lose"),
              offline || (directTempChild && parent == temporaryRoot),
              args[3].range(of: #"^[0-9]{1,4}(\.[0-9]{1,4}){0,3}$"#, options: .regularExpression) != nil else {
            throw ProbeError.invalidArguments
        }
        let endpoint = FeedbackSettingsModel.endpoint
        guard endpoint.absoluteString == "https://riftlet-feedback-receiver.haohongfei2001.workers.dev/v1/feedback" else {
            throw ProbeError.invalidArguments
        }
        let (secrets, fresh) = try capability(at: directory, prepare: action == "prepare", offline: offline)
        let outbox = directory.appendingPathComponent("outbox")
        guard fresh || FileManager.default.fileExists(atPath: outbox.appendingPathComponent("feedback.sqlite").path) else {
            throw ProbeError.invalidState
        }
        let store = try FeedbackStore(directory: outbox)
        var records = try await store.records()
        if fresh && records.isEmpty {
            let engine = FeedbackEngine(store: store, secrets: secrets, transport: DisabledFeedbackTransport())
            _ = try await engine.enqueue(FeedbackDraft(text: syntheticText, revision: 1), appVersion: args[3], product: .saytile)
            records = try await store.records()
        }
        guard records.count == 1, let record = records.first else { throw ProbeError.invalidState }
        try verifyWire(record)
        var result = "prepared"
        var code: Int32 = 0
        if action != "prepare" {
            let transport: any FeedbackTransport = offline ? OfflineWire(loseReply: action == "lose") : try HTTPSFeedbackTransport(endpoint: endpoint)
            if action == "status" {
                guard record.attempts > 0 else { throw ProbeError.invalidState }
                do {
                    // FeedbackEngine.refresh also pumps queued reports. A probe status check must only GET.
                    let response = try await transport.perform(.status, record: record, secret: secrets.value)
                    try response.validate(for: record.id)
                    try await store.apply(response)
                    result = response.state
                } catch { result = "unknown"; code = 2 }
            } else if record.state == .queued && record.attempts == 0 {
                let single = SingleSubmission(transport)
                let engine = FeedbackEngine(store: store, secrets: secrets, transport: single)
                await engine.pump()
                await engine.stop()
                if let response = await single.receipt { result = response.state }
                else { result = "unknown"; code = 2 }
            } else {
                result = "already-attempted"; code = 2
            }
        }
        guard let stored = try await store.records().first else { throw ProbeError.invalidState }
        switch result {
        case "received" where stored.state != .received && stored.state != .delivered,
             "delivered" where stored.state != .delivered:
            result = "receipt-not-persisted"
            code = 2
        case "prepared", "received", "delivered": break
        default: code = 2
        }
        let output: [String: Any] = ["id": stored.id, "product": "saytile", "result": result,
                                    "attempts": stored.attempts, "localState": stored.state.rawValue, "offline": offline,
                                    "payloadSHA256": SHA256.hash(data: stored.bytes).map { String(format: "%02x", $0) }.joined()]
        let json = try JSONSerialization.data(withJSONObject: output, options: [.sortedKeys])
        try await store.markClean()
        print(String(decoding: json, as: UTF8.self))
        return code
    }
}
