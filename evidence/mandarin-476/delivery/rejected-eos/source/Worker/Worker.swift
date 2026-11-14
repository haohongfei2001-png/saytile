import Darwin
import Foundation
import FluidAudio
import MLX
import NemotronStreamingASR
import Qwen3ASR

// Private pipe from the signed Saytile process. PCM16LE mono, 16 kHz.
// A zero-length frame ends one utterance. EOF releases the model.
func bytes(_ count: Int, allowEOF: Bool = false) throws -> Data? {
    var data = Data()
    while data.count < count {
        let part = try FileHandle.standardInput.read(upToCount: count - data.count) ?? Data()
        if part.isEmpty {
            if allowEOF && data.isEmpty { return nil }
            throw WorkerError.truncated
        }
        data.append(part)
    }
    return data
}

func publish(_ text: String, kind: String, frames: Int, decodes: [[String: Any]] = [], diagnosticFinalVerified: Bool? = nil) throws {
    var event: [String: Any] = ["kind": kind, "text": text, "frames": frames]
    if !decodes.isEmpty { event["decodes"] = decodes }
    if let diagnosticFinalVerified { event["diagnosticFinalVerified"] = diagnosticFinalVerified }
    var line = try JSONSerialization.data(withJSONObject: event)
    line.append(10)
    try FileHandle.standardOutput.write(contentsOf: line)
}

