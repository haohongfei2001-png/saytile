import AppKit
import SwiftUI

// Used only by the isolated --ui-review entry point. These are sampled production
// paths with synthetic levels, not microphone recordings or animation timing tests.
extension AppDelegate {
    @MainActor func reviewVoiceGlyph(output: URL) throws {
        let area = CGRect(x: 0, y: 0, width: 24, height: 18)
        let paused = VoiceCaptureGlyphShape(paused: 1, speaking: 0, level: 0)
        let standby = VoiceCaptureGlyphShape(paused: 0, speaking: 0, level: 0)
        let quiet = VoiceCaptureGlyphShape(paused: 0, speaking: 1, level: 0.01)
        let loud = VoiceCaptureGlyphShape(paused: 0, speaking: 1, level: 1)
        let pausedGeometry = try glyphGeometry(paused, in: area)
        let standbyGeometry = try glyphGeometry(standby, in: area)
        let quietGeometry = try glyphGeometry(quiet, in: area)
        let loudGeometry = try glyphGeometry(loud, in: area)
        guard pausedGeometry.contours == 1, standbyGeometry.contours == 1,
              quietGeometry.contours == 5, loudGeometry.contours == 5,
              abs(standbyGeometry.bounds.width - standbyGeometry.bounds.height) < 0.001,
              loudGeometry.bounds.height > quietGeometry.bounds.height,
              abs(loudGeometry.bounds.width - quietGeometry.bounds.width) < 0.001,
              loud.path(in: area).contains(CGPoint(x: 12, y: loudGeometry.bounds.minY + 0.1)),
              !loud.path(in: area).contains(CGPoint(x: 12.95, y: loudGeometry.bounds.minY + 0.1)),
              paused.path(in: area).contains(CGPoint(x: 9.5, y: 5.5)),
              !paused.path(in: area).contains(CGPoint(x: 15.9, y: 5.5)),
              paused.path(in: area).contains(CGPoint(x: 15.9, y: 9)) else {
            throw VoiceGlyphReviewFailure("glyph endpoints lost triangle direction, round dot, five bars or level response")
        }
        for level in [0, 0.35, 1, -1, 2, .nan, .infinity] as [Double] {
            let fixedPause = try glyphGeometry(.init(paused: 1, speaking: 0, level: level), in: area)
            let fixedStandby = try glyphGeometry(.init(paused: 0, speaking: 0, level: level), in: area)
            guard fixedPause.points == pausedGeometry.points, fixedStandby.points == standbyGeometry.points else {
                throw VoiceGlyphReviewFailure("measured amplitude moved a paused or standby glyph")
            }
            _ = try glyphGeometry(.init(paused: 0, speaking: 1, level: level), in: area)
        }

        var frames = [VoiceGlyphReviewFrame]()
        func hold(_ phase: String, _ p: Double, _ s: Double, _ l: Double, _ duration: Int) {
            frames.append(.init(filename: String(format: "frame-%03d.png", frames.count),
                                duration_ms: duration, phase: phase, paused: p, speaking: s, level: l))
        }
        func transition(_ phase: String, from: (Double, Double, Double),
                        to: (Double, Double, Double), duration: Int) {
            let steps = duration / 20
            for index in 1...steps {
                let t = Double(index) / Double(steps)
                let eased = t * t * (3 - 2 * t)
                hold(phase, from.0 + (to.0 - from.0) * eased,
                     from.1 + (to.1 - from.1) * eased,
                     from.2 + (to.2 - from.2) * eased, 20)
            }
        }
        hold("paused", 1, 0, 0, 500)
        transition("triangle_to_dot", from: (1, 0, 0), to: (0, 0, 0), duration: 160)
        hold("standby", 0, 0, 0, 500)
        transition("dot_to_bars", from: (0, 0, 0), to: (0, 1, 0.15), duration: 160)
        var previousLevel = 0.15
        for level in [0.5, 0.9, 0.3, 0.08, 0.65, 0.2] {
            hold("synthetic_level_change", 0, 1, (previousLevel + level) / 2, 40)
            hold("synthetic_level_change", 0, 1, level, 60)
            previousLevel = level
        }
        transition("bars_to_dot", from: (0, 1, previousLevel), to: (0, 0, 0), duration: 160)
        hold("standby_after_speech", 0, 0, 0, 600)
        transition("dot_to_triangle", from: (0, 0, 0), to: (1, 0, 0), duration: 120)
        hold("paused_by_click", 1, 0, 0, 500)
        transition("triangle_to_dot", from: (1, 0, 0), to: (0, 0, 0), duration: 160)
        hold("standby", 0, 0, 0, 300)
        transition("dot_to_bars", from: (0, 0, 0), to: (0, 1, 0.6), duration: 160)
        hold("recognizing", 0, 1, 0.6, 300)
        transition("bars_to_triangle", from: (0, 1, 0.6), to: (1, 0, 0), duration: 120)
        hold("paused_during_speech", 1, 0, 0, 600)

        let directory = output.appendingPathComponent("voice-glyph-motion", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        for frame in frames {
            let shape = VoiceCaptureGlyphShape(paused: frame.paused, speaking: frame.speaking, level: frame.level)
            _ = try glyphGeometry(shape, in: area)
            // This mirrors only the existing capsule's paint and fixed size. The
            // production glyph geometry is reused; there is no new panel design.
            let content = shape.foregroundStyle(Palette.accent)
                .frame(width: 24, height: 18)
                .frame(width: 78, height: 30)
                .background(Palette.accent.opacity(0.12 - 0.06 * frame.paused), in: Capsule())
                .overlay(Capsule().stroke(.white.opacity(0.45), lineWidth: 0.75))
                .environment(\.colorScheme, .light)
            let renderer = ImageRenderer(content: content)
            renderer.scale = 3
            guard let image = renderer.cgImage,
                  let png = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) else {
                throw VoiceGlyphReviewFailure("offscreen SwiftUI glyph rendering failed")
            }
            try png.write(to: directory.appendingPathComponent(frame.filename))
        }
        let manifest = VoiceGlyphReviewManifest(
            scope: "Production SwiftUI glyph paths; synthetic amplitude and sampled morph parameters; no microphone, AX action, real-time animation timing or full-panel design approval. Offscreen ImageRenderer creates no windows.",
            width_points: 78, height_points: 30, scale: 3, frames: frames)
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(manifest).write(to: directory.appendingPathComponent("manifest.json"))
        print("UI_VOICE_GLYPH_PASS finite bounded morphs; right-facing triangle, stable dot, five real-level-dependent bar paths; \(frames.count) synthetic offscreen frames")
    }

