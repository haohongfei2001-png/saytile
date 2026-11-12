import AppKit
import Testing
@testable import SaytileVoiceUI

@Suite @MainActor struct TranscriptScrollingTests {
    private struct Row: VoiceTranscriptEntry {
        let id = UUID()
        let position: Int64
        var displayText: String { "测试行 \(position)" }
    }

    @Test(.serialized, arguments: [NSScroller.Style.overlay, .legacy])
    func pageKeysLoadAdjacentHistoryOnceAndRespectSelection(style: NSScroller.Style) async throws {
        _ = NSApplication.shared
        let box = NSRect(x: 0, y: 0, width: 200, height: 90)
        let scroll = CompactTranscriptScrollView<Row>(frame: box)
        let panel = NSPanel(contentRect: box, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isReleasedWhenClosed = false
        panel.contentView = scroll
        panel.alphaValue = 0
        panel.ignoresMouseEvents = true
        panel.orderFrontRegardless()
        defer { panel.orderOut(nil); panel.close() }
        let view = scroll.transcriptView
        var requests: [Bool] = []
        scroll.onPage = { requests.append($0) }
        let entries = (1...80).map { Row(position: Int64($0)) }
        scroll.updateDocument(PanelTimelineDocument(entries: entries, older: true, newer: true))
        scroll.layoutSubtreeIfNeeded()
        scroll.scrollerStyle = style
        scroll.flashScrollers()
        scroll.layoutSubtreeIfNeeded()
        #expect(scroll.documentVisibleRect.height < view.bounds.height)
        #expect(!scroll.hasVerticalScroller && scroll.verticalScroller == nil)
        #expect(!scroll.hasHorizontalScroller && scroll.horizontalScroller == nil)
        #expect(abs(scroll.contentSize.width - scroll.bounds.width) < 0.5)
        scroll.contentView.scroll(to: CGPoint(x: 0, y: (view.bounds.height - scroll.contentSize.height) / 2))
        scroll.reflectScrolledClipView(scroll.contentView)
        let start = scroll.contentView.bounds.minY
        let wheel = try #require(CGEvent(scrollWheelEvent2Source: nil, units: .line,
                                          wheelCount: 1, wheel1: 3, wheel2: 0, wheel3: 0))
        // Route this wheel event to the isolated native window at its text area.
        // CGEvent uses a top-left desktop origin; the NSPanel uses bottom-left.
        let primary = try #require(NSScreen.screens.first)
        let point = panel.convertPoint(toScreen: CGPoint(x: box.midX, y: box.midY))
        wheel.location = CGPoint(x: point.x, y: primary.frame.maxY - point.y)
        panel.sendEvent(try #require(NSEvent(cgEvent: wheel)))
        // Yield the main actor so AppKit can finish the native scroll. Pumping a
        // nested run loop inside a synchronous test can starve deferred delivery.
        let deadline = ContinuousClock.now + .seconds(1)
        while scroll.contentView.bounds.minY >= start, ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(8))
        }
        #expect(start > 32)
        #expect(scroll.contentView.bounds.minY < start, "wheel from \(start) to \(scroll.contentView.bounds.minY)")
        #expect(scroll.verticalScroller == nil)
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
