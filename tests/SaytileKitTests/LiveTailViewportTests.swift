import AppKit
import Testing
@testable import SaytileVoiceUI

@Suite @MainActor struct LiveTailViewportTests {
    private struct Row: VoiceTranscriptEntry {
        let id = UUID()
        let position: Int64 = 1
        var displayText: String
    }

    @Test func wrappingAndReadingInANativePanel() async throws {
        _ = NSApplication.shared
        let box = NSRect(x: 0, y: 0, width: 185, height: 95)
        let scroll = CompactTranscriptScrollView<Row>(frame: box)
        let panel = NSPanel(contentRect: box, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isReleasedWhenClosed = false
        panel.contentView = scroll
        panel.alphaValue = 0.01
        panel.ignoresMouseEvents = true
        panel.orderBack(nil)
        defer { panel.orderOut(nil); panel.close() }
        var row = Row(displayText: String(repeating: "屏幕上有一条连续的文字。", count: 20))
        scroll.updateDocument(.init(entries: [row]))
        scroll.layoutSubtreeIfNeeded()
        scroll.jumpToLatest()
        scroll.transcriptView.showsLiveCaret = true
        let originalText = row.displayText
        let initial = scroll.documentVisibleRect.minY
        row.displayText += "下一句话逐渐显示在同一份文本末尾。"
        scroll.updateDocument(.init(entries: [row]))
        let target = scroll.transcriptView.frame.height - scroll.contentSize.height
        #expect(target > initial)
        let atWrite = scroll.documentVisibleRect.minY
        var positions = [atWrite]
        var lostOwnership = !scroll.isFollowingLatest
        let deadline = ContinuousClock.now + .seconds(2)
        while positions.last! != target, ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(5))
            lostOwnership = lostOwnership || !scroll.isFollowingLatest
            positions.append(scroll.documentVisibleRect.minY)
        }
        let intermediate = Set(positions.filter { $0 > initial && $0 < target })
        print("LIVE_TAIL_NATIVE initial=\(initial) atWrite=\(atWrite) intermediate=\(intermediate.count) target=\(target) reached=\(positions.last!)")
        if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            #expect(atWrite == target)
        } else {
            #expect(atWrite == initial)
            #expect(intermediate.count >= 2)
        }
        #expect(zip(positions, positions.dropFirst()).allSatisfy { $0 <= $1 })
        #expect(positions.last == target)
        #expect(!lostOwnership && scroll.isFollowingLatest)
        #expect(scroll.transcriptView.string == row.displayText)

        row.displayText = originalText
        scroll.updateDocument(.init(entries: [row]))
        let beforeUnwrap = scroll.documentVisibleRect.minY
        if !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            #expect(beforeUnwrap == target)
        }
        let unwrapDeadline = ContinuousClock.now + .seconds(2)
        while scroll.documentVisibleRect.minY > initial, ContinuousClock.now < unwrapDeadline {
            try await Task.sleep(for: .milliseconds(5))
        }
        #expect(scroll.documentVisibleRect.minY == initial)
        #expect(scroll.transcriptView.bounds.height == initial + scroll.contentSize.height)
        row.displayText += "这一次折行时立即选中一小段文字。"
        scroll.updateDocument(.init(entries: [row]))
        scroll.transcriptView.setSelectedRange(NSRange(location: 10, length: 4))
        let selectionOrigin = scroll.documentVisibleRect.minY
        let selected = scroll.selectionSnapshot
        try await Task.sleep(for: .milliseconds(200))
        #expect(!selected.isEmpty && scroll.selectionSnapshot == selected)
        #expect(scroll.documentVisibleRect.minY == selectionOrigin)
        scroll.jumpToLatest()
        row.displayText += "再继续说一句，文字出现时允许向上回看。"
        scroll.updateDocument(.init(entries: [row]))
        scroll.contentView.scroll(to: NSPoint(x: 0, y: initial / 2))
        scroll.reflectScrolledClipView(scroll.contentView)
        let reading = scroll.documentVisibleRect.minY
        try await Task.sleep(for: .milliseconds(300))
        #expect(!scroll.isFollowingLatest)
        #expect(scroll.documentVisibleRect.minY == reading)
        row.displayText += "阅览过程中继续收录。"
        scroll.updateDocument(.init(entries: [row]))
        #expect(abs(scroll.documentVisibleRect.minY - reading) <= 1)
    }
}
