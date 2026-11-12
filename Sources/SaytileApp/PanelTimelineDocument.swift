import AppKit
import SaytileKit
import SaytileVoiceUI

extension TimelineEntry: GroupedVoiceTranscriptEntry {
    public var displayText: String { recording.text }
}

typealias PanelTimelineDocument = SaytileVoiceUI.PanelTimelineDocument<TimelineEntry>
typealias PanelTranscriptAccess = SaytileVoiceUI.PanelTranscriptAccess<TimelineEntry>
typealias CompactTranscriptScrollView = SaytileVoiceUI.CompactTranscriptScrollView<TimelineEntry>

extension SaytileVoiceUI.PanelTimelineDocument where Entry == TimelineEntry {
    init(page: TimelinePage, tail: TimelineEntry?, idle: Bool, reading: Bool) {
        self.init(entries: page.entries, tailGroup: tail?.group, idle: idle, reading: reading,
                  older: page.hasOlder, newer: page.hasNewer)
    }
}
