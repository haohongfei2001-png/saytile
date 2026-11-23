import AppKit

// Compile this probe together with Sources/SaytileApp/SaytileBrand.swift.
// The first argument is the .app supplying the actual shipping mark.
extension Bundle {
    static var module: Bundle {
        Bundle(url: URL(fileURLWithPath: CommandLine.arguments[1]))!
    }
}

@main @MainActor
struct StatusMarkProbe {
    static func main() throws {
        _ = NSApplication.shared
        let mark = SaytileBrand.menuBarMark!
        let size = NSSize(width: 20, height: 20)
        precondition(mark.size == size && mark.isTemplate)

        let sheet = bitmap(width: 352, height: 112)
        let sheetContext = NSGraphicsContext(bitmapImageRep: sheet)!
        for (column, appearance) in [NSAppearance.Name.aqua, .darkAqua].enumerated() {
            let style = NSAppearance(named: appearance)!
            let dark = column == 1
            for scale in [1, 2] {
                let view = NSImageView(frame: NSRect(origin: .zero, size: size))
                view.image = mark
                view.imageScaling = .scaleNone
                view.appearance = style
                view.contentTintColor = .labelColor
                let pixels = 20 * scale
                let rep = bitmap(width: pixels, height: pixels)
                rep.size = size
                let context = NSGraphicsContext(bitmapImageRep: rep)!
                style.performAsCurrentDrawingAppearance {
                    view.displayIgnoringOpacity(view.bounds, in: context)
                }
                var ink = 0
                var bounds = CGRect.null
                for y in 0..<pixels {
                    for x in 0..<pixels {
                        let color = rep.colorAt(x: x, y: y)!
                        if color.alphaComponent > 0.6 {
                            precondition(dark ? color.redComponent > 0.8 : color.redComponent < 0.2)
                            ink += 1
                            bounds = bounds.union(CGRect(x: x, y: y, width: 1, height: 1))
                        }
                    }
                }
                precondition(ink > scale * scale * 45)
                precondition(bounds.width >= 13 * CGFloat(scale) && bounds.height >= 15 * CGFloat(scale))
                precondition(bounds.minX > 0 && bounds.maxX < CGFloat(pixels))
                precondition(bounds.minY > 0 && bounds.maxY < CGFloat(pixels))
                print("\(appearance.rawValue) @\(scale)x ink=\(ink) bounds=\(bounds)")
                NSGraphicsContext.saveGraphicsState()
                NSGraphicsContext.current = sheetContext
                let x = CGFloat(column * 176)
                let y = CGFloat((2 - scale) * 56)
                NSColor(white: dark ? 0.14 : 0.95, alpha: 1).setFill()
                NSRect(x: x, y: y, width: 176, height: 56).fill()
                let raster = NSImage(size: size)
                raster.addRepresentation(rep)
                sheetContext.imageInterpolation = .none
                raster.draw(in: NSRect(x: x + 57, y: y + 18, width: 20, height: 20))
                raster.draw(in: NSRect(x: x + 100, y: y + 3, width: 50, height: 50))
                ("\(scale)×" as NSString).draw(at: NSPoint(x: x + 20, y: y + 19), withAttributes: [
                    .font: NSFont.monospacedDigitSystemFont(ofSize: 13, weight: .regular),
                    .foregroundColor: NSColor(white: dark ? 0.8 : 0.3, alpha: 1),
                ])
                NSGraphicsContext.restoreGraphicsState()
            }
        }
        let destination = URL(fileURLWithPath: CommandLine.arguments[2])
        try sheet.representation(using: .png, properties: [:])!.write(to: destination)
    }

    private static func bitmap(width: Int, height: Int) -> NSBitmapImageRep {
        NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height,
                         bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                         isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    }
}
