import Foundation
import Testing
@testable import SaytileKit

@Suite struct QwenPrefixConfirmationTests {
    @Test func completePhraseNeedsIndependentAudioAndFollowingSpeech() {
        var gate = QwenPrefixConfirmation()
        let text = "今天阳光很好，我们继续讨论接下来的安排"
        for i in 0..<3 { #expect(gate.accept(text, frames: 16_000 + i * 8_000) == 0) }
        #expect(gate.accept(text, frames: 40_000) == "今天阳光很好，".utf16.count)
        // Re-decoding an unchanged PCM window is not independent evidence.
        #expect(gate.accept(text, frames: 40_000) == 0)
        #expect(gate.accept("今天阴天，我们继续讨论接下来的安排", frames: 48_000) == 0)
        #expect(gate.confirmed == "今天阳光很好，")
    }
    @Test func trailingStopAndUnfinishedWordsNeverBecomeEarlyDispatch() {
        var gate = QwenPrefixConfirmation()
        for i in 0..<8 { #expect(gate.accept("这个词还没有说完。", frames: 16_000 + i * 8_000) == 0) }
    }
    @Test(arguments: ["请支付30元，", "请支付三十元，", "我不接受，", "先不要发送，"])
    func criticalPhraseNeedsLongerAgreement(phrase: String) {
        var gate = QwenPrefixConfirmation()
        for i in 0..<5 {
            #expect(gate.accept(phrase + "我们接着讨论后面的安排", frames: 16_000 + i * 8_000) == 0)
        }
        #expect(gate.accept(phrase + "我们接着讨论后面的安排", frames: 56_000) == phrase.utf16.count)
    }
}
