import Darwin
import Foundation

/// One captured choice per ticket. Capture always owns the PCM journal.
protocol LocalASRProvider: Sendable {
    func open(store: SaytileStore, ticket: RecognitionTicket) -> any RecognitionSession
}
/// A definite provider or asset failure. Silence, store errors and an
/// explicitly cancelled session must not change routing for later speech.
struct LocalASREngineUnavailable: LocalizedError {
    let reason: String
    var errorDescription: String? { reason }
}

struct AppleLocalASR: LocalASRProvider {
    var onUnavailable: (@Sendable (LocalASRID) -> Void)? = nil
    var review: LocalTextReview? = nil
    func open(store: SaytileStore, ticket: RecognitionTicket) -> any RecognitionSession {
        LiveSpeechSession(store: store, ticket: ticket, review: review, onUnavailable: onUnavailable)
    }
}
struct NativeLocalASR: LocalASRProvider {
    var onUnavailable: (@Sendable (LocalASRID) -> Void)? = nil
    let model: LocalASRID
    let service: LocalASRService
    var review: LocalTextReview? = nil
    func open(store: SaytileStore, ticket: RecognitionTicket) -> any RecognitionSession {
        ModelRecognitionSession(model: model, service: service, store: store, ticket: ticket, review: review, onUnavailable: onUnavailable)
    }
}

/// Optional decode times are emitted only for an isolated local stream probe.
public struct WorkerDecodeTiming: Codable, Sendable {
    public let startUptime: Double
    public let endUptime: Double
    public let frames: Int
    public let final: Bool
    public let changed: Bool?
    public let verifiedPreviewTokens: Int?
}

public struct WorkerStartupTiming: Codable, Sendable {
    public let stage: String
    public let uptime: Double
}

public struct WorkerEvent: Decodable, Sendable {
    public let kind: String
    public let text: String
    public let frames: Int
    public let decodes: [WorkerDecodeTiming]?
    public let startup: [WorkerStartupTiming]?
}

final class ModelWorker: @unchecked Sendable {
    let id: LocalASRID
    let process = Process()
    let input: FileHandle
    let events: AsyncThrowingStream<WorkerEvent, Error>
    init(id: LocalASRID, directory: URL, helpers: URL, stride: Int,
         observe: (@Sendable (WorkerEvent) -> Void)? = nil) throws {
        self.id = id
        let stdin = Pipe(), stdout = Pipe()
        input = stdin.fileHandleForWriting
        _ = fcntl(input.fileDescriptor, F_SETNOSIGPIPE, 1)
        process.executableURL = helpers.appending(path: id.sherpaRuntime ? "SaytileSherpa" : "SaytileModelWorker")
        if let resources = Bundle.main.resourceURL,
           FileManager.default.fileExists(atPath: resources.appending(path: "default.metallib").path) {
            process.currentDirectoryURL = resources
        }
        process.arguments = [id.rawValue, directory.path, String(stride)]
        if observe != nil {
            var environment = ProcessInfo.processInfo.environment
            environment["SAYTILE_WORKER_TIMING"] = "1"
            process.environment = environment
        }
        process.standardInput = stdin
        process.standardOutput = stdout
        process.standardError = FileHandle.nullDevice
        let (stream, channel) = AsyncThrowingStream<WorkerEvent, Error>.makeStream(bufferingPolicy: .bufferingOldest(128))
        events = stream
        try process.run()
        try? stdin.fileHandleForReading.close()
        try? stdout.fileHandleForWriting.close()
        let source = stdout.fileHandleForReading
        DispatchQueue(label: "saytile.asr.results", qos: .userInitiated).async {
            defer { try? source.close() }
            do {
                var pending = Data()
                // Darwin FileHandle.read(upToCount:) can wait to fill the requested
                // length on a live pipe. A short POSIX read surfaces each flushed line.
                var buffer = [UInt8](repeating: 0, count: 16_384)
                while true {
                    let count = buffer.withUnsafeMutableBytes { Darwin.read(source.fileDescriptor, $0.baseAddress, $0.count) }
                    if count < 0 && errno == EINTR { continue }
                    if count < 0 { throw LocalASREngineUnavailable(reason: "本机识别结果读取失败") }
                    if count == 0 { break }
                    pending.append(contentsOf: buffer.prefix(count))
                    while let end = pending.firstIndex(of: 10) {
                        let line = pending[..<end]
                        let event: WorkerEvent
                        do { event = try JSONDecoder().decode(WorkerEvent.self, from: line) }
                        catch { throw LocalASREngineUnavailable(reason: "本机识别返回了无效结果") }
                        observe?(event)
                        if case .dropped = channel.yield(event) { throw AudioFailure.message("本机识别回传队列已满") }
                        pending.removeSubrange(...end)
                    }
                    if pending.count > 1024 * 1024 { throw LocalASREngineUnavailable(reason: "本机识别输出过长") }
                }
                channel.finish(throwing: LocalASREngineUnavailable(reason: "本机识别进程已退出"))
            } catch { channel.finish(throwing: error) }
        }
    }
    func write(_ data: Data) throws {
        for start in Swift.stride(from: 0, to: max(1, data.count), by: 65_536) {
            let end = min(start + 65_536, data.count)
            var count = UInt32(end - start).littleEndian
            var frame = withUnsafeBytes(of: &count) { Data($0) }
            frame.append(data[(data.startIndex + start)..<(data.startIndex + end)])
            try input.write(contentsOf: frame)
        }
    }
    func stop() {
        if process.isRunning { process.terminate() }
    }
    deinit { stop(); try? input.close() }
}

