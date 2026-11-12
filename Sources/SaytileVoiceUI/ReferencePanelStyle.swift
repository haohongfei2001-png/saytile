import SwiftUI
import AppKit

/// Measured from the user's 1536 x 1024 reference supplied on 2026-11-07.
/// Reference main card: (130,250,688,468) physical pixels. One point = two
/// reference pixels. These tokens belong ONLY to the compact transcript panel.
public enum ReferencePanelStyle {
    public static let width: CGFloat = 344
    public static let height: CGFloat = 234
    public static let radius: CGFloat = 28
    public static let textInset: CGFloat = 22
    public static let fontSize: CGFloat = 19.5
    public static let lineHeight: CGFloat = 26
    public static let footerLeading: CGFloat = 20.5
    public static let footerTrailing: CGFloat = 14
    public static let footerBottom: CGFloat = 18
    public static let copyWidth: CGFloat = 42
    public static let controlHeight: CGFloat = 33.5
    public static let voiceWidth: CGFloat = 92.5
    public static let shadowInset: CGFloat = 32
    public static let violet = Color(red: 0.55, green: 0.23, blue: 0.98)
    public static let ink = NSColor(srgbRed: 0.035, green: 0.035, blue: 0.05, alpha: 1)
    public static let copyInk = Color(red: 0.43, green: 0.45, blue: 0.51)
    public static let glyph = LinearGradient(colors: [Color(red: 0.59, green: 0.29, blue: 1), violet], startPoint: .top, endPoint: .bottom)
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
    let radius: CGFloat
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    private var shape: RoundedRectangle { RoundedRectangle(cornerRadius: radius, style: .continuous) }
    public var body: some View {
        ZStack {
            // Behind-window AppKit material supplies the blur. A neutral,
            // translucent white wash supplies legibility without painting a
            // fixed blue/purple background over the user's desktop.
            ReferenceGlassBackdrop()
                .opacity(reduceTransparency ? 1 : 0.10)
            shape.fill(.white.opacity(reduceTransparency ? 1 : 0.42))
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
public struct ReferenceControlSurface: View {
    var copy = false
    var scale: CGFloat = 1
    public init(copy: Bool = false, scale: CGFloat = 1) { self.copy = copy; self.scale = scale }
    private var radius: CGFloat { (copy ? 13 : ReferencePanelStyle.controlHeight / 2) * scale }
    public var body: some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        // Both controls are neutral translucent white glass, not tinted
        // lavender buttons. Only the voice glyph and live caret carry violet.
        shape.fill(LinearGradient(colors: copy
            ? [.white.opacity(0.65), .white.opacity(0.36)]
            : [.white.opacity(0.58), .white.opacity(0.29)],
            startPoint: .top, endPoint: .bottom))
            .overlay {
                shape.strokeBorder(
                    LinearGradient(colors: [.white.opacity(0.95), .white.opacity(0.35)],
                                   startPoint: .top, endPoint: .bottom),
                    lineWidth: 0.7)
            }
            .shadow(color: .black.opacity(0.09), radius: 3.5, x: 0, y: 2.5)
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


/// Visible glass size, in AppKit points (never the shadow-expanded host frame).
public struct VoicePanelMetrics {
    public let scale: CGFloat
    public let typeScale: CGFloat
    public let radius: CGFloat
    public let footerLeading: CGFloat
    public let footerBottom: CGFloat
    public let footerTop: CGFloat
    public let topPadding: CGFloat
    public let voiceWidth: CGFloat
    public let copyWidth: CGFloat
    public let controlHeight: CGFloat
    public let copyMarkSize: CGFloat

    public init(width: CGFloat, inRail: Bool = false) {
        // The artwork measures 325px across the complete rail, with a
        // 295px card. Scale all of its elements together on either host.
        let referenceWidth: CGFloat = inRail ? 295 : ReferencePanelStyle.width
        let factor = min(inRail ? 1.4 : 1, max(0.4, width / referenceWidth))
        scale = factor
        typeScale = max(0.72, factor)
        radius = (inRail ? 22 : ReferencePanelStyle.radius) * factor
        footerLeading = (inRail ? 15 : ReferencePanelStyle.footerLeading) * factor
        footerBottom = (inRail ? 9 : ReferencePanelStyle.footerBottom) * factor
        footerTop = (inRail ? 2 : 6) * factor
        topPadding = (inRail ? 6 : 10.5) * factor
        voiceWidth = (inRail ? 86 : ReferencePanelStyle.voiceWidth) * factor
        copyWidth = (inRail ? 47 : ReferencePanelStyle.copyWidth) * factor
        controlHeight = (inRail ? 36 : ReferencePanelStyle.controlHeight) * factor
        copyMarkSize = (inRail ? 19 : 16) * factor
    }
}

/// The cast shadow extends beyond the glass, without changing its measured bounds.
struct VoicePanelShadow: View {
    let radius: CGFloat
    var body: some View {
            // Draw the cast shadow only outside the glass. A dark duplicate
            // beneath the translucent card neutralizes the actual desktop hue.
            Canvas { context, size in
                let bounds = CGRect(origin: .zero, size: size)
                let card = bounds.insetBy(dx: ReferencePanelStyle.shadowInset, dy: ReferencePanelStyle.shadowInset)
                let shape = RoundedRectangle(cornerRadius: radius, style: .continuous).path(in: card)
                var exterior = Path(bounds); exterior.addPath(shape)
                context.clip(to: exterior, style: FillStyle(eoFill: true))
                context.drawLayer { layer in
                    layer.addFilter(.shadow(color: .black.opacity(0.26), radius: 10, x: 0, y: 9))
                    layer.fill(shape, with: .color(.black))
                }
            }.allowsHitTesting(false).accessibilityHidden(true)
            .padding(-ReferencePanelStyle.shadowInset)
    }
}

/// Insets of the first card in the supplied 1672 × 941 desktop composition.
/// Both hosts measure the outer rail first and place the card inside it.
public struct VoiceRailMetrics {
    public let sideInset: CGFloat
    public let topInset: CGFloat
    public let bottomInset: CGFloat
    public let radius: CGFloat

    public init(width: CGFloat) {
        let scale = min(1.5, max(0, width) / 325)
        sideInset = 15 * scale
        topInset = 25 * scale
        bottomInset = 8 * scale
        radius = 28 * scale
    }

    public static func factoryHeight(width: CGFloat, visibleHeight: CGFloat) -> CGFloat {
        VoiceRailProportions.factoryHeight(width: width, visibleHeight: visibleHeight)
    }

    /// AppKit coordinates, with the origin at the lower left.
    public func cardFrame(in slot: CGRect) -> CGRect {
        let side = min(sideInset, slot.width / 4)
        let top = min(topInset, slot.height / 4)
        let bottom = min(bottomInset, slot.height / 8)
        return CGRect(x: slot.minX + side, y: slot.minY + bottom,
                      width: slot.width - 2 * side, height: slot.height - top - bottom)
    }
}

/// The same translucent outside edge extends down Nearpane's sidebar and
/// encloses just the first slot in Saytile.
public struct VoiceRailGlass: View {
    public let width: CGFloat
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    public init(width: CGFloat) { self.width = width }

    public var body: some View {
        let shape = RoundedRectangle(cornerRadius: VoiceRailMetrics(width: width).radius, style: .continuous)
        ZStack {
            ReferenceGlassBackdrop().opacity(reduceTransparency ? 1 : 0.12)
            shape.fill(.white.opacity(reduceTransparency ? 0.94 : 0.20))
            shape.fill(LinearGradient(colors: [.white.opacity(0.14), .white.opacity(0.025)],
                                      startPoint: .topLeading, endPoint: .bottomTrailing))
            shape.strokeBorder(.white.opacity(0.43), lineWidth: 0.75)
        }
        .clipShape(shape)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

extension EnvironmentValues {
    @Entry var insideVoiceRail = false
}

/// The slot consumes its host allocation, including the rail's margins.
public struct FramedVoiceSlot<Content: View>: View {
    private let content: Content
    public init(@ViewBuilder content: () -> Content) { self.content = content() }

    public var body: some View {
        GeometryReader { geometry in
            let slot = CGRect(origin: .zero, size: geometry.size)
            let card = VoiceRailMetrics(width: slot.width).cardFrame(in: slot)
            content
                .environment(\.insideVoiceRail, true)
                .frame(width: card.width, height: card.height)
                .position(x: card.midX, y: slot.height - card.midY)
        }
    }
}
