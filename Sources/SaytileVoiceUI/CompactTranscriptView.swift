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
    var compact = false

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
        view.setControlOnly(compact)
        view.applyTypeScale(typeScale)
        view.updateDocument(document)
        view.focus(on: focusPosition)
        view.consumeLatestRequest(latestRequest)
    }
}

@MainActor
public final class CompactTranscriptScrollView<Entry: VoiceTranscriptEntry>: NSScrollView, NSTextViewDelegate {
    public let transcriptView = CompactTranscriptTextView(frame: .zero)
    public private(set) var isFollowingLatest = true {
        didSet { if !isFollowingLatest { stopTailMotion() } }
    }
    public private(set) var latestText = ""
    public var hasDeferredUpdate: Bool { !Self.sameText(transcriptView.string, latestText) }
    var onFollowChange: (Bool) -> Void = { _ in }
    var onSelectionChange: (String) -> Void = { _ in }

    public private(set) var rendered = PanelTimelineDocument<Entry>()
    private var pending = PanelTimelineDocument<Entry>()
    private var liveTick: Task<Void, Never>?
    private var liveDeadline: TimeInterval?
    var onPage: (Bool) -> Void = { _ in }
    public internal(set) var editing = false
    var applyEdits: (@MainActor ([VoicePanelEdit]) throws -> PanelTimelineDocument<Entry>)?
    private var intendedEdit: (range: NSRange, replacement: String)?
    private var emptiedRow: (id: UUID, caret: Int)?
    private var focusedPosition: Int64?
    private var pagingFrom: Int64?
    public var selectionSnapshot: String {
        let range = transcriptView.selectedRange(), string = transcriptView.string as NSString
        return NSMaxRange(range) <= string.length ? string.substring(with: range) : ""
    }
    func focus(on position: Int64?) {
        guard let position else { focusedPosition = nil; return }
        guard focusedPosition != position, let span = rendered.spans.first(where: { $0.entry.position == position }) else { return }
        focusedPosition = position
        stopWheelMotion()
        pageRemainder = 0
        isFollowingLatest = false
        transcriptView.scrollRangeToVisible(NSRange(location: span.range.location, length: 1))
        publishState()
    }
    func updateDocument(_ document: PanelTimelineDocument<Entry>) {
        // Meter redraws do not consume extra reveal steps. A final revision has a
        // new identity even if the recognizer confirmed precisely the same words.
        if liveTick != nil, pending == document, Self.sameText(latestText, document.text) { return }
        if pending.liveTailID != document.liveTailID { cancelLivePresentation() }
        pending = document
        latestText = document.text
        applyLatest()
    }
    private var lastManagedOrigin: NSPoint?
    // Overflow belongs only to the page edge reached by this wheel gesture.
    private var pageRemainder: CGFloat = 0
    private var changingDocument = false
    private var selecting = false
    private var notificationScheduled = false
    private var latestRequest = 0
    private var lastLayoutSize = NSSize.zero
    private var measuredHeight: CGFloat = 0
    private var wheelLink: CADisplayLink?
    private var applyingWheelStep = false
    private var wheelRemaining: CGFloat = 0
    private var wheelLastFrame: CFTimeInterval = 0
    private var wheelDeadline: CFTimeInterval = 0
    private var tailLink: CADisplayLink?
    private var tailStart: (time: CFTimeInterval, y: CGFloat, destination: CGFloat)?

