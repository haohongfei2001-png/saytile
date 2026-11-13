import Foundation
import Testing
@testable import SaytileKit
import SaytileVoiceUI

@Suite("Display geometry")
struct WindowPlacementTests {
    @Test func glassRimIsEvenAndCornersRemainConcentricWhenResized() {
        let slot = CGRect(x: 1347, y: 0, width: 325, height: 175)
        let metrics = VoiceRailMetrics(width: slot.width)
        #expect(metrics.cardFrame(in: slot) == slot.insetBy(dx: 10, dy: 10))
        for width: CGFloat in [100, 178, 240, 325, 560, 1280] {
            let frame = CGRect(x: 450, y: 22, width: width, height: 175)
            let outer = VoiceRailMetrics(width: width)
            let inner = outer.cardFrame(in: frame)
            let inset = inner.minX - frame.minX
            #expect(abs(inner.minY - frame.minY - inset) < 0.000_001)
            #expect(abs(frame.maxY - inner.maxY - inset) < 0.000_001)
            #expect(abs(frame.maxX - inner.maxX - inset) < 0.000_001)
            #expect(abs(outer.radius - VoicePanelMetrics(width: inner.width, inRail: true).radius - inset) < 0.000_001)
        }
        let tiny = CGRect(x: 10, y: 20, width: 240, height: 2)
        #expect(VoiceRailMetrics.factoryHeight(width: 325, visibleHeight: 940) == 173)
        #expect(VoiceRailMetrics.factoryHeight(width: 325, visibleHeight: 400) == 90)
        #expect(tiny.contains(VoiceRailMetrics(width: tiny.width).cardFrame(in: tiny)))
    }

