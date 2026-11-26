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
        let starts: [TimeInterval] = [0, 4, 35, 96]
        var texts = ["我们🙂先把这个想法记下来，", "稍微停顿之后继续，文字仍然属于同一段。",
                     "隔了一会儿再说，这是同一个时间组里的新自然段。", "一分钟后开启另一段输入，回看时再显示新的时间。"]
        var recordings: [Recording] = []
        var tickets: [RecognitionTicket] = []
        let hasControlProbe = ProcessInfo.processInfo.environment["SAYTILE_UI_CONTROL_PROBE"] != nil
        var copyChecks: [String] = []
        for index in texts.indices {
            let row = try await model.store.createRecording(createdAt: base.addingTimeInterval(starts[index]))
            let ticket = try await model.store.beginRecognition(recordingID: row.id)
            _ = try await model.store.applyRecognition(ticket: ticket, text: texts[index], isFinal: index > 1)
            try await addSilentReviewAudio(model: model, recordingID: row.id, frames: 16_000)
            try await model.store.finishRecording(id: row.id, speechEndedAt: base.addingTimeInterval(starts[index] + 1))
            recordings.append(row); tickets.append(ticket)
            if index == 2 {
                // Stop before the fourth recording opens another time group. A
                // whole-group implementation must fail this same-group fixture.
                copyChecks = try await reviewSameGroupParagraphCopy(model: model, board: board,
                    latestTicket: ticket, latestText: texts[index], output: output, controls: hasControlProbe)
            }
        }
        await model.refresh()
        let initial = try await model.store.timelinePage().entries
        guard initial.count == 4, initial.allSatisfy({ $0.preferredOrigin != .userEdit }),
              initial[0].paragraphID == initial[1].paragraphID,
              initial[1].paragraphID != initial[2].paragraphID,
              initial[2].paragraphID != initial[3].paragraphID,
              initial[0].group == initial[2].group, initial[2].group != initial[3].group else {
            throw ReviewFailure("3/30/60-second speech-end gaps did not form three paragraphs and two time groups")
        }
        let ids = recordings.map(\.id)
        let sourceText = texts[0] + texts[1] + "\n" + texts[2] + "\n" + texts[3]
        guard PanelTimelineDocument(entries: initial).text == sourceText,
              model.archiveGroups.flatMap(\.paragraphs).count == 3, model.archiveGroups.count == 2 else {
            throw ReviewFailure("archive and live panel did not use the same paragraph identities")
        }
        var checks: [String] = ["ASR-origin seed", "three-second continuation", "30-second paragraph", "60-second time group"] + copyChecks
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
        // The timeline prefix keeps this owned nonactivating window drawable
        // offscreen. macOS may remove an alpha-zero window from AXWindows during
        // the playback wait, leaving the independent stop-button probe no tree.
        try await reviewValidatedWindow(SettingsView(model: model, initialPage: .archive), size: .init(width: 1000, height: 760),
            name: "timeline-natural-archive", output: output, validation: { host in
                try await self.reviewUntil { host.layoutSubtreeIfNeeded(); return self.naturalEditors(in: host).count == 3 }
                let editors = self.naturalEditors(in: host)
                guard Set(editors.compactMap { $0.accessibilityIdentifier() }) == Set(paragraphs.map { "archive.text.\($0.anchorID)" }) else {
                    throw ReviewFailure("archive retained per-recording editors instead of one per paragraph")
                }
                try self.captureReview(host, name: "natural-archive-reading", output: output)
                if hasControlProbe {
                    for paragraph in paragraphs {
                        let focused = try await self.archiveEditor(paragraph.anchorID, in: host)
                        guard host.window?.makeFirstResponder(focused) == true else {
                            throw ReviewFailure("archive focus did not reveal its actions")
                        }
                        try await Task.sleep(for: .milliseconds(100))
                        host.layoutSubtreeIfNeeded()
                        for prefix in ["archive.play.", "archive.favorite."] {
                            let identifier = prefix + paragraph.anchorID.uuidString
                            // The existing independent AX fixture checks the entire
                            // owned window for exactly one matching native control.
                            let result = try await self.performControl(identifier, in: host, arguments: ["inspect"])
                            guard result.contains("NATIVE_UI_INSPECT ") else {
                                throw ReviewFailure("native paragraph control inspection was incomplete")
                            }
                            archiveInventory.append(identifier)
                        }
                    }
                    checks.append("one native play/star control per paragraph via independent AX inspection")
                }
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
                try self.copyNaturalArchiveParagraph(editor, anchorID: first.anchorID)
                guard board.string(forType: .string) == expected else {
                    throw ReviewFailure("archive whole-paragraph copy lost the edited visible snapshot")
                }
                if hasControlProbe {
                    _ = try await self.performControl("archive.favorite.\(first.anchorID)", in: host)
                } else { await model.toggleParagraphFavorite(first) }
                try await self.reviewUntil { model.archiveGroups.flatMap(\.paragraphs).contains { $0.id == first.id && $0.pinned } }
                for id in ids.prefix(2) {
                    guard try await model.store.recording(id: id)?.isPinned == true else { throw ReviewFailure("paragraph star omitted an original recording") }
                }
                try self.captureReview(host, name: "natural-archive-editing", output: output)
                if hasControlProbe {
                    _ = try await self.performControl("archive.play.\(first.anchorID)", in: host)
                } else { model.playParagraph(first) }
                try await self.reviewUntil { model.audio.playingID == first.anchorID && model.audio.playbackPosition > 1.1 }
                guard abs(model.audio.playbackDuration - 2) < 0.02 else { throw ReviewFailure("paragraph playback did not span both one-second originals") }
                let playedTo = model.audio.playbackPosition
                if hasControlProbe {
                    _ = try await self.performControl("archive.play.\(first.anchorID)", in: host)
                } else { model.playParagraph(first) }
                try await self.reviewUntil { model.audio.playingID == nil }
                checks += ["one native editor per paragraph", "panel/archive identical newlines", "cross-owner emoji edit",
                           "archive private selection copy", "archive native undo/redo", "late ASR manual protection",
                           "archive context copy keeps the user-edited visible snapshot",
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
            "speechEndGapsSeconds": [3, 30, 60], "recordings": 4, "paragraphs": 3, "timeGroups": 2,
            "checks": checks, "archiveControls": archiveInventory,
            "nativeControlActions": ["status": hasControlProbe ? "PASS" : "NOT_RUN",
                                     "reason": hasControlProbe ? "independent owned-window AX inspection and AXPress, including panel.copy" : "SAYTILE_UI_CONTROL_PROBE not configured; panel copy/star/play model actions only"],
            "paragraphCopy": ["status": "PASS", "fixtureRecordings": 3, "fixtureTimeGroups": 1, "fixtureParagraphs": 2,
                              "panelButtonAX": hasControlProbe ? "PASS" : "NOT_RUN",
                              "archiveAction": "real native context-menu action dispatched by NSMenu; no global input",
                              "checks": copyChecks],
            "audio": audio,
            "timeline": finals.map { ["id": $0.id.uuidString, "position": $0.position, "paragraphID": $0.paragraphID, "group": $0.group] as [String: Any] }]
        try JSONSerialization.data(withJSONObject: receipt, options: [.prettyPrinted, .sortedKeys])
            .write(to: output.appendingPathComponent("natural-paragraphs.json"))
        print("NATURAL_PARAGRAPHS_PASS 4 synthetic originals, 3 natural paragraphs, 2 time groups; native panel/archive editing and playback")
    }

    /// Uses the production panel button and archive menu while both paragraphs
    /// still share one time group; all text and pasteboard contents are synthetic.
    @MainActor private func reviewSameGroupParagraphCopy(model: AppModel, board: NSPasteboard,
        latestTicket: RecognitionTicket, latestText: String, output: URL, controls: Bool) async throws -> [String] {
        await model.refresh()
        let entries = try await model.store.timelinePage().entries
        let paragraphs = model.archiveGroups.flatMap(\.paragraphs).sorted { $0.id < $1.id }
        guard entries.count == 3, Set(entries.map(\.group)).count == 1, paragraphs.count == 2,
              let historical = paragraphs.first, let latest = paragraphs.last,
              latest.page.entries.map(\.id) == [latestTicket.recordingID],
              latest.text == latestText, model.canCopyLatestParagraph else {
            throw ReviewFailure("same-group copy fixture did not contain two distinct natural paragraphs")
        }
        let original = PanelTimelineDocument(entries: entries).text
        var copiedParagraph = ""
        try await reviewValidatedWindow(InputPanelWindowView(model: model), size: .init(width: 340, height: 240),
            name: "timeline-natural-paragraph-copy", output: output, validation: { host in
                let scroll = try self.compactTranscript(in: host)
                let editor = scroll.transcriptView
                try await self.reviewUntil { editor.string == original }
                editor.commandPasteboard = board
                @MainActor func copyPanel() async throws {
                    if controls { _ = try await self.performControl("panel.copy", in: host) }
                    else { model.copyTimeline(paragraphID: scroll.selectedParagraphID,
                        rendered: scroll.rendered.spans.map(\.entry), displayed: scroll.rendered.displayed) }
                }
                editor.setSelectedRange(.init(location: 0, length: 0))
                let origin = scroll.contentView.bounds.origin
                let audioState = model.audio.state, notice = model.notice
                try await copyPanel()
                guard board.string(forType: .string) == latestText,
                      scroll.contentView.bounds.origin == origin, model.audio.state == audioState, model.notice == notice else {
                    throw ReviewFailure("no-selection panel copy included an older natural paragraph or disturbed the panel")
                }
                copiedParagraph = board.string(forType: .string) ?? ""
                let emoji = (editor.string as NSString).range(of: "🙂")
                guard emoji.location != NSNotFound, emoji.length == 2 else { throw ReviewFailure("UTF-16 selection fixture is missing") }
                editor.setSelectedRange(emoji)
                try await copyPanel()
                guard board.string(forType: .string) == historical.text, editor.selectedRange() == emoji else {
                    throw ReviewFailure("panel button did not copy the complete historical paragraph selected by its emoji")
                }
                editor.copy(nil)
                guard board.string(forType: .string) == "🙂", editor.selectedRange() == emoji else {
                    throw ReviewFailure("native system copy no longer preserves the exact emoji selection")
                }
                guard let latestSpan = scroll.rendered.spans.last,
                      latestSpan.range.location > emoji.location else {
                    throw ReviewFailure("cross-paragraph selection fixture is missing")
                }
                let acrossParagraphs = NSRange(location: emoji.location,
                    length: latestSpan.range.location + 2 - emoji.location)
                editor.setSelectedRange(acrossParagraphs)
                try await copyPanel()
                guard board.string(forType: .string) == historical.text,
                      editor.selectedRange() == acrossParagraphs else {
                    throw ReviewFailure("cross-paragraph product copy did not use the selection's starting paragraph")
                }
                editor.setSelectedRange(.init(location: 0, length: 0))
                try await copyPanel()
                let copied = board.changeCount
                let revised = latestText.replacingOccurrences(of: "新自然段", with: "下一自然段")
                guard revised != latestText,
                      try await model.store.applyRecognition(ticket: latestTicket, text: revised, isFinal: true) else {
                    throw ReviewFailure("late revision fixture was not applied")
                }
                await model.refresh()
                try await self.reviewUntil { editor.string.hasSuffix(revised) }
                guard board.changeCount == copied, board.string(forType: .string) == copiedParagraph,
                      scroll.rendered.spans.map({ $0.entry.id }) == entries.map(\.id) else {
                    throw ReviewFailure("late revision rewrote the copied paragraph or reordered its source rows")
                }
                _ = try await model.store.applyRecognition(ticket: latestTicket, text: latestText, isFinal: true)
                await model.refresh()
                try await self.reviewUntil { editor.string == original }
                guard board.changeCount == copied else { throw ReviewFailure("restoring a revision mutated the copied snapshot") }
                try self.captureReview(host, name: "same-group-panel-copy", output: output)
                // Selecting history intentionally pins the model's page. Restore
                // following through the normal owned-view action before the next
                // fixture appends a fourth recording; clearing a selection alone
                // must never move the user's reading position in the product.
                scroll.jumpToLatest()
                try await self.reviewUntil { scroll.isFollowingLatest }
                await model.refresh()
            }, interaction: nil)
        try await reviewValidatedWindow(SettingsView(model: model, initialPage: .archive), size: .init(width: 1000, height: 620),
            name: "timeline-natural-archive-copy", output: output, validation: { host in
                guard let editor = try await self.archiveEditor(latest.anchorID, in: host) as? ArchiveParagraphTextView else {
                    throw ReviewFailure("same-group archive paragraph is not a native editor")
                }
                try await self.reviewUntil { editor.string == latestText }
                try self.copyNaturalArchiveParagraph(editor, anchorID: latest.anchorID)
                guard board.string(forType: .string) == copiedParagraph else {
                    throw ReviewFailure("archive and panel copied different scopes for the same natural paragraph")
                }
                try self.captureReview(host, name: "same-group-archive-copy", output: output)
            }, interaction: nil)
        return ["same time group, two paragraphs: panel copies latest paragraph only",
                "panel button copies the complete historical paragraph identified by an emoji selection",
                "native system copy retains the exact emoji selection",
                "cross-paragraph product selection copies its starting paragraph only",
                "late ASR revision preserves copied paragraph snapshot",
                "panel/archive context copy agree on the same natural paragraph"]
    }

    @MainActor private func copyNaturalArchiveParagraph(_ editor: ArchiveParagraphTextView, anchorID: UUID) throws {
        let menu = NSMenu()
        editor.prepareMenu?(menu)
        let identifier = NSUserInterfaceItemIdentifier("archive.copyParagraph.\(anchorID)")
        let matches = menu.items.enumerated().filter { $0.element.identifier == identifier }
        guard matches.count == 1, let item = matches.first, item.element.isEnabled, item.element.action != nil else {
            throw ReviewFailure("archive whole-paragraph copy is not a unique actionable native menu item")
        }
        menu.performActionForItem(at: item.offset)
    }

    @MainActor private func naturalEditors(in host: NSView) -> [ArchiveParagraphTextView] {
        var stack = [host], result: [ArchiveParagraphTextView] = []
        while let view = stack.popLast() {
            if let editor = view as? ArchiveParagraphTextView { result.append(editor) }
            stack += view.subviews
        }
        return result
    }
}
