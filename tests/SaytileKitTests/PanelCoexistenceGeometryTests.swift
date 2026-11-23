import Foundation
import CoreGraphics
import Testing
@testable import SaytileKit

@Suite("Panel coexistence geometry")
struct PanelCoexistenceGeometryTests {
    private let screen = CGRect(x: 0, y: 0, width: 1400, height: 900)
    private let panel = CGRect(x: 1000, y: 600, width: 200, height: 200)

    @Test func placementModesKeepStableStorageValues() throws {
        #expect(PanelPlacementMode.allCases.map(\.rawValue) == ["floating", "boundary"])
        for mode in PanelPlacementMode.allCases {
            #expect(try JSONDecoder().decode(PanelPlacementMode.self, from: JSONEncoder().encode(mode)) == mode)
        }
    }

    @Test func nonoverlappingWindowAndExactGapDoNotMove() {
        let frame = CGRect(x: 100, y: 100, width: 500, height: 500)
        #expect(PanelCoexistenceGeometry.ordinaryWindow(frame, excluding: panel, visibleFrame: screen) == frame)
        let touchingGap = CGRect(x: 592, y: 500, width: 400, height: 300)
        #expect(PanelCoexistenceGeometry.ordinaryWindow(touchingGap, excluding: panel, visibleFrame: screen) == touchingGap)
    }

