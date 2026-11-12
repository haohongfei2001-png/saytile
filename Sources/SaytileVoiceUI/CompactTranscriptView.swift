import AppKit
import SwiftUI

/// One selectable, inline-editable transcript. Model revisions never make this view first responder.
struct CompactTranscriptView<Entry: VoiceTranscriptEntry>: NSViewRepresentable {
    let document: PanelTimelineDocument<Entry>
    let access: PanelTranscriptAccess<Entry>
    var onPage: (Bool) -> Void
    var focusPosition: Int64?
    var editing = false
    var latestRequest = 0
    var onFollowChange: (Bool) -> Void = { _ in }
    var onSelectionChange: (String) -> Void = { _ in }
    var fillContextMenu: (@MainActor (NSMenu) -> Void)? = nil

    var applyEdits: (@MainActor ([VoicePanelEdit]) throws -> PanelTimelineDocument<Entry>)? = nil
    var onEdit: (@MainActor () -> Void)? = nil
    var showsLiveCaret = false
    var typeScale: CGFloat = 1

    func makeNSView(context: Context) -> CompactTranscriptScrollView<Entry> {
        CompactTranscriptScrollView<Entry>(frame: .zero)
    }
    func updateNSView(_ view: CompactTranscriptScrollView<Entry>, context: Context) {
        view.onFollowChange = onFollowChange
        view.onSelectionChange = onSelectionChange
        view.transcriptView.fillContextMenu = fillContextMenu
        view.transcriptView.showsLiveCaret = showsLiveCaret && view.isFollowingLatest && !document.idle && !editing
        access.view = view
        view.applyEdits = applyEdits
        view.transcriptView.isEditable = applyEdits != nil
        view.transcriptView.onEdit = onEdit
        view.onPage = onPage
        view.editing = editing
        view.applyTypeScale(typeScale)
        view.updateDocument(document)
        view.focus(on: focusPosition)
        view.consumeLatestRequest(latestRequest)
    }
}

@MainActor
public final class CompactTranscriptScrollView<Entry: VoiceTranscriptEntry>: NSScrollView, NSTextViewDelegate {
    public let transcriptView = CompactTranscriptTextView(frame: .zero)
    public private(set) var isFollowingLatest = true
    public private(set) var latestText = ""
    public var hasDeferredUpdate: Bool { !Self.sameText(transcriptView.string, latestText) }
    var onFollowChange: (Bool) -> Void = { _ in }
    var onSelectionChange: (String) -> Void = { _ in }

