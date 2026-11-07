import Foundation
import Darwin
import SaytileKit

struct CorpusItem: Codable { let id: String; let voice: String; let spoken: String; let expected: String; let critical: [String] }
final class TimingCollector: @unchecked Sendable {
    let lock = NSLock(); var events: [SpeechTimingEvent] = []
    func append(_ event: SpeechTimingEvent) { lock.lock(); events.append(event); lock.unlock() }
    func snapshot() -> [SpeechTimingEvent] { lock.lock(); defer { lock.unlock() }; return events }
}
struct CorpusResult: Codable {
    let id: String; let voice: String; let expected: String; let recognized: String
    let normalizedCER: Double; let missingCriticalPhrases: [String]
    let recognitionState: String; let error: String?; let audioDuration: Double
    let firstTextSeconds: Double?; let finalizationAfterInputSeconds: Double?
    let timings: [SpeechTimingEvent]
    let localCandidateCount: Int
    let localProviders: [String]
    let localUnifiedEvidence: Bool
    let dispatchableUTF16Length: Int
}
func normalized(_ value: String) -> String {
    value.folding(options: [.caseInsensitive, .widthInsensitive], locale: Locale(identifier: "zh-CN"))
        .unicodeScalars.filter { !CharacterSet.whitespacesAndNewlines.contains($0) && !CharacterSet.punctuationCharacters.contains($0) }
        .map(String.init).joined()
}
func distance(_ a: String, _ b: String) -> Int {
    let x = Array(a), y = Array(b); var row = Array(0...y.count)
    for (i, character) in x.enumerated() {
        var next = [i + 1] + [Int](repeating: 0, count: y.count)
        for (j, other) in y.enumerated() { next[j + 1] = min(next[j] + 1, row[j + 1] + 1, row[j] + (character == other ? 0 : 1)) }
        row = next
    }
    return row[y.count]
}
@main struct AudioCorpusProbe {
    static func main() async throws {
        let args = CommandLine.arguments
        guard args.count == 4 || (args.count == 5 && args[4] == "--prepare-speech") else { fatalError("manifest.json fixture-directory isolated-store [--prepare-speech]") }
        let corpus = try JSONDecoder().decode([CorpusItem].self, from: Data(contentsOf: URL(fileURLWithPath: args[1])))
        if args.contains("--prepare-speech") { try await AssetPreparationObservation.prepareIfNeeded() }
        let availability = await AppleSpeechService.availability()
        guard availability.supported && availability.installed else {
            let result: [String: Any] = ["status": "LOCAL_SPEECH_UNAVAILABLE", "supported": availability.supported,
                "installed": availability.installed, "message": availability.message, "microphone_opened": false]
            FileHandle.standardOutput.write(try JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted, .sortedKeys]))
            exit(5)
        }
        let store = try SaytileStore(directory: URL(fileURLWithPath: args[3]))
        var results: [CorpusResult] = []
        for item in corpus {
            FileHandle.standardError.write(Data("Recognizing synthetic fixture \(item.id)\n".utf8))
            let timing = TimingCollector()
            let id = try await AudioDiagnostics.transcribeFixture(url: URL(fileURLWithPath: args[2]).appendingPathComponent(item.id + ".aiff"), store: store, realtime: true, event: { timing.append($0) })
            let record = try await store.recording(id: id)!
            let candidates = try await store.recognitionCandidates(recordingID: id)
            let providers = Array(Set(candidates.map { $0.run.provider })).sorted()
            let decisions = try await store.fusionDecisions(recordingID: id)
            let unified = !candidates.isEmpty && providers == ["apple-speech-analyzer"] && !decisions.isEmpty
            let dispatchable = try await store.latestDispatchableRevision(recordingID: id)
            let events = timing.snapshot()
            let finished = events.first(where: { $0.kind == "inputFinished" })?.elapsedSeconds
            let completed = events.last(where: { $0.kind == "completed" })?.elapsedSeconds
            let expected = normalized(item.expected), recognized = normalized(record.text)
            results.append(CorpusResult(id: item.id, voice: item.voice, expected: item.expected, recognized: record.text,
                normalizedCER: Double(distance(expected, recognized)) / Double(max(1, expected.count)),
                missingCriticalPhrases: item.critical.filter { !recognized.contains(normalized($0)) },
                recognitionState: record.recognitionState.rawValue, error: record.lastError, audioDuration: record.duration,
                firstTextSeconds: events.first(where: { $0.kind == "firstText" })?.elapsedSeconds,
                finalizationAfterInputSeconds: completed.flatMap { completion in finished.map { max(0, completion - $0) } }, timings: events,
                localCandidateCount: candidates.count, localProviders: providers, localUnifiedEvidence: unified,
                dispatchableUTF16Length: dispatchable?.text.utf16.count ?? 0))
        }
        try await store.close()
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        FileHandle.standardOutput.write(try encoder.encode(results))
        if results.contains(where: { $0.recognitionState != "completed" || !$0.localUnifiedEvidence }) { exit(2) }
    }
}
