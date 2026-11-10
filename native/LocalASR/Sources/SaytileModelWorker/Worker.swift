import Darwin
import Foundation
import FluidAudio
import NemotronStreamingASR
import Qwen3ASR

// Private pipe from the signed Saytile process. PCM16LE mono, 16 kHz.
// A zero-length frame ends one utterance. EOF releases the model.
enum WorkerError: Error { case invalidFrame, truncated, configuration }
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
func publish(_ text: String, kind: String, frames: Int) throws {
    let event: [String: Any] = ["kind": kind, "text": text, "frames": frames]
    var line = try JSONSerialization.data(withJSONObject: event)
    line.append(10)
    try FileHandle.standardOutput.write(contentsOf: line)
}

@main struct Worker {
    static func main() async throws {
        let args = CommandLine.arguments
        guard args.count == 4, let stride = Int(args[3]), (8_000...64_000).contains(stride) else { throw WorkerError.configuration }
        let id = args[1], directory = URL(fileURLWithPath: args[2], isDirectory: true)
        let nemo: NemotronStreamingASRMLXModel?
        let transcribe: (([Float]) async throws -> String)?
        switch id {
        case "nemotron-metal":
            nemo = try await .fromDirectory(directory)
            transcribe = nil
        case "qwen-small", "qwen-large":
            nemo = nil
            let model = try await Qwen3ASRModel.fromPretrained(modelId: id == "qwen-small"
                ? "aufklarer/Qwen3-ASR-0.6B-MLX-4bit" : "aufklarer/Qwen3-ASR-1.7B-MLX-4bit",
                cacheDir: directory, offlineMode: true)
            transcribe = { try model.transcribeThrowing(audio: $0, options: .init(language: "zh", longInputThresholdSeconds: .infinity)) }
        case "paraformer":
            nemo = nil
            let model = ParaformerManager(models: try ParaformerModels.load(from: directory, precision: .int8))
            transcribe = { try await model.transcribe(audio: $0) }
        case "sensevoice":
            nemo = nil
            let model = SenseVoiceManager(models: try SenseVoiceModels.load(from: directory, precision: .int8))
            transcribe = { try await model.transcribe(audio: $0) }
        default: throw WorkerError.configuration
        }
        try publish("", kind: "ready", frames: 0)
        var stream = try nemo?.createSession(language: "zh")
        // Decode a short first window on the same warmed model. After a
        // revision, request one earlier confirmation; the normal growth cadence
        // and full final decode stay unchanged.
        let firstStride = id == "qwen-small" ? min(stride, 12_800) : stride
        var samples: [Float] = [], prefix = "", last = "", frames = 0, next = firstStride
        while let header = try bytes(4, allowEOF: true) {
            let size = Int(header.withUnsafeBytes { $0.loadUnaligned(as: UInt32.self).littleEndian })
            guard size <= 65_536 && size.isMultiple(of: 2) else { throw WorkerError.invalidFrame }
            let end = size == 0
            let chunk = try bytes(size)!.withUnsafeBytes { buffer in
                buffer.bindMemory(to: Int16.self).map { Float(Int16(littleEndian: $0)) / 32768 }
            }
            frames += chunk.count
            var update: String?
            if let stream {
                let results = try end ? stream.finalize() : stream.pushAudio(chunk)
                update = results.last?.text
            } else if let transcribe {
                samples.append(contentsOf: chunk)
                // Upstream batch encoders have finite input windows. Bound history
                // without retaining or retranscribing all preceding utterances.
                if end || samples.count >= 16_000 * 24 || (id == "qwen-small" && samples.count >= next) {
                    let tail = samples.isEmpty ? "" : try await transcribe(samples)
                    update = prefix + tail
                    if samples.count >= 16_000 * 24 {
                        prefix += tail
                        samples.removeAll(keepingCapacity: true)
                        next = stride
                    } else {
                        let rollback = !last.isEmpty && !(update ?? "").hasPrefix(String(last.dropLast(2)))
                        next = samples.count + (rollback ? firstStride : stride)
                    }
                }
            }
            if end {
                try publish(update ?? last, kind: "final", frames: frames)
                stream = try nemo?.createSession(language: "zh")
                samples.removeAll(keepingCapacity: true)
                prefix = ""; last = ""; next = firstStride; frames = 0
            } else if let update, !update.isEmpty, update != last, id == "nemotron-metal" || id == "qwen-small" {
                last = update
                try publish(update, kind: "partial", frames: frames)
            }
        }
    }
}
