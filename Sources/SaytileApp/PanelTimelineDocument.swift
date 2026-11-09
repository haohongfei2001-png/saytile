import AppKit
import SaytileKit

/// Only the current SQLite window has TextKit glyphs. Positions identify
/// the same utterance across overlapping windows and later revisions.
struct PanelTimelineDocument: Equatable {
    struct Span: Equatable {
        let entry: TimelineEntry
        let range: NSRange
    }
    var text = ""
    var spans: [Span] = []
    var markers: [NSRange] = []
    var copyTail: TimelineEntry?
    var activeStart: Int?
    var idle = false
    var firstPosition: Int64?
    var lastPosition: Int64?
    var older = false
    var newer = false

    init() {}
    init(page: TimelinePage, tail: TimelineEntry?, idle: Bool, reading: Bool) {
        self.idle = idle && !page.hasNewer
        copyTail = tail
        firstPosition = page.entries.first?.position
        lastPosition = page.entries.last?.position
        older = page.hasOlder
        newer = page.hasNewer
        let content = NSMutableString(capacity: 256)
        var group: Int64?, day: String?
        for row in page.entries where !row.recording.text.isEmpty {
            if content.length > 0 { content.append("\n") }
            if group != row.group {
                if !reading && row.group == tail?.group && content.length > 0 {
                    // Optical inset above live text must not expose the last glyphs of history.
                    content.append("\n")
                }
                if reading || row.group != tail?.group {
                    let start = content.length
                    let offset = Double(row.groupUTCOffset)
                    let second = (Int(floor(row.groupStart.timeIntervalSince1970 + offset)) % 86400 + 86400) % 86400
                    let time = String(format: "%02d:%02d", second / 3600, second / 60 % 60)
                    content.append((day != row.groupDay ? row.groupDay + "  " : "") + time)
                    markers.append(NSRange(location: start, length: content.length - start))
                    content.append("\n")
                }
                group = row.group
                day = row.groupDay
                if group == tail?.group { activeStart = content.length }
            }
            let start = content.length
            content.append(row.recording.text)
            spans.append(Span(entry: row, range: NSRange(location: start, length: content.length - start)))
        }
        // A new utterance can arrive before the first recognition result.
        if activeStart == nil && !page.hasNewer { activeStart = content.length }
        text = content as String
    }
}
@MainActor final class PanelTranscriptAccess: ObservableObject {
    weak var view: CompactTranscriptScrollView?
}
