import AppKit
import SaytileVoiceUI

/// Raster derivatives of the approved artwork, never a re-typeset approximation.
/// White plates belong to app icons; transparent marks belong to the workspace.
@MainActor
enum SaytileBrand {
    private static let resources = Bundle.main.bundleURL.pathExtension == "app" ? Bundle.main : Bundle.module
    private static func image(_ name: String) -> NSImage? {
        resources.url(forResource: name, withExtension: "png").flatMap(NSImage.init(contentsOf:))
    }
    static let mark = image("SaytileBrandMark")
    private static let blackMark = image("SaytileBlackBrandMark")
    private static let blackMarkDark = image("SaytileBlackBrandMarkDark")
    private static let purpleIcon = image("SaytilePurplePlate")
    private static let blackIcon = image("SaytileBlackPlate")

    static func mark(for brand: BrandAppearance, dark: Bool = false) -> NSImage? {
        brand == .purple ? mark : (dark ? blackMarkDark : blackMark)
    }
    static func icon(for brand: BrandAppearance) -> NSImage? {
        brand == .purple ? purpleIcon : blackIcon
    }

    /// Keep template coverage, not the photograph's white background. The system
    /// supplies menu-bar contrast; neither recording nor failures recolor it.
    private static func template(from mark: NSImage?) -> NSImage? {
        guard let mark else { return nil }
        let image = NSImage(size: NSSize(width: 20, height: 20), flipped: false) { _ in
            NSGraphicsContext.current?.imageInterpolation = .high
            mark.draw(in: NSRect(x: 2, y: 1, width: 16, height: 18),
                      from: .zero, operation: .sourceOver, fraction: 1)
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "Saytile"
        return image
    }
    static let menuBarMark = template(from: mark)
    private static let blackMenuBarMark = template(from: blackMark)
    static func menuBarMark(for brand: BrandAppearance) -> NSImage? {
        brand == .purple ? menuBarMark : blackMenuBarMark
    }
}
