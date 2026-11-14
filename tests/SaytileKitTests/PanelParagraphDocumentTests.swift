import AppKit
import Foundation
#if !SAYTILE_DOCUMENT_STANDALONE
import Testing
@testable import SaytileVoiceUI
#endif

/// Pure bounded-document cases also run without creating NSApplication or a window.
enum PanelParagraphDocumentCases {
    struct Row: VoiceTranscriptEntry {
        let id: UUID
        let position: Int64
        let paragraphID: Int64
        var displayText: String
        var isUserEdited = false
        var paragraphBreakHidden = false
    }
    struct Failure: Error, CustomStringConvertible { let description: String }
    static func require(_ condition: @autoclosure () -> Bool, _ message: String) throws {
        if !condition() { throw Failure(description: message) }
    }
    static func rows(_ texts: [String], paragraphs: [Int64], edited: Set<Int> = [], hidden: Set<Int64> = []) -> [Row] {
        texts.enumerated().map { .init(id: UUID(), position: Int64($0.offset + 1),
            paragraphID: paragraphs[$0.offset], displayText: $0.element, isUserEdited: edited.contains($0.offset), paragraphBreakHidden: hidden.contains(paragraphs[$0.offset])) }
    }
    static func applying(_ edits: [VoicePanelEdit], to original: [Row]) throws -> [Row] {
        var rows = original
        for edit in edits {
            guard let index = rows.firstIndex(where: { $0.id == edit.id }),
                  edit.before?.utf16.elementsEqual(rows[index].displayText.utf16) == true else {
                throw Failure(description: "Edit lost its source recording or conflict baseline")
            }
            rows[index].displayText = edit.after
            rows[index].isUserEdited = true
            if let hidden = edit.paragraphBreakHidden {
                try require(rows[index].paragraphBreakHidden == edit.previousParagraphBreakHidden, "Boundary conflict baseline differs")
                let paragraph = rows[index].paragraphID
                for member in rows.indices where rows[member].paragraphID == paragraph { rows[member].paragraphBreakHidden = hidden }
            }
        }
        return rows
    }
    static func inverse(_ edits: [VoicePanelEdit]) -> [VoicePanelEdit] {
        edits.map { .init(id: $0.id, before: $0.after, after: $0.before ?? "",
            paragraphBreakHidden: $0.previousParagraphBreakHidden, previousParagraphBreakHidden: $0.paragraphBreakHidden) }
    }
    static func run() throws -> Int {
        var assertions = 0
        let emptyLead = rows(["前段", "", "后段", "继续"], paragraphs: [1, 2, 2, 2])
        try require(PanelTimelineDocument(entries: emptyLead).text == "前段\n后段继续", "Unrecognized leading row must keep its paragraph")
        let emptyManual = rows(["前段", "", "后段", "继续"], paragraphs: [1, 2, 2, 2], edited: [1], hidden: [2])
        try require(PanelTimelineDocument(entries: emptyManual).text == "前段后段继续", "Explicit hidden boundary survives an empty first row")
        let page = PanelTimelineDocument(entries: Array(emptyLead.dropFirst()), older: true)
        try require(page.text == "后段继续" && page.entries.count == 3 && page.older, "A page cannot invent leading whitespace or discard empty identities")
        assertions += 3

        let cases: [([String], [Int64], Set<Int>)] = [
            (["甲", "乙", "丙"], [1, 1, 1], []),
            (["甲", "乙", "丙"], [1, 2, 3], []),
            (["First", "second", "third"], [1, 2, 3], []),
            (["甲🙂", "𠮷乙", "尾"], [1, 2, 2], []),
            (["é", "cafe\u{301}", "中文"], [1, 2, 3], []),
            (["甲\n", "乙", "丙"], [1, 2, 3], []),
            (["甲", "\n乙", "丙"], [1, 2, 3], []),
            (["甲", "", "乙", "丙"], [1, 2, 2, 3], []),
            (["甲", "", "乙", "丙"], [1, 2, 2, 3], [1]),
            (["甲", "乙", "丙"], [1, 2, 3], [1]),
            (["前", "First", "second", "尾"], [1, 2, 2, 3], []),
            (["甲", "\n", "乙"], [1, 2, 3], []),
            (["前", "e\u{301}", "尾", "结束"], [1, 2, 3, 4], []),
            (["前", "", "\n", "后"], [1, 2, 2, 3], [1]),
            (["前", "", "", "后"], [1, 2, 3, 3], []),
            (["First", "", "next", "tail"], [1, 2, 2, 3], [1]),
            (["前", " ", "后"], [1, 2, 3], []),
            (["前\r\n", "后", "尾"], [1, 2, 2], [])
        ]
        for (texts, paragraphs, edited) in cases {
            let entries = rows(texts, paragraphs: paragraphs, edited: edited)
            let document = PanelTimelineDocument(entries: entries)
            let ns = document.text as NSString
            let stops = document.text.indices.map { $0.utf16Offset(in: document.text) } + [ns.length]
            for start in stops {
                for stop in stops where stop >= start {
                    for inserted in ["", "中", "X", "é", "e\u{301}", "\n", "\n\n", " 🗣️A\n中"] {
                        let range = NSRange(location: start, length: stop - start)
                        let expected = ns.replacingCharacters(in: range, with: inserted)
                        guard let edits = document.edits(for: range, replacement: inserted) else {
                            throw Failure(description: "Mapping refused \(texts) paragraphs \(paragraphs), range \(range), replacement [\(inserted)]")
                        }
                        let updated = try applying(edits, to: entries)
                        try require(PanelTimelineDocument(entries: updated).text.utf16.elementsEqual(expected.utf16), "Exact native edit reconstruction")
                        let undo = inverse(edits)
                        let restored = try applying(undo, to: updated)
                        try require(PanelTimelineDocument(entries: restored).text.utf16.elementsEqual(document.text.utf16),
                            "Undo lost paragraph: \(texts), range \(range), replacement [\(inserted)], got [\(PanelTimelineDocument(entries: restored).text)]")
                        let redone = try applying(inverse(undo), to: restored)
                        try require(PanelTimelineDocument(entries: redone).text.utf16.elementsEqual(expected.utf16), "Redo changed paragraph boundaries")
                        guard let archive = document.edits(replacingDisplayedText: expected) else {
                            throw Failure(description: "Archive diff refused \(texts), original range \(range), replacement [\(inserted)], expected [\(expected)]")
                        }
                        let archived = try applying(archive, to: entries)
                        try require(PanelTimelineDocument(entries: archived).text.utf16.elementsEqual(expected.utf16), "Archive and panel mapping disagree")
                        assertions += 4
                    }
                }
            }
        }
        let archiveRows = rows(["前一段", "第二段", "继续"], paragraphs: [1, 2, 2])
        let secondArchive = PanelTimelineDocument(entries: Array(archiveRows.dropFirst()))
        guard let archiveEdit = secondArchive.edits(replacingDisplayedText: "改过的第二段继续") else {
            throw Failure(description: "Independent archive paragraph edit refused")
        }
        let fullAfterArchive = try applying(archiveEdit, to: archiveRows)
        try require(PanelTimelineDocument(entries: fullAfterArchive).text == "前一段\n改过的第二段继续",
                    "Independent archive edit must keep the full panel paragraph boundary")
        guard let clearingFirst = secondArchive.edits(replacingDisplayedText: "继续") else {
            throw Failure(description: "Archive first-recording deletion refused")
        }
        let clearedFirst = try applying(clearingFirst, to: archiveRows)
        try require(PanelTimelineDocument(entries: clearedFirst).text == "前一段\n继续",
                    "Empty edited archive member must not imply a removed paragraph break")
        try require(clearingFirst.allSatisfy { $0.paragraphBreakHidden == nil },
                    "Ordinary archive text edits cannot change paragraph metadata")
        assertions += 2
        let deleting = PanelTimelineDocument(entries: archiveRows)
        guard let join = deleting.edits(for: NSRange(location: 3, length: 1), replacement: "") else {
            throw Failure(description: "Explicit paragraph join refused")
        }
        var joined = try applying(join, to: archiveRows)
        joined.append(Row(id: UUID(), position: 4, paragraphID: 2, displayText: "后续", paragraphBreakHidden: true))
        try require(PanelTimelineDocument(entries: joined).text == "前一段第二段继续后续",
                    "Future same-paragraph ASR must not resurrect a removed break")
        assertions += 2
        let empty = rows(["", ""], paragraphs: [1, 1])
        let emptyDoc = PanelTimelineDocument(entries: empty)
        guard let firstTyped = emptyDoc.edits(replacingDisplayedText: "先手动补上🙂") else { throw Failure(description: "Empty archive edit refused") }
        try require(firstTyped.count == 1 && firstTyped.first?.id == empty[0].id && firstTyped.first?.before == "", "Empty paragraph must reuse original recording")
        assertions += 1
        return assertions
    }

#if !SAYTILE_DOCUMENT_PURE
    @MainActor static func nativeUndoRedo() throws {
        _ = NSApplication.shared
        var rows = PanelParagraphDocumentCases.rows(["前段", "后段"], paragraphs: [1, 2])
        let view = CompactTranscriptScrollView<PanelParagraphDocumentCases.Row>(frame: .init(x: 0, y: 0, width: 260, height: 140))
        let editor = view.transcriptView
        editor.isEditable = true
        view.applyEdits = { edits in
            rows = try PanelParagraphDocumentCases.applying(edits, to: rows)
            return .init(entries: rows)
        }
        view.updateDocument(.init(entries: rows))
        let undo = editor.panelUndo
        undo.groupsByEvent = false
        undo.beginUndoGrouping()
        editor.setSelectedRange(.init(location: 2, length: 1))
        editor.insertText("", replacementRange: editor.selectedRange())
        undo.endUndoGrouping()
        try require(editor.string == "前段后段", "Native deletion/redo must not resurrect the automatic break")
        editor.undoPanelEdit(nil)
        try require(editor.string == "前段\n后段", "Native undo must restore the automatic break as explicit text")
        editor.redoPanelEdit(nil)
        try require(editor.string == "前段后段", "Native deletion/redo must not resurrect the automatic break")
    }
#endif
}

#if SAYTILE_DOCUMENT_STANDALONE
@main enum PanelParagraphDocumentMain {
    @MainActor static func main() {
        do {
            print("PASS \(try PanelParagraphDocumentCases.run()) paragraph/edit/undo assertions")
#if !SAYTILE_DOCUMENT_PURE
            try PanelParagraphDocumentCases.nativeUndoRedo()
            print("PASS native AppKit paragraph deletion, undo and redo")
#endif
        }
        catch { print("FAIL \(error)"); exit(1) }
    }
}
#else
@Suite struct PanelParagraphDocumentTests {
    @Test func paragraphMappingPreservesEveryNativeEditAndUndo() throws {
        #expect(try PanelParagraphDocumentCases.run() > 1000)
    }

    @MainActor @Test func nativeUndoRedoRestoresDeletedAutomaticParagraph() throws {
        try PanelParagraphDocumentCases.nativeUndoRedo()
    }
}
#endif
