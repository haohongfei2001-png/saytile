import Testing
@testable import SaytileKit

@Suite("Speech range aggregation")
struct SpeechResultTests {
    @Test func finalizationWatermarkStabilizesEarlierVolatileTextWithoutRepeat() {
        var aggregate = SpeechResultAccumulator()
        aggregate.apply(start: 0, end: 1, text: "第一句", isFinal: false)
        let result = aggregate.apply(start: 1, end: 2, text: "继续", isFinal: false, finalizedThrough: 1)
        #expect(result.stableText == "第一句")
        #expect(result.fullText == "第一句继续")
        #expect(!result.isCompletelyFinal)
        #expect(aggregate.advanceFinalization(through: 2).isCompletelyFinal)
    }
    @Test func finalizationWatermarkNeverRewindsOrPromotesBeyondCoverage() {
        var aggregate = SpeechResultAccumulator()
        aggregate.apply(start: 0, end: 2, text: "完整范围", isFinal: false)
        #expect(aggregate.advanceFinalization(through: 1).stableText.isEmpty)
        #expect(aggregate.advanceFinalization(through: .nan).stableText.isEmpty)
        let final = aggregate.advanceFinalization(through: 2)
        #expect(final.isCompletelyFinal)
        #expect(aggregate.advanceFinalization(through: 0) == final)
    }
    @Test func validHypothesisIsVisibleEvenWithoutANewerFinalizationTime() {
        var aggregate = SpeechResultAccumulator()
        let first = aggregate.apply(start: 0, end: 1, text: "当时", isFinal: false, finalizedThrough: .nan)
        #expect(first.fullText == "当时")
        #expect(first.stableText.isEmpty)

        aggregate.advanceFinalization(through: 1)
        let tail = aggregate.apply(start: 1, end: 2, text: "没听清", isFinal: false, finalizedThrough: 0)
        #expect(tail.fullText == "当时没听清")
        #expect(tail.stableText == "当时")
        let final = aggregate.apply(start: 1, end: 2, text: "没听清。", isFinal: true, finalizedThrough: .nan)
        #expect(final.fullText == "当时没听清。")
        #expect(final.isCompletelyFinal)
    }
    @Test func finalPrefixAdvancesWhileTailIsVolatile() {
        var aggregate = SpeechResultAccumulator()
        aggregate.apply(start:0,end:1,text:"你好",isFinal:true)
        var snapshot = aggregate.apply(start:1,end:2,text:"世界",isFinal:false)
        #expect(snapshot.fullText == "你好世界")
        #expect(snapshot.stableText == "你好")
        #expect(!snapshot.isCompletelyFinal)
        snapshot = aggregate.apply(start:1,end:2,text:"，世界。",isFinal:true)
        #expect(snapshot.stableText == "你好，世界。")
        #expect(snapshot.isCompletelyFinal)
    }
    @Test func laterFinalDoesNotSkipEarlierVolatileRange() {
        var aggregate = SpeechResultAccumulator()
        aggregate.apply(start:0,end:1,text:"未定稿",isFinal:false)
        let snapshot = aggregate.apply(start:1,end:2,text:"已定稿",isFinal:true)
        #expect(snapshot.stableText.isEmpty)
        #expect(snapshot.fullText == "未定稿已定稿")
    }
    @Test func revisingRangeReplacesInsteadOfDuplicating() {
        var aggregate = SpeechResultAccumulator()
        aggregate.apply(start:0,end:1,text:"你号",isFinal:false)
        aggregate.apply(start:0,end:1,text:"你好",isFinal:true)
        let snapshot = aggregate.apply(start:0,end:1,text:"你好",isFinal:true)
        #expect(snapshot.fullText == "你好")
        #expect(snapshot.stableText == "你好")
    }
    @Test func mergedRangeReplacesAllOverlaps() {
        var aggregate = SpeechResultAccumulator()
        aggregate.apply(start:0,end:1,text:"一",isFinal:false)
        aggregate.apply(start:1,end:2,text:"二",isFinal:false)
        let snapshot = aggregate.apply(start:0,end:2,text:"合并修订",isFinal:true)
        #expect(snapshot.fullText == "合并修订")
        #expect(snapshot.stableText == "合并修订")
    }
    @Test func invalidRangesDoNotLoseValidText() {
        var aggregate = SpeechResultAccumulator()
        let original = aggregate.apply(start:0,end:1,text:"你😀",isFinal:true)
        #expect(aggregate.apply(start:.nan,end:2,text:"无效",isFinal:true) == original)
        #expect(aggregate.apply(start:2,end:1,text:"无效",isFinal:true) == original)
        #expect(aggregate.apply(start:2,end:.infinity,text:"无效",isFinal:true) == original)
    }
}
