import Foundation

extension SaytileStore {
    /// Commit the detail editor's accepted input before handing control back to AppKit.
    /// Use the same serialized, revocable connection as the timeline editor.
    @MainActor public func writeArchiveDraft(recordingID: UUID, text: String?, basedOn base: UUID?) throws {
        try panelEditor.use(at: directory.appendingPathComponent("Saytile.sqlite")) { writer in
            try writer.transaction {
                guard try writer.rows("SELECT 1 FROM recordings WHERE id=? AND deleted=0", [.text(recordingID.uuidString)]).first != nil
                else { throw StoreError.missingRecording }
                if let text {
                    try Self.persistArchiveDraft(text, id: recordingID, base: base, updateBase: true, in: writer)
                } else {
                    try writer.execute("DELETE FROM editing_drafts WHERE recording_id=?", [.text(recordingID.uuidString)])
                }
            }
        }
    }

    static func persistArchiveDraft(_ text: String, id: UUID, base: UUID?, updateBase: Bool, in writer: StoreDatabase) throws {
        try writer.execute("""
            INSERT INTO editing_drafts(recording_id,text,updated_at) VALUES(?,?,?)
            ON CONFLICT(recording_id) DO UPDATE SET text=excluded.text,updated_at=excluded.updated_at
            """, [.text(id.uuidString), .text(text), .double(Date().timeIntervalSince1970)])
        if updateBase {
            try writer.execute("""
                INSERT INTO archive_draft_bases(recording_id,revision_id) VALUES(?,?)
                ON CONFLICT(recording_id) DO UPDATE SET revision_id=excluded.revision_id
                """, [.text(id.uuidString), base.map { .text($0.uuidString) } ?? .null])
        }
    }
}
