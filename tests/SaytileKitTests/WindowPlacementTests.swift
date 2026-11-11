import Foundation
import Testing
@testable import SaytileKit

@Suite("Display geometry")
struct WindowPlacementTests {
    @Test func referenceCardGeometryExcludesTransparentShadowMargin() {
        let size = WindowPlacement.panelDefaultSize
        let inset = WindowPlacement.panelShadowInset
        #expect(size.width - 2 * inset == 344)
        #expect(size.height - 2 * inset == 234)
        #expect(WindowPlacement.panelContentDefaultSize == CGSize(width: 344, height: 234))
    }

    @Test func unlaidOutMenuAnchorCannotPlaceFreshWindowInBottomCorner() {
        let display = CGRect(x:0,y:0,width:1920,height:1080)
        let fallback = WindowPlacement.panel(anchor:nil,visibleFrame:display)
        #expect(WindowPlacement.panel(anchor:CGRect(x:0,y:0,width:28,height:22),visibleFrame:display) == fallback)
        #expect(fallback.midX == display.midX && fallback.midY == display.midY)
        #expect(WindowPlacement.panel(anchor:CGRect(x:1720,y:1056,width:24,height:24),visibleFrame:display) != fallback)
    }

    @Test func panelFitsOffsetAndCompactDisplays() {
        for screen in [CGRect(x: 0, y: 0, width: 1440, height: 875), CGRect(x: -1920, y: 180, width: 1920, height: 1040), CGRect(x: 1440, y: -400, width: 800, height: 500)] {
            for anchor in [CGRect(x: screen.maxX - 30, y: screen.maxY, width: 24, height: 24), CGRect(x: screen.minX + 2, y: screen.maxY, width: 24, height: 24)] {
                let frame = WindowPlacement.panel(anchor: anchor, visibleFrame: screen)
                #expect(screen.contains(frame))
                #expect(frame.size == CGSize(width: 408, height: 298))
            }
        }
    }

    @Test func compactResizeLimitsBoundLargeContentAndSmallDragRequests() {
        let screen = CGRect(x: 0, y: 25, width: 1440, height: 850)
        let limits = WindowPlacement.panelLimits(visibleFrame: screen)
        #expect(limits.minimum == CGSize(width: 384, height: 264))
        #expect(limits.maximum == CGSize(width: 424, height: 544))
        #expect(WindowPlacement.panelSize(CGSize(width: 10, height: 20), visibleFrame: screen) == limits.minimum)
        #expect(WindowPlacement.panelSize(CGSize(width: 900, height: 20_000), visibleFrame: screen) == limits.maximum)
        #expect(WindowPlacement.panelSize(CGSize(width: 414, height: 474), visibleFrame: screen) == CGSize(width: 414, height: 474))
    }

    @Test func constrainedVisibleFrameTakesPrecedenceOverNormalMinimum() {
        let screen = CGRect(x: -300, y: -180, width: 300, height: 180)
        let limits = WindowPlacement.panelLimits(visibleFrame: screen)
        #expect(limits.minimum == CGSize(width: 284, height: 164))
        #expect(limits.maximum == limits.minimum)
        let frame = WindowPlacement.panel(anchor: CGRect(x: -8, y: 0, width: 20, height: 20), visibleFrame: screen)
        #expect(frame == screen.insetBy(dx: 8, dy: 8))
        #expect(WindowPlacement.restoredPanel(CGRect(x: 900, y: 900, width: 600, height: 900), visibleFrames: [screen]) == frame)
    }

    @Test func displayScaleDoesNotMultiplyLogicalPanelSize() {
        // Different macOS scaling choices change logical visible frames, not
        // the desired point size of the same panel.
        for size in [CGSize(width: 1280, height: 775), CGSize(width: 1920, height: 1055), CGSize(width: 2560, height: 1415)] {
            let frame = WindowPlacement.panel(anchor: nil, visibleFrame: CGRect(origin: .zero, size: size))
            #expect(frame.size == WindowPlacement.panelDefaultSize)
        }
    }