    public override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        transcriptView.replaceTextContainer(ReaderTextContainer(size: NSSize(width: max(1, frameRect.width), height: .greatestFiniteMagnitude)))
        borderType = .noBorder
        drawsBackground = false
        hasVerticalScroller = false
        hasHorizontalScroller = false
        transcriptView.isEditable = false
        transcriptView.isSelectable = true
        // Undo must carry row identities; AppKit raw UTF-16 inverses alone would
        // restore a cross-row cut into the wrong recording after an ASR update.
        transcriptView.allowsUndo = false
        transcriptView.isAutomaticTextReplacementEnabled = false
        transcriptView.isAutomaticDashSubstitutionEnabled = false
        transcriptView.isAutomaticQuoteSubstitutionEnabled = false
        transcriptView.typingAttributes = attributes
        transcriptView.compositionFinished = { [weak self] in
            self?.finishUserInput()
            self?.releaseConcealedEditor()
        }
        transcriptView.willAcceptEditingFocus = { [weak self] in self?.settleLivePresentation() }
        transcriptView.pointerDown = { [weak self] _ in
            self?.settleLivePresentation()
            self?.emptiedRow = nil
        }
        transcriptView.isRichText = false
        transcriptView.importsGraphics = false
        transcriptView.drawsBackground = false
        // The viewport ends at the final line of text, including after a long pause.
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
            stopWheelMotion()
            pageRemainder = 0
            requestAdjacentPage(older: older)
        }
        transcriptView.onSelectionTracking = { [weak self] tracking in
            guard let self else { return }
            selecting = tracking
            if tracking { stopWheelMotion(); pageRemainder = 0; isFollowingLatest = false; publishState() }
            else if transcriptView.selectedRange().length == 0 { applyLatest() }
        }
        documentView = transcriptView
        contentView.postsBoundsChangedNotifications = true
        NotificationCenter.default.addObserver(self, selector: #selector(viewportChanged), name: NSView.boundsDidChangeNotification, object: contentView)
    }
    public required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    // Keep the same editor, undo history and selection when only the voice button
    // is visible. A hidden editor must not continue accepting keyboard input.
    private var controlOnly = false
    func setControlOnly(_ compact: Bool) {
        guard compact != controlOnly else { return }
        controlOnly = compact
        transcriptView.concealed = compact
        if compact {
            cancelLivePresentation()
            stopWheelMotion()
            stopTailMotion()
            releaseConcealedEditor()
        }
    }

    private func releaseConcealedEditor() {
        // Resigning mid-composition can commit the phonetic preedit. Keep its
        // current input session until the IME finishes or the board opens again.
        guard controlOnly, !transcriptView.composing, !transcriptView.hasMarkedText(),
              let window, window.firstResponder === transcriptView else { return }
        window.makeFirstResponder(nil)
    }

    public override func layout() {
        super.layout()
        let size = contentSize
        guard !controlOnly, !changingDocument, size.width > 0, size.height > 0, size != lastLayoutSize else { return }
        if lastLayoutSize.width != size.width { (transcriptView.textContainer as? ReaderTextContainer)?.preserve([]) }
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
        jumpToLatest()
    }

    public func jumpToLatest() {
        stopWheelMotion()
        pageRemainder = 0
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
        // Direct AX edits may arrive without a focus/click callback. Freeze the
        // visible ranges until the edit commits against the full revision.
        if liveDeadline != nil { cancelLivePresentation() }
        stopTailMotion()
        stopWheelMotion()
        pageRemainder = 0
        if let replacementString, !transcriptView.hasMarkedText(),
           Self.sameText(rendered.text, textView.string) {
            intendedEdit = (range, replacementString)
        }
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
            edit = rendered.edit(in: change.range, replacement: change.replacement, newRow: false)
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
        cancelLivePresentation()
        guard let storage = transcriptView.textStorage else { return }
        changingDocument = true
        let preservedWraps = readingWraps(from: rendered, to: document, anchor: nil)
        rendered = document
        pending = document
        latestText = document.text
        let patch = Self.patch(from: transcriptView.string as NSString, to: document.text as NSString)
        storage.replaceCharacters(in: patch.range, with: patch.replacement)
        (transcriptView.textContainer as? ReaderTextContainer)?.preserve(preservedWraps)
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
        if transcriptView.selectedRange().length > 0 {
            stopWheelMotion()
            pageRemainder = 0
            isFollowingLatest = false
        }
        else if !selecting { applyLatest() }
        publishState()
    }

    public override func scrollWheel(with event: NSEvent) {
        let mechanical = !event.hasPreciseScrollingDeltas && event.phase.isEmpty && event.momentumPhase.isEmpty
        if !mechanical { stopWheelMotion() }
        let delta = event.scrollingDeltaY
        guard delta != 0 else { super.scrollWheel(with: event); return }
        if delta > 0 || tailLink != nil { isFollowingLatest = false; publishState() }
        lastManagedOrigin = nil
        if pageRemainder != 0, (delta > 0) != (pageRemainder > 0) { pageRemainder = 0 }
        if mechanical {
            let limit = max(1, contentSize.height / 2)
            let distance = min(limit, max(-limit, delta * verticalLineScroll))
            if window?.isVisible == true, !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
                if wheelRemaining * distance < 0 { wheelRemaining = 0 }
                wheelRemaining += distance
                let now = CACurrentMediaTime()
                wheelDeadline = now + 0.09
                if wheelLink == nil {
                    wheelLastFrame = now
                    let link = displayLink(target: self, selector: #selector(advanceWheelMotion))
                    wheelLink = link
                    link.add(to: .main, forMode: .common)
                }
            } else {
                stopWheelMotion()
                applyWheelDistance(distance)
            }
        } else {
            applyWheelDistance(delta, preciseEvent: event)
        }
    }

    @objc private func advanceWheelMotion() {
        let now = CACurrentMediaTime()
        let fraction = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? 1 :
            min(1, (now - wheelLastFrame) / max(0.0001, wheelDeadline - wheelLastFrame))
        let step = wheelRemaining * fraction
        wheelLastFrame = now
        wheelRemaining -= step
        if fraction == 1 { stopWheelMotion() }
        applyWheelDistance(step)
    }

    private func stopWheelMotion() {
        wheelLink?.invalidate()
        wheelLink = nil
        wheelRemaining = 0
    }

    private func applyWheelDistance(_ distance: CGFloat, preciseEvent: NSEvent? = nil) {
        guard distance != 0 else { return }
        let older = distance > 0
        let before = documentVisibleRect.minY
        let maximumY = max(0, transcriptView.bounds.height - contentSize.height)
        let canPage = !selecting && !editing && transcriptView.selectedRange().length == 0 &&
            (older ? rendered.older : rendered.newer)
        let room = max(0, older ? before : maximumY - before)
        if let preciseEvent, !(canPage && abs(distance) > room) {
            super.scrollWheel(with: preciseEvent)
        } else {
            // At a virtual boundary, split the event here. Giving its clipped
            // excess to AppKit as well would replay it after the page changes.
            applyingWheelStep = true
            scroll(to: NSPoint(x: 0, y: min(maximumY, max(0, before - distance))))
            applyingWheelStep = false
        }
        guard canPage else { return }
        let overflow = max(0, abs(distance) - room)
        if overflow > 0 {
            // A slow database read should not replay a screenful of stale input.
            let limit = max(1, contentSize.height / 2)
            pageRemainder = min(limit, max(-limit, pageRemainder + (older ? overflow : -overflow)))
        }
        requestAdjacentPage(older: older, wheelReachedEdge: overflow > 0)
    }

    private func requestAdjacentPage(older: Bool, wheelReachedEdge: Bool = false) {
        guard !selecting, !editing, transcriptView.selectedRange().length == 0 else { return }
        let edge = older ? rendered.firstPosition : rendered.lastPosition
        guard let edge, pagingFrom != edge, older ? rendered.older : rendered.newer,
              wheelReachedEdge || (older ? documentVisibleRect.minY < 32 : isAtBottom) else { return }
        pagingFrom = edge
        isFollowingLatest = false
        onPage(older)
    }

    @objc private func viewportChanged(_ notification: Notification) {
        guard !controlOnly, !changingDocument, !selecting, contentSize == lastLayoutSize else { return }
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
        if !applyingWheelStep { stopWheelMotion() }
        if !editing, transcriptView.selectedRange().length == 0, isAtBottom, !rendered.newer {
            isFollowingLatest = true
            if hasDeferredUpdate { applyLatest() }
        } else { isFollowingLatest = false }
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
        (transcriptView.textContainer as? ReaderTextContainer)?.preserve([])
        typeScale = scale
        transcriptView.textContainerInset = NSSize(width: 2, height: 6 * scale)
        transcriptView.typingAttributes = attributes
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

    /// Explicit interaction takes a snapshot of the recognizer's current candidate right away.
    /// Selections and deferred changes in a pinned/edited document retain their existing ownership.
    public func settleLivePresentation() {
        guard liveDeadline != nil else { return }
        cancelLivePresentation()
        applyLatest(immediate: true)
    }

    private func cancelLivePresentation() {
        liveTick?.cancel()
        liveTick = nil
        liveDeadline = nil
    }

    /// A partial can arrive several syllables at a time. Render the first group on this
    /// turn, and distribute only a genuine append over at most three more 28 ms ticks.
    /// Newer candidates inherit the original deadline. Rewrites and finals apply atomically.
    private func liveFrame(immediate: Bool, patch: (range: NSRange, replacement: String),
                           oldLength: Int) -> PanelTimelineDocument<Entry> {
        guard !immediate, !controlOnly, window?.isVisible == true, isFollowingLatest, !pending.newer, !pending.idle,
              !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion,
              !NSWorkspace.shared.isVoiceOverEnabled,
              !(transcriptView.isEditable && window?.isKeyWindow == true && window?.firstResponder === transcriptView),
              let tail = pending.spans.last, pending.liveTailID == tail.entry.id,
              tail.entry.position == pending.lastPosition, patch.range == NSRange(location: oldLength, length: 0),
              oldLength >= tail.range.location - 1, NSMaxRange(tail.range) == latestText.utf16.count,
              patch.replacement.count >= 2 else {
            cancelLivePresentation()
            return pending
        }

        let now = ProcessInfo.processInfo.systemUptime
        let interval = 0.028
        let deadline = liveDeadline ?? now + 3 * interval
        let remainingTicks = min(3, Int(ceil((deadline - now) / interval)))
        guard remainingTicks > 0 else {
            cancelLivePresentation()
            return pending
        }
        let groups = remainingTicks + 1
        let characters = patch.replacement.count
        // A separator before a new Latin utterance never consumes the first visible frame.
        let minimum = max(oldLength < tail.range.location ? 2 : 1, (characters + groups - 1) / groups)
        var boundary = patch.replacement.index(patch.replacement.startIndex, offsetBy: minimum)
        // AppKit wraps Latin words as a unit. Do not animate parts of an already
        // available word onto one line and force them back down on the next tick.
        while boundary < patch.replacement.endIndex,
              Self.isWordRun(patch.replacement[patch.replacement.index(before: boundary)]),
              Self.isWordRun(patch.replacement[boundary]) {
            patch.replacement.formIndex(after: &boundary)
        }
        guard boundary < patch.replacement.endIndex else { cancelLivePresentation(); return pending }
        let end = oldLength + patch.replacement[..<boundary].utf16.count
        let visibleRange = NSRange(location: tail.range.location, length: end - tail.range.location)
        let target = latestText as NSString
        var frame = pending
        frame.text = target.substring(to: end)
        frame.spans[frame.spans.count - 1] = .init(entry: tail.entry, range: visibleRange)
        frame.displayed[tail.entry.position] = target.substring(with: visibleRange)

        liveDeadline = deadline
        if liveTick == nil {
            let delay = min(interval, deadline - now)
            liveTick = Task { @MainActor [weak self] in
                do { try await Task.sleep(for: .seconds(delay)) } catch { return }
                guard let self else { return }
                liveTick = nil
                applyLatest()
            }
        }
        return frame
    }

    private static func isWordRun(_ character: Character) -> Bool {
        character.isASCII && (character.isLetter || character.isNumber || character == "_")
    }

    private func applyLatest(immediate: Bool = false) {
        guard !controlOnly, !changingDocument, !selecting, !editing,
              !transcriptView.composing, !transcriptView.hasMarkedText(),
              applyEdits == nil || Self.sameText(rendered.text, transcriptView.string),
              transcriptView.selectedRange().length == 0,
              pending != rendered || !Self.sameText(latestText, transcriptView.string), let storage = transcriptView.textStorage else { return }
        if rendered.firstPosition == pending.firstPosition, rendered.lastPosition == pending.lastPosition,
           Self.sameText(rendered.text, pending.text), rendered.markers == pending.markers {
            cancelLivePresentation()
            rendered = pending
            return
        }
        let old = transcriptView.string as NSString
        let fullPatch = Self.patch(from: old, to: latestText as NSString)
        let target = liveFrame(immediate: immediate, patch: fullPatch, oldLength: old.length)
        let new = target.text as NSString
        let patch = liveTick == nil ? fullPatch : (range: fullPatch.range, replacement: new.substring(from: old.length))
        let oldCaret = transcriptView.selectedRange().location
        let anchor = isFollowingLatest ? nil : readingAnchor()
        let oldOrigin = contentView.bounds.origin
        let oldDocument = rendered
        let anchoredSpan = anchor.flatMap { a in oldDocument.spans.first { NSMaxRange($0.range) > a.character } }
        let preservedWraps = readingWraps(from: oldDocument, to: target, anchor: anchor?.character, changedAt: patch.range.location)
        var wheelOffset: CGFloat = 0
        if oldDocument.firstPosition != target.firstPosition || oldDocument.lastPosition != target.lastPosition {
            if let edge = pagingFrom, (pageRemainder > 0 && target.firstPosition.map { $0 < edge } == true ||
                pageRemainder < 0 && target.lastPosition.map { $0 > edge } == true) {
                wheelOffset = pageRemainder
            }
            pagingFrom = nil
            pageRemainder = 0
        }
        rendered = target
        changingDocument = true
        storage.replaceCharacters(in: patch.range, with: NSAttributedString(string: patch.replacement, attributes: attributes))
        (transcriptView.textContainer as? ReaderTextContainer)?.preserve(preservedWraps)
        if oldDocument.markers != rendered.markers || !rendered.markers.isEmpty {
            storage.setAttributes(attributes, range: NSRange(location: 0, length: new.length))
            styleMarkers(in: storage)
        }
        let caret = min(new.length, Self.shift(oldCaret, through: patch.range, replacementLength: patch.replacement.utf16.count))
        transcriptView.setSelectedRange(NSRange(location: caret, length: 0))
        let liveWrap = isFollowingLatest && !oldDocument.text.isEmpty && !rendered.newer &&
            (transcriptView.shouldDrawLiveCaret || tailLink != nil) && window?.isVisible == true &&
            !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        ensureDocumentLayout(keepingVisibleOrigin: liveWrap ? oldOrigin.y : nil)
        if isFollowingLatest { scrollToLatest(animated: liveWrap) }
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
        if wheelOffset != 0, !isFollowingLatest {
            scroll(to: NSPoint(x: oldOrigin.x, y: contentView.bounds.minY - wheelOffset))
        }
        changingDocument = false
        publishState()
    }

    /// Carry soft line starts by recording identity, never by the old page's global offset.
    /// Retain the earliest shared line and the first line still being read: pinning
    /// only a vertical offset would rewrap every line from a different column.
    private func readingWraps(from old: PanelTimelineDocument<Entry>, to next: PanelTimelineDocument<Entry>,
                              anchor: Int?, changedAt: Int? = nil) -> [Int] {
        guard let container = transcriptView.textContainer as? ReaderTextContainer else { return [] }
        guard let manager = transcriptView.layoutManager, !old.spans.isEmpty, !next.spans.isEmpty else { return [] }
        let changingHead = old.firstPosition != next.firstPosition
        let changesBeforeReader = anchor.map { (changedAt ?? .max) < $0 } ?? false
        guard changingHead || changesBeforeReader || !container.wraps.isEmpty else { return [] }
        let destinations = Dictionary(uniqueKeysWithValues: next.spans.map { ($0.entry.id, $0) })
        func mapped(_ position: Int) -> Int? {
            guard let span = old.spans.first(where: { NSLocationInRange(position, $0.range) }),
                  let newSpan = destinations[span.entry.id] else { return nil }
            let local = position - span.range.location
            if Self.sameText(span.entry.displayText, newSpan.entry.displayText) { return newSpan.range.location + local }
            // An earlier word within this same long recording can also change.
            // Carry only boundaries on a surviving character, never into rewritten text.
            let edit = Self.patch(from: span.entry.displayText as NSString, to: newSpan.entry.displayText as NSString)
            guard !NSLocationInRange(local, edit.range) else { return nil }
            let offset = Self.shift(local, through: edit.range, replacementLength: edit.replacement.utf16.count, rightAffinity: true)
            guard offset < newSpan.range.length else { return nil }
            return newSpan.range.location + offset
        }
        var kept = container.wraps.compactMap(mapped)
        guard manager.numberOfGlyphs > 0, Self.sameText(old.text, transcriptView.string) else { return kept }
        var range = NSRange()
        if changingHead, let first = old.spans.first(where: { destinations[$0.entry.id] != nil }) {
            let glyph = manager.glyphIndexForCharacter(at: first.range.location)
            _ = manager.lineFragmentRect(forGlyphAt: glyph, effectiveRange: &range)
            let beginning = manager.characterIndexForGlyph(at: range.location)
            if let projected = mapped(beginning) { kept.append(projected) }
            else if NSMaxRange(range) < manager.numberOfGlyphs,
                    let projected = mapped(manager.characterIndexForGlyph(at: NSMaxRange(range))) { kept.append(projected) }
        }
        if (changingHead || changesBeforeReader), let anchor {
            _ = manager.lineFragmentRect(forGlyphAt: manager.glyphIndexForCharacter(at: anchor), effectiveRange: &range)
            if let projected = mapped(manager.characterIndexForGlyph(at: range.location)) { kept.append(projected) }
        }
        return kept
    }

    private func ensureDocumentLayout(keepingVisibleOrigin origin: CGFloat? = nil) {
        let width = max(1, contentSize.width)
        if transcriptView.frame.width != width {
            transcriptView.setFrameSize(NSSize(width: width, height: transcriptView.frame.height))
        }
        guard let manager = transcriptView.layoutManager, let container = transcriptView.textContainer else { return }
        manager.ensureLayout(for: container)
        measuredHeight = max(contentSize.height, ceil(manager.usedRect(for: container).maxY + transcriptView.textContainerInset.height * 2))
        // An unstable last line can unwrap. Let it move back over the same
        // short interval; shrinking the document first would snap the clip view.
        let size = NSSize(width: width, height: max(measuredHeight, (origin ?? 0) + contentSize.height))
        if transcriptView.frame.size != size { transcriptView.setFrameSize(size) }
    }

    private func scrollToLatest(animated: Bool = false) {
        let destination = max(0, measuredHeight - contentSize.height)
        let current = contentView.bounds.minY
        if animated, abs(destination - current) >= 1 {
            if tailStart?.destination != destination {
                tailStart = (CACurrentMediaTime(), current, destination)
            }
            if tailLink == nil {
                let link = displayLink(target: self, selector: #selector(advanceTailMotion))
                tailLink = link
                link.add(to: .main, forMode: .common)
            }
        } else {
            stopTailMotion()
            positionLiveTail(at: destination)
        }
    }

    @objc private func advanceTailMotion() {
        guard let start = tailStart, isFollowingLatest, !editing, !selecting,
              !transcriptView.hasMarkedText(), transcriptView.selectedRange().length == 0 else {
            stopTailMotion()
            return
        }
        let progress = min(1, (CACurrentMediaTime() - start.time) / 0.15)
        let remaining = 1 - progress
        positionLiveTail(at: start.destination + (start.y - start.destination) * remaining * remaining)
        if progress == 1 { stopTailMotion() }
    }

    private func positionLiveTail(at y: CGFloat) {
        let wasChanging = changingDocument
        changingDocument = true
        scroll(to: NSPoint(x: 0, y: y))
        if transcriptView.frame.height > measuredHeight {
            transcriptView.setFrameSize(NSSize(width: transcriptView.frame.width,
                height: max(measuredHeight, contentView.bounds.minY + contentSize.height)))
        }
        changingDocument = wasChanging
    }

    private func stopTailMotion() {
        tailLink?.invalidate()
        tailLink = nil
        tailStart = nil
    }

    public override func viewWillMove(toWindow newWindow: NSWindow?) {
        if window !== newWindow { stopWheelMotion(); stopTailMotion() }
        super.viewWillMove(toWindow: newWindow)
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
    fileprivate var concealed = false
    public override var acceptsFirstResponder: Bool { !concealed && super.acceptsFirstResponder }
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

    var willAcceptEditingFocus: () -> Void = {}
    public override func becomeFirstResponder() -> Bool {
        guard !concealed else { return false }
        if isEditable { willAcceptEditingFocus() }
        return super.becomeFirstResponder()
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
