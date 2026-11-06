// Research handoff only. No production target imports this file.
import Foundation

public struct ASRAudioFormat: Sendable, Codable, Equatable {
    public let sampleRate: Int
    public let channels: Int
    public let encoding: String // pcm_s16le; compressed transport is an adapter concern.
}

public struct ASRAudioFrame: Sendable {
    public let data: Data
    public let sourceStartFrame: Int64 // canonical saved-audio clock, never wall time
    public let sourceFrameCount: Int
    public let sourceFormat: ASRAudioFormat
}

public struct ASRRunIdentity: Sendable, Codable, Hashable {
    public let recordingID: UUID
    public let generationID: UUID // one coordinator-owned RecognitionTicket
    public let engineRunID: UUID // child engine, does not replace active_attempt
    public let audioEpoch: Int64
    public let engine: String
    public let model: String
}

public enum ASRRevisionRole: String, Sendable, Codable {
    case preview
    case authoritative
    case alternate // preserved, never automatically inserted into another app
}

public struct ASRTextSnapshot: Sendable {
    public let run: ASRRunIdentity
    public let sequence: Int64
    public let text: String
    public let engineStableUTF16End: Int
    public let finalThroughSourceFrame: Int64?
    public let isUtteranceFinal: Bool
    // A provider's `final` flag is not authority to rewrite previously dispatched text.
}

public enum ASREvent: Sendable {
    case ready(ASRRunIdentity)
    case snapshot(ASRTextSnapshot)
    case completed(ASRRunIdentity)
    case recoverableFailure(ASRRunIdentity, code: String)
}

public struct ASRRequest: Sendable {
    public let run: ASRRunIdentity
    public let sourceFormat: ASRAudioFormat
    public let languageHints: [String] // hints only; never gold-reference language oracle
    public let endpointPolicy: String
}

public protocol StreamingASRSession: Sendable {
    var events: AsyncThrowingStream<ASREvent, Error> { get }
    func append(_ frame: ASRAudioFrame) async throws
    func endAudio(finalSourceFrame: Int64) async throws
    func cancel() async
}

public protocol StreamingASREngine: Sendable {
    func start(_ request: ASRRequest) async throws -> any StreamingASRSession
}

public protocol FinalizingASREngine: Sendable {
    // Audio lease and deletion epoch are checked by the coordinator before/after this call.
    func transcribe(savedAudio: URL, request: ASRRequest) async throws -> ASRTextSnapshot
}

public protocol ASRCredentialProvider: Sendable {
    // Keychain or a narrowly scoped short-lived server token. Never UserDefaults/source/logs.
    func credential(for provider: String) async throws -> String
}
