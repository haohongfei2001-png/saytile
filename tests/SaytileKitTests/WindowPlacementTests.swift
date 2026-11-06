import Foundation
import Testing
@testable import SaytileKit

@Suite("Display geometry")
struct WindowPlacementTests {
    @Test func panelFitsOffsetAndCompactDisplays() {
        for screen in [CGRect(x: 0, y: 0, width: 1440, height: 875), CGRect(x: -1920, y: 180, width: 1920, height: 1040), CGRect(x: 1440, y: -400, width: 800, height: 500)] {
            for anchor in [CGRect(x: screen.maxX - 30, y: screen.maxY, width: 24, height: 24), CGRect(x: screen.minX + 2, y: screen.maxY, width: 24, height: 24)] {
                let frame = WindowPlacement.panel(anchor: anchor, visibleFrame: screen)
                #expect(screen.contains(frame))
                #expect(frame.width == 400)
                #expect(frame.height <= 550)
            }
        }
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