/// Pressure is a system condition, not a user-facing performance mode. This
/// watcher owns no model and cannot start inference while the microphone is quiet.
private final class LocalModelMemoryPressureMonitor: @unchecked Sendable {
    private let source: any DispatchSourceMemoryPressure
    init(_ changed: @escaping @Sendable (Bool) -> Void) {
        source = DispatchSource.makeMemoryPressureSource(eventMask: [.normal, .warning, .critical],
                                                        queue: .global(qos: .utility))
        source.setEventHandler { [weak self] in
            guard let self else { return }
            changed(!self.source.data.intersection([.warning, .critical]).isEmpty)
        }
        source.activate()
    }
    deinit { source.cancel() }
}

public actor LocalASRService {
    /// Thinking and reading pauses should normally reuse the already loaded
    /// model. Pausing, sleeping and memory pressure can end this lease early.
    static let warmIdleRetention: Duration = .seconds(180)
    public nonisolated let library: LocalModelLibrary
    private let helpers: URL
    private let chunkFrames: Int?
    private let validatedDirectory: @Sendable (LocalASRID) async throws -> URL
    private let idleRetention: Duration
    private var probeObserver: (@Sendable (WorkerEvent) -> Void)?
    private var waiting: [UUID] = []
    private var activeModel: LocalASRID?
    private var worker: ModelWorker?
    private var idle: Task<Void, Never>?
    private var idleGeneration: UInt64 = 0
    private var standbyEnabled = true
    private var elevatedMemoryPressure = false
    private var releaseRequested = false
    private var pressureMonitor: LocalModelMemoryPressureMonitor?
    public init(root: URL, helpers: URL? = nil, chunkFrames: Int? = nil) {
        let library = LocalModelLibrary(root: root)
        self.library = library
        self.helpers = helpers ?? Bundle.main.bundleURL.appending(path: "Contents/Helpers")
        self.chunkFrames = chunkFrames
        idleRetention = Self.warmIdleRetention
        validatedDirectory = { id in try await library.validated(LocalModelManifest.load(id)) }
    }
    /// Isolated process tests exercise the real pipe, session and lifecycle with
    /// a deterministic worker; production always uses the verified model library.
    init(root: URL, helpers: URL, idleRetention: Duration,
         validatedDirectory: @escaping @Sendable (LocalASRID) async throws -> URL) {
        library = LocalModelLibrary(root: root)
        self.helpers = helpers
        self.chunkFrames = nil
        self.idleRetention = idleRetention
        self.validatedDirectory = validatedDirectory
    }
    deinit { idle?.cancel(); worker?.stop() }
    /// Called only by the isolated fixture probe before it starts its first session.
    public func observeFixtureWorker(_ observe: @escaping @Sendable (WorkerEvent) -> Void) {
        probeObserver = observe
    }

    public func releaseIdle() {
        // Do not throw away an in-flight final. Remember the request so that
        // completion actually releases it instead of starting another warm lease.
        releaseRequested = true
        stopIdleWorker()
    }
    public func setStandbyEnabled(_ enabled: Bool) {
        standbyEnabled = enabled
        if !enabled { stopIdleWorker() }
    }
    func memoryPressureChanged(elevated: Bool) {
        elevatedMemoryPressure = elevated
        if elevated { stopIdleWorker() }
    }
    private func cancelIdleRelease() {
        idleGeneration &+= 1
        idle?.cancel(); idle = nil
    }
    private func stopIdleWorker() {
        guard activeModel == nil else { return }
        cancelIdleRelease()
        worker?.stop()
        worker = nil
        releaseRequested = false
    }
    private func finishedRecognition() {
        activeModel = nil
        guard standbyEnabled, !elevatedMemoryPressure, !releaseRequested, worker != nil else {
            stopIdleWorker(); return
        }
        cancelIdleRelease()
        let generation = idleGeneration, duration = idleRetention
        idle = Task { [weak self] in
            do { try await Task.sleep(for: duration) } catch { return }
            await self?.expireIdleLease(generation)
        }
    }
    private func expireIdleLease(_ generation: UInt64) {
        guard generation == idleGeneration, activeModel == nil else { return }
        stopIdleWorker()
    }
    private func monitorMemoryPressureIfNeeded() {
        guard pressureMonitor == nil else { return }
        pressureMonitor = LocalModelMemoryPressureMonitor { [weak self] elevated in
            Task { await self?.memoryPressureChanged(elevated: elevated) }
        }
    }
    public func delete(_ model: LocalASRID) async throws {
        guard activeModel != model else { throw AudioFailure.message("本段识别结束后可删除模型") }
        if worker?.id == model {
            worker?.stop()
            worker = nil
        }
        try await library.delete(model)
    }
    public func availability(_ id: LocalASRID) async -> SpeechAvailability {
        if id == .apple { return await AppleSpeechService.availability() }
        let status = await library.status(id)
        let ready = status.installed && FileManager.default.isExecutableFile(atPath:
            helpers.appending(path: id.sherpaRuntime ? "SaytileSherpa" : "SaytileModelWorker").path)
        return .init(supported: true, installed: ready, message: ready ? id.title : "\(id.title) · 需要准备模型")
    }
    fileprivate func recognize(_ id: LocalASRID, audio: AsyncStream<Data>, ingress: LocalCandidateIngress, recordingID: UUID) async throws -> Bool {
        monitorMemoryPressureIfNeeded()
        let token = UUID()
        guard waiting.count < 8 else { throw AudioFailure.message("前段识别仍在进行，原音可重新识别") }
        waiting.append(token)
        FixturePerformanceTrace.record("asr.queued", recordingID: recordingID)
        defer { waiting.removeAll { $0 == token } }
        while activeModel != nil || waiting.first != token { try await Task.sleep(for: .milliseconds(20)) }
        try Task.checkCancellation()
        activeModel = id
        FixturePerformanceTrace.record("asr.admitted", recordingID: recordingID)
        cancelIdleRelease()
        defer { finishedRecognition() }
        do {
            let fresh = worker?.id != id || worker?.process.isRunning != true
            do {
                FixturePerformanceTrace.record("asr.validationStarted", recordingID: recordingID)
                let directory = try await validatedDirectory(id)
                FixturePerformanceTrace.record("asr.assetsReady", recordingID: recordingID)
                try Task.checkCancellation()
                if fresh {
                    worker?.stop()
                    let stride = chunkFrames ?? (id == .qwen ? 8_000 : 19_200)
                    FixturePerformanceTrace.record("asr.workerLaunching", recordingID: recordingID)
                    worker = try ModelWorker(id: id, directory: directory, helpers: helpers, stride: stride,
                                             observe: probeObserver)
                }
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                throw LocalASREngineUnavailable(reason: error.localizedDescription)
            }
            guard let current = worker else { throw LocalASREngineUnavailable(reason: "本机识别进程未启动") }
            return try await withTaskCancellationHandler {
                let sender = Task.detached {
                    var framesSent = 0
                    for await frame in audio {
                        try Task.checkCancellation()
                        if !frame.isEmpty {
                            let start = FixturePerformanceTrace.enabled ? ProcessInfo.processInfo.systemUptime : 0
                            try current.write(frame)
                            framesSent += frame.count / 2
                            FixturePerformanceTrace.record("asr.pipeWritten", recordingID: recordingID, frames: framesSent, since: start)
                        }
                    }
                    try Task.checkCancellation()
                    try current.write(Data())
                }
                defer { sender.cancel() }
                do {
                    var ready = !fresh, lastFrames = 0
                    var liveText = LocalLiveText(model: id, previewPolicy: .provisional)
                    var qwenPrefix = QwenPrefixConfirmation()
                    for try await event in current.events {
                        try Task.checkCancellation()
                        if event.kind == "ready" && !ready {
                            FixturePerformanceTrace.record("asr.workerReady", recordingID: recordingID)
                            ready = true; continue
                        }
                        guard ready, ["partial", "final"].contains(event.kind), event.frames >= lastFrames else {
                            throw LocalASREngineUnavailable(reason: "本机识别事件顺序异常")
                        }
                        lastFrames = event.frames
                        let final = event.kind == "final"
                        FixturePerformanceTrace.record("asr.rawReceived", recordingID: recordingID, frames: event.frames, decision: event.kind)
                        let confirmationStart = FixturePerformanceTrace.enabled ? ProcessInfo.processInfo.systemUptime : 0
                        // Even a visually withheld spelling must break acoustic
                        // agreement. Never count only the previews we chose to show.
                        let confirmed = id == .qwen && !final
                            ? qwenPrefix.accept(event.text, frames: event.frames) : nil
                        let stable = event.text.isEmpty ? nil : liveText.accept(event.text, final: final)
                        FixturePerformanceTrace.record("preview.decided", recordingID: recordingID, frames: event.frames,
                            since: confirmationStart, decision: stable == nil ? "withheld" : (final ? "final" : "preview"))
                        if let stable {
                            try await ingress.receive(.init(text: liveText.presentation, stableUTF16Length: confirmed ?? stable,
                                audioEndSeconds: Double(event.frames) / 16_000, timingGranularity: "utterance", isComplete: final))
                        } else if id == .qwen, !final, !event.text.isEmpty {
                            // Record contrary evidence without repainting a transient
                            // tail. Store now revokes the older dispatch proof.
                            try await ingress.receive(.init(text: event.text, stableUTF16Length: 0,
                                audioEndSeconds: Double(event.frames) / 16_000), publish: false)
                        }
                        if final {
                            try await sender.value
                            // Empty EOS is a completed decoder operation, not a
                            // completed transcript or proof of silence. Retain
                            // this healthy worker and report the distinct result.
                            return !event.text.isEmpty
                        }
                    }
                    throw ProviderFailure.incomplete
                } catch { current.stop(); throw error }
            } onCancel: { current.stop() }
        } catch { worker?.stop(); worker = nil; throw error }
    }
}

