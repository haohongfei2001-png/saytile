import AppKit

/// One extraction of the user-selected lettering. Keep it out of the transcript itself.
@MainActor
enum SaytileBrand {
    static let mark: NSImage? = {
        let name = "SaytileBrandMark"
        // Installed app first; SwiftPM's own resource bundle for a development launch.
        let resources = Bundle.main.bundleURL.pathExtension == "app" ? Bundle.main : Bundle.module
        let url = resources.url(forResource: name, withExtension: "png")
        return url.flatMap(NSImage.init(contentsOf:))
    }()

    /// The status item is an application menu. Keep the approved lettering and its
    /// footprint constant as capture, faults, and panel visibility change.
    static let menuBarMark: NSImage? = {
        guard let mark else { return nil }
        let size = NSSize(width: 20, height: 20)
        let image = NSImage(size: size, flipped: false) { _ in
            NSGraphicsContext.current?.imageInterpolation = .high
            // The original is 152 × 172. Integral edges keep its small dot
            // and crossbar aligned at both menu-bar backing scales.
            mark.draw(in: NSRect(x: 2, y: 1, width: 16, height: 18),
                      from: .zero, operation: .sourceOver, fraction: 1)
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "Saytile"
        return image
    }()
}
