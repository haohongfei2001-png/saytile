import Foundation
import CryptoKit
@preconcurrency import AVFoundation

/// Explicit, local-fixture quality probes. No microphone, target binding, dispatch or
/// environment-variable credentials are used. Calling this with consent may incur BYOK charges.
public enum MultiRecognitionDiagnostics {
    @discardableResult
    public static func transcribeFixture(url: URL, store: SaytileStore,
                                         configuration: RecognitionConfiguration) async throws -> UUID {
        // Reject before reading a fixture, creating a record, looking up credentials,
        // or constructing any live provider. validateForCloud alone permits disabled cloud.
        guard configuration.cloudEnabled else {
            throw ProviderFailure.configuration("多模型回放需要显式启用云端识别，并授权每个启用模型。")
        }
        try configuration.validateForCloud()
        let file = try validatedFixture(url)
        let source = try fixtureIdentity(url: url, frameCount: file.length)
        let configurationIdentity = try identity(configuration: configuration)
        var credentials: [UUID: String] = [:]
        for model in configuration.activeModels {
            guard let key = try CloudCredentialStore.read(configurationID: model.id, provider: model.provider), !key.isEmpty else {
                throw ProviderFailure.configuration("\(model.purpose.label)缺少此配置的 Keychain API Key，尚未启动任何模型。")
            }
            credentials[model.id] = key
        }
        // Persist the entire source before any provider connection. A model, network or
        // replay failure cannot prevent this original from being retained for recovery.
        let recordingID = try await importOriginal(file: file, store: store)
        let metadataURL = try replayMetadataURL(store: store, recordingID: recordingID)
        let ticket = try await store.beginFusionRecognition(recordingID: recordingID, mode: configuration.inputMode)
        var replay = ReplayMetadata(recordingID: recordingID, recognitionID: ticket.id,
                                    mode: configuration.inputMode, frameCount: file.length,
                                    replayStartedAt: Date(), firstAudioSubmittedAt: nil,
                                    lastAudioSubmittedAt: nil, sessionEndedAt: nil,
                                    source: source, configuration: configuration,
                                    configurationIdentity: configurationIdentity,
                                    sourceRevision: Bundle.main.object(forInfoDictionaryKey: "SaytileSourceRevision") as? String)
        do { try encode(replay).write(to: metadataURL, options: .atomic) }
        catch {
            try? await store.failRecognition(ticket: ticket, message: "无法保存回放时间记录，原音已保存；尚未启动模型。")
            throw error
        }
        let approvedCredentials = credentials
        var dependencies = RecognitionPipelineDependencies.live
        dependencies.observeLanguage = { _ in } // Synthetic checks must not train the usage profile.
        dependencies.credential = { approvedCredentials[$0.id] }
        let session = MultiRecognitionSession(store: store, ticket: ticket, configuration: configuration,
                                               dependencies: dependencies)
        do {
            try await withTaskCancellationHandler {
                let clock = ContinuousClock(), origin = clock.now
                var framesSubmitted: Int64 = 0
                for chunk in try await store.audioChunks(recordingID: recordingID) {
                    let source = try await store.audioURL(for: chunk)
                    let handle = try FileHandle(forReadingFrom: source)
                    defer { try? handle.close() }
                    try handle.seek(toOffset: 44) // Our own PCMJournal's canonical header.
                    var remaining = chunk.frames * 2
                    while remaining > 0 {
                        try Task.checkCancellation()
                        let wanted = Int(min(640, remaining)) // 20 ms, 16 kHz, mono PCM16.
                        guard let frame = try handle.read(upToCount: wanted), frame.count == wanted else {
                            throw AudioFailure.message("已保存的回放音频不完整；停止发送，保留现有证据。")
                        }
                        framesSubmitted += Int64(frame.count / 2)
                        // Absolute monotonic deadlines avoid accumulated per-packet sleep drift.
                        try await clock.sleep(until: origin.advanced(by: .seconds(Double(framesSubmitted) / 16_000)))
                        session.append(frame)
                        let now = Date()
                        if replay.firstAudioSubmittedAt == nil { replay.firstAudioSubmittedAt = now }
                        replay.lastAudioSubmittedAt = now
                        remaining -= Int64(frame.count)
                    }
                }
                replay.framesSubmitted = framesSubmitted
                replay.inputEOF = framesSubmitted == file.length
                replay.inputEOFAt = Date()
                try encode(replay).write(to: metadataURL, options: .atomic)
                session.finish()
                await session.wait()
                try Task.checkCancellation()
            } onCancel: { session.cancel() }
            replay.sessionEndedAt = Date()
            try encode(replay).write(to: metadataURL, options: .atomic)
            // A failed/uncertain recognition still returns its durable record for inspection.
            return recordingID
        } catch {
            session.cancel()
            await session.wait()
            replay.sessionEndedAt = Date()
            try? encode(replay).write(to: metadataURL, options: .atomic)
            throw error
        }
    }

