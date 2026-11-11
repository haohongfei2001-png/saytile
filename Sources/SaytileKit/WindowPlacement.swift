import Foundation
import CoreGraphics

/// Window geometry uses visible frames, including displays with negative origins and menu bars.
public enum WindowPlacement {
    // Card body is 344 x 234 points, measured at 1/2 the supplied 688 x 468px.
    // The transparent 32pt perimeter contains the production shadow.
    public static let panelShadowInset: CGFloat = 32
    public static let panelContentDefaultSize = CGSize(width: 344, height: 234)
    public static let panelDefaultSize = CGSize(width: 408, height: 298)
    public static let panelMinimumSize = CGSize(width: 384, height: 264)
    public static let panelMaximumSize = CGSize(width: 424, height: 544)

    /// Logical points, never physical pixels. Very small visible areas take
    /// precedence over the normal minimum, so no edge or resize handle is lost.
    public static func panelLimits(visibleFrame: CGRect) -> (minimum: CGSize, maximum: CGSize) {
        let available = panelVisibleArea(visibleFrame).size
        let maximum = CGSize(width: min(panelMaximumSize.width, available.width),
                             height: min(panelMaximumSize.height, available.height))
        return (CGSize(width: min(panelMinimumSize.width, maximum.width),
                       height: min(panelMinimumSize.height, maximum.height)), maximum)
    }

    public static func panelSize(_ requested: CGSize, visibleFrame: CGRect) -> CGSize {
        let limits = panelLimits(visibleFrame: visibleFrame)
        return CGSize(width: min(max(requested.width, limits.minimum.width), limits.maximum.width),
                      height: min(max(requested.height, limits.minimum.height), limits.maximum.height))
    }

    public static func panel(anchor: CGRect?, visibleFrame: CGRect, preferredSize: CGSize = panelDefaultSize) -> CGRect {
        let inset = panelVisibleArea(visibleFrame)
        let size = panelSize(preferredSize, visibleFrame: visibleFrame)
        // A hidden/unlaid-out NSStatusItem can briefly advertise an origin
        // near (0,0). It is not a menu-bar anchor; clamping it strands a first
        // window in the bottom corner. Never change a saved user placement.
        let menuAnchor = anchor.flatMap { rect -> CGRect? in
            guard !rect.isEmpty, rect.midX >= visibleFrame.minX, rect.midX <= visibleFrame.maxX,
                  abs(rect.maxY - visibleFrame.maxY) <= max(56, rect.height + 24) else { return nil }
            return rect
        }
        let x = menuAnchor.map { $0.maxX - size.width } ?? inset.midX - size.width / 2
        let y = menuAnchor.map { $0.minY - size.height - 8 } ?? inset.midY - size.height / 2
        return CGRect(x: min(max(x, inset.minX), inset.maxX - size.width),
                      y: min(max(y, inset.minY), inset.maxY - size.height), width: size.width, height: size.height)
    }

    public static func restoredPanel(_ frame: CGRect, visibleFrames: [CGRect]) -> CGRect {
        guard let destination = destination(for: frame, visibleFrames: visibleFrames) else { return frame }
        let area = panelVisibleArea(destination)
        let size = panelSize(frame.size, visibleFrame: destination)
        return CGRect(x: min(max(frame.minX, area.minX), area.maxX - size.width),
                      y: min(max(frame.minY, area.minY), area.maxY - size.height), width: size.width, height: size.height)
    }

    private static func panelVisibleArea(_ frame: CGRect) -> CGRect {
        // Insets must not create negative dimensions on constrained remote or
        // transient screen geometries.
        frame.insetBy(dx: min(8, max(0, (frame.width - 1) / 2)), dy: min(8, max(0, (frame.height - 1) / 2)))
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
        let fx = fraction(frame.minX - visibleFrame.minX, visibleFrame.width - frame.width)
        let fy = fraction(frame.minY - visibleFrame.minY, visibleFrame.height - frame.height)
        let projected = CGRect(x: dest.minX + fx * (dest.width-size.width), y: dest.minY + fy * (dest.height-size.height), width: size.width, height: size.height)
        return WindowPlacement.restoredPanel(projected, visibleFrames: [dest])
    }
}
