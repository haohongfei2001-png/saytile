import Foundation
@testable import SaytileKit

struct NaturalParagraphTests {
    struct Failure: Error, CustomStringConvertible { let description: String }
    private func check(_ condition: Bool, _ message: String = #function, line: Int = #line) throws {
        if !condition { throw Failure(description: "\(message):\(line)") }
    }
    private func directory() -> URL { FileManager.default.temporaryDirectory.appendingPathComponent("saytile-paragraph-" + UUID().uuidString) }
    private var noon: Date { Calendar.current.startOfDay(for: Date(timeIntervalSince1970: 1_800_000_000)).addingTimeInterval(43_200) }
    private func add(_ store: SaytileStore, _ start: Date, _ seconds: Double = 1, _ text: String = "正文") async throws -> Recording {
        let record = try await store.createRecording(createdAt: start)
        try await store.finishRecording(id: record.id, speechEndedAt: start.addingTimeInterval(seconds))
        let ticket = try await store.beginRecognition(recordingID: record.id)
        try await store.applyRecognition(ticket: ticket, text: text, isFinal: true)
        try await store.finishRecognition(ticket: ticket)
        return record
    }

    func actualSpeechGapHasIndependentParagraphAndTimeGroupThresholds() async throws {
        let dir = directory(); defer { try? FileManager.default.removeItem(at: dir) }
        let store = try SaytileStore(directory: dir)
        try check(store.initialTimelineIdleSeconds == 60)
        _ = try await add(store, noon, 4, "开头")
        _ = try await add(store, noon.addingTimeInterval(18.999), 1.001, "短停顿")
        _ = try await add(store, noon.addingTimeInterval(35), 5, "新自然段")
        _ = try await add(store, noon.addingTimeInterval(99.999), 1.001, "仍同时间组")
        _ = try await add(store, noon.addingTimeInterval(161), 1, "新时间组")
        let entries = try await store.timelinePage().entries
        try check(entries.map(\.paragraphID) == [1, 1, 3, 4, 5])
        try check(entries.map(\.group) == [1, 1, 1, 1, 5])
        try check(entries[1].paragraphStart == noon)
        try check(try store.timelineCopy(group: 1, through: 4, displayed: [:]) == "开头短停顿\n新自然段\n仍同时间组")
        let dispatchSnapshots = try store.timelineGroupSnapshots(group: 1, through: 4)
        try check(dispatchSnapshots.map(\.text) == ["开头", "短停顿", "新自然段", "仍同时间组"], "Copy paragraphs must not add characters to the external dispatch ledger")
        try await store.close()
    }

    func longUtteranceAndLateRevisionsNeverRegroup() async throws {
        let dir = directory(); defer { try? FileManager.default.removeItem(at: dir) }
        let store = try SaytileStore(directory: dir)
        let a = try await add(store, noon, 30, "前半")
        let b = try await add(store, noon.addingTimeInterval(30), 30, "后半")
        let before = try await store.timelinePage().entries
        let retry = try await store.beginRecognition(recordingID: a.id)
        try await store.applyRecognition(ticket: retry, text: "迟到修正", isFinal: false)
        try await store.saveEdit(recordingID: a.id, text: "我的改写")
        try await store.applyRecognition(ticket: retry, text: "不得覆盖人工", isFinal: true)
        let after = try await store.timelinePage().entries
        try check(before.map(\.paragraphID) == [1, 1] && after.map(\.paragraphID) == [1, 1])
        try check(after[0].recording.text == "我的改写" && after[1].id == b.id)
        try await store.deleteAudio(recordingID: a.id)
        try check(try await store.recording(id: a.id)?.text == "我的改写")
        try await store.close()
        let reopened = try SaytileStore(directory: dir)
        try check(try await reopened.timelinePage().entries.map(\.paragraphID) == [1, 1])
        try await reopened.close()
    }

