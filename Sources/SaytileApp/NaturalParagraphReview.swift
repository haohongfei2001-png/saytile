import AppKit
import SwiftUI
import CryptoKit
import SaytileKit
import SaytileVoiceUI

/// Explicit --ui-review only: synthetic ASR-origin rows, private pasteboard,
/// silent originals and owned nonactivating native windows. No ASR or microphone.
extension AppDelegate {
    @MainActor func reviewNaturalParagraphs(model: AppModel, output: URL) async throws {
        guard try await model.store.listRecordings(limit: 1).isEmpty,
              let board = model.copyPasteboard, board.name != NSPasteboard.general.name,
              model.audio.state == .paused, !model.directMode else {
            throw ReviewFailure("natural-paragraph review requires an empty isolated store and private pasteboard")
        }
        try await model.store.setTimelineIdleSeconds(60)
        let base = Calendar.current.startOfDay(for: Date()).addingTimeInterval(10 * 3600)
        let starts: [TimeInterval] = [0, 4, 20, 81]
        var texts = ["我们先把这个想法记下来，", "稍微停顿之后继续，文字仍然属于同一段。",
                     "隔了一会儿再说，这是同一个时间组里的新自然段。", "一分钟后开启另一段输入，回看时再显示新的时间。"]
        var recordings: [Recording] = []
        var tickets: [RecognitionTicket] = []
        for index in texts.indices {
            let row = try await model.store.createRecording(createdAt: base.addingTimeInterval(starts[index]))
            let ticket = try await model.store.beginRecognition(recordingID: row.id)
            _ = try await model.store.applyRecognition(ticket: ticket, text: texts[index], isFinal: index > 1)
            try await addSilentReviewAudio(model: model, recordingID: row.id, frames: 16_000)
            try await model.store.finishRecording(id: row.id, speechEndedAt: base.addingTimeInterval(starts[index] + 1))
            recordings.append(row); tickets.append(ticket)
        }
        await model.refresh()
        let initial = try await model.store.timelinePage().entries
        guard initial.count == 4, initial.allSatisfy({ $0.preferredOrigin != .userEdit }),
              initial[0].paragraphID == initial[1].paragraphID,
              initial[1].paragraphID != initial[2].paragraphID,
              initial[2].paragraphID != initial[3].paragraphID,
              initial[0].group == initial[2].group, initial[2].group != initial[3].group else {
            throw ReviewFailure("3/15/60-second speech-end gaps did not form three paragraphs and two time groups")
        }
        let ids = recordings.map(\.id)
        let sourceText = texts[0] + texts[1] + "\n" + texts[2] + "\n" + texts[3]
        guard PanelTimelineDocument(entries: initial).text == sourceText,
              model.archiveGroups.flatMap(\.paragraphs).count == 3, model.archiveGroups.count == 2 else {
            throw ReviewFailure("archive and live panel did not use the same paragraph identities")
        }
        var checks: [String] = ["ASR-origin seed", "three-second continuation", "15-second paragraph", "60-second time group"]
        try await reviewValidatedWindow(InputPanelWindowView(model: model), size: .init(width: 340, height: 360),
            name: "natural-panel", output: output, validation: { host in
                let scroll = try self.compactTranscript(in: host)
                try await self.reviewUntil { scroll.transcriptView.string == sourceText }
                guard scroll.rendered.spans.map({ $0.entry.id }) == ids else { throw ReviewFailure("panel reordered source owners") }
                try self.captureReview(host, name: "natural-panel-before-revision", output: output)
                let editor = scroll.transcriptView
                editor.commandPasteboard = board
                let selection = NSRange(location: 0, length: 2)
                editor.setSelectedRange(selection)
                editor.copy(nil)
                guard board.string(forType: .string) == "我们" else { throw ReviewFailure("panel selection did not copy to private pasteboard") }
                let copied = board.changeCount
                let origin = scroll.contentView.bounds.origin
                texts[0] = "我们先把这一段想法记下来，"
                _ = try await model.store.applyRecognition(ticket: tickets[0], text: texts[0], isFinal: true)
                await model.refresh()
                try await Task.sleep(for: .milliseconds(150))
                guard editor.string == sourceText, editor.selectedRange() == selection,
                      scroll.contentView.bounds.origin == origin, board.changeCount == copied else {
                    throw ReviewFailure("late revision disturbed selected text, reading position or copied snapshot")
                }
                editor.setSelectedRange(.init(location: 0, length: 0))
                let expected = texts[0] + texts[1] + "\n" + texts[2] + "\n" + texts[3]
                try await self.reviewUntil { editor.string == expected }
                guard scroll.rendered.spans.map({ $0.entry.id }) == ids else { throw ReviewFailure("late ASR moved to the end") }
                checks += ["panel selection/copy", "selected viewport held", "late ASR retains original position"]
            }, interaction: nil)

        await model.refresh()
        let beforeArchive = try await model.store.timelinePage().entries
        let panelText = PanelTimelineDocument(entries: beforeArchive).text
        let paragraphs = model.archiveGroups.flatMap(\.paragraphs).sorted { $0.id < $1.id }
        guard paragraphs.map(\.text).joined(separator: "\n") == panelText,
              let first = paragraphs.first, first.page.entries.map(\.id) == Array(ids.prefix(2)) else {
            throw ReviewFailure("archive paragraph aggregation differs from the panel")
        }
        var archiveInventory: [String] = []
        try await reviewValidatedWindow(SettingsView(model: model, initialPage: .archive), size: .init(width: 1000, height: 760),
            name: "natural-archive", output: output, validation: { host in
                try await self.reviewUntil { host.layoutSubtreeIfNeeded(); return self.naturalEditors(in: host).count == 3 }
                let editors = self.naturalEditors(in: host)
                guard Set(editors.compactMap { $0.accessibilityIdentifier() }) == Set(paragraphs.map { "archive.text.\($0.anchorID)" }) else {
                    throw ReviewFailure("archive retained per-recording editors instead of one per paragraph")
                }
                try self.captureReview(host, name: "natural-archive-reading", output: output)
                for paragraph in paragraphs {
                    let focused = try await self.archiveEditor(paragraph.anchorID, in: host)
                    guard host.window?.makeFirstResponder(focused) == true else { throw ReviewFailure("archive focus did not reveal its actions") }
                    try await Task.sleep(for: .milliseconds(100))
                    host.layoutSubtreeIfNeeded()
                    let nodes = self.naturalAccessibility(in: host)
                    archiveInventory += nodes.compactMap { $0.accessibilityIdentifier() }.filter { $0.hasPrefix("archive.") }
                    for prefix in ["archive.play.", "archive.favorite."] {
                        guard nodes.filter({ $0.accessibilityIdentifier() == prefix + paragraph.anchorID.uuidString }).count == 1 else {
                            let diagnostic = nodes.map { ["id": $0.accessibilityIdentifier() ?? "", "role": $0.accessibilityRole()?.rawValue ?? "", "label": $0.accessibilityLabel() ?? ""] }
                            try JSONSerialization.data(withJSONObject: diagnostic, options: [.prettyPrinted, .sortedKeys])
                                .write(to: output.appendingPathComponent("owned-archive-accessibility.json"))
                            throw ReviewFailure("focused paragraph did not have exactly one play/star control: \(prefix)\(paragraph.anchorID)")
                        }
                    }
                }
                archiveInventory = Array(Set(archiveInventory)).sorted()
                guard let editor = try await self.archiveEditor(first.anchorID, in: host) as? ArchiveParagraphTextView,
                      host.window?.makeFirstResponder(editor) == true else { throw ReviewFailure("archive paragraph could not acquire native editing focus") }
                editor.commandPasteboard = board
                let before = editor.string
                let crossing = NSRange(location: texts[0].utf16.count - 1, length: 2)
                let inserted = "，🙂继续"
                let expected = (before as NSString).replacingCharacters(in: crossing, with: inserted)
                guard let undo = editor.undoManager else { throw ReviewFailure("archive native undo is unavailable") }
                undo.groupsByEvent = false
                undo.beginUndoGrouping(); editor.breakUndoCoalescing()
                editor.insertText(inserted, replacementRange: crossing)
                undo.endUndoGrouping()
                let paragraphID = first.id
                func storedText() async throws -> String {
                    PanelTimelineDocument(entries: try await model.store.paragraphMembers(paragraphID: paragraphID).entries).text
                }
                guard editor.string == expected, try await storedText() == expected else {
                    throw ReviewFailure("cross-recording emoji edit did not commit exact displayed text")
                }
                let emoji = (editor.string as NSString).range(of: "🙂")
                editor.setSelectedRange(emoji); editor.copy(nil)
                guard board.string(forType: .string) == "🙂" else { throw ReviewFailure("archive emoji selection copy failed") }
                let clipboardSnapshot = board.changeCount
                undo.undo()
                guard editor.string == before, try await storedText() == before else { throw ReviewFailure("archive undo did not restore both original owners") }
                undo.redo()
                guard editor.string == expected, try await storedText() == expected else { throw ReviewFailure("archive redo lost the multi-owner edit") }
                _ = try await model.store.applyRecognition(ticket: tickets[1], text: "迟到的识别不能覆盖人工修改。", isFinal: true)
                await model.refresh()
                guard try await storedText() == expected, board.changeCount == clipboardSnapshot,
                      try await model.store.revisions(recordingID: ids[1]).contains(where: { $0.text == "迟到的识别不能覆盖人工修改。" }) else {
                    throw ReviewFailure("late ASR overwrote a manual paragraph or its copied snapshot")
                }
                try await self.naturalPress("archive.favorite.\(first.anchorID)", in: host)
                try await self.reviewUntil { model.archiveGroups.flatMap(\.paragraphs).contains { $0.id == first.id && $0.pinned } }
                for id in ids.prefix(2) {
                    guard try await model.store.recording(id: id)?.isPinned == true else { throw ReviewFailure("paragraph star omitted an original recording") }
                }
                try self.captureReview(host, name: "natural-archive-editing", output: output)
                try await self.naturalPress("archive.play.\(first.anchorID)", in: host)
                try await self.reviewUntil { model.audio.playingID == first.anchorID && model.audio.playbackPosition > 1.1 }
                guard abs(model.audio.playbackDuration - 2) < 0.02 else { throw ReviewFailure("paragraph playback did not span both one-second originals") }
                let playedTo = model.audio.playbackPosition
                try await self.naturalPress("archive.play.\(first.anchorID)", in: host)
                try await self.reviewUntil { model.audio.playingID == nil }
                checks += ["one editor/play/star per paragraph", "panel/archive identical newlines", "cross-owner emoji edit",
                           "archive private selection copy", "archive native undo/redo", "late ASR manual protection",
                           "whole-paragraph star", "real AVAudioPlayer silent clip transition past \(playedTo) seconds"]
                guard let secondEditor = try await self.archiveEditor(ids[2], in: host) as? ArchiveParagraphTextView,
                      host.window?.makeFirstResponder(secondEditor) == true else {
                    throw ReviewFailure("second archive paragraph could not acquire editing focus")
                }
                secondEditor.insertText("过", replacementRange: .init(location: 0, length: 1))
                let entire = PanelTimelineDocument(entries: try await model.store.timelinePage().entries).text
                guard entire.components(separatedBy: "\n").count == 3,
                      entire.components(separatedBy: "\n")[1] == "过了一会儿再说，这是同一个时间组里的新自然段。" else {
                    throw ReviewFailure("independent archive edit collapsed a paragraph on the live panel")
                }
                checks.append("independent second-paragraph edit keeps panel boundary")
                host.window?.makeFirstResponder(host)
            }, interaction: nil)
        await model.refresh()
        try await reviewValidatedWindow(InputPanelWindowView(model: model), size: .init(width: 340, height: 360),
            name: "natural-panel-after-edit", output: output, validation: { host in
                let scroll = try self.compactTranscript(in: host)
                let expected = PanelTimelineDocument(entries: try await model.store.timelinePage().entries).text
                try await self.reviewUntil { scroll.transcriptView.string == expected }
                guard scroll.rendered.spans.map({ $0.entry.id }) == ids else { throw ReviewFailure("archive edit lost live panel recording identities") }
            }, interaction: nil)
        let finals = try await model.store.timelinePage().entries
        let audio = try recordings.map { row -> [String: Any] in
            let url = model.store.audioDirectory.appendingPathComponent(row.id.uuidString + "/sample.wav")
            let data = try Data(contentsOf: url)
            return ["recording": row.id.uuidString, "sha256": SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined(), "bytes": data.count]
        }
        let receipt: [String: Any] = ["status": "PASS", "source": Bundle.main.object(forInfoDictionaryKey: "SaytileSourceRevision") as? String ?? "unpackaged",
            "syntheticOnly": true, "asrExecuted": false, "microphoneOpened": false, "privatePasteboard": true,
            "captureScope": "owned nonactivating native views rendered using AppKit cacheDisplay; not a full-desktop screenshot",
            "speechEndGapsSeconds": [3, 15, 60], "recordings": 4, "paragraphs": 3, "timeGroups": 2,
            "checks": checks, "archiveControls": archiveInventory, "audio": audio,
            "timeline": finals.map { ["id": $0.id.uuidString, "position": $0.position, "paragraphID": $0.paragraphID, "group": $0.group] as [String: Any] }]
        try JSONSerialization.data(withJSONObject: receipt, options: [.prettyPrinted, .sortedKeys])
            .write(to: output.appendingPathComponent("natural-paragraphs.json"))
        print("NATURAL_PARAGRAPHS_PASS 4 synthetic originals, 3 natural paragraphs, 2 time groups; native panel/archive editing and playback")
    }

