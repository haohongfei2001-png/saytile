import Testing
import Foundation
@preconcurrency import AVFoundation
@testable import SaytileKit

@Suite("Capture converter input ownership")
struct CaptureConverterTests {
    @Test(arguments: [16_000.0, 22_050.0, 44_100.0, 48_000.0])
    func varyingRingBatchSizesPreserveCompleteWaveform(sampleRate: Double) async throws {
        let count = Int(sampleRate * (60_809.0 / 22_050.0))
        // Non-silent, deterministic signal, with distinct beginning and ending
        // transients. No microphone, assets, model or voice-quality assumption.
        var samples = (0..<count).map { index in
            let t = Double(index) / sampleRate
            return Float(0.35 * sin(2 * .pi * (125 * t + 31 * t * t)) + 0.17 * sin(2 * .pi * 733 * t))
        }
        samples[0] = 0.75; samples[count - 1] = -0.75
        let reference = try Self.contiguousReference(samples, sampleRate: sampleRate)
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("saytile-converter-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try SaytileStore(directory: root)
        let worker = try CaptureWorker(store: store, ring: AudioRing(capacity: 8_192), sampleRate: sampleRate,
            recognitionEnabled: false, update: { _, _ in }, failed: { _ in })
        var actual = Data(), offset = 0, batch = 0
        let pattern = [8_192, 1_024, 1_024, 512, 1_024]
        while offset < samples.count {
            let end = min(samples.count, offset + pattern[batch % pattern.count])
            for pcm in try await worker.convertCapturedSamples(Array(samples[offset..<end]), count: UInt32(end - offset)) {
                actual.append(pcm)
            }
            offset = end; batch += 1
        }
        for pcm in try await worker.drainConvertedTail() { actual.append(pcm) }
        print("CAPTURE_CONVERTER rate=\(sampleRate) source_frames=\(samples.count) reference_frames=\(reference.count / 2) actual_frames=\(actual.count / 2) waveform_equal=\(actual == reference)")
        #expect(actual.count == reference.count, "Every source batch must actually reach the converter before being retired")
        #expect(actual == reference, "Full beginning, middle and end waveform must match the contiguous reference; no padding")
        #expect(try await worker.drainConvertedTail().isEmpty, "End-of-stream draining must not replay audio")
        try await store.close()
    }

    private static func contiguousReference(_ samples: [Float], sampleRate: Double) throws -> Data {
        let source = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: sampleRate, channels: 1, interleaved: false)!
        let target = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: 16_000, channels: 1, interleaved: false)!
        let input = AVAudioPCMBuffer(pcmFormat: source, frameCapacity: UInt32(samples.count))!
        input.frameLength = input.frameCapacity
        samples.withUnsafeBufferPointer { input.floatChannelData![0].update(from: $0.baseAddress!, count: samples.count) }
        let converter = AVAudioConverter(from: source, to: target)!
        var supplied = false, result = Data()
        while true {
            let output = AVAudioPCMBuffer(pcmFormat: target, frameCapacity: UInt32(ceil(Double(samples.count) * 16_000 / sampleRate) + 64))!
            var error: NSError?
            let status = converter.convert(to: output, error: &error) { _, state in
                if supplied { state.pointee = .endOfStream; return nil }
                supplied = true; state.pointee = .haveData; return input
            }
            if status == .error { throw error ?? AudioFailure.message("Reference conversion failed") as NSError }
            if output.frameLength > 0 { result.append(Data(bytes: output.int16ChannelData![0], count: Int(output.frameLength) * 2)) }
            if status == .endOfStream || output.frameLength == 0 { return result }
        }
    }
}
