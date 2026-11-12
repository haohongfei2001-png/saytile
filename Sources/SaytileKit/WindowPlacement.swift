import Foundation
import CoreGraphics

/// Window geometry uses visible frames, including displays with negative origins and menu bars.
public enum WindowPlacement {
    // The approved 344 × 234pt reference and 32pt shadow ring stay unchanged.
    // Runtime glass size follows Nearpane (12.5% × 22.5% of the safe desktop).
    public static let panelShadowInset: CGFloat = 32
    public static let nearpaneWidthFraction: CGFloat = 0.125
    public static let nearpaneVoiceHeightFraction: CGFloat = 0.225
    public static let panelContentDefaultSize = CGSize(width: 344, height: 234)
    public static let panelDefaultSize = CGSize(width: 408, height: 298)
    // 178pt of glass fits both reference controls and their optical margins.
    public static let panelMinimumSize = CGSize(width: 178 + 64, height: 150 + 64)

    /// Product dimensions exclude the invisible 32pt window shadow on each side.
    public static func panelGlassFrame(_ windowFrame: CGRect) -> CGRect {
        windowFrame.insetBy(dx: panelShadowInset, dy: panelShadowInset)
    }

    /// Constrain the visible glass rather than the transparent NSPanel margin.
    /// The margin may be clipped beyond a docked screen edge.
    public static func panelLimits(visibleFrame: CGRect) -> (minimum: CGSize, maximum: CGSize) {
        let maximum = CGSize(width: max(0, visibleFrame.width) + 2 * panelShadowInset,
                             height: max(0, visibleFrame.height) + 2 * panelShadowInset)
        return (CGSize(width: min(panelMinimumSize.width, maximum.width),
                       height: min(panelMinimumSize.height, maximum.height)), maximum)
    }

    public static func panelSize(_ requested: CGSize, visibleFrame: CGRect) -> CGSize {
        let limits = panelLimits(visibleFrame: visibleFrame)
        return CGSize(width: min(max(requested.width, limits.minimum.width), limits.maximum.width),
                      height: min(max(requested.height, limits.minimum.height), limits.maximum.height))
    }

    /// Nearpane voice section by itself; not a full-height sidebar or fixed card.
    public static func initialPanel(visibleFrame: CGRect) -> CGRect {
        let size = panelSize(CGSize(width: visibleFrame.width * nearpaneWidthFraction + 2 * panelShadowInset,
                                    height: visibleFrame.height * nearpaneVoiceHeightFraction + 2 * panelShadowInset),
                             visibleFrame: visibleFrame)
        // The glass touches the visible desktop's upper-right edge.
        return CGRect(x: visibleFrame.maxX - size.width + panelShadowInset,
                      y: visibleFrame.maxY - size.height + panelShadowInset,
                      width: size.width, height: size.height)
    }

    public static func restoredPanel(_ frame: CGRect, visibleFrames: [CGRect]) -> CGRect {
        guard let destination = destination(for: frame, visibleFrames: visibleFrames) else { return frame }
        let size = panelSize(frame.size, visibleFrame: destination)
        let left = destination.minX - panelShadowInset
        let bottom = destination.minY - panelShadowInset
        return CGRect(x: min(max(frame.minX, left), destination.maxX - size.width + panelShadowInset),
                      y: min(max(frame.minY, bottom), destination.maxY - size.height + panelShadowInset),
                      width: size.width, height: size.height)
    }

    private static func destination(for frame: CGRect, visibleFrames: [CGRect]) -> CGRect? {
        visibleFrames.max { lhs, rhs in
            let a = lhs.intersection(frame), b = rhs.intersection(frame)
            let leftArea = a.isNull ? 0 : a.width * a.height
            let rightArea = b.isNull ? 0 : b.width * b.height
            if leftArea != rightArea { return leftArea < rightArea }
            // After a monitor disconnects, use the nearest remaining screen
            // instead of depending on the system's screen-array order.
            let leftDistance = pow(lhs.midX - frame.midX, 2) + pow(lhs.midY - frame.midY, 2)
            let rightDistance = pow(rhs.midX - frame.midX, 2) + pow(rhs.midY - frame.midY, 2)
            return leftDistance > rightDistance
        }
    }

    public static func restored(_ frame: CGRect, visibleFrames: [CGRect]) -> CGRect {
        guard let destination = destination(for: frame, visibleFrames: visibleFrames) else { return frame }
        let size = CGSize(width: min(frame.width, destination.width), height: min(frame.height, destination.height))
        return CGRect(x: min(max(frame.minX, destination.minX), destination.maxX - size.width),
                      y: min(max(frame.minY, destination.minY), destination.maxY - size.height), width: size.width, height: size.height)
    }
}

/// The user's placement is stored against the usable area of the original display.
/// A temporary fallback never replaces it when the display is disconnected.
public struct SavedPanelPlacement: Codable, Equatable {
    public let displayID: String
    public let frame: CGRect
    public let visibleFrame: CGRect

    public init?(frame: CGRect, visibleFrame: CGRect, displayID: String) {
        guard !displayID.isEmpty, Self.valid(frame), Self.valid(visibleFrame) else { return nil }
        self.frame = frame; self.visibleFrame = visibleFrame; self.displayID = displayID
    }
    private static func valid(_ rect: CGRect) -> Bool {
        [rect.minX, rect.minY, rect.width, rect.height].allSatisfy(\.isFinite) && rect.width > 0 && rect.height > 0
    }
    public func restored(on screens: [(id: String, visible: CGRect)]) -> CGRect? {
        guard Self.valid(frame), Self.valid(visibleFrame), !screens.isEmpty else { return nil }
        guard let match = screens.first(where: { $0.id == displayID && Self.valid($0.visible) }) else {
            return WindowPlacement.restoredPanel(frame, visibleFrames: screens.map(\.visible))
        }
        let dest = match.visible
        if dest == visibleFrame { return WindowPlacement.restoredPanel(frame, visibleFrames: [dest]) }
        let size = WindowPlacement.panelSize(frame.size, visibleFrame: dest)
        func fraction(_ value: CGFloat, _ span: CGFloat) -> CGFloat { span > 0 ? min(1, max(0, value / span)) : 0.5 }
        // Preserve the visible glass's relative placement across screen changes.
        let inset = WindowPlacement.panelShadowInset
        let fx = fraction(frame.minX + inset - visibleFrame.minX,
                          visibleFrame.width - (frame.width - 2 * inset))
        let fy = fraction(frame.minY + inset - visibleFrame.minY,
                          visibleFrame.height - (frame.height - 2 * inset))
        let projected = CGRect(x: dest.minX - inset + fx * (dest.width - (size.width - 2 * inset)),
                               y: dest.minY - inset + fy * (dest.height - (size.height - 2 * inset)),
                               width: size.width, height: size.height)
        return WindowPlacement.restoredPanel(projected, visibleFrames: [dest])
    }
}
