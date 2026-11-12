import SwiftUI
import SaytileVoiceUI

/// This is the actual shipping window content, also used by the native reference
/// renderer. Transparent margins keep the card shadow inside the NSWindow instead
/// of clipping it off or substituting an unrelated system-window shadow.
struct InputPanelWindowView: View {
    @ObservedObject var model: AppModel
    var body: some View {
        InputPanelView(model: model)
            .padding(ReferencePanelStyle.shadowInset)
    }
}
