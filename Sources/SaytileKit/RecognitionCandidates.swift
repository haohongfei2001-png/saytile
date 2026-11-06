import Foundation

/// A provider attempt is subordinate to a logical recognition generation. It cannot publish text.
public struct ModelRunTicket: Codable, Sendable, Equatable, Identifiable {
    public let id: UUID
    public let recognitionID: UUID
    public let recordingID: UUID
    public let audioEpoch: Int64
    public let configurationID: UUID
    public let provider: String
    public let model: String
    public let purpose: RecognitionPurpose
    public init(id: UUID = UUID(), recognitionID: UUID, recordingID: UUID, audioEpoch: Int64,
                configurationID: UUID, provider: String, model: String, purpose: RecognitionPurpose) {
        self.id = id; self.recognitionID = recognitionID; self.recordingID = recordingID
        self.audioEpoch = audioEpoch; self.configurationID = configurationID
        self.provider = provider; self.model = model; self.purpose = purpose
    }
}

/// Timing is provider evidence, not a duration inferred from character count.
public struct RecognitionToken: Codable, Sendable, Equatable {
    public let text: String
    public let startSeconds: Double
    public let endSeconds: Double
    public let isFinal: Bool
    public let language: String?
    /// Raw, provider-specific evidence. Never compare this as a calibrated cross-provider probability.
    public let rawConfidence: Double?
    public init(text: String, startSeconds: Double, endSeconds: Double, isFinal: Bool,
                language: String? = nil, rawConfidence: Double? = nil) {
        self.text = text; self.startSeconds = startSeconds; self.endSeconds = endSeconds
        self.isFinal = isFinal; self.language = language; self.rawConfidence = rawConfidence
    }
}

public struct RecognitionCandidate: Codable, Sendable, Equatable, Identifiable {
    public let id: UUID
    public let run: ModelRunTicket
    public let sequence: Int64
    public let text: String
    public let stableUTF16Length: Int
    public let audioStartSeconds: Double
    public let audioEndSeconds: Double
    public let timingGranularity: String
    public let language: String?
    public let isComplete: Bool
    public let tokens: [RecognitionToken]
    public let createdAt: Date
    public init(id: UUID = UUID(), run: ModelRunTicket, sequence: Int64, text: String,
                stableUTF16Length: Int = 0, audioStartSeconds: Double = 0,
                audioEndSeconds: Double, timingGranularity: String = "utterance",
                language: String? = nil, isComplete: Bool = false,
                tokens: [RecognitionToken] = [], createdAt: Date = Date()) {
        self.id = id; self.run = run; self.sequence = sequence; self.text = text
        self.stableUTF16Length = stableUTF16Length; self.audioStartSeconds = audioStartSeconds
        self.audioEndSeconds = audioEndSeconds; self.timingGranularity = timingGranularity
        self.language = language; self.isComplete = isComplete; self.tokens = tokens; self.createdAt = createdAt
    }
    public init(id: UUID = UUID(), run: ModelRunTicket, sequence: Int64, event: ProviderTranscriptEvent,
                createdAt: Date = Date()) {
        self.init(id: id, run: run, sequence: sequence, text: event.text,
                  stableUTF16Length: event.stableUTF16Length, audioStartSeconds: event.audioStartSeconds,
                  audioEndSeconds: event.audioEndSeconds, timingGranularity: event.timingGranularity,
                  language: event.language, isComplete: event.isComplete,
                  tokens: event.tokens.map { RecognitionToken(text: $0.text, startSeconds: $0.startSeconds,
                      endSeconds: $0.endSeconds, isFinal: $0.isFinal, language: $0.language, rawConfidence: $0.rawConfidence) },
                  createdAt: createdAt)
    }
    public var stableText: String { RecognitionUTF16.slice(text, start: 0, end: stableUTF16Length) ?? "" }
}

public enum ModelRunState: String, Codable, Sendable { case running, completed, failed, cancelled, interrupted }
public struct ModelRunRecord: Codable, Sendable, Equatable, Identifiable {
    public var id: UUID { ticket.id }
    public let ticket: ModelRunTicket
    public let state: ModelRunState
    public let lastSequence: Int64
    public let error: String?
    public let retryable: Bool
}

/// Values may be unknown; zero is not substituted for unreported billing data.
public struct ModelUsageRecord: Codable, Sendable, Equatable, Identifiable {
    public let id: UUID
    public let runID: UUID
    public let requestID: String?
    public let audioSeconds: Double?
    public let inputTokens: Int?
    public let outputTokens: Int?
    public let estimatedCost: Double?
    public let currency: String
    public let status: String
    public let elapsedSeconds: Double?
    public let createdAt: Date
    public init(id: UUID = UUID(), runID: UUID, requestID: String? = nil, audioSeconds: Double? = nil,
                inputTokens: Int? = nil, outputTokens: Int? = nil, estimatedCost: Double? = nil,
                currency: String = "USD", status: String = "completed", elapsedSeconds: Double? = nil, createdAt: Date = Date()) {
        self.id = id; self.runID = runID; self.requestID = requestID; self.audioSeconds = audioSeconds
        self.inputTokens = inputTokens; self.outputTokens = outputTokens; self.estimatedCost = estimatedCost
        self.currency = currency; self.status = status; self.elapsedSeconds = elapsedSeconds; self.createdAt = createdAt
    }
}

public enum FusionError: Error, LocalizedError, Sendable {
    case invalidCandidate, invalidSelection, insufficientAlignment, protectedContentDisagreement, staleGeneration
    public var errorDescription: String? {
        switch self {
        case .invalidCandidate: "识别候选的时间、文本边界或运行身份无效。"
        case .invalidSelection: "AI 选择不属于已保存的语音证据，已保留原候选。"
        case .insufficientAlignment: "没有足够的真实时间对齐证据，暂不拼接候选。"
        case .protectedContentDisagreement: "数字、单位或否定存在未解决分歧，需要复听。"
        case .staleGeneration: "该识别代次已失效。"
        }
    }
}

public enum RecognitionUTF16 {
    /// Both ends must be complete extended grapheme boundaries, including emoji/combining marks.
    public static func slice(_ text: String, start: Int, end: Int) -> String? {
        guard start >= 0, end >= start, end <= text.utf16.count else { return nil }
        let units = text.utf16
        let lower = units.index(units.startIndex, offsetBy: start)
        let upper = units.index(units.startIndex, offsetBy: end)
        guard let lo = String.Index(lower, within: text), let hi = String.Index(upper, within: text),
              (lo == text.endIndex || text.indices.contains(lo)),
              (hi == text.endIndex || text.indices.contains(hi)) else { return nil }
        return String(text[lo..<hi])
    }
    public static func commonPrefix(_ texts: [String]) -> String {
        guard var prefix = texts.first else { return "" }
        for text in texts.dropFirst() {
            var match = ""
            for (a, b) in zip(prefix, text) { guard a == b else { break }; match.append(a) }
            prefix = match
        }
        return prefix
    }
}