    func paragraphsPageWithoutSplittingAndSearchReturnsEveryMember() async throws {
        let dir = directory(); defer { try? FileManager.default.removeItem(at: dir) }
        let store = try SaytileStore(directory: dir)
        var ids: [UUID] = []
        for index in 0..<135 {
            ids.append(try await add(store, noon.addingTimeInterval(Double(index * 2)), 1, index == 75 ? "唯一搜索%_" : "第\(index)句").id)
        }
        try await store.registerAudioChunk(recordingID: ids[134], relativePath: ids[134].uuidString + "/test.wav", frames: 16_000)
        _ = try await add(store, noon.addingTimeInterval(400), 1, "另段")
        let latest = try await store.archiveParagraphPage(limit: 1)
        try check(latest.paragraphs.map(\.id) == [136] && latest.hasOlder && !latest.hasNewer && !latest.paragraphs[0].hasAudio)
        let older = try await store.archiveParagraphPage(.ending(at: 135), limit: 1)
        try check(older.paragraphs.count == 1 && older.paragraphs[0].memberCount == 135 && older.hasNewer && !older.hasOlder && older.paragraphs[0].hasAudio)
        var window = TimelineWindow.starting(at: 0), read: [TimelineEntry] = []
        while true {
            let page = try await store.paragraphMembers(paragraphID: 1, window)
            try check(page.entries.count <= 64 && page.entries.allSatisfy { $0.paragraphID == 1 })
            read += page.entries
            guard page.hasNewer, let last = page.entries.last else { break }
            window = .starting(at: last.position + 1)
        }
        try check(read.map(\.id) == ids && Set(read.map(\.position)).count == 135)
        let found = try await store.archiveParagraphPage(query: "%_")
        try check(found.paragraphs.map(\.id) == [1] && found.paragraphs[0].memberCount == 135)
        try check(try await store.paragraphRecordingIDs(paragraphID: 1) == ids)
        let copied = try store.paragraphCopy(paragraphID: 1, displayed: [76: "眼前显示"])
        try check(copied.contains("第0句") && copied.contains("第134句") && copied.contains("眼前显示") && !copied.contains("唯一搜索"))
        try await store.setPinned(recordingID: ids[75], pinned: true)
        try check(try await store.archiveParagraphPage(filter: .pinned).paragraphs.map(\.id) == [1])
        try check(try await store.toggleParagraphPinned(paragraphID: 1) == false)
        try check(try await store.archiveParagraphPage(filter: .pinned).paragraphs.isEmpty)
        try check(try await store.toggleParagraphPinned(paragraphID: 1))
        try check(try await store.paragraphMembers(paragraphID: 1, .ending(at: 135)).entries.allSatisfy { $0.recording.isPinned })
        try await store.deleteRecord(recordingID: ids[0])
        let remaining = try await store.archiveParagraphPage(.ending(at: 1)).paragraphs
        try check(remaining[0].id == 1 && remaining[0].started == noon && remaining[0].memberCount == 134 && remaining[0].firstRecordingID == ids[0])
        try await store.close()
    }

