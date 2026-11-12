import SaytileVoiceUI
import AppKit
import SaytileKit

/// The NSPanel includes a transparent margin. Its system resize border is too
/// far from the visible glass to serve as the primary pointer affordance.
final class VoicePanel: NSPanel {
    var didChoosePosition: (() -> Void)?
    var draggingPlacement: Bool { gesture != nil }
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    private enum Operation {
        case move
        case resize(NSCursor.FrameResizePosition)

        var cursor: NSCursor {
            switch self {
            case .move: return .openHand
            case .resize(let edge): return .frameResize(position: edge, directions: .all)
            }
        }
    }

    private struct Gesture {
        let operation: Operation
        let frame: CGRect
        let pointer: CGPoint
        let visible: CGRect
    }
    private var gesture: Gesture?
    private weak var transcript: CompactTranscriptTextView?
    private var customCursor = false

    override func sendEvent(_ event: NSEvent) {
        switch event.type {
        case .leftMouseDown:
            if !event.modifierFlags.contains(.control), let screen,
               let operation = operation(at: event.locationInWindow) {
                gesture = Gesture(operation: operation, frame: frame,
                                  pointer: convertPoint(toScreen: event.locationInWindow), visible: screen.visibleFrame)
                if case .move = operation { NSCursor.closedHand.set() }
                return
            }
        case .leftMouseDragged:
            if let gesture {
                let p = convertPoint(toScreen: event.locationInWindow)
                let dx = p.x - gesture.pointer.x, dy = p.y - gesture.pointer.y
                switch gesture.operation {
                case .move:
                    // Constrain only on release so the pointer can cross between displays.
                    setFrameOrigin(CGPoint(x: gesture.frame.minX + dx, y: gesture.frame.minY + dy))
                case .resize(let edge):
                    setFrame(resizedFrame(gesture, edge: edge, dx: dx, dy: dy), display: true)
                }
                return
            }
        case .leftMouseUp:
            if let finished = gesture {
                gesture = nil
                if frame != finished.frame { didChoosePosition?() }
                updatePointer(at: event.locationInWindow)
                return
            }
        case .mouseMoved, .cursorUpdate:
            super.sendEvent(event)
            if gesture == nil { updatePointer(at: event.locationInWindow) }
            return
        default: break
        }
        super.sendEvent(event)
    }

    private func operation(at p: CGPoint) -> Operation? {
        let card = CGRect(origin: .zero, size: frame.size).insetBy(dx: WindowPlacement.panelShadowInset, dy: WindowPlacement.panelShadowInset)
        guard card.insetBy(dx: -7, dy: -7).contains(p) else { return nil }
        let left = p.x - card.minX, right = card.maxX - p.x
        let bottom = p.y - card.minY, top = card.maxY - p.y
        let scale = VoicePanelMetrics(width: card.width).scale
        let corner = max(8, 18 * scale)
        if top <= corner && left <= corner { return .resize(.topLeft) }
        if top <= corner && right <= corner { return .resize(.topRight) }
        if bottom <= corner && left <= corner { return .resize(.bottomLeft) }
        if bottom <= corner && right <= corner { return .resize(.bottomRight) }
        if top <= 7 { return .resize(.top) }
        if bottom <= 7 { return .resize(.bottom) }
        if left <= 7 { return .resize(.left) }
        if right <= 7 { return .resize(.right) }

        // The bottom gutter, gap between the controls, and top and left
        // margins move the panel even when every line of the transcript is full.
        if top <= 10 * scale || bottom < ReferencePanelStyle.footerBottom * scale { return .move }
        if bottom <= ReferencePanelStyle.footerBottom * scale + ReferencePanelStyle.controlHeight * scale {
            let gapStart = ReferencePanelStyle.footerLeading * scale + ReferencePanelStyle.copyWidth * scale
            let gapEnd = ReferencePanelStyle.footerTrailing * scale + ReferencePanelStyle.voiceWidth * scale
            return left > gapStart && right > gapEnd ? .move : nil
        }
        if left < ReferencePanelStyle.textInset * scale - 2 { return .move }

        if transcript == nil { transcript = findTranscript(in: contentView) }
        guard let transcript, let scroller = transcript.enclosingScrollView,
              transcript.selectedRange().length == 0 else { return nil }
        let clip = scroller.contentView
        guard clip.bounds.contains(clip.convert(p, from: nil)) else { return nil }
        if let bar = scroller.verticalScroller, !bar.isHidden,
           bar.bounds.contains(bar.convert(p, from: nil)) { return nil }
        if transcript.string.isEmpty { return .move }
        guard let manager = transcript.layoutManager, let container = transcript.textContainer else { return nil }
        let point = transcript.convert(p, from: nil)
        let textBottom = transcript.textContainerOrigin.y + manager.usedRect(for: container).maxY
        // Leave entire occupied lines (including their trailing whitespace) to
        // NSTextView for selection, contextual commands and double/triple-clicks.
        return point.y > textBottom ? .move : nil
    }

    private func findTranscript(in view: NSView?) -> CompactTranscriptTextView? {
        if let text = view as? CompactTranscriptTextView { return text }
        for child in view?.subviews ?? [] {
            if let text = findTranscript(in: child) { return text }
        }
        return nil
    }

    private func updatePointer(at point: CGPoint) {
        if let operation = operation(at: point) {
            operation.cursor.set()
            customCursor = true
        } else if customCursor {
            if let transcript, transcript.visibleRect.contains(transcript.convert(point, from: nil)) { NSCursor.iBeam.set() }
            else { NSCursor.arrow.set() }
            customCursor = false
        }
    }

    private func resizedFrame(_ gesture: Gesture, edge: NSCursor.FrameResizePosition, dx: CGFloat, dy: CGFloat) -> CGRect {
        let start = gesture.frame
        let left = [.left, .topLeft, .bottomLeft].contains(edge)
        let right = [.right, .topRight, .bottomRight].contains(edge)
        let top = [.top, .topLeft, .topRight].contains(edge)
        let bottom = [.bottom, .bottomLeft, .bottomRight].contains(edge)
        let limits = WindowPlacement.panelLimits(visibleFrame: gesture.visible)
        let area = CGRect(x: gesture.visible.midX - limits.maximum.width / 2,
                          y: gesture.visible.midY - limits.maximum.height / 2,
                          width: limits.maximum.width, height: limits.maximum.height)
        let width = left ? min(start.maxX - area.minX, start.width - dx) :
                    right ? min(area.maxX - start.minX, start.width + dx) : start.width
        let height = bottom ? min(start.maxY - area.minY, start.height - dy) :
                     top ? min(area.maxY - start.minY, start.height + dy) : start.height
        let size = WindowPlacement.panelSize(CGSize(width: width, height: height), visibleFrame: gesture.visible)
        return CGRect(x: left ? start.maxX - size.width : start.minX,
                      y: bottom ? start.maxY - size.height : start.minY, width: size.width, height: size.height)
    }
}
