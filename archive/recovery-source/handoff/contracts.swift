// Always-On Voice — interface draft, NOT a compiled or implemented application.
// This file has NOT been compiled against a macOS SDK. It defines ownership,
// persistence and integration boundaries; method names below are app contracts,
// not claims that Apple/WhisperKit expose identically named APIs.
// Target: macOS 26+, Apple Silicon, Swift 6. No microphone or AX side effects here.

import Foundation

typealias ContentGeneration = Int64
typealias FrameIndex = Int64

struct SamplePosition: Sendable, Equatable {
    let epochID: UUID
    let frame: FrameIndex
}

// Half-open [start, end), measured in the original capture epoch's sample clock.
// Resampling adapters maintain an explicit mapping back to this clock.
struct AudioRange: Sendable, Equatable {
    let epochID: UUID
    let start: FrameIndex
    let end: FrameIndex
}

struct ArchiveFormat: Sendable {
    let sampleRateHz: Int
    // Archive is mono signed 16-bit little-endian PCM. Actual input may be
    // Float32/multichannel; downmix/quantize outside the realtime callback.
    let channels: Int = 1
    let bytesPerSample: Int = 2
}

struct CaptureEpoch: Sendable {
    let id: UUID
    let deviceUID: String
    let startedAt: Date
    let archiveFormat: ArchiveFormat
    let generation: ContentGeneration
}

enum CaptureStopReason: Sendable {
    case userPause, lockScreen, sleep, excludedApplication
    case permissionLost, deviceLost, writeUnavailable
}

enum CaptureEvent: Sendable {
    case epochStarted(CaptureEpoch)
    case gap(AudioRange?, reasonCode: String)
    case stopped(CaptureStopReason)
}

protocol CaptureController: Actor {
    // AVAudioEngine owns the sole microphone tap. The realtime tap ONLY copies
    // into a preallocated SPSC buffer and updates atomic counters. It never
    // calls these actor methods, allocates Data, yields AsyncStream, or writes DB.
    func start(deviceUID: String, generation: ContentGeneration) async throws -> CaptureEpoch
    func stop(reason: CaptureStopReason) async
    func events() -> AsyncStream<CaptureEvent>
}

struct RetainedPCM: Sendable {
    let range: AudioRange
    let format: ArchiveFormat
    let bytes: Data // Owned by the non-realtime consumer; bounded batch only.
}

struct DurableAudioSpan: Sendable {
    let chunkID: UUID
    let range: AudioRange
    let generation: ContentGeneration
}

struct RecoverySummary: Sendable {
    let recoveredChunks: Int
    let discardedTombstonedChunks: Int
    let gaps: [AudioRange]
    let pendingCleanupCount: Int
}

protocol AudioJournal: Actor {
    // A new file at 15 seconds MAX, or earlier when continuity/format changes.
    // No concatenation across dropped silence into one supposedly contiguous file.
    func append(_ pcm: RetainedPCM) async throws
    // File data + relevant sidecar/directory synchronization precedes SQLite
    // registration. Returns exact spans, not a max cursor that hides skipped gaps.
    func checkpoint() async throws -> [DurableAudioSpan]
    func seal(epochID: UUID) async throws
    // Load deletion tombstones and generation BEFORE scanning .part/orphan files.
    // Trim incomplete frames; distinguish known durable coverage from recovered tail.
    func recover() async throws -> RecoverySummary
}

enum SegmentEvent: Sendable {
    case speechBegan(utteranceID: UUID, coreStart: SamplePosition, preRoll: AudioRange)
    case softCheckpoint(utteranceID: UUID, through: SamplePosition)
    case speechEnded(utteranceID: UUID, through: SamplePosition)
    case rotateLongSession(utteranceID: UUID, through: SamplePosition, context: AudioRange)
}

protocol Segmenter: Actor {
    // Independent 16 kHz VAD sidechain; current FluidAudio window is 4096 frames.
    // 1 s pre-roll, ~800 ms end silence, ~30 s soft checkpoint, ~5 min rotation
    // are INITIAL DESIGN PARAMETERS, not measured quality/latency guarantees.
    func acceptVAD(probability: Float, inputRange: AudioRange) -> [SegmentEvent]
    func reset(for epoch: CaptureEpoch)
}

struct RecognitionToken: Sendable, Equatable {
    let jobID: UUID
    let utteranceID: UUID
    let attemptID: UUID
    let generation: ContentGeneration
}

enum RecognitionLane: Sendable { case live, manual, recovery }
enum SpeechEngineKind: Sendable { case appleSpeechTranscriber, whisperKitTurbo }

enum RecognitionSource: Sendable {
    // A live job exists at speech onset, before its final end frame is known.
    case live(epochID: UUID, coreStart: FrameIndex, contextStart: FrameIndex)
    case sealed(core: AudioRange, context: AudioRange?)
}

struct RecognitionRequest: Sendable {
    let token: RecognitionToken
    let engine: SpeechEngineKind
    let modelRevision: String
    let requestRevision: Int
    let lane: RecognitionLane
    let source: RecognitionSource
    let localeIdentifier: String
}

struct SpeechCapabilities: Sendable {
    let isAvailable: Bool
    let supportedLocales: [String]
    let installedLocales: [String]
    let supportsVolatileResults: Bool
}

