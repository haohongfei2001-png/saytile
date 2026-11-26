import Foundation
import Testing
@testable import SaytileKit
@testable import SaytileVoiceUI

struct ParagraphReuseTests {
    private func directory() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("saytile-paragraph-reuse-\(UUID())")
    }

    private var start: Date {
        Calendar.current.startOfDay(for: Date(timeIntervalSince1970: 1_800_000_000)).addingTimeInterval(43_200)
    }

    private func add(_ store: SaytileStore, at date: Date, text: String,
                     final: Bool = true) async throws -> (record: Recording, ticket: RecognitionTicket) {
        let record = try await store.createRecording(createdAt: date)
        try await store.finishRecording(id: record.id, speechEndedAt: date.addingTimeInterval(1))
        let ticket = try await store.beginRecognition(recordingID: record.id)
        try await store.applyRecognition(ticket: ticket, text: text, isFinal: final)
        if final { try await store.finishRecognition(ticket: ticket) }
        return (record, ticket)
    }

    @Test func wholeParagraphCopyAndFrozenInsertionIncludeOffscreenTextAndVisibleTail() async throws {
        let dir = directory(); defer { try? FileManager.default.removeItem(at: dir) }
        let store = try SaytileStore(directory: dir)
        for index in 0..<129 {
            _ = try await add(store, at: start.addingTimeInterval(Double(index * 2)), text: "word\(index)")
        }
        let tail = try await add(store, at: start.addingTimeInterval(258), text: "tailWord", final: false)
        let page = try await store.timelinePage()
        let last = try #require(page.entries.last)
        #expect(page.hasOlder && page.entries.count == TimelinePage.capacity)
        #expect(page.entries.first?.position == 67)

        var displayed = Dictionary(uniqueKeysWithValues: page.entries.map { ($0.position, $0.recording.text) })
        displayed[last.position] = "tail" // The visible prefix of the real current partial.
        let snapshots = try store.paragraphTextSnapshots(paragraphID: last.paragraphID, through: last.position,
            rendered: page.entries.map(TimelineTextSnapshot.init), displayed: displayed)
        let expected = ((0..<129).map { "word\($0)" } + ["tail"]).joined(separator: " ")
        let copied = try store.paragraphCopy(paragraphID: last.paragraphID, through: last.position, displayed: displayed)
        #expect(snapshots.count == 130)
        #expect(copied.utf16.elementsEqual(expected.utf16))
        #expect(snapshots.map(\.text).joined().utf16.elementsEqual(copied.utf16))
        #expect(snapshots.last?.sourceText == "tailWord" && snapshots.last?.text == " tail")

        var frozen: [TranscriptRevision] = []
        for snapshot in snapshots {
            let revisionID = try #require(snapshot.revisionID)
            frozen.append(try await store.freezeRevision(recordingID: snapshot.recordingID,
                revisionID: revisionID, text: snapshot.sourceText, presentationText: snapshot.text))
        }
        #expect(frozen.map(\.text).joined().utf16.elementsEqual(copied.utf16))
        let beforeFinal = try await store.recording(id: tail.record.id)
        #expect(beforeFinal?.preferredRevisionID == last.recording.preferredRevisionID)
        #expect(beforeFinal?.text == "tailWord")

        try await store.applyRecognition(ticket: tail.ticket, text: "revisedTail", isFinal: true)
        try await store.finishRecognition(ticket: tail.ticket)
        let continued = try await add(store, at: start.addingTimeInterval(260), text: "continued")
        let updated = try await store.timelinePage()
        #expect(updated.entries.last?.id == continued.record.id)
        #expect(updated.entries.last?.paragraphID == last.paragraphID,
                "Copying and freezing must not turn the next short-pause capture into a new paragraph")
        let retained = try await store.revisions(recordingID: tail.record.id)
        let frozenTail = try #require(frozen.last)
        #expect(retained.contains { $0.id == frozenTail.id && $0.text.utf16.elementsEqual(" tail".utf16) })
        #expect(copied.utf16.elementsEqual(expected.utf16))
        #expect(frozen.map(\.text).joined().utf16.elementsEqual(expected.utf16))
        try await store.close()
    }

    @Test func paragraphReuseKeepsCompletedUserEditsWhenFinalRecognitionArrives() async throws {
        let dir = directory(); defer { try? FileManager.default.removeItem(at: dir) }
        let store = try SaytileStore(directory: dir)
        let first = try await add(store, at: start, text: "识别中的原稿", final: false)
        _ = try await add(store, at: start.addingTimeInterval(2), text: "继续表达。")
        let edited = "本人修改🙂\n保留手工换行。"
        let userVersion = try await store.saveEdit(recordingID: first.record.id, text: edited)
        let page = try await store.timelinePage()
        let displayed = Dictionary(uniqueKeysWithValues: page.entries.map { ($0.position, $0.recording.text) })
        let snapshots = try store.paragraphTextSnapshots(paragraphID: 1,
            rendered: page.entries.map(TimelineTextSnapshot.init), displayed: displayed)
        let copied = try store.paragraphCopy(paragraphID: 1, displayed: displayed)
        let expected = edited + "继续表达。"
        #expect(copied.utf16.elementsEqual(expected.utf16))
        var frozen: [TranscriptRevision] = []
        for snapshot in snapshots {
            frozen.append(try await store.freezeRevision(recordingID: snapshot.recordingID,
                revisionID: try #require(snapshot.revisionID), text: snapshot.sourceText, presentationText: snapshot.text))
        }

        try await store.applyRecognition(ticket: first.ticket, text: "迟到的模型终稿不得追加或覆盖。", isFinal: true)
        try await store.finishRecognition(ticket: first.ticket)
        let current = try await store.recording(id: first.record.id)
        #expect(current?.preferredRevisionID == userVersion.id && current?.text == edited)
        let currentCopy = try store.paragraphCopy(paragraphID: 1, displayed: [:])
        #expect(currentCopy.utf16.elementsEqual(expected.utf16))
        #expect(frozen.map(\.text).joined().utf16.elementsEqual(copied.utf16))
        let history = try await store.revisions(recordingID: first.record.id)
        #expect(history.contains { $0.text == "迟到的模型终稿不得追加或覆盖。" && $0.origin == .final })
        try await store.close()
    }

    @Test func frozenPresentationPreservesExactUnicodeAndRejectsWrongSource() async throws {
        let dir = directory(); defer { try? FileManager.default.removeItem(at: dir) }
        let store = try SaytileStore(directory: dir)
        let nfc = "caf\u{00E9}", nfd = "cafe\u{0301}"
        #expect(nfc == nfd && !nfc.utf16.elementsEqual(nfd.utf16))
        let seed = try await add(store, at: start, text: nfc)
        let page = try await store.timelinePage()
        let source = try #require(page.entries.first)
        let revisionID = try #require(source.recording.preferredRevisionID)
        let snapshots = try store.paragraphTextSnapshots(paragraphID: source.paragraphID,
            rendered: [TimelineTextSnapshot(source)], displayed: [source.position: nfd])
        let snapshot = try #require(snapshots.first)
        let frozen = try await store.freezeRevision(recordingID: snapshot.recordingID,
            revisionID: revisionID, text: snapshot.sourceText, presentationText: snapshot.text)
        let copied = try store.paragraphCopy(paragraphID: source.paragraphID, displayed: [source.position: nfd])
        #expect(frozen.id != revisionID)
        #expect(frozen.text.utf16.elementsEqual(nfd.utf16) && frozen.text.utf16.elementsEqual(copied.utf16))
        let preferred = try await store.recording(id: seed.record.id)
        #expect(preferred?.preferredRevisionID == revisionID)
        #expect(preferred?.text.utf16.elementsEqual(nfc.utf16) == true)

        // A canonically equivalent but different source is not this immutable revision.
        await #expect(throws: StoreError.self) {
            try await store.freezeRevision(recordingID: seed.record.id, revisionID: revisionID, text: nfd)
        }
        await #expect(throws: StoreError.self) {
            try await store.freezeRevision(recordingID: seed.record.id, revisionID: revisionID,
                text: "not this revision", presentationText: "visible")
        }
        try await store.close()
    }

    @Test func explicitSelectionUsesItsOriginalParagraphIdentityEvenWhenTextRepeats() {
        struct Row: VoiceTranscriptEntry {
            let id = UUID()
            let position: Int64
            let paragraphID: Int64
            let displayText: String
        }
        let document = PanelTimelineDocument(entries: [
            Row(position: 1, paragraphID: 1, displayText: "重复🙂"),
            Row(position: 2, paragraphID: 1, displayText: "旧段后半"),
            Row(position: 3, paragraphID: 3, displayText: "重复🙂")
        ])
        let text = document.text as NSString
        let firstEmoji = text.range(of: "🙂")
        let lastEmoji = text.range(of: "🙂", options: .backwards)
        #expect(firstEmoji.location != lastEmoji.location)
        #expect(document.selectedParagraphID(in: firstEmoji) == 1)
        #expect(document.selectedParagraphID(in: lastEmoji) == 3)
        #expect(document.selectedParagraphID(in: NSRange(location: firstEmoji.location,
            length: NSMaxRange(lastEmoji) - firstEmoji.location)) == 1)
        #expect(document.selectedParagraphID(in: NSRange(location: lastEmoji.location, length: 0)) == nil)
        #expect(document.selectedParagraphID(in: NSRange(location: text.length, length: 1)) == nil)
        #expect(document.selectedParagraphID(in: NSRange(location: NSNotFound, length: 1)) == nil)
        #expect(document.selectedParagraphID(in: NSRange(location: -1, length: 2)) == nil)
        #expect(document.selectedParagraphID(in: NSRange(location: 1, length: Int.max)) == nil)
    }
}
