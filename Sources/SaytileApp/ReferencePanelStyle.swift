import SwiftUI
import AppKit

/// Measured from the user's 1536 x 1024 reference supplied on 2026-11-07.
/// Reference main card: (130,250,688,468) physical pixels. One point = two
/// reference pixels. These tokens belong ONLY to the compact transcript panel.
enum ReferencePanelStyle {
    static let width: CGFloat = 344
    static let height: CGFloat = 234
    static let radius: CGFloat = 28
    static let textInset: CGFloat = 22
    static let fontSize: CGFloat = 19.5
    static let lineHeight: CGFloat = 26
    static let footerLeading: CGFloat = 20.5
    static let footerTrailing: CGFloat = 14
    static let footerBottom: CGFloat = 18
    static let copyWidth: CGFloat = 42
    static let controlHeight: CGFloat = 33.5
    static let voiceWidth: CGFloat = 92.5
    static let shadowInset: CGFloat = 32
    static let violet = Color(red: 0.55, green: 0.23, blue: 0.98)
    static let ink = NSColor(srgbRed: 0.035, green: 0.035, blue: 0.05, alpha: 1)
    static let copyInk = Color(red: 0.43, green: 0.45, blue: 0.51)
    static let glyph = LinearGradient(colors: [Color(red: 0.59, green: 0.29, blue: 1), violet], startPoint: .top, endPoint: .bottom)
}

/// A surface, not a reference-image backdrop: selectable native text and actual
/// controls are rendered above it. The source image is never used at runtime.
private struct ReferenceGlassBackdrop: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        // Aqua popover blur is a neutral light glass material. Wallpaper hues
        // may show through; the panel itself does not own a violet/blue tint.
        view.material = .popover
        view.blendingMode = .behindWindow
        view.state = .active
        view.appearance = NSAppearance(named: .aqua)
        return view
    }
    func updateNSView(_ view: NSVisualEffectView, context: Context) {}
}

struct ReferencePanelSurface: View {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    private var shape: RoundedRectangle { RoundedRectangle(cornerRadius: ReferencePanelStyle.radius, style: .continuous) }
    var body: some View {
        ZStack {
            // Behind-window AppKit material supplies the blur. A neutral,
            // translucent white wash supplies legibility without painting a
            // fixed blue/purple background over the user's desktop.
            ReferenceGlassBackdrop()
            shape.fill(.white.opacity(reduceTransparency ? 1 : 0.46))
                .overlay {
                    shape.fill(LinearGradient(stops: [
                        .init(color: .white.opacity(0.23), location: 0),
                        .init(color: .white.opacity(0.05), location: 0.38),
                        .init(color: .white.opacity(0), location: 1)
                    ], startPoint: .top, endPoint: .bottom))
                }
                .overlay {
                    shape.strokeBorder(
                        LinearGradient(colors: [.white.opacity(0.91), .white.opacity(0.24)],
                                       startPoint: .topLeading, endPoint: .bottomTrailing),
                        lineWidth: 0.65)
                }
        }
        .clipShape(shape)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// The raised small buttons use a clear highlight, inner tint and two restrained
/// shadows. No macOS default bezel, resize grip or extra state label is added.
struct ReferenceControlSurface: View {
    var copy = false
    private var radius: CGFloat { copy ? 13 : ReferencePanelStyle.controlHeight / 2 }
    var body: some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        // Both controls are neutral translucent white glass, not tinted
        // lavender buttons. Only the voice glyph and live caret carry violet.
        shape.fill(LinearGradient(colors: copy
            ? [.white.opacity(0.82), .white.opacity(0.57)]
            : [.white.opacity(0.79), .white.opacity(0.53)],
            startPoint: .top, endPoint: .bottom))
            .overlay {
                shape.strokeBorder(
                    LinearGradient(colors: [.white.opacity(0.95), .white.opacity(0.35)],
                                   startPoint: .top, endPoint: .bottom),
                    lineWidth: 0.7)
            }
            .shadow(color: .black.opacity(0.15), radius: 4.5, x: 0, y: -3)
            .accessibilityHidden(true)
    }
}

struct ReferenceCopyMark: Shape {
    func path(in rect: CGRect) -> Path {
        let scale = min(rect.width, rect.height) / 16
        func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: rect.minX + x * scale, y: rect.minY + y * scale) }
        var p = Path()
        // Back square stops where the foreground square overlaps it.
        p.move(to: point(5.5, 10.5)); p.addLine(to: point(2.5, 10.5))
        p.addQuadCurve(to: point(1, 9), control: point(1, 10.5))
        p.addLine(to: point(1, 2.5)); p.addQuadCurve(to: point(2.5, 1), control: point(1, 1))
        p.addLine(to: point(9, 1)); p.addQuadCurve(to: point(10.5, 2.5), control: point(10.5, 1))
        p.addLine(to: point(10.5, 5.5))
        p.addRoundedRect(in: CGRect(x: rect.minX + 5.5 * scale, y: rect.minY + 5.5 * scale, width: 9.5 * scale, height: 9.5 * scale), cornerSize: CGSize(width: 1.7 * scale, height: 1.7 * scale))
        return p
    }
}

/// This is the actual shipping window content, also used by the native reference
/// renderer. Transparent margins keep the card shadow inside the NSWindow instead
/// of clipping it off or substituting an unrelated system-window shadow.
struct InputPanelWindowView: View {
    @ObservedObject var model: AppModel
    var body: some View {
        InputPanelView(model: model)
            .shadow(color: .black.opacity(0.17), radius: 12, x: 0, y: -11)
            .shadow(color: .black.opacity(0.06), radius: 2.5, x: 0, y: -2)
            .padding(ReferencePanelStyle.shadowInset)
    }
}
