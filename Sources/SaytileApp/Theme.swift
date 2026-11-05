import SwiftUI

// Select the stable property wrapper: CLT 27 does not ship SwiftUIMacros.
typealias ViewState<Value> = SwiftUI.State<Value>

enum Palette {
    static let ink = Color(red: 0.14, green: 0.16, blue: 0.14)
    static let paper = Color(red: 0.985, green: 0.989, blue: 0.976)
    static let canvas = Color(red: 0.933, green: 0.937, blue: 0.91)
    static let green = Color(red: 0.26, green: 0.39, blue: 0.30)
    static let muted = Color(red: 0.41, green: 0.46, blue: 0.38)
    static let soft = Color(red: 0.92, green: 0.95, blue: 0.91)
    static let amber = Color(red: 0.58, green: 0.42, blue: 0.22)
}

struct VoiceMark: View {
    var active = false
    var size: CGFloat = 24
    var body: some View {
        HStack(spacing: size / 7) {
            ForEach(0..<3) { index in
                Capsule().fill(Palette.green.opacity(active ? 1 : 0.55))
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
            .foregroundStyle(prominent ? .white : Palette.green)
            .background(prominent ? Palette.green : Palette.soft, in: RoundedRectangle(cornerRadius: 8))
            .opacity(!isEnabled ? 0.38 : configuration.isPressed ? 0.7 : 1)
    }
}

struct StatePill: View {
    let text: String
    var warning = false
    var body: some View {
        Label(text, systemImage: warning ? "exclamationmark.circle" : "circle.fill")
            .font(.system(size: 11)).foregroundStyle(warning ? Palette.amber : Palette.green)
            .padding(.horizontal, 9).padding(.vertical, 5)
            .background((warning ? Palette.amber : Palette.green).opacity(0.08), in: Capsule())
    }
}
