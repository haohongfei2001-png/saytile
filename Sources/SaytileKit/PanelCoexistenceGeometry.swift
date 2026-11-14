import Foundation
import CoreGraphics

public enum PanelPlacementMode: String, Codable, CaseIterable, Sendable {
    case floating
    case boundary
}

/// Pure geometry in one display's macOS logical coordinates. Callers own AX access,
/// screen selection and saved user placements. A nil result never authorizes a move.
public enum PanelCoexistenceGeometry {
    /// Keep the ordinary window's size whenever a translation can avoid the panel.
    /// Otherwise retain the largest possible area, then minimize the translation.
    /// Existing small windows are never enlarged; a resized axis cannot shrink below
    /// the lesser of its original extent and minimumSize.
    public static func ordinaryWindow(
        _ window: CGRect, excluding panel: CGRect, visibleFrame: CGRect,
        gap: CGFloat = 8, minimumSize: CGSize = CGSize(width: 320, height: 180)
    ) -> CGRect? {
        guard valid(window), valid(panel), valid(visibleFrame), valid(minimumSize),
              gap.isFinite, gap >= 0, let obstacle = expanded(panel, by: gap) else { return nil }
        let areas = freeAreas(in: visibleFrame, excluding: obstacle)
        let originalSize = window.size
        let translations = areas.compactMap { fitted(originalSize, near: window.origin, in: $0) }
        if let nearest = closest(translations, to: window.origin) { return nearest }

        let floor = CGSize(width: min(originalSize.width, minimumSize.width),
                           height: min(originalSize.height, minimumSize.height))
        var best: CGRect?
        for area in areas {
            let size = CGSize(width: min(originalSize.width, area.width),
                              height: min(originalSize.height, area.height))
            guard size.width >= floor.width, size.height >= floor.height,
                  let candidate = fitted(size, near: window.origin, in: area) else { continue }
            // Compare retained fractions rather than huge raw areas that can overflow.
            let retained = (size.width / originalSize.width) * (size.height / originalSize.height)
            let previous = best.map { ($0.width / originalSize.width) * ($0.height / originalSize.height) } ?? -1
            if retained > previous || (retained == previous && distance(candidate.origin, window.origin) < distance(best!.origin, window.origin)) {
                best = candidate
            }
        }
        return best
    }

    /// Translate, never resize, a full-screen panel away from known control bounds.
    /// The radius is always measured from preferred, not the last temporary frame.
    /// A still-safe current placement may stay within hysteresis points of the optimal
    /// distance, avoiding direction flips from tiny AX-bound changes. No placement is
    /// returned when the panel cannot fit within the bounded neighborhood.
    public static func fullscreenPanel(
        preferred: CGRect, current: CGRect? = nil, avoiding controls: [CGRect],
        visibleFrame: CGRect, gap: CGFloat = 8, maximumDisplacement: CGFloat = 240,
        heightFraction: CGFloat = 0.35, hysteresis: CGFloat = 8
    ) -> CGRect? {
        guard valid(preferred), valid(visibleFrame), controls.allSatisfy(valid),
              gap.isFinite, gap >= 0, maximumDisplacement.isFinite, maximumDisplacement >= 0,
              heightFraction.isFinite, heightFraction >= 0, heightFraction <= 1,
              hysteresis.isFinite, hysteresis >= 0,
              preferred.width <= visibleFrame.width, preferred.height <= visibleFrame.height else { return nil }
        let limit = min(maximumDisplacement, visibleFrame.height * heightFraction)
        let expandedControls = controls.compactMap { expanded($0, by: gap) }
        guard expandedControls.count == controls.count else { return nil }
        let obstacles = expandedControls.filter { overlaps($0, visibleFrame) }
        let xs = visibleFrame.minX...(visibleFrame.maxX - preferred.width)
        let ys = visibleFrame.minY...(visibleFrame.maxY - preferred.height)
        let xValues = Set([clamp(preferred.minX, to: xs), xs.lowerBound, xs.upperBound]
            + obstacles.flatMap { [$0.minX - preferred.width, $0.maxX] })
            .filter { $0.isFinite && xs.contains($0) }.sorted()
        var candidates: [CGRect] = []
        // For each critical x, union the forbidden open y intervals. This avoids
        // cubic enumeration of every x/y/control combination in dense toolbars.
        for x in xValues {
            let intervals = obstacles.filter { x < $0.maxX && x + preferred.width > $0.minX }
                .map { ($0.minY - preferred.height, $0.maxY) }
            guard let y = nearestFreeY(to: preferred.minY, within: ys, excluding: intervals) else { continue }
            let candidate = CGRect(x: x, y: y, width: preferred.width, height: preferred.height)
            if distance(candidate.origin, preferred.origin) <= limit { candidates.append(candidate) }
        }
        guard let best = closest(candidates, to: preferred.origin) else { return nil }
        if let current, valid(current), current.size == preferred.size,
           visibleFrame.contains(current), !obstacles.contains(where: { overlaps(current, $0) }),
           distance(current.origin, preferred.origin) <= limit,
           distance(current.origin, preferred.origin) <= distance(best.origin, preferred.origin) + hysteresis {
            return current
        }
        return best
    }

