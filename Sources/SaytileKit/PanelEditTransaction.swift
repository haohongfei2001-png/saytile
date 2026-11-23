import Foundation

public struct PanelRowEdit: Sendable {
    public let id: UUID
    public let before: String?
    public let after: String
    public let paragraphBreakHidden: Bool?
    public let previousParagraphBreakHidden: Bool?

    public init(id: UUID, before: String?, after: String, paragraphBreakHidden: Bool? = nil, previousParagraphBreakHidden: Bool? = nil) {
        self.id = id
        self.before = before
        self.after = after
        self.paragraphBreakHidden = paragraphBreakHidden
        self.previousParagraphBreakHidden = previousParagraphBreakHidden
    }
}

extension SaytileStore {
    /// Runs inside the host's single SQLite transaction. Retain original audio,
    /// every prior revision, and any separate, unfinished archive editor draft.
    @discardableResult static func writePanelEdits(_ edits: [PanelRowEdit], to db: StoreDatabase, at date: Date) throws -> [UUID: UUID] {
        var revisions: [UUID: UUID] = [:]
        let now = StoreDatabase.Value.double(date.timeIntervalSince1970)
        var breaks: [Int64: (before: Bool, after: Bool)] = [:]
        for edit in edits where edit.paragraphBreakHidden != nil || edit.previousParagraphBreakHidden != nil {
            guard edit.before != nil, let after = edit.paragraphBreakHidden, let before = edit.previousParagraphBreakHidden,
                  let row = try db.rows("""
                    SELECT p.paragraph_start,head.break_hidden FROM transcript_timeline t
                    JOIN timeline_paragraphs p ON p.position=t.position JOIN timeline_paragraphs head ON head.position=p.paragraph_start
                    JOIN recordings r ON r.id=t.recording_id WHERE r.id=? AND r.deleted=0
                    """, [.text(edit.id.uuidString)]).first,
                  let paragraph = row["paragraph_start"].flatMap(Int64.init), (row["break_hidden"] == "1") == before
            else { throw StoreError.invalidBoundary }
            if let existing = breaks[paragraph], existing.before != before || existing.after != after { throw StoreError.invalidBoundary }
            breaks[paragraph] = (before, after)
        }
        for edit in edits {
            let id = StoreDatabase.Value.text(edit.id.uuidString)
            var base = StoreDatabase.Value.null
            if let before = edit.before {
                guard let row = try db.rows("""
                    SELECT r.preferred_revision,v.origin,v.text FROM recordings r
                    LEFT JOIN revisions v ON v.id=r.preferred_revision WHERE r.id=? AND r.deleted=0
                    """, [id]).first else { throw StoreError.missingRecording }
                // ASR can finish while a selection or IME composition is held.
                // Preserve the user's snapshot, but never overwrite a newer human edit.
                if row["origin"] == "userEdit", !(row["text"] ?? "").utf16.elementsEqual(before.utf16) {
                    throw StoreError.database("这段文字已在另一处修改，请重新选择要编辑的文字。")
                }
                if let revision = row["preferred_revision"] { base = .text(revision) }
            } else {
                try db.execute("""
                    INSERT INTO recordings(id,created_at,sample_rate,audio_state,recognition_state,is_recording)
                    VALUES(?,?,16000,'deleted','completed',0)
                    """, [id, now])
            }
            // Deleting/restoring only an automatic separator does not turn the
            // recognizer's unchanged words into a human edit or freeze live ASR.
            if edit.paragraphBreakHidden != nil, let before = edit.before, before.utf16.elementsEqual(edit.after.utf16) { continue }
            let revisionID = UUID()
            revisions[edit.id] = revisionID
            let revision = StoreDatabase.Value.text(revisionID.uuidString)
            try db.execute("""
                INSERT INTO revisions(id,recording_id,text,origin,created_at,base_revision) VALUES(?,?,?,'userEdit',?,?)
                """, [revision, id, .text(edit.after), now, base])
            try db.execute("UPDATE recordings SET preferred_revision=? WHERE id=?", [revision, id])
        }
        for (paragraph, change) in breaks {
            try db.execute("UPDATE timeline_paragraphs SET break_hidden=? WHERE position=?", [.int(change.after ? 1 : 0), .int(paragraph)])
        }
        return revisions
    }
}
