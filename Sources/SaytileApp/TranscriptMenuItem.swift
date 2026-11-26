import AppKit

/// AppKit may copy contextual menu items while preparing an NSTextView menu.
/// Keep the action target in representedObject, which travels with those copies,
/// instead of pointing at an original menu item that a refresh can release.
@MainActor
final class TranscriptMenuItem: NSMenuItem {
    init(title: String, identifier: String, action: @escaping @MainActor () -> Void) {
        let command = TranscriptMenuCommand(action: action)
        super.init(title: title, action: #selector(TranscriptMenuCommand.performCommand(_:)), keyEquivalent: "")
        self.identifier = .init(identifier); setAccessibilityIdentifier(identifier)
        representedObject = command
        target = command
    }
    required init(coder: NSCoder) { fatalError("TranscriptMenuItem is created programmatically") }
}

@MainActor
private final class TranscriptMenuCommand: NSObject {
    private let invoke: @MainActor () -> Void
    init(action: @escaping @MainActor () -> Void) { invoke = action; super.init() }
    @objc func performCommand(_ sender: NSMenuItem) { invoke() }
}
