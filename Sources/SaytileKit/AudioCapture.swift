import Foundation
import Combine
@preconcurrency import AVFoundation
import AppKit
import CoreAudio
import CAudio

public enum CaptureState: Equatable, Sendable {
    case paused, starting, listening, speaking, interrupted(String)
    public var isRunning: Bool { self == .listening || self == .speaking || self == .starting }
    public var label: String {
        switch self { case .paused: "已暂停"; case .starting: "正在准备"; case .listening: "正在待命"; case .speaking: "正在聆听"; case let .interrupted(reason): reason }
    }
}
public struct AudioInputDevice: Identifiable, Sendable {
    public let id: UInt32
    public let name: String
    public let uid: String
}

final class AudioRing: @unchecked Sendable {
    let pointer: OpaquePointer
    init(capacity: UInt32) throws { guard let p = st_ring_create(capacity) else { throw AudioFailure.message("无法分配收音缓冲") }; pointer = p }
    deinit { st_ring_destroy(pointer) }
}

actor CaptureWorker {
    let store: SaytileStore
    let ring: AudioRing
    let sampleRate: Double
    let recognitionEnabled: Bool
    let recognitionFactory: RecognitionSessionFactory
    let journalIO: PCMJournal.IO
    let update: @Sendable (Bool, Float) -> Void
    let failed: @MainActor @Sendable (String) -> Void
    var segmenter: VoiceSegmenter
    var journal: PCMJournal?
    var recordingID: UUID?
    var speech: (any RecognitionSession)?
    var retired: [any RecognitionSession] = []
    var converter: AVAudioConverter
    var sourceFormat: AVAudioFormat
    var targetFormat: AVAudioFormat
    var runTask: Task<Void, Never>?
    var stopping = false
    init(store: SaytileStore, ring: AudioRing, sampleRate: Double, recognitionEnabled: Bool = true, recognitionFactory: RecognitionSessionFactory = RecognitionSessionFactory(), journalIO: PCMJournal.IO = .live, update: @escaping @Sendable (Bool, Float) -> Void, failed: @escaping @MainActor @Sendable (String) -> Void) throws {
        self.store = store; self.ring = ring; self.sampleRate = sampleRate; self.recognitionEnabled = recognitionEnabled; self.update = update; self.failed = failed
        self.journalIO = journalIO
        self.recognitionFactory = recognitionFactory
        segmenter = try VoiceSegmenter(endSilenceFrames: recognitionFactory.usesCloud ? 100 : 40,
                                       maximumFrames: recognitionFactory.usesCloud ? 15_000 : 1_500)
        sourceFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: sampleRate, channels: 1, interleaved: false)!
        targetFormat = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: 16_000, channels: 1, interleaved: false)!
        guard let converter = AVAudioConverter(from: sourceFormat, to: targetFormat) else { throw AudioFailure.message("麦克风格式不受支持") }
        self.converter = converter
    }
    func start() { runTask = Task { await run() } }
    func stop() async {
        stopping = true; await runTask?.value; runTask = nil
        do { try await flushTail(); try await endUtterance() } catch {
            await cleanupCaptureFailure(error)
            await failed(error.localizedDescription)
        }
    }
    func run() async {
        var samples = [Float](repeating: 0, count: 8_192)
        var lastFramesAt = Date()
        do {
            while !Task.isCancelled {
                if st_ring_dropped(ring.pointer) > 0 { throw AudioFailure.message("收音数据不连续，已保留此前原音；请确认麦克风后恢复录音") }
                let n = samples.withUnsafeMutableBufferPointer { st_ring_read(ring.pointer, $0.baseAddress!, UInt32($0.count)) }
                if n > 0 {
                    lastFramesAt = Date()
                    let batchEnd = lastFramesAt.addingTimeInterval(-Double(st_ring_pending(ring.pointer)) / sampleRate)
                    let converted = try convertCapturedSamples(samples, count: n)
                    var remaining = converted.reduce(0) { $0 + $1.count }
                    for pcm in converted {
                        remaining -= pcm.count
                        try await acceptPCM(pcm, endingAt: batchEnd.addingTimeInterval(-Double(remaining) / 32000))
                    }
                    let energy = samples.prefix(Int(n)).reduce(Float(0)) { $0 + $1 * $1 } / Float(n)
                    update(segmenter.speaking, min(1, sqrt(energy) * 7))
                }
                if !stopping && Date().timeIntervalSince(lastFramesAt) > 3 { throw AudioFailure.message("麦克风停止提供音频，请确认设备和权限后恢复") }
                if stopping && n == 0 { break }
                if !stopping { try await Task.sleep(for: .milliseconds(40)) }
            }
        } catch is CancellationError { }
        catch { await cleanupCaptureFailure(error); await failed(error.localizedDescription) }
    }
    func convertCapturedSamples(_ samples: [Float], count: UInt32) throws -> [Data] {
        precondition(count > 0 && Int(count) <= samples.count)
        let buffer = AVAudioPCMBuffer(pcmFormat: sourceFormat, frameCapacity: count)!
        buffer.frameLength = count
        samples.withUnsafeBufferPointer { buffer.floatChannelData![0].update(from: $0.baseAddress!, count: Int(count)) }
        var supplied = false, result: [Data] = []
        repeat {
            let output = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: UInt32(ceil(Double(count) * 16_000 / sampleRate) + 32))!
            var error: NSError?
            let status = converter.convert(to: output, error: &error) { _, state in
                if supplied { state.pointee = .noDataNow; return nil }
                supplied = true; state.pointee = .haveData; return buffer
            }
            if status == .error { throw error ?? AudioFailure.message("收音格式转换失败") as NSError }
            if output.frameLength > 0 { result.append(Data(bytes: output.int16ChannelData![0], count: Int(output.frameLength) * 2)) }
            // A smaller output buffer can be filled entirely from the converter's
            // earlier input. Keep this newly read ring batch until the callback
            // actually accepts it; otherwise it vanishes without a ring overflow.
            if !supplied && output.frameLength == 0 { throw AudioFailure.message("收音格式转换未继续处理输入，请恢复录音") }
        } while !supplied
        return result
    }
    func drainConvertedTail() throws -> [Data] {
        var result: [Data] = []
        while true {
            let output = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: 4_096)!
            var error: NSError?
            let status = converter.convert(to: output, error: &error) { _, state in state.pointee = .endOfStream; return nil }
            if status == .error { throw error ?? AudioFailure.message("收音尾部转换失败") as NSError }
            if output.frameLength > 0 { result.append(Data(bytes: output.int16ChannelData![0], count: Int(output.frameLength) * 2)) }
            if output.frameLength == 0 || status == .endOfStream { break }
        }
        return result
    }
    private var lastPCMEnd: Date?
    func acceptPCM(_ pcm: Data, endingAt time: Date = .now) async throws {
        lastPCMEnd = time
        for event in segmenter.accept(pcm, nextMaximumFrames: recognitionFactory.isHosted ? 1500 : nil) {
            switch event {
            case let .begin(preRoll, sample):
                try await beginUtterance(at: time.addingTimeInterval(Double(sample - segmenter.receivedSamples) / 16000))
                for frame in preRoll { try await append(frame) }
            case let .audio(frame): try await append(frame)
            case let .end(sample): try await endUtterance(at: time.addingTimeInterval(Double(sample - segmenter.receivedSamples) / 16000))
            }
        }
    }
    func flushTail() async throws {
        for pcm in try drainConvertedTail() {
            try await acceptPCM(pcm, endingAt: (lastPCMEnd ?? .now).addingTimeInterval(Double(pcm.count) / 32000))
        }
        for event in segmenter.finish() {
            if case let .audio(data) = event { try await append(data) }
            if case let .end(sample) = event {
                try await endUtterance(at: (lastPCMEnd ?? .now).addingTimeInterval(Double(sample - segmenter.receivedSamples) / 16000))
            }
        }
    }
    func beginUtterance(at start: Date = .now) async throws {
        // A settings change during journal creation must not grant new destinations
        // to audio that began under a local-only or older consent configuration.
        let snapshot = recognitionFactory.snapshot
        let record = try await store.createRecording(createdAt: start)
        recordingID = record.id
        do {
            let journal = try PCMJournal(directory: store.audioDirectory, recordingID: record.id, io: journalIO)
            try journal.openChunk(); self.journal = journal
            try await store.registerAudioChunk(recordingID: record.id, relativePath: journal.relativePath, frames: 0)
        } catch {
            await cleanupCaptureFailure(error)
            throw error
        }
        // Recognition setup cannot terminate the independent recorder.
        do {
            guard recognitionEnabled else { return }
            let config = snapshot.configuration
            if config.cloudEnabled && !snapshot.isHosted {
                try await store.authorizeCloudRecovery(recordingID: record.id, configuration: config)
            }
            let ticket = try await (config.cloudEnabled
                ? store.beginFusionRecognition(recordingID: record.id, mode: config.inputMode)
                : store.beginRecognition(recordingID: record.id))
            speech = recognitionFactory.make(store: store, ticket: ticket, snapshot: snapshot)
        } catch { speech = nil }
    }
    func append(_ data: Data) async throws {
        guard let journal, let recordingID else { return }
        try journal.append(data)
        if journal.needsCheckpoint || journal.needsRotation {
            try journal.checkpoint()
            try await store.registerAudioChunk(recordingID: recordingID, relativePath: journal.relativePath, frames: journal.frames)
            let attributes = try FileManager.default.attributesOfFileSystem(forPath: store.audioDirectory.path)
            if let bytes = attributes[.systemFreeSize] as? NSNumber, bytes.int64Value < 100_000_000 { throw AudioFailure.message("磁盘可用空间不足，已暂停收音") }
        }
        speech?.append(data)
        if journal.needsRotation {
            try journal.closeChunk(); try journal.openChunk()
            try await store.registerAudioChunk(recordingID: recordingID, relativePath: journal.relativePath, frames: 0)
        }
    }
    func endUtterance(at end: Date = .now) async throws {
        guard let recordingID else { return }
        guard let journal, journal.isOpen else {
            let error = AudioFailure.message("原音文件未创建，录音已停止")
            await cleanupCaptureFailure(error); throw error
        }
        do {
        try journal.closeChunk()
        try await store.registerAudioChunk(recordingID: recordingID, relativePath: journal.relativePath, frames: journal.frames)
        try await store.finishRecording(id: recordingID, speechEndedAt: end)
        speech?.finish()
        // Closed-input sessions finish independently. Admission is bounded by the
        // cloud factory, never by cancelling older accepted recognition results.
        retired.removeAll { $0.isComplete }
        if let speech { retired.append(speech) }
        self.speech = nil; self.journal = nil; self.recordingID = nil
        } catch { await cleanupCaptureFailure(error); throw error }
    }
    func cleanupCaptureFailure(_ error: Error) async {
        speech?.cancel()
        guard let recordingID else { journal?.abandonOpenHandle(); journal = nil; speech = nil; return }
        if let journal {
            // Retry synchronization once. If it still fails, only publish the last
            // successfully synchronized watermark, never the speculative tail.
            try? journal.closeChunk()
            if !journal.relativePath.isEmpty, journal.durableFrames > 0 {
                try? await store.registerAudioChunk(recordingID: recordingID, relativePath: journal.relativePath, frames: journal.durableFrames)
            }
            journal.abandonOpenHandle()
        }
        try? await store.finishRecording(id: recordingID)
        let chunks = (try? await store.audioChunks(recordingID: recordingID)) ?? []
        let message = "采集已中断：\(error.localizedDescription)。未确认的尾部不计入已保存范围。"
        if chunks.contains(where: { $0.frames > 0 }) {
            try? await store.recordCaptureFailure(recordingID: recordingID, message: message)
        } else {
            try? await store.markAudioMissing(recordingID: recordingID, message: message)
        }
        speech = nil; journal = nil; self.recordingID = nil
    }
    func hasPendingRecognition() -> Bool { speech?.isComplete == false || retired.contains { !$0.isComplete } }
    func cancelRecognitionAndWait(recordingID: UUID? = nil) async {
        let sessions = (retired + (speech.map { [$0] } ?? [])).filter { recordingID == nil || $0.recordingID == recordingID }
        let cancelledIDs = Set(sessions.map { ObjectIdentifier($0) })
        sessions.forEach { $0.cancel() }
        for session in sessions { await session.wait() }
        // The worker is reentrant while awaiting providers. Newly retired jobs
        // still belong to us and must remain cancellable by the next revocation.
        retired.removeAll { cancelledIDs.contains(ObjectIdentifier($0)) }
    }

}

