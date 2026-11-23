import SwiftUI
import SaytileVoiceUI

// Select the stable property wrapper: CLT 27 does not ship SwiftUIMacros.
typealias ViewState<Value> = SwiftUI.State<Value>

private struct BrandAppearanceKey: EnvironmentKey {
    static let defaultValue: BrandAppearance = .purple
}
extension EnvironmentValues {
    var brandAppearance: BrandAppearance {
        get { self[BrandAppearanceKey.self] }
        set { self[BrandAppearanceKey.self] = newValue }
    }
}

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

/// Secondary windows follow system contrast and appearance. The panel has its own measured palette.
enum WorkspaceStyle {
    static let foreground = Color(nsColor: .labelColor)
    static let secondary = Color(nsColor: .secondaryLabelColor)
    static let background = Color(nsColor: .windowBackgroundColor)
    static let editor = Color(nsColor: .textBackgroundColor)
    static let accent = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(srgbRed: 0.76, green: 0.68, blue: 1, alpha: 1)
            : NSColor(srgbRed: 0.39, green: 0.26, blue: 0.67, alpha: 1)
    })
    static func accent(for brand: BrandAppearance) -> Color {
        guard brand == .black else { return accent }
        // A black brand is not a black window. In dark system windows the neutral
        // accent reverses for contrast; the white app-icon plate does not change.
        return Color(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                ? NSColor(srgbRed: 0.90, green: 0.90, blue: 0.90, alpha: 1)
                : NSColor(srgbRed: 0, green: 0, blue: 0, alpha: 1)
        })
    }
    static func selection(for brand: BrandAppearance) -> Color { accent(for: brand).opacity(0.12) }
    static let title = Font.system(size: 25, weight: .semibold)
}

struct WorkspaceBrand: View {
    @Environment(\.brandAppearance) private var brand
    @Environment(\.colorScheme) private var colorScheme
    var compact = false
    var body: some View {
        Group {
            if let mark = SaytileBrand.mark(for: brand, dark: colorScheme == .dark) {
                Image(nsImage: mark).resizable().interpolation(.high).aspectRatio(contentMode: .fit)
                    .frame(width: compact ? 22 : 32, height: compact ? 24 : 36)
            } else {
                Text("Saytile").font(.headline)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Saytile")
        .accessibilityIdentifier("workspace.brand")
    }
}

struct WorkspaceNavRow: View {
    @Environment(\.brandAppearance) private var brand
    let title: String
    let symbol: String
    let selected: Bool
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack(spacing: 9) {
                Image(systemName: symbol).frame(width: 19).foregroundStyle(selected ? WorkspaceStyle.accent(for: brand) : .secondary)
                Text(title).font(.system(size: 13, weight: selected ? .semibold : .regular))
                Spacer(minLength: 0)
            }.padding(.horizontal, 10).frame(maxWidth: .infinity).frame(height: 34)
                .background(selected ? WorkspaceStyle.selection(for: brand) : .clear, in: RoundedRectangle(cornerRadius: 7))
                .contentShape(Rectangle())
        }.buttonStyle(.plain).accessibilityLabel(title).accessibilityAddTraits(selected ? .isSelected : [])
    }
}

struct QuietButton: ButtonStyle {
    @Environment(\.brandAppearance) private var brand
    @Environment(\.isEnabled) private var isEnabled
    var prominent = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.system(size: 12, weight: .medium))
            .padding(.horizontal, 13).padding(.vertical, 8)
            .foregroundStyle(prominent ? .white : WorkspaceStyle.foreground)
            .background(prominent ? (brand == .black ? Color.black : Palette.accent) : WorkspaceStyle.selection(for: brand), in: RoundedRectangle(cornerRadius: 8))
            .contentShape(Rectangle())
            .opacity(!isEnabled ? 0.38 : configuration.isPressed ? 0.7 : 1)
    }
}

struct StatePill: View {
    @Environment(\.brandAppearance) private var brand
    let text: String
    var warning = false
    var body: some View {
        Label(text, systemImage: warning ? "exclamationmark.circle" : "circle.fill")
            .font(.system(size: 11)).foregroundStyle(warning ? Palette.amber : WorkspaceStyle.accent(for: brand))
            .padding(.horizontal, 9).padding(.vertical, 5)
            .background((warning ? Palette.amber : WorkspaceStyle.accent(for: brand)).opacity(0.08), in: Capsule())
    }
}
