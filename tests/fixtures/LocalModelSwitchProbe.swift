import AVFoundation
import Foundation
@testable import SaytileKit

/// Uses real workers in the installed bundle and the production session factory. No audio input device.
@main struct LocalModelSwitchProbe {
    static func main() async {
        do { try await run() } catch { print("Switch probe: " + error.localizedDescription); exit(2) }
    }
    static func run() async throws {
        let args = CommandLine.arguments
        guard args.count == 5 else { throw CocoaError(.fileNoSuchFile) }
        let app = URL(fileURLWithPath: args[1]), weights = URL(fileURLWithPath: args[2]), file = URL(fileURLWithPath: args[3])
        let output = URL(fileURLWithPath: args[4])
        guard let stamp = Bundle(url: app)?.object(forInfoDictionaryKey: "SaytileSourceRevision") as? String,
              file.lastPathComponent == "fleurs-zh-13737992583400421680.wav" else { throw CocoaError(.fileReadCorruptFile) }
        let audio = try AVAudioFile(forReading: file, commonFormat: .pcmFormatInt16, interleaved: false)
        guard audio.processingFormat.channelCount == 1, audio.processingFormat.sampleRate == 16_000, audio.length == 163_200,
              let buffer = AVAudioPCMBuffer(pcmFormat: audio.processingFormat, frameCapacity: AVAudioFrameCount(audio.length)) else { throw CocoaError(.fileReadCorruptFile) }
        try audio.read(into: buffer)
        guard let values = buffer.int16ChannelData?[0] else { throw CocoaError(.fileReadUnknown) }
        let pcm = Data(bytes: values, count: Int(buffer.frameLength) * 2)
        let dir = FileManager.default.temporaryDirectory.appending(path: "saytile-switch-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        // A command-line probe has no app resource bundle. Match the trusted
        // working directory used by the signed app for its Metal helper.
        guard FileManager.default.changeCurrentDirectoryPath(app.appending(path: "Contents/Resources").path) else { throw CocoaError(.fileNoSuchFile) }
        let store = try SaytileStore(directory: dir)
        let factory = RecognitionSessionFactory()
        let service = LocalASRService(root: weights, helpers: app.appending(path: "Contents/Helpers"))
        factory.selectLocal(live: .sherpa, archive: .sherpa, service: service)
        var history: [[String]] = []
        for (index, expect) in ["sherpa", "nemotron-metal"].enumerated() {
            let snapshot = factory.snapshot
            let record = try await store.createRecording()
            let ticket = try await store.beginRecognition(recordingID: record.id)
            let session = factory.make(store: store, ticket: ticket, snapshot: snapshot, newCapture: true)
            var switched = false
            let clock = ContinuousClock(), began = clock.now
            for i in stride(from: 0, to: pcm.count, by: 1280) {
                let end = min(i + 1280, pcm.count)
                try await clock.sleep(until: began + .milliseconds(Int64(end / 32)))
                session.append(pcm.subdata(in: i..<end))
                if index == 0 && !switched && end >= 160_000 {
                    let early = try await store.recording(id: record.id)?.text ?? ""
                    guard !early.isEmpty else { throw CocoaError(.fileReadUnknown) }
                    factory.selectLocal(live: .nemotron, archive: .sherpa, service: service)
                    switched = true
                }
            }
            session.finish(); await session.wait()
            let runs = try await store.modelRuns(recordingID: record.id).map { $0.ticket.provider }
            let state = try await store.recording(id: record.id)
            guard runs == [expect], state?.recognitionState == .completed, state?.text.isEmpty == false else {
                throw NSError(domain: "LocalSwitch", code: 1, userInfo: [NSLocalizedDescriptionKey: "expected " + expect + "; observed " + runs.joined(separator: ",") + "; state " + (state?.recognitionState.rawValue ?? "missing") + "; " + (state?.lastError ?? "")])
            }
            history.append(runs)
        }
        await service.releaseIdle()
        let res: [String: Any] = ["status": "PASS", "source": stamp, "providers_in_order": history,
            "changed_selection_at_input_seconds": 5, "active_utterance_already_displayed_text": true,
            "scope": "production session factory and signed installed model workers, paced public PCM; no GUI clicks"]
        try JSONSerialization.data(withJSONObject: res, options: [.prettyPrinted, .sortedKeys]).write(to: output)
    }
}
