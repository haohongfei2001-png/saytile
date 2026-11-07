import SwiftUI

// Select the stable property wrapper: CLT 27 does not ship SwiftUIMacros.
typealias ViewState<Value> = SwiftUI.State<Value>

enum Palette {
    static let ink = Color(red: 0.17, green: 0.16, blue: 0.23)
    static let paper = Color(red: 0.977, green: 0.974, blue: 0.994)
    static let canvas = Color(red: 0.934, green: 0.925, blue: 0.978)
    // Lavender implementation of the written specification. Exact reference
    // sampling remains pending until the approved original asset is accessible.
    static let accent = Color(red: 0.43, green: 0.36, blue: 0.69)
    static let muted = Color(red: 0.43, green: 0.41, blue: 0.51)
    static let soft = Color(red: 0.93, green: 0.91, blue: 0.98)
    static let amber = Color(red: 0.58, green: 0.42, blue: 0.22)
}

struct VoiceMark: View {
    var active = false
    var size: CGFloat = 24
    var body: some View {
        HStack(spacing: size / 7) {
            ForEach(0..<3) { index in
                Capsule().fill(Palette.accent.opacity(active ? 1 : 0.55))
                    .frame(width: size / 6, height: size * [0.65, 1, 0.45][index])
            }
        }.frame(width: size, height: size).accessibilityHidden(true)
    }
}

struct QuietButton: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    var prominent = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.system(size: 12, weight: .medium))
            .padding(.horizontal, 13).padding(.vertical, 8)
            .foregroundStyle(prominent ? .white : Palette.accent)
            .background(prominent ? Palette.accent : Palette.soft, in: RoundedRectangle(cornerRadius: 8))
            .opacity(!isEnabled ? 0.38 : configuration.isPressed ? 0.7 : 1)
    }
}

struct StatePill: View {
    let text: String
    var warning = false
    var body: some View {
        Label(text, systemImage: warning ? "exclamationmark.circle" : "circle.fill")
            .font(.system(size: 11)).foregroundStyle(warning ? Palette.amber : Palette.accent)
            .padding(.horizontal, 9).padding(.vertical, 5)
            .background((warning ? Palette.amber : Palette.accent).opacity(0.08), in: Capsule())
    }
}
