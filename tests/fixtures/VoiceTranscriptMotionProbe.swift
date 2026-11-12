import AppKit
import ImageIO
import UniformTypeIdentifiers
import SwiftUI

// Runs the actual shared SwiftUI panel in its own nonactivating NSPanel. All input
// is an explicit replay; it never opens a microphone, a database or another window.
private struct Row: VoiceTranscriptEntry {
    let id: UUID
    let position: Int64
    var displayText: String
}

private struct ReplayEvent: Codable {
    let ms: Double
    let text: String
    let final: Bool
}

private struct Scenario: Codable {
    let name: String
    let events: [ReplayEvent]
}

@MainActor private final class Replay: ObservableObject {
    let access = PanelTranscriptAccess<Row>()
    let history = Row(id: UUID(), position: 1, displayText: String(repeating: "请保留这份历史记录。", count: 8))
    var live = Row(id: UUID(), position: 2, displayText: "")
    @Published var document = PanelTimelineDocument<Row>()
    private(set) var edits: [VoicePanelEdit] = []

    func publish(_ text: String, final: Bool) {
        live.displayText = text
        var next = PanelTimelineDocument(entries: [history, live])
        #if SAYTILE_HAS_LIVE_TAIL
        next.liveTailID = final ? nil : live.id
        #endif
        document = next
    }

    func apply(_ changes: [VoicePanelEdit]) throws -> PanelTimelineDocument<Row> {
        guard let change = changes.first, changes.count == 1,
              change.id == live.id, change.before == live.displayText else {
            throw Failure.invalidEdit
        }
        edits += changes
        publish(change.after, final: true)
        return document
    }
}

private struct Surface: View {
    @ObservedObject var replay: Replay
    var body: some View {
        VoiceSurfacePanel(document: replay.document, access: replay.access,
            capture: .init(state: .recognizing, level: 0.25, actionLabel: "暂停", accessibilityValue: "识别中"),
            canCopy: true, selectedText: "", onCopy: {}, onToggle: {}, applyEdits: replay.apply) { EmptyView() }
    }
}

private enum Failure: Error { case arguments, setup, invalidEdit }

