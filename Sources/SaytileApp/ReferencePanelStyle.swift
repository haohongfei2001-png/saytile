import SwiftUI
import SaytileVoiceUI

/// Standalone host of the first sidebar slot. The NSPanel is exactly the
/// visible rail footprint; the transcript card and its shadow sit inside it.
struct InputPanelWindowView: View {
    @ObservedObject var model: AppModel
    var onExpand: (@MainActor () -> Void)? = nil
    var body: some View {
        GeometryReader { geometry in
            let radius = VoiceRailMetrics(width: geometry.size.width).radius
            let compact = VoicePanelFootprint.isCompact(outerWidth: geometry.size.width)
            FramedVoiceSlot(showsBorder: model.panelBorderVisible) {
                InputPanelView(model: model, onExpand: compact ? onExpand : nil)
            }
                .background {
                    if model.panelBorderVisible && !compact {
                        VoiceRailGlass(width: geometry.size.width)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
        }
    }
}