    @Test func overlappingOrdinaryWindowUsesClosestSizePreservingTranslation() {
        let frame = CGRect(x: 700, y: 500, width: 400, height: 300)
        #expect(PanelCoexistenceGeometry.ordinaryWindow(frame, excluding: panel, visibleFrame: screen)
                == CGRect(x: 592, y: 500, width: 400, height: 300))
    }

    @Test func preserveSizeTakesPriorityOverNearbyShrinking() {
        let area = CGRect(x: 0, y: 0, width: 1000, height: 800)
        let obstacle = CGRect(x: 700, y: 100, width: 100, height: 400)
        let frame = CGRect(x: 700, y: 100, width: 300, height: 400)
        #expect(PanelCoexistenceGeometry.ordinaryWindow(frame, excluding: obstacle, visibleFrame: area)
                == CGRect(x: 392, y: 100, width: 300, height: 400))
    }

    @Test func oversizedWindowKeepsLargestAvailableAreaWithoutCrossingPanel() {
        let area = CGRect(x: 0, y: 0, width: 1280, height: 720)
        let obstacle = CGRect(x: 1120, y: 560, width: 160, height: 160)
        #expect(PanelCoexistenceGeometry.ordinaryWindow(area, excluding: obstacle, visibleFrame: area)
                == CGRect(x: 0, y: 0, width: 1112, height: 720))
    }

    @Test func minimumSizeCanRefuseMovementButExistingSmallWindowsStaySmall() {
        let area = CGRect(x: 0, y: 0, width: 400, height: 300)
        let obstacle = CGRect(x: 100, y: 0, width: 200, height: 300)
        #expect(PanelCoexistenceGeometry.ordinaryWindow(area, excluding: obstacle, visibleFrame: area) == nil)
        let tiny = CGRect(x: 150, y: 100, width: 80, height: 60)
        #expect(PanelCoexistenceGeometry.ordinaryWindow(tiny, excluding: obstacle, visibleFrame: area)
                == CGRect(x: 12, y: 100, width: 80, height: 60))
        let custom = PanelCoexistenceGeometry.ordinaryWindow(area, excluding: obstacle, visibleFrame: area,
                                                            minimumSize: CGSize(width: 80, height: 60))
        #expect(custom?.size == CGSize(width: 92, height: 300))
    }

    @Test func disconnectedAndNegativeOriginScreenRemainWithinSingleVisibleFrame() throws {
        let area = CGRect(x: -1280, y: 40, width: 1280, height: 760)
        let obstacle = CGRect(x: -160, y: 600, width: 160, height: 200)
        let old = CGRect(x: 1800, y: 100, width: 800, height: 500)
        let result = try #require(PanelCoexistenceGeometry.ordinaryWindow(old, excluding: obstacle, visibleFrame: area))
        #expect(area.contains(result))
        #expect(result.size == old.size)
        #expect(!intersectsArea(result, obstacle.insetBy(dx: -8, dy: -8)))
        // A panel entirely on a disconnected display reserves no space here.
        #expect(PanelCoexistenceGeometry.ordinaryWindow(result, excluding: panel, visibleFrame: area) == result)
    }

    @Test func ordinaryPlacementHasContainmentSeparationAndIdempotenceAcrossSizes() {
        for x in stride(from: -200, through: 1400, by: 200) {
            for y in stride(from: -100, through: 900, by: 200) {
                for size in [CGSize(width: 100, height: 80), CGSize(width: 500, height: 400), CGSize(width: 1700, height: 1000)] {
                    let requested = CGRect(origin: CGPoint(x: x, y: y), size: size)
                    if let result = PanelCoexistenceGeometry.ordinaryWindow(requested, excluding: panel, visibleFrame: screen) {
                        #expect(screen.contains(result))
                        #expect(!intersectsArea(result, panel.insetBy(dx: -8, dy: -8)))
                        #expect(result.width <= size.width && result.height <= size.height)
                        #expect(result.width >= min(size.width, 320) && result.height >= min(size.height, 180))
                        #expect(PanelCoexistenceGeometry.ordinaryWindow(result, excluding: panel, visibleFrame: screen) == result)
                    }
                }
            }
        }
    }

    @Test func fullScreenMovesInEachDirectionWithoutChangingPanelSize() throws {
        let area = CGRect(x: 0, y: 0, width: 1000, height: 1000)
        let preferred = CGRect(x: 450, y: 450, width: 100, height: 100)
        let pairs: [(CGRect, CGPoint)] = [
            (CGRect(x: 500, y: 450, width: 60, height: 100), CGPoint(x: 392, y: 450)),
            (CGRect(x: 390, y: 450, width: 110, height: 100), CGPoint(x: 508, y: 450)),
            (CGRect(x: 450, y: 500, width: 100, height: 60), CGPoint(x: 450, y: 392)),
            (CGRect(x: 450, y: 390, width: 100, height: 110), CGPoint(x: 450, y: 508))]
        for (control, expected) in pairs {
            let result = try #require(PanelCoexistenceGeometry.fullscreenPanel(preferred: preferred, avoiding: [control], visibleFrame: area))
            #expect(result == CGRect(origin: expected, size: preferred.size))
            #expect(area.contains(result))
            #expect(!intersectsArea(result, control.insetBy(dx: -8, dy: -8)))
        }
    }

    @Test func fullScreenUsesShortestFeasibleTranslationAgainstAnExhaustiveGridOracle() throws {
        let area = CGRect(x: -10, y: -20, width: 20, height: 20)
        let preferred = CGRect(x: -2, y: -12, width: 4, height: 4)
        let cases = [
            [CGRect(x: -1, y: -12, width: 3, height: 4), CGRect(x: -5, y: -8, width: 11, height: 2), CGRect(x: -7, y: -16, width: 3, height: 12)],
            [CGRect(x: -10, y: -20, width: 10, height: 9), CGRect(x: 4, y: -15, width: 6, height: 15)],
            [CGRect(x: -6, y: -16, width: 12, height: 12)],
            []]
        for controls in cases {
            let result = try #require(PanelCoexistenceGeometry.fullscreenPanel(preferred: preferred, avoiding: controls,
                                                                              visibleFrame: area, gap: 0, maximumDisplacement: 40, heightFraction: 1))
            let brute = (-10...6).flatMap { x in (-20 ... -4).map { y in CGRect(x: x, y: y, width: 4, height: 4) } }
                .filter { frame in !controls.contains(where: { intersectsArea(frame, $0) }) }
                .map { hypot($0.minX - preferred.minX, $0.minY - preferred.minY) }.min()
            #expect(hypot(result.minX - preferred.minX, result.minY - preferred.minY) == brute)
        }
    }

    @Test func exactContactBetweenControlsLeavesAValidSingleOrigin() {
        let area = CGRect(x: 0, y: 0, width: 100, height: 100)
        let preferred = CGRect(x: 40, y: 40, width: 20, height: 20)
        let controls = [CGRect(x: 0, y: 0, width: 100, height: 40), CGRect(x: 0, y: 60, width: 100, height: 40)]
        #expect(PanelCoexistenceGeometry.fullscreenPanel(preferred: preferred, avoiding: controls,
                                                        visibleFrame: area, gap: 0) == preferred)
    }

    @Test func noFitAndBoundedDisplacementNeverTeleportOrShrinkPanel() {
        let area = CGRect(x: 0, y: 0, width: 1000, height: 1000)
        let preferred = CGRect(x: 450, y: 450, width: 100, height: 100)
        #expect(PanelCoexistenceGeometry.fullscreenPanel(preferred: preferred, avoiding: [area], visibleFrame: area) == nil)
        let atLimit = CGRect(x: 310, y: 0, width: 690, height: 1000)
        #expect(PanelCoexistenceGeometry.fullscreenPanel(preferred: preferred, avoiding: [atLimit], visibleFrame: area, gap: 0)?.minX == 210)
        let beyond = CGRect(x: 309, y: 0, width: 691, height: 1000)
        #expect(PanelCoexistenceGeometry.fullscreenPanel(preferred: preferred, avoiding: [beyond], visibleFrame: area, gap: 0) == nil)
        #expect(PanelCoexistenceGeometry.fullscreenPanel(preferred: preferred, avoiding: [atLimit], visibleFrame: area, gap: 0, heightFraction: 0.2) == nil)
        #expect(PanelCoexistenceGeometry.fullscreenPanel(preferred: preferred.offsetBy(dx: 2000, dy: 0), avoiding: [], visibleFrame: area) == nil)
        #expect(PanelCoexistenceGeometry.fullscreenPanel(preferred: area.insetBy(dx: -1, dy: 0), avoiding: [], visibleFrame: area) == nil)
    }

    @Test func safeCurrentPlacementAbsorbsSmallJitterWithoutCumulativeDrift() throws {
        let area = CGRect(x: 0, y: 0, width: 1000, height: 1000)
        let preferred = CGRect(x: 450, y: 450, width: 100, height: 100)
        let control = CGRect(x: 500, y: 450, width: 60, height: 100)
        let initial = try #require(PanelCoexistenceGeometry.fullscreenPanel(preferred: preferred, avoiding: [control], visibleFrame: area))
        for delta: CGFloat in [2, 4, 6, 4, 2, 0] {
            #expect(PanelCoexistenceGeometry.fullscreenPanel(preferred: preferred, current: initial,
                                                            avoiding: [control.offsetBy(dx: delta, dy: 0)], visibleFrame: area) == initial)
        }
        let unsafe = try #require(PanelCoexistenceGeometry.fullscreenPanel(preferred: preferred, current: initial,
                                                                          avoiding: [control.offsetBy(dx: -10, dy: 0)], visibleFrame: area))
        #expect(unsafe.minX == 382)
        let farCurrent = initial.offsetBy(dx: -300, dy: 0)
        #expect(PanelCoexistenceGeometry.fullscreenPanel(preferred: preferred, current: farCurrent, avoiding: [control], visibleFrame: area) == initial)
    }

    @Test func invalidBoundsParametersAndNaNFailWithoutMakingUnsafeFrames() {
        let invalid = [CGRect.zero, CGRect.null, CGRect.infinite,
                       CGRect(x: CGFloat.nan, y: 0, width: 10, height: 10),
                       CGRect(x: 0, y: 0, width: -10, height: 10)]
        for rect in invalid {
            #expect(PanelCoexistenceGeometry.ordinaryWindow(rect, excluding: panel, visibleFrame: screen) == nil)
            #expect(PanelCoexistenceGeometry.ordinaryWindow(panel, excluding: rect, visibleFrame: screen) == nil)
            #expect(PanelCoexistenceGeometry.fullscreenPanel(preferred: panel, avoiding: [rect], visibleFrame: screen) == nil)
            #expect(PanelCoexistenceGeometry.fullscreenPanel(preferred: panel, avoiding: [], visibleFrame: rect) == nil)
        }
        #expect(PanelCoexistenceGeometry.ordinaryWindow(panel, excluding: panel, visibleFrame: screen, gap: .nan) == nil)
        #expect(PanelCoexistenceGeometry.ordinaryWindow(panel, excluding: panel, visibleFrame: screen, minimumSize: .zero) == nil)
        #expect(PanelCoexistenceGeometry.fullscreenPanel(preferred: panel, avoiding: [], visibleFrame: screen, maximumDisplacement: -.infinity) == nil)
        #expect(PanelCoexistenceGeometry.fullscreenPanel(preferred: panel, avoiding: [], visibleFrame: screen, heightFraction: .nan) == nil)
        #expect(PanelCoexistenceGeometry.fullscreenPanel(preferred: panel, avoiding: [], visibleFrame: screen, hysteresis: -1) == nil)
    }

    private func intersectsArea(_ a: CGRect, _ b: CGRect) -> Bool {
        a.minX < b.maxX && b.minX < a.maxX && a.minY < b.maxY && b.minY < a.maxY
    }
}
