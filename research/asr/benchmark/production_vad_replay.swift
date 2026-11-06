// Research-only boundary probe. Compile in the same module as the UNCHANGED
// Sources/SaytileKit/AudioJournal.swift and the production CAudio target.
// This runs VoiceSegmenter, not CaptureWorker/LiveSpeechSession or hardware.
import Foundation
import CryptoKit

@main
struct ProductionVADReplay {
    static func hash(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    static func pcm(_ file: Data) throws -> Data {
        func word(_ p: Int, _ n: Int) -> Int {
            (0..<n).reduce(0) { $0 | (Int(file[p + $1]) << (8 * $1)) }
        }
        func tag(_ p: Int) -> String { String(decoding: file[p..<(p + 4)], as: UTF8.self) }
        guard file.count >= 44, tag(0) == "RIFF", tag(8) == "WAVE" else {
            throw AudioFailure.message("Expected a RIFF WAV")
        }
        var p = 12, acceptedFormat = false
        var payload: Data?
        while p + 8 <= file.count {
            let kind = tag(p), count = word(p + 4, 4), start = p + 8
            guard count <= file.count - start else { throw AudioFailure.message("Truncated WAV chunk") }
            if kind == "fmt " {
                guard count >= 16, word(start, 2) == 1, word(start + 2, 2) == 1,
                      word(start + 4, 4) == 16_000, word(start + 14, 2) == 16 else {
                    throw AudioFailure.message("Input must already be PCM16 mono 16000 Hz; this probe does not resample")
                }
                acceptedFormat = true
            } else if kind == "data" { payload = Data(file[start..<(start + count)]) }
            p = start + count + count % 2
        }
        guard acceptedFormat, let payload, !payload.isEmpty, payload.count % 2 == 0 else {
            throw AudioFailure.message("Missing format or complete Int16 payload")
        }
        return payload
    }

    static func main() throws {
        let args = Array(CommandLine.arguments.dropFirst())
        guard args.count >= 2 else {
            throw AudioFailure.message("Usage: production-vad-replay INPUT.wav NEW_OUTPUT_DIR [--repeat N] [--active-tail]")
        }
        var repeatCount = 1, activeTail = false, i = 2
        while i < args.count {
            if args[i] == "--repeat", i + 1 < args.count, let n = Int(args[i + 1]), (1...10_000).contains(n) {
                repeatCount = n; i += 2
            } else if args[i] == "--active-tail" { activeTail = true; i += 1 }
            else { throw AudioFailure.message("Unknown or invalid argument: \(args[i])") }
        }
        let inputURL = URL(fileURLWithPath: args[0]).standardizedFileURL
        let outputURL = URL(fileURLWithPath: args[1]).standardizedFileURL
        guard !FileManager.default.fileExists(atPath: outputURL.path) else {
            throw AudioFailure.message("Output directory must be new")
        }
        let file = try Data(contentsOf: inputURL), originalPCM = try pcm(file)
        guard originalPCM.count <= 19_200_000 / repeatCount else {
            throw AudioFailure.message("Boundary probe is limited to ten minutes of PCM")
        }
        var input = Data(); input.reserveCapacity(originalPCM.count * repeatCount)
        for _ in 0..<repeatCount { input.append(originalPCM) }
        try FileManager.default.createDirectory(at: outputURL, withIntermediateDirectories: true)

        let segmenter = try VoiceSegmenter()
        var offset = 0, segmentStart = 0, segmentEnd = 0, postBeginFrames = 0
        var current = Data(), records: [[String: Any]] = []
        var tailAttempted = false, finishAudioBytes = 0, previousEnd = 0
        var omittedBytes = 0, overlapBytes = 0

        func consume(_ events: [VoiceSegmenter.Event], finishing: Bool) throws {
            for event in events {
                switch event {
                case let .begin(preRoll):
                    guard current.isEmpty else { throw AudioFailure.message("Unexpected nested begin") }
                    for frame in preRoll { current.append(frame) }
                    segmentStart = offset - current.count; segmentEnd = offset; postBeginFrames = 0
                case let .audio(data):
                    current.append(data); segmentEnd = offset
                    if finishing { finishAudioBytes += data.count } else { postBeginFrames += 1 }
                case .end:
                    let name = String(format: "segment-%03d.wav", records.count)
                    let exact = segmentStart >= 0 && segmentEnd <= input.count &&
                        input.subdata(in: segmentStart..<segmentEnd) == current
                    var wav = PCMJournal.header(frames: Int64(current.count / 2)); wav.append(current)
                    try wav.write(to: outputURL.appendingPathComponent(name), options: .atomic)
                    omittedBytes += max(0, segmentStart - previousEnd)
                    overlapBytes += max(0, previousEnd - segmentStart)
                    records.append([
                        "index": records.count, "file": name,
                        "source_start_sample": segmentStart / 2, "source_end_sample": segmentEnd / 2,
                        "frames": current.count / 2, "seconds": Double(current.count) / 32_000,
                        "pcm_sha256": hash(current), "exact_input_range_match": exact,
                        "post_begin_frames": postBeginFrames,
                        "end_reason": finishing ? "input_finish" : (postBeginFrames >= 1500 ? "forced_rotation" : "vad_silence")
                    ])
                    previousEnd = segmentEnd; current.removeAll(keepingCapacity: true)
                }
            }
        }

        while offset < input.count {
            let next = min(input.count, offset + 640)
            let block = input.subdata(in: offset..<next); offset = next
            try consume(segmenter.accept(block), finishing: false)
            if activeTail && segmenter.speaking {
                // Stop 43 complete samples into the next 320-sample VAD frame.
                let end = min(input.count, offset + 86)
                if end > offset {
                    let tail = input.subdata(in: offset..<end); offset = end
                    try consume(segmenter.accept(tail), finishing: false)
                }
                tailAttempted = true
                break
            }
        }
        let wasSpeakingAtFinish = segmenter.speaking
        try consume(segmenter.finish(), finishing: true)
        omittedBytes += max(0, offset - previousEnd)
        let report: [String: Any] = [
            "scope": "unchanged production VoiceSegmenter only; no ASR, capture hardware, or input resampler",
            "input_path": inputURL.path, "input_wav_sha256": hash(file),
            "original_pcm_sha256": hash(originalPCM), "repeat_count": repeatCount,
            "derived_fixture": repeatCount > 1 || activeTail,
            "fed_pcm_sha256": hash(input.prefix(offset)), "fed_samples": offset / 2,
            "active_tail_requested": activeTail, "active_tail_trigger_observed": tailAttempted,
            "speaking_at_finish": wasSpeakingAtFinish, "finish_audio_bytes": finishAudioBytes,
            "omitted_samples": omittedBytes / 2, "overlap_samples": overlapBytes / 2,
            "forced_rotations": records.filter { ($0["end_reason"] as? String) == "forced_rotation" }.count,
            "segments": records
        ]
        let data = try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: outputURL.appendingPathComponent("report.json"), options: .atomic)
        print("Wrote \(records.count) segments; report: \(outputURL.appendingPathComponent("report.json").path)")
    }
}
