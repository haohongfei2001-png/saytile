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
    @Test func finishDoesNotSaveStandbySilenceAsSpeech() throws {
        let segmenter = try VoiceSegmenter()
        _ = segmenter.accept(Data(repeating:0,count:1003 * 2))
        #expect(segmenter.finish().isEmpty)
    }
}
