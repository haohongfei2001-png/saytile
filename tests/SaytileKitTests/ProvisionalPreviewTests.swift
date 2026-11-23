import AppKit
import Testing
@testable import SaytileKit
@testable import SaytileVoiceUI

@Suite struct ProvisionalPreviewTests {
    @Test func oldWordUncertaintyDoesNotFreezeNewSpeechOrGrantDispatch() {
        var strict = LocalLiveText(model: .qwen)
        var preview = LocalLiveText(model: .qwen, previewPolicy: .provisional)
        let start = "这里是视力最好的地区，这里的山谷拥有各种各样的花岗岩"
        for text in [start, start + "和峭壁"] {
            _ = strict.accept(text, final: false); _ = preview.accept(text, final: false)
        }
        for text in ["这里是智利最好的地区，这里的山谷拥有各种各样的花岗岩和峭壁，平时你",
                     "这里是这里最好的地区，这里的山谷拥有各种各样的花岗岩和峭壁，平时你能看到远方"] {
            #expect(strict.accept(text, final: false) == nil)
            #expect(preview.accept(text, final: false) == 0)
            #expect(preview.presentation == text)
        }
        let final = "这里是智利最好的地区。"
        #expect(preview.accept(final, final: true) == final.utf16.count)
        #expect(preview.presentation == final)
    }

    @Test func changedNumberAndNegationRemainPreviewAndUserEditWins() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try SaytileStore(directory: root)
        let record = try await store.createRecording()
        let ticket = try await store.beginRecognition(recordingID: record.id)
        let ingress = LocalCandidateIngress(store: store, ticket: ticket, model: .qwen)
        var preview = LocalLiveText(model: .qwen, previewPolicy: .provisional)
        for text in ["我想支付三十元，今天就处理", "我不想支付十三元，今天先不要处理这个订单"] {
            let decision = preview.accept(text, final: false)
            let stable = try #require(decision)
            try await ingress.receive(.init(text: preview.presentation, stableUTF16Length: stable, audioEndSeconds: 3))
            #expect(try await store.recording(id: record.id)?.text == text)
            #expect(try await store.latestDispatchableRevision(recordingID: record.id) == nil)
        }
        _ = try await store.saveEdit(recordingID: record.id, text: "用户改成自己的文字")
        let final = "我不想支付十三元。"
        try await ingress.receive(.init(text: final, stableUTF16Length: final.utf16.count, audioEndSeconds: 4, isComplete: true))
        try await ingress.finish()
        #expect(try await store.recording(id: record.id)?.text == "用户改成自己的文字")
    }

    @Test func isolatedTailFlipStillNeedsConfirmation() {
        var preview = LocalLiveText(model: .qwen, previewPolicy: .provisional)
        let a = "这个例子介绍人类大理石的五倍。", b = "这个例子介绍人类大力士的五倍。"
        #expect(preview.accept(a, final: false) == 0)
        #expect(preview.accept(b, final: false) == nil)
        #expect(preview.accept(a, final: false) == 0)
        // Re-observing A confirms its punctuation too; the transient word B never appears.
        #expect(preview.presentation == a)
        #expect(preview.accept(b, final: true) == b.utf16.count)
        #expect(preview.presentation == b)
    }

    @MainActor @Test func nativeFinalTintChangesEvenWithoutTextMutation() {
        struct Row: VoiceTranscriptEntry {
            let id = UUID(), position: Int64 = 1
            let displayText = "这是模型当前候选"
            var isProvisional = true
        }
        _ = NSApplication.shared
        let scroll = CompactTranscriptScrollView<Row>(frame: NSRect(x: 0, y: 0, width: 260, height: 180))
        var row = Row()
        scroll.updateDocument(.init(entries: [row]))
        let storage = scroll.transcriptView.textStorage!
        let color = storage.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor
        #expect(color?.alphaComponent == 0.60)
        row.isProvisional = false
        scroll.updateDocument(.init(entries: [row]))
        #expect(scroll.transcriptView.string == row.displayText)
        #expect((storage.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor)?.alphaComponent == 1)
    }
}
