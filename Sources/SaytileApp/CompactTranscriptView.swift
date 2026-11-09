import AppKit
import SwiftUI

/// One selectable transcript. Model revisions never make this view first responder.
struct CompactTranscriptView: NSViewRepresentable {
    let document: PanelTimelineDocument
    let access: PanelTranscriptAccess
    var onPage: (Bool) -> Void
    var focusPosition: Int64?
    var editing = false
    var latestRequest = 0
    var onFollowChange: (Bool) -> Void = { _ in }
    var onSelectionChange: (String) -> Void = { _ in }
    var fillContextMenu: (@MainActor (NSMenu) -> Void)? = nil

    var showsLiveCaret = false

    func makeNSView(context: Context) -> CompactTranscriptScrollView {
        CompactTranscriptScrollView(frame: .zero)
    }
    func updateNSView(_ view: CompactTranscriptScrollView, context: Context) {
        view.onFollowChange = onFollowChange
        view.onSelectionChange = onSelectionChange
        view.transcriptView.fillContextMenu = fillContextMenu
        view.transcriptView.showsLiveCaret = showsLiveCaret && view.isFollowingLatest && !document.idle && !editing
        access.view = view
        view.onPage = onPage
        view.editing = editing
        view.updateDocument(document)
        view.focus(on: focusPosition)
        view.consumeLatestRequest(latestRequest)
    }
}

@MainActor
final class CompactTranscriptScrollView: NSScrollView, NSTextViewDelegate {
    let transcriptView = CompactTranscriptTextView(frame: .zero)
    private(set) var isFollowingLatest = true
    private(set) var latestText = ""
    var hasDeferredUpdate: Bool { !Self.sameText(transcriptView.string, latestText) }
    var onFollowChange: (Bool) -> Void = { _ in }
    var onSelectionChange: (String) -> Void = { _ in }

    private(set) var rendered = PanelTimelineDocument()
    private var pending = PanelTimelineDocument()
    var onPage: (Bool) -> Void = { _ in }
    var editing = false
    private var focusedPosition: Int64?
    private var motion: Task<Void, Never>?
    private var pagingFrom: Int64?
    var selectionSnapshot: String {
        let range = transcriptView.selectedRange(), string = transcriptView.string as NSString
        return NSMaxRange(range) <= string.length ? string.substring(with: range) : ""
    }
    func focus(on position: Int64?) {
        guard let position else { focusedPosition = nil; return }
        guard focusedPosition != position, let span = rendered.spans.first(where: { $0.entry.position == position }) else { return }
        focusedPosition = position
        isFollowingLatest = false
        transcriptView.scrollRangeToVisible(NSRange(location: span.range.location, length: 1))
        publishState()
    }
    func updateDocument(_ document: PanelTimelineDocument) {
        if editing || selecting || transcriptView.selectedRange().length > 0 { motion?.cancel() }
        pending = document
        latestText = document.text
        applyLatest()
    }
    private var lastManagedOrigin: NSPoint?
    private var wheelDirection: Bool?
    private var changingDocument = false
    private var selecting = false
    private var notificationScheduled = false
    private var latestRequest = 0
    private var lastLayoutSize = NSSize.zero

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        borderType = .noBorder
        drawsBackground = false
        hasVerticalScroller = true
        hasHorizontalScroller = false
        autohidesScrollers = true
        scrollerStyle = .overlay
        transcriptView.isEditable = false
        transcriptView.isSelectable = true
        transcriptView.isRichText = false
        transcriptView.importsGraphics = false
        transcriptView.drawsBackground = false
        // TextKit lays out glyphs; this scroll view owns document height,
        // including the empty viewport after the last spoken word.
        transcriptView.isVerticallyResizable = false
        transcriptView.isHorizontallyResizable = false
        transcriptView.autoresizingMask = [.width]
        transcriptView.minSize = .zero
        transcriptView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        transcriptView.textContainerInset = NSSize(width: 2, height: 6)
        transcriptView.textContainer?.widthTracksTextView = true
        transcriptView.textContainer?.heightTracksTextView = false
        transcriptView.textContainer?.containerSize = NSSize(width: max(1, contentSize.width), height: CGFloat.greatestFiniteMagnitude)
        transcriptView.textContainer?.lineFragmentPadding = 0
        transcriptView.delegate = self
        transcriptView.setAccessibilityIdentifier("panel.transcript")
        transcriptView.setAccessibilityLabel("当前转写文字")
        transcriptView.onSelectionTracking = { [weak self] tracking in
            guard let self else { return }
            selecting = tracking
            if tracking { motion?.cancel(); isFollowingLatest = false; publishState() }
            else if transcriptView.selectedRange().length == 0 { applyLatest() }
        }
        documentView = transcriptView
        contentView.postsBoundsChangedNotifications = true
        NotificationCenter.default.addObserver(self, selector: #selector(viewportChanged), name: NSView.boundsDidChangeNotification, object: contentView)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layout() {
        super.layout()
        let size = contentSize
        guard !changingDocument, size.width > 0, size.height > 0, size != lastLayoutSize else { return }
        lastLayoutSize = size
        let origin = contentView.bounds.origin
        changingDocument = true
        ensureDocumentLayout()
        if isFollowingLatest, !editing, !selecting, transcriptView.selectedRange().length == 0 { scrollToLatest() }
        else { scroll(to: origin) }
        changingDocument = false
    }

