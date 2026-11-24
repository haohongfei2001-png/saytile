import AppKit
import Foundation
import Sparkle

// Only the model's presentation properties are substituted. The controller is
// compiled unchanged from Sources and delegates to the pinned real framework.
@MainActor final class AppModel {
    var updateConfigured = false
    var updateStatus = ""
    var canCheckForUpdates = false
    var automaticUpdateChecks = false
    var expectsUpdateRelaunch = false
    var updateActionTitle = ""
    var checkForUpdates: (() -> Void)?
    var setAutomaticUpdateChecks: (Bool) -> Void = { _ in }
}

@main struct AppUpdateControllerProbe {
    @MainActor static func main() {
        let model = AppModel()
        // The unbundled probe intentionally has no feed: no network/UI/keychain.
        let controller = AppUpdateController(model: model)
        let selector = NSSelectorFromString("updater:shouldDownloadReleaseNotesForUpdate:")
        let implementsNotesPolicy = controller.responds(to: selector)
        print("SPARKLE_RELEASE_NOTES_DELEGATE_IMPLEMENTED=\(implementsNotesPolicy)")
        precondition(!model.updateConfigured && !model.canCheckForUpdates)
        precondition(!model.expectsUpdateRelaunch)
        guard implementsNotesPolicy else { exit(1) }
    }
}
