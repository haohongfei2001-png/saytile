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
}

public struct WorkerEvent: Decodable, Sendable {
    public let kind: String
    public let text: String
    public let frames: Int
    public let decodes: [WorkerDecodeTiming]?
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

public actor LocalASRService {
    public nonisolated let library: LocalModelLibrary
    private let helpers: URL
    private let chunkFrames: Int?
    private var probeObserver: (@Sendable (WorkerEvent) -> Void)?
    private var waiting: [UUID] = []
    private var activeModel: LocalASRID?
    private var worker: ModelWorker?
    private var idle: Task<Void, Never>?
    public init(root: URL, helpers: URL? = nil, chunkFrames: Int? = nil) {
        library = LocalModelLibrary(root: root)
        self.helpers = helpers ?? Bundle.main.bundleURL.appending(path: "Contents/Helpers")
        self.chunkFrames = chunkFrames
    }
    /// Called only by the isolated fixture probe before it starts its first session.
    public func observeFixtureWorker(_ observe: @escaping @Sendable (WorkerEvent) -> Void) {
        probeObserver = observe
    }

    public func releaseIdle() {
        guard activeModel == nil else { return }
        idle?.cancel()
        worker?.stop()
        worker = nil
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
    fileprivate func recognize(_ id: LocalASRID, audio: AsyncStream<Data>, ingress: LocalCandidateIngress) async throws {
        let token = UUID()
        guard waiting.count < 8 else { throw AudioFailure.message("前段识别仍在进行，原音可重新识别") }
        waiting.append(token)
        defer { waiting.removeAll { $0 == token } }
        while activeModel != nil || waiting.first != token { try await Task.sleep(for: .milliseconds(20)) }
        try Task.checkCancellation()
        activeModel = id
        idle?.cancel()
        defer {
            activeModel = nil
            idle = Task { do { try await Task.sleep(for: .seconds(30)) } catch { return }; releaseIdle() }
        }
        do {
            let fresh = worker?.id != id || worker?.process.isRunning != true
            do {
                let manifest = try LocalModelManifest.load(id)
                let directory = try await library.validated(manifest)
                try Task.checkCancellation()
                if fresh {
                    worker?.stop()
                    let stride = chunkFrames ?? (id == .qwen ? 8_000 : 19_200)
                    worker = try ModelWorker(id: id, directory: directory, helpers: helpers, stride: stride,
                                             observe: probeObserver)
                }
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                throw LocalASREngineUnavailable(reason: error.localizedDescription)
            }
            guard let current = worker else { throw LocalASREngineUnavailable(reason: "本机识别进程未启动") }
            try await withTaskCancellationHandler {
                let sender = Task.detached {
                    for await frame in audio {
                        try Task.checkCancellation()
                        if !frame.isEmpty { try current.write(frame) }
                    }
                    try Task.checkCancellation()
                    try current.write(Data())
                }
                defer { sender.cancel() }
                do {
                    var ready = !fresh, lastFrames = 0
                    var liveText = LocalLiveText(model: id)
                    for try await event in current.events {
                        try Task.checkCancellation()
                        if event.kind == "ready" && !ready { ready = true; continue }
                        guard ready, ["partial", "final"].contains(event.kind), event.frames >= lastFrames else {
                            throw LocalASREngineUnavailable(reason: "本机识别事件顺序异常")
                        }
                        lastFrames = event.frames
                        let final = event.kind == "final"
                        if !event.text.isEmpty, let stable = liveText.accept(event.text, final: final) {
                            try await ingress.receive(.init(text: liveText.presentation, stableUTF16Length: stable,
                                audioEndSeconds: Double(event.frames) / 16_000, timingGranularity: "utterance", isComplete: final))
                        }
                        if final {
                            try await sender.value
                            guard !event.text.isEmpty else { throw ProviderFailure.incomplete }
                            return
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
    let model: LocalASRID
    private(set) var previous = ""
    private(set) var presentation = ""
    private var readingPrefix = ""
    private var withheld: String?
    init(model: LocalASRID) { self.model = model }
    mutating func accept(_ text: String, final: Bool) -> Int? {
        if final {
            presentation = text
            return text.utf16.count
        }
        let common = RecognitionUTF16.commonPrefix([previous, text])
        if model == .qwen || model == .qwenLarge {
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
                    ?? Self.locallyConfirmedPrefix(previous: previous, prior: prior, text: text) {
                    readingPrefix = prefix
                } else { return nil }
            } else if common.count > 8 {
                let supported = String(common.dropLast(8))
                if supported.utf16.count > readingPrefix.utf16.count { readingPrefix = supported }
            }
            withheld = nil
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
        if last - first < 4, first >= 3, old.count - last > 12 {
            // A different, earlier spelling on the prior pass must not invalidate
            // the local evidence when the current pass restores the displayed words.
            guard current[(first - 3)..<old.count].elementsEqual(observed[(first - 3)..<old.count]) else { return nil }
            let earlier = (0..<(first - 3)).filter { observed[$0] != current[$0] }
            if let a = earlier.first, let b = earlier.last {
                guard b - a < 4, earlier.allSatisfy({ ordinaryHan(observed[$0]) && ordinaryHan(current[$0]) }) else { return nil }
            } else if current != observed {
                // Without an independent earlier change, this fallback admits
                // only two whole lexical hypotheses that corroborate one another.
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
                try await service.recognize(model, audio: audio, ingress: ingress)
                try await ingress.finish()
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
