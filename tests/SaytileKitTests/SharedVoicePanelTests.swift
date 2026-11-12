import Foundation
import Testing
import SaytileVoiceUI

@Suite struct SharedVoicePanelTests {
    private struct Entry: GroupedVoiceTranscriptEntry {
        let id = UUID()
        let position: Int64
        let group: Int64
        let displayText: String
        let groupDay = "2026-11-12"
        let groupStart = Date(timeIntervalSince1970: 3_600 * 6)
        let groupUTCOffset = 3_600 * 8
    }

    @Test func twoHostsCanUseTheSameGroupedTextAndFrozenSelectionRanges() {
        let earlier = Entry(position: 31, group: 31, displayText: "第一段。")
        let active = Entry(position: 32, group: 32, displayText: "现在 🎙️ 继续。")
        let pending = Entry(position: 33, group: 32, displayText: "")
        let entries = [earlier, active, pending]
        let live = PanelTimelineDocument(entries: entries, tailGroup: 32, idle: false, reading: false)
        let reading = PanelTimelineDocument(entries: entries, tailGroup: 32, idle: true, reading: true, older: true)
        #expect(live.text == "2026-11-12  14:00\n第一段。\n\n现在 🎙️ 继续。")
        #expect(live.displayed[pending.position] == "")
        #expect(live.activeStart == live.spans.last?.range.location)
        #expect(reading.markers.count == 2)
        #expect(reading.idle && reading.older)
        for span in reading.spans {
            #expect((reading.text as NSString).substring(with: span.range) == span.entry.displayText)
        }
        #expect(PanelTimelineDocument(entries: entries, tailGroup: 32, idle: true, reading: true, newer: true).idle == false)
    }

    @Test func bothFooterControlsFitNarrowGlassAtTheSameScale() {
        for width: CGFloat in [100, 128, 160, 178, 240, 344] {
            let metrics = VoicePanelMetrics(width: width)
            let footer = ReferencePanelStyle.footerLeading + ReferencePanelStyle.copyWidth + 8
                + ReferencePanelStyle.voiceWidth + ReferencePanelStyle.footerTrailing
            #expect(footer * metrics.scale <= width)
            #expect(metrics.typeScale * ReferencePanelStyle.fontSize >= 14)
            #expect(metrics.typeScale <= 1)
        }
        #expect(VoicePanelMetrics(width: 344).scale == 1)
    }

    @Test func lateAmplitudeCannotAnimatePausedOrWaitingGlyphs() {
        for state: VoicePanelState in [.paused, .standby, .starting, .recoveryNeeded] {
            #expect(VoicePanelCapture(state: state, level: 0.8, actionLabel: "", accessibilityValue: "").level == nil)
        }
        #expect(VoicePanelCapture(state: .recognizing, level: .nan, actionLabel: "", accessibilityValue: "").level == nil)
        #expect(VoicePanelCapture(state: .recognizing, level: 0.8, actionLabel: "", accessibilityValue: "").level == 0.8)
    }
}
