import SwiftUI

/// Optional shortcut to the single transcript panel, never a second recorder.
struct VoiceEntryView: View {
    @ObservedObject var model: AppModel
    let open: () -> Void

    var body: some View {
        Button(action: open) {
            Image(systemName: model.captureProblem ? "exclamationmark" : "waveform")
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(model.captureProblem ? Palette.amber : Palette.accent)
                .frame(width: 42, height: 42)
                .background(Palette.paper.opacity(0.82), in: Circle())
                .background(.ultraThinMaterial, in: Circle())
                .overlay(Circle().stroke(.white.opacity(0.75), lineWidth: 0.75))
                .contentShape(Circle())
        }.buttonStyle(.plain)
            .help("打开输入板")
            .accessibilityLabel("打开输入板")
            .accessibilityValue(model.panelCaptureLabel)
            .accessibilityIdentifier("voiceEntry.open")
    }
}
