import Foundation
import AVFoundation
import Speech

struct TimedText: Codable, Sendable { let start: Double; let end: Double; let text: String; let final: Bool }
struct Observation: Codable { let path: String; let results: [TimedText]; let error: String? }

@main struct AppleRangeProbe {
    static func main() async throws {
        var observations: [Observation] = []
        for path in CommandLine.arguments.dropFirst() {
            do { observations.append(.init(path: path, results: try await analyze(URL(fileURLWithPath:path)), error: nil)) }
            catch { observations.append(.init(path: path, results: [], error: String(describing:error))) }
        }
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        FileHandle.standardOutput.write(try encoder.encode(observations))
    }
    static func analyze(_ url: URL) async throws -> [TimedText] {
        guard let locale = await SpeechTranscriber.supportedLocale(equivalentTo: Locale(identifier:"zh-CN")) else { throw CocoaError(.featureUnsupported) }
        let transcriber = SpeechTranscriber(locale: locale, preset: .progressiveTranscription)
        _ = try await AssetInventory.reserve(locale: locale)
        if let request = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
            try await request.downloadAndInstall()
        }
        guard await AssetInventory.status(forModules:[transcriber]) == .installed else { throw CocoaError(.fileNoSuchFile) }
        let modules: [any SpeechModule] = [transcriber, SpeechDetector()]
        guard let format = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith:modules) else { throw CocoaError(.featureUnsupported) }
        let file = try AVAudioFile(forReading:url, commonFormat:.pcmFormatInt16, interleaved:false)
        guard let converter = AVAudioConverter(from:file.processingFormat, to:format),
              let input = AVAudioPCMBuffer(pcmFormat:file.processingFormat, frameCapacity:AVAudioFrameCount(file.length)) else { throw CocoaError(.fileReadCorruptFile) }
        try file.read(into:input)
        let analyzer = SpeechAnalyzer(modules:modules)
        let (stream, continuation) = AsyncStream<AnalyzerInput>.makeStream()
        let resultTask = Task {
            var result: [TimedText] = []
            for try await r in transcriber.results {
                result.append(.init(start:r.range.start.seconds, end:CMTimeRangeGetEnd(r.range).seconds,
                                    text:String(r.text.characters), final:r.isFinal))
            }
            return result
        }
        do {
            try await analyzer.prepareToAnalyze(in:format)
            try await analyzer.start(inputSequence:stream)
            var supplied = false
            while true {
                guard let output = AVAudioPCMBuffer(pcmFormat:format, frameCapacity:4096) else { throw CocoaError(.fileReadCorruptFile) }
                var error: NSError?
                let status = converter.convert(to:output, error:&error) { _, state in
                    if supplied { state.pointee = .endOfStream; return nil }
                    supplied = true; state.pointee = .haveData; return input
                }
                if status == .error { throw error ?? CocoaError(.fileReadCorruptFile) as NSError }
                if output.frameLength > 0 { continuation.yield(AnalyzerInput(buffer:output)) }
                if status == .endOfStream || output.frameLength == 0 { break }
            }
            continuation.finish()
            try await analyzer.finalizeAndFinishThroughEndOfInput()
            return try await resultTask.value
        } catch {
            continuation.finish(); await analyzer.cancelAndFinishNow(); resultTask.cancel(); throw error
        }
    }
}
