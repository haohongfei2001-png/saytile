import SwiftUI
import SaytileVoiceUI

/// Standalone host of the first sidebar slot. The NSPanel is exactly the
/// visible rail footprint; the transcript card and its shadow sit inside it.
struct InputPanelWindowView: View {
    @ObservedObject var model: AppModel
    var body: some View {
        GeometryReader { geometry in
            let radius = VoiceRailMetrics(width: geometry.size.width).radius
            FramedVoiceSlot(showsBorder: model.panelBorderVisible) { InputPanelView(model: model) }
                .background {
                    if model.panelBorderVisible { VoiceRailGlass(width: geometry.size.width) }
                }
                .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
        }
    }
}
