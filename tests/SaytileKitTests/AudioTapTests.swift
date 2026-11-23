import Testing
import Foundation
import Darwin
import CAudio
@preconcurrency import AVFoundation
@testable import SaytileKit

private final class TapBox: @unchecked Sendable {
    let callback: AVAudioNodeTapBlock
    init(_ callback: @escaping AVAudioNodeTapBlock) { self.callback = callback }
}

@Suite("Real-time tap actor isolation")
struct AudioTapTests {
    @Test(arguments: [(UInt32(1), UInt32(2)), (UInt32(2), UInt32(1))])
    func recordingTapRejectsChangedChannelLayoutUntilEngineIsRebuilt(expected: UInt32, actual: UInt32) throws {
        let ring = try AudioRing(capacity: 1_024)
        let callback = AudioTapCallbacks.recording(ring: ring, channels: expected, sampleRate: 16_000)
        let changedFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16_000, channels: actual, interleaved: false)!
        let changed = AVAudioPCMBuffer(pcmFormat: changedFormat, frameCapacity: 320)!
        changed.frameLength = 320
        changed.floatChannelData![0].initialize(repeating: 0.25, count: 320)
        if actual > 1 { changed.floatChannelData![1].initialize(repeating: 0.75, count: 320) }
        callback(changed, AVAudioTime(sampleTime: 0, atRate: 16_000))
        var output = [Float](repeating: 0, count: 320)
        #expect(output.withUnsafeMutableBufferPointer { st_ring_read(ring.pointer, $0.baseAddress!, 320) } == 0)
        #expect(st_ring_dropped(ring.pointer) == 320)
    }
    @MainActor @Test func recordingTapCreatedOnMainActorRunsOnBackgroundThread() async throws {
        let ring = try AudioRing(capacity: 1_024)
        let callback = TapBox(AudioTapCallbacks.recording(ring: ring, channels: 1, sampleRate: 16_000))
        let background = await Task.detached {
            let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16_000, channels: 1, interleaved: false)!
            let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 320)!
            buffer.frameLength = 320
            buffer.floatChannelData![0].initialize(repeating: 0.25, count: 320)
            callback.callback(buffer, AVAudioTime(sampleTime: 0, atRate: 16_000))
            return pthread_main_np() == 0
        }.value
        #expect(background)
        var output = [Float](repeating: 0, count: 320)
        #expect(output.withUnsafeMutableBufferPointer { st_ring_read(ring.pointer, $0.baseAddress!, 320) } == 320)
        #expect(output.allSatisfy { $0 == 0.25 })
    }
    @Test func recordingTapRejectsChangedSampleRateBeforeOldConverterReadsIt() throws {
        let ring = try AudioRing(capacity: 1_024)
        let callback = AudioTapCallbacks.recording(ring: ring, channels: 1, sampleRate: 16_000)
        let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 48_000, channels: 1, interleaved: false)!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 320)!
        buffer.frameLength = 320
        buffer.floatChannelData![0].initialize(repeating: 0.25, count: 320)
        callback(buffer, AVAudioTime(sampleTime: 0, atRate: 48_000))
        var output = [Float](repeating: 0, count: 320)
        #expect(output.withUnsafeMutableBufferPointer { st_ring_read(ring.pointer, $0.baseAddress!, 320) } == 0)
        #expect(st_ring_dropped(ring.pointer) == 320)
    }
    @MainActor @Test func countOnlyTapNeverReadsSampleDataAndRunsOffMain() async throws {
        let counter = try AudioProbeCounter()
        let callback = TapBox(AudioTapCallbacks.counting(counter: counter))
        let background = await Task.detached {
            let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16_000, channels: 1, interleaved: false)!
            let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 640)!
            buffer.frameLength = 640
            callback.callback(buffer, AVAudioTime(sampleTime: 0, atRate: 16_000))
            return pthread_main_np() == 0
        }.value
        #expect(background)
        #expect(st_probe_buffers(counter.pointer) == 1)
        #expect(st_probe_frames(counter.pointer) == 640)
    }
}
