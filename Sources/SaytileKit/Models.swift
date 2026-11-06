import Foundation

public enum RecordingFilter: Sendable { case all, pinned, needsRecovery }
public enum AudioState: String, Codable, Sendable { case available, deletePending, deleted, missing }
public enum RecognitionState: String, Codable, Sendable { case queued, running, completed, failed, cancelled }
public enum RevisionOrigin: String, Codable, Sendable { case partial, final, userEdit }
public enum DispatchState: String, Codable, Sendable { case dispatching, confirmed, unverified, failed, cancelled }

public struct Recording: Identifiable, Sendable, Equatable {
    public let id: UUID
    public let createdAt: Date
    public let text: String
    public let preferredRevisionID: UUID?
    public let duration: Double
    public let isPinned: Bool
    public let audioState: AudioState
    public let recognitionState: RecognitionState
    public let isRecording: Bool
    public let lastError: String?
    public let sampleRate: Double
}
public struct TranscriptRevision: Identifiable, Sendable, Equatable {
    public let id: UUID
    public let recordingID: UUID
    public let text: String
    public let origin: RevisionOrigin
    public let createdAt: Date
}
public struct AudioChunk: Identifiable, Sendable, Equatable {
    public let id: UUID
    public let recordingID: UUID
    public let relativePath: String
    public let frames: Int64
    public let ordinal: Int
}
public struct RecognitionTicket: Sendable, Equatable {
    public let id: UUID
    public let recordingID: UUID
    public let audioEpoch: Int64
}
public struct DispatchReservation: Identifiable, Sendable, Equatable {
    public let id: UUID
    public let recordingID: UUID
    public let revisionID: UUID
    public let text: String
    public let utf16Start: Int
    public let utf16End: Int
}
public struct StorageSummary: Sendable {
    public let audioBytes: Int64
    public let recordingCount: Int
    public let pendingRecognitionCount: Int
    public let pendingDeletionCount: Int
    public let availableDiskBytes: Int64
    public var shouldWarn: Bool { audioBytes >= 10 * 1024 * 1024 * 1024 || availableDiskBytes < 1024 * 1024 * 1024 }
}
public struct StoreRecovery: Sendable {
    public let interruptedRecordings: Int
    public let interruptedRecognitions: Int
    public let unverifiedDispatches: Int
}
public enum StoreError: LocalizedError, Sendable {
    case database(String), missingRecording, missingRevision, audioUnavailable, recordingActive, audioInUse
    case invalidPath, invalidFrames, invalidBoundary, bindingInvalid, prefixChanged, lateRecognitionDeferred
    public var errorDescription: String? {
        switch self {
        case .database(let message): return "资料库暂时不可用：\(message)"
        case .missingRecording: return "记录不存在。"
        case .missingRevision: return "文字版本不存在。"
        case .audioUnavailable: return "原音不可用。"
        case .recordingActive: return "请先结束当前语音，再删除原音。"
        case .audioInUse: return "原音正在回放或识别，清理将在使用结束后继续。"
        case .invalidPath: return "音频路径无效。"
        case .invalidFrames: return "音频长度无效。"
        case .invalidBoundary: return "文字边界无效。"
        case .bindingInvalid: return "输入目标已改变，请重新选择目标。"
        case .lateRecognitionDeferred: return "较早讲话的识别结果已保留在 Saytile，请手动取用以保持草稿顺序。"
        case .prefixChanged: return "已输入的文字发生修订，后续文字保留在输入板。"
        }
    }
}
