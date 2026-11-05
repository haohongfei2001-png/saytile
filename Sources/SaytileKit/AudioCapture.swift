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
    let journalIO: PCMJournal.IO
    let update: @Sendable (Bool, Float) -> Void
    let failed: @MainActor @Sendable (String) -> Void
    var segmenter: VoiceSegmenter
    var journal: PCMJournal?
    var recordingID: UUID?
    var speech: LiveSpeechSession?
    var retired: [LiveSpeechSession] = []
    var converter: AVAudioConverter
    var sourceFormat: AVAudioFormat
    var targetFormat: AVAudioFormat
    var runTask: Task<Void, Never>?
    var stopping = false
    init(store: SaytileStore, ring: AudioRing, sampleRate: Double, recognitionEnabled: Bool = true, journalIO: PCMJournal.IO = .live, update: @escaping @Sendable (Bool, Float) -> Void, failed: @escaping @MainActor @Sendable (String) -> Void) throws {
        self.store = store; self.ring = ring; self.sampleRate = sampleRate; self.recognitionEnabled = recognitionEnabled; self.update = update; self.failed = failed
        self.journalIO = journalIO
        segmenter = try VoiceSegmenter()
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
                if st_ring_dropped(ring.pointer) > 0 { throw AudioFailure.message("收音缓冲溢出，已保留此前原音；请恢复录音") }
                let n = samples.withUnsafeMutableBufferPointer { st_ring_read(ring.pointer, $0.baseAddress!, UInt32($0.count)) }
                if n > 0 {
                    lastFramesAt = Date()
                    let buffer = AVAudioPCMBuffer(pcmFormat: sourceFormat, frameCapacity: n)!
                    buffer.frameLength = n
                    samples.withUnsafeBufferPointer { buffer.floatChannelData![0].update(from: $0.baseAddress!, count: Int(n)) }
                    let output = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: UInt32(ceil(Double(n) * 16_000 / sampleRate) + 32))!
                    var supplied = false; var error: NSError?
                    let status = converter.convert(to: output, error: &error) { _, state in
                        if supplied { state.pointee = .noDataNow; return nil }
                        supplied = true; state.pointee = .haveData; return buffer
                    }
                    if status == .error { throw error ?? AudioFailure.message("收音格式转换失败") as NSError }
                    if output.frameLength > 0 {
                        let pcm = Data(bytes: output.int16ChannelData![0], count: Int(output.frameLength) * 2)
                        try await acceptPCM(pcm)
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
    func acceptPCM(_ pcm: Data) async throws {
        for event in segmenter.accept(pcm) {
            switch event {
            case let .begin(preRoll): try await beginUtterance(); for frame in preRoll { try await append(frame) }
            case let .audio(frame): try await append(frame)
            case .end: try await endUtterance()
            }
        }
    }
    func flushTail() async throws {
        while true {
            let output = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: 4_096)!
            var error: NSError?
            let status = converter.convert(to: output, error: &error) { _, state in state.pointee = .endOfStream; return nil }
            if status == .error { throw error ?? AudioFailure.message("收音尾部转换失败") as NSError }
            if output.frameLength > 0 { try await acceptPCM(Data(bytes: output.int16ChannelData![0], count: Int(output.frameLength) * 2)) }
            if output.frameLength == 0 || status == .endOfStream { break }
        }
        for event in segmenter.finish() {
            if case let .audio(data) = event { try await append(data) }
            if case .end = event { try await endUtterance() }
        }
    }
    func beginUtterance() async throws {
        let record = try await store.createRecording()
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
            let ticket = try await store.beginRecognition(recordingID: record.id)
            speech = LiveSpeechSession(store: store, ticket: ticket)
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
    func endUtterance() async throws {
        guard let recordingID else { return }
        guard let journal, journal.isOpen else {
            let error = AudioFailure.message("原音文件未创建，录音已停止")
            await cleanupCaptureFailure(error); throw error
        }
        do {
        try journal.closeChunk()
        try await store.registerAudioChunk(recordingID: recordingID, relativePath: journal.relativePath, frames: journal.frames)
        try await store.finishRecording(id: recordingID)
        speech?.finish()
        // At most two draining recognizers. Their inputs are already closed.
        if let speech { retired.append(speech) }
        if retired.count > 2 { retired.removeFirst().cancel() }
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
        let message = "采集因保存故障停止：\(error.localizedDescription)。未确认的尾部不计入已保存范围。"
        if chunks.contains(where: { $0.frames > 0 }) {
            try? await store.recordCaptureFailure(recordingID: recordingID, message: message)
        } else {
            try? await store.markAudioMissing(recordingID: recordingID, message: message)
        }
        speech = nil; journal = nil; self.recordingID = nil
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
            guard oldValue != selectedDeviceID, state.isRunning else { return }
            let generation = startGeneration
            Task {
                state = .paused
                await stopCapture()
                guard generation == startGeneration, requestedRunning else { return }
                await start()
            }
        }
    }
    @Published public private(set) var playingID: UUID?
    @Published public private(set) var speechStatus = "正在检查识别资源"
    @Published public private(set) var preparingSpeech = false
    @Published public private(set) var reprocessingID: UUID?
    private let store: SaytileStore
    private var engine: AVAudioEngine?
    private var worker: CaptureWorker?
    private var stopTask: Task<Void, Never>?
    private var ring: AudioRing?
    private var observers: [NSObjectProtocol] = []
    private var requestedRunning = false
    private var startGeneration: UInt64 = 0
    private var automaticAssetAttempted = false
    private var systemSleeping = false
    private var sessionInactive = false
    private var interruption = false
    private var playbackResume = false
    private var playbackLease: UUID?
    private var player: AVAudioPlayer?
    private var playbackURLs: [URL] = []
    private var retryTask: Task<Void, Never>?
    private var recoveryTask: Task<Void, Never>?
    private var meterTask: Task<Void, Never>?
    private var meterContinuation: AsyncStream<(Bool, Float)>.Continuation?
    public init(store: SaytileStore) {
        self.store = store; super.init(); refreshDevices()
        let center = NSWorkspace.shared.notificationCenter
        observers.append(center.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in Task { @MainActor in
            self?.systemSleeping = true; await self?.suspend(reason: "Mac 已睡眠")
        } })
        observers.append(center.addObserver(forName: NSWorkspace.sessionDidResignActiveNotification, object: nil, queue: .main) { [weak self] _ in Task { @MainActor in
            self?.sessionInactive = true; await self?.suspend(reason: "会话已暂停")
        } })
        observers.append(center.addObserver(forName: NSWorkspace.sessionDidBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in Task { @MainActor in
            guard let self else { return }; self.sessionInactive = false
            if self.requestedRunning && !self.systemSleeping { await self.start() }
        } })
        observers.append(center.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in Task { @MainActor in
            guard let self else { return }; self.systemSleeping = false
            if self.requestedRunning && !self.sessionInactive { await self.start() }
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
        Task { speechStatus = await AppleSpeechService.availability().message }
        recoveryTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(30))
                guard let self, !self.state.isRunning, self.playingID == nil, self.retryTask == nil else { continue }
                guard await AppleSpeechService.availability().installed,
                      !self.state.isRunning, self.playingID == nil, self.retryTask == nil,
                      let candidate = try? await self.store.claimRecoveryRecording() else { continue }
                guard !self.state.isRunning, self.playingID == nil, self.retryTask == nil else {
                    try? await self.store.releaseRecoveryClaim(recordingID:candidate.id)
                    continue
                }
                await self.retry(recordingID: candidate.id, isAutomatic: true)
            }
        }
    }
    public func prepareSpeechAssets() async {
        guard !preparingSpeech else { return }; preparingSpeech = true; defer { preparingSpeech = false }
        speechStatus = "正在准备中文识别资源 · 原音继续保存"
        do { try await AppleSpeechService.prepare(); speechStatus = await AppleSpeechService.availability().message }
        catch { issue = "中文资源下载失败：\(error.localizedDescription)"; speechStatus = issue! }
    }
    public func start() async {
        let generationBeforeStop = startGeneration
        if let stopTask { await stopTask.value }
        guard generationBeforeStop == startGeneration, !systemSleeping, !sessionInactive else { return }
        guard !state.isRunning else { return }
        retryTask?.cancel()
        playbackResume = false; stopPlayback(); requestedRunning = true; state = .starting; issue = nil
        startGeneration &+= 1
        let generation = startGeneration
        var allowed = AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
        if AVCaptureDevice.authorizationStatus(for: .audio) == .notDetermined { allowed = await AVCaptureDevice.requestAccess(for: .audio) }
        guard generation == startGeneration, requestedRunning, state == .starting else { return }
        guard allowed else { state = .interrupted("需要麦克风权限"); issue = "请在系统设置 → 隐私与安全性 → 麦克风中允许 Saytile"; return }
        var startingEngine: AVAudioEngine?
        var tapInstalled = false
        do {
            let engine = AVAudioEngine()
            startingEngine = engine
            let input = engine.inputNode
            if selectedDeviceID != 0 {
                var id = selectedDeviceID
                let result = AudioUnitSetProperty(input.audioUnit!, kAudioOutputUnitProperty_CurrentDevice, kAudioUnitScope_Global, 0, &id, UInt32(MemoryLayout.size(ofValue: id)))
                guard result == noErr else { throw AudioFailure.message("所选麦克风不可用，请重新选择") }
            }
            let format = input.outputFormat(forBus: 0)
            guard format.sampleRate > 0, format.channelCount > 0, format.commonFormat == .pcmFormatFloat32, !format.isInterleaved else { throw AudioFailure.message("麦克风格式不受支持") }
            let ring = try AudioRing(capacity: UInt32(format.sampleRate * 4))
            let (meter, meterContinuation) = AsyncStream<(Bool, Float)>.makeStream(bufferingPolicy: .bufferingNewest(1))
            self.meterContinuation = meterContinuation
            meterTask = Task { [weak self] in
                var lastMeter = Date.distantPast
                for await (speaking, level) in meter {
                    guard let self, self.state.isRunning else { continue }
                    let nextState: CaptureState = speaking ? .speaking : .listening
                    if self.state != nextState { self.state = nextState }
                    if Date().timeIntervalSince(lastMeter) >= 0.1 {
                        if abs(self.level - level) > 0.01 { self.level = level }
                        lastMeter = Date()
                    }
                }
            }
            let worker = try CaptureWorker(store: store, ring: ring, sampleRate: format.sampleRate, update: { speaking, level in
                meterContinuation.yield((speaking, level))
            }, failed: { [weak self] message in Task { @MainActor in await self?.suspend(reason: message) } })
            let channelCount = format.channelCount
            input.installTap(onBus: 0, bufferSize: 1_024, format: format, block: AudioTapCallbacks.recording(ring: ring, channels: channelCount))
            tapInstalled = true
            engine.prepare(); try engine.start()
            self.engine = engine; self.ring = ring; self.worker = worker; state = .listening
            await worker.start()
            if !automaticAssetAttempted {
                automaticAssetAttempted = true
                Task {
                    let availability = await AppleSpeechService.availability()
                    if availability.installed { speechStatus = availability.message }
                    else if availability.supported { await prepareSpeechAssets() }
                    else { speechStatus = availability.message }
                }
            }
        } catch {
            startingEngine?.stop()
            if tapInstalled { startingEngine?.inputNode.removeTap(onBus: 0) }
            meterContinuation?.finish(); meterContinuation = nil
            meterTask?.cancel(); meterTask = nil
            state = .interrupted(error.localizedDescription); issue = error.localizedDescription
        }
    }
    public func pause() async { startGeneration &+= 1; requestedRunning = false; playbackResume = false; state = .paused; await stopCapture() }
    private func stopCapture() async {
        if let stopTask { await stopTask.value; return }
        engine?.stop(); engine?.inputNode.removeTap(onBus: 0); engine = nil
        let old = worker; worker = nil; ring = nil; level = 0
        meterContinuation?.finish(); meterContinuation = nil; meterTask?.cancel(); meterTask = nil
        let task = Task<Void, Never> { await old?.stop() }
        stopTask = task
        await task.value
        stopTask = nil
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
            var nameAddress = AudioObjectPropertyAddress(mSelector: kAudioObjectPropertyName, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
            var name: Unmanaged<CFString>?; var nameSize = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
            _ = AudioObjectGetPropertyData(id, &nameAddress, 0, nil, &nameSize, &name)
            return AudioInputDevice(id: id, name: (name?.takeUnretainedValue() as String?) ?? "麦克风")
        }
    }
    public func play(recordingID: UUID) async throws {
        let resume = state.isRunning
        playbackResume = false; stopPlayback()
        let lease = try await store.acquireAudioLease(recordingID: recordingID)
        do {
            let chunks = try await store.audioChunks(recordingID: recordingID)
            var urls: [URL] = []
            for chunk in chunks where chunk.frames > 0 { urls.append(try await store.audioURL(for: chunk)) }
            guard !urls.isEmpty else { throw AudioFailure.message("原音不存在") }
            await stopCapture(); state = .paused
            playbackLease = lease; playbackResume = resume
            playbackURLs = urls; playingID = recordingID; try playNext()
        } catch { stopPlayback(); try? await store.releaseAudioLease(lease); throw error }
    }
    private func playNext() throws {
        guard !playbackURLs.isEmpty else { stopPlayback(); return }
        player = try AVAudioPlayer(contentsOf: playbackURLs.removeFirst()); player?.delegate = self
        guard player?.play() == true else { throw AudioFailure.message("无法播放原音") }
    }
    public func stopPlayback() {
        player?.stop(); player = nil; playingID = nil; playbackURLs = []
        if let lease = playbackLease { playbackLease = nil; Task { try? await store.releaseAudioLease(lease) } }
        if playbackResume {
            playbackResume = false
            let generation = startGeneration
            Task {
                guard generation == startGeneration, requestedRunning else { return }
                await start()
            }
        }
    }
    nonisolated public func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in do { try playNext() } catch { issue = error.localizedDescription; stopPlayback() } }
    }
    public func retry(recordingID: UUID, isAutomatic: Bool = false) async {
        guard retryTask == nil else { issue = "已有重新识别任务，请稍后再试"; return }
        retryTask = Task {
            reprocessingID = recordingID
            defer { retryTask = nil; reprocessingID = nil }
            var lease: UUID?
            var session: LiveSpeechSession?
            do {
                lease = try await store.acquireAudioLease(recordingID: recordingID)
                let chunks = try await store.audioChunks(recordingID: recordingID)
                let ticket = try await store.beginRecognition(recordingID: recordingID)
                let activeSession = LiveSpeechSession(store: store, ticket: ticket)
                session = activeSession
                for chunk in chunks {
                    try Task.checkCancellation()
                    let handle = try FileHandle(forReadingFrom: try await store.audioURL(for: chunk))
                    defer { try? handle.close() }
                    try handle.seek(toOffset: 44)
                    while let data = try handle.read(upToCount: 6_400), !data.isEmpty {
                        activeSession.append(data); try await Task.sleep(for: .milliseconds(100))
                    }
                    try handle.close()
                }
                activeSession.finish(); await activeSession.wait()
            } catch is CancellationError {
                session?.cancel(); await session?.wait()
                try? await store.queueRecognition(recordingID: recordingID)
                if isAutomatic { try? await store.releaseRecoveryClaim(recordingID:recordingID) }
            } catch { session?.cancel(); issue = error.localizedDescription }
            if let lease { try? await store.releaseAudioLease(lease) }
        }
    }
}
