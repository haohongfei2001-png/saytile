import AppKit
import Foundation
import Darwin
@testable import SaytileKit

@MainActor final class Observation {
    let controller: AudioController
    let file: FileHandle
    let appPID: pid_t
    var tokens:[NSObjectProtocol] = []
    init(controller: AudioController, output: String, pid: pid_t) throws {
        self.controller = controller
        self.appPID = pid
        guard FileManager.default.createFile(atPath: output, contents: nil) else { throw CocoaError(.fileWriteUnknown) }
        file = try FileHandle(forWritingTo: URL(fileURLWithPath: output))
        for (name,label) in [(NSWorkspace.willSleepNotification,"willSleep"),(NSWorkspace.didWakeNotification,"didWake"),(NSWorkspace.sessionDidBecomeActiveNotification,"sessionActive"),(NSWorkspace.sessionDidResignActiveNotification,"sessionInactive")] {
            tokens.append(NSWorkspace.shared.notificationCenter.addObserver(forName:name,object:nil,queue:.main){ [weak self] _ in
                Task { @MainActor in
                    self?.record(label)
                    try? await Task.sleep(for:.milliseconds(300))
                    self?.record(label+"Settled")
                }
            })
        }
    }
    func record(_ label: String) {
        func kernelDate(_ name: String) -> Double? {
            var value = timeval()
            var size = MemoryLayout<timeval>.size
            guard sysctlbyname(name,&value,&size,nil,0) == 0 else { return nil }
            return Double(value.tv_sec) + Double(value.tv_usec)/1e6
        }
        let row:[String:Any] = ["unix":Date().timeIntervalSince1970,"event":label,"controller_state":String(describing:controller.state),"issue":controller.issue ?? "","is_running":controller.state.isRunning,"same_app_pid_alive":kill(appPID,0)==0,"kernel_sleep":kernelDate("kern.sleeptime") as Any,"kernel_wake":kernelDate("kern.waketime") as Any]
        if let json = try? JSONSerialization.data(withJSONObject:row) {
            try? file.write(contentsOf:json+Data([10]))
            try? file.synchronize()
        }
    }
}
@main struct Probe {
    @MainActor static func main() async throws {
        let args = CommandLine.arguments
        let store = try SaytileStore(directory:URL(fileURLWithPath:args[2]))
        let controller = AudioController(store:store,startupRecoveryReady:false)
        controller.selectDevice(uid:"app.saytile.test.absent."+UUID().uuidString)
        await controller.start(requestPermission:false)
        guard !controller.state.isRunning else { throw CocoaError(.validationMissingMandatoryProperty) }
        let group = try Observation(controller:controller,output:args[3],pid:Int32(args[4])!)
        group.record("armed")
        if args[1] == "controlled" {
            let center = NSWorkspace.shared.notificationCenter
            center.post(name:NSWorkspace.willSleepNotification,object:nil)
            try await Task.sleep(for:.milliseconds(600))
            guard controller.issue == "Mac 已睡眠" else { throw CocoaError(.validationMissingMandatoryProperty) }
            center.post(name:NSWorkspace.didWakeNotification,object:nil)
            try await Task.sleep(for:.milliseconds(600))
            guard controller.issue?.contains("未连接") == true && !controller.state.isRunning else { throw CocoaError(.validationMissingMandatoryProperty) }
            await controller.pause()
            group.record("intentionalPauseBeforeSleep")
            center.post(name:NSWorkspace.willSleepNotification,object:nil)
            try await Task.sleep(for:.milliseconds(600))
            guard controller.state == .paused else { throw CocoaError(.validationMissingMandatoryProperty) }
            group.record("intentionalPauseDuringSleep")
            center.post(name:NSWorkspace.didWakeNotification,object:nil)
            try await Task.sleep(for:.milliseconds(600))
            guard controller.state == .paused else { throw CocoaError(.validationMissingMandatoryProperty) }
        } else {
            await controller.pause()
            group.record("observingPausedController")
            while Date().timeIntervalSince1970 < Double(args[5])! {
                try await Task.sleep(for:.seconds(30))
                if kill(group.appPID,0) != 0 { break }
            }
        }
        group.record("finished")
        await controller.pause()
        try await store.close()
        withExtendedLifetime(group) {}
    }
}