    func consumeLatestRequest(_ request: Int) {
        guard request != latestRequest else { return }
        latestRequest = request
        wheelDirection = nil
        jumpToLatest()
    }

    func jumpToLatest() {
        changingDocument = true
        transcriptView.setSelectedRange(NSRange(location: transcriptView.string.utf16.count, length: 0))
        changingDocument = false
        isFollowingLatest = true
        applyLatest()
        scrollToLatest()
        publishState()
    }

    func textViewDidChangeSelection(_ notification: Notification) {
        guard !changingDocument else { return }
        if transcriptView.selectedRange().length > 0 { motion?.cancel(); isFollowingLatest = false }
        else if !selecting { applyLatest() }
        publishState()
    }

    override func scrollWheel(with event: NSEvent) {
        motion?.cancel()
        let delta = event.scrollingDeltaY
        if delta != 0 {
            wheelDirection = delta > 0
            if delta > 0 { isFollowingLatest = false; publishState() }
            requestAdjacentPage(older: delta > 0)
        }
        super.scrollWheel(with: event)
        if delta != 0 { requestAdjacentPage(older: delta > 0) }
    }

    private func requestAdjacentPage(older: Bool) {
        guard !selecting, !editing, transcriptView.selectedRange().length == 0 else { return }
        let edge = older ? rendered.firstPosition : rendered.lastPosition
        guard let edge, pagingFrom != edge,
              older ? (rendered.older && documentVisibleRect.minY < 32) : (rendered.newer && isAtBottom) else { return }
        pagingFrom = edge
        isFollowingLatest = false
        onPage(older)
    }

    @objc private func viewportChanged(_ notification: Notification) {
        guard !changingDocument, !selecting, contentSize == lastLayoutSize else { return }
        // AppKit can publish our own bounds change on a later run-loop turn.
        guard contentView.bounds.origin != lastManagedOrigin else { return }
        lastManagedOrigin = nil
        if !editing, transcriptView.selectedRange().length == 0, isAtBottom, !rendered.newer {
            isFollowingLatest = true
            if hasDeferredUpdate { applyLatest() }
        } else { isFollowingLatest = false }
        if let older = wheelDirection { requestAdjacentPage(older: older) }
        if let event = NSApp.currentEvent, event.type == .leftMouseDragged || event.type == .leftMouseUp {
            requestAdjacentPage(older: !isAtBottom)
        }
        publishState()
    }

    private var isAtBottom: Bool {
        // A small deliberate upward scroll is still a reading choice. Only
        // floating-point rounding at the actual edge may count as the bottom;
        // a visible near-bottom band would silently resume live following.
        let bottom = transcriptView.bounds.maxY
        let rounding = max(1, abs(bottom)) * CGFloat.ulpOfOne * 8
        return documentVisibleRect.maxY >= bottom - rounding
    }