    func additiveMigrationPreservesLegacyGroupsAndAllOriginalRows() async throws {
        let dir = directory(); defer { try? FileManager.default.removeItem(at: dir) }
        let old = try SaytileStore(directory: dir)
        try await old.setTimelineIdleSeconds(120)
        let a = try await add(old, noon, 1, "旧原文")
        _ = try await add(old, noon.addingTimeInterval(91), 1, "旧标题仍同组")
        try await old.saveEdit(recordingID: a.id, text: "旧人工稿")
        try await old.setPinned(recordingID: a.id, pinned: true)
        try await old.saveDraft(recordingID: a.id, text: "草稿")
        try await old.close()
        let db = try StoreDatabase(url: dir.appendingPathComponent("Saytile.sqlite"))
        let tables = ["recordings", "revisions", "editing_drafts", "chunks", "transcript_timeline"]
        let original = try tables.map { try db.rows("SELECT * FROM " + $0 + " ORDER BY rowid") }
        try db.script("DROP TRIGGER timeline_natural_paragraph; DROP TABLE timeline_paragraphs; DROP TABLE natural_paragraph_schema;")
        try db.close()
        let migrated = try SaytileStore(directory: dir)
        try check(migrated.initialTimelineIdleSeconds == 60)
        let entries = try await migrated.timelinePage().entries
        try check(entries.map(\.group) == [1, 1] && entries.map(\.paragraphID) == [1, 2])
        try await migrated.close()
        let inspected = try StoreDatabase(url: dir.appendingPathComponent("Saytile.sqlite"))
        try check(try tables.map { try inspected.rows("SELECT * FROM " + $0 + " ORDER BY rowid") } == original)
        try check(try inspected.rows("PRAGMA user_version").first?["user_version"] == "6")
        try check(try inspected.rows("PRAGMA foreign_key_check").isEmpty)
        try inspected.execute("UPDATE timeline_settings SET idle_seconds=180")
        try inspected.execute("ALTER TABLE timeline_paragraphs DROP COLUMN break_hidden")
        try inspected.execute("UPDATE natural_paragraph_schema SET version=1")
        try inspected.close()
        let custom = try SaytileStore(directory: dir)
        try check(custom.initialTimelineIdleSeconds == 180)
        let customEntries = try await custom.timelinePage().entries
        try check(customEntries.map(\.paragraphID) == [1, 2] && customEntries.allSatisfy { !$0.paragraphBreakHidden })
        try await custom.close()
    }

    @MainActor func multiRecordingEditValidatesEveryOwnerAndPreservesVersions() async throws {
        let dir = directory(); defer { try? FileManager.default.removeItem(at: dir) }
        let store = try SaytileStore(directory: dir)
        let a = try await add(store, noon, 1, "甲😀")
        let b = try await add(store, noon.addingTimeInterval(2), 1, "乙")
        let other = try await add(store, noon.addingTimeInterval(20), 1, "另段")
        do {
            _ = try store.editArchiveParagraph(id: 1, edits: [.init(id: a.id, before: "甲😀", after: "错误修改"), .init(id: other.id, before: "另段", after: "跨段")])
            throw Failure(description: "Accepted an edit from another paragraph")
        } catch is StoreError {}
        try check(try await store.recording(id: a.id)?.text == "甲😀")
        let updated = try store.editArchiveParagraph(id: 1, edits: [.init(id: a.id, before: "甲😀", after: "甲😀修改\n"), .init(id: b.id, before: "乙", after: "乙修改")])
        try check(updated.map(\.id) == [a.id, b.id] && updated.allSatisfy { $0.preferredOrigin == .userEdit })
        try await store.saveEdit(recordingID: b.id, text: "其他窗口新稿")
        do {
            _ = try store.editArchiveParagraph(id: 1, edits: [.init(id: a.id, before: "甲😀修改\n", after: "不能部分提交"), .init(id: b.id, before: "乙修改", after: "覆盖")])
            throw Failure(description: "Accepted stale edit")
        } catch is StoreError {}
        try check(try await store.recording(id: a.id)?.text == "甲😀修改\n")
        let aVersions = try await store.revisions(recordingID: a.id), bVersions = try await store.revisions(recordingID: b.id)
        try check(aVersions.count == 2 && bVersions.count == 3)
        try await store.close()
    }

    @MainActor func ordinaryHeadEditKeepsParagraphAndWinsOverLateMachineRevision() async throws {
        let dir = directory(); defer { try? FileManager.default.removeItem(at: dir) }
        let store = try SaytileStore(directory: dir)
        _ = try await add(store, noon, 1, "前句")
        let b = try await add(store, noon.addingTimeInterval(20), 1, "眼前原稿")
        let ticket = try await store.beginRecognition(recordingID: b.id)
        try await store.applyRecognition(ticket: ticket, text: "后台机器修订", isFinal: false)
        let changed = try store.editArchiveParagraph(id: 2, edits: [.init(id: b.id, before: "眼前原稿", after: "本人改字")])
        try check(changed.first?.recording.text == "本人改字" && changed.first?.preferredOrigin == .userEdit)
        try check(try store.timelineCopy(group: 1, through: 2, displayed: [:]) == "前句\n本人改字")
        try await store.applyRecognition(ticket: ticket, text: "迟到终稿", isFinal: true)
        try await store.finishRecognition(ticket: ticket)
        try check(try await store.recording(id: b.id)?.text == "本人改字")
        let versions = try await store.revisions(recordingID: b.id)
        try check(Set(versions.map(\.text)) == ["眼前原稿", "后台机器修订", "本人改字", "迟到终稿"])
        try await store.close()
    }