enum SpeechEvent: Sendable {
    // Replace the corresponding volatile range, never blindly append strings.
    case hypothesis(token: RecognitionToken, range: AudioRange, text: String, isFinal: Bool)
    // Advancing this watermark can stabilize an earlier isFinal=false hypothesis
    // even if no identical final result is emitted again.
    case finalizationProgress(token: RecognitionToken, through: SamplePosition)
    case finished(RecognitionToken)
    case failed(RecognitionToken, code: String)
}

protocol SpeechSession: Actor {
    func results() -> AsyncThrowingStream<SpeechEvent, Error>
    func append(_ pcm: RetainedPCM) async throws
    // Adapter ends its input, finalizes, and drains its result consumer before
    // reporting completion. No clearing the tail when finalize merely returns.
    func finishAndDrain() async throws
    func cancel() async
}

protocol SpeechEngine: Actor {
    func capabilities(localeIdentifier: String) async throws -> SpeechCapabilities
    func prepare(localeIdentifier: String) async throws
    func start(_ request: RecognitionRequest) async throws -> any SpeechSession
    func releaseIdleResources() async
    // Apple adapter: supported/installed locale + AssetInventory checks;
    // AVAudioConverter -> bestAvailableAudioFormat -> AnalyzerInput.
    // WhisperKit adapter: pinned multilingual turbo model; no automatic upload.
}

protocol RecognitionCoordinator: Actor {
    // Persist source references and create a job at speech start. Capture/storage
    // never waits for an ASR slot. One active worker; live work outranks old retry.
    func enqueue(_ request: RecognitionRequest) async throws
    func acceptDurableCoverage(_ spans: [DurableAudioSpan]) async
    func resumeAfterCrash() async throws
    func cancel(utteranceID: UUID) async
    // Queues contain IDs/ranges, not unlimited waveform buffers. Paused history
    // jobs resume from disk; repeated failure has finite backoff and yields to live.
}

enum TranscriptOrigin: Sendable { case asrPartial, asrFinal, userEdit, aiVariant }

struct TranscriptSnapshot: Sendable {
    let id: UUID
    let utteranceID: UUID
    let origin: TranscriptOrigin
    let text: String
    let stableThrough: SamplePosition?
}

protocol TranscriptStore: Actor {
    // One transaction verifies generation + active attempt + nondeleted source
    // and writes the result. Checking before an unrelated later write is a race.
    func apply(_ event: SpeechEvent) async throws
    // Freeze the visible version when editing or creating an insertion operation.
    // Only bounded draft checkpoints mutate; referenced/final versions are immutable.
    func beginEdit(snapshotID: UUID) async throws -> TranscriptSnapshot
    func saveEdit(baseID: UUID, text: String) async throws -> TranscriptSnapshot
    func search(_ query: String, limit: Int, offset: Int) async throws -> [TranscriptSnapshot]
}

struct InputTargetToken: Sendable, Equatable {
    // Opaque IN-MEMORY binding to one current process/window/editable target and
    // direct-input session. A persisted application label cannot reconstruct it.
    let id: UUID
    let bindingGeneration: UInt64
}

enum TargetValidation: Sendable {
    case editableCaret
    case selectedTextRequiresExplicitChoice
    case changed, unsupported, sensitiveOrTerminal
}

struct InsertionRequest: Sendable {
    let id: UUID
    let snapshot: TranscriptSnapshot
    // Half-open UTF-16 offsets, validated at text boundaries before AX bridging.
    let utf16Start: Int
    let utf16End: Int
    let target: InputTargetToken
}

enum InsertionResult: Sendable {
    case confirmed, unverified, failed(code: String), cancelledBeforeDispatch
}

@MainActor
protocol InsertionCoordinator: AnyObject {
    func bindCurrentEditableTarget() throws -> InputTargetToken
    func validate(_ token: InputTargetToken) -> TargetValidation
    func insert(_ request: InsertionRequest) async -> InsertionResult
    func copy(_ snapshot: TranscriptSnapshot) throws
    func cancelPrepared(operationID: UUID)
    func invalidateBinding()
    // Persist dispatching BEFORE one AX-local insertion or Cmd+V. Never Return,
    // send, whole-field AXValue rewrite, automatic uncertain retry, or terminal paste.
    // Preserve nonempty selection by explicit append-after/replace choice; copy
    // fallback when selection semantics are unavailable. No ASR-induced activation.
    // Restore clipboard only after observed consumption and unchanged changeCount.
    // Shutdown/rebind/mode exit expires all prepared automatic operations.
}

struct DeletionRequest: Sendable {
    let id: UUID
    let generation: ContentGeneration
    let utteranceID: UUID?
    let range: AudioRange? // nil only for deleting the entire generation.
}

struct DeletionProgress: Sendable {
    let tombstoneCommitted: Bool
    let physicalCleanupComplete: Bool
}

protocol HistoryMaintenance: Actor {
    // Commit tombstone + cancel jobs first. Generation-wide delete also advances
    // global generation. Tombstones survive object row removal and orphan recovery.
    func delete(_ request: DeletionRequest) async throws -> DeletionProgress
    func resumePendingDeletions() async throws
    func enforceRetention(maxDays: Int, maxAudioBytes: Int64) async throws
    // User deletion is distinct from automatic retention: shared PCM blocks may
    // need byte-preserving copies of surviving ranges, reference replacement, then
    // unlinking old blocks. Incomplete cleanup is not reported as completed erasure.
    // Normal GC protects unrecognized/failed/pinned audio and all active leases.
}

// First implementation should satisfy these contracts in one app process with
// isolated queues/actors. Add XPC only if measured fallback-engine failures justify
// isolating inference; do not introduce an always-recording daemon or cloud account.