    public private(set) var rendered = PanelTimelineDocument<Entry>()
    private var pending = PanelTimelineDocument<Entry>()
    var onPage: (Bool) -> Void = { _ in }
    public internal(set) var editing = false
    var applyEdits: (@MainActor ([VoicePanelEdit]) throws -> PanelTimelineDocument<Entry>)?
    private var intendedEdit: (range: NSRange, replacement: String)?
    private var createRowFromIdle = false
    private var emptiedRow: (id: UUID, caret: Int)?
    private var focusedPosition: Int64?
    private var motion: Task<Void, Never>?
    private var pagingFrom: Int64?
    public var selectionSnapshot: String {
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
    func updateDocument(_ document: PanelTimelineDocument<Entry>) {
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

    public override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        borderType = .noBorder
        drawsBackground = false
        hasVerticalScroller = true
        verticalScroller = TranscriptScroller()
        hasHorizontalScroller = false
        autohidesScrollers = true
        scrollerStyle = NSScroller.preferredScrollerStyle
        transcriptView.isEditable = false
        transcriptView.isSelectable = true
        // Undo must carry row identities; AppKit raw UTF-16 inverses alone would
        // restore a cross-row cut into the wrong recording after an ASR update.
        transcriptView.allowsUndo = false
        transcriptView.isAutomaticTextReplacementEnabled = false
        transcriptView.isAutomaticDashSubstitutionEnabled = false
        transcriptView.isAutomaticQuoteSubstitutionEnabled = false
        transcriptView.typingAttributes = attributes
        transcriptView.compositionFinished = { [weak self] in self?.finishUserInput() }
        transcriptView.pointerDown = { [weak self] point in
            guard let self, let manager = transcriptView.layoutManager, let container = transcriptView.textContainer else { return }
            emptiedRow = nil
            createRowFromIdle = rendered.idle && point.y >= manager.usedRect(for: container).maxY + transcriptView.textContainerOrigin.y
        }
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
        transcriptView.onPageNavigation = { [weak self] older in
            guard let self else { return }
            motion?.cancel()
            wheelDirection = nil
            requestAdjacentPage(older: older)
        }
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
    public required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    public override func layout() {
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

    public func jumpToLatest() {
        changingDocument = true
        transcriptView.setSelectedRange(NSRange(location: transcriptView.string.utf16.count, length: 0))
        changingDocument = false
        isFollowingLatest = true
        applyLatest()
        scrollToLatest()
        publishState()
    }

    public func textView(_ textView: NSTextView, shouldChangeTextIn range: NSRange, replacementString: String?) -> Bool {
        guard !changingDocument, applyEdits != nil else { return false }
        if let replacementString, !transcriptView.hasMarkedText(),
           Self.sameText(rendered.text, textView.string) {
            intendedEdit = (range, replacementString)
        }
        motion?.cancel()
        return true
    }

    public func textDidChange(_ notification: Notification) { finishUserInput() }

    private func finishUserInput() {
        guard !changingDocument, !transcriptView.composing, !transcriptView.hasMarkedText(),
              let applyEdits else { return }
        let old = rendered.text as NSString, new = transcriptView.string
        guard !Self.sameText(rendered.text, new) else { intendedEdit = nil; return }
        let change: (range: NSRange, replacement: String)
        if let edit = intendedEdit, NSMaxRange(edit.range) <= old.length,
           Self.sameText(old.replacingCharacters(in: edit.range, with: edit.replacement), new) {
            change = edit
        } else {
            // Composition can span several native marked-text replacements.
            change = Self.patch(from: old, to: new as NSString)
        }
        intendedEdit = nil
        let edit: PanelTimelineDocument<Entry>.Edit?
        if let emptiedRow, change.range == NSRange(location: emptiedRow.caret, length: 0),
           !change.replacement.isEmpty, !rendered.spans.contains(where: { $0.entry.id == emptiedRow.id }) {
            edit = .init(rows: [.init(id: emptiedRow.id, before: "", after: change.replacement)],
                         anchor: emptiedRow.id, offset: change.replacement.utf16.count)
        } else {
            edit = rendered.edit(in: change.range, replacement: change.replacement, newRow: createRowFromIdle)
        }
        guard let edit else {
            showEdit(rendered, caret: change.range.location)
            return
        }
        do {
            // Persist each committed AppKit edit before displaying its new ranges.
            let document = edit.rows.isEmpty ? rendered : try applyEdits(edit.rows)
            let span = document.spans.first { $0.entry.id == edit.anchor }
            let caret = span.map { $0.range.location + min($0.range.length, edit.offset) } ?? change.range.location
            if !edit.rows.isEmpty { registerUndo(edit.rows, caret: change.range.location) }
            createRowFromIdle = false
            emptiedRow = span == nil && edit.rows.contains(where: { $0.id == edit.anchor && $0.after.isEmpty })
                ? (edit.anchor, min(caret, document.text.utf16.count)) : nil
            showEdit(document, caret: caret)
        } catch {
            // The host reports the error. Refuse the mutation atomically.
            showEdit(rendered, caret: change.range.location)
            NSSound.beep()
        }
    }

    private func registerUndo(_ applied: [VoicePanelEdit], caret: Int) {
        let inverse = applied.map { VoicePanelEdit(id: $0.id, before: $0.after, after: $0.before ?? "") }
        transcriptView.panelUndo.registerUndo(withTarget: self) { view in
            MainActor.assumeIsolated { view.performHistoryEdit(inverse, caret: caret) }
        }
        transcriptView.panelUndo.setActionName("编辑文字")
    }

    private func performHistoryEdit(_ edits: [VoicePanelEdit], caret: Int) {
        guard let applyEdits else { return }
        do {
            let previousCaret = transcriptView.selectedRange().location
            let document = try applyEdits(edits)
            registerUndo(edits, caret: previousCaret)
            showEdit(document, caret: caret)
        } catch { NSSound.beep() }
    }

    private func showEdit(_ document: PanelTimelineDocument<Entry>, caret: Int) {
        guard let storage = transcriptView.textStorage else { return }
        changingDocument = true
        rendered = document
        pending = document
        latestText = document.text
        let patch = Self.patch(from: transcriptView.string as NSString, to: document.text as NSString)
        storage.replaceCharacters(in: patch.range, with: patch.replacement)
        storage.setAttributes(attributes, range: NSRange(location: 0, length: storage.length))
        styleMarkers(in: storage)
        transcriptView.typingAttributes = attributes
        let selection = NSRange(location: min(storage.length, caret), length: 0)
        transcriptView.setSelectedRange(selection)
        ensureDocumentLayout()
        transcriptView.scrollRangeToVisible(selection)
        changingDocument = false
        publishState()
    }

    public func textViewDidChangeSelection(_ notification: Notification) {
        guard !changingDocument else { return }
        if let emptiedRow, transcriptView.selectedRange().location != emptiedRow.caret,
           Self.sameText(rendered.text, transcriptView.string) { self.emptiedRow = nil }
        if transcriptView.selectedRange().length > 0 { motion?.cancel(); isFollowingLatest = false }
        else if !selecting { applyLatest() }
        publishState()
    }

    public override func scrollWheel(with event: NSEvent) {
        motion?.cancel()
        let delta = event.scrollingDeltaY
        if delta != 0 {
            lastManagedOrigin = nil
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
        // Consume this wheel event at the boundary it requested. Layout
        // notifications from the new page cannot request a second page.
        wheelDirection = nil
        isFollowingLatest = false
        onPage(older)
    }

    @objc private func viewportChanged(_ notification: Notification) {
        guard !changingDocument, !selecting, contentSize == lastLayoutSize else { return }
        // AppKit may publish the aligned position on the next layout pass,
        // after our scroll returned its fractional origin. Only recognize the
        // adjacent backing-pixel boundary of that particular managed scroll.
        let origin = contentView.bounds.origin
        if let last = lastManagedOrigin {
            if origin == last { return }
            let scale = window?.backingScaleFactor ?? 1
            let prior = last.y * scale, current = origin.y * scale
            let rounding = max(1, abs(current)) * CGFloat.ulpOfOne * 8
            let tracking = NSEvent.pressedMouseButtons != 0
            if !tracking, origin.x == last.x, abs(prior - prior.rounded()) > rounding,
               abs(current - current.rounded()) <= rounding, abs(current - prior) < 1 {
                lastManagedOrigin = origin
                return
            }
        }
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

    private var typeScale: CGFloat = 1
    func applyTypeScale(_ scale: CGFloat) {
        guard typeScale != scale, !transcriptView.hasMarkedText() else { return }
        typeScale = scale
        transcriptView.textContainerInset = NSSize(width: 2, height: 6 * scale)
        if let storage = transcriptView.textStorage {
            storage.setAttributes(attributes, range: NSRange(location: 0, length: storage.length))
            styleMarkers(in: storage)
        }
        needsLayout = true
    }

    private func styleMarkers(in storage: NSTextStorage) {
        for marker in rendered.markers where NSMaxRange(marker) <= storage.length {
            storage.addAttributes([.font: NSFont.systemFont(ofSize: 10), .foregroundColor: NSColor.secondaryLabelColor], range: marker)
        }
    }

    private var attributes: [NSAttributedString.Key: Any] {
        let paragraph = NSMutableParagraphStyle()
        paragraph.minimumLineHeight = ReferencePanelStyle.lineHeight * typeScale
        paragraph.maximumLineHeight = ReferencePanelStyle.lineHeight * typeScale
        paragraph.paragraphSpacing = 0
        let base = NSFont(name: "PingFangSC-Regular", size: ReferencePanelStyle.fontSize * typeScale) ?? NSFont.systemFont(ofSize: ReferencePanelStyle.fontSize * typeScale)
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
        guard !changingDocument, !selecting, !editing,
              !transcriptView.composing, !transcriptView.hasMarkedText(),
              applyEdits == nil || Self.sameText(rendered.text, transcriptView.string),
              transcriptView.selectedRange().length == 0,
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
            styleMarkers(in: storage)
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
                let local = Self.patch(from: previous.entry.displayText as NSString, to: next.entry.displayText as NSString)
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
        if !rendered.text.isEmpty, rendered.text.utf16.count == transcriptView.string.utf16.count {
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
public final class CompactTranscriptTextView: NSTextView, NSMenuDelegate {
    let panelUndo = UndoManager()
    // NSTextStorage also consults the responder chain during replacements.
    // Keep raw range inverses out of our row-aware history, including on redo.
    public override var undoManager: UndoManager? { isEditable ? nil : super.undoManager }
    @objc(undo:) public func undoPanelEdit(_ sender: Any?) { panelUndo.undo() }
    @objc(redo:) public func redoPanelEdit(_ sender: Any?) { panelUndo.redo() }
    public override var needsPanelToBecomeKey: Bool { isEditable || super.needsPanelToBecomeKey }
    public override func acceptsFirstMouse(for event: NSEvent?) -> Bool { isEditable || super.acceptsFirstMouse(for: event) }
    /// Plain-text editor commands share one pasteboard, including for isolated
    /// native tests. Copying snapshots the current selection immediately.
    public var commandPasteboard: NSPasteboard = .general
    private func copySelection() -> Bool {
        let range = selectedRange(), source = string as NSString
        guard range.length > 0, NSMaxRange(range) <= source.length else { return false }
        let snapshot = source.substring(with: range)
        commandPasteboard.clearContents()
        return commandPasteboard.setString(snapshot, forType: .string)
    }
    public override func copy(_ sender: Any?) { _ = copySelection() }
    public override func cut(_ sender: Any?) {
        guard isEditable, copySelection() else { return }
        deleteBackward(sender)
    }
    public override func paste(_ sender: Any?) {
        guard isEditable, let plain = commandPasteboard.string(forType: .string) else { return }
        insertText(plain, replacementRange: selectedRange())
    }

    public override func performKeyEquivalent(with event: NSEvent) -> Bool {
        // A nonactivating panel can be key while another app owns the menu bar.
        // Route edit shortcuts only when this text view really owns the caret.
        guard isEditable, window?.firstResponder === self, !hasMarkedText() else {
            return super.performKeyEquivalent(with: event)
        }
        let flags = event.modifierFlags.intersection([.command, .control, .option, .shift])
        let key = event.charactersIgnoringModifiers?.lowercased()
        if flags == [.command, .shift], key == "z" { redoPanelEdit(nil); return true }
        guard flags == .command else { return super.performKeyEquivalent(with: event) }
        switch key {
        case "a": selectAll(nil)
        case "c": copy(nil)
        case "x": cut(nil)
        case "v": paste(nil)
        case "z": undoPanelEdit(nil)
        default: return super.performKeyEquivalent(with: event)
        }
        return true
    }

    var pointerDown: (NSPoint) -> Void = { _ in }
    var composing = false
    var compositionFinished: () -> Void = {}
    public override func setMarkedText(_ string: Any, selectedRange: NSRange, replacementRange: NSRange) {
        composing = true
        super.setMarkedText(string, selectedRange: selectedRange, replacementRange: replacementRange)
        composing = false
    }
    public override func unmarkText() {
        super.unmarkText()
        if !composing { compositionFinished() }
    }
    public override func insertText(_ string: Any, replacementRange: NSRange) {
        // AppKit may unmark before replacing the phonetic preedit with its candidate.
        composing = true
        super.insertText(string, replacementRange: replacementRange)
        composing = false
        compositionFinished()
    }
    // A read-only trailing voice caret: no editing, focus acquisition, timer or
    // insertion. Selection and reading earlier text suppress it.
    var showsLiveCaret = false { didSet { if oldValue != showsLiveCaret { needsDisplay = true } } }
    var shouldDrawLiveCaret: Bool {
        let editingHere = isEditable && window?.isKeyWindow == true && window?.firstResponder === self
        return showsLiveCaret && !editingHere && selectedRange().length == 0 && !string.isEmpty
    }

    public override func viewWillMove(toWindow newWindow: NSWindow?) {
        let center = NotificationCenter.default
        for name in [NSWindow.didBecomeKeyNotification, NSWindow.didResignKeyNotification] {
            if let window { center.removeObserver(self, name: name, object: window) }
            if let newWindow { center.addObserver(self, selector: #selector(refreshCaret), name: name, object: newWindow) }
        }
        super.viewWillMove(toWindow: newWindow)
    }

    @objc private func refreshCaret(_ notification: Notification) { needsDisplay = true }

    public override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard shouldDrawLiveCaret,
              let manager = layoutManager, let container = textContainer,
              manager.numberOfGlyphs > 0 else { return }
        let end = manager.numberOfGlyphs - 1
        let glyph = manager.boundingRect(forGlyphRange: NSRange(location: end, length: 1), in: container)
        let line = manager.lineFragmentRect(forGlyphAt: end, effectiveRange: nil)
        let origin = textContainerOrigin
        let font = textStorage?.attribute(.font, at: max(0, string.utf16.count - 1), effectiveRange: nil) as? NSFont
        let ink = font?.boundingRect(forGlyph: manager.glyph(at: end))
        let inkEnd = ink.map { line.minX + manager.location(forGlyphAt: end).x + $0.maxX } ?? glyph.maxX
        let scale = (font?.pointSize ?? ReferencePanelStyle.fontSize) / ReferencePanelStyle.fontSize
        let rect = CGRect(x: origin.x + inkEnd + 9 * scale,
                          y: origin.y + line.minY + 3 * scale, width: 2.5 * scale, height: 19 * scale)
        guard rect.maxX < bounds.maxX - 1 else { return }
        NSColor(srgbRed: 0.55, green: 0.23, blue: 0.98, alpha: 1).setFill()
        NSBezierPath(roundedRect: rect, xRadius: 1.25, yRadius: 1.25).fill()
    }
    var onEdit: (@MainActor () -> Void)?
    public override func accessibilityPerformPress() -> Bool {
        guard let onEdit else { return super.accessibilityPerformPress() }
        onEdit()
        return true
    }
    public override func isAccessibilitySelectorAllowed(_ selector: Selector) -> Bool {
        if selector == #selector(accessibilityPerformPress), onEdit != nil { return true }
        return super.isAccessibilitySelectorAllowed(selector)
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
    public override func menu(for event: NSEvent) -> NSMenu? {
        contextCharacter = characterIndexForInsertion(at: convert(event.locationInWindow, from: nil))
        return fillContextMenu != nil ? transcriptMenu : super.menu(for: event)
    }
    public func menuNeedsUpdate(_ menu: NSMenu) {
        guard menu === transcriptMenu, let fillContextMenu else { return }
        menu.removeAllItems()
        if isEditable {
            for (title, selector, key, enabled) in [
                ("剪切", #selector(cut(_:)), "x", selectedRange().length > 0),
                ("复制", #selector(copy(_:)), "c", selectedRange().length > 0),
                ("粘贴", #selector(paste(_:)), "v", commandPasteboard.availableType(from: [.string]) != nil),
                ("全选", #selector(selectAll(_:)), "a", !string.isEmpty)
            ] {
                let item = menu.addItem(withTitle: title, action: selector, keyEquivalent: key)
                item.target = self
                item.isEnabled = enabled
            }
            menu.addItem(.separator())
        }
        fillContextMenu(menu)
    }
    var onPageNavigation: ((Bool) -> Void)?
    public override func doCommand(by selector: Selector) {
        let canPage = selectedRange().length == 0 && !hasMarkedText()
        super.doCommand(by: selector)
        guard canPage else { return }
        switch selector {
        case #selector(pageUp(_:)), #selector(scrollPageUp(_:)):
            onPageNavigation?(true)
        case #selector(pageDown(_:)), #selector(scrollPageDown(_:)):
            onPageNavigation?(false)
        default:
            break
        }
    }

    public private(set) var contextCharacter: Int?
    var onSelectionTracking: (Bool) -> Void = { _ in }
    public override func mouseDown(with event: NSEvent) {
        pointerDown(convert(event.locationInWindow, from: nil))
        onSelectionTracking(true)
        super.mouseDown(with: event)
        onSelectionTracking(false)
    }
}