@main private struct VoiceTranscriptMotionProbe {
    @MainActor static func main() async {
        do {
            let args = CommandLine.arguments
            guard (4...5).contains(args.count) else { throw Failure.arguments }
            let scenarios = try JSONDecoder().decode([Scenario].self, from: Data(contentsOf: URL(fileURLWithPath: args[1])))
            NSApplication.shared.setActivationPolicy(.prohibited)
            NSApplication.shared.finishLaunching()
            var results = [[String: Any]]()
            for scenario in scenarios {
                results.append(try await measure(scenario, gif: args.count == 5 ? URL(fileURLWithPath: args[4]) : nil))
            }
            let report: [String: Any] = ["sourceSHA": args[3], "clock": "systemUptime", "evidenceLayer": "native shared VoiceSurfacePanel; replayed host documents, isolated pasteboard", "scenarios": results]
            try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]).write(to: URL(fileURLWithPath: args[2]))
        } catch { print("Motion probe failed: \(error)"); exit(2) }
    }

    @MainActor private static func measure(_ scenario: Scenario, gif: URL?) async throws -> [String: Any] {
        guard let first = scenario.events.first, let final = scenario.events.last, final.final, !first.text.isEmpty,
              zip(scenario.events, scenario.events.dropFirst()).allSatisfy({ $0.ms < $1.ms }) else { throw Failure.arguments }
        let replay = Replay()
        replay.publish("", final: true)
        let box = NSRect(x: 0, y: 0, width: 167, height: 98)
        let panel = NSPanel(contentRect: box, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.ignoresMouseEvents = true
        let host = NSHostingView(rootView: Surface(replay: replay))
        panel.contentView = host
        if let frame = NSScreen.main?.visibleFrame { panel.setFrameOrigin(NSPoint(x: frame.minX, y: frame.minY)) }
        panel.orderBack(nil)
        defer { panel.orderOut(nil); panel.close() }
        try await Task.sleep(for: .milliseconds(230))
        guard let scroll = replay.access.view, panel.isVisible, !panel.isKeyWindow else { throw Failure.setup }
        let editor = scroll.transcriptView
        scroll.jumpToLatest()
        try await Task.sleep(for: .milliseconds(90))
        let seed = replay.history.displayText
        guard editor.string == seed else { throw Failure.setup }
        let source = scenario.events
        let start = ProcessInfo.processInfo.systemUptime
        func now() -> Double { (ProcessInfo.processInfo.systemUptime - start) * 1000 }
        var frames = [[String: Any]](), dispatchMS = [Double]()
        var index = 0, previous = "", previousY = scroll.contentView.bounds.minY
        var changes = 0, largestAddition = 0, maxYStep: CGFloat = 0, elapsedToFirst: Double?
        var maxPollGap = 0.0, previousPoll = 0.0, maxBackwards: CGFloat = 0, evidenceOnly = true
        var everKey = false
        var images = [(Double, CGImage)]()
        while now() < final.ms + 350 {
            let tick = now()
            maxPollGap = max(maxPollGap, tick - previousPoll)
            previousPoll = tick
            while index < source.count, tick >= source[index].ms {
                let event = source[index]
                dispatchMS.append(now())
                replay.publish(event.text, final: event.final)
                index += 1
            }
            panel.displayIfNeeded()
            if gif != nil, tick - (images.last?.0 ?? -100) >= 1000 / 30 {
                // Rasterize only this isolated NSTextView's actual viewport. No
                // composited desktop, other window or user text enters the GIF.
                let rect = editor.visibleRect
                guard let bitmap = editor.bitmapImageRepForCachingDisplay(in: rect) else { throw Failure.setup }
                editor.cacheDisplay(in: rect, to: bitmap)
                guard let image = bitmap.cgImage,
                      let opaque = CGContext(data: nil, width: image.width, height: image.height, bitsPerComponent: 8,
                          bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)
                      else { throw Failure.setup }
                let bounds = CGRect(x: 0, y: 0, width: image.width, height: image.height)
                opaque.setFillColor(NSColor.white.cgColor); opaque.fill(bounds); opaque.draw(image, in: bounds)
                guard let snapshot = opaque.makeImage() else { throw Failure.setup }
                images.append((tick, snapshot))
            }
            let text = editor.string
            let tail = text.hasPrefix(seed) ? String(text.dropFirst(seed.count)) : text
            let y = scroll.contentView.bounds.minY
            everKey = everKey || panel.isKeyWindow
            if tail != previous || y != previousY {
                if tail != previous {
                    changes += 1
                    let common = zip(tail, previous).prefix(while: { $0 == $1 }).count
                    largestAddition = max(largestAddition, tail.count - common)
                    if elapsedToFirst == nil, !tail.isEmpty { elapsedToFirst = now() - (dispatchMS.first ?? tick) }
                    evidenceOnly = evidenceOnly && text.hasPrefix(seed) && source.prefix(index).contains { $0.text.hasPrefix(tail) }
                }
                var intersects = false
                if let layout = editor.layoutManager, let container = editor.textContainer, !text.isEmpty {
                    let glyph = layout.glyphRange(forCharacterRange: NSRange(location: (text as NSString).length - 1, length: 1), actualCharacterRange: nil)
                    let rect = layout.boundingRect(forGlyphRange: glyph, in: container).offsetBy(dx: editor.textContainerOrigin.x, dy: editor.textContainerOrigin.y)
                    intersects = editor.visibleRect.intersects(rect)
                }
                frames.append(["ms": now(), "sourceCount": index, "text": tail, "offsetY": y, "tailGlyphInClip": intersects])
                maxYStep = max(maxYStep, abs(y - previousY))
                maxBackwards = max(maxBackwards, previousY - y)
                previous = tail; previousY = y
            }
            try await Task.sleep(for: .milliseconds(8))
        }
        if let gif {
            guard let destination = CGImageDestinationCreateWithURL(gif as CFURL, UTType.gif.identifier as CFString, images.count, nil) else { throw Failure.setup }
            CGImageDestinationSetProperties(destination, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0]] as CFDictionary)
            for (i, frame) in images.enumerated() {
                let delay = i + 1 < images.count ? (images[i + 1].0 - frame.0) / 1000 : 0.65
                CGImageDestinationAddImage(destination, frame.1, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: delay]] as CFDictionary)
            }
            guard CGImageDestinationFinalize(destination) else { throw Failure.setup }
        }
        let finalMatches = editor.string.utf16.elementsEqual(replay.document.text.utf16) && previous == final.text
        let range = NSRange(location: (seed as NSString).length, length: 2)
        guard NSMaxRange(range) <= (editor.string as NSString).length else { throw Failure.setup }
        let board = NSPasteboard.withUniqueName()
        defer { board.releaseGlobally() }
        editor.commandPasteboard = board
        editor.setSelectedRange(range)
        let selected = (editor.string as NSString).substring(with: range)
        editor.copy(nil)
        let readOrigin = scroll.contentView.bounds.origin
        replay.publish(final.text + "再次确认", final: false)
        try await Task.sleep(for: .milliseconds(130))
        let selectionProtected = scroll.selectionSnapshot == selected && editor.selectedRange() == range
        let readerStable = scroll.contentView.bounds.origin == readOrigin
        let copyStable = board.string(forType: .string) == selected
        scroll.jumpToLatest()
        replay.publish(final.text + "再次确认", final: true)
        try await Task.sleep(for: .milliseconds(100))
        let editRange = NSRange(location: (editor.string as NSString).length, length: 0)
        editor.insertText("手改", replacementRange: editRange)
        try await Task.sleep(for: .milliseconds(100))
        let editPassed = replay.edits.count == 1 && replay.live.displayText == final.text + "再次确认手改" && editor.string == replay.document.text
        return ["name": scenario.name, "sourceEvents": source.count, "events": source.map { ["ms": $0.ms, "text": $0.text, "final": $0.final] as [String: Any] }, "dispatchMS": dispatchMS, "frames": frames,
                "displayedChanges": changes, "largestReplacementSuffixCharacters": largestAddition, "largestScrollStepPoints": maxYStep, "largestBackwardStepPoints": maxBackwards,
                "firstSourceToNativeTextMS": elapsedToFirst as Any? ?? NSNull(), "largestSampleGapMS": maxPollGap,
                "framePoints": [box.width, box.height], "clipPoints": [scroll.contentSize.width, scroll.contentSize.height], "backingScale": panel.backingScaleFactor,
                "finalExact": finalMatches, "onlySubmittedPrefixes": evidenceOnly, "selectionProtected": selectionProtected, "readingOriginHeld": readerStable, "copySnapshotHeld": copyStable,
                "editPersisted": editPassed, "everTookKey": everKey]
    }
}