/// A rolling batch decoder can replace a large prefix on a transient pass.
/// Keep that pass off the panel until supported by a later hypothesis. The
/// preview is always an exact prefix of the current raw hypothesis. Only the cache-aware
/// Nemotron decoder appends irrevocable token IDs during a stream.
struct LocalLiveText {
    /// `confirmed` preserves the 0.22 reading gate for paired candidate replay.
    /// `provisional` is display-only: rolling hypotheses still grant zero UTF-16
    /// dispatch length here. Qwen phrase confirmation is an independent evidence
    /// boundary; Store ownership and target checks still govern every write.
    enum PreviewPolicy { case confirmed, provisional }
    let model: LocalASRID
    let previewPolicy: PreviewPolicy
    private(set) var previous = ""
    private(set) var presentation = ""
    private var readingPrefix = ""
    private var withheld: String?
    private var unconfirmedTail: String?
    private var recentPreviews: [[Character]] = []
    private var deferredOldWord = false
    init(model: LocalASRID, previewPolicy: PreviewPolicy = .confirmed) {
        self.model = model; self.previewPolicy = previewPolicy
    }
    mutating func accept(_ text: String, final: Bool) -> Int? {
        if final {
            presentation = text
            return text.utf16.count
        }
        // A previously settled, tiny Chinese spelling change with at most four
        // new characters gets one observation to settle. Never chain this hold:
        // the very next whole hypothesis is eligible, even if it disagrees.
        // First words, substantial fresh speech and critical tokens bypass it.
        let resumeOldWord = deferredOldWord
        deferredOldWord = false
        if model == .qwen, previewPolicy == .provisional {
            let current = Self.previewLetters(text)
            defer {
                recentPreviews.append(current)
                if recentPreviews.count > 4 { recentPreviews.removeFirst() }
            }
            if !resumeOldWord, Self.briefOldWordRevision(previous: Self.previewLetters(previous),
                current: current, history: recentPreviews) {
                deferredOldWord = true
                return nil
            }
        }
        let common = RecognitionUTF16.commonPrefix([previous, text])
        if model == .qwen || model == .qwenLarge {
            if !resumeOldWord, let correction = Self.tailOnlyCorrection(previous: previous, text: text),
               unconfirmedTail != correction {
                // A single unchanged-length tail spelling is not new speech.
                // Keep the last observed words until this correction is repeated
                // or fresh speech arrives. EOS always bypasses this preview gate.
                unconfirmedTail = correction
                return nil
            }
            unconfirmedTail = nil
            if previewPolicy == .confirmed {
            // The zh decoder can change the script of the whole hypothesis mid-utterance.
            // Compare scripts only for preview ownership. Publish the original model string.
            let matches = RecognitionUTF16.hasExactPrefix(text, prefix: readingPrefix)
            if !matches, let reference = readingPrefix.applyingTransform(StringTransform("Traditional-Simplified"), reverse: false),
               let candidate = text.applyingTransform(StringTransform("Traditional-Simplified"), reverse: false),
               candidate.hasPrefix(reference), !reference.isEmpty {
                readingPrefix = String(text.prefix(readingPrefix.count))
            } else if !matches, let mapped = Self.formattedPrefix(readingPrefix, in: text) {
                // The decoder can restyle an earlier English phrase on every pass
                // while correctly extending the tail. Compare only the protected
                // preview prefix. Never synthesize display text or grant dispatch.
                readingPrefix = mapped
            } else if !matches {
                // A decoder may permanently change “二十九岁” to “29岁”. Suppressing
                // every later hypothesis would freeze the preview until end of speech.
                // Require two concordant passes. For a change deep in a long
                // preview, the rest of the already visible words must still align.
                let prior = withheld
                withheld = text
                guard let prior else { return nil }
                if let prefix = Self.confirmedReadingPrefix(previous: previous, prior: prior, text: text, unchanged: common.count)
                    ?? Self.locallyConfirmedPrefix(previous: previous, prior: prior, text: text)
                    ?? Self.confirmedLatinSpacing(previous: previous, prior: prior, text: text) {
                    readingPrefix = prefix
                } else { return nil }
            } else if common.count > 8 {
                let supported = String(common.dropLast(8))
                if supported.utf16.count > readingPrefix.utf16.count { readingPrefix = supported }
            }
            withheld = nil
            }
        }
        // The rolling decoder ends almost every intermediate hypothesis with a
        // full stop, including on the first word. Reveal the words immediately.
        // Internal punctuation and the eventual verbatim final are preserved.
        if (model == .qwen || model == .qwenLarge),
           text.last == "。", text.count > 1, !previous.hasPrefix(text) {
            presentation = String(text.dropLast())
        } else {
            presentation = text
        }
        previous = text
        return model == .nemotron ? String(common.dropLast()).utf16.count : 0
    }