    @MainActor private func glyphGeometry(_ shape: VoiceCaptureGlyphShape, in area: CGRect) throws -> VoiceGlyphGeometry {
        let path = shape.path(in: area)
        var points = [CGPoint](), contours = 0, closes = 0
        path.forEach { element in
            switch element {
            case .move(let point): points.append(point); contours += 1
            case .line(let point): points.append(point)
            case .quadCurve(let point, let control): points.append(contentsOf: [point, control])
            case .curve(let point, let first, let second): points.append(contentsOf: [point, first, second])
            case .closeSubpath: closes += 1
            }
        }
        let bounds = path.boundingRect, allowed = area.insetBy(dx: -0.001, dy: -0.001)
        guard !points.isEmpty, contours == closes,
              [bounds.minX, bounds.minY, bounds.width, bounds.height].allSatisfy({ $0.isFinite }),
              bounds.width > 0, bounds.height > 0,
              points.allSatisfy({ $0.x.isFinite && $0.y.isFinite && allowed.contains($0) }) else {
            throw VoiceGlyphReviewFailure("glyph path is nonfinite, unclosed or outside its 24x18 area")
        }
        return .init(points: points, contours: contours, bounds: bounds)
    }
}

private struct VoiceGlyphGeometry {
    let points: [CGPoint]
    let contours: Int
    let bounds: CGRect
}

private struct VoiceGlyphReviewFrame: Encodable {
    let filename: String
    let duration_ms: Int
    let phase: String
    let paused: Double
    let speaking: Double
    let level: Double
}

private struct VoiceGlyphReviewManifest: Encodable {
    let scope: String
    let width_points: Int
    let height_points: Int
    let scale: Int
    let frames: [VoiceGlyphReviewFrame]
}

private struct VoiceGlyphReviewFailure: LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}
