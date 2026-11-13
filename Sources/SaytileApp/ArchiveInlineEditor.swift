import AppKit
import SwiftUI

/// Each paragraph owns its original recording, text selection and undo history.
/// AppKit handles the first click, keyboard input and IME in the same view used for reading.
struct ArchiveInlineEditor: NSViewRepresentable {
    let item: DisplayRecording
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
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = 3
        view.defaultParagraphStyle = paragraph
        view.setAccessibilityIdentifier("archive.text.\(item.id)")
        view.setAccessibilityLabel("编辑这段文字")
        view.delegate = view
        return view
    }

    func updateNSView(_ view: ArchiveParagraphTextView, context: Context) {
        let id = item.id
        view.commandPasteboard = model.copyPasteboard
        view.save = { before, after in
            do { try model.editArchiveText(id, before: before, after: after) }
            catch { model.notice = error.localizedDescription; throw error }
        }
        view.onFocus = { active in
            if active { model.setArchiveEditing(id) }
            else { model.endArchiveEditing(id) }
            focusChanged(active)
        }
        view.prepareMenu = { menu in
            menu.addItem(.separator())
            if item.hasAudio {
                menu.addItem(TranscriptMenuItem(
                    title: model.playingID == id ? "停止回听" : "回听原音",
                    identifier: "archive.play.\(id)") { model.play(item) })
            }
            menu.addItem(TranscriptMenuItem(
                title: item.pinned ? "取消收藏" : "收藏这条记录",
                identifier: "archive.favorite.\(id)") { Task { await model.toggleFavorite(id) } })
            menu.addItem(TranscriptMenuItem(title: "原音与文字版本…", identifier: "archive.detail.\(id)") {
                Task { await model.selectForEditing(item) }
            })
        }
        view.display(item)
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
    var save: ((String, String) throws -> Void)?
    var commandPasteboard: NSPasteboard?
    private let editUndo = UndoManager()
    private var committed = ""
    private var latest = ""
    private var placeholder = ""
    private var changingComposition = false
    private var interacting = false
    override var undoManager: UndoManager? { editUndo }

    func display(_ item: DisplayRecording) {
        latest = item.text
        if placeholder != item.emptyTextLabel {
            placeholder = item.emptyTextLabel
            if string.isEmpty { needsDisplay = true }
        }
        if !interacting && !changingComposition && !hasMarkedText() { applyLatest() }
    }

    private func applyLatest() {
        guard !string.utf16.elementsEqual(latest.utf16) else { committed = latest; return }
        editUndo.removeAllActions()
        string = latest
        committed = latest
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
            try save(committed, edit)
            committed = edit
            latest = edit
        } catch {
            editUndo.removeAllActions()
            string = latest
            committed = latest
            NSSound.beep()
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
