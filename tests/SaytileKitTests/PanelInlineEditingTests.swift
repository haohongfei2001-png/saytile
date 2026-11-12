import Foundation
import Testing
@testable import SaytileKit
@testable import SaytileVoiceUI

@Suite struct PanelInlineEditingTests {
    private struct Row: VoiceTranscriptEntry {
        let id: UUID
        let position: Int64
        let displayText: String
    }

    @Test func utf16CrossRowJoinAndEmptyCanvas() throws {
        let a = Row(id: UUID(), position: 1, displayText: "甲🙂乙")
        let b = Row(id: UUID(), position: 2, displayText: "丙丁")
        let document = PanelTimelineDocument(entries: [a, b])
        let edit = try #require(document.edit(in: NSRange(location: 1, length: 5), replacement: "𠮷", newRow: false))
        #expect(edit.rows == [.init(id: a.id, before: "甲🙂乙", after: "甲𠮷丁"), .init(id: b.id, before: "丙丁", after: "")])
        #expect(edit.offset == 3)
        let newline = try #require(document.edit(in: NSRange(location: 4, length: 1), replacement: "", newRow: false))
        #expect(newline.rows.map(\.after) == ["甲🙂乙丙丁", ""])
        let single = try #require(document.edit(in: NSRange(location: 5, length: 0), replacement: "我", newRow: false))
        #expect(single.rows == [.init(id: b.id, before: "丙丁", after: "我丙丁")])
        let empty = PanelTimelineDocument<Row>()
        let note = try #require(empty.edit(in: .init(location: 0, length: 0), replacement: "手打", newRow: false))
        #expect(note.rows.count == 1 && note.rows[0].before == nil && note.rows[0].after == "手打")
    }

    @MainActor @Test func atomicEditConflictRecoveryAndNoAutomaticDelivery() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try SaytileStore(directory: directory)
        let binding = try await store.createBinding(label: "隔离测试")
        let noteID = UUID()
        let first = try store.editTimeline([.init(id: noteID, before: nil, after: "手打")], window: .latest)
        #expect(first.tail?.recording.audioState == .deleted && first.tail?.recording.isRecording == false)
        #expect(try await store.pendingRecordings().isEmpty)
        #expect(try await store.directInputCandidates(bindingID: binding, createdSince: .distantPast).isEmpty)
        let rec = try await store.createRecording()
        let ticket = try await store.beginRecognition(recordingID: rec.id)
        _ = try await store.applyRecognition(ticket: ticket, text: "识别初稿", isFinal: false)
        try await store.saveDraft(recordingID: rec.id, text: "另一个档案草稿")
        _ = try store.editTimeline([.init(id: noteID, before: "手打", after: "合并"), .init(id: rec.id, before: "识别初稿", after: "")], window: .latest)
        _ = try await store.applyRecognition(ticket: ticket, text: "迟到的最终稿", isFinal: true)
        #expect(try await store.recording(id: rec.id)?.text == "")
        #expect(try await store.loadDraft(recordingID: rec.id) == "另一个档案草稿")
        #expect(throws: StoreError.self) {
            _ = try store.editTimeline([.init(id: rec.id, before: "", after: "半次写入"), .init(id: noteID, before: "旧稿", after: "不能覆盖")], window: .latest)
        }
        #expect(try await store.recording(id: rec.id)?.text == "")
        try await store.close()
        let reopened = try SaytileStore(directory: directory)
        #expect(throws: StoreError.self) {
            _ = try store.editTimeline([.init(id: noteID, before: "合并", after: "关闭后写入")], window: .latest)
        }
        #expect(try await reopened.timelinePage().entries.map(\.recording.text) == ["合并", ""])
        #expect(try await reopened.revisions(recordingID: rec.id).contains { $0.text == "迟到的最终稿" })
        try await reopened.close()
    }
}
