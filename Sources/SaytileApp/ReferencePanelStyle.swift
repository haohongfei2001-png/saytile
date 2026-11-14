import SwiftUI
import SaytileVoiceUI

/// Standalone host of the first sidebar slot. The NSPanel is exactly the
/// visible rail footprint; the transcript card and its shadow sit inside it.
struct InputPanelWindowView: View {
    @ObservedObject var model: AppModel
    var onExpand: (@MainActor () -> Void)? = nil
    var body: some View {
        GeometryReader { geometry in
            let layout = VoicePanelLayout(size: geometry.size)
            FramedVoiceSlot(showsBorder: model.panelBorderVisible) {
                InputPanelView(model: model, onExpand: VoicePanelFootprint.offersReadingSize(for: geometry.size) ? onExpand : nil)
            }
                .background {
                    if model.panelBorderVisible {
                        VoiceRailGlass(width: geometry.size.width).opacity(layout.railOpacity)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: layout.outerRadius, style: .continuous))
        }
        .environment(\.isOverFullscreen, model.panelOverFullscreen)
    }
}
