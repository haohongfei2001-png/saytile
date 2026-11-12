import SaytileVoiceUI
import AppKit
import SaytileKit

/// Resize at the outer rail, move from its gutters, and leave the inner card’s
/// controls and occupied transcript lines available to their native views.
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
    private var customCursor = false

    func cancelPlacementGesture() {
        guard gesture != nil else { return }
        gesture = nil
        customCursor = false
        NSCursor.arrow.set()
    }

    func applyPlacement(_ proposed: CGRect, on visible: CGRect) {
        let bounded = WindowPlacement.restoredPanel(proposed, visibleFrames: [visible])
        let limits = WindowPlacement.panelLimits(visibleFrame: visible)
        if maxSize != limits.maximum || minSize != limits.minimum {
            minSize = .zero
            maxSize = limits.maximum
            minSize = limits.minimum
        }
        if frame != bounded { setFrame(bounded, display: isVisible) }
    }

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
                    let displays = NSScreen.screens.map { (frame: $0.frame, visible: $0.visibleFrame) }
                    if let visible = WindowPlacement.dragDestination(pointer: p, currentPanel: frame, displays: displays) {
                        applyPlacement(gesture.frame.offsetBy(dx: dx, dy: dy), on: visible)
                    }
                case .resize(let edge):
                    applyPlacement(resizedFrame(gesture, edge: edge, dx: dx, dy: dy), on: gesture.visible)
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
        let rail = CGRect(origin: .zero, size: frame.size)
        guard rail.contains(p) else { return nil }
        let card = VoiceRailMetrics(width: rail.width).cardFrame(in: rail)
        let left = p.x - rail.minX, right = rail.maxX - p.x
        let bottom = p.y - rail.minY, top = rail.maxY - p.y
        let metrics = VoicePanelMetrics(width: card.width, inRail: true)
        let scale = metrics.scale
        let corner = max(8, 18 * scale)
        if top <= corner && left <= corner { return .resize(.topLeft) }
        if top <= corner && right <= corner { return .resize(.topRight) }
        if bottom <= corner && left <= corner { return .resize(.bottomLeft) }
        if bottom <= corner && right <= corner { return .resize(.bottomRight) }
        if top <= 7 { return .resize(.top) }
        if bottom <= 7 { return .resize(.bottom) }
        if left <= 7 { return .resize(.left) }
        if right <= 7 { return .resize(.right) }

        guard card.contains(p) else { return .move }
        let cardLeft = p.x - card.minX, cardRight = card.maxX - p.x
        let cardBottom = p.y - card.minY, cardTop = card.maxY - p.y
        // The bottom gutter, gap between the controls, and top and left
        // margins move the panel even when every line of the transcript is full.
        if cardTop <= metrics.topPadding || cardBottom < metrics.footerBottom { return .move }
        if cardBottom <= metrics.footerBottom + metrics.controlHeight {
            let gapStart = metrics.footerLeading + metrics.copyWidth
            let gapEnd = ReferencePanelStyle.footerTrailing * scale + metrics.voiceWidth
            return cardLeft > gapStart && cardRight > gapEnd ? .move : nil
        }
        if cardLeft < ReferencePanelStyle.textInset * scale - 2 { return .move }

        // Every point in the transcript, including the blank canvas, accepts a
        // click to place the insertion point. The gutters above still drag.
        return nil
    }

    private func updatePointer(at point: CGPoint) {
        if let operation = operation(at: point) {
            operation.cursor.set()
            customCursor = true
        } else if customCursor {
            if let contentView, contentView.hitTest(contentView.convert(point, from: nil)) is CompactTranscriptTextView { NSCursor.iBeam.set() }
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