@MainActor
public final class AudioController: NSObject, ObservableObject, AVAudioPlayerDelegate {
    @Published public private(set) var state: CaptureState = .paused
    @Published public private(set) var level: Float = 0
    @Published public var issue: String?
    @Published public private(set) var devices: [AudioInputDevice] = []
    @Published public var selectedDeviceID: UInt32 = 0 {
        didSet {
            if !selectingDeviceUID { selectedDeviceUID = selectedDeviceID == 0 ? nil : devices.first(where: { $0.id == selectedDeviceID })?.uid }
            guard oldValue != selectedDeviceID, state.isRunning else { return }
            let generation = startGeneration
            Task {
                state = .paused
                await stopCapture()
                guard generation == startGeneration, requestedRunning else { return }
                await start(requestPermission: false)
            }
        }
    }
    @Published public private(set) var selectedDeviceUID: String?
    private var selectingDeviceUID = false
    @Published public private(set) var playingID: UUID?
    @Published public private(set) var playbackPosition: Double = 0
    @Published public private(set) var playbackDuration: Double = 0
    @Published public private(set) var speechStatus = "正在检查识别资源"
    @Published public private(set) var preparingSpeech = false
    @Published public private(set) var reprocessingID: UUID?
    private let store: SaytileStore
    private let recognitionFactory: RecognitionSessionFactory
    private var pinnedInput: PinnedAudioInput?
    private var engine: AVAudioEngine?
    private var worker: CaptureWorker?
    private var stopTask: Task<Void, Never>?
    private var shutdownTask: Task<Void, Never>?
    private var isShuttingDown = false
    private var drainingWorkers: [CaptureWorker] = []
    private var assetTask: Task<Void, Never>?
    private var availabilityTask: Task<Void, Never>?
    private var automaticAssetTask: Task<Void, Never>?
    private var ring: AudioRing?
    private var observers: [NSObjectProtocol] = []
    private var requestedRunning = false
    private var startGeneration: UInt64 = 0
    private var automaticAssetAttempted = false
    private var lifecycleGate = AudioLifecycleGate()
    private var lockBridge: AudioLockEventBridge?
    private var lifecycleTask: Task<Void, Never>?
    private var interruption = false
    private var playbackResume = false
    private var playbackGeneration: UInt64 = 0
    private var playbackLease: UUID?
    private var leaseReleaseTasks: [UUID: Task<Void, Never>] = [:]
    private var player: AVAudioPlayer?
    private var playbackURLs: [URL] = []
    private var playbackTimeline = AudioPlaybackTimeline(durations: [])
    private var playbackIndex = 0
    private var playbackProgressTask: Task<Void, Never>?
    private var retryTask: Task<Void, Never>?
    private var lastVoiceAt = Date.distantPast
    private var recoveryTask: Task<Void, Never>?
    private var startupRecoveryReady: Bool
    private var meterTask: Task<Void, Never>?
    private var meterContinuation: AsyncStream<(Bool, Float)>.Continuation?
    public convenience init(store: SaytileStore, recognitionConfiguration: RecognitionConfiguration = RecognitionConfiguration(), startupRecoveryReady: Bool = true) {
        self.init(store: store, recognitionFactory: RecognitionSessionFactory(configuration: recognitionConfiguration),
                  startupRecoveryReady: startupRecoveryReady)
    }
    init(store: SaytileStore, recognitionFactory: RecognitionSessionFactory, startupRecoveryReady: Bool = true) {
        self.startupRecoveryReady = startupRecoveryReady
        self.store = store; self.recognitionFactory = recognitionFactory
        super.init(); refreshDevices()
        let center = NSWorkspace.shared.notificationCenter
        observers.append(center.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in Task { @MainActor in
            guard let self else { return }
            self.lifecycleGate.sleeping = true
            if AudioLifecycleGate.shouldSuspendForSystemLifecycle(state: self.state, requestedRunning: self.requestedRunning) {
                await self.suspend(reason: "Mac 已睡眠")
            }
        } })
        observers.append(center.addObserver(forName: NSWorkspace.sessionDidResignActiveNotification, object: nil, queue: .main) { [weak self] _ in Task { @MainActor in
            guard let self else { return }
            self.lifecycleGate.sessionInactive = true
            if AudioLifecycleGate.shouldSuspendForSystemLifecycle(state: self.state, requestedRunning: self.requestedRunning) {
                await self.suspend(reason: "会话已暂停")
            }
        } })
        observers.append(center.addObserver(forName: NSWorkspace.sessionDidBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in Task { @MainActor in
            guard let self else { return }; self.lifecycleGate.sessionInactive = false; self.lifecycleGate.refresh(AudioSessionSnapshot.current())
            if self.requestedRunning && self.lifecycleGate.permitsCapture { await self.start(requestPermission: false) }
        } })
        observers.append(center.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in Task { @MainActor in
            guard let self else { return }; self.lifecycleGate.sleeping = false; self.lifecycleGate.refresh(AudioSessionSnapshot.current())
            if self.requestedRunning && self.lifecycleGate.permitsCapture { await self.start(requestPermission: false) }
        } })
        observers.append(NotificationCenter.default.addObserver(forName: .AVAudioEngineConfigurationChange, object: nil, queue: .main) { [weak self] note in
            let changedEngine = (note.object as? AVAudioEngine).map(ObjectIdentifier.init)
            Task { @MainActor in
                guard let self, self.state.isRunning, let engine = self.engine,
                      changedEngine == ObjectIdentifier(engine) else { return }
                await self.suspend(reason: "麦克风配置改变，请确认设备后恢复")
                self.refreshDevices()
            }
        })
        lifecycleGate.refresh(AudioSessionSnapshot.current())
        lockBridge = AudioLockEventBridge { [weak self] locked in
            guard let self else { return }
            if locked {
                self.lifecycleGate.receivedLock()
                if self.state.isRunning { await self.suspend(reason: "屏幕已锁定") }
            } else {
                self.lifecycleGate.receivedUnlock(snapshot: AudioSessionSnapshot.current())
                if self.requestedRunning && self.lifecycleGate.permitsCapture { await self.start(requestPermission: false) }
            }
        }
        lifecycleTask = Task { [weak self] in
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(1)) } catch { break }
                guard let self, !self.isShuttingDown else { break }
                let previouslyAllowed = self.lifecycleGate.permitsCapture
                self.lifecycleGate.refresh(AudioSessionSnapshot.current())
                if self.state.isRunning && !self.lifecycleGate.permitsCapture {
                    await self.suspend(reason: self.lifecycleGate.reason)
                } else if AudioLifecycleGate.requiresPermissionSuspension(state: self.state, authorization: AVCaptureDevice.authorizationStatus(for: .audio)) {
                    self.requestedRunning = false
                    await self.suspend(reason: "麦克风权限已撤回，请在系统设置恢复权限后重新开启")
                } else if let pinned = self.pinnedInput, self.state.isRunning {
                    do { try pinned.checkProgress() }
                    catch { await self.suspend(reason: error.localizedDescription); self.refreshDevices() }
                } else if !previouslyAllowed && self.lifecycleGate.permitsCapture && self.requestedRunning {
                    await self.start(requestPermission: false)
                }
            }
        }
        availabilityTask = Task {
            speechStatus = recognitionFactory.usesCloud ? "单一语言专家识别 · " + recognitionFactory.configuration.inputMode.label : await AppleSpeechService.availability().message
        }
        recoveryTask = Task { [weak self] in
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(10)) } catch { break }
                guard let self, self.canRecoverInBackground else { continue }
                let recognitionAvailable = self.recognitionFactory.usesCloud ? true : await AppleSpeechService.availability().installed
                guard self.recognitionFactory.configuration.automaticRecovery,
                      recognitionAvailable,
                      self.canRecoverInBackground,
                      let candidate = try? await self.store.claimRecoveryRecording() else { continue }
                guard self.canRecoverInBackground else {
                    try? await self.store.releaseRecoveryClaim(recordingID:candidate.id)
                    continue
                }
                await self.retry(recordingID: candidate.id, isAutomatic: true)
            }
        }
    }
    /// Internal injection keeps lifecycle tests off microphones and user hardware.
    convenience init(store: SaytileStore, initialWorker: CaptureWorker) {
        self.init(store: store, startupRecoveryReady: false)
        worker = initialWorker
    }
    private var recognitionSettingsGeneration: UInt64 = 0
    /// Revoke future cloud sessions synchronously, before awaiting cancellation of old work.
    public func selectHostedRoute(_ route: HostedRoute, revoke: Bool = false) {
        recognitionFactory.select(route, revoke: revoke)
    }

    public func revokeCloudRecognition() {
        recognitionSettingsGeneration &+= 1
        var local = recognitionFactory.configuration; local.cloudEnabled = false
        recognitionFactory.update(local)
        retryTask?.cancel()
        speechStatus = "云端已停用 · 本机识别"
    }
    public func setRouteForNextUtterance(_ configuration: RecognitionConfiguration) {
        recognitionSettingsGeneration &+= 1
        recognitionFactory.update(configuration, nextUtteranceOnly: true)
        speechStatus = configuration.cloudEnabled ? "新讲话使用已选语言专家" : "新讲话使用本机识别"
    }
    public func setRecognitionConfiguration(_ configuration: RecognitionConfiguration) async {
        recognitionSettingsGeneration &+= 1
        let generation = recognitionSettingsGeneration
        recognitionFactory.update(configuration)
        await worker?.cancelRecognitionAndWait()
        for old in drainingWorkers { await old.cancelRecognitionAndWait() }
        guard generation == recognitionSettingsGeneration else { return }
        retryTask?.cancel()
        let message = configuration.cloudEnabled ? "单一语言专家识别 · " + configuration.inputMode.label : await AppleSpeechService.availability().message
        guard generation == recognitionSettingsGeneration else { return }
        speechStatus = message
    }
    /// Best-effort cancellation of in-flight requests. Already received remote audio
    /// cannot be recalled; Store's epoch guard also rejects every later callback.
    public func cancelRecognition(recordingID: UUID) async {
        await worker?.cancelRecognitionAndWait(recordingID: recordingID)
        for old in drainingWorkers { await old.cancelRecognitionAndWait(recordingID: recordingID) }
        if reprocessingID == recordingID {
            let activeRetry = retryTask
            activeRetry?.cancel()
            await activeRetry?.value
        }
    }
    public func prepareSpeechAssets() async {
        guard !isShuttingDown else { return }
        if let assetTask { await assetTask.value; return }
        let task = Task { @MainActor in
            preparingSpeech = true; defer { preparingSpeech = false }
            speechStatus = "正在准备中文识别资源 · 原音继续保存"
            do { try await AppleSpeechService.prepare(); try Task.checkCancellation(); speechStatus = await AppleSpeechService.availability().message }
            catch is CancellationError { }
            catch { if !isShuttingDown { issue = "中文资源下载失败：\(error.localizedDescription)"; speechStatus = issue! } }
        }
        assetTask = task; await task.value; assetTask = nil
    }
    public func start(requestPermission: Bool = true) async {
        guard !isShuttingDown else { return }
        let generationBeforeStop = startGeneration
        if let stopTask { await stopTask.value }
        lifecycleGate.refresh(AudioSessionSnapshot.current())
        guard !isShuttingDown, generationBeforeStop == startGeneration, lifecycleGate.permitsCapture else { return }
        guard !state.isRunning else { return }
        retryTask?.cancel()
        playbackResume = false; stopPlayback(); requestedRunning = true; state = .starting; issue = nil
        startGeneration &+= 1
        let generation = startGeneration
        var allowed = AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
        if requestPermission && AVCaptureDevice.authorizationStatus(for: .audio) == .notDetermined { allowed = await AVCaptureDevice.requestAccess(for: .audio) }
        guard generation == startGeneration, requestedRunning, state == .starting else { return }
        lifecycleGate.refresh(AudioSessionSnapshot.current())
        guard lifecycleGate.permitsCapture else {
            state = .interrupted(lifecycleGate.reason); issue = lifecycleGate.reason; return
        }
        guard allowed else { state = .interrupted("需要麦克风权限"); issue = "请在系统设置 → 隐私与安全性 → 麦克风中允许 Saytile"; return }
        var startingEngine: AVAudioEngine?
        var tapInstalled = false
        do {
            refreshDevices()
            let selected: AudioInputDevice?
            if let uid = selectedDeviceUID {
                guard let device = devices.first(where: { $0.uid == uid }) else { throw AudioFailure.message("所选麦克风未连接，请连接设备或明确选择另一个麦克风") }
                selected = device
            } else if selectedDeviceID != 0 {
                guard let device = devices.first(where: { $0.id == selectedDeviceID }) else { throw AudioFailure.message("所选麦克风未连接") }
                selected = device
            } else {
                selected = nil
            }
            let pinned = try selected.map(PinnedAudioInput.init)
            let engine = pinned == nil ? AVAudioEngine() : nil
            startingEngine = engine
            let input = engine?.inputNode
            let format = input?.outputFormat(forBus: 0)
            if let format {
                guard format.sampleRate > 0, format.channelCount > 0, format.commonFormat == .pcmFormatFloat32, !format.isInterleaved else { throw AudioFailure.message("麦克风格式不受支持") }
            }
            guard let sampleRate = pinned?.sampleRate ?? format?.sampleRate else { throw AudioFailure.message("没有可用的麦克风") }
            let ring = try AudioRing(capacity: UInt32(sampleRate * 4))
            let (meter, meterContinuation) = AsyncStream<(Bool, Float)>.makeStream(bufferingPolicy: .bufferingNewest(1))
            self.meterContinuation = meterContinuation
            meterTask = Task { [weak self] in
                var lastMeter = Date.distantPast
                for await (speaking, level) in meter {
                    guard let self, self.state.isRunning else { continue }
                    if speaking { self.lastVoiceAt = Date(); self.retryTask?.cancel() }
                    let nextState: CaptureState = speaking ? .speaking : .listening
                    if self.state != nextState { self.state = nextState }
                    if Date().timeIntervalSince(lastMeter) >= 0.1 {
                        if abs(self.level - level) > 0.01 { self.level = level }
                        lastMeter = Date()
                    }
                }
            }
            let worker = try CaptureWorker(store: store, ring: ring, sampleRate: sampleRate, recognitionFactory: recognitionFactory, update: { speaking, level in
                meterContinuation.yield((speaking, level))
            }, failed: { [weak self] message in Task { @MainActor in await self?.suspend(reason: message) } })
            if let pinned {
                pinnedInput = pinned
                try pinned.start(ring: ring)
                while pinned.frames == 0 {
                    try await Task.sleep(for: .milliseconds(20))
                    guard generation == startGeneration, requestedRunning, state == .starting else { return }
                    try pinned.checkProgress()
                }
            } else if let engine, let input, let format {
                input.installTap(onBus: 0, bufferSize: 1_024, format: format, block: AudioTapCallbacks.recording(ring: ring, channels: format.channelCount, sampleRate: format.sampleRate))
                tapInstalled = true
                engine.prepare(); try engine.start()
            }
            self.engine = engine; self.ring = ring; self.worker = worker; state = .listening
            await worker.start()
            if !automaticAssetAttempted && !recognitionFactory.usesCloud {
                automaticAssetAttempted = true
                automaticAssetTask = Task {
                    let availability = await AppleSpeechService.availability()
                    if availability.installed { speechStatus = availability.message }
                    else if availability.supported { await prepareSpeechAssets() }
                    else { speechStatus = availability.message }
                }
            }
        } catch {
            guard generation == startGeneration else { return }
            pinnedInput?.stop(); pinnedInput = nil
            startingEngine?.stop()
            if tapInstalled { startingEngine?.inputNode.removeTap(onBus: 0) }
            meterContinuation?.finish(); meterContinuation = nil
            meterTask?.cancel(); meterTask = nil
            state = .interrupted(error.localizedDescription); issue = error.localizedDescription
        }
    }
    public func pause() async { startGeneration &+= 1; playbackGeneration &+= 1; requestedRunning = false; playbackResume = false; state = .paused; await stopCapture() }
    private func stopCapture() async {
        if let stopTask { await stopTask.value; return }
        pinnedInput?.stop(); pinnedInput = nil
        engine?.stop(); engine?.inputNode.removeTap(onBus: 0); engine = nil
        let old = worker; worker = nil; ring = nil; level = 0
        meterContinuation?.finish(); meterContinuation = nil; meterTask?.cancel(); meterTask = nil
        // Keep ownership before the first suspension: revocation must find jobs
        // even while this worker is draining/resynchronizing its final audio.
        if let old { drainingWorkers.append(old) }
        let task = Task<Void, Never> {
            await old?.stop()
            var pending: [CaptureWorker] = []
            for candidate in drainingWorkers where await candidate.hasPendingRecognition() { pending.append(candidate) }
            drainingWorkers = pending
            // Waiters may start a new capture only after all stop bookkeeping,
            // not merely after old.stop() while the pruning await is suspended.
            stopTask = nil
        }
        stopTask = task
        await task.value
    }
    private func suspend(reason: String) async {
        guard !interruption else { return }; interruption = true; defer { interruption = false }
        startGeneration &+= 1
        state = .interrupted(reason); issue = reason
        await stopCapture()
    }
    public func refreshDevices() {
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDevices, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size) == noErr else { return }
        var ids = [AudioDeviceID](repeating: 0, count: Int(size) / MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &ids) == noErr else { return }
        devices = ids.compactMap { id in
            var streamAddress = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyStreams, mScope: kAudioDevicePropertyScopeInput, mElement: kAudioObjectPropertyElementMain)
            var streamSize: UInt32 = 0
            guard AudioObjectGetPropertyDataSize(id, &streamAddress, 0, nil, &streamSize) == noErr, streamSize > 0 else { return nil }
            func stringProperty(_ selector: AudioObjectPropertySelector) -> String? {
                var address = AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
                var value: Unmanaged<CFString>?; var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
                guard AudioObjectGetPropertyData(id, &address, 0, nil, &size, &value) == noErr else { return nil }
                // CoreAudio documents ownership transfer for both name and UID.
                return value?.takeRetainedValue() as String?
            }
            guard let uid = stringProperty(kAudioDevicePropertyDeviceUID) else { return nil }
            return AudioInputDevice(id: id, name: stringProperty(kAudioObjectPropertyName) ?? "麦克风", uid: uid)
        }
    }
    public func selectDevice(uid: String?) {
        selectingDeviceUID = true
        selectedDeviceUID = uid
        selectedDeviceID = uid.flatMap { uid in devices.first(where: { $0.uid == uid })?.id } ?? 0
        selectingDeviceUID = false
        if uid != nil && selectedDeviceID == 0 && state.isRunning {
            Task { await suspend(reason: "所选麦克风未连接") }
        }
    }
    public func play(recordingID: UUID) async throws {
        guard !isShuttingDown else { throw CancellationError() }
        let resume = state.isRunning || playbackResume
        playbackResume = false; stopPlayback()
        let generation = playbackGeneration
        var lease: UUID?
        do {
            lease = try await store.acquireAudioLease(recordingID: recordingID)
            let chunks = try await store.audioChunks(recordingID: recordingID)
            var urls: [URL] = []; var durations: [Double] = []
            let sampleRate = (try await store.recording(id: recordingID))?.sampleRate ?? 16_000
            for chunk in chunks where chunk.frames > 0 {
                urls.append(try await store.audioURL(for: chunk)); durations.append(Double(chunk.frames) / sampleRate)
            }
            guard !urls.isEmpty else { throw AudioFailure.message("原音不存在") }
            guard generation == playbackGeneration, !isShuttingDown else { throw CancellationError() }
            await stopCapture()
            guard generation == playbackGeneration, !isShuttingDown else { throw CancellationError() }
            state = .paused
            playbackLease = lease; playbackResume = resume
            playbackURLs = urls; playbackTimeline = AudioPlaybackTimeline(durations: durations)
            playbackDuration = playbackTimeline.duration; playbackPosition = 0; playbackIndex = 0
            playingID = recordingID; try playCurrentChunk(offset: 0)
            playbackProgressTask = Task { [weak self] in
                while !Task.isCancelled {
                    do { try await Task.sleep(for: .milliseconds(100)) } catch { break }
                    guard let self, let player = self.player, self.playingID != nil else { break }
                    self.playbackPosition = min(self.playbackDuration, self.playbackTimeline.starts[self.playbackIndex] + player.currentTime)
                }
            }
        } catch {
            if generation == playbackGeneration { playbackResume = resume; stopPlayback() }
            if let lease { try? await store.releaseAudioLease(lease) }; throw error
        }
    }
    private func playCurrentChunk(offset: Double) throws {
        guard playbackURLs.indices.contains(playbackIndex) else { stopPlayback(); return }
        player?.stop()
        player = try AVAudioPlayer(contentsOf: playbackURLs[playbackIndex]); player?.delegate = self
        player?.currentTime = offset
        guard player?.play() == true else { throw AudioFailure.message("无法播放原音") }
    }
    public func seekPlayback(to seconds: Double) {
        guard playingID != nil, let location = playbackTimeline.location(at: seconds) else { return }
        do {
            if location.index == playbackIndex { player?.currentTime = location.offset }
            else { playbackIndex = location.index; try playCurrentChunk(offset: location.offset) }
            playbackPosition = playbackTimeline.starts[location.index] + location.offset
        } catch { issue = error.localizedDescription; stopPlayback() }
    }
    public func stopPlayback() {
        playbackGeneration &+= 1
        playbackProgressTask?.cancel(); playbackProgressTask = nil
        player?.stop(); player = nil; playingID = nil; playbackURLs = []
        playbackTimeline = AudioPlaybackTimeline(durations: []); playbackIndex = 0
        playbackPosition = 0; playbackDuration = 0
        if let lease = playbackLease {
            playbackLease = nil
            let store = store
            leaseReleaseTasks[lease] = Task { @MainActor [weak self] in
                try? await store.releaseAudioLease(lease)
                self?.leaseReleaseTasks[lease] = nil
            }
        }
        if playbackResume {
            playbackResume = false
            let generation = startGeneration
            Task {
                guard generation == startGeneration, requestedRunning else { return }
                await start(requestPermission: false)
            }
        }
    }
    nonisolated public func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in
            guard self.player === player else { return }
            guard flag else { issue = "原音播放未完整完成，请重试"; stopPlayback(); return }
            do { playbackIndex += 1; try playCurrentChunk(offset: 0) }
            catch { issue = error.localizedDescription; stopPlayback() }
        }
    }
    nonisolated public func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
        let message = error?.localizedDescription ?? "音频解码失败"
        Task { @MainActor in
            guard self.player === player else { return }
            issue = message; stopPlayback()
        }
    }
    /// Repair/import must finish before background recognition can claim saved audio.
    public func completeStartupRecovery() { startupRecoveryReady = true }
    private var canRecoverInBackground: Bool {
        startupRecoveryReady && !isShuttingDown && lifecycleGate.permitsCapture && playingID == nil && retryTask == nil &&
        (state == .paused || (state == .listening && Date().timeIntervalSince(lastVoiceAt) >= 5))
    }
    public func retry(recordingID: UUID, isAutomatic: Bool = false,
                      expectedConfiguration: RecognitionConfiguration? = nil) async {
        guard !isShuttingDown else { return }
        // Capture the explicit action's destinations before any suspension. An
        // automatic job can only reuse persisted per-recording authorization.
        let captured = recognitionFactory.snapshot
        let currentSnapshot = captured.isHosted ? captured.localOnly : captured
        // The UI captures its applied configuration at the click. A queued task
        // cannot silently acquire different cloud destinations before it starts.
        let requestedSnapshot = expectedConfiguration == nil || expectedConfiguration == currentSnapshot.appliedConfiguration
            ? currentSnapshot : currentSnapshot.localOnly
        if !isAutomatic {
            do {
                if requestedSnapshot.configuration.cloudEnabled {
                    try await store.authorizeCloudRecovery(recordingID: recordingID, configuration: requestedSnapshot.configuration)
                }
                try await store.resetRecognitionRetry(recordingID: recordingID)
            } catch { issue = error.localizedDescription; return }
        }
        guard !isShuttingDown else { return }
        if state == .speaking || state == .starting {
            try? await store.queueRecognition(recordingID: recordingID)
            if isAutomatic { try? await store.releaseRecoveryClaim(recordingID: recordingID) }
            else { issue = "已排队，将在讲话停顿后重新识别" }
            return
        }
        guard retryTask == nil else { issue = "已有重新识别任务，请稍后再试"; return }
        retryTask = Task {
            reprocessingID = recordingID
            defer { retryTask = nil; reprocessingID = nil }
            var lease: UUID?
            var session: (any RecognitionSession)?
            do {
                try Task.checkCancellation()
                let authorized = try await store.permitsAutomaticCloudRecovery(recordingID: recordingID,
                    configuration: requestedSnapshot.configuration)
                let snapshot = authorized ? requestedSnapshot : requestedSnapshot.localOnly
                let config = snapshot.configuration
                if isAutomatic && !config.cloudEnabled {
                    let availability = await recognitionFactory.localAvailability()
                    try Task.checkCancellation()
                    guard availability.installed else {
                        try await store.releaseRecoveryClaim(recordingID: recordingID)
                        return
                    }
                }
                try Task.checkCancellation()
                lease = try await store.acquireAudioLease(recordingID: recordingID)
                let chunks = try await store.audioChunks(recordingID: recordingID)
                let ticket = try await (config.cloudEnabled
                    ? store.beginFusionRecognition(recordingID: recordingID, mode: config.inputMode)
                    : store.beginRecognition(recordingID: recordingID))
                try Task.checkCancellation()
                let activeSession = recognitionFactory.make(store: store, ticket: ticket, snapshot: snapshot)
                session = activeSession
                for chunk in chunks {
                    try Task.checkCancellation()
                    let handle = try FileHandle(forReadingFrom: try await store.audioURL(for: chunk))
                    defer { try? handle.close() }
                    try await SavedAudioReplay.feed(handle: handle, append: { activeSession.append($0) })
                    try handle.close()
                }
                activeSession.finish()
                await withTaskCancellationHandler { await activeSession.wait() } onCancel: { activeSession.cancel() }
                try Task.checkCancellation()
            } catch is CancellationError {
                session?.cancel(); await session?.wait()
                try? await store.queueRecognition(recordingID: recordingID)
                if isAutomatic { try? await store.releaseRecoveryClaim(recordingID:recordingID) }
            } catch { session?.cancel(); await session?.wait(); issue = error.localizedDescription }
            if let lease { try? await store.releaseAudioLease(lease) }
        }
    }
    public func shutdown() async {
        if let shutdownTask { await shutdownTask.value; return }
        isShuttingDown = true; requestedRunning = false; playbackResume = false
        startGeneration &+= 1; playbackGeneration &+= 1
        let task = Task { @MainActor in
            recoveryTask?.cancel(); lifecycleTask?.cancel(); availabilityTask?.cancel()
            automaticAssetTask?.cancel(); assetTask?.cancel(); retryTask?.cancel()
            lockBridge?.invalidate(); lockBridge = nil
            for observer in observers {
                NotificationCenter.default.removeObserver(observer)
                NSWorkspace.shared.notificationCenter.removeObserver(observer)
            }
            observers.removeAll()
            let lease = playbackLease; playbackLease = nil
            stopPlayback()
            if let lease { try? await store.releaseAudioLease(lease) }
            for release in Array(leaseReleaseTasks.values) { await release.value }
            leaseReleaseTasks.removeAll()
            await stopCapture()
            for worker in drainingWorkers { await worker.cancelRecognitionAndWait() }
            drainingWorkers.removeAll()
            await retryTask?.value; await recoveryTask?.value; await lifecycleTask?.value
            await automaticAssetTask?.value; await assetTask?.value; await availabilityTask?.value
            state = .paused
        }
        shutdownTask = task; await task.value
    }

}

/// Saved mono Int16 16 kHz audio follows its source duration. Feeding faster can
/// overflow a healthy real-time provider's bounded queue during long recoveries.
enum SavedAudioReplay {
    static func feed(handle: FileHandle, append: @Sendable (Data) -> Void,
                     pause: @Sendable (Double) async throws -> Void = { try await Task.sleep(for: .seconds($0)) }) async throws {
        try handle.seek(toOffset: 44)
        while let data = try handle.read(upToCount: 6_400), !data.isEmpty {
            try Task.checkCancellation()
            append(data)
            try await pause(Double(data.count) / 32_000)
        }
    }
}
