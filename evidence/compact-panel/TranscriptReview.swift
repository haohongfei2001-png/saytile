import AppKit
import Foundation

@main struct TranscriptReview {
    @MainActor static func main() throws {
        NSApplication.shared.setActivationPolicy(.prohibited)
        let view = CompactTranscriptScrollView(frame: NSRect(x: 0, y: 0, width: 314, height: 150))
        view.layoutSubtreeIfNeeded()
        let cases: [(String, String)] = [
            ("否定：不要支付15元。", "否定：不要支付50元。"),
            ("A😀Z", "A😄Z"),
            ("cafe\u{301}", "café"),
            ("x👨‍👩‍👧‍👦y", "x👨‍👩‍👦y"),
            ("👍🏻，完成", "👍🏽，完成"),
            ("a\u{301}中b", "a\u{302}中b"),
            ("新增😀内容", ""),
            ("", "English 中文 😀 15kg"),
            ("👩‍💻文本", "👩文本"),
            ("前缀🇨🇳后缀", "前缀🇬🇧后缀")
        ]
        var count = 0
        for (before, after) in cases {
            view.updateTranscript(before)
            let storage = view.transcriptView.textStorage!
            view.updateTranscript(after)
            guard view.transcriptView.string.utf8.elementsEqual(after.utf8),
                  view.transcriptView.textStorage === storage,
                  view.transcriptView.selectedRange().location <= after.utf16.count else {
                throw NSError(domain: "TranscriptReview", code: 1, userInfo: [NSLocalizedDescriptionKey: "Exact Unicode update or text-storage identity failed in case \(count)"])
            }
            count += 1
        }
        view.updateTranscript("选中 😀 不要支付15元。")
        view.transcriptView.setSelectedRange(NSRange(location: 6, length: 8))
        let selected = view.transcriptView.selectedRange(), held = view.transcriptView.string
        view.updateTranscript("新的实时文字和完全变化的表达。")
        guard view.transcriptView.string == held, view.hasDeferredUpdate,
              view.transcriptView.selectedRange() == selected else { throw NSError(domain: "TranscriptReview", code: 2) }
        view.jumpToLatest()
        guard view.transcriptView.string == "新的实时文字和完全变化的表达。", !view.hasDeferredUpdate,
              view.transcriptView.selectedRange().length == 0, view.isFollowingLatest else { throw NSError(domain: "TranscriptReview", code: 3) }
        view.updateTranscript("cafe\u{301}")
        view.transcriptView.setSelectedRange(NSRange(location: 0, length: 5))
        view.updateTranscript("café")
        guard view.hasDeferredUpdate, view.transcriptView.string.utf16.count == 5 else { throw NSError(domain: "TranscriptReview", code: 4) }
        view.jumpToLatest()
        guard !view.hasDeferredUpdate, view.transcriptView.string.utf16.count == 4 else { throw NSError(domain: "TranscriptReview", code: 5) }
        view.transcriptView.setSelectedRange(NSRange(location: 0, length: 4))
        view.updateTranscript("")
        guard view.hasDeferredUpdate else { throw NSError(domain: "TranscriptReview", code: 6) }
        view.jumpToLatest()
        guard view.transcriptView.string.isEmpty, view.transcriptView.selectedRange() == NSRange(location: 0, length: 0) else { throw NSError(domain: "TranscriptReview", code: 7) }

        let lines = (0..<70).map { "第\($0 + 1)行：中文 English 😀，不要支付15元。" }.joined(separator: "\n")
        view.updateTranscript(lines)
        view.layoutSubtreeIfNeeded()
        view.contentView.scroll(to: NSPoint(x: 0, y: 120))
        view.reflectScrolledClipView(view.contentView)
        guard !view.isFollowingLatest else { throw NSError(domain: "TranscriptReview", code: 8) }
        let origin = view.contentView.bounds.origin
        let appended = lines + "\n继续表达。"
        view.updateTranscript(appended)
        guard !view.isFollowingLatest, abs(view.contentView.bounds.origin.y - origin.y) < 1 else { throw NSError(domain: "TranscriptReview", code: 9) }
        let layout = view.transcriptView.layoutManager!, container = view.transcriptView.textContainer!
        func visibleCharacter() -> Int {
            let point = NSPoint(x: 0, y: view.documentVisibleRect.minY - view.transcriptView.textContainerInset.height)
            return layout.characterIndexForGlyph(at: layout.glyphIndex(for: point, in: container))
        }
        let beforeCharacter = visibleCharacter(), prefix = "新增开头😀：不应移动正在阅读的文字。\n"
        view.updateTranscript(prefix + appended)
        guard !view.isFollowingLatest, visibleCharacter() == beforeCharacter + prefix.utf16.count else { throw NSError(domain: "TranscriptReview", code: 10) }
        print("PASS exact_unicode_updates=\(count) selection_defer_and_release=1 selected_normalization=1 selected_clear=1 manual_scroll_append=1 prepend_reading_anchor=1 same_text_storage=true window_created=false app_active=\(NSApp.isActive)")
    }
}
