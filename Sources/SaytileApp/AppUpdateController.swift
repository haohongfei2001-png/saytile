import AppKit
import Combine
import SaytileKit
#if canImport(Sparkle)
import Sparkle

/// One updater for the process. Sparkle owns download, validation and installation;
/// the app's normal asynchronous termination owns durable recording/draft shutdown.
@MainActor
final class AppUpdateController: NSObject, SPUUpdaterDelegate, @preconcurrency SPUStandardUserDriverDelegate {
    private weak var model: AppModel?
    private var updater: SPUUpdater?
    private var observations: [NSKeyValueObservation] = []
    private var configuration: AppUpdateConfiguration?
    private var availableVersion: String?

    init(model: AppModel, bundle: Bundle = .main, isolatedFixture: Bool = false,
         userDriver: (any SPUUserDriver)? = nil) {
        self.model = model
        super.init()
        do {
            configuration = try AppUpdateConfiguration(info: bundle.infoDictionary ?? [:],
                bundleID: bundle.bundleIdentifier, isolatedFixture: isolatedFixture)
            let driver = userDriver ?? SPUStandardUserDriver(hostBundle: bundle, delegate: self)
            let updater = SPUUpdater(hostBundle: bundle, applicationBundle: bundle, userDriver: driver, delegate: self)
            self.updater = updater
            updater.sendsSystemProfile = false
            try updater.start()
            model.updateConfigured = true
            model.updateStatus = "安装新版本前会征求你的确认。"
            model.checkForUpdates = { [weak self] in self?.checkForUpdates() }
            model.setAutomaticUpdateChecks = { [weak self] enabled in
                self?.updater?.automaticallyChecksForUpdates = enabled
                self?.publish()
            }
            observations = [
                updater.observe(\.canCheckForUpdates, options: [.initial, .new]) { [weak self] _, _ in
                    Task { @MainActor in self?.publish() }
                },
                updater.observe(\.automaticallyChecksForUpdates, options: [.initial, .new]) { [weak self] _, _ in
                    Task { @MainActor in self?.publish() }
                }
            ]
            publish()
        } catch {
            model.updateStatus = error.localizedDescription
            model.updateConfigured = false
            model.canCheckForUpdates = false
        }
    }

    func checkForUpdates() {
        guard let updater, updater.canCheckForUpdates else { return }
        model?.updateStatus = availableVersion.map { "发现新版本 \($0)，可查看并安装。" } ?? "正在检查更新…"
        updater.checkForUpdates()
        publish()
    }
    private func publish() {
        model?.canCheckForUpdates = updater?.canCheckForUpdates ?? false
        model?.automaticUpdateChecks = updater?.automaticallyChecksForUpdates ?? false
    }
    func feedURLString(for updater: SPUUpdater) -> String? { configuration?.feedURL.absoluteString }
    func allowedSystemProfileKeys(for updater: SPUUpdater) -> [String]? { [] }
    func updaterShouldDownloadReleaseNotes(_ updater: SPUUpdater) -> Bool { false }

    func updater(_ updater: SPUUpdater, shouldProceedWithUpdate item: SUAppcastItem, updateCheck: SPUUpdateCheck) throws {
        guard item.signingValidationStatus == .succeeded else {
            throw AppUpdateConfiguration.Failure.signature
        }
        let info = updater.hostBundle.infoDictionary ?? [:]
        guard let version = info["CFBundleShortVersionString"] as? String,
              let build = info["CFBundleVersion"] as? String,
              AppUpdateConfiguration.isUpgrade(from: version, build: build,
                  to: item.displayVersionString, build: item.versionString) else {
            throw NSError(domain: "app.saytile.updates", code: 1,
                userInfo: [NSLocalizedDescriptionKey: "更新版本未通过校验，已保留当前版本。"])
        }
    }

    func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) {
        availableVersion = item.displayVersionString
        model?.updateStatus = "发现新版本 \(item.displayVersionString)"
        model?.updateActionTitle = "查看更新…"
    }
    func updaterDidNotFindUpdate(_ updater: SPUUpdater, error: Error) {
        availableVersion = nil
        // An empty feed says no published update, not that all engineering work is released.
        model?.updateStatus = "暂无可用更新。"
        model?.updateActionTitle = "检查更新…"
    }
    func updater(_ updater: SPUUpdater, didAbortWithError error: Error) {
        availableVersion = nil
        let code = (error as NSError).code
        if (error as NSError).domain == SUSparkleErrorDomain && code == 1001 {
            model?.updateStatus = "暂无可用更新。"
        } else if (error as NSError).domain == SUSparkleErrorDomain && code == 4007 {
            model?.updateStatus = "已取消更新，当前版本仍可使用。"
        } else if (error as NSError).domain == SUSparkleErrorDomain && code == 4008 {
            model?.updateStatus = "已暂缓安装，当前版本仍可使用。"
        } else {
            model?.updateStatus = "更新未完成：\(error.localizedDescription)"
        }
        model?.updateActionTitle = "检查更新…"
        publish()
    }
    func updater(_ updater: SPUUpdater, didFinishUpdateCycleFor updateCheck: SPUUpdateCheck, error: Error?) {
        publish()
    }

    // Scheduled discoveries only change the existing settings/menu entry. They
    // never focus a window, stop capture, or install while the user is speaking.
    var supportsGentleScheduledUpdateReminders: Bool { true }
    func standardUserDriverShouldHandleShowingScheduledUpdate(_ update: SUAppcastItem, andInImmediateFocus immediateFocus: Bool) -> Bool { false }
    func standardUserDriverWillHandleShowingUpdate(_ handleShowingUpdate: Bool, forUpdate update: SUAppcastItem, state: SPUUserUpdateState) {
        availableVersion = update.displayVersionString
        if !handleShowingUpdate {
            model?.updateStatus = "发现新版本 \(update.displayVersionString)，可在这里查看并安装。"
            model?.updateActionTitle = "查看更新…"
        }
    }
    func standardUserDriverWillFinishUpdateSession() {
        if model?.updateStatus == "正在检查更新…" { model?.updateStatus = "安装新版本前会征求你的确认。" }
        availableVersion = nil
        model?.updateActionTitle = "检查更新…"
        publish()
    }
}
#endif
