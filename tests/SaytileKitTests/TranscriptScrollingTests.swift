import AppKit
import Testing
@testable import SaytileVoiceUI

@Suite @MainActor struct TranscriptScrollingTests {
    private struct Row: VoiceTranscriptEntry {
        let id = UUID()
        let position: Int64
        var displayText: String { "测试行 \(position)" }
    }

    private func waitForWheel(toReach condition: () -> Bool) async throws {
        let deadline = ContinuousClock.now + .seconds(2)
        while !condition(), ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(4)) }
        #expect(condition())
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
        #expect(start > 32)
        let expected = min(3 * scroll.verticalLineScroll, scroll.contentSize.height / 2)
        try await waitForWheel { abs(scroll.contentView.bounds.minY - (start - expected)) < 0.5 }
        let travel = start - scroll.contentView.bounds.minY
        #expect(travel > 0 && travel <= scroll.contentSize.height / 2 + 1, "wheel moved \(travel) pt")
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

    @Test func mechanicalWheelInterpolatesOnlyItsOwnMotion() async throws {
        _ = NSApplication.shared
        let box = NSRect(x: 0, y: 0, width: 154.5, height: 65)
        let scroll = CompactTranscriptScrollView<Row>(frame: box)
        let panel = NSPanel(contentRect: box, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.contentView = scroll
        panel.isReleasedWhenClosed = false
        panel.ignoresMouseEvents = true
        panel.alphaValue = 0.01
        panel.orderBack(nil)
        defer { panel.orderOut(nil); panel.close() }
        let rows = (1...64).map { Row(position: Int64($0)) }
        scroll.updateDocument(.init(entries: rows))
        scroll.layoutSubtreeIfNeeded()
        func move(to y: CGFloat) {
            scroll.contentView.scroll(to: NSPoint(x: 0, y: y))
            scroll.reflectScrolledClipView(scroll.contentView)
        }
        func wheel(_ amount: Int32) throws {
            let cg = try #require(CGEvent(scrollWheelEvent2Source: nil, units: .line, wheelCount: 1,
                                          wheel1: amount, wheel2: 0, wheel3: 0))
            scroll.scrollWheel(with: try #require(NSEvent(cgEvent: cg)))
        }
        move(to: 100)
        try wheel(3)
        if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            #expect(scroll.documentVisibleRect.minY == 70)
            return
        }
        #expect(scroll.documentVisibleRect.minY == 100)
        try await waitForWheel { scroll.documentVisibleRect.minY < 100 }
        let firstFrame = scroll.documentVisibleRect.minY
        #expect(firstFrame > 70)
        try wheel(-1)
        try await waitForWheel { abs(scroll.documentVisibleRect.minY - firstFrame - 10) < 0.01 }
        try wheel(2)
        move(to: 45)
        try await Task.sleep(for: .milliseconds(160))
        #expect(scroll.documentVisibleRect.minY == 45)
    }

    @Test func wheelOverflowIsConsumedOnceByTheRequestedPageAndCancelsOnReversal() async throws {
        _ = NSApplication.shared
        let box = NSRect(x: 0, y: 0, width: 182, height: 80)
        let rows = (1...96).map { Row(position: Int64($0)) }
        for (unit, delta, reverse) in [(CGScrollEventUnit.line, Int32(3), false), (.pixel, 8, false), (.line, 3, true)] {
            let scroll = CompactTranscriptScrollView<Row>(frame: box)
            let panel = NSPanel(contentRect: box, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            panel.isReleasedWhenClosed = false
            panel.contentView = scroll
            panel.alphaValue = 0.01
            panel.ignoresMouseEvents = true
            panel.orderBack(nil)
            defer { panel.orderOut(nil); panel.close() }
            func move(_ y: CGFloat) {
                scroll.contentView.scroll(to: NSPoint(x: 0, y: y))
                scroll.reflectScrolledClipView(scroll.contentView)
            }
            func wheel(_ value: Int32) async throws {
                let cg = try #require(CGEvent(scrollWheelEvent2Source: nil, units: unit, wheelCount: 1,
                                              wheel1: value, wheel2: 0, wheel3: 0))
                // Address the real NSScrollView in this panel directly. Desktop hit
                // testing can deliver to an unrelated window during concurrent tests.
                let before = scroll.documentVisibleRect.minY
                scroll.scrollWheel(with: try #require(NSEvent(cgEvent: cg)))
                let distance = CGFloat(value) * (unit == .line ? scroll.verticalLineScroll : 1)
                let target = max(0, min(scroll.transcriptView.bounds.height - scroll.contentSize.height, before - distance))
                try await waitForWheel { abs(scroll.documentVisibleRect.minY - target) < 0.01 }
            }
            scroll.updateDocument(.init(entries: Array(rows.suffix(64)), older: true))
            scroll.layoutSubtreeIfNeeded()
            var requests: [Bool] = []
            scroll.onPage = { requests.append($0) }
            move(100)
            try await wheel(delta)
            let interior = 100 - scroll.documentVisibleRect.minY
            #expect(interior > 2 && requests.isEmpty)
            // A separate programmatic adjustment must not replay the previous wheel direction.
            move(2)
            #expect(requests.isEmpty)
            try await wheel(delta)
            #expect(requests == [true])
            #expect(scroll.documentVisibleRect.minY == 0)
            if reverse { try await wheel(-1) }
            let edgeOffset = scroll.documentVisibleRect.minY
            scroll.updateDocument(.init(entries: Array(rows.prefix(64)), newer: true))
            let span = try #require(scroll.rendered.spans.first { $0.entry.id == rows[32].id })
            let manager = try #require(scroll.transcriptView.layoutManager)
            let glyph = manager.glyphIndexForCharacter(at: span.range.location)
            let lineY = manager.lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil).minY
            let expected = lineY + edgeOffset - (reverse ? 0 : interior - 2)
            try await waitForWheel { abs(scroll.documentVisibleRect.minY - expected) <= 0.5 }
            #expect(!scroll.isFollowingLatest && requests == [true])
        }
    }
}
