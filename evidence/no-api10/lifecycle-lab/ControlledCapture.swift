import AppKit
import AVFoundation
import AudioToolbox
@testable import SaytileKit

struct LabError: Error { let reason: String }
@main struct ControlledCapture {
    @MainActor static func main() async throws {
        guard ProcessInfo.processInfo.environment["SAYTILE_DEDICATED_AUDIO_LAB"] == "hosted-vm" else { exit(64) }
        let args = CommandLine.arguments
        let root = URL(fileURLWithPath: args[1], isDirectory: true)
        let store = try SaytileStore(directory: root.appendingPathComponent("store"))
        let audio = AudioController(store: store, startupRecoveryReady: false)
        var result: [String: Any] = ["status": "BLOCKED", "kernel_sleep": false, "private_mic": false,
                                    "cloud": false, "authorization": AVCaptureDevice.authorizationStatus(for: .audio).rawValue]
        func save() throws {
            try JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted,.sortedKeys]).write(to: root.appendingPathComponent("capture.json"), options: .atomic)
        }
        guard AVCaptureDevice.authorizationStatus(for: .audio) == .authorized else {
            result["reason"] = "isolated process has no existing microphone grant"; try save(); return
        }
        guard let device = audio.devices.first(where: { $0.uid == "BlackHole2ch_UID" && $0.name == "BlackHole 2ch" }) else {
            result["reason"] = "test loopback unavailable"; try save(); return
        }
        let source = try AVAudioFile(forReading: URL(fileURLWithPath: args[2]))
        guard let signal = AVAudioPCMBuffer(pcmFormat: source.processingFormat, frameCapacity: UInt32(source.length)) else { throw LabError(reason: "buffer") }
        try source.read(into: signal)
        let output = AVAudioEngine(), player = AVAudioPlayerNode()
        guard let unit = output.outputNode.audioUnit else { throw LabError(reason: "output unit unavailable") }
        var id = device.id, check: AudioDeviceID = 0, size = UInt32(MemoryLayout<AudioDeviceID>.size)
        guard AudioUnitSetProperty(unit,kAudioOutputUnitProperty_CurrentDevice,kAudioUnitScope_Global,0,&id,size) == noErr,
              AudioUnitGetProperty(unit,kAudioOutputUnitProperty_CurrentDevice,kAudioUnitScope_Global,0,&check,&size) == noErr,
              check == device.id else { throw LabError(reason: "unable to pin test output") }
        output.attach(player); output.connect(player,to:output.mainMixerNode,format:signal.format)
        try output.start()
        defer { player.stop(); output.stop() }
        audio.selectDevice(uid: device.uid)
        guard audio.selectedDeviceUID == device.uid else { throw LabError(reason: "test input was not pinned") }
        try save()
        do {
            await audio.start(requestPermission: false)
            guard audio.state.isRunning else { throw LabError(reason: "selected test input failed to start") }
            let checkLink = ProcessInfo.processInfo.environment["SAYTILE_VM_LINK_CHECK"] == "1"
            func markPhase(_ name: String) throws {
                try Data().write(to: root.appendingPathComponent(name), options: .atomic)
            }
            func waitForSignal(_ name: String) async throws {
                for _ in 0..<300 {
                    if FileManager.default.fileExists(atPath: root.appendingPathComponent(name).path) { return }
                    try await Task.sleep(for: .milliseconds(100))
                }
                throw LabError(reason: "hosted link test timed out waiting for " + name)
            }
            if checkLink {
                try markPhase("input-ready")
                try await waitForSignal("play")
            }
            player.scheduleBuffer(signal,at:nil,options:.loops, completionHandler: nil); player.play()
            func recording(excluding previous: UUID? = nil) async throws -> UUID {
                for _ in 0..<100 {
                    if let row = try await store.listRecordings(limit: 10).first(where: { $0.isRecording && $0.id != previous }) { return row.id }
                    try await Task.sleep(for: .milliseconds(100))
                }
                throw LabError(reason: "no voice segment on isolated input")
            }
            let first = try await recording()
            if checkLink {
                try markPhase("journal-open")
                try await waitForSignal("restored")
            }
            try await Task.sleep(for: .milliseconds(450))
            let center = NSWorkspace.shared.notificationCenter
            center.post(name:NSWorkspace.willSleepNotification,object:nil)
            for _ in 0..<100 {
                if !audio.state.isRunning, try await store.recording(id:first)?.isRecording == false { break }
                try await Task.sleep(for:.milliseconds(100))
            }
            player.pause()
            let sealed = try await store.audioChunks(recordingID: first)
            guard !audio.state.isRunning, audio.issue == "Mac 已睡眠", !sealed.isEmpty,
                  try await store.recording(id: first)?.isRecording == false else { throw LabError(reason: "sleep did not seal active recording") }
            var digests: [Data] = []
            for chunk in sealed {
                let bytes = try Data(contentsOf: await store.audioURL(for:chunk))
                guard bytes.starts(with: Data("RIFF".utf8)) && bytes.count == 44 + 2 * Int(chunk.frames) else { throw LabError(reason:"invalid sealed original") }
                digests.append(bytes)
            }
            center.post(name:NSWorkspace.didWakeNotification,object:nil)
            for _ in 0..<100 {
                if audio.state.isRunning { break }
                try await Task.sleep(for:.milliseconds(100))
            }
            guard audio.state.isRunning, audio.selectedDeviceUID == device.uid else { throw LabError(reason:"selected source did not resume") }
            player.play()
            let second = try await recording(excluding:first)
            try await Task.sleep(for:.milliseconds(450))
            await audio.pause(); player.pause()
            center.post(name:NSWorkspace.willSleepNotification,object:nil)
            try await Task.sleep(for:.milliseconds(350))
            center.post(name:NSWorkspace.didWakeNotification,object:nil)
            try await Task.sleep(for:.milliseconds(550))
            guard audio.state == .paused, try await store.recording(id:second)?.isRecording == false,
                  try await !store.audioChunks(recordingID:second).isEmpty else { throw LabError(reason:"second segment or intentional pause lost") }
            for (i,chunk) in sealed.enumerated() {
                guard try Data(contentsOf: await store.audioURL(for:chunk)) == digests[i] else { throw LabError(reason:"original changed after wake") }
            }
            result["status"]="PASS"; result["first_frames"]=sealed.reduce(Int64(0)){ $0 + Int64($1.frames) }
            result["two_distinct_recordings"]=first != second;result["pause_preserved"]=true;result["prior_wavs_byte_identical"]=true
        } catch { result["status"]="FAIL"; result["reason"]=String(describing:error) }
        await audio.shutdown();try await store.close();try save()
        if result["status"] as? String == "FAIL" { exit(1) }
    }
}
