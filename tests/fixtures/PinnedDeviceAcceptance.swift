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
@MainActor func count(_ device: AudioInputDevice, label: String) async throws -> UInt64 {
    let input = try PinnedAudioInput(device: device)
    defer { input.stop() }
    try input.start(ring: nil)
    try await Task.sleep(for: .seconds(3))
    try input.checkProgress()
    print("ROUTE",label,"frames",input.frames,"rate",input.sampleRate)
    try require(input.frames > 0, "no frames")
    return input.frames
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
            var outAddress = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultOutputDevice, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
            var outputID: AudioDeviceID = 0
            var idSize = UInt32(MemoryLayout.size(ofValue: outputID))
            try require(AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &outAddress, 0, nil, &idSize, &outputID) == noErr, "no output device")
            var subdevices = [[kAudioSubDeviceUIDKey:physical.uid]]
            if outputID != source {
                var address = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyDeviceUID, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
                var outputUID: Unmanaged<CFString>?
                var size = UInt32(MemoryLayout.size(ofValue: outputUID))
                try require(AudioObjectGetPropertyData(outputID, &address, 0, nil, &size, &outputUID) == noErr, "no output uid")
                if let outputUID { subdevices.append([kAudioSubDeviceUIDKey:outputUID.takeRetainedValue() as String]) }
            }
            if CommandLine.arguments.contains("--input-only") { subdevices = [[kAudioSubDeviceUIDKey:physical.uid]] }
            let description: [String:Any] = [kAudioAggregateDeviceNameKey:"Saytile isolated route",kAudioAggregateDeviceUIDKey:uid,kAudioAggregateDeviceIsPrivateKey:1,kAudioAggregateDeviceMainSubDeviceKey:physical.uid,kAudioAggregateDeviceSubDeviceListKey:subdevices]
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
            let initialFrames = try await count(physical, label:"physical-A")
            controller.selectDevice(uid: uid)
            try require(controller.selectedDeviceID == aggregate, "aggregate not selected")
            guard let secondary = controller.devices.first(where: { $0.id == aggregate && $0.uid == uid }) else { throw CheckError(message:"private route unavailable") }
            let live = try PinnedAudioInput(device:secondary)
            defer { live.stop() }
            try live.start(ring:nil)
            try await Task.sleep(for:.seconds(3))
            try live.checkProgress()
            let secondFrames=live.frames
            print("ROUTE private aggregate active before removal",secondFrames,"rate",live.sampleRate)
            try require(AudioHardwareDestroyAggregateDevice(aggregate) == noErr, "aggregate destruction failed")
            owned = false
            var detected = false
            for _ in 0..<60 {
                do { try live.checkProgress() }
                catch { detected = true; print("REMOVAL",error.localizedDescription); break }
                try await Task.sleep(for:.milliseconds(100))
            }
            try require(detected,"removed live input did not interrupt")
            live.stop()
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
            let returnedFrames = try await count(physical, label:"physical-A-return")
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
