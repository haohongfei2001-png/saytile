// Included by the presentation package and the Foundation-only placement code.
// Keep the formula available to either product without importing its host.
import CoreGraphics

enum VoiceRailProportions {
    static func factoryHeight(width: CGFloat, visibleHeight: CGFloat) -> CGFloat {
        min(max(0, visibleHeight) * 0.225, max(0, width) * 173 / 325)
    }
}
