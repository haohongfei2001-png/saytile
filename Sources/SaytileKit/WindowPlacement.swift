import Foundation
import CoreGraphics

/// Window geometry uses visible frames, including displays with negative origins and menu bars.
public enum WindowPlacement {
    public static let nearpaneWidthFraction: CGFloat = 0.125
    public static let nearpaneVoiceHeightFraction: CGFloat = 0.225
    public static let panelDefaultSize = CGSize(width: 344, height: 234)
    public static let panelMinimumSize = CGSize(width: 178, height: 150)

    public static func panelLimits(visibleFrame: CGRect) -> (minimum: CGSize, maximum: CGSize) {
        let maximum = visibleFrame.size
        let width = min(maximum.width, max(20, maximum.width * nearpaneWidthFraction))
        let height = min(maximum.height, max(1, maximum.height * nearpaneVoiceHeightFraction))
        return (CGSize(width: min(panelMinimumSize.width, width),
                       height: min(panelMinimumSize.height, height)), maximum)
    }

    public static func panelSize(_ requested: CGSize, visibleFrame: CGRect) -> CGSize {
        let limits = panelLimits(visibleFrame: visibleFrame)
        return CGSize(width: min(max(requested.width, limits.minimum.width), limits.maximum.width),
                      height: min(max(requested.height, limits.minimum.height), limits.maximum.height))
    }

    /// Nearpane voice section by itself; not a full-height sidebar or fixed card.
    public static func initialPanel(visibleFrame: CGRect) -> CGRect {
        let size = panelSize(CGSize(width: visibleFrame.width * nearpaneWidthFraction,
                                    height: visibleFrame.height * nearpaneVoiceHeightFraction),
                             visibleFrame: visibleFrame)
        // The glass touches the visible desktop's upper-right edge.
        return CGRect(x: visibleFrame.maxX - size.width,
                      y: visibleFrame.maxY - size.height,
                      width: size.width, height: size.height)
    }

    public static func restoredPanel(_ frame: CGRect, visibleFrames: [CGRect]) -> CGRect {
        guard let destination = destination(for: frame, visibleFrames: visibleFrames) else { return frame }
        let size = panelSize(frame.size, visibleFrame: destination)
        let left = destination.minX
        let bottom = destination.minY
        return CGRect(x: min(max(frame.minX, left), destination.maxX - size.width),
                      y: min(max(frame.minY, bottom), destination.maxY - size.height),
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
    /// v2/v3 stored a transparent 32pt ring on every side. Recover the
    /// previously chosen visible rectangle, including its display identity.
    public func removingLegacyShadowMargin() -> Self? {
        guard frame.width > 64, frame.height > 64 else { return nil }
        return Self(frame: frame.insetBy(dx: 32, dy: 32), visibleFrame: visibleFrame, displayID: displayID)
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
        let fx = fraction(frame.minX - visibleFrame.minX, visibleFrame.width - frame.width)
        let fy = fraction(frame.minY - visibleFrame.minY, visibleFrame.height - frame.height)
        let projected = CGRect(x: dest.minX + fx * (dest.width - size.width),
                               y: dest.minY + fy * (dest.height - size.height),
                               width: size.width, height: size.height)
        return WindowPlacement.restoredPanel(projected, visibleFrames: [dest])
    }
}
