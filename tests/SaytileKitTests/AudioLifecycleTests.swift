import Testing
import Foundation
@testable import SaytileKit

@Suite("Capture shutdown tail")
struct AudioLifecycleTests {
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
    @Test func finishDoesNotSaveStandbySilenceAsSpeech() throws {
        let segmenter = try VoiceSegmenter()
        _ = segmenter.accept(Data(repeating:0,count:1003 * 2))
        #expect(segmenter.finish().isEmpty)
    }
}