    @MainActor func conflictDraftPreservesBothWritersWithoutSelectingEitherDraft() async throws {
        let dir = directory(); defer { try? FileManager.default.removeItem(at: dir) }
        let store = try SaytileStore(directory: dir)
        let a = try await add(store, noon)
        let base = try await store.saveEdit(recordingID: a.id, text: "共同原文")
        try store.writeArchiveDraft(recordingID: a.id, text: "另一处未完成草稿", basedOn: base.id)
        let preferred = try await store.saveEdit(recordingID: a.id, text: "另一处已保存", clearingDraftMatching: "不匹配", basedOn: base.id)
        let failed = PanelRowEdit(id: a.id, before: "共同原文", after: "眼前未保存修改")
        do {
            _ = try store.editArchiveParagraph(id: 1, edits: [failed])
            throw Failure(description: "Accepted conflicting human version")
        } catch is StoreError {}
        try store.preserveArchiveParagraphDraft(id: 1, edits: [failed], bases: [a.id: base.id])
        try check(try await store.recording(id: a.id)?.preferredRevisionID == preferred.id)
        let pending = try await store.archiveDraft(recordingID: a.id)
        try check(pending?.text == failed.after && pending?.base == base.id)
        let versions = try await store.revisions(recordingID: a.id)
        try check(versions.contains { $0.text == "另一处未完成草稿" && $0.origin == .userEdit })
        try store.preserveArchiveParagraphDraft(id: 1, edits: [failed], bases: [a.id: base.id])
        try check(try await store.revisions(recordingID: a.id).count == versions.count)
        do {
            try store.preserveArchiveParagraphDraft(id: 999, edits: [failed], bases: [a.id: base.id])
            throw Failure(description: "Saved a draft under wrong paragraph")
        } catch is StoreError {}
        try await store.close()
        let reopened = try SaytileStore(directory: dir)
        try check(try await reopened.recording(id: a.id)?.preferredRevisionID == preferred.id)
        try check(try await reopened.loadDraft(recordingID: a.id) == failed.after)
        try check(try await reopened.revisions(recordingID: a.id).contains { $0.text == "另一处未完成草稿" })
        try await reopened.close()
    }

    @MainActor func emptyHumanRowsDoNotInventBoundaryIntentOrEvictVisibleText() async throws {
        let dir = directory(); defer { try? FileManager.default.removeItem(at: dir) }
        let store = try SaytileStore(directory: dir)
        _ = try await add(store, noon, 1, "前段")
        let b = try await add(store, noon.addingTimeInterval(20), 1, "本段开头")
        try await store.saveEdit(recordingID: b.id, text: "")
        let c = try await add(store, noon.addingTimeInterval(22), 1, "继续")
        for index in 0..<65 {
            let r = try await store.createRecording(createdAt: noon.addingTimeInterval(24 + Double(index)))
            try await store.finishRecording(id: r.id, speechEndedAt: noon.addingTimeInterval(25 + Double(index)))
            try await store.saveEdit(recordingID: r.id, text: "")
        }
        let panel = try await store.panelTimeline(.latest)
        try check(panel.page.entries.count == 2)
        try check(panel.page.entries.first?.recording.text == "前段" && panel.page.entries.last?.recording.text == "继续")
        try check(panel.textTail?.id == c.id)
        try check(try store.timelineCopy(group: 1, through: 68, displayed: [:]) == "前段\n继续")
        _ = try store.editTimeline([.init(id: b.id, before: "", after: "", paragraphBreakHidden: true, previousParagraphBreakHidden: false)], window: .latest)
        try check(try store.timelineCopy(group: 1, through: 68, displayed: [:]) == "前段继续")
        let hidden = try await store.panelTimeline(.latest)
        try check(hidden.page.entries.last?.paragraphBreakHidden == true)
        _ = try store.editTimeline([.init(id: b.id, before: "", after: "", paragraphBreakHidden: false, previousParagraphBreakHidden: true)], window: .latest)
        try check(try store.timelineCopy(group: 1, through: 68, displayed: [:]) == "前段\n继续")
        try await store.close()
    }

