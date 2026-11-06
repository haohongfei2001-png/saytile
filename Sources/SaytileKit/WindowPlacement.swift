import Foundation
import CoreGraphics

/// Window geometry uses visible frames, including displays with negative origins and menu bars.
public enum WindowPlacement {
    public static func panel(anchor: CGRect?, visibleFrame: CGRect, preferredSize: CGSize = CGSize(width: 400, height: 550)) -> CGRect {
        let inset = visibleFrame.insetBy(dx: 8, dy: 8)
        let size = CGSize(width: min(preferredSize.width, inset.width), height: min(preferredSize.height, inset.height))
        let x = anchor.map { $0.maxX - size.width } ?? inset.midX - size.width / 2
        let y = anchor.map { $0.minY - size.height - 8 } ?? inset.midY - size.height / 2
        return CGRect(x: min(max(x, inset.minX), inset.maxX - size.width),
                      y: min(max(y, inset.minY), inset.maxY - size.height), width: size.width, height: size.height)
    }

    public static func restored(_ frame: CGRect, visibleFrames: [CGRect]) -> CGRect {
        guard !visibleFrames.isEmpty else { return frame }
        let destination = visibleFrames.max { lhs, rhs in
            let a = lhs.intersection(frame), b = rhs.intersection(frame)
            return (a.isNull ? 0 : a.width * a.height) < (b.isNull ? 0 : b.width * b.height)
        }!
        let size = CGSize(width: min(frame.width, destination.width), height: min(frame.height, destination.height))
        return CGRect(x: min(max(frame.minX, destination.minX), destination.maxX - size.width),
                      y: min(max(frame.minY, destination.minY), destination.maxY - size.height), width: size.width, height: size.height)
    }
}