@main struct Worker {
    static func main() async throws {
        let args = CommandLine.arguments
        guard args.count == 4, let stride = Int(args[3]), (8_000...64_000).contains(stride) else { throw WorkerError.configuration }
        let id = args[1], directory = URL(fileURLWithPath: args[2], isDirectory: true)
        let rollingQwen = id == "qwen-small" || id == "qwen-large"
        let nemo: NemotronStreamingASRMLXModel?
        let transcribe: (([Float], Bool) async throws -> String)?
        var verifiedTokens = 0
        switch id {
        case "nemotron-metal":
            nemo = try await .fromDirectory(directory)
            transcribe = nil
        case "qwen-small", "qwen-large":
            // Keep reusable Metal allocations bounded between incremental decodes.
            MLX.Memory.cacheLimit = 32 * 1024 * 1024
            nemo = nil
            let model = try await Qwen3ASRModel.fromPretrained(modelId: id == "qwen-small"
                ? "aufklarer/Qwen3-ASR-0.6B-MLX-4bit" : "aufklarer/Qwen3-ASR-1.7B-MLX-4bit",
                cacheDir: directory, offlineMode: true)
            // The small model translated whole English clauses in Mandarin speech
            // when forced to Chinese. Leave it free to transcribe the spoken language.
            let language = id == "qwen-small" ? nil : "Chinese"
            let options = Qwen3DecodingOptions(language: language, longInputThresholdSeconds: .infinity)
            transcribe = { samples, verifyingPreview in
                var decoding = options
                decoding.verifiesPreviewTokens = verifyingPreview
                if !verifyingPreview { model.clearPreviewTokens() }
                let text = try model.transcribeThrowing(audio: samples, options: decoding)
                verifiedTokens = model.verifiedPreviewTokenCount
                return text
            }
        case "paraformer":
            nemo = nil
            let model = ParaformerManager(models: try ParaformerModels.load(from: directory, precision: .int8))
            transcribe = { samples, _ in try await model.transcribe(audio: samples) }
        case "sensevoice":
            nemo = nil
            let model = SenseVoiceManager(models: try SenseVoiceModels.load(from: directory, precision: .int8))
            transcribe = { samples, _ in try await model.transcribe(audio: samples) }
        default: throw WorkerError.configuration
        }
        try publish("", kind: "ready", frames: 0)
        var stream = try nemo?.createSession(language: "zh")
        // Give the first hypothesis 800 ms of acoustic context even when later
        // previews are requested more frequently.
        let firstStride: Int
        switch id {
        case "qwen-small": firstStride = 12_800
        case "qwen-large": firstStride = min(stride, 12_800)
        default: firstStride = stride
        }
        // Coalesce up to the previous 3.6 s of new PCM under heavy backlog.
        // More frequent previews should consume spare time, not delay EOS.
        let maxPreviewBacklog = max(57_600, 3 * stride)
        let traceDecodes = id == "qwen-small" && ProcessInfo.processInfo.environment["SAYTILE_WORKER_TIMING"] == "1"
        var decodes: [[String: Any]] = []
        // Local capture segments contain up to 30 s of active frames plus 1 s
        // of pre-roll. Keep that whole segment available for the EOS decode.
        let windowLimit = 16_000 * (rollingQwen ? 32 : 24)
        var samples: [Float] = [], prefix = "", last = "", frames = 0, next = firstStride
        // Only original scalar-greedy output can be an exact-PCM final.
        // Block-verified previews may differ numerically and always need a fresh EOS.
        var exactPreview: (frames: Int, text: String)?
        var input = PCMFrameReader(descriptor: STDIN_FILENO)
        func nextFrame() throws -> Data? {
            if id == "qwen-small" { return try input.next() }
            guard let header = try bytes(4, allowEOF: true) else { return nil }
            let size = Int(header.withUnsafeBytes { $0.loadUnaligned(as: UInt32.self).littleEndian })
            guard size <= 65_536, size.isMultiple(of: 2) else { throw WorkerError.invalidFrame }
            return try bytes(size)
        }
        while let payload = try nextFrame() {
            let end = payload.isEmpty
            let chunk = payload.withUnsafeBytes { buffer in
                buffer.bindMemory(to: Int16.self).map { Float(Int16(littleEndian: $0)) / 32768 }
            }
            frames += chunk.count
            var update: String?
            var diagnosticFinalVerified = false
            if let stream {
                let results = try end ? stream.finalize() : stream.pushAudio(chunk)
                update = results.last?.text
            } else if end, let exactPreview, exactPreview.frames == frames {
                update = exactPreview.text
            } else if let transcribe {
                samples.append(contentsOf: chunk)
                // Upstream batch encoders have finite input windows. Bound history
                // without retaining or retranscribing all preceding utterances.
                if end || samples.count >= windowLimit || (rollingQwen && samples.count >= next) {
                    // Once the first real result is visible, drain complete PCM
                    // packets that arrived while MLX was decoding before asking
                    // for the next preview. Always decode the window boundary
                    // and EOS. Keep all samples, including partially read packets.
                    if id == "qwen-small", !end, !last.isEmpty, samples.count < windowLimit,
                       samples.count - next < maxPreviewBacklog, try input.hasNextFrameNow() { continue }
                    let started = traceDecodes ? ProcessInfo.processInfo.systemUptime : 0
                    // ISOLATED EXPERIMENT ONLY: re-encode the full current PCM
                    // at EOS, then validate previous token IDs against it. Never
                    // return previous preview text, and keep the 32 s boundary
                    // on the original greedy path. No-draft/short input falls back.
                    let verifyingPreview = id == "qwen-small" && !last.isEmpty
                        && samples.count >= 48_000 && samples.count < windowLimit
                    diagnosticFinalVerified = end && verifyingPreview
                    let tail = samples.isEmpty ? "" : try await transcribe(samples, verifyingPreview)
                    let decoded = prefix + tail
                    update = decoded
                    if id == "qwen-small" && !end { exactPreview = verifyingPreview ? nil : (frames, decoded) }
                    if traceDecodes {
                        decodes.append(["startUptime": started, "endUptime": ProcessInfo.processInfo.systemUptime,
                                        "frames": frames, "final": end, "changed": update != last,
                                        "verifiedPreviewTokens": verifyingPreview ? verifiedTokens : 0,
                                        "diagnosticFinalVerified": diagnosticFinalVerified])
                    }
                    if samples.count >= windowLimit {
                        prefix += tail
                        samples.removeAll(keepingCapacity: true)
                        next = stride
                    } else {
                        let rollback = !last.isEmpty && !(update ?? "").hasPrefix(String(last.dropLast(2)))
                        next = samples.count + (rollback ? min(firstStride, stride) : stride)
                    }
                }
            }
            if end {
                try publish(update ?? last, kind: "final", frames: frames, decodes: decodes,
                            diagnosticFinalVerified: diagnosticFinalVerified)
                decodes.removeAll(keepingCapacity: true)
                exactPreview = nil
                stream = try nemo?.createSession(language: "zh")
                samples.removeAll(keepingCapacity: true)
                prefix = ""; last = ""; next = firstStride; frames = 0
            } else if let update, !update.isEmpty, update != last, id == "nemotron-metal" || rollingQwen {
                last = update
                try publish(update, kind: "partial", frames: frames, decodes: decodes)
                decodes.removeAll(keepingCapacity: true)
            }
        }
    }
}
