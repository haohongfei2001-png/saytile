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

    @Test func newPanelFitsAtUpperRightWithOneEighthGlassWidth() {
        for display in [CGRect(x: 0, y: 0, width: 1440, height: 875),
                        CGRect(x: -1920, y: 180, width: 1920, height: 1040),
                        CGRect(x: 0, y: -2000, width: 3024, height: 1920)] {
            let frame = WindowPlacement.initialPanel(visibleFrame: display)
            #expect(display.maxX - frame.maxX == 8)
            #expect(display.maxY - frame.maxY == 8)
            #expect(frame.width - 2 * WindowPlacement.panelShadowInset == (display.width / 8).rounded())
            #expect(frame.height == WindowPlacement.panelDefaultSize.height)
        }
    }

    @Test func portraitDisplayLeavesEnoughRoomForBothControls() {
        let display = CGRect(x: -800, y: -400, width: 800, height: 1280)
        let frame = WindowPlacement.initialPanel(visibleFrame: display)
        #expect(frame.width - 2 * WindowPlacement.panelShadowInset == 178)
        #expect(display.insetBy(dx: 8, dy: 8).contains(frame))
    }

    @Test func panelCanShrinkOrGrowAcrossAvailableScreen() {
        let display = CGRect(x: 0, y: 25, width: 1920, height: 850)
        let limits = WindowPlacement.panelLimits(visibleFrame: display)
        let initial = WindowPlacement.initialPanel(visibleFrame: display)
        #expect(limits.minimum == CGSize(width: 242, height: 214))
        #expect(limits.minimum.width < initial.width)
        #expect(limits.maximum == display.insetBy(dx: 8, dy: 8).size)
        #expect(WindowPlacement.panelSize(CGSize(width: 1, height: 1), visibleFrame: display) == limits.minimum)
        #expect(WindowPlacement.panelSize(CGSize(width: 3200, height: 2000), visibleFrame: display) == limits.maximum)
        let enlarged = CGSize(width: 920, height: 740)
        #expect(WindowPlacement.panelSize(enlarged, visibleFrame: display) == enlarged)
    }

    @Test func temporarilyDisconnectedWidePanelReturnsAtChosenSize() throws {
        let desk = CGRect(x: -1920, y: 0, width: 1920, height: 1050)
        let portrait = CGRect(x: 0, y: 0, width: 800, height: 1260)
        let enlarged = CGRect(x: -1720, y: 140, width: 1510, height: 790)
        let saved = try #require(SavedPanelPlacement(frame: enlarged, visibleFrame: desk, displayID: "external"))
        let fallback = try #require(saved.restored(on: [("portrait", portrait)]))
        #expect(portrait.insetBy(dx: 8, dy: 8).contains(fallback))
        #expect(fallback.width == 784 && fallback.height == enlarged.height)
        #expect(saved.restored(on: [("portrait", portrait), ("external", desk)]) == enlarged)
    }

    @Test func constrainedVisibleFrameTakesPrecedenceOverNormalMinimum() {
        let screen = CGRect(x: -300, y: -180, width: 220, height: 180)
        let limits = WindowPlacement.panelLimits(visibleFrame: screen)
        #expect(limits.minimum == CGSize(width: 204, height: 164))
        #expect(limits.maximum == limits.minimum)
        let frame = WindowPlacement.initialPanel(visibleFrame: screen)
        #expect(frame == screen.insetBy(dx: 8, dy: 8))
        #expect(WindowPlacement.restoredPanel(CGRect(x: 900, y: 900, width: 600, height: 900), visibleFrames: [screen]) == frame)
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

    @Test func largeUserPanelRestoresWithoutFormerWidthCap() {
        let screen = CGRect(x: 0, y: 40, width: 1280, height: 700)
        let restored = WindowPlacement.restoredPanel(CGRect(x: 1000, y: -300, width: 464, height: 614), visibleFrames: [screen])
        #expect(restored.size == CGSize(width: 464, height: 614))
        #expect(screen.insetBy(dx: 8, dy: 8).contains(restored))
    }

    @Test func tinyPositiveVisibleAreaNeverProducesNegativeWindowSize() {
        let screen = CGRect(x: -5, y: 8, width: 10, height: 8)
        let frame = WindowPlacement.initialPanel(visibleFrame: screen)
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