    private var attributes: [NSAttributedString.Key: Any] {
        let paragraph = NSMutableParagraphStyle()
        paragraph.minimumLineHeight = ReferencePanelStyle.lineHeight
        paragraph.maximumLineHeight = ReferencePanelStyle.lineHeight
        paragraph.paragraphSpacing = 0
        let base = NSFont(name: "PingFangSC-Regular", size: ReferencePanelStyle.fontSize) ?? NSFont.systemFont(ofSize: ReferencePanelStyle.fontSize)
        let font = base
        return [.font: font, .foregroundColor: ReferencePanelStyle.ink, .paragraphStyle: paragraph]
    }

    private struct ReadingAnchor {
        let character: Int
        let offset: CGFloat
    }
    private func readingAnchor() -> ReadingAnchor? {
        guard let manager = transcriptView.layoutManager, let container = transcriptView.textContainer,
              manager.numberOfGlyphs > 0 else { return nil }
        let point = NSPoint(x: 0, y: max(0, documentVisibleRect.minY - transcriptView.textContainerInset.height))
        let glyph = min(manager.numberOfGlyphs - 1, manager.glyphIndex(for: point, in: container))
        let rectangle = manager.boundingRect(forGlyphRange: NSRange(location: glyph, length: 1), in: container)
        return ReadingAnchor(character: manager.characterIndexForGlyph(at: glyph),
                             offset: documentVisibleRect.minY - rectangle.minY - transcriptView.textContainerInset.height)
    }

