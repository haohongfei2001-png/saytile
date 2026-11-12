import AppKit
import Testing
@testable import SaytileVoiceUI

@MainActor @Suite struct ReaderRevisionTests {
    struct Row: VoiceTranscriptEntry {
        let id = UUID()
        let position: Int64
        var displayText: String
    }

    @Test func historicalRevisionBeforeTheVisiblePassageKeepsItsOriginalLineBreaks() throws {
        _ = NSApplication.shared
        let scroll = CompactTranscriptScrollView<Row>(frame: NSRect(x: 0, y: 0, width: 162, height: 80))
        let window = NSPanel(contentRect: scroll.bounds, styleMask: [.borderless, .nonactivatingPanel],
                             backing: .buffered, defer: false)
        window.contentView = scroll
        window.isReleasedWhenClosed = false
        window.orderBack(nil)
        defer { window.orderOut(nil); window.close() }
        var rows = (0..<64).map { Row(position: Int64($0), displayText: "第\($0)天继续讲话。") }
        scroll.updateDocument(.init(entries: rows))
        scroll.layoutSubtreeIfNeeded()
        let manager = try #require(scroll.transcriptView.layoutManager)
        let container = try #require(scroll.transcriptView.textContainer)
        func glyph(_ character: Int) -> NSRect {
            manager.boundingRect(forGlyphRange: NSRange(location: manager.glyphIndexForCharacter(at: character), length: 1), in: container)
        }
        let middle = scroll.rendered.spans[30]
        scroll.contentView.scroll(to: NSPoint(x: 0, y: glyph(middle.range.location).minY))
        scroll.reflectScrolledClipView(scroll.contentView)
        #expect(!scroll.isFollowingLatest)
        func samples() -> [Int: NSPoint] {
            let origin = scroll.transcriptView.textContainerOrigin, clip = scroll.documentVisibleRect
            var points: [Int: NSPoint] = [:]
            for span in scroll.rendered.spans where (27...37).contains(span.entry.position) {
                for offset in 0..<span.range.length {
                    let r = glyph(span.range.location + offset)
                    let y = r.midY + origin.y - clip.minY
                    if y >= 0, y < clip.height {
                        points[Int(span.entry.position)*100+offset] = NSPoint(x: r.minX + origin.x, y: y)
                    }
                }
            }
            return points
        }
        let before = samples()
        rows[4].displayText += "修正"
        scroll.updateDocument(.init(entries: rows))
        let after = samples()
        let shared = before.keys.filter { after[$0] != nil }
        let maxX = shared.map { abs(before[$0]!.x - after[$0]!.x) }.max() ?? .infinity
        let maxY = shared.map { abs(before[$0]!.y - after[$0]!.y) }.max() ?? .infinity
        print("READER_EARLIER_REVISION retained=\(shared.count)/\(before.count) dx=\(maxX) dy=\(maxY)")
        #expect(before.count > 12 && shared.count == before.count)
        #expect(maxX <= 1 && maxY <= 1)
    }
}
