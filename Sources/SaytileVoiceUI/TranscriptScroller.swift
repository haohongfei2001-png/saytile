import AppKit

/// Only the position mark is painted. AppKit keeps the full native drag target,
/// accessibility actions and overlay fade, including the system “Always” preference.
@MainActor
final class TranscriptScroller: NSScroller {
    override class var isCompatibleWithOverlayScrollers: Bool { true }

    override func drawKnobSlot(in slotRect: NSRect, highlight flag: Bool) {}

    override func drawKnob() {
        let knob = rect(for: .knob)
        guard knob.height > 0, knob.width > 0 else { return }
        let highContrast = NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast
        let width = min(knob.width, highContrast ? 4 : 2.5)
        let mark = NSRect(x: knob.midX - width / 2, y: knob.minY,
                          width: width, height: knob.height)
        NSColor.labelColor.withAlphaComponent(highContrast ? 0.73 : 0.33).setFill()
        NSBezierPath(roundedRect: mark, xRadius: width / 2, yRadius: width / 2).fill()
    }
}
