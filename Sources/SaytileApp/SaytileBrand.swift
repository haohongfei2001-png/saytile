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

    static let active = menuImage(opacity: 1, warning: false)
    static let paused = menuImage(opacity: 0.72, warning: false)
    static let problem = menuImage(opacity: 1, warning: true)

    private static func menuImage(opacity: CGFloat, warning: Bool) -> NSImage? {
        guard let mark else { return nil }
        let alert = warning ? NSImage(systemSymbolName: "exclamationmark", accessibilityDescription: nil) : nil
        let size = NSSize(width: warning ? 25 : 18, height: 18)
        let image = NSImage(size: size, flipped: false) { _ in
            NSGraphicsContext.current?.imageInterpolation = .high
            let width = 18 * mark.size.width / mark.size.height
            mark.draw(in: NSRect(x: (18-width)/2, y: 0, width: width, height: 18), from: .zero,
                      operation: .sourceOver, fraction: opacity)
            alert?.draw(in: NSRect(x: 19, y: 3, width: 5, height: 12), from: .zero,
                        operation: .sourceOver, fraction: 1)
            return true
        }
        image.isTemplate = true // AppKit supplies menu-bar contrast for either appearance.
        return image
    }
}
