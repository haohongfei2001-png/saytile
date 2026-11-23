// Included by the presentation package and the Foundation-only placement code.
// Keep the formula available to either product without importing its host.
import CoreGraphics

enum VoiceRailProportions {
    static func factoryHeight(width: CGFloat, visibleHeight: CGFloat) -> CGFloat {
        min(max(0, visibleHeight) * 0.225, max(0, width) * 173 / 325)
    }
}

/// Geometry of the standalone voice-only footprint, in macOS logical points.
public enum VoicePanelFootprint {
    public static let minimumSize = CGSize(width: 28, height: 26)
    public static let compactWidthLimit: CGFloat = 80
    public static let controlSize = CGSize(width: 54, height: 26)

    // This threshold only determines when the Restore Reading Size menu is useful.
    public static func offersReadingSize(for size: CGSize) -> Bool {
        isCompact(outerWidth: size.width) || size.height <= 44
    }

    public static func isCompact(outerWidth: CGFloat) -> Bool {
        outerWidth <= compactWidthLimit
    }
}
