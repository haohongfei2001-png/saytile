import SaytileVoiceUI
import AppKit
import SaytileKit

/// Resize at the outer rail, move from its gutters, and leave the inner card’s
/// controls and occupied transcript lines available to their native views.
final class VoicePanel: NSPanel {
    var expandedHeight: CGFloat?
    var expandedWidth: CGFloat?
    var anchorsRightOnExpand: Bool?
    var compactCaptureAction: (() -> Void)?
    var didChoosePosition: (() -> Void)?
    var isCompact: Bool { SaytileVoiceUI.VoicePanelFootprint.offersReadingSize(for: frame.size) }
    var draggingPlacement: Bool { gesture != nil || expansion != nil }
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
        let beganOnCapture: Bool
        var didDrag = false
    }
    private var gesture: Gesture?
    private var customCursor = false

    private struct Expansion {
        let from: CGRect
        let to: CGRect
        let visible: CGRect
        let started: CFTimeInterval
    }
    private var expansion: Expansion?
    private var expansionLink: CADisplayLink?

    private func stopExpansion() {
        expansionLink?.invalidate()
        expansionLink = nil
        expansion = nil
    }

    func cancelPlacementGesture() {
        stopExpansion()
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
        if !draggingPlacement { rememberReadingSize() }
    }

    private func rememberReadingSize() {
        guard !isCompact else { return }
        expandedWidth = frame.width
        expandedHeight = frame.height
    }

    func expandToReadingSize() {
        guard isCompact, let visible = screen?.visibleFrame else { return }
        cancelPlacementGesture()
        let target = WindowPlacement.expandedPanel(from: frame, on: visible, width: expandedWidth,
                                                   height: expandedHeight, anchorsRight: anchorsRightOnExpand)
        if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion || !isVisible {
            applyPlacement(target, on: visible)
            didChoosePosition?()
            return
        }
        expansion = Expansion(from: frame, to: target, visible: visible, started: CACurrentMediaTime())
        let link = displayLink(target: self, selector: #selector(advanceExpansion))
        expansionLink = link
        link.add(to: .main, forMode: .common)
    }

    @objc private func advanceExpansion() {
        guard let expansion else { return }
        let progress = min(1, max(0, (CACurrentMediaTime() - expansion.started) / 0.20))
        if progress >= 1 || NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            applyPlacement(expansion.to, on: expansion.visible)
            stopExpansion()
            rememberReadingSize()
            didChoosePosition?()
            return
        }
        let fraction = progress * progress * (3 - 2 * progress)
        func interpolate(_ start: CGFloat, _ end: CGFloat) -> CGFloat { start + (end - start) * fraction }
        let from = expansion.from, to = expansion.to
        let intermediate = CGRect(x: interpolate(from.minX, to.minX), y: interpolate(from.minY, to.minY),
                                  width: interpolate(from.width, to.width), height: interpolate(from.height, to.height))
        applyPlacement(intermediate, on: expansion.visible)
    }

    override func orderOut(_ sender: Any?) {
        if let expansion {
            stopExpansion()
            applyPlacement(expansion.to, on: expansion.visible)
            didChoosePosition?()
        }
        cancelPlacementGesture()
        super.orderOut(sender)
    }

    override func sendEvent(_ event: NSEvent) {
        switch event.type {
        case .leftMouseDown:
            stopExpansion()
            if !event.modifierFlags.contains(.control), let screen,
               let operation = operation(at: event.locationInWindow) {
                rememberReadingSize()
                gesture = Gesture(operation: operation, frame: frame,
                                  pointer: convertPoint(toScreen: event.locationInWindow), visible: screen.visibleFrame,
                                  beganOnCapture: VoicePanelLayout(size: frame.size).captureFrame.contains(event.locationInWindow))
                if case .move = operation, gesture?.beganOnCapture == false { NSCursor.closedHand.set() }
                return
            }
        case .leftMouseDragged:
            if let gesture {
                let p = convertPoint(toScreen: event.locationInWindow)
                let dx = p.x - gesture.pointer.x, dy = p.y - gesture.pointer.y
                if gesture.beganOnCapture && !gesture.didDrag && hypot(dx, dy) < 4 { return }
                self.gesture?.didDrag = true
                switch gesture.operation {
                case .move:
                    NSCursor.closedHand.set()
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
                if finished.beganOnCapture && !finished.didDrag {
                    let release = convertPoint(toScreen: event.locationInWindow)
                    if VoicePanelLayout(size: frame.size).captureFrame.contains(event.locationInWindow),
                       hypot(release.x - finished.pointer.x, release.y - finished.pointer.y) < 4 {
                        compactCaptureAction?()
                    }
                } else if frame != finished.frame {
                    if isCompact, case let .resize(edge) = finished.operation {
                        if [.left, .topLeft, .bottomLeft].contains(edge) { anchorsRightOnExpand = true }
                        if [.right, .topRight, .bottomRight].contains(edge) { anchorsRightOnExpand = false }
                    }
                    rememberReadingSize()
                    didChoosePosition?()
                }
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
        let layout = VoicePanelLayout(size: rail.size)
        if layout.canUseCopy && layout.copyFrame.contains(p) { return nil }
        let left = p.x, right = rail.width - p.x
        let bottom = p.y, top = rail.height - p.y
        let corner: CGFloat = min(12, min(rail.width, rail.height) / 4)
        if top <= corner && left <= corner { return .resize(.topLeft) }
        if top <= corner && right <= corner { return .resize(.topRight) }
        if bottom <= corner && left <= corner { return .resize(.bottomLeft) }
        if bottom <= corner && right <= corner { return .resize(.bottomRight) }
        if top <= 7 { return .resize(.top) }
        if bottom <= 7 { return .resize(.bottom) }
        if left <= 7 { return .resize(.left) }
        if right <= 7 { return .resize(.right) }

        if layout.captureFrame.contains(p) {
            // The smallest surface can still be moved by dragging the glyph.
            // Mouse-up inside its original footprint is the only capture action.
            return isCompact ? .move : nil
        }
        if layout.canUseTranscript && layout.transcriptFrame.contains(p) { return nil }
        return .move
    }

    private func updatePointer(at point: CGPoint) {
        if let operation = operation(at: point) {
            if case .move = operation, VoicePanelLayout(size: frame.size).captureFrame.contains(point) {
                NSCursor.pointingHand.set()
            } else { operation.cursor.set() }
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
        let visible = gesture.visible
        let width = left ? min(start.maxX - visible.minX, start.width - dx) :
                    right ? min(visible.maxX - start.minX, start.width + dx) : start.width
        let height = bottom ? min(start.maxY - visible.minY, start.height - dy) :
                     top ? min(visible.maxY - start.minY, start.height + dy) : start.height
        let size = WindowPlacement.panelSize(CGSize(width: width, height: height), visibleFrame: visible)
        let y = bottom ? start.maxY - size.height : start.minY
        return CGRect(x: left ? start.maxX - size.width : start.minX, y: y,
                      width: size.width, height: size.height)
    }
}
