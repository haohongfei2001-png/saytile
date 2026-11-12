import AppKit

/// Each menu owns its action items until AppKit finishes dispatch. No global
/// key equivalents or focus changes are required to invoke these commands.
@MainActor
final class TranscriptMenuItem: NSMenuItem {
    private let invoke: @MainActor () -> Void
    init(title: String, identifier: String, action: @escaping @MainActor () -> Void) {
        invoke = action
        super.init(title: title, action: #selector(performCommand), keyEquivalent: "")
        self.identifier = .init(identifier); setAccessibilityIdentifier(identifier)
        target = self
    }
    required init(coder: NSCoder) { fatalError("TranscriptMenuItem is created programmatically") }
    @objc private func performCommand() { invoke() }
}