    @Test func reopeningKeepsUserPositionAndResizeWithinBounds() {
        let screen = CGRect(x: -1440, y: 120, width: 1440, height: 875)
        let moved = CGRect(x: -900, y: 240, width: 414, height: 474)
        #expect(WindowPlacement.restoredPanel(moved, visibleFrames: [screen]) == moved)
        #expect(WindowPlacement.restoredPanel(moved, visibleFrames: []) == moved)
    }

    @Test func disconnectedPanelUsesNearestRemainingDisplayRegardlessOfArrayOrder() {
        let left = CGRect(x: -1440, y: 0, width: 1440, height: 900)
        let right = CGRect(x: 0, y: 0, width: 1440, height: 900)
        let disconnected = CGRect(x: 3000, y: 200, width: 414, height: 474)
        let restored = WindowPlacement.restoredPanel(disconnected, visibleFrames: [left, right])
        #expect(right.insetBy(dx: 8, dy: 8).contains(restored))
        #expect(restored.size == disconnected.size)
        #expect(restored == WindowPlacement.restoredPanel(disconnected, visibleFrames: [right, left]))
    }

    @Test func legacyOversizedPanelRestoresWithinNewCompactBounds() {
        let screen = CGRect(x: 0, y: 40, width: 1280, height: 700)
        let restored = WindowPlacement.restoredPanel(CGRect(x: 1000, y: -300, width: 464, height: 614), visibleFrames: [screen])
        #expect(restored.size == CGSize(width: 424, height: 544))
        #expect(screen.insetBy(dx: 8, dy: 8).contains(restored))
    }

    @Test func tinyPositiveVisibleAreaNeverProducesNegativeWindowSize() {
        let screen = CGRect(x: -5, y: 8, width: 10, height: 8)
        let frame = WindowPlacement.panel(anchor: nil, visibleFrame: screen)
        #expect(frame.width == 1 && frame.height == 1)
        #expect(screen.contains(frame))
    }

    @Test func disconnectedDisplayRestoresToRemainingScreen() {
        let screen = CGRect(x: 0, y: 0, width: 1280, height: 800)
        let old = CGRect(x: -1800, y: 90, width: 1040, height: 720)
        let restored = WindowPlacement.restored(old, visibleFrames: [screen])
        #expect(screen.contains(restored))
        #expect(restored.size == old.size)
    }

    @Test func keepsWindowOnDisplayWithLargestOverlap() {
        let left = CGRect(x: -1280, y: 0, width: 1280, height: 800)
        let right = CGRect(x: 0, y: 0, width: 1440, height: 900)
        let frame = CGRect(x: -900, y: 30, width: 800, height: 570)
        #expect(WindowPlacement.restored(frame, visibleFrames: [right, left]) == frame)
        #expect(WindowPlacement.restored(frame, visibleFrames: []) == frame)
    }
}

@Test func preferredPanelSurvivesDisconnectAndChangedScale() throws {
    let a = CGRect(x: -1600, y: 40, width: 1600, height: 900)
    let b = CGRect(x: 0, y: 20, width: 1200, height: 760)
    let frame = CGRect(x: -520, y: 320, width: 416, height: 350)
    let saved = try #require(SavedPanelPlacement(frame: frame, visibleFrame: a, displayID: "desk"))
    let persisted = try JSONDecoder().decode(SavedPanelPlacement.self, from: JSONEncoder().encode(saved))
    #expect(persisted.restored(on: [("built-in", b), ("desk", a)]) == frame)
    #expect(b.contains(try #require(persisted.restored(on: [("built-in", b)]))))
    let scaled = CGRect(x: -1100, y: 10, width: 1100, height: 700)
    let changed = try #require(persisted.restored(on: [("desk", scaled)]))
    #expect(scaled.contains(changed) && changed.midX > scaled.midX && changed.size == frame.size)
    #expect(persisted.restored(on: [("desk", a)]) == frame)
    #expect(persisted.restored(on: []) == nil)
}
