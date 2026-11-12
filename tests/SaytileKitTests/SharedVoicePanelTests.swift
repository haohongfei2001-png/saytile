import Foundation
import Testing
import SaytileVoiceUI

@Suite struct SharedVoicePanelTests {
    private struct Entry: GroupedVoiceTranscriptEntry {
        let id = UUID()
        let position: Int64
        let group: Int64
        let displayText: String
        var groupDay = "2026-11-12"
        let groupStart = Date(timeIntervalSince1970: 3_600 * 6)
        let groupUTCOffset = 3_600 * 8
    }

    @Test func twoHostsCanUseTheSameGroupedTextAndFrozenSelectionRanges() {
        let earlier = Entry(position: 31, group: 31, displayText: "第一段。")
        let active = Entry(position: 32, group: 32, displayText: "现在 🎙️ 继续。", groupDay: "2026-11-13")
        let pending = Entry(position: 33, group: 32, displayText: "")
        let entries = [earlier, active, pending]
        let live = PanelTimelineDocument(entries: entries, tailGroup: 32, idle: false, reading: false)
        let reading = PanelTimelineDocument(entries: entries, tailGroup: 32, idle: true, reading: true, older: true)
        #expect(live.text == "第一段。现在 🎙️ 继续。")
        #expect(live.displayed[pending.position] == "")
        #expect(live.activeStart == live.spans.last?.range.location)
        #expect(reading.text == live.text && reading.spans == live.spans && reading.markers.isEmpty)
        #expect(reading.idle && reading.older)
        for span in reading.spans {
            #expect((reading.text as NSString).substring(with: span.range) == span.entry.displayText)
        }
        #expect(PanelTimelineDocument(entries: entries, tailGroup: 32, idle: true, reading: true, newer: true).idle == false)
    }

    @Test func transcriptBoundariesAreLanguageAwareAndPreserveTypedWhitespace() {
        #expect(VoiceTranscriptFlow.join(["我", "", "说中文。", "Next", "word,", "and", "最后。"]) == "我说中文。Next word, and最后。")
        #expect(VoiceTranscriptFlow.join(["no ", "extra", "\n", "spaces", "."]) == "no extra\nspaces.")
    }

    @Test func bothFooterControlsFitNarrowGlassAtTheSameScale() {
        for width: CGFloat in [100, 128, 160, 178, 240, 344] {
            let metrics = VoicePanelMetrics(width: width)
            let footer = metrics.footerLeading + metrics.copyWidth + 8 * metrics.scale
                + metrics.voiceWidth + ReferencePanelStyle.footerTrailing * metrics.scale
            #expect(footer <= width)
            #expect(metrics.typeScale * ReferencePanelStyle.fontSize >= 14)
            #expect(metrics.typeScale <= 1)
        }
        #expect(VoicePanelMetrics(width: 344).scale == 1)
    }

    @Test func artworkScalesTheTextAndBothControlsAtDefaultAndReferenceSidebarWidths() {
        for outer: CGFloat in [240, 325, 374] {
            let card = VoiceRailMetrics(width: outer).cardFrame(in: CGRect(x: 0, y: 0, width: outer, height: 300))
            let metrics = VoicePanelMetrics(width: card.width, inRail: true)
            let normalized = 325 / outer
            #expect(abs(metrics.typeScale * normalized - 1) < 0.001)
            #expect(abs(metrics.copyWidth * normalized - 47) < 0.001)
            #expect(abs(metrics.voiceWidth * normalized - 86) < 0.001)
            #expect(abs(metrics.controlHeight * normalized - 36) < 0.001)
        }
    }

    @Test func lateAmplitudeCannotAnimatePausedOrWaitingGlyphs() {
        for state: VoicePanelState in [.paused, .standby, .starting, .recoveryNeeded] {
            #expect(VoicePanelCapture(state: state, level: 0.8, actionLabel: "", accessibilityValue: "").level == nil)
        }
        #expect(VoicePanelCapture(state: .recognizing, level: .nan, actionLabel: "", accessibilityValue: "").level == nil)
        #expect(VoicePanelCapture(state: .recognizing, level: 0.8, actionLabel: "", accessibilityValue: "").level == 0.8)
    }
}
