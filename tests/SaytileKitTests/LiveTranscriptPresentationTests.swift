import AppKit
import Testing
@testable import SaytileVoiceUI

@MainActor @Suite struct LiveTranscriptPresentationTests {
    private struct Row: VoiceTranscriptEntry {
        let id: UUID
        let position: Int64
        let displayText: String
    }

    @Test func revisionsInterruptOnlyLiveAppendsAndNativeRangesStayExact() async throws {
        _ = NSApplication.shared
        let box = NSRect(x: 0, y: 0, width: 210, height: 115)
        let panel = NSPanel(contentRect: box, styleMask: [.nonactivatingPanel, .borderless], backing: .buffered, defer: false)
        let scroll = CompactTranscriptScrollView<Row>(frame: box)
        panel.contentView = scroll
        panel.isReleasedWhenClosed = false
        panel.alphaValue = 0
        panel.ignoresMouseEvents = true
        panel.orderFrontRegardless()
        defer { panel.orderOut(nil); panel.close() }
        let id = UUID()
        func doc(_ text: String, live: Bool = true) -> PanelTimelineDocument<Row> {
            var next = PanelTimelineDocument(entries: [Row(id: id, position: 1, displayText: text)])
            next.liveTailID = live ? id : nil
            return next
        }
        let phrase = "明天👨🏾‍💻到机场讨论费用"
        let live = doc(phrase)
        let presentationEnabled = !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion && !NSWorkspace.shared.isVoiceOverEnabled
        scroll.updateDocument(live)
        let early = scroll.transcriptView.string
        #expect(!early.isEmpty && phrase.hasPrefix(early))
        #expect(scroll.rendered.displayed[1] == early)
        #expect(scroll.rendered.spans.last?.range == NSRange(location: 0, length: early.utf16.count))
        if presentationEnabled { #expect(early != phrase) } else { #expect(early == phrase) }
        // Repeated microphone meter redraws must not immediately consume the other steps.
        for _ in 0..<20 { scroll.updateDocument(live) }
        #expect(scroll.transcriptView.string == early)
        scroll.updateDocument(doc("后天再谈")) // a real tail rewrite
        #expect(scroll.transcriptView.string == "后天再谈")
        let latest = "后天再谈下个月的预算和人员安排"
        scroll.updateDocument(doc(latest))
        scroll.updateDocument(doc(latest, live: false))
        #expect(scroll.transcriptView.string == latest)
        try await Task.sleep(for: .milliseconds(130))
        #expect(scroll.transcriptView.string == latest)

        let appended = latest + " StreamingParaformer"
        scroll.updateDocument(doc(appended))
        #expect(scroll.transcriptView.string == appended)
        let full = appended + "需要保留这段真实的完整文字"
        scroll.updateDocument(doc(full))
        scroll.transcriptView.setSelectedRange(NSRange(location: 0, length: 2))
        let pinned = scroll.transcriptView.string
        try await Task.sleep(for: .milliseconds(120))
        #expect(scroll.transcriptView.string == pinned)
        #expect(scroll.selectionSnapshot == "后天")
        scroll.jumpToLatest()
        scroll.settleLivePresentation()
        #expect(scroll.transcriptView.string == full)

        let tail = full + "新说的词语要保留"
        scroll.updateDocument(doc(tail))
        let cut = NSRange(location: 1, length: 1)
        let expected = (tail as NSString).replacingCharacters(in: cut, with: "日")
        var edits: [VoicePanelEdit] = []
        scroll.applyEdits = { changes in
            edits += changes
            return doc(expected, live: false)
        }
        scroll.transcriptView.isEditable = true
        scroll.transcriptView.insertText("日", replacementRange: cut)
        #expect(edits == [VoicePanelEdit(id: id, before: tail, after: expected)])
        #expect(scroll.transcriptView.string == expected)
        try await Task.sleep(for: .milliseconds(120))
        #expect(scroll.transcriptView.string == expected)
        panel.orderOut(nil)
        scroll.updateDocument(doc(expected + "隐藏窗口"))
        #expect(scroll.transcriptView.string == expected + "隐藏窗口")
    }
}