    private static func previewLetters(_ text: String) -> [Character] {
        Array(text.lowercased().filter { $0.isLetter || $0.isNumber })
    }
    private static func briefOldWordRevision(previous: [Character], current: [Character], history: [[Character]]) -> Bool {
        guard history.count == 4, previous.count >= 20,
              current.count >= previous.count, current.count - previous.count <= 4 else { return false }
        let changes = previous.indices.filter { previous[$0] != current[$0] }
        guard let first = changes.first, let last = changes.last, first >= 3, last - first <= 2 else { return false }
        func ordinary(_ c: Character) -> Bool {
            c.unicodeScalars.count == 1 && c.unicodeScalars.allSatisfy { (0x3400...0x9FFF).contains($0.value) }
                && !c.isNumber && !"一二三四五六七八九十百千万萬亿億零〇两兩".contains(c) && !protectsBoundary(c)
        }
        return (previous[first...last] + current[first...last]).allSatisfy(ordinary)
            && history.allSatisfy { $0.count > last && $0[first...last].elementsEqual(previous[first...last]) }
    }

    private static func tailOnlyCorrection(previous: String, text: String) -> String? {
        let old = Array(previous.filter { $0.isLetter || $0.isNumber })
        let current = Array(text.filter { $0.isLetter || $0.isNumber })
        guard old.count >= 12, old.count == current.count else { return nil }
        let changed = old.indices.filter { old[$0] != current[$0] }
        guard let first = changed.first, let last = changed.last,
              first >= max(8, old.count - 8), last - first < 3 else { return nil }
        func ordinaryHan(_ c: Character) -> Bool {
            c.unicodeScalars.count == 1 && c.unicodeScalars.allSatisfy { (0x3400...0x9FFF).contains($0.value) }
                && !protectsBoundary(c)
        }
        guard changed.allSatisfy({ ordinaryHan(old[$0]) && ordinaryHan(current[$0]) }) else { return nil }
        // Comparison only: the actual displayed string still comes from the
        // current raw hypothesis, after all existing ownership checks below.
        return String(current)
    }