    @MainActor func explicitBoundaryEditIsReversibleAndDoesNotFreezeOrRewriteASR() async throws {
        let dir = directory(); defer { try? FileManager.default.removeItem(at: dir) }
        let store = try SaytileStore(directory: dir)
        _ = try await add(store, noon, 1, "第一段")
        let b = try await add(store, noon.addingTimeInterval(20), 1, "第二段")
        let c = try await add(store, noon.addingTimeInterval(22), 1, "接续")
        let ticket = try await store.beginRecognition(recordingID: b.id)
        try await store.applyRecognition(ticket: ticket, text: "第二段有新增", isFinal: false)
        let originalCount = try await store.revisions(recordingID: b.id).count
        _ = try store.editTimeline([.init(id: b.id, before: "第二段", after: "第二段", paragraphBreakHidden: true, previousParagraphBreakHidden: false)], window: .latest)
        try check(try await store.recording(id: b.id)?.text == "第二段有新增")
        try check(try await store.revisions(recordingID: b.id).count == originalCount)
        do {
            _ = try store.editTimeline([.init(id: b.id, before: "第二段有新增", after: "不得写入", paragraphBreakHidden: true, previousParagraphBreakHidden: false)], window: .latest)
            throw Failure(description: "Accepted stale paragraph boundary")
        } catch is StoreError {}
        do {
            _ = try store.editTimeline([.init(id: b.id, before: "第二段有新增", after: "不得部分写入", paragraphBreakHidden: false, previousParagraphBreakHidden: true),
                                       .init(id: c.id, before: "接续", after: "接续", paragraphBreakHidden: true, previousParagraphBreakHidden: true)], window: .latest)
            throw Failure(description: "Accepted contradictory edits to one paragraph boundary")
        } catch is StoreError {}
        try check(try await store.recording(id: b.id)?.text == "第二段有新增")
        try await store.applyRecognition(ticket: ticket, text: "第二段最终", isFinal: true)
        try await store.finishRecognition(ticket: ticket)
        try check(try store.timelineCopy(group: 1, through: 3, displayed: [:]) == "第一段第二段最终接续")
        _ = try store.editTimeline([.init(id: b.id, before: "第二段最终", after: "第二段最终", paragraphBreakHidden: false, previousParagraphBreakHidden: true)], window: .latest)
        try check(try store.timelineCopy(group: 1, through: 3, displayed: [:]) == "第一段\n第二段最终接续")
        _ = try store.editTimeline([.init(id: b.id, before: "第二段最终", after: "第二段最终", paragraphBreakHidden: true, previousParagraphBreakHidden: false)], window: .latest)
        try await store.close()
        let reopened = try SaytileStore(directory: dir)
        let members = try await reopened.paragraphMembers(paragraphID: 2).entries
        try check(members.count == 2 && members.allSatisfy { $0.paragraphBreakHidden && $0.preferredOrigin == .final })
        try await reopened.close()
    }

