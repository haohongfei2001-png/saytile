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
    public static let minimumSize = CGSize(width: 72, height: 44)
    public static let compactWidthLimit: CGFloat = 80
    static let compactCornerRadius: CGFloat = 12
    public static let controlSize = CGSize(width: 54, height: 26)

    public static func isCompact(outerWidth: CGFloat) -> Bool {
        outerWidth <= compactWidthLimit
    }
}
