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
    init(_ kind: String, images: URL?) throws {
        self.kind = kind
        self.images = images
        // Deliberately short, distinct rows. Offsets and passage identity are
        // stable across overlapping SQLite-style windows, even after a reflow.
        let syllables = Array("听风海云山湖春秋夜雨星光青松红梅白鹭南北东西丘原江河林田")
        rows = (0..<272).map { i in
            let a = String(syllables[i % syllables.count]), b = String(syllables[(i / syllables.count) % syllables.count])
            return Row(id: UUID(), position: Int64(i + 1), displayText: i.isMultiple(of: 5) ? a : a + b + (i.isMultiple(of: 3) ? "。" : ""))
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
    func apply(delta: Int32, precise: Bool, phase: Int64 = 0, momentum: Int64 = 0) async throws {
        step += 1
        let before = snapshot()
        guard let cg = CGEvent(scrollWheelEvent2Source: nil, units: precise ? .pixel : .line, wheelCount: 1, wheel1: delta, wheel2: 0, wheel3: 0) else { throw ProbeError.event }
        cg.setIntegerValueField(.scrollWheelEventScrollPhase, value: phase)
        cg.setIntegerValueField(.scrollWheelEventMomentumPhase, value: momentum)
        cg.setIntegerValueField(.scrollWheelEventIsContinuous, value: precise ? 1 : 0)
        guard let e = NSEvent(cgEvent: cg), e.hasPreciseScrollingDeltas == precise else { throw ProbeError.event }
        scroll.scrollWheel(with: e) // point-to-point only; never post system input
        try await Task.sleep(for: .milliseconds(17))
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
    func run() async throws -> [String: Any] {
        defer { window.orderOut(nil); window.close() }
        try await Task.sleep(for: .milliseconds(150))
        guard window.isVisible && !window.isKeyWindow && !snapshot().glyphY.isEmpty else { throw ProbeError.window }
        try await gesture(1, events: 89); try await gesture(-1, events: 79)
        try await Task.sleep(for: .milliseconds(80))
        try fulfill()
        return ["input": kind, "oldestStart": oldestStart, "finalStart": start, "initialStart": rows.count-capacity,
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
            for type in ["wheel", "precise"] { results.append(try await Probe(type, images: images).run()) }
            let report: [String: Any] = ["source": CommandLine.arguments[1], "cases": results]
            try JSONSerialization.data(withJSONObject: report, options: [.sortedKeys]).write(to: URL(fileURLWithPath: CommandLine.arguments[2]))
        } catch { print("reader-motion failure: \(error)"); exit(2) }
    }
}
