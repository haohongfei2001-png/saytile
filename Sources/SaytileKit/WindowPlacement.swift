import Foundation
import CoreGraphics

/// Window geometry uses visible frames, including displays with negative origins and menu bars.
public enum WindowPlacement {
    public static let panelDefaultSize = CGSize(width: 345, height: 234)
    public static let panelMinimumSize = CGSize(width: 320, height: 200)
    public static let panelMaximumSize = CGSize(width: 360, height: 480)

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
        let x = anchor.map { $0.maxX - size.width } ?? inset.midX - size.width / 2
        let y = anchor.map { $0.minY - size.height - 8 } ?? inset.midY - size.height / 2
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
