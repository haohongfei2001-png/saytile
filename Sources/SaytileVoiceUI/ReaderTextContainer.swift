import AppKit
import os

/// Preserves an existing soft wrap where two bounded history windows overlap.
/// This is a typesetting constraint only: storage, selection, the clipboard and
/// accessibility contain precisely the original text, with no inserted controls.
@MainActor
final class ReaderTextContainer: NSTextContainer {
    // AppKit declares its typesetting callback nonisolated. Share immutable
    // snapshots and never hold the lock across a TextKit call.
    private nonisolated let lineStarts = OSAllocatedUnfairLock(initialState: [Int]())
    var wraps: [Int] { lineStarts.withLock { $0 } }

    func preserve(_ starts: [Int]) {
        let next = Array(Set(starts.filter { $0 > 0 })).sorted()
        guard next != wraps else { return }
        lineStarts.withLock { $0 = next }
        if let manager = layoutManager, let storage = manager.textStorage {
            manager.invalidateLayout(forCharacterRange: NSRange(location: 0, length: storage.length), actualCharacterRange: nil)
        }
    }

    override func lineFragmentRect(forProposedRect proposed: NSRect, at index: Int,
                                   writingDirection direction: NSWritingDirection,
                                   remaining: UnsafeMutablePointer<NSRect>?) -> NSRect {
        var rect = super.lineFragmentRect(forProposedRect: proposed, at: index, writingDirection: direction, remaining: remaining)
        guard let stop = lineStarts.withLock({ $0.first(where: { $0 > index }) }), let storage = layoutManager?.textStorage,
              stop <= storage.length, rect.width > 1 else { return rect }
        // A distant boundary need not be measured. Even if a tiny/combining
        // glyph run spans the lookahead, measure the prefix before deciding.
        let length = min(stop - index, 128)
        var width = storage.attributedSubstring(from: NSRange(location: index, length: length)).size().width
        if length < stop - index {
            guard width < rect.width else { return rect }
            width = storage.attributedSubstring(from: NSRange(location: index, length: stop-index)).size().width
        }
        if width < rect.width {
            rect.size.width = min(rect.width, max(1, width + 0.0625))
        }
        return rect
    }
}