    private static func confirmedReadingPrefix(previous: String, prior: String, text: String, unchanged: Int) -> String? {
        let supported = RecognitionUTF16.commonPrefix([prior, text])
        guard text.count >= previous.count,
              supported.count >= max(unchanged + 4, min(previous.count, 12)) else { return nil }
        if previous.count - unchanged <= 24 {
            let oldTail = Array(previous.dropFirst(unchanged))
            let newTail = String(supported.dropFirst(unchanged).prefix(48))
            guard oldTail.count >= 4, (0...(oldTail.count - 4)).contains(where: { i in
                let anchor = oldTail[i..<(i + 4)]
                return anchor.allSatisfy { $0.isLetter || $0.isNumber } && newTail.contains(String(anchor))
            }) else { return nil }
        } else if !Self.hasLocalizedCorrection(from: previous, to: supported) { return nil }
        return String(supported.dropLast(8))
    }

    // In mixed speech Qwen may split an earlier compound ("smartphone" to
    // "smart phone") while appending Chinese words. Spaces can change meaning.
    // Accept the complete current hypothesis only after a second observation
    // confirms the changed boundary, the entire old text, and fresh speech.
    private static func confirmedLatinSpacing(previous: String, prior: String, text: String) -> String? {
        func latin(_ c: Character) -> Bool {
            guard let n = c.asciiValue else { return false }
            return (65...90).contains(n) || (97...122).contains(n)
        }
        func units(_ value: String) -> [(Character, String.Index)] {
            var result: [(Character, String.Index)] = []
            for i in value.indices {
                let c = value[i], next = value.index(after: i)
                if c == "。", next == value.endIndex { continue }
                if c == "，", i > value.startIndex, next < value.endIndex {
                    let before = value[value.index(before: i)], after = value[next]
                    if before.isLetter, after.isLetter, !protectsBoundary(before), !protectsBoundary(after) { continue }
                }
                result.append((latin(c) ? Character(c.lowercased()) : c, next))
            }
            return result
        }
        let original = units(previous).map(\.0), proposal = units(text)
        let current = proposal.map(\.0)
        let i = zip(original, current).prefix(while: { $0 == $1 }).count
        guard i >= 2, i < min(original.count, current.count), original[..<i].suffix(2).allSatisfy(latin) else { return nil }
        let inserting = current[i] == " "
        guard inserting != (original[i] == " ") else { return nil }
        var corrected = original
        if inserting { corrected.insert(" ", at: i) } else { corrected.remove(at: i) }
        let after = i + (inserting ? 1 : 0)
        let right = corrected[after...].prefix(while: latin)
        let following = corrected.dropFirst(after + right.count)
        guard right.count >= 2, following.count >= 6, following.prefix(6).allSatisfy({ $0.isLetter }),
              current.starts(with: corrected) else { return nil }
        let observed = units(prior).map(\.0)
        guard observed.starts(with: corrected),
              observed.dropFirst(corrected.count).contains(where: { $0.isLetter || $0.isNumber }),
              current.dropFirst(corrected.count).contains(where: { $0.isLetter || $0.isNumber }) else { return nil }
        return String(text[..<proposal[corrected.count - 9].1])
    }