    /// JSON contains evidence and timing, never PCM, keys or a fabricated accuracy score.
    /// Dates use Unix epoch milliseconds so sub-second distinctions remain inspectable.
    @discardableResult
    public static func exportTrace(store: SaytileStore, recordingID: UUID, to url: URL) async throws -> URL {
        guard url.isFileURL else { throw AudioFailure.message("诊断报告必须写入指定的本地文件。") }
        guard let record = try await store.recording(id: recordingID) else { throw StoreError.missingRecording }
        let candidates = try await store.recognitionCandidates(recordingID: recordingID)
        let decisions = try await store.fusionDecisions(recordingID: recordingID)
        let runs = try await store.modelRuns(recordingID: recordingID)
        let usage = try await store.modelUsage(recordingID: recordingID)
        let revisions = try await store.revisions(recordingID: recordingID)
        let dispatchable = try await store.latestDispatchableRevision(recordingID: recordingID)
        let currentURL = try replayMetadataURL(store: store, recordingID: recordingID)
        let metadataURL = FileManager.default.fileExists(atPath: currentURL.path) ? currentURL :
            currentURL.deletingLastPathComponent().appendingPathComponent("multi-asr-replay.json")
        try StorePath.rejectSymbolicLink(metadataURL)
        let replay = try? decoder().decode(ReplayMetadata.self, from: Data(contentsOf: metadataURL))
        let selectedCandidates = candidates.filter { replay == nil || $0.run.recognitionID == replay?.recognitionID }
        let selectedDecisions = decisions.filter { replay == nil || $0.recognitionID == replay?.recognitionID }
        let terminal: (state: String, occurredAt: Date)?
        let logicalState: String?
        if let recognitionID = replay?.recognitionID {
            terminal = try await store.fusionTerminal(recognitionID: recognitionID)
            logicalState = try await store.fusionSessionState(recognitionID: recognitionID)
        } else { terminal = nil; logicalState = nil }
        // A complete provider candidate and a stopped replay do not prove a completed
        // logical recognition. Persisted terminal state supplies its own real clock.
        let completedAt = terminal?.state == "completed" ? terminal?.occurredAt : nil
        let selectedID = selectedDecisions.reversed().compactMap(\.revisionID).first
        let selectedRevision = revisions.first { $0.id == selectedID }
        let finalization = replay.map { metadata in
            TraceFinalization(recognitionID: metadata.recognitionID, state: logicalState,
                              completedAt: completedAt, selectedRevisionID: selectedRevision?.id,
                              selectedText: selectedRevision?.text,
                              dispatchEligible: selectedRevision != nil && selectedRevision?.id == dispatchable?.id,
                              dispatchableRevisionID: dispatchable?.id, dispatchableText: dispatchable?.text,
                              lastDecisionID: selectedDecisions.last?.id,
                              resolved: selectedDecisions.last.map { !$0.proposal.unresolved })
        }
        let firstCandidate = selectedCandidates.filter { !$0.text.isEmpty }.map(\.createdAt).min()
        let firstPreview = selectedDecisions.filter { !$0.proposal.previewText.isEmpty }.map(\.createdAt).min()
        let publications = selectedDecisions.filter { $0.outcome == "published" && !$0.proposal.stableText.isEmpty }
        let firstStable = publications.map(\.createdAt).min()
        let completeCandidates = selectedCandidates.filter(\.isComplete)
        let firstProviderFinal = completeCandidates.map(\.createdAt).min()
        let lastProviderFinal = completeCandidates.map(\.createdAt).max()
        let origin = replay?.replayStartedAt
        let timing = TraceTiming(
            origin: origin,
            firstCandidatePersistedAt: firstCandidate, firstPreviewPersistedAt: firstPreview,
            firstStablePublishedAt: firstStable, firstCompleteCandidateAt: firstProviderFinal,
            lastCompleteCandidateAt: lastProviderFinal, lastStablePublishedAt: publications.map(\.createdAt).max(),
            logicalSessionEndedAt: replay?.sessionEndedAt,
            logicalRecognitionCompletedAt: completedAt,
            firstCandidateSeconds: elapsed(firstCandidate, since: origin),
            firstPreviewSeconds: elapsed(firstPreview, since: origin),
            firstStableSeconds: elapsed(firstStable, since: origin),
            firstCompleteCandidateSeconds: elapsed(firstProviderFinal, since: origin),
            lastCompleteCandidateSeconds: elapsed(lastProviderFinal, since: origin),
            sessionElapsedSeconds: elapsed(replay?.sessionEndedAt, since: origin))
        let trace = Trace(schemaVersion: 2, exportedAt: Date(), timestampEncoding: "unix-epoch-milliseconds",
                          recording: TraceRecording(record), replay: replay, timing: timing,
                          source: replay?.source, configuration: replay?.configuration,
                          configurationIdentity: replay?.configurationIdentity, sourceRevision: replay?.sourceRevision,
                          finalization: finalization,
                          candidates: candidates, fusionDecisions: decisions, modelRuns: runs, modelUsage: usage,
                          revisions: revisions.map(TraceRevision.init), dispatchableRevision: dispatchable.map(TraceRevision.init),
                          accuracyMeasurement: "not-measured-no-reference-transcript",
                          notes: [
                            "All candidate/model generations are exported; replay timing selects the recorded logical recognition ID when available.",
                            "Preview times measure persisted fusion decisions, not UI rendering; stable publication is eligibility, not external insertion.",
                            "Source identity hashes the entire original WAV. Configuration identity hashes its encoded non-credential snapshot; single-expert baselines are explicitly labeled.",
                            "audioSubmittedSeconds is an input frontier, not a word's acoustic endpoint or a time-aligned reference annotation.",
                            "A provider's complete candidate is not the unified final result. Completion is reported separately from session termination.",
                            "No CER/WER/MER, reference alignment, quality improvement or microphone latency was measured.",
                            "Missing timestamps, token counts, actual charges or calibrated confidence remain unavailable; no zero is substituted.",
                            "The source PCM is retained separately in the owned recording audio directory and is not embedded in this JSON."
                          ])
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try encode(trace).write(to: url, options: .atomic)
        return url
    }

