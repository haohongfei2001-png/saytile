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

    @Test func resizingBothHostsReflowsTextWithoutZoomingControlsOrGlyphs() {
        for rail in [false, true] {
            let baseline = VoicePanelMetrics(width: 180, inRail: rail)
            for width: CGFloat in [72, 100, 112, 160, 178, 240, 344, 620, 1440] {
                let metrics = VoicePanelMetrics(width: width, inRail: rail)
                #expect(abs(metrics.typeScale * ReferencePanelStyle.fontSize - 14.04) < 0.001)
                #expect(metrics.copyWidth == 30 && metrics.copyMarkSize == 13)
                #expect(metrics.voiceWidth == 54 && metrics.controlHeight == 26)
                #expect(metrics.scale == baseline.scale && metrics.footerLeading == baseline.footerLeading)
                #expect(metrics.showsCopy == (width >= 112))
                if metrics.showsCopy {
                    #expect(metrics.footerLeading + metrics.copyWidth + metrics.voiceWidth
                            + ReferencePanelStyle.footerTrailing * metrics.scale + 8 <= width)
                }
            }
        }
    }

    @Test func voiceOnlyFootprintKeepsRoomForBothEdgeDragsAndTheUnscaledButton() {
        let size = VoicePanelFootprint.minimumSize
        #expect(VoicePanelFootprint.isCompact(outerWidth: size.width))
        #expect(VoicePanelFootprint.isCompact(outerWidth: 80))
        #expect(!VoicePanelFootprint.isCompact(outerWidth: 81))
        #expect(size.width - VoicePanelFootprint.controlSize.width >= 14)
        #expect(size.height - VoicePanelFootprint.controlSize.height >= 14)
    }

    @Test func lateAmplitudeCannotAnimatePausedOrWaitingGlyphs() {
        for state: VoicePanelState in [.paused, .standby, .starting, .recoveryNeeded] {
            #expect(VoicePanelCapture(state: state, level: 0.8, actionLabel: "", accessibilityValue: "").level == nil)
        }
        #expect(VoicePanelCapture(state: .recognizing, level: .nan, actionLabel: "", accessibilityValue: "").level == nil)
        #expect(VoicePanelCapture(state: .recognizing, level: 0.8, actionLabel: "", accessibilityValue: "").level == 0.8)
    }
}
