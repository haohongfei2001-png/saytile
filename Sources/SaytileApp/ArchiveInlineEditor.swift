import AppKit
import SwiftUI

/// A natural paragraph owns a bounded window of its original recording rows.
/// AppKit handles the first click, keyboard input and IME in the same view used for reading.
struct ArchiveInlineEditor: NSViewRepresentable {
    let paragraph: ArchiveDisplayParagraph
    let model: AppModel
    let focusChanged: (Bool) -> Void

    func makeNSView(context: Context) -> ArchiveParagraphTextView {
        let view = ArchiveParagraphTextView(frame: .zero)
        view.isRichText = false
        view.isEditable = true
        view.isSelectable = true
        view.drawsBackground = false
        view.allowsUndo = true
        view.font = .systemFont(ofSize: 16)
        view.textColor = .labelColor
        view.textContainerInset = NSSize(width: 0, height: 4)
        view.textContainer?.lineFragmentPadding = 0
        view.textContainer?.widthTracksTextView = true
        view.isHorizontallyResizable = false
        view.isVerticallyResizable = false
        let style = NSMutableParagraphStyle()
        style.lineSpacing = 3
        view.defaultParagraphStyle = style
        view.setAccessibilityIdentifier("archive.text.\(paragraph.anchorID)")
        view.setAccessibilityLabel("编辑这段文字")
        view.delegate = view
        return view
    }

    func updateNSView(_ view: ArchiveParagraphTextView, context: Context) {
        let id = paragraph.id
        view.commandPasteboard = model.copyPasteboard
        view.save = { snapshot, after in
            do { return try model.editArchiveParagraph(id, snapshot: snapshot, after: after) }
            catch { model.notice = error.localizedDescription; throw error }
        }
        view.onFocus = { active in
            if active { model.setArchiveEditing(paragraph.page.entries.first?.id ?? paragraph.anchorID) }
            else if let owner = paragraph.page.entries.first?.id { model.endArchiveEditing(owner) }
            focusChanged(active)
        }
        view.prepareMenu = { [weak view] menu in
            menu.addItem(.separator())
            menu.addItem(TranscriptMenuItem(title: "复制这一整段", identifier: "archive.copyParagraph.\(paragraph.anchorID)") {
                guard let view else { return }
                model.copyParagraph(paragraph, displayed: view.visibleSnapshot)
            })
            if paragraph.hasAudio {
                menu.addItem(TranscriptMenuItem(
                    title: model.playingID == paragraph.anchorID ? "停止回听" : "回听这一整段",
                    identifier: "archive.play.\(paragraph.anchorID)") { model.playParagraph(paragraph) })
            }
            menu.addItem(TranscriptMenuItem(
                title: paragraph.pinned ? "取消这一段的收藏" : "收藏这一整段",
                identifier: "archive.favorite.\(paragraph.anchorID)") { Task { await model.toggleParagraphFavorite(paragraph) } })
            // Individual original audio/revision owners remain accessible in a
            // secondary menu; the archive itself has one action pair per paragraph.
            let versions = NSMenuItem(title: "原音与文字版本", action: nil, keyEquivalent: "")
            let submenu = NSMenu()
            for item in paragraph.items {
                let label = item.date.formatted(date: .omitted, time: .standard)
                submenu.addItem(TranscriptMenuItem(title: label, identifier: "archive.detail.\(item.id)") {
                    Task { await model.selectForEditing(item) }
                })
            }
            versions.submenu = submenu
            menu.addItem(versions)
        }
        view.display(paragraph)
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: ArchiveParagraphTextView, context: Context) -> CGSize? {
        guard let width = proposal.width, width.isFinite, width > 0 else { return nil }
        return CGSize(width: width, height: nsView.fittingHeight(for: width))
    }

    static func dismantleNSView(_ view: ArchiveParagraphTextView, coordinator: ()) {
        view.endInteraction()
        view.onFocus = nil
        view.prepareMenu = nil
        view.save = nil
        view.delegate = nil
    }
}

@MainActor
final class ArchiveParagraphTextView: NSTextView, NSTextViewDelegate {
    var onFocus: ((Bool) -> Void)?
    var prepareMenu: ((NSMenu) -> Void)?
    var save: ((PanelTimelineDocument, String) throws -> PanelTimelineDocument)?
    var commandPasteboard: NSPasteboard?
    private let editUndo = UndoManager()
    private var committed = ""
    private var committedDocument = PanelTimelineDocument()
    private var latestDocument = PanelTimelineDocument()
    private var latest = ""
    private var placeholder = ""
    private var changingComposition = false
    private var interacting = false
    private var hasUnsavedChanges = false
    var visibleSnapshot: [Int64: String] {
        var visible = committedDocument.displayed
        // Failed disk writes remain visible and copyable as a local draft.
        if let edits = committedDocument.edits(replacingDisplayedText: string) {
            let positions = Dictionary(uniqueKeysWithValues: committedDocument.entries.map { ($0.id, $0.position) })
            for edit in edits { if let position = positions[edit.id] { visible[position] = edit.after } }
        }
        return visible
    }
    override var undoManager: UndoManager? { editUndo }

