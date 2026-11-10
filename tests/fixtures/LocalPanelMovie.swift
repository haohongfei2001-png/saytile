import AppKit
import AVFoundation
import ScreenCaptureKit

// Engineering-only: record one window of the expressly launched fixture process.
// No display fallback, desktop audio, microphone, or enumeration of browser text.
final class RecordingSink: NSObject, SCRecordingOutputDelegate, @unchecked Sendable {
    let done = DispatchSemaphore(value: 0)
    var error: Error?
    func waitForFinish() -> Bool { done.wait(timeout: .now() + 5) == .success }
    func recordingOutputDidFinishRecording(_ output: SCRecordingOutput) { done.signal() }
    func recordingOutput(_ output: SCRecordingOutput, didFailWithError error: Error) {
        self.error = error
        done.signal()
    }
}
@main struct LocalPanelMovie {
    static func main() async {
        do { try await record() } catch { print("Window-only capture unavailable: " + error.localizedDescription); exit(2) }
    }
    static func unavailable(_ reason: String) -> NSError {
        NSError(domain: "SaytileFixtureMovie", code: 1, userInfo: [NSLocalizedDescriptionKey: reason])
    }
    static func record() async throws {
        await MainActor.run { _ = NSApplication.shared; NSApp.setActivationPolicy(.prohibited) }
        let args = CommandLine.arguments
        guard args.count == 4, let pid = Int32(args[1]), let seconds = Double(args[2]), (2...20).contains(seconds)
            else { throw unavailable("invalid fixture PID or duration") }
        guard CGPreflightScreenCaptureAccess() else { throw unavailable("no existing screen recording authorization; no prompt issued") }
        var fixture = false
        for _ in 0..<30 {
            if let app = NSRunningApplication(processIdentifier: pid), app.bundleIdentifier == "app.saytile.mac",
               let path = app.bundleURL?.resolvingSymlinksInPath().path,
               (path.hasPrefix("/private/tmp/saytile-local-final.") || path.hasPrefix("/tmp/saytile-local-final.")),
               path.hasSuffix("/Applications/Saytile.app") { fixture = true; break }
            try await Task.sleep(for: .milliseconds(100))
        }
        guard fixture else { throw unavailable("PID is not the isolated signed Saytile candidate") }
        let url = URL(fileURLWithPath: args[3])
        guard !FileManager.default.fileExists(atPath: url.path) else { throw CocoaError(.fileWriteFileExists) }
        var own: SCWindow?
        for _ in 0..<30 {
            let content = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true)
            let matches = content.windows.filter { $0.owningApplication?.processID == pid && $0.frame.width >= 280 && $0.frame.height >= 160 }
            if matches.count == 1 { own = matches[0]; break }
            try await Task.sleep(for: .milliseconds(100))
        }
        guard let own else { throw CocoaError(.fileNoSuchFile) }
        let filter = SCContentFilter(desktopIndependentWindow: own)
        let config = SCStreamConfiguration()
        config.width = Int(own.frame.width) * 2
        config.height = Int(own.frame.height) * 2
        config.showsCursor = false
        config.capturesAudio = false
        config.captureMicrophone = false
        config.ignoreShadowsSingleWindow = true
        config.minimumFrameInterval = CMTime(value: 1, timescale: 15)
        let stream = SCStream(filter: filter, configuration: config, delegate: nil)
        let rc = SCRecordingOutputConfiguration()
        rc.outputURL = url; rc.outputFileType = .mp4; rc.videoCodecType = .h264
        let sink = RecordingSink()
        let output = SCRecordingOutput(configuration: rc, delegate: sink)
        try stream.addRecordingOutput(output)
        try await stream.startCapture()
        try await Task.sleep(for: .milliseconds(Int(seconds * 1000)))
        try await stream.stopCapture()
        let finished = await Task.detached { sink.waitForFinish() }.value
        if let error = sink.error { throw error }
        let asset = AVURLAsset(url: url)
        let duration = try await asset.load(.duration).seconds
        let video = try await asset.loadTracks(withMediaType: .video).count
        let audio = try await asset.loadTracks(withMediaType: .audio).count
        guard finished, video == 1, audio == 0, duration >= seconds - 1 else { throw CocoaError(.fileReadCorruptFile) }
        print("PASS isolated native window; seconds=\(duration) video_tracks=\(video) audio_tracks=\(audio) width=\(config.width) height=\(config.height)")
    }
}
