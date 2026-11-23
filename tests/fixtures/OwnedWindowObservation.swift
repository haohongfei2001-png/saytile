import AppKit
import Darwin

// Read only the explicitly supplied disposable fixture process's window metadata.
// No titles, other application contents, AX, screen capture, focus or input.
let pid = Int32(CommandLine.arguments[1])!
let start = ProcessInfo.processInfo.systemUptime
while kill(pid, 0) == 0 {
    let windows = (CGWindowListCopyWindowInfo(.optionAll, kCGNullWindowID) as? [[String: Any]] ?? [])
        .filter { ($0[kCGWindowOwnerPID as String] as? Int32) == pid }
        .map { entry in
            Dictionary(uniqueKeysWithValues: [kCGWindowNumber, kCGWindowLayer, kCGWindowIsOnscreen, kCGWindowAlpha, kCGWindowBounds]
                .compactMap { key in entry[key as String].map { (key as String, $0) } })
        }
    let data = try JSONSerialization.data(withJSONObject: ["uptime": ProcessInfo.processInfo.systemUptime,
                                                          "elapsed": ProcessInfo.processInfo.systemUptime - start,
                                                          "windows": windows], options: [.sortedKeys])
    FileHandle.standardOutput.write(data + Data([10]))
    Thread.sleep(forTimeInterval: 0.1)
}