    private func applyLatest() {
        guard !changingDocument, !selecting, !editing, transcriptView.selectedRange().length == 0,
              pending != rendered || !Self.sameText(latestText, transcriptView.string), let storage = transcriptView.textStorage else { return }
        let old = transcriptView.string as NSString, new = latestText as NSString
        let patch = Self.patch(from: old, to: new)
        let oldCaret = transcriptView.selectedRange().location
        let anchor = isFollowingLatest ? nil : readingAnchor()
        let oldOrigin = contentView.bounds.origin
        let oldDocument = rendered
        let anchoredSpan = anchor.flatMap { a in oldDocument.spans.first { NSMaxRange($0.range) > a.character } }
        let enteringIdle = pending.idle && !rendered.idle && !rendered.spans.isEmpty
        if oldDocument.firstPosition != pending.firstPosition ||
            oldDocument.lastPosition != pending.lastPosition { pagingFrom = nil }
        rendered = pending
        motion?.cancel()
        changingDocument = true
        storage.replaceCharacters(in: patch.range, with: NSAttributedString(string: patch.replacement, attributes: attributes))
        if oldDocument.markers != rendered.markers || !rendered.markers.isEmpty {
            storage.setAttributes(attributes, range: NSRange(location: 0, length: new.length))
            for marker in rendered.markers {
                storage.addAttributes([.font: NSFont.systemFont(ofSize: 10), .foregroundColor: NSColor.secondaryLabelColor], range: marker)
            }
        }
        let caret = min(new.length, Self.shift(oldCaret, through: patch.range, replacementLength: patch.replacement.utf16.count))
        transcriptView.setSelectedRange(NSRange(location: caret, length: 0))
        ensureDocumentLayout()
        if isFollowingLatest {
            if enteringIdle && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
                let start = oldOrigin.y
                let end = max(0, transcriptView.bounds.height - contentSize.height)
                motion = Task { @MainActor [weak self] in
                    for step in 1...12 {
                        do { try await Task.sleep(for: .milliseconds(16)) } catch { return }
                        guard let self, self.isFollowingLatest, !self.editing, !self.selecting,
                              self.transcriptView.selectedRange().length == 0 else { return }
                        let progress = CGFloat(step) / 12
                        self.changingDocument = true
                        self.scroll(to: NSPoint(x: 0, y: start + (end - start) * progress * (2 - progress)))
                        self.changingDocument = false
                    }
                }
            } else { scrollToLatest() }
        }
        else if let anchor, let manager = transcriptView.layoutManager, let container = transcriptView.textContainer, new.length > 0 {
            var adjusted = Self.shift(anchor.character, through: patch.range, replacementLength: patch.replacement.utf16.count, rightAffinity: true)
            if let previous = anchoredSpan, let next = rendered.spans.first(where: { $0.entry.id == previous.entry.id }),
               anchor.character >= previous.range.location {
                let local = Self.patch(from: previous.entry.recording.text as NSString, to: next.entry.recording.text as NSString)
                adjusted = next.range.location + Self.shift(anchor.character - previous.range.location, through: local.range,
                    replacementLength: local.replacement.utf16.count, rightAffinity: true)
            }
            let position = min(new.length - 1, adjusted)
            let glyph = manager.glyphIndexForCharacter(at: position)
            let rect = manager.boundingRect(forGlyphRange: NSRange(location: glyph, length: 1), in: container)
            scroll(to: NSPoint(x: oldOrigin.x, y: rect.minY + transcriptView.textContainerInset.height + anchor.offset))
        } else { scroll(to: oldOrigin) }
        changingDocument = false
        publishState()
    }

    private func ensureDocumentLayout() {
        let width = max(1, contentSize.width)
        transcriptView.setFrameSize(NSSize(width: width, height: max(contentSize.height, transcriptView.frame.height)))
        guard let manager = transcriptView.layoutManager, let container = transcriptView.textContainer else { return }
        manager.ensureLayout(for: container)
        var height = ceil(manager.usedRect(for: container).maxY + transcriptView.textContainerInset.height * 2)
        if !rendered.text.isEmpty {
            if rendered.idle || rendered.activeStart == rendered.text.utf16.count {
                height += contentSize.height
            } else if let start = rendered.activeStart, start > 0 {
                let glyph = manager.glyphIndexForCharacter(at: start)
                height = max(height, manager.lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil).minY + contentSize.height)
            }
        }
        transcriptView.setFrameSize(NSSize(width: width, height: max(contentSize.height, height)))
    }
    private func scrollToLatest() {
        let wasChanging = changingDocument
        changingDocument = true
        ensureDocumentLayout()
        scroll(to: NSPoint(x: 0, y: max(0, transcriptView.bounds.height - contentSize.height)))
        changingDocument = wasChanging
    }
    private func scroll(to point: NSPoint) {
        let maximum = max(0, transcriptView.bounds.height - contentSize.height)
        contentView.scroll(to: NSPoint(x: 0, y: min(maximum, max(0, point.y))))
        reflectScrolledClipView(contentView)
        lastManagedOrigin = contentView.bounds.origin
    }

    private func publishState() {
        guard !notificationScheduled else { return }
        notificationScheduled = true
        // NSViewRepresentable updates may originate inside a SwiftUI render pass.
        // Publish once on the next main-actor turn instead of changing View state in it.
        Task { @MainActor [weak self] in
            guard let self else { return }
            notificationScheduled = false
            onFollowChange(isFollowingLatest)
            let range = transcriptView.selectedRange(), text = transcriptView.string as NSString
            onSelectionChange(range.location <= text.length && NSMaxRange(range) <= text.length ? text.substring(with: range) : "")
        }
    }

    // Swift String equality normalizes canonically equivalent text. The displayed
    // bytes/UTF-16 ranges must still match the actual persisted transcript.
    private static func sameText(_ lhs: String, _ rhs: String) -> Bool {
        lhs.utf16.elementsEqual(rhs.utf16)
    }

    private static func shift(_ position: Int, through range: NSRange, replacementLength: Int, rightAffinity: Bool = false) -> Int {
        if rightAffinity, range.length == 0, position == range.location { return position + replacementLength }
        if position <= range.location { return position }
        if position >= NSMaxRange(range) { return position + replacementLength - range.length }
        return range.location + replacementLength
    }
    /// Keep the unchanged UTF-16 prefix/suffix in the same text storage. If a
    /// boundary falls inside a composed character, widen the patch, never split it.
    private static func patch(from old: NSString, to new: NSString) -> (range: NSRange, replacement: String) {
        var prefix = 0
        while prefix < min(old.length, new.length), old.character(at: prefix) == new.character(at: prefix) { prefix += 1 }
        let oldStart = prefix < old.length ? old.rangeOfComposedCharacterSequence(at: prefix).location : prefix
        let newStart = prefix < new.length ? new.rangeOfComposedCharacterSequence(at: prefix).location : prefix
        prefix = min(oldStart, newStart)
        var suffix = 0
        while suffix < min(old.length - prefix, new.length - prefix),
              old.character(at: old.length - suffix - 1) == new.character(at: new.length - suffix - 1) { suffix += 1 }
        let oldEnd = old.length - suffix, newEnd = new.length - suffix
        if (oldEnd < old.length && old.rangeOfComposedCharacterSequence(at: oldEnd).location != oldEnd) ||
           (newEnd < new.length && new.rangeOfComposedCharacterSequence(at: newEnd).location != newEnd) { suffix = 0 }
        return (NSRange(location: prefix, length: old.length - prefix - suffix),
                new.substring(with: NSRange(location: prefix, length: new.length - prefix - suffix)))
    }
}

