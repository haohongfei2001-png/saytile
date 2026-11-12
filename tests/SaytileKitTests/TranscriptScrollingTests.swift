import AppKit
import Testing
@testable import SaytileVoiceUI

@Suite @MainActor struct TranscriptScrollingTests {
    private struct Row: VoiceTranscriptEntry {
        let id = UUID()
        let position: Int64
        var displayText: String { "测试行 \(position)" }
    }

    @Test func pageKeysLoadAdjacentHistoryOnceAndRespectSelection() throws {
        _ = NSApplication.shared
        let box = NSRect(x: 0, y: 0, width: 200, height: 90)
        let scroll = CompactTranscriptScrollView<Row>(frame: box)
        let panel = NSPanel(contentRect: box, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isReleasedWhenClosed = false
        panel.contentView = scroll
        defer { panel.close() }
        let view = scroll.transcriptView
        var requests: [Bool] = []
        scroll.onPage = { requests.append($0) }
        let entries = (1...80).map { Row(position: Int64($0)) }
        scroll.updateDocument(PanelTimelineDocument(entries: entries, older: true, newer: true))
        scroll.layoutSubtreeIfNeeded()
        #expect(scroll.verticalScroller is TranscriptScroller)
        #expect(scroll.verticalScroller?.accessibilityRole() == .scrollBar)
        view.setSelectedRange(NSRange(location: 0, length: 2))
        view.scrollRangeToVisible(NSRange(location: 0, length: 0))
        view.doCommand(by: #selector(NSResponder.scrollPageUp(_:)))
        #expect(requests.isEmpty)
        view.setSelectedRange(NSRange(location: 0, length: 0))
        view.doCommand(by: #selector(NSResponder.pageUp(_:)))
        view.doCommand(by: #selector(NSResponder.scrollPageUp(_:)))
        #expect(requests == [true])
        scroll.jumpToLatest()
        view.doCommand(by: #selector(NSResponder.scrollPageDown(_:)))
        #expect(requests == [true, false])
    }
}