    @Test func legacyExpandedPlacementMigratesOnceToTheVisibleRail() throws {
        let screen = CGRect(x: -1200, y: 30, width: 1200, height: 800)
        let chosen = CGRect(x: -1000, y: 200, width: 305, height: 227)
        let old = try #require(SavedPanelPlacement(frame: chosen.insetBy(dx: -32, dy: -32),
                                                  visibleFrame: screen, displayID: "external"))
        let migrated = try #require(old.removingLegacyShadowMargin())
        #expect(migrated.frame == chosen)
        #expect(migrated.restored(on: [("external", screen)]) == chosen)
        #expect(old.frame.size == CGSize(width: 369, height: 291))
    }

    @Test func newPanelMatchesNearpaneVoiceRectAcrossDisplays() {
        for display in [CGRect(x: 0, y: 0, width: 1440, height: 875),
                        CGRect(x: 0, y: 25, width: 1280, height: 650),
                        CGRect(x: -1920, y: 180, width: 1920, height: 1040),
                        CGRect(x: 0, y: -2000, width: 3024, height: 1920)] {
            let frame = WindowPlacement.initialPanel(visibleFrame: display)
            let card = VoiceRailMetrics(width: frame.width).cardFrame(in: frame)
            #expect(frame.maxX == display.maxX)
            #expect(abs(frame.maxY - display.maxY) < 0.000_001)
            #expect(frame.width == display.width * 0.125)
            #expect(frame.height == min(display.height * 0.225, frame.width * 173 / 325))
            #expect(display.contains(frame))
            #expect(frame.contains(card) && card.width < frame.width && card.height < frame.height)
        }
    }

    @Test func portraitDisplayUsesTheSameFactoryWidthAsTheSidebar() {
        let display = CGRect(x: -800, y: -400, width: 800, height: 1280)
        let frame = WindowPlacement.initialPanel(visibleFrame: display)
        #expect(frame.width == 100)
        #expect(display.contains(frame))
    }

    @Test func panelCanShrinkOrGrowAcrossAvailableScreen() {
        let display = CGRect(x: 0, y: 25, width: 1920, height: 850)
        let limits = WindowPlacement.panelLimits(visibleFrame: display)
        let initial = WindowPlacement.initialPanel(visibleFrame: display)
        #expect(limits.minimum == CGSize(width: 72, height: 44))
        #expect(limits.minimum.width < initial.width)
        #expect(limits.minimum.height < initial.height)
        #expect(limits.maximum == display.size)
        #expect(WindowPlacement.panelSize(CGSize(width: 1, height: 1), visibleFrame: display) == limits.minimum)
        #expect(WindowPlacement.panelSize(CGSize(width: 3200, height: 2000), visibleFrame: display) == limits.maximum)
        let enlarged = CGSize(width: 920, height: 740)
        #expect(WindowPlacement.panelSize(enlarged, visibleFrame: display) == enlarged)
    }

    @Test func compactWidthUsesOneFixedHeightAndKeepsThePreviousTopEdge() throws {
        let screen = CGRect(x: -800, y: 20, width: 1280, height: 740)
        let wide = CGRect(x: -600, y: 306, width: 245, height: 187)
        let narrow = CGRect(x: wide.maxX - 77, y: wide.minY, width: 77, height: wide.height)
        let compact = WindowPlacement.restoredPanel(narrow, visibleFrames: [screen])
        #expect(compact == CGRect(x: narrow.minX, y: wide.maxY - 44, width: 77, height: 44))
        #expect(WindowPlacement.panelSize(CGSize(width: 81, height: wide.height), visibleFrame: screen).height == wide.height)
        let saved = try #require(SavedPanelPlacement(frame: compact, visibleFrame: screen,
                                                     displayID: "built-in", expandedHeight: wide.height))
        let reopened = try JSONDecoder().decode(SavedPanelPlacement.self, from: JSONEncoder().encode(saved))
        #expect(reopened.expandedHeight == wide.height)
        #expect(reopened.restored(on: [("built-in", screen)]) == compact)
        let previous = try #require(SavedPanelPlacement(frame: wide, visibleFrame: screen, displayID: "built-in"))
        let legacy = try JSONDecoder().decode(SavedPanelPlacement.self, from: JSONEncoder().encode(previous))
        #expect(legacy.expandedHeight == nil && legacy.restored(on: [("built-in", screen)]) == wide)
    }

    @Test func temporarilyDisconnectedWidePanelReturnsAtChosenSize() throws {
        let desk = CGRect(x: -1920, y: 0, width: 1920, height: 1050)
        let portrait = CGRect(x: 0, y: 0, width: 800, height: 1260)
        let enlarged = CGRect(x: -1720, y: 140, width: 1510, height: 790)
        let saved = try #require(SavedPanelPlacement(frame: enlarged, visibleFrame: desk, displayID: "external"))
        let fallback = try #require(saved.restored(on: [("portrait", portrait)]))
        #expect(portrait.contains(fallback))
        #expect(fallback.width == portrait.width && fallback.height == enlarged.height)
        #expect(saved.restored(on: [("portrait", portrait), ("external", desk)]) == enlarged)
    }

    @Test func constrainedVisibleFrameTakesPrecedenceOverNormalMinimum() {
        let screen = CGRect(x: -300, y: -180, width: 220, height: 180)
        let limits = WindowPlacement.panelLimits(visibleFrame: screen)
        #expect(limits.minimum == CGSize(width: 27.5, height: 27.5 * 173 / 325))
        #expect(limits.maximum == screen.size)
        let frame = WindowPlacement.initialPanel(visibleFrame: screen)
        #expect(screen.contains(frame))
        #expect(screen.contains(WindowPlacement.restoredPanel(CGRect(x: 900, y: 900, width: 600, height: 900), visibleFrames: [screen])))
    }

    @Test func savedDockedGlassRemainsEdgeAlignedAfterDisplayRescale() throws {
        let old = CGRect(x: -1920, y: 0, width: 1920, height: 1080)
        let fresh = CGRect(x: -2560, y: 30, width: 2560, height: 1390)
        let frame = WindowPlacement.initialPanel(visibleFrame: old)
        let saved = try #require(SavedPanelPlacement(frame: frame, visibleFrame: old, displayID: "primary"))
        let result = try #require(saved.restored(on: [("primary", fresh)]))
        #expect(result.maxX == fresh.maxX)
        #expect(result.maxY == fresh.maxY)
        #expect(result.size == frame.size)
        #expect(fresh.contains(result))
    }

    @Test func draggedPanelFollowsPointerAcrossScreensAndRespectsSystemUI() throws {
        let left = CGRect(x: -1440, y: -300, width: 1440, height: 900)
        let right = CGRect(x: 0, y: 0, width: 800, height: 1000)
        let leftUsable = CGRect(x: -1400, y: -300, width: 1400, height: 875)
        let rightUsable = CGRect(x: 0, y: 60, width: 800, height: 915)
        let displays = [(frame: left, visible: leftUsable), (frame: right, visible: rightUsable)]
        let large = CGRect(x: -1300, y: -200, width: 1100, height: 700)
        let menu = CGPoint(x: 1, y: 990)
        let dock = CGPoint(x: 12, y: 10)
        for pointer in [menu, dock] {
            let target = try #require(WindowPlacement.dragDestination(pointer: pointer, currentPanel: large, displays: displays))
            #expect(target == rightUsable)
            let placed = WindowPlacement.restoredPanel(large, visibleFrames: [target])
            #expect(rightUsable.contains(placed))
            #expect(placed.width == rightUsable.width)
        }
        let gap = CGPoint(x: 20, y: -25)
        #expect(WindowPlacement.dragDestination(pointer: gap, currentPanel: large, displays: displays) == leftUsable)
        #expect(WindowPlacement.dragDestination(pointer: gap, currentPanel: large, displays: [displays[1]]) == rightUsable)
        #expect(WindowPlacement.dragDestination(pointer: gap, currentPanel: large, displays: []) == nil)
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
        #expect(right.contains(restored))
        #expect(restored.size == disconnected.size)
        #expect(restored == WindowPlacement.restoredPanel(disconnected, visibleFrames: [right, left]))
    }

    @Test func largeUserPanelRestoresWithoutFormerWidthCap() {
        let screen = CGRect(x: 0, y: 40, width: 1280, height: 700)
        let restored = WindowPlacement.restoredPanel(CGRect(x: 1000, y: -300, width: 464, height: 614), visibleFrames: [screen])
        #expect(restored.size == CGSize(width: 464, height: 614))
        #expect(screen.contains(restored))
    }

    @Test func tinyPositiveVisibleAreaNeverProducesNegativeWindowSize() {
        let screen = CGRect(x: -5, y: 8, width: 10, height: 8)
        let frame = WindowPlacement.initialPanel(visibleFrame: screen)
        #expect(frame.width == 10 && abs(frame.height - 1.8) < 0.000_001)
        #expect(frame.maxX == screen.maxX && frame.maxY == screen.maxY)
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
    let fallback = try #require(persisted.restored(on: [("built-in", b)]))
    #expect(b.contains(fallback))
    #expect(fallback.minX == b.minX)
    #expect(fallback.size == frame.size)
    let scaled = CGRect(x: -1100, y: 10, width: 1100, height: 700)
    let changed = try #require(persisted.restored(on: [("desk", scaled)]))
    #expect(scaled.contains(changed) && changed.midX > scaled.midX && changed.size == frame.size)
    #expect(persisted.restored(on: [("desk", a)]) == frame)
    #expect(persisted.restored(on: []) == nil)
}
