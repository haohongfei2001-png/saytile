import Foundation
import Testing
@testable import SaytileKit

@Suite("AssemblyAI adapter evidence parsing")
struct AssemblyAIAdapterTests {
    @Test func millisecondsAreConvertedWithoutInventingTiming() {
        let words: [[String: Any]] = [
            ["text": "SwiftUI", "start": 100.0, "end": 530.0, "confidence": 0.91],
            ["text": "SQLite", "start": 550.0, "end": 980.0]
        ]
        let parsed = AssemblyAIStreamingProvider.parseWords(words)
        #expect(parsed.count == 2)
        #expect(parsed[0].startSeconds == 0.1)
        #expect(parsed[0].endSeconds == 0.53)
        #expect(parsed[0].rawConfidence == 0.91)
        #expect(parsed[1].rawConfidence == nil)
    }

    @Test func malformedTimingIsNotPromotedToEvidence() {
        let raw: [[String: Any]] = [
            ["text": "wrong", "start": 500.0, "end": 100.0],
            ["text": "missing", "start": 10.0],
            ["text": "valid", "start": 0.0, "end": 200.0]
        ]
        #expect(AssemblyAIStreamingProvider.parseWords(raw).map(\.text) == ["valid"])
    }
}
