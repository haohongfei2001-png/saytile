import AppKit
import Foundation
@testable import SaytileKit

@main struct PausedWake {
    @MainActor static func main() async throws {
        let store = try SaytileStore(directory:URL(fileURLWithPath:CommandLine.arguments[1]))
        let audio = AudioController(store:store,startupRecoveryReady:false)
        let center = NSWorkspace.shared.notificationCenter
        let initial = String(describing:audio.state)
        center.post(name:NSWorkspace.willSleepNotification,object:nil)
        try await Task.sleep(for:.milliseconds(350))
        let asleep = String(describing:audio.state)
        center.post(name:NSWorkspace.didWakeNotification,object:nil)
        try await Task.sleep(for:.milliseconds(500))
        let records = try await store.listRecordings(limit:1)
        let output:[String:Any] = ["scope":"Local NSWorkspace notification delivery to the production controller with no prior capture request","initial":initial,"sleep":asleep,"wake":String(describing:audio.state),"issue_after_wake":audio.issue ?? "","is_running":audio.state.isRunning,"records":records.count,"pause_label_preserved":audio.state == .paused]
        print(String(data:try JSONSerialization.data(withJSONObject:output),encoding:.utf8)!)
        await audio.pause()
        try await store.close()
    }
}
