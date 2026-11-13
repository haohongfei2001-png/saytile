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
    static let selection = accent.opacity(0.12)
    static let title = Font.system(size: 25, weight: .semibold)
}

struct WorkspaceBrand: View {
    var showsName = true
    var body: some View {
        HStack(spacing: 9) {
            if let mark = SaytileBrand.mark {
                Image(nsImage: mark).resizable().interpolation(.high).aspectRatio(contentMode: .fit)
                    .frame(width: 28, height: 32).accessibilityHidden(true)
            }
            if showsName || SaytileBrand.mark == nil {
                Text("Saytile").font(.system(size: 18, weight: .semibold))
            }
        }
        .foregroundStyle(WorkspaceStyle.foreground)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Saytile")
    }
}

struct WorkspaceNavRow: View {
    let title: String
    let symbol: String
    let selected: Bool
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack(spacing: 9) {
                Image(systemName: symbol).frame(width: 19).foregroundStyle(selected ? WorkspaceStyle.accent : .secondary)
                Text(title).font(.system(size: 13, weight: selected ? .semibold : .regular))
                Spacer(minLength: 0)
            }.padding(.horizontal, 10).frame(height: 34)
                .background(selected ? WorkspaceStyle.selection : .clear, in: RoundedRectangle(cornerRadius: 7))
                .contentShape(Rectangle())
        }.buttonStyle(.plain).accessibilityLabel(title).accessibilityAddTraits(selected ? .isSelected : [])
    }
}

struct QuietButton: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    var prominent = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.system(size: 12, weight: .medium))
            .padding(.horizontal, 13).padding(.vertical, 8)
            .foregroundStyle(prominent ? .white : WorkspaceStyle.foreground)
            .background(prominent ? Palette.accent : WorkspaceStyle.selection, in: RoundedRectangle(cornerRadius: 8))
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