    // Changing a boundary next to a number or negative can change the meaning
    // even when the surrounding spoken words are unchanged.
    private static func protectsBoundary(_ c: Character?) -> Bool {
        guard let c else { return false }
        return c.isNumber || "不没無无未非否别別勿莫甭负負".contains(c)
    }

    /// Two growing passes can agree about a local correction while disagreeing
    /// at an earlier word that the current pass leaves exactly as last displayed.
    /// Only accept a whole current hypothesis, never splice corrected words.
    private static func locallyConfirmedPrefix(previous: String, prior: String, text: String) -> String? {
        // Ignore Chinese phrase punctuation for alignment only. Preserve number
        // punctuation, word boundaries, signs and all non-Han lexical units.
        func units(_ raw: String) -> [(Character, String.Index)] {
            var result: [(Character, String.Index)] = []
            var i = raw.startIndex
            while i < raw.endIndex {
                let c = raw[i], next = raw.index(after: i)
                let before = i == raw.startIndex ? nil : raw[raw.index(before: i)]
                let after = next == raw.endIndex ? nil : raw[next]
                if c == "—", after == "—", let before, before.isLetter, !protectsBoundary(before) {
                    let end = raw.index(after: next)
                    if end < raw.endIndex, raw[end].isLetter, !protectsBoundary(raw[end]) { i = end; continue }
                }
                if !("。，、".contains(c) && !protectsBoundary(before) && !protectsBoundary(after)) {
                    result.append((c, next))
                }
                i = next
            }
            return result
        }
        let old = units(previous).map(\.0), observed = units(prior).map(\.0), mapped = units(text)
        let current = mapped.map(\.0)
        guard old.count >= 20, current.count >= old.count + 2,
              observed.count > old.count, current.count >= observed.count else { return nil }
        let changes = old.indices.filter { old[$0] != current[$0] }
        guard let first = changes.first, let last = changes.last else { return nil }
        func ordinaryHan(_ c: Character) -> Bool {
            c.unicodeScalars.count == 1 && c.unicodeScalars.allSatisfy { (0x3400...0x9FFF).contains($0.value) }
                && !protectsBoundary(c)
        }
        guard changes.allSatisfy({ ordinaryHan(old[$0]) && ordinaryHan(current[$0]) }) else { return nil }
        // A shared space or an ellipsis does not substantiate a new word.
        let extensionAgreement = zip(current[old.count...], observed[old.count...]).prefix { $0 == $1 }
        guard extensionAgreement.contains(where: { $0.0.isLetter || $0.0.isNumber }) else { return nil }

        let anchorEnd: Int
        let clusters = changes.reduce(into: [[Int]]()) { groups, index in
            if let end = groups.last?.last, index == end + 1 { groups[groups.count - 1].append(index) }
            else { groups.append([index]) }
        }
        if clusters.count == 2, clusters.allSatisfy({ $0.count <= 3 }), first >= 12,
           clusters[1][0] - clusters[0].last! >= 4, old.count - last > 12 {
            // Two independent earlier Chinese words can settle on the same pass.
            // Both raw observations must corroborate the ENTIRE visible lexical
            // span, not just a shared phrase. Reject numbers, negatives, changed
            // word lengths and broad rewrites above; publish only the raw model
            // hypothesis. Final text and external dispatch remain independent.
            guard observed.prefix(old.count).elementsEqual(current.prefix(old.count)) else { return nil }
            anchorEnd = old.count
        } else if last - first < 4, first >= 3, old.count - last > 12 {
            // A different, earlier spelling on the prior pass must not invalidate
            // the local evidence when the current pass restores the displayed words.
            guard current[(first - 3)..<old.count].elementsEqual(observed[(first - 3)..<old.count]) else { return nil }
            let earlier = (0..<(first - 3)).filter { observed[$0] != current[$0] }
            if let a = earlier.first, let b = earlier.last {
                guard b - a < 4, earlier.allSatisfy({ ordinaryHan(observed[$0]) && ordinaryHan(current[$0]) }) else { return nil }
            } else if !current.starts(with: observed) {
                // Without an independent earlier change, this fallback admits
                // only a whole corroborated lexical hypothesis and its exact
                // extension. New speech must not invalidate already matching
                // words, but a changed word in the observed tail still does.
                return nil
            }
            anchorEnd = old.count
        } else {
            // A short unfinished word at the old right edge can be corrected at
            // the same time as one older word. Both passes must corroborate the
            // *whole* corrected old span, then grow beyond it with real words.
            let tail = changes.drop { $0 - first < 4 }
            guard let tailStart = tail.first, tailStart >= old.count - 3,
                  let earlyEnd = changes.last(where: { $0 < tailStart }), tailStart - earlyEnd > 12,
                  observed.prefix(old.count).elementsEqual(current.prefix(old.count)),
                  current[observed.count...].contains(where: { $0.isLetter || $0.isNumber }) else { return nil }
            anchorEnd = tailStart
        }
        let offset = anchorEnd - 12, anchor = old[offset..<anchorEnd]
        func unique(_ words: [Character]) -> Bool {
            !(0...(words.count - anchor.count)).contains { i in
                i != offset && words[i...].starts(with: anchor)
            }
        }
        guard unique(old), unique(observed), unique(current) else { return nil }
        // Protect only material already visible and corroborated on both passes.
        return String(text[..<mapped[old.count - 9].1])
    }