    func display(_ paragraph: ArchiveDisplayParagraph) {
        latestDocument = paragraph.document
        latest = latestDocument.text
        if placeholder != paragraph.emptyTextLabel {
            placeholder = paragraph.emptyTextLabel
            if string.isEmpty { needsDisplay = true }
        }
        if !interacting && !changingComposition && !hasMarkedText() && !hasUnsavedChanges { applyLatest() }
    }

    private func applyLatest() {
        guard !hasUnsavedChanges else { return }
        guard !string.utf16.elementsEqual(latest.utf16) else { committed = latest; committedDocument = latestDocument; return }
        editUndo.removeAllActions()
        string = latest
        committed = latest
        committedDocument = latestDocument
        invalidateIntrinsicContentSize()
    }

    func fittingHeight(for width: CGFloat) -> CGFloat {
        guard let container = textContainer, let manager = layoutManager else { return 30 }
        if abs(container.size.width - width) > 0.01 {
            container.containerSize = .init(width: width, height: .greatestFiniteMagnitude)
        }
        manager.ensureLayout(for: container)
        let bottom = max(manager.usedRect(for: container).maxY, manager.extraLineFragmentRect.maxY)
        return max(28, ceil(bottom) + 2 * textContainerInset.height)
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard string.isEmpty, !interacting, !placeholder.isEmpty else { return }
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 13), .foregroundColor: NSColor.secondaryLabelColor
        ]
        (placeholder as NSString).draw(with: bounds.insetBy(dx: 0, dy: textContainerInset.height),
                                        options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine],
                                        attributes: attributes)
    }

    override func accessibilityPlaceholderValue() -> String? { string.isEmpty ? placeholder : nil }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func becomeFirstResponder() -> Bool {
        guard super.becomeFirstResponder() else { return false }
        if !interacting {
            interacting = true
            onFocus?(true)
            needsDisplay = true
        }
        return true
    }
    override func resignFirstResponder() -> Bool {
        guard super.resignFirstResponder() else { return false }
        endInteraction()
        return true
    }
    func endInteraction() {
        guard interacting else { return }
        if hasMarkedText() { unmarkText() }
        persist()
        interacting = false
        onFocus?(false)
        applyLatest()
        needsDisplay = true
    }

    func textDidChange(_ notification: Notification) { persist() }

    private func persist() {
        invalidateIntrinsicContentSize()
        guard !changingComposition, !hasMarkedText(), let save, !string.utf16.elementsEqual(committed.utf16) else { return }
        let edit = string
        do {
            let saved = try save(committedDocument, edit)
            committedDocument = saved
            latestDocument = saved
            committed = edit
            latest = edit
            hasUnsavedChanges = false
        } catch {
            // Keep the exact local draft and its undo history. The host attempts
            // durable recovery; a late refresh or blur must not erase failed typing.
            hasUnsavedChanges = true
        }
    }

    // Marked Pinyin stays local to the input method. Commit only its accepted candidate.
    override func setMarkedText(_ string: Any, selectedRange: NSRange, replacementRange: NSRange) {
        changingComposition = true
        super.setMarkedText(string, selectedRange: selectedRange, replacementRange: replacementRange)
        changingComposition = false
    }
    override func insertText(_ string: Any, replacementRange: NSRange) {
        changingComposition = true
        super.insertText(string, replacementRange: replacementRange)
        changingComposition = false
        persist()
    }
    override func unmarkText() {
        super.unmarkText()
        persist()
    }

    override func doCommand(by selector: Selector) {
        switch selector {
        case #selector(insertTab(_:)): window?.selectNextKeyView(self)
        case #selector(insertBacktab(_:)): window?.selectPreviousKeyView(self)
        default: super.doCommand(by: selector)
        }
    }

    override func copy(_ sender: Any?) {
        guard let commandPasteboard else { super.copy(sender); return }
        let range = selectedRange(), source = string as NSString
        guard range.length > 0, NSMaxRange(range) <= source.length else { return }
        commandPasteboard.clearContents()
        commandPasteboard.setString(source.substring(with: range), forType: .string)
    }
    override func cut(_ sender: Any?) {
        guard commandPasteboard != nil else { super.cut(sender); return }
        guard selectedRange().length > 0 else { return }
        copy(sender)
        deleteBackward(sender)
    }
    override func paste(_ sender: Any?) {
        guard let commandPasteboard else { super.paste(sender); return }
        if let text = commandPasteboard.string(forType: .string) { insertText(text, replacementRange: selectedRange()) }
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        let menu = super.menu(for: event)?.copy() as? NSMenu ?? NSMenu()
        prepareMenu?(menu)
        return menu
    }
}
