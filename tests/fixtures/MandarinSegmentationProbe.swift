import AVFoundation
import CryptoKit
import Foundation
@testable import SaytileKit

/// Inspect only pinned public WAVs. Exercise the product VAD without starting a
/// microphone, creating an archive, changing decoder settings or measuring ASR.
@main struct MandarinSegmentationProbe {
    struct Source: Decodable {
        let id, source, audio_sha256: String
    }
    struct Segment: Codable {
        let firstVoiceSample, lastVoiceSample: Int64
        let journalFrames: Int
    }
    struct Result: Encodable {
        let id, source: String
        let frames: Int
        let segments: [Segment]
    }
    static func main() throws {
        let args = CommandLine.arguments
        guard args.count >= 4 else { throw CocoaError(.fileReadInvalidFileName) }
        let directory = URL(fileURLWithPath: args[1])
        var results = [Result]()
        for manifest in args.dropFirst(3) {
            let rows = try JSONDecoder().decode([Source].self, from: Data(contentsOf: URL(fileURLWithPath: manifest)))
            for row in rows {
                let url = directory.appendingPathComponent(row.id + ".wav")
                guard !row.id.contains("/"), SHA256.hash(data: try Data(contentsOf: url)).map({
                    String(format: "%02x", $0)
                }).joined() == row.audio_sha256 else { throw CocoaError(.fileReadCorruptFile) }
                let file = try AVAudioFile(forReading: url, commonFormat: .pcmFormatInt16, interleaved: false)
                guard file.processingFormat.sampleRate == 16_000, file.processingFormat.channelCount == 1,
                      let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: 3200)
                else { throw CocoaError(.fileReadCorruptFile) }
                let segmenter = try VoiceSegmenter()
                var segments = [Segment](), start: Int64?, captured = 0
                func observe(_ events: [VoiceSegmenter.Event]) {
                    for event in events {
                        switch event {
                        case .begin(let preRoll, let sample):
                            precondition(start == nil)
                            start = sample
                            captured = preRoll.reduce(0) { $0 + $1.count / 2 }
                        case .audio(let pcm):
                            precondition(start != nil)
                            captured += pcm.count / 2
                        case .end(let sample):
                            segments.append(Segment(firstVoiceSample: start!, lastVoiceSample: sample, journalFrames: captured))
                            start = nil
                        }
                    }
                }
                while file.framePosition < file.length {
                    try file.read(into: buffer)
                    guard buffer.frameLength > 0, let samples = buffer.int16ChannelData else { throw CocoaError(.fileReadCorruptFile) }
                    observe(segmenter.accept(Data(bytes: samples[0], count: 2 * Int(buffer.frameLength))))
                }
                observe(segmenter.finish())
                precondition(start == nil)
                results.append(Result(id: row.id, source: row.source, frames: Int(file.length), segments: segments))
            }
        }
        let output = URL(fileURLWithPath: args[2])
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        try encoder.encode(results).write(to: output, options: .withoutOverwriting)
    }
}