    /// Map common ASR typography to the exact raw end index in the new pass.
    /// Keep word boundaries, signs, numbers, and lexical changes distinct.
    private static func formattedPrefix(_ raw: String, in candidate: String) -> String? {
        guard !raw.isEmpty else { return nil }
        func latin(_ c: Character?) -> Bool {
            guard let n = c?.asciiValue else { return false }
            return (65...90).contains(n) || (97...122).contains(n)
        }
        enum Unit: Equatable { case literal(Character), pause }
        func units(_ text: String, alignPauses: Bool) -> [(Unit, String.Index)] {
            var out: [(Unit, String.Index)] = []
            var i = text.startIndex
            while i < text.endIndex {
                let c = text[i], next = text.index(after: i)
                var end = next
                defer { i = end }
                let before = i == text.startIndex ? nil : text[text.index(before: i)]
                let after = next == text.endIndex ? nil : text[next]
                let protected = protectsBoundary(before) || protectsBoundary(after)
                if !alignPauses, c == "，", !protected { continue }
                let mapped: Unit
                if alignPauses, !protected, c == "。" || c == "，" || c == "、" {
                    mapped = .pause
                } else if alignPauses, c == "—", after == "—", before?.isLetter == true,
                          !protected, text.index(after: next) < text.endIndex,
                          text[text.index(after: next)].isLetter, !protectsBoundary(text[text.index(after: next)]) {
                    // A Chinese double dash can mark an apposition. A minus,
                    // single dash, numeric range or moved boundary stays distinct.
                    end = text.index(after: next)
                    mapped = .pause
                } else if c == "-", latin(before), latin(after) { mapped = .literal(" ") }
                else if latin(c) { mapped = .literal(Character(c.lowercased())) }
                else { mapped = .literal(c) }
                out.append((mapped, end))
            }
            return out
        }
        // First preserve the existing optional-comma comparison. If that fails,
        // require an actual phrase boundary on both sides at the same position.
        for alignPauses in [false, true] {
            let prefix = units(raw, alignPauses: alignPauses), update = units(candidate, alignPauses: alignPauses)
            if !prefix.isEmpty, update.count >= prefix.count,
               zip(prefix, update).allSatisfy({ $0.0.0 == $0.1.0 }) {
                return String(candidate[..<update[prefix.count - 1].1])
            }
        }
        return nil
    }