    /// Bounded streaming hash of an explicitly supplied fixture; never reads a
    /// microphone, user archive, credentials, or a path inferred from the machine.
    static func fixtureIdentity(url: URL, frameCount: Int64) throws -> TraceSource {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        while let data = try handle.read(upToCount: 64 * 1024), !data.isEmpty { hasher.update(data: data) }
        return TraceSource(fixtureID: url.deletingPathExtension().lastPathComponent,
                           audioSHA256: hasher.finalize().map { String(format: "%02x", $0) }.joined(),
                           sampleRate: 16_000, frameCount: frameCount)
    }
    static func identity(configuration: RecognitionConfiguration) throws -> TraceConfigurationIdentity {
        let data = try encode(configuration)
        return TraceConfigurationIdentity(sha256: SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined(),
                                          evaluationMode: "single-asr-plus-gpt6")
    }

    private static func validatedFixture(_ url: URL) throws -> AVAudioFile {
        guard url.isFileURL else { throw AudioFailure.message("只接受明确指定的本地 WAV 文件。") }
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        let header = try handle.read(upToCount: 12) ?? Data()
        guard header.count == 12, String(data: header.prefix(4), encoding: .ascii) == "RIFF",
              String(data: header.suffix(4), encoding: .ascii) == "WAVE" else {
            throw AudioFailure.message("质量回放只接受 RIFF/WAV 格式的 16 kHz 单声道 PCM16 原音。")
        }
        let file = try AVAudioFile(forReading: url, commonFormat: .pcmFormatInt16, interleaved: false)
        let format = file.fileFormat.streamDescription.pointee
        guard format.mFormatID == kAudioFormatLinearPCM, format.mSampleRate == 16_000,
              format.mChannelsPerFrame == 1, format.mBitsPerChannel == 16,
              format.mFormatFlags & kAudioFormatFlagIsSignedInteger != 0,
              format.mFormatFlags & (kAudioFormatFlagIsFloat | kAudioFormatFlagIsBigEndian) == 0,
              file.length > 0 else {
            throw AudioFailure.message("质量回放要求非空、16 kHz、单声道、有符号小端 PCM16 WAV；不会暗中转换输入格式。")
        }
        return file
    }

