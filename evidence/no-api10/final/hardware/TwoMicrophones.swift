import AVFoundation
import CoreAudio
import Foundation
@testable import SaytileKit

@main struct TwoMicrophones {
    static func number(_ device:AudioDeviceID,_ selector:AudioObjectPropertySelector) -> UInt32 {
        var a=AudioObjectPropertyAddress(mSelector:selector,mScope:kAudioObjectPropertyScopeGlobal,mElement:kAudioObjectPropertyElementMain)
        var n=UInt32.max,size=UInt32(MemoryLayout<UInt32>.size)
        return AudioObjectGetPropertyData(device,&a,0,nil,&size,&n)==noErr ? n : .max
    }
    @MainActor static func main() async throws {
        let root=URL(fileURLWithPath:CommandLine.arguments[1])
        let out=URL(fileURLWithPath:CommandLine.arguments[2])
        let store=try SaytileStore(directory:root)
        let audio=AudioController(store:store,startupRecoveryReady:false)
        let sys=AudioDeviceID(kAudioObjectSystemObject)
        let defaultIn=number(sys,kAudioHardwarePropertyDefaultInputDevice)
        let defaultOut=number(sys,kAudioHardwarePropertyDefaultOutputDevice)
        var result:[String:Any]=["status":"BLOCKED","source":CommandLine.arguments[3],"samples_read":false,"upload":false,"changes_system_default":false]
        func save(_ reason:String) throws {
            result["reason"]=reason
            try JSONSerialization.data(withJSONObject:result,options:[.sortedKeys,.prettyPrinted]).write(to:out,options:.atomic)
        }
        guard AVCaptureDevice.authorizationStatus(for:.audio) == .authorized else { try save("existing permission unavailable");return }
        let builtIn=audio.devices.first { number($0.id,kAudioDevicePropertyTransportType)==kAudioDeviceTransportTypeBuiltIn }
        let extra=audio.devices.first { [kAudioDeviceTransportTypeBluetooth,kAudioDeviceTransportTypeUSB,kAudioDeviceTransportTypeBluetoothLE].contains(number($0.id,kAudioDevicePropertyTransportType)) }
        guard let primary=builtIn,let external=extra else { try save("second physical route unavailable");return }
        guard [primary.id,external.id,defaultOut].allSatisfy({number($0,kAudioDevicePropertyDeviceIsRunningSomewhere)==0}) else {
            try save("one of the physical devices is in use; no capture attempted");return
        }
        guard primary.id != external.id else {try save("same physical route");return}
        var rows:[[String:Any]]=[]
        do {
            for (stage,device) in [("built-in",primary),("external",external),("built-in-return",primary)] {
                audio.selectDevice(uid:device.uid)
                guard audio.selectedDeviceUID==device.uid, audio.selectedDeviceID==device.id else {throw CocoaError(.validationMissingMandatoryProperty)}
                let input=try PinnedAudioInput(device:device)
                do {
                    defer { input.stop() }
                    try input.start(ring:nil)
                    try await Task.sleep(for:.seconds(2))
                    try input.checkProgress()
                    guard input.frames>0 else {throw CocoaError(.validationMissingMandatoryProperty)}
                    rows.append(["stage":stage,"frames":input.frames,"sample_rate":input.sampleRate])
                }
            }
            result["routes"]=rows
            result["default_input_unchanged"]=number(sys,kAudioHardwarePropertyDefaultInputDevice)==defaultIn
            result["default_output_unchanged"]=number(sys,kAudioHardwarePropertyDefaultOutputDevice)==defaultOut
            result["records"]=try await store.listRecordings(limit:1).count
            result["wavs"]=(FileManager.default.enumerator(at:root,includingPropertiesForKeys:nil)?.allObjects as? [URL])?.filter{$0.pathExtension.lowercased()=="wav"}.count ?? -1
            guard result["default_input_unchanged"] as? Bool == true, result["default_output_unchanged"] as? Bool == true,
                  result["records"] as? Int==0,result["wavs"] as? Int==0 else {throw CocoaError(.validationMissingMandatoryProperty)}
            result["external_transport"]=number(external.id,kAudioDevicePropertyTransportType)==kAudioDeviceTransportTypeUSB ? "USB" : "Bluetooth"
            result["status"]="PASS";try save("two independent physical input endpoints selected with the shipping backend")
        } catch {
            result["routes"]=rows
            result["status"]="FAIL";try save("the physical route check did not complete")
        }
        await audio.shutdown();try await store.close()
    }
}
