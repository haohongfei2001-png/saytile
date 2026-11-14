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
    var showsStroke = true
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.isOverFullscreen) private var isOverFullscreen
    private var shape: RoundedRectangle { RoundedRectangle(cornerRadius: radius, style: .continuous) }
    public var body: some View {
        ZStack {
            // Behind-window AppKit material supplies the blur. A neutral,
            // translucent white wash supplies legibility without painting a
            // fixed blue/purple background over the user's desktop.
            ReferenceGlassBackdrop()
                .opacity(reduceTransparency ? 1 : isOverFullscreen ? 0.85 : 0.10)
            shape.fill(.white.opacity(reduceTransparency ? 1 : isOverFullscreen ? 0.64 : 0.42))
                .overlay {
                    shape.fill(LinearGradient(stops: [
                        .init(color: .white.opacity(0.23), location: 0),
                        .init(color: .white.opacity(0.05), location: 0.38),
                        .init(color: .white.opacity(0), location: 1)
                    ], startPoint: .top, endPoint: .bottom))
                }
                .overlay {
                    if showsStroke {
                        shape.strokeBorder(
                            LinearGradient(colors: [.white.opacity(0.91), .white.opacity(0.24)],
                                           startPoint: .topLeading, endPoint: .bottomTrailing),
                            lineWidth: 0.65)
                    }
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
    public let showsCopy: Bool
    public let copyMarkSize: CGFloat

    public init(width: CGFloat, inRail: Bool = false) {
        // Desktop points, not a zoom factor: rewrap the text when the user resizes.
        scale = 0.68
        typeScale = 0.72
        radius = inRail ? VoiceRailMetrics.contentRadius(width: width) : ReferencePanelStyle.radius
        footerLeading = 10
        footerBottom = 6
        footerTop = 2
        topPadding = 4
        voiceWidth = VoicePanelFootprint.controlSize.width
        copyWidth = 30
        controlHeight = VoicePanelFootprint.controlSize.height
        copyMarkSize = 13
        showsCopy = width >= 112
    }
}

/// Shared control and editor frames in the slot's AppKit coordinates (origin at bottom left).
/// Every dimension follows the proposed size directly while the pointer is dragging.
public struct VoicePanelLayout: Sendable {
    public let cardFrame, captureFrame, copyFrame, transcriptFrame: CGRect
    public let transcriptOpacity, copyOpacity, controlChromeOpacity: CGFloat
    public let outerRadius, innerRadius, railOpacity: CGFloat
    public var canUseTranscript: Bool { transcriptOpacity >= 0.5 }
    public var canUseCopy: Bool { copyOpacity >= 0.5 }

    public init(size: CGSize, inRail: Bool = true) {
        let slot = CGRect(origin: .zero, size: CGSize(width: max(0, size.width), height: max(0, size.height)))
        let rail = VoiceRailMetrics(width: slot.width)
        let control = VoicePanelFootprint.controlSize
        func blend(_ value: CGFloat, from start: CGFloat, to end: CGFloat) -> CGFloat {
            let t = min(1, max(0, (value - start) / (end - start)))
            return t * t * (3 - 2 * t)
        }
        // As the side borders approach the button, its own bezel melts into the glass.
        // In a wide, shallow board the button remains distinct at the right.
        controlChromeOpacity = blend(slot.width, from: control.width, to: 96)
        railOpacity = min(controlChromeOpacity, blend(slot.height, from: control.height, to: 58))
        let inset = inRail ? min(rail.sideInset * railOpacity, min(slot.width, slot.height) / 4) : 0
        let card = slot.insetBy(dx: inset, dy: inset)
        cardFrame = card
        let metrics = VoicePanelMetrics(width: card.width, inRail: inRail)
        let minimumRadius: CGFloat = 12
        let regularRadius = inRail ? rail.radius : ReferencePanelStyle.radius
        outerRadius = min(min(slot.width, slot.height) / 2, minimumRadius + (regularRadius - minimumRadius) * railOpacity)
        innerRadius = max(0, outerRadius - inset)

        // Keep normal insets until the board itself would clip the control. Below its
        // nominal width, only the visible part is interactive; the glyph is never scaled.
        let trailing = min(ReferencePanelStyle.footerTrailing * metrics.scale, max(0, card.width - control.width))
        let bottom = min(metrics.footerBottom, max(0, card.height - control.height))
        let buttonWidth = min(card.width, control.width)
        let height = min(card.height, control.height)
        captureFrame = CGRect(x: card.maxX - trailing - buttonWidth, y: card.minY + bottom,
                              width: buttonWidth, height: height)
        copyFrame = CGRect(x: card.minX + metrics.footerLeading, y: captureFrame.minY,
                           width: metrics.copyWidth, height: height)
        // A fading copy control always has enough room to avoid the capture hit target.
        copyOpacity = blend(captureFrame.minX - copyFrame.maxX, from: 3, to: 13)

        let sidePadding = blend(card.width, from: 28, to: 96)
        let leading = (ReferencePanelStyle.textInset * metrics.scale - 2) * sidePadding
        let trailingText = 8 * metrics.scale * sidePadding
        let lower = min(card.maxY, captureFrame.maxY + metrics.footerTop)
        let text = CGRect(x: card.minX + leading, y: lower,
                          width: max(0, card.width - leading - trailingText),
                          height: max(0, card.maxY - metrics.topPadding - lower))
        transcriptFrame = text
        transcriptOpacity = min(blend(text.height, from: 17, to: 27), blend(text.width, from: 16, to: 24))
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

/// A single even glass rim. Both contours follow the same corner centres.
public struct VoiceRailMetrics {
    private static let referenceWidth: CGFloat = 325
    private static let referenceRim: CGFloat = 10
    private static let referenceRadius: CGFloat = 28
    static let referenceContentWidth = referenceWidth - 2 * referenceRim

    public let sideInset: CGFloat
    public var topInset: CGFloat { sideInset }
    public var bottomInset: CGFloat { sideInset }
    public let radius: CGFloat

    public init(width: CGFloat) {
        let scale = min(1.5, max(0, width) / Self.referenceWidth)
        sideInset = Self.referenceRim * scale
        radius = Self.referenceRadius * scale
    }

    static func contentRadius(width: CGFloat) -> CGFloat {
        (referenceRadius - referenceRim) * min(1.5, max(0, width) / referenceContentWidth)
    }

    public static func factoryHeight(width: CGFloat, visibleHeight: CGFloat) -> CGFloat {
        VoiceRailProportions.factoryHeight(width: width, visibleHeight: visibleHeight)
    }

    public func cardFrame(in slot: CGRect) -> CGRect {
        let rim = min(sideInset, min(slot.width, slot.height) / 4)
        return slot.insetBy(dx: rim, dy: rim)
    }
}

/// The same translucent outside edge extends down Nearpane's sidebar and
/// encloses just the first slot in Saytile.
public struct VoiceRailGlass: View {
    public let width: CGFloat
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.isOverFullscreen) private var isOverFullscreen
    public init(width: CGFloat) { self.width = width }

    public var body: some View {
        let shape = RoundedRectangle(cornerRadius: VoiceRailMetrics(width: width).radius, style: .continuous)
        ZStack {
            ReferenceGlassBackdrop().opacity(reduceTransparency ? 1 : isOverFullscreen ? 0.80 : 0.12)
            shape.fill(.white.opacity(reduceTransparency ? 0.94 : isOverFullscreen ? 0.50 : 0.27))
            shape.strokeBorder(LinearGradient(colors: [.white.opacity(0.64), .white.opacity(0.32)],
                                              startPoint: .top, endPoint: .bottom), lineWidth: 0.7)
        }
        .clipShape(shape)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

private struct SingleGlassSurfaceKey: EnvironmentKey {
    static let defaultValue = false
}

private struct VoiceSlotLayoutKey: EnvironmentKey {
    static let defaultValue: VoicePanelLayout? = nil
}

private struct InsideVoiceRailKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var voiceSlotLayout: VoicePanelLayout? {
        get { self[VoiceSlotLayoutKey.self] }
        set { self[VoiceSlotLayoutKey.self] = newValue }
    }

    var singleGlassSurface: Bool {
        get { self[SingleGlassSurfaceKey.self] }
        set { self[SingleGlassSurfaceKey.self] = newValue }
    }

    var insideVoiceRail: Bool {
        get { self[InsideVoiceRailKey.self] }
        set { self[InsideVoiceRailKey.self] = newValue }
    }
}

/// The slot consumes its host allocation, including the rail's margins.
public struct FramedVoiceSlot<Content: View>: View {
    private let content: Content
    private let showsBorder: Bool
    public init(showsBorder: Bool = true, @ViewBuilder content: () -> Content) {
        self.showsBorder = showsBorder
        self.content = content()
    }

    public var body: some View {
        GeometryReader { geometry in
            let slot = CGRect(origin: .zero, size: geometry.size)
            let layout = VoicePanelLayout(size: slot.size)
            let card = layout.cardFrame
            content
                .environment(\.insideVoiceRail, true)
                .environment(\.voiceSlotLayout, layout)
                .environment(\.singleGlassSurface, !showsBorder)
                .frame(width: card.width, height: card.height)
                .position(x: card.midX, y: slot.height - card.midY)
                .background {
                    if !showsBorder {
                        ReferencePanelSurface(radius: layout.outerRadius, showsStroke: false)
                    }
                }
        }
    }
}
