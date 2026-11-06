import Foundation
@preconcurrency import Speech
@preconcurrency import AVFoundation

struct DictationCase: Decodable { let id: String; let expected: String }
struct DictationResult: Encodable { let id: String; let expected: String; let text: String; let elapsedSeconds: Double }
@main struct DictationComparisonProbe {
    static func main() async throws {
        let args = CommandLine.arguments
        let cases = try JSONDecoder().decode([DictationCase].self, from: Data(contentsOf: URL(fileURLWithPath: args[1])))
        guard let locale = await DictationTranscriber.supportedLocale(equivalentTo: Locale(identifier: "zh-CN")) else { throw NSError(domain: "Corpus", code: 1, userInfo: [NSLocalizedDescriptionKey: "Dictation zh-CN unavailable"]) }
        let prep = DictationTranscriber(locale: locale, preset: .progressiveLongDictation)
        _ = try await AssetInventory.reserve(locale: locale)
        if let request = try await AssetInventory.assetInstallationRequest(supporting: [prep]) { try await request.downloadAndInstall() }
        var results: [DictationResult] = []
        for item in cases {
            let started = ProcessInfo.processInfo.systemUptime
            let transcriber = DictationTranscriber(locale: locale, preset: .progressiveLongDictation)
            let analyzer = SpeechAnalyzer(modules: [transcriber])
            let consume = Task {
                var pieces: [Double: (Double, String)] = [:]
                for try await result in transcriber.results {
                    let start = result.range.start.seconds, end = CMTimeRangeGetEnd(result.range).seconds
                    pieces = pieces.filter { !($0.key < end && $0.value.0 > start) }
                    pieces[start] = (end, String(result.text.characters))
                }
                return pieces.sorted { $0.key < $1.key }.map { $0.value.1 }.joined()
            }
            let file = try AVAudioFile(forReading: URL(fileURLWithPath: args[2]).appendingPathComponent(item.id + ".aiff"))
            try await analyzer.start(inputAudioFile: file, finishAfterFile: true)
            let text = try await consume.value
            results.append(.init(id: item.id, expected: item.expected, text: text, elapsedSeconds: ProcessInfo.processInfo.systemUptime - started))
        }
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        FileHandle.standardOutput.write(try encoder.encode(results))
    }
}