    private static func hasLocalizedCorrection(from visible: String, to confirmed: String) -> Bool {
        // Ignore sentence punctuation for alignment only. Preserve digits, signs
        // and the raw model string used for display. No partial becomes stable.
        let punctuation = CharacterSet(charactersIn: "，。！？、；：,—!?;:“”「」").union(.whitespacesAndNewlines)
        func words(_ text: String) -> [Character] {
            text.filter { !$0.unicodeScalars.allSatisfy(punctuation.contains) }
        }
        let old = words(visible), new = words(confirmed)
        let common = zip(old, new).prefix(while: { $0 == $1 }).count
        let oldTail = old.dropFirst(common), newTail = new.dropFirst(common)
        if oldTail.isEmpty { return old.count >= 12 }
        for removed in 0...min(4, oldTail.count) {
            let suffix = oldTail.dropFirst(removed)
            guard suffix.count >= 12 else { break }
            for inserted in 0...min(4, newTail.count) where newTail.dropFirst(inserted).starts(with: suffix) {
                return true
            }
        }
        return false
    }
}

private final class ModelRecognitionSession: RecognitionSession, @unchecked Sendable {
    let recordingID: UUID
    private let state = RecognitionSessionCompletion()
    private let channel: AsyncStream<Data>.Continuation
    private let task: Task<Void, Never>
    private let bufferLock = NSLock()
    private var pendingPCM = Data()
    private let timeout: Duration
    var isComplete: Bool { state.isComplete }
    init(model: LocalASRID, service: LocalASRService, store: SaytileStore, ticket: RecognitionTicket, review: LocalTextReview?, onUnavailable: (@Sendable (LocalASRID) -> Void)?) {
        recordingID = ticket.recordingID
        timeout = model.capability == .batch ? .seconds(180) : .seconds(60)
        let (audio, sender) = AsyncStream<Data>.makeStream(bufferingPolicy: .bufferingOldest(600))
        channel = sender
        let state = state
        task = Task {
            defer { state.finish() }
            let ingress = LocalCandidateIngress(store: store, ticket: ticket, model: model, review: review)
            do {
                try await ingress.start()
                if try await service.recognize(model, audio: audio, ingress: ingress, recordingID: ticket.recordingID) {
                    try await ingress.finish()
                } else {
                    await ingress.finishWithoutTranscript()
                }
            }
            catch {
                if error is LocalASREngineUnavailable && !Task.isCancelled { onUnavailable?(model) }
                await ingress.fail("本机识别未完成，原音可重试。\(error.localizedDescription)")
            }
        }
    }
    func append(_ data: Data) {
        // VAD emits short frames. Bound backlog by audio duration instead of
        // allowing scheduler contention to exhaust hundreds of tiny slots.
        let overflow = bufferLock.withLock {
            var offset = data.startIndex
            while offset < data.endIndex {
                let count = min(3_200 - pendingPCM.count, data.endIndex - offset)
                pendingPCM.append(data[offset..<(offset + count)])
                offset += count
                if pendingPCM.count == 3_200 {
                    let result = channel.yield(pendingPCM)
                    pendingPCM.removeAll(keepingCapacity: true)
                    if case .dropped = result { return true }
                }
            }
            return false
        }
        if overflow { cancel() }
    }
    func finish() {
        let overflow = bufferLock.withLock {
            defer { pendingPCM.removeAll(); channel.finish() }
            if !pendingPCM.isEmpty, case .dropped = channel.yield(pendingPCM) { return true }
            return false
        }
        if overflow { task.cancel() }
        let active = task, deadline = timeout
        state.watch(Task { do { try await Task.sleep(for: deadline) } catch { return }; active.cancel() })
    }
    func cancel() { channel.finish(); task.cancel() }
    func wait() async { await task.value }
}
