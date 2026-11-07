import AppKit
@preconcurrency import AVFoundation
import CoreAudio
import AudioToolbox
import CAudio
@testable import SaytileKit

struct CheckError: Error { let message: String }
func require(_ condition: Bool, _ message: String) throws {
    if !condition { throw CheckError(message: message) }
}
func defaultInput() throws -> AudioDeviceID {
    var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultInputDevice, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
    var id: AudioDeviceID = 0
    var size = UInt32(MemoryLayout.size(ofValue: id))
    try require(AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &id) == noErr && id != 0, "no default input")
    return id
}
@MainActor func count(_ id: AudioDeviceID, label: String) async throws -> UInt64 {
    let engine = AVAudioEngine()
    let input = engine.inputNode
    if label == "explicit" {
        guard let unit = input.audioUnit else { throw CheckError(message:"input AudioUnit unavailable") }
        var selected = id
        try require(AudioUnitSetProperty(unit,kAudioOutputUnitProperty_CurrentDevice,kAudioUnitScope_Global,0,&selected,UInt32(MemoryLayout.size(ofValue:selected))) == noErr,"explicit bind failed")
        var actual:AudioDeviceID=0
        var size=UInt32(MemoryLayout.size(ofValue:actual))
        try require(AudioUnitGetProperty(unit,kAudioOutputUnitProperty_CurrentDevice,kAudioUnitScope_Global,0,&actual,&size)==noErr && actual==id,"explicit device readback failed")
    }
    let format = input.outputFormat(forBus: 0)
    try require(format.sampleRate > 0 && format.channelCount > 0, "invalid input format")
    let counter = try AudioProbeCounter()
    input.installTap(onBus: 0, bufferSize: 1024, format: format, block: AudioTapCallbacks.counting(counter: counter))
    defer { engine.stop(); input.removeTap(onBus: 0) }
    try engine.start()
    try await Task.sleep(for: .seconds(5))
    let frames = st_probe_frames(counter.pointer)
    print("ROUTE \(label) verified_device=true frames=\(frames) rate=\(format.sampleRate)")
    return UInt64(frames)
}
@main struct Probe {
    @MainActor static func main() async { do {
        guard AVCaptureDevice.authorizationStatus(for:.audio) == .authorized else { print("BLOCKED existing permission"); return }
        let id = try defaultInput()
        for label in ["default-before","explicit","default-after"] {
            _ = try await count(id,label:label)
            try require(try defaultInput()==id,"system default changed")
        }
    } catch { print("INCOMPLETE",error); exit(2) }
    }
}