    private static func nearestFreeY(to preferred: CGFloat, within bounds: ClosedRange<CGFloat>,
                                     excluding intervals: [(CGFloat, CGFloat)]) -> CGFloat? {
        let sorted = intervals.sorted { $0.0 == $1.0 ? $0.1 < $1.1 : $0.0 < $1.0 }
        var merged: [(CGFloat, CGFloat)] = []
        for interval in sorted {
            if let last = merged.last, interval.0 < last.1 {
                merged[merged.count - 1].1 = max(last.1, interval.1)
            } else { merged.append(interval) }
        }
        let y = clamp(preferred, to: bounds)
        guard let blocked = merged.first(where: { $0.0 < y && y < $0.1 }) else { return y }
        return [blocked.0, blocked.1].filter { $0.isFinite && bounds.contains($0) }
            .min { abs($0 - preferred) < abs($1 - preferred) }
    }

    private static func freeAreas(in visible: CGRect, excluding obstacle: CGRect) -> [CGRect] {
        guard overlaps(visible, obstacle) else { return [visible] }
        let left = min(visible.maxX, max(visible.minX, obstacle.minX))
        let right = max(visible.minX, min(visible.maxX, obstacle.maxX))
        let below = min(visible.maxY, max(visible.minY, obstacle.minY))
        let above = max(visible.minY, min(visible.maxY, obstacle.maxY))
        return [CGRect(x: visible.minX, y: visible.minY, width: left - visible.minX, height: visible.height),
                CGRect(x: right, y: visible.minY, width: visible.maxX - right, height: visible.height),
                CGRect(x: visible.minX, y: visible.minY, width: visible.width, height: below - visible.minY),
                CGRect(x: visible.minX, y: above, width: visible.width, height: visible.maxY - above)]
            .filter(valid)
    }

    private static func fitted(_ size: CGSize, near point: CGPoint, in area: CGRect) -> CGRect? {
        guard size.width <= area.width, size.height <= area.height else { return nil }
        return CGRect(x: clamp(point.x, to: area.minX...(area.maxX - size.width)),
                      y: clamp(point.y, to: area.minY...(area.maxY - size.height)),
                      width: size.width, height: size.height)
    }

    private static func closest(_ frames: [CGRect], to point: CGPoint) -> CGRect? {
        frames.min { distance($0.origin, point) < distance($1.origin, point) }
    }
    private static func clamp(_ value: CGFloat, to range: ClosedRange<CGFloat>) -> CGFloat {
        min(max(value, range.lowerBound), range.upperBound)
    }
    private static func distance(_ a: CGPoint, _ b: CGPoint) -> CGFloat { hypot(a.x - b.x, a.y - b.y) }
    private static func overlaps(_ a: CGRect, _ b: CGRect) -> Bool {
        a.minX < b.maxX && b.minX < a.maxX && a.minY < b.maxY && b.minY < a.maxY
    }
    private static func expanded(_ rect: CGRect, by gap: CGFloat) -> CGRect? {
        let result = rect.insetBy(dx: -gap, dy: -gap)
        return valid(result) ? result : nil
    }
    private static func valid(_ size: CGSize) -> Bool {
        size.width.isFinite && size.height.isFinite && size.width > 0 && size.height > 0
    }
    private static func valid(_ rect: CGRect) -> Bool {
        !rect.isNull && !rect.isInfinite && valid(rect.size)
            && [rect.origin.x, rect.origin.y, rect.maxX, rect.maxY].allSatisfy(\.isFinite)
    }
}