    private static func importOriginal(file: AVAudioFile, store: SaytileStore) async throws -> UUID {
        let record = try await store.createRecording()
        var journal: PCMJournal?
        do {
            let writer = try PCMJournal(directory: store.audioDirectory, recordingID: record.id)
            journal = writer
            try writer.openChunk()
            while file.framePosition < file.length {
                try Task.checkCancellation()
                guard let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: 16_000) else {
                    throw AudioFailure.message("无法分配回放音频缓冲区。")
                }
                try file.read(into: buffer)
                guard buffer.frameLength > 0, let samples = buffer.int16ChannelData?[0] else {
                    throw AudioFailure.message("无法读取完整 PCM16 回放音频。")
                }
                try writer.append(Data(bytes: samples, count: Int(buffer.frameLength) * 2))
                try writer.checkpoint()
                try await store.registerAudioChunk(recordingID: record.id, relativePath: writer.relativePath, frames: writer.durableFrames)
                if writer.needsRotation && file.framePosition < file.length {
                    try writer.closeChunk()
                    try writer.openChunk()
                }
            }
            try writer.closeChunk()
            try await store.registerAudioChunk(recordingID: record.id, relativePath: writer.relativePath, frames: writer.durableFrames)
            try await store.finishRecording(id: record.id)
            return record.id
        } catch {
            if let journal, journal.isOpen {
                try? journal.closeChunk()
                try? await store.registerAudioChunk(recordingID: record.id, relativePath: journal.relativePath, frames: journal.durableFrames)
            }
            try? await store.recordCaptureFailure(recordingID: record.id, message: "回放原音导入未完成，已持久化的音频片段保留。")
            throw error
        }
    }
    private static func replayMetadataURL(store: SaytileStore, recordingID: UUID) throws -> URL {
        let directory = store.audioDirectory.appendingPathComponent(recordingID.uuidString, isDirectory: true)
        try StorePath.rejectSymbolicLink(directory)
        let url = directory.appendingPathComponent("single-asr-replay.json")
        try StorePath.rejectSymbolicLink(url)
        return url
    }
    private static func encode<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .millisecondsSince1970
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(value)
    }
    private static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        return decoder
    }
    private static func elapsed(_ date: Date?, since origin: Date?) -> Double? {
        guard let date, let origin else { return nil }
        let value = date.timeIntervalSince(origin)
        return value.isFinite && value >= 0 ? value : nil
    }

    struct ReplayMetadata: Codable {
        var recordingID: UUID
        var recognitionID: UUID
        var mode: InputQualityMode
        var frameCount: Int64
        var replayStartedAt: Date
        var firstAudioSubmittedAt: Date?
        var lastAudioSubmittedAt: Date?
        var sessionEndedAt: Date?
        var framesSubmitted: Int64? = nil
        var inputEOF: Bool? = nil
        var inputEOFAt: Date? = nil
        var source: TraceSource? = nil
        var configuration: RecognitionConfiguration? = nil
        var configurationIdentity: TraceConfigurationIdentity? = nil
        var sourceRevision: String? = nil
    }
    struct TraceSource: Codable {
        var fixtureID: String
        var audioSHA256: String
        var sampleRate: Double
        var frameCount: Int64
    }
    struct TraceConfigurationIdentity: Codable {
        var sha256: String
        var evaluationMode: String
    }
    private struct TraceFinalization: Encodable {
        var recognitionID: UUID
        var state: String?
        var completedAt: Date?
        var selectedRevisionID: UUID?
        var selectedText: String?
        var dispatchEligible: Bool
        var dispatchableRevisionID: UUID?
        var dispatchableText: String?
        var lastDecisionID: UUID?
        var resolved: Bool?
    }
    private struct Trace: Encodable {
        var schemaVersion: Int
        var exportedAt: Date
        var timestampEncoding: String
        var recording: TraceRecording
        var replay: ReplayMetadata?
        var timing: TraceTiming
        var source: TraceSource?
        var configuration: RecognitionConfiguration?
        var configurationIdentity: TraceConfigurationIdentity?
        var sourceRevision: String?
        var finalization: TraceFinalization?
        var candidates: [RecognitionCandidate]
        var fusionDecisions: [FusionDecisionRecord]
        var modelRuns: [ModelRunRecord]
        var modelUsage: [ModelUsageRecord]
        var revisions: [TraceRevision]
        var dispatchableRevision: TraceRevision?
        var accuracyMeasurement: String
        var notes: [String]
    }
    private struct TraceRecording: Encodable {
        var id: UUID
        var createdAt: Date
        var text: String
        var preferredRevisionID: UUID?
        var duration: Double
        var audioState: AudioState
        var recognitionState: RecognitionState
        var isRecording: Bool
        var lastError: String?
        var sampleRate: Double
        init(_ record: Recording) {
            id = record.id; createdAt = record.createdAt; text = record.text; preferredRevisionID = record.preferredRevisionID
            duration = record.duration; audioState = record.audioState; recognitionState = record.recognitionState
            isRecording = record.isRecording; lastError = record.lastError; sampleRate = record.sampleRate
        }
    }
    private struct TraceRevision: Encodable {
        var id: UUID
        var text: String
        var origin: RevisionOrigin
        var createdAt: Date
        init(_ revision: TranscriptRevision) {
            id = revision.id; text = revision.text; origin = revision.origin; createdAt = revision.createdAt
        }
    }
    private struct TraceTiming: Encodable {
        var origin: Date?
        var firstCandidatePersistedAt: Date?
        var firstPreviewPersistedAt: Date?
        var firstStablePublishedAt: Date?
        var firstCompleteCandidateAt: Date?
        var lastCompleteCandidateAt: Date?
        var lastStablePublishedAt: Date?
        var logicalSessionEndedAt: Date?
        var logicalRecognitionCompletedAt: Date?
        var firstCandidateSeconds: Double?
        var firstPreviewSeconds: Double?
        var firstStableSeconds: Double?
        var firstCompleteCandidateSeconds: Double?
        var lastCompleteCandidateSeconds: Double?
        var sessionElapsedSeconds: Double?
    }
}
