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
    guard let unit = input.audioUnit else { throw CheckError(message: "input AudioUnit unavailable") }
    var selected = id
    try require(AudioUnitSetProperty(unit, kAudioOutputUnitProperty_CurrentDevice, kAudioUnitScope_Global, 0, &selected, UInt32(MemoryLayout.size(ofValue: selected))) == noErr, "set input failed")
    var actual: AudioDeviceID = 0
    var size = UInt32(MemoryLayout.size(ofValue: actual))
    try require(AudioUnitGetProperty(unit, kAudioOutputUnitProperty_CurrentDevice, kAudioUnitScope_Global, 0, &actual, &size) == noErr && actual == id, "wrong AudioUnit device")
    let format = input.outputFormat(forBus: 0)
    try require(format.sampleRate > 0 && format.channelCount > 0, "invalid input format")
    let counter = try AudioProbeCounter()
    input.installTap(onBus: 0, bufferSize: 1024, format: format, block: AudioTapCallbacks.counting(counter: counter))
    defer { engine.stop(); input.removeTap(onBus: 0) }
    try engine.start()
    try await Task.sleep(for: .seconds(2))
    let frames = st_probe_frames(counter.pointer)
    print("ROUTE \(label) verified_device=true frames=\(frames) rate=\(format.sampleRate)")
    return UInt64(frames)
}
func halCount(_ id: AudioDeviceID) async throws -> UInt64 {
    let counter = try AudioProbeCounter()
    var procID: AudioDeviceIOProcID?
    let rc = AudioDeviceCreateIOProcIDWithBlock(&procID, id, nil) { _, input, _, _, _ in
        // Read only the size of the first buffer; never follow mData.
        st_probe_count(counter.pointer, input.pointee.mBuffers.mDataByteSize)
    }
    try require(rc == noErr && procID != nil, "HAL IOProc registration failed: " + String(rc))
    defer { _ = AudioDeviceDestroyIOProcID(id, procID!) }
    let start = AudioDeviceStart(id, procID!)
    try require(start == noErr, "HAL device start failed: " + String(start))
    defer { _ = AudioDeviceStop(id, procID!) }
    try await Task.sleep(for:.seconds(2))
    return UInt64(st_probe_frames(counter.pointer))
}
@main struct Probe {
    @MainActor static func main() async {
        do {
            guard AVCaptureDevice.authorizationStatus(for: .audio) == .authorized else {
                print("BLOCKED pre-existing microphone authorization unavailable"); return
            }
            let source = try defaultInput()
            let store = try SaytileStore(directory: URL(fileURLWithPath: CommandLine.arguments[1]))
            let controller = AudioController(store: store, startupRecoveryReady: false)
            guard let physical = controller.devices.first(where: { $0.id == source }) else { throw CheckError(message: "default input not enumerated") }
            let uid = "app.saytile.test.route." + UUID().uuidString
            let description: [String:Any] = [kAudioAggregateDeviceNameKey:"Saytile isolated route",kAudioAggregateDeviceUIDKey:uid,kAudioAggregateDeviceIsPrivateKey:1,kAudioAggregateDeviceMainSubDeviceKey:physical.uid,kAudioAggregateDeviceSubDeviceListKey:[[kAudioSubDeviceUIDKey:physical.uid]]]
            var aggregate: AudioDeviceID = 0
            let result = AudioHardwareCreateAggregateDevice(description as CFDictionary, &aggregate)
            guard result == noErr && aggregate != 0 else { print("BLOCKED private aggregate create status=\(result)"); return }
            var owned = true
            defer { if owned { _ = AudioHardwareDestroyAggregateDevice(aggregate) } }
            for _ in 0..<30 {
                controller.refreshDevices()
                if controller.devices.contains(where: { $0.id == aggregate }) { break }
                try await Task.sleep(for: .milliseconds(100))
            }
            try require(controller.devices.contains(where: { $0.id == aggregate && $0.uid == uid }), "aggregate not enumerated")
            controller.selectDevice(uid: physical.uid)
            try require(controller.selectedDeviceID == source, "physical not selected")
            let initialFrames = try await count(source, label:"physical-A")
            controller.selectDevice(uid: uid)
            try require(controller.selectedDeviceID == aggregate, "aggregate not selected")
            let inputBytes = try await halCount(aggregate)
            print("HAL aggregate input metadata bytes=\(inputBytes)")
            let secondFrames = try await count(aggregate, label:"private-aggregate-B")
            try require(AudioHardwareDestroyAggregateDevice(aggregate) == noErr, "aggregate destruction failed")
            owned = false
            for _ in 0..<30 {
                controller.refreshDevices()
                if !controller.devices.contains(where: { $0.id == aggregate }) { break }
                try await Task.sleep(for: .milliseconds(100))
            }
            try require(!controller.devices.contains(where: { $0.uid == uid }) && controller.selectedDeviceUID == uid, "removed selection not retained")
            await controller.start(requestPermission: false)
            try require(!controller.state.isRunning && controller.issue?.contains("未连接") == true, "missing route did not report disconnected: " + (controller.issue ?? "nil"))
            await controller.pause()
            controller.selectDevice(uid: physical.uid)
            let returnedFrames = try await count(source, label:"physical-A-return")
            try require(try defaultInput() == source, "system default input changed")
            let records = try await store.listRecordings(limit: 1)
            try require(records.isEmpty, "unexpected recording")
            print("PASS system default unchanged; selected removed private route refused before capture; no stored audio")
            try await store.close()
            try require(initialFrames > 0 && returnedFrames > 0, "physical route start or return returned no frames")
            print(secondFrames > 0 ? "PASS aggregate input backend" : "FAIL aggregate input backend received zero frames")
        } catch {
            print("ROUTE_PROBE_INCOMPLETE \(error)")
            exit(2)
        }
    }
}