    @MainActor private func naturalEditors(in host: NSView) -> [ArchiveParagraphTextView] {
        var stack = [host], result: [ArchiveParagraphTextView] = []
        while let view = stack.popLast() {
            if let editor = view as? ArchiveParagraphTextView { result.append(editor) }
            stack += view.subviews
        }
        return result
    }
    @MainActor private func naturalAccessibility(in host: NSView) -> [any NSAccessibilityProtocol] {
        var pending: [Any] = [host], seen = Set<ObjectIdentifier>(), result: [any NSAccessibilityProtocol] = []
        while let item = pending.popLast(), seen.count < 3000 {
            guard let node = item as? any NSAccessibilityProtocol else { continue }
            let identity = ObjectIdentifier(node as AnyObject)
            guard seen.insert(identity).inserted else { continue }
            result.append(node)
            pending += node.accessibilityChildren() ?? []
            if let view = item as? NSView {
                pending += view.subviews
                pending += NSAccessibility.unignoredChildren(from: view.subviews)
            }
        }
        return result
    }
    @MainActor private func naturalPress(_ identifier: String, in host: NSView) async throws {
        let matches = naturalAccessibility(in: host).filter { $0.accessibilityIdentifier() == identifier }
        guard matches.count == 1, matches[0].accessibilityPerformPress() else { throw ReviewFailure("owned native control refused press: \(identifier)") }
        try await Task.sleep(for: .milliseconds(50))
    }
}