@MainActor
final class CompactTranscriptTextView: NSTextView, NSMenuDelegate {
    // A read-only trailing voice caret: no editing, focus acquisition, timer or
    // insertion. Selection and reading earlier text suppress it.
    var showsLiveCaret = false { didSet { if oldValue != showsLiveCaret { needsDisplay = true } } }
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard showsLiveCaret, selectedRange().length == 0, !string.isEmpty,
              let manager = layoutManager, let container = textContainer,
              manager.numberOfGlyphs > 0 else { return }
        let end = manager.numberOfGlyphs - 1
        let glyph = manager.boundingRect(forGlyphRange: NSRange(location: end, length: 1), in: container)
        let line = manager.lineFragmentRect(forGlyphAt: end, effectiveRange: nil)
        let origin = textContainerOrigin
        let font = textStorage?.attribute(.font, at: max(0, string.utf16.count - 1), effectiveRange: nil) as? NSFont
        let ink = font?.boundingRect(forGlyph: manager.glyph(at: end))
        let inkEnd = ink.map { line.minX + manager.location(forGlyphAt: end).x + $0.maxX } ?? glyph.maxX
        let rect = CGRect(x: origin.x + inkEnd + 9,
                          y: origin.y + line.minY + 3, width: 2.5, height: 19)
        guard rect.maxX < bounds.maxX - 1 else { return }
        NSColor(srgbRed: 0.55, green: 0.23, blue: 0.98, alpha: 1).setFill()
        NSBezierPath(roundedRect: rect, xRadius: 1.25, yRadius: 1.25).fill()
    }
    private let transcriptMenu = NSMenu(title: "文字操作")
    var fillContextMenu: (@MainActor (NSMenu) -> Void)? {
        didSet {
            if fillContextMenu != nil, menu !== transcriptMenu {
                transcriptMenu.autoenablesItems = false
                transcriptMenu.delegate = self
                menu = transcriptMenu
            } else if fillContextMenu == nil, menu === transcriptMenu { menu = nil }
        }
    }
    override func menu(for event: NSEvent) -> NSMenu? {
        contextCharacter = characterIndexForInsertion(at: convert(event.locationInWindow, from: nil))
        return fillContextMenu != nil ? transcriptMenu : super.menu(for: event)
    }
    func menuNeedsUpdate(_ menu: NSMenu) {
        guard menu === transcriptMenu, let fillContextMenu else { return }
        menu.removeAllItems()
        fillContextMenu(menu)
    }
    private(set) var contextCharacter: Int?
    var onSelectionTracking: (Bool) -> Void = { _ in }
    override func mouseDown(with event: NSEvent) {
        onSelectionTracking(true)
        super.mouseDown(with: event)
        onSelectionTracking(false)
    }
}

/// Each menu owns its action items until AppKit finishes dispatch. No global
/// key equivalents or focus changes are required to invoke these commands.
@MainActor
final class TranscriptMenuItem: NSMenuItem {
    private let invoke: @MainActor () -> Void
    init(title: String, identifier: String, action: @escaping @MainActor () -> Void) {
        invoke = action
        super.init(title: title, action: #selector(performCommand), keyEquivalent: "")
        self.identifier = .init(identifier); setAccessibilityIdentifier(identifier)
        target = self
    }
    required init(coder: NSCoder) { fatalError("TranscriptMenuItem is created programmatically") }
    @objc private func performCommand() { invoke() }
}