    func starredParagraphProtectsNewMembersAndStopsAtNextParagraph() async throws {
        let dir = directory(); defer { try? FileManager.default.removeItem(at: dir) }
        let store = try SaytileStore(directory: dir)
        let a = try await add(store, noon)
        try check(try await store.toggleParagraphPinned(paragraphID: 1))
        let b = try await add(store, noon.addingTimeInterval(2))
        try check(try await store.recording(id: b.id)?.isPinned == true)
        try check(try await store.cleanupCandidates(olderThan: noon.addingTimeInterval(1000)).isEmpty)
        try check(try await store.toggleParagraphPinned(paragraphID: 1) == false)
        let c = try await add(store, noon.addingTimeInterval(4))
        try check(try await store.recording(id: c.id)?.isPinned == false)
        try check(try await store.cleanupCandidates(olderThan: noon.addingTimeInterval(1000)).map(\.id) == [a.id, b.id, c.id])
        try check(try await store.toggleParagraphPinned(paragraphID: 1))
        let d = try await add(store, noon.addingTimeInterval(20))
        try check(try await store.recording(id: d.id)?.isPinned == false)
        try check(try await store.cleanupCandidates(olderThan: noon.addingTimeInterval(1000)).map(\.id) == [d.id])
        try await store.close()
    }

    func midnightClockReversalAndDurableFrameFallback() async throws {
        let dir = directory(); defer { try? FileManager.default.removeItem(at: dir) }
        let store = try SaytileStore(directory: dir)
        let start = Calendar.current.startOfDay(for: noon).addingTimeInterval(86_399)
        _ = try await add(store, start, 0.5)
        _ = try await add(store, start.addingTimeInterval(1), 1)
        _ = try await add(store, start.addingTimeInterval(0.9), 1)
        let first = try await store.timelinePage().entries
        try check(Set(first.map(\.paragraphID)).count == 3 && Set(first.map(\.group)).count == 3)
        let a = try await store.createRecording(createdAt: start.addingTimeInterval(100))
        try await store.registerAudioChunk(recordingID: a.id, relativePath: a.id.uuidString + "/test.wav", frames: 160_000)
        try await store.finishRecording(id: a.id)
        _ = try await add(store, start.addingTimeInterval(124.999), 1)
        let last = try await store.timelinePage().entries
        try check(last[3].paragraphID == last[4].paragraphID && last[3].speechEnd == start.addingTimeInterval(110))
        try await store.close()
    }
}

@main struct RunNaturalParagraphs {
 @MainActor static func main() async throws {
 let t=NaturalParagraphTests()
 try await t.actualSpeechGapHasIndependentParagraphAndTimeGroupThresholds(); print("PASS actualSpeechGapHasIndependentParagraphAndTimeGroupThresholds")
 try await t.longUtteranceAndLateRevisionsNeverRegroup(); print("PASS longUtteranceAndLateRevisionsNeverRegroup")
 try await t.paragraphsPageWithoutSplittingAndSearchReturnsEveryMember(); print("PASS paragraphsPageWithoutSplittingAndSearchReturnsEveryMember")
 try await t.additiveMigrationPreservesLegacyGroupsAndAllOriginalRows(); print("PASS additiveMigrationPreservesLegacyGroupsAndAllOriginalRows")
 try await t.multiRecordingEditValidatesEveryOwnerAndPreservesVersions(); print("PASS multiRecordingEditValidatesEveryOwnerAndPreservesVersions")
 try await t.ordinaryHeadEditKeepsParagraphAndWinsOverLateMachineRevision(); print("PASS ordinaryHeadEditKeepsParagraphAndWinsOverLateMachineRevision")
 try await t.conflictDraftPreservesBothWritersWithoutSelectingEitherDraft(); print("PASS conflictDraftPreservesBothWritersWithoutSelectingEitherDraft")
 try await t.emptyHumanRowsDoNotInventBoundaryIntentOrEvictVisibleText(); print("PASS emptyHumanRowsDoNotInventBoundaryIntentOrEvictVisibleText")
 try await t.explicitBoundaryEditIsReversibleAndDoesNotFreezeOrRewriteASR(); print("PASS explicitBoundaryEditIsReversibleAndDoesNotFreezeOrRewriteASR")
 try await t.starredParagraphProtectsNewMembersAndStopsAtNextParagraph(); print("PASS starredParagraphProtectsNewMembersAndStopsAtNextParagraph")
 try await t.midnightClockReversalAndDurableFrameFallback(); print("PASS midnightClockReversalAndDurableFrameFallback")
 print("NATURAL_PARAGRAPHS_PASS tests=11")
 }
}
