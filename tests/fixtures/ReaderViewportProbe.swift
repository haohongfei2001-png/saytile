import AppKit
import CoreGraphics

private struct CaptureFailure: Error {}

private struct Row: VoiceTranscriptEntry {
    let id: UUID
    let position: Int64
    var displayText: String
}
private enum ProbeError: Error { case args, event, window }
private struct Key: Hashable { let row: Int64; let offset: Int }
private struct Visible {
    let glyphY: [Key: CGFloat]
    let glyphX: [Key: CGFloat]
    let lineHeight: CGFloat
    let origin: CGFloat
    let height: CGFloat
}

@MainActor private final class Probe {
    let scroll: CompactTranscriptScrollView<Row>
    let window: NSPanel
    let rows: [Row]
    let capacity = 64
    var start: Int
    var pageChanges = [[String: Any]](), motions = [[String: Any]](), revisions = [[String: Any]]()
    var pending: Bool?
    var seenOrigins = Set<Int>()
    var oldestStart: Int
    var everKey = false
    var step = 0
    let kind: String
    let images: URL?
    let profile: String
    init(_ kind: String, profile: String = "dense-zh", images: URL?) throws {
        self.kind = kind
        self.images = images
        self.profile = profile
        // Deliberately short, distinct rows. Offsets and passage identity are
        // stable across overlapping SQLite-style windows, even after a reflow.
        let syllables = Array("听风海云山湖春秋夜雨星光青松红梅白鹭南北东西丘原江河林田")
        rows = (0..<272).map { i in
            let a = String(syllables[i % syllables.count]), b = String(syllables[(i / syllables.count) % syllables.count])
            let mixed = ["Saytile", a + b, "9.5", "，", "试🙂", "A/B", a + b + "。", "🌗", "42%", "AA", "👩🏽‍💻", a + "\n" + b]
            let text = profile == "mixed-authored" ? mixed[i % mixed.count] : (i.isMultiple(of: 5) ? a : a + b + (i.isMultiple(of: 3) ? "。" : ""))
            return Row(id: UUID(), position: Int64(i + 1), displayText: text)
        }
        start = rows.count - capacity
        oldestStart = start
        let box = NSRect(x: 0, y: 0, width: 154.5, height: 65)
        scroll = .init(frame: box)
        window = NSPanel(contentRect: box, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.hidesOnDeactivate = false
        window.ignoresMouseEvents = true
        window.contentView = scroll
        if let frame = NSScreen.main?.visibleFrame { window.setFrameOrigin(frame.origin) }
        window.orderBack(nil)
        scroll.applyTypeScale(0.72)
        scroll.onPage = { [weak self] older in self?.pending = older }
        publish()
        window.contentView?.layoutSubtreeIfNeeded()
        scroll.jumpToLatest()
    }
    func publish(changeLast: Bool = false) {
        var slice = Array(rows[start..<min(rows.count, start + capacity)])
        if changeLast { slice[slice.count - 1].displayText += "修订" }
        scroll.updateDocument(.init(entries: slice, older: start > 0, newer: start + capacity < rows.count))
    }
    func snapshot() -> Visible {
        window.displayIfNeeded()
        everKey = everKey || window.isKeyWindow
        let editor = scroll.transcriptView
        let view = editor.visibleRect
        var yy = [Key: CGFloat](), xx = [Key: CGFloat](), lh: CGFloat = 0
        if let manager = editor.layoutManager, let container = editor.textContainer {
            let local = view.offsetBy(dx: -editor.textContainerOrigin.x, dy: -editor.textContainerOrigin.y)
            let glyphs = manager.glyphRange(forBoundingRect: local, in: container)
            for g in glyphs.location..<NSMaxRange(glyphs) {
                let character = manager.characterIndexForGlyph(at: g)
                guard let span = scroll.rendered.spans.first(where: { NSLocationInRange(character, $0.range) }) else { continue }
                let line = manager.lineFragmentRect(forGlyphAt: g, effectiveRange: nil)
                let rect = manager.boundingRect(forGlyphRange: NSRange(location: g, length: 1), in: container)
                let y = line.midY + editor.textContainerOrigin.y - view.minY
                // Omit partial lines so an extreme glyph sliver cannot count as a preserved viewport.
                guard y >= 0 && y < view.height else { continue }
                let key = Key(row: span.entry.position, offset: character - span.range.location)
                yy[key] = y; xx[key] = rect.minX + editor.textContainerOrigin.x - view.minX; lh = line.height
            }
        }
        return Visible(glyphY: yy, glyphX: xx, lineHeight: lh, origin: view.minY, height: view.height)
    }
    static func delta(_ a: Visible, _ b: Visible) -> [String: Any] {
        let common = a.glyphY.keys.filter { b.glyphY[$0] != nil }
        let dy = common.map { b.glyphY[$0]! - a.glyphY[$0]! }.sorted()
        let dx = common.map { abs(b.glyphX[$0]! - a.glyphX[$0]!) }.sorted()
        return ["beforeFirst": a.glyphY.keys.map(\.row).min() as Any? ?? NSNull(), "afterFirst": b.glyphY.keys.map(\.row).min() as Any? ?? NSNull(),
                "beforeGlyphs": a.glyphY.count, "afterGlyphs": b.glyphY.count, "common": common.count,
                "medianDY": dy.isEmpty ? NSNull() as Any : dy[dy.count / 2] as Any, "maxAbsDY": dy.map(abs).max() as Any? ?? NSNull(),
                "medianAbsDX": dx.isEmpty ? NSNull() as Any : dx[dx.count / 2] as Any,
                "originBefore": a.origin, "originAfter": b.origin, "lineHeight": a.lineHeight, "height": a.height]
    }
    static func unexpected(_ a: Visible, _ b: Visible, expected: CGFloat) -> CGFloat? {
        a.glyphY.compactMap { key, y in b.glyphY[key].map { abs($0 - y - expected) } }.max()
    }
    func image(_ label: String) throws {
        guard let images else { return }
        let editor = scroll.transcriptView, rect = editor.visibleRect
        guard let bitmap = editor.bitmapImageRepForCachingDisplay(in: rect) else { throw CaptureFailure() }
        editor.cacheDisplay(in: rect, to: bitmap)
        guard let image = bitmap.cgImage, let context = CGContext(data: nil, width: image.width, height: image.height,
                bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { throw CaptureFailure() }
        let bounds = CGRect(x: 0, y: 0, width: image.width, height: image.height)
        context.setFillColor(NSColor.white.cgColor); context.fill(bounds); context.draw(image, in: bounds)
        guard let opaque = context.makeImage(), let png = NSBitmapImageRep(cgImage: opaque).representation(using: .png, properties: [:]) else { throw CaptureFailure() }
        try png.write(to: images.appendingPathComponent("reader-" + kind + "-" + label + ".png"))
    }
    func fulfill(expectedScreenShift: CGFloat = 0) throws {
        guard let older = pending else { return }
        pending = nil
        let capture = pageChanges.isEmpty && images != nil
        let before = snapshot(), old = start
        if capture { try image("before") }
        let pivot = start + min(capacity, rows.count - start) / 2
        start = older ? max(0, pivot + 1 - capacity) : min(rows.count - capacity, pivot)
        guard start != old else { return }
        publish()
        let after = snapshot()
        if capture { try image("after") }
        var record = Self.delta(before, after)
        record["expectedScreenShift"] = expectedScreenShift
        record["maxUnexpectedDY"] = Self.unexpected(before, after, expected: expectedScreenShift) as Any? ?? NSNull()
        record["step"] = step; record["older"] = older; record["from"] = old; record["to"] = start
        pageChanges.append(record)
        oldestStart = min(oldestStart, start)
    }
    func dispatch(delta: Int32, precise: Bool, phase: Int64 = 0, momentum: Int64 = 0) throws -> NSEvent {
        guard let cg = CGEvent(scrollWheelEvent2Source: nil, units: precise ? .pixel : .line, wheelCount: 1, wheel1: delta, wheel2: 0, wheel3: 0) else { throw ProbeError.event }
        cg.setIntegerValueField(.scrollWheelEventScrollPhase, value: phase)
        cg.setIntegerValueField(.scrollWheelEventMomentumPhase, value: momentum)
        cg.setIntegerValueField(.scrollWheelEventIsContinuous, value: precise ? 1 : 0)
        guard let e = NSEvent(cgEvent: cg), e.hasPreciseScrollingDeltas == precise else { throw ProbeError.event }
        scroll.scrollWheel(with: e) // point-to-point only; never post system input
        return e
    }
    func apply(delta: Int32, precise: Bool, phase: Int64 = 0, momentum: Int64 = 0) async throws {
        step += 1
        let before = snapshot()
        let e = try dispatch(delta: delta, precise: precise, phase: phase, momentum: momentum)
        // Single-notch endpoint contract. The separate burst probe issues a new
        // mechanical detent every 18 ms, long before the 90 ms response settles.
        if precise {
            try await Task.sleep(for: .milliseconds(17))
        } else {
            let cap = max(1, scroll.contentSize.height / 2)
            let distance = min(cap, max(-cap, e.scrollingDeltaY * scroll.verticalLineScroll))
            let limit = max(0, scroll.transcriptView.bounds.height - scroll.contentSize.height)
            let end = min(limit, max(0, before.origin-distance))
            let deadline = ProcessInfo.processInfo.systemUptime + 0.18
            repeat {
                try await Task.sleep(for: .milliseconds(6))
                // Allow the final sub-pixel remainder to reach a page edge even
                // when the physical clip can move no further.
                if abs(scroll.contentView.bounds.minY-end) < 0.001, end > 0, end < limit { break }
            } while ProcessInfo.processInfo.systemUptime < deadline
        }
        // The host read reaches the product view on a later turn. Observe the
        // actual same glyph before and after replacement, without wheel travel.
        let beforePage = snapshot()
        let cap = max(1, scroll.contentSize.height / 2)
        let intended = precise ? e.scrollingDeltaY : min(cap, max(-cap, e.scrollingDeltaY * scroll.verticalLineScroll))
        let consumed = before.origin - beforePage.origin
        let residual = intended >= 0 ? max(0, intended - consumed) : min(0, intended - consumed)
        try fulfill(expectedScreenShift: residual)
        let after = snapshot()
        var m = Self.delta(before, after)
        m["intended"] = intended; m["beforeSwapTravel"] = consumed
        m["step"] = step; m["delta"] = e.scrollingDeltaY; m["phase"] = e.phase.rawValue; m["momentum"] = e.momentumPhase.rawValue
        motions.append(m)
        if let first = after.glyphY.keys.map(\.row).min() { seenOrigins.insert(Int(first)) }
        if step == 15 || step == 51 {
            let r = snapshot(); publish(changeLast: true)
            revisions.append(Self.delta(r, snapshot()))
        }
    }
    func gesture(_ sign: Int32, events: Int) async throws {
        if kind == "wheel" {
            for _ in 0..<events { try await apply(delta: sign, precise: false) }
        } else {
            try await apply(delta: sign * 4, precise: true, phase: 1)
            for _ in 0..<events { try await apply(delta: sign * 9, precise: true, phase: 2) }
            try await apply(delta: 0, precise: true, phase: 4)
            try await apply(delta: sign * 8, precise: true, momentum: 1)
            for speed: Int32 in [7,5,3,2,1] { try await apply(delta: sign * speed, precise: true, momentum: 2) }
            try await apply(delta: 0, precise: true, momentum: 3)
        }
    }
    func continuousWheel() async throws -> [String: Any] {
        // Measure a fixed, settling wheel movement on an ordinary line, then
        // continuously traverse pages. Compare actual travel from overlapping
        // *visible glyphs*, not the clip origin which changes on pagination.
        let begin = rows.count - capacity
        start = begin; pending = nil; publish(); scroll.jumpToLatest()
        let maxY = scroll.transcriptView.bounds.height - scroll.contentSize.height
        scroll.contentView.scroll(to: .init(x: 0, y: maxY / 2)); scroll.reflectScrolledClipView(scroll.contentView)
        try await Task.sleep(for: .milliseconds(50))
        let three = min(scroll.contentSize.height / 2, 3 * scroll.verticalLineScroll)
        let first = snapshot().origin
        _ = try dispatch(delta: 3, precise: false)
        var single = [Double](), last = first
        let t = ProcessInfo.processInfo.systemUptime
        while ProcessInfo.processInfo.systemUptime - t < 0.19 {
            let current = snapshot().origin
            if abs(current-last) > 0.0001 { single.append(first-current); last = current }
            try await Task.sleep(for: .milliseconds(5))
        }
        let settledSingle = snapshot().origin
        try await Task.sleep(for: .milliseconds(100))
        let drift = abs(snapshot().origin - settledSingle)
        let singleTotal = first - settledSingle
        // Start on the latest page, well above the lower boundary, with ample
        // history ahead of an uninterrupted scroll. No global endpoint clips it.
        scroll.jumpToLatest(); pending = nil
        var previous = snapshot(), sum = 0.0, maxDX = 0.0, maxSpread = 0.0, misses = 0
        var pageSteps = [[String:Any]](), frameY = [Double]()
        func observe(_ next: Visible) {
            let d = Self.delta(previous, next)
            if let dy = d["medianDY"] as? CGFloat {
                sum += dy
                if abs(dy) > 0.001 { frameY.append(dy) }
                maxDX = max(maxDX, d["medianAbsDX"] as? CGFloat ?? 0)
                maxSpread = max(maxSpread, Self.unexpected(previous, next, expected: dy) ?? 0)
            } else { misses += 1 }
            previous = next
        }
        let count = 18
        for _ in 0..<count {
            _ = try dispatch(delta: 3, precise: false)
            for _ in 0..<3 {
                try await Task.sleep(for: .milliseconds(6))
                observe(snapshot())
                if pending != nil {
                    let oldCount = pageChanges.count
                    try fulfill(); observe(snapshot())
                    if pageChanges.count > oldCount { pageSteps.append(pageChanges.removeLast()) }
                }
            }
        }
        let finish = ProcessInfo.processInfo.systemUptime + 0.19
        while ProcessInfo.processInfo.systemUptime < finish {
            try await Task.sleep(for: .milliseconds(6)); observe(snapshot())
            if pending != nil {
                let oldCount = pageChanges.count
                try fulfill(); observe(snapshot())
                if pageChanges.count > oldCount { pageSteps.append(pageChanges.removeLast()) }
            }
        }
        let total = sum
        try await Task.sleep(for: .milliseconds(100)); observe(snapshot())
        let longDrift = abs(sum-total)
        // A reversal discards only the unfinished movement in the old direction.
        // The new notch starts at the last *visible* point and must land 30 pt back.
        start = begin; pending = nil; publish(); scroll.jumpToLatest()
        scroll.contentView.scroll(to: .init(x: 0, y: maxY / 2)); scroll.reflectScrolledClipView(scroll.contentView)
        try await Task.sleep(for: .milliseconds(40))
        _ = try dispatch(delta: 3, precise: false)
        try await Task.sleep(for: .milliseconds(25))
        let reversal = snapshot().origin
        _ = try dispatch(delta: -3, precise: false)
        var opposite = 0.0
        for _ in 0..<32 {
            try await Task.sleep(for: .milliseconds(5))
            opposite = max(opposite, reversal - snapshot().origin)
        }
        let reversedTotal = snapshot().origin - reversal
        return ["threeNotchPoints": three, "singleChanges": single, "singleTravel": singleTotal, "singleDrift": drift,
                "burstDetents": count, "burstTravel": total, "burstExpected": three * Double(count), "burstSwaps": pageSteps,
                "burstMoves": frameY, "burstMissingGlyphs": misses, "burstMaxMedianDX": maxDX, "burstMaxNonrigidDY": maxSpread,
                "burstStopDrift": longDrift, "reversedTravel": reversedTotal, "staleDirectionAfterReversal": opposite]
    }
    func globalEdge(older: Bool) async throws -> [String: Any] {
        start = older ? 0 : rows.count - capacity
        pending = nil
        publish()
        scroll.jumpToLatest()
        if older { scroll.contentView.scroll(to: .zero); scroll.reflectScrolledClipView(scroll.contentView) }
        try await Task.sleep(for: .milliseconds(40))
        let original = snapshot(), oldCount = pageChanges.count
        for _ in 0..<3 { try await apply(delta: older ? 1 : -1, precise: kind == "precise", phase: kind == "precise" ? 2 : 0) }
        try await Task.sleep(for: .milliseconds(40))
        var record = Self.delta(original, snapshot()); record["older"] = older
        record["pageRequests"] = pageChanges.count - oldCount
        return record
    }
    func run() async throws -> [String: Any] {
        defer { window.orderOut(nil); window.close() }
        try await Task.sleep(for: .milliseconds(150))
        guard window.isVisible && !window.isKeyWindow && !snapshot().glyphY.isEmpty else { throw ProbeError.window }
        try await gesture(1, events: profile == "mixed-authored" ? 210 : 89); try await gesture(-1, events: profile == "mixed-authored" ? 195 : 79)
        try await Task.sleep(for: .milliseconds(80))
        try fulfill()
        let gestureFinalStart = start
        let limits = [try await globalEdge(older: true), try await globalEdge(older: false)]
        let burst = kind == "wheel" && images == nil ? try await continuousWheel() : [:]
        return ["input": kind, "profile": profile, "globalEnds": limits, "mechanicalBurst": burst, "oldestStart": oldestStart, "finalStart": gestureFinalStart, "initialStart": rows.count-capacity,
                "everKey": everKey, "distinctVisibleFirstRows": seenOrigins.count, "pageChanges": pageChanges, "steps": motions, "lateRevisions": revisions]
    }
}
@main private struct ReaderViewportProbe {
    @MainActor static func main() async {
        do {
            guard (3...4).contains(CommandLine.arguments.count) else { throw ProbeError.args }
            NSApplication.shared.setActivationPolicy(.prohibited)
            NSApplication.shared.finishLaunching()
            var results = [[String: Any]]()
            let images = CommandLine.arguments.count == 4 ? URL(fileURLWithPath: CommandLine.arguments[3]) : nil
            for profile in ["dense-zh", "mixed-authored"] {
                for type in ["wheel", "precise"] { results.append(try await Probe(type, profile: profile, images: profile == "dense-zh" ? images : nil).run()) }
                if images != nil { break } // the extra run captures only the Chinese boundary
            }
            let report: [String: Any] = ["source": CommandLine.arguments[1], "cases": results]
            try JSONSerialization.data(withJSONObject: report, options: [.sortedKeys]).write(to: URL(fileURLWithPath: CommandLine.arguments[2]))
        } catch { print("reader-motion failure: \(error)"); exit(2) }
    }
}
