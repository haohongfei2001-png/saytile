import Foundation
import Testing
@testable import SaytileKit

@Suite struct TranscriptTimelineTests {
    @Test func speechBoundariesRevisionIdentityAndSnapshot() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = try SaytileStore(directory: dir)
        let day = Calendar.current.startOfDay(for: .now).addingTimeInterval(43200)
        func add(_ delta: Double, _ end: Double, _ text: String) async throws -> Recording {
            let r = try await store.createRecording(createdAt: day.addingTimeInterval(delta))
            try await store.finishRecording(id: r.id, speechEndedAt: day.addingTimeInterval(end))
            try await store.saveEdit(recordingID: r.id, text: text)
            return r
        }
        let a = try await add(0, 120, "原话")
        _ = try await add(239.9, 240, "接续")
        let c = try await add(360, 361, "新组")
        let p = try await store.timelinePage().entries
        #expect(p.map(\.group) == [p[0].position,p[0].position,p[2].position])
        #expect(p[1].groupStart == day)
        try await store.saveEdit(recordingID: a.id, text: "保留修改")
        try await store.deleteAudio(recordingID: a.id)
        let changed = try await store.timelinePage().entries
        #expect(changed.map(\.id) == p.map(\.id))
        #expect(changed[0].recording.text == "保留修改")
        #expect(try store.timelineCopy(group: p[0].group, through: p[1].position, displayed: [p[0].position:"原话"]) == "原话\n接续")
        #expect(try store.timelineCopy(group: p[0].group, through: p[1].position, displayed: [p[1].position:""]) == "保留修改")
        #expect(try store.timelineCopy(group: p[2].group, through: p[2].position, displayed: [:]) == "新组")
        try await store.setTimelineIdleSeconds(600)
        _ = try await add(490, 491, "修改阈值")
        let rolled = try await add(488, 489, "时钟拨回")
        let midnight = Calendar.current.startOfDay(for: day.addingTimeInterval(86400))
        let last = try await store.createRecording(createdAt: midnight.addingTimeInterval(-1))
        let next = try await store.createRecording(createdAt: midnight)
        try await store.close()
        let reopened = try SaytileStore(directory: dir)
        let history = try await reopened.timelinePage().entries
        #expect(reopened.initialTimelineIdleSeconds == 600)
        #expect(history[3].group == history[2].group && history[2].id == c.id)
        #expect(history[4].id == rolled.id && history[4].group == history[4].position)
        #expect(history[5].id == last.id && history[6].id == next.id)
        #expect(history[5].groupDay != history[6].groupDay)
    }

    @Test func migrationAndKeysetTraversalAtScale() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let old = try SaytileStore(directory: dir)
        let keep = try await old.createRecording()
        try await old.saveEdit(recordingID: keep.id, text: "保留旧稿")
        try await old.close()
        let fixture = try StoreDatabase(url: dir.appendingPathComponent("Saytile.sqlite"))
        try fixture.script("""
            DROP TRIGGER timeline_record; DROP TABLE transcript_timeline; DROP TABLE timeline_settings;
            PRAGMA user_version=5;
            WITH RECURSIVE seq(x) AS (VALUES(1) UNION ALL SELECT x+1 FROM seq WHERE x<12000)
            INSERT INTO recordings(id,created_at,sample_rate,is_recording)
            SELECT printf('00000000-0000-4000-8000-%012d',x),1700000000+x,16000,0 FROM seq;
            """)
        try fixture.close()
        let start = ContinuousClock.now
        let migrated = try SaytileStore(directory: dir)
        var page = try await migrated.timelinePage(), count = 0, previous = Int64.max, queries = 0
        while true {
            #expect(page.entries.count <= TimelinePage.capacity)
            guard let first = page.entries.first, let last = page.entries.last else { break }
            #expect(last.position < previous)
            count += page.entries.count; queries += 1; previous = first.position
            guard page.hasOlder else { break }
            page = try await migrated.timelinePage(.ending(at: first.position - 1))
        }
        #expect(count == 12001 && queries == 188)
        #expect(try await migrated.recording(id: keep.id)?.text == "保留旧稿")
        print("TIMELINE_SCALE rows=\(count) page_reads=\(queries) max_resident_rows=64 migration_and_traversal=\(start.duration(to: .now))")
    }

    @Test func manualRoutingIsExclusiveAndFailClosed() throws {
        var config = RecognitionConfiguration()
        config.languagePreference = .chinese
        let english = try #require(config.models.first { $0.purpose == .englishASR })
        config.manualASRConfigurationID = english.id
        #expect(try config.resolvedForCurrentLanguage().enabledModels.filter { $0.purpose.isStreaming }.map(\.id) == [english.id])
        let factory = RecognitionSessionFactory(configuration: config)
        let original = factory.snapshot
        config.manualASRConfigurationID = nil
        factory.update(config, nextUtteranceOnly: true)
        #expect(original.configuration.selectedASRModel?.id == english.id)
        #expect(factory.snapshot.configuration.selectedASRModel?.purpose == .chineseASR)
        config.manualASRConfigurationID = UUID()
        #expect(config.selectedASRModel == nil)
    }
}
