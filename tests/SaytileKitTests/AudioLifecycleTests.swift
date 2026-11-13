import Testing
import Foundation
@testable import SaytileKit

@Suite("Capture shutdown tail")
struct AudioLifecycleTests {
    @Test func durationRolloverKeepsEveryPCMByteWhenPausedNearTheBoundary() throws {
        let samples = (0..<12_800).map { i in
            let t = Double(i) / 16_000
            return Int16(10_000 * sin(2 * .pi * 120 * t) + 4_000 * sin(2 * .pi * 660 * t))
        }
        let pcm = samples.withUnsafeBytes { Data($0) }
        // A short limit exercises the same forced rollover as 30 s of local
        // capture. Determine the onset with the real bundled WebRTC detector.
        let probe = try VoiceSegmenter(maximumFrames: 3)
        var onsetEnd = 0
        while !probe.speaking && onsetEnd < pcm.count {
            _ = probe.accept(pcm.subdata(in: onsetEnd..<(onsetEnd + 640)))
            onsetEnd += 640
        }
        try #require(probe.speaking)
        let boundary = onsetEnd + 3 * 640
        for tailSamples in [0, 17, 319, 320, 337, 640, 959, 960, 1280] {
            let input = pcm.prefix(boundary + tailSamples * 2)
            let segmenter = try VoiceSegmenter(maximumFrames: 3)
            var saved = Data(), starts = 0, ends = 0
            for event in segmenter.accept(input) + segmenter.finish() {
                switch event {
                case .begin(let frames, _):
                    #expect(starts == ends)
                    starts += 1
                    for frame in frames { saved.append(frame) }
                case .audio(let frame):
                    #expect(starts == ends + 1)
                    saved.append(frame)
                case .end:
                    #expect(starts == ends + 1)
                    ends += 1
                }
            }
            #expect(starts == ends)
            #expect(saved == input)
            if tailSamples < 320 { #expect(starts == 1) }
            if tailSamples >= 960 { #expect(starts > 1) }
            #expect(segmenter.finish().isEmpty)
        }
    }

    @Test func finishFlushesSubVADFrameTailOfActiveSpeech() throws {
        let segmenter = try VoiceSegmenter()
        var pcm = Data()
        for sample in 0..<1003 {
            let phase = Double(sample) / 16000
            let value = 10000 * (sin(2 * Double.pi * 120 * phase) + 0.4 * sin(2 * Double.pi * 660 * phase))
            var integer = Int16(value).littleEndian
            withUnsafeBytes(of:&integer) { pcm.append(contentsOf:$0) }
        }
        _ = segmenter.accept(pcm)
        #expect(segmenter.speaking)
        let end = segmenter.finish()
        var tail = Data(); var ended = false
        for event in end {
            switch event { case .audio(let frame): tail.append(frame); case .end: ended = true; case .begin: Issue.record("Shutdown must not create a new recording") }
        }
        #expect(tail == pcm.suffix(86))
        #expect(ended)
        #expect(!segmenter.speaking)
        #expect(segmenter.finish().isEmpty)
    }
    @Test func localRecognizerKeepsItsContextAcrossAThinkingPause() throws {
        let segmenter = try VoiceSegmenter()
        let samples = (0..<3_200).map { i in
            Int16(10_000 * sin(2 * .pi * Double(i) * 180 / 16_000))
        }
        let syllable = samples.withUnsafeBytes { Data($0) }
        let pause = Data(repeating: 0, count: 35_200) // 1.1 seconds at 16 kHz, mono PCM16.
        let events = segmenter.accept(syllable + pause + syllable + Data(repeating: 0, count: 80_000))
        let starts = events.filter { if case .begin = $0 { true } else { false } }
        let ends = events.filter { if case .end = $0 { true } else { false } }
        #expect(starts.count == 1)
        #expect(ends.count == 1)
        #expect(!segmenter.speaking)
    }
    @Test func isolatedClickAndItsVADHangoverCannotStartARecording() throws {
        let segmenter = try VoiceSegmenter()
        // The pinned WebRTC model classifies this impulse once, then returns
        // three hangover frames. Those frames cannot vote for a new utterance.
        var samples = [Int16](repeating: 0, count: 32_000)
        samples[3_200] = 10_000
        let pcm = samples.withUnsafeBytes { Data($0) }
        #expect(segmenter.accept(pcm).isEmpty)
        #expect(segmenter.finish().isEmpty)
    }

    @Test func finishDoesNotSaveStandbySilenceAsSpeech() throws {
        let segmenter = try VoiceSegmenter()
        _ = segmenter.accept(Data(repeating:0,count:1003 * 2))
        #expect(segmenter.finish().isEmpty)
    }
}
