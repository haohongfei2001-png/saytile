import AppKit
func mark(_ value: String) { FileHandle.standardError.write(Data((value + "\n").utf8)) }
@main struct Entry {
    @MainActor static func main() throws {
        let app = NSApplication.shared
        app.setActivationPolicy(.prohibited)
        guard let path = Bundle.main.path(forResource: "Saytile", ofType: "icns"), let supplied = NSImage(contentsOfFile: path) else { exit(2) }
        mark("local_icon_loaded")
        app.applicationIconImage = supplied
        mark("application_icon_set")
        let named = NSImage(named: NSImage.applicationIconName)
        mark("standard_named_icon_returned")
        let value: [String: Any] = ["application_property_identity": app.applicationIconImage === supplied, "named_image_identity": named === supplied, "active": app.isActive, "windows": app.windows.count, "activation_policy": "prohibited", "ui_created": false]
        let data = try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys])
        FileHandle.standardOutput.write(data)
    }
}
