import Foundation

/// Stable server discriminator. Omitted on legacy Riftlet envelopes to preserve their bytes.
public enum FeedbackProduct: String, Codable, CaseIterable, Sendable { case riftlet, saytile, nearpane }

public enum FeedbackKind: String, Codable, CaseIterable, Sendable { case problem, suggestion }
public enum FeedbackFailure: Error, Equatable, Sendable {
    case invalidText, invalidDiagnostic, storageUnavailable, capacity, secretUnavailable
    case endpointUnavailable, invalidResponse, transport, conflict, rejected, rateLimited(Int)
}

/// Closed vocabulary only. No arbitrary errors, screenshot IDs/hashes, paths,
/// clipboard contents, acceptance traces or browser state can be recorded here.
public enum FeedbackFact: String, Codable, CaseIterable, Sendable {
    case sessionStarted, previousSessionUnclean, initializationIssue, captureSourceUnavailable
    case captureImportIssue, captureUnsupported, privateStorageIssue, queueReadIssue
    case selectionAccepted, selectionRejected, permissionUnavailable
    case visibilityVisible, visibilitySwallowed, visibilityArchived, visibilityRemoved
    case queuePending, queueTransferring, queueUnknown, queueFailed, queueUsed, queueMissing
    case phasePrepared, phaseDispatchIntent, phaseInputTriggered, phaseAttachmentPresent
    case phaseUnknown, phaseCompensated, phaseFailed, phaseSucceeded
    case reasonCapture, reasonUploadStarted, reasonLegacyCompletion, reasonAutomaticArchive
    case reasonUserRemoved, reasonUserRestored, reasonSafeFailure
    case uiProjectionDeferred, uiProjectionMismatchCandidate
}
public struct FeedbackEvent: Codable, Equatable, Sendable {
    public let fact: FeedbackFact
    public let count: Int
    public init(_ fact: FeedbackFact, count: Int = 1) { self.fact = fact; self.count = max(0, min(9999, count)) }
}
public struct FeedbackDiagnostic: Codable, Equatable, Sendable {
    public let schema: Int
    public let coverage: String
    public let events: [FeedbackEvent]
    public let dropped: Int
    public init(events: [FeedbackEvent], dropped: Int = 0) {
        schema = 1; coverage = "session-sampled-v1"; self.events = Array(events.suffix(64))
        self.dropped = max(0, min(9999, dropped))
    }
    public func validate() throws {
        guard schema == 1, coverage == "session-sampled-v1", events.count <= 64,
              (0...9999).contains(dropped), events.allSatisfy({ (0...9999).contains($0.count) }) else {
            throw FeedbackFailure.invalidDiagnostic
        }
    }
    public func preview() throws -> String {
        try validate()
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return String(decoding: try encoder.encode(self), as: UTF8.self)
    }
}
public struct FeedbackDraft: Codable, Equatable, Sendable {
    public var kind: FeedbackKind
    public var text: String
    public var diagnostic: FeedbackDiagnostic?
    public var revision: Int64
    public init(kind: FeedbackKind = .problem, text: String = "", diagnostic: FeedbackDiagnostic? = nil, revision: Int64 = 0) {
        self.kind = kind; self.text = text; self.diagnostic = diagnostic; self.revision = revision
    }
}
public struct FeedbackEnvelope: Codable, Equatable, Sendable {
    public let schema: Int
    public let id: String
    public let kind: FeedbackKind
    public let text: String
    public let appVersion: String
    public let product: FeedbackProduct?
    public let createdAt: Int64
    public let diagnostic: FeedbackDiagnostic?
    public init(draft: FeedbackDraft, id: UUID = UUID(), appVersion: String, now: Date = Date(), product: FeedbackProduct? = nil) throws {
        guard !draft.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              draft.text.unicodeScalars.count <= 4000, draft.text.utf8.count <= 16384 else { throw FeedbackFailure.invalidText }
        try draft.diagnostic?.validate()
        schema = 1; self.id = id.uuidString.lowercased(); kind = draft.kind; text = draft.text
        self.appVersion = appVersion.range(of: #"^[0-9]{1,4}(\.[0-9]{1,4}){0,3}$"#, options: .regularExpression) != nil ? appVersion : "0"
        self.product = product
        createdAt = Int64(now.timeIntervalSince1970); diagnostic = draft.diagnostic
    }
    public func encoded() throws -> Data {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let bytes = try encoder.encode(self)
        guard bytes.count <= 32768 else { throw FeedbackFailure.invalidText }
        return bytes
    }
}
public enum FeedbackLocalState: String, Codable, Sendable {
    case queued, received, delivered, blocked, deletionQueued, deletionBlocked, deletionPending, deleted, cancelled, expired
}
public struct FeedbackRecord: Sendable {
    public let id: String
    public let envelope: FeedbackEnvelope
    public let bytes: Data
    public let state: FeedbackLocalState
    public let attempts: Int
    public let nextAttempt: Date
    public let created: Date
    public var label: String {
        switch state {
        case .queued: return "已保存在本机，等待服务接收"
        case .received: return "云端已持久接收"
        case .delivered: return "已进入私有反馈中心"
        case .cancelled: return "已取消本机投递（未发送）"
        case .blocked: return "需处理；文字仍保存在本机"
        case .deletionQueued: return "删除申请待发送；不会再提交反馈正文"
        case .deletionBlocked: return "删除申请受阻；请检查访问凭证后重新申请，不会重发正文"
        case .deletionPending: return "删除处理中（包括私有维护副本）"
        case .deleted: return "服务已确认删除"
        case .expired: return "投递已过期；本机文字保留"
        }
    }
}
public struct FeedbackReceipt: Codable, Equatable, Sendable {
    public let id: String
    public let state: String
    public let durable: Bool
    public init(id: String, state: String = "received", durable: Bool = true) { self.id = id; self.state = state; self.durable = durable }
    public func validate(for id: String) throws {
        guard self.id == id, durable, ["received", "delivered", "delivery_uncertain", "deletion_pending", "deleted", "delivery_expired"].contains(state) else {
            throw FeedbackFailure.invalidResponse
        }
    }
}
