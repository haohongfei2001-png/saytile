import Foundation
import Testing
@testable import SaytileKit

struct ArchiveReadingTests {
    @Test func originalGroupSurvivesPagingFilteringAndDeletion() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try SaytileStore(directory: directory)
        try await store.setTimelineIdleSeconds(120) // Explicit legacy grouping remains supported.
        let date = Calendar.current.startOfDay(for: .now).addingTimeInterval(3600)
        func segment(start: TimeInterval, end: TimeInterval, text: String?) async throws -> UUID {
            let row = try await store.createRecording(createdAt: date.addingTimeInterval(start))
            if let text { try await store.saveEdit(recordingID: row.id, text: text) }
            try await store.finishRecording(id: row.id, speechEndedAt: date.addingTimeInterval(end))
            return row.id
        }
        let first = try await segment(start: 0, end: 300, text: nil)
        let second = try await segment(start: 309, end: 321, text: "长句 25%")
        let third = try await segment(start: 440, end: 445, text: "接着说")
        let fourth = try await segment(start: 565, end: 567, text: "新的输入")
        let originalGroup = try #require(try await store.timelinePosition(of: first))
        try await store.setPinned(recordingID: second, pinned: true)
        try await store.saveEdit(recordingID: second, text: "长句已修改")
        try await store.saveDraft(recordingID: third, text: "拟稿_25%")
        try await store.deleteRecord(recordingID: first)
        try await store.close()

        let reopened = try SaytileStore(directory: directory)
        let page = try await reopened.archiveEntries(limit: 2)
        let all = try await reopened.archiveEntries(limit: 4)
        #expect(page.map(\.id) == [fourth, third])
        #expect(all.map(\.id) == [fourth, third, second])
        #expect(all[0].group != originalGroup)
        #expect(all[1].group == originalGroup && all[2].group == originalGroup)
        #expect(page.last?.groupStart == date)
        let favorites = try await reopened.archiveEntries(filter: .pinned)
        #expect(favorites.map(\.id) == [second] && favorites[0].groupStart == date)
        let history = try await reopened.archiveEntries(query: "%")
        let drafts = try await reopened.archiveEntries(query: "_")
        #expect(history.map(\.id) == [third, second] && history.allSatisfy { $0.group == originalGroup })
        #expect(drafts.map(\.id) == [third])
    }

    @MainActor @Test func editingEmptyParagraphSurvivesFilterAndProtectsNewerVersions() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try SaytileStore(directory: directory)
        let id = try await store.createRecording().id
        try await store.finishRecording(id: id)
        try await store.saveEdit(recordingID: id, text: "原文")
        try await store.saveDraft(recordingID: id, text: "详情草稿")
        let empty = try store.editArchiveParagraph(id: id, before: "原文", after: "")
        #expect(empty.id == id && empty.text.isEmpty)
        #expect(try await store.archiveEntries().isEmpty)
        #expect(try await store.archiveEntries(editingID: id).map(\.id) == [id])
        let updated = try store.editArchiveParagraph(id: id, before: "", after: "接着写")
        #expect(updated.text == "接着写")
        try await store.saveEdit(recordingID: id, text: "另一处的新稿")
        #expect(throws: StoreError.self) { try store.editArchiveParagraph(id: id, before: "接着写", after: "过时输入") }
        #expect(try await store.recording(id: id)?.text == "另一处的新稿")
        #expect(try await store.revisions(recordingID: id).count == 4)
    }

    @MainActor @Test func detailDraftRequiresItsReviewedHumanRevisionAfterRestart() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try SaytileStore(directory: directory)
        let id = try await store.createRecording().id
        let base = try await store.saveEdit(recordingID: id, text: "原文")
        try store.writeArchiveDraft(recordingID: id, text: "详情稿", basedOn: base.id)
        let other = try store.editArchiveParagraph(id: id, before: "原文", after: "浮板修改")
        try await store.close()

        let reopened = try SaytileStore(directory: directory)
        let pending = try #require(try await reopened.archiveDraft(recordingID: id))
        #expect(pending.base == base.id)
        await #expect(throws: StoreError.self) {
            try await reopened.saveEdit(recordingID: id, text: pending.text, clearingDraftMatching: pending.text, basedOn: pending.base)
        }
        #expect(try await reopened.recording(id: id)?.text == other.text)
        #expect(try await reopened.loadDraft(recordingID: id) == pending.text)
        let newer = try reopened.editArchiveParagraph(id: id, before: other.text, after: "第三版")
        await #expect(throws: StoreError.self) {
            try await reopened.saveEdit(recordingID: id, text: pending.text, clearingDraftMatching: pending.text, basedOn: other.preferredRevisionID)
        }
        try await reopened.saveEdit(recordingID: id, text: pending.text, clearingDraftMatching: pending.text, basedOn: newer.preferredRevisionID)
        #expect(try await reopened.loadDraft(recordingID: id) == nil)
        #expect(try await reopened.recording(id: id)?.text == pending.text)
        #expect(throws: StoreError.self) { try reopened.editArchiveParagraph(id: id, before: newer.text, after: "过时的改动") }
        #expect(try await reopened.revisions(recordingID: id).count == 4)
    }

    @MainActor @Test func existingDraftWithoutKnownBaseKeepsManualTranscript() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try SaytileStore(directory: directory)
        let id = try await store.createRecording().id
        let current = try await store.saveEdit(recordingID: id, text: "已有手稿")
        try await store.saveDraft(recordingID: id, text: "旧版草稿")
        try await store.close()
        let old = try StoreDatabase(url: directory.appendingPathComponent("Saytile.sqlite"))
        try old.execute("DROP TABLE archive_draft_bases")
        try old.close()
        let upgraded = try SaytileStore(directory: directory)
        let restored = try #require(try await upgraded.archiveDraft(recordingID: id))
        #expect(restored.base == nil && restored.text == "旧版草稿")
        try upgraded.writeArchiveDraft(recordingID: id, text: "旧版草稿继续", basedOn: restored.base)
        await #expect(throws: StoreError.self) {
            try await upgraded.saveEdit(recordingID: id, text: "旧版草稿继续", clearingDraftMatching: "旧版草稿继续", basedOn: restored.base)
        }
        #expect(try await upgraded.recording(id: id)?.preferredRevisionID == current.id)
        #expect(try await upgraded.loadDraft(recordingID: id) == "旧版草稿继续")
    }
}
