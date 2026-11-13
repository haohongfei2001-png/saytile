import AppKit
import Combine
import SaytileKit

/// Observes only this isolated panel's laid-out NSTextView. No screen capture,
/// microphone, pasteboard, real archive or external application is used.
@MainActor enum LocalStreamProbe {
    struct Frame: Codable { let t: Double; let text: String; let speaking: Bool; let level: Float }
    struct Publication: Codable { let t: Double; let text: String }
    struct Result: Codable {
        let model: String
        let sha: String?
        let sample: String
        let publications: [Publication]
        let frames: [Frame]
        let displayedChanges: Int
        let endOfFile: Double
        let pipelineSettledAt: Double
        let total: Double
        let archive: [String]
        let providers: [String]
        let recordStates: [String]
        let recordingErrors: [String]
    }
    static func textView(_ parent: NSView) -> CompactTranscriptScrollView? {
        if let result = parent as? CompactTranscriptScrollView { return result }
        for item in parent.subviews { if let found = textView(item) { return found } }
        return nil
    }
    static func run(model: AppModel, panel: NSWindow?, id: LocalASRID) async throws {
        guard let panel, let content = panel.contentView,
              try await model.store.listRecordings(limit: 1).isEmpty else { throw CocoaError(.fileReadCorruptFile) }
        let source = model.directory.appending(path: "fixture.wav")
        let values = try source.resourceValues(forKeys: [.isSymbolicLinkKey,.isRegularFileKey,.fileSizeKey])
        guard values.isRegularFile == true, values.isSymbolicLink == false, (values.fileSize ?? 0) < 60_000_000 else { throw CocoaError(.fileReadCorruptFile) }
        await model.initialLoad()
        model.selectSource("local")
        model.selectLocal(id, archiveOnly: id.capability == .batch)
        if id == .apple, !(await AppleSpeechService.availability()).installed {
            await model.audio.prepareSpeechAssets()
            let status = await AppleSpeechService.availability()
            guard status.installed else { throw AudioFailure.message(model.audio.appleResourceFailure ?? status.message) }
        }
        let start = ProcessInfo.processInfo.systemUptime
        // These are host timeline publications before the view performs any presentation.
        // A display frame is not another ASR result. Collect only inside this disposable probe.
        var publications: [Publication] = []
        let subscription = model.$timeline.sink { page in
            let text = PanelTimelineDocument(entries: page.entries).text
            if !text.isEmpty, text != publications.last?.text, publications.count < 512 {
                publications.append(Publication(t: ProcessInfo.processInfo.systemUptime - start, text: text))
            }
        }
        defer { subscription.cancel() }
        let observe = Task { @MainActor () -> ([Frame], Int) in
            var frames: [Frame] = [], last = "", changes = 0, captured = false
            while !Task.isCancelled {
                if panel.isVisible, let view = textView(content), !view.isHiddenOrHasHiddenAncestor,
                   let manager = view.transcriptView.layoutManager, manager.numberOfGlyphs > 0 {
                    let string = view.transcriptView.string
                    if !string.isEmpty, last != string {
                        last = string; changes += 1
                        if changes <= 512 { frames.append(Frame(t: ProcessInfo.processInfo.systemUptime - start, text: string, speaking: model.audio.state == .speaking, level: model.audio.level)) }
                        if changes >= 3, !captured, model.audio.state == .speaking, let bitmap = content.bitmapImageRepForCachingDisplay(in: content.bounds) {
                            captured = true
                            content.cacheDisplay(in: content.bounds, to: bitmap)
                            try? bitmap.representation(using: .png, properties: [:])?.write(to: model.directory.appending(path: "partial.png"))
                        }
                    }
                }
                do { try await Task.sleep(for: .milliseconds(35)) } catch { break }
            }
            return (frames, changes)
        }
        defer { observe.cancel() }
        let batch = id.capability == .batch
        let eos = try await model.audio.replayLocalFixture(source, recordOnly: batch)
        let settled = ProcessInfo.processInfo.systemUptime - start
        if batch {
            for record in try await model.store.listRecordings(limit: 20) {
                await model.audio.retry(recordingID: record.id)
                let limit = ContinuousClock.now + .seconds(190)
                while try await model.store.recording(id: record.id)?.recognitionState != .completed {
                    if ContinuousClock.now > limit { throw AudioFailure.message("档案重识别未完成") }
                    try await Task.sleep(for: .milliseconds(100))
                }
            }
        }
        try await Task.sleep(for: .milliseconds(500))
        observe.cancel()
        let (frames, changes) = await observe.value
        let records = try await model.store.listRecordings(limit: 20)
        var providers = Set<String>()
        for r in records {
            let runs = try await model.store.modelRuns(recordingID: r.id)
            providers.formUnion(runs.map { $0.ticket.provider })
        }
        let receipt = Result(model: id.rawValue, sha: Bundle.main.object(forInfoDictionaryKey: "SaytileSourceRevision") as? String,
            sample: source.lastPathComponent, publications: publications, frames: frames, displayedChanges: changes, endOfFile: eos - start, pipelineSettledAt: settled,
            total: ProcessInfo.processInfo.systemUptime - start, archive: records.map(\.text), providers: providers.sorted(),
            recordStates: records.map { $0.recognitionState.rawValue }, recordingErrors: records.compactMap(\.lastError))
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted,.sortedKeys]
        try encoder.encode(receipt).write(to: model.directory.appending(path: "visible.json"), options: .atomic)
        let early = frames.filter { $0.t < receipt.endOfFile && $0.speaking }
        let expected = id == .apple ? "apple-speech-analyzer" : id.rawValue
        guard (batch ? early.isEmpty : early.count >= 2), providers == [expected], records.contains(where: { !$0.text.isEmpty }) else {
            throw AudioFailure.message("未观察到多次结束前的原生文字更新")
        }
    }
}
