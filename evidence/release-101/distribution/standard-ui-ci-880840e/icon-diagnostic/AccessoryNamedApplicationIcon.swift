import AppKit
func mark(_ value: String) { FileHandle.standardError.write(Data((value + "\n").utf8)) }
@main struct Entry {
    @MainActor static func main() throws {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        guard let path = Bundle.main.path(forResource: "Saytile", ofType: "icns"), let supplied = NSImage(contentsOfFile: path) else { exit(2) }
        mark("local_icon_loaded")
        let registered = supplied.setName(NSImage.applicationIconName)
        mark("real_icon_named registered=\(registered)")
        let named = NSImage(named: NSImage.applicationIconName)
        mark("standard_named_icon_returned")
        let value: [String: Any] = ["name_registered": registered, "named_image_identity": named === supplied, "active": app.isActive, "windows": app.windows.count, "activation_policy": "accessory", "ui_created": false]
        let data = try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys])
        FileHandle.standardOutput.write(data)
    }
}
