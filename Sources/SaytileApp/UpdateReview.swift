import AppKit
import Darwin
import Foundation
import Security
import SaytileKit
import SwiftUI
#if canImport(Sparkle)
import Sparkle
#endif

/// Only disposable, re-signed app copies may carry this marker. Sparkle relaunches
/// without the original argv, so resolve isolation before constructing AppModel.
struct UpdateReviewRequest {
    let root: URL
    let directory: URL
    let preferencesSuite: String
    let eventLog: URL
    let sessionID: String
    let phase: String
    let scenario: String

    var preferences: UserDefaults { UserDefaults(suiteName: preferencesSuite)! }

    static func resolve(bundle: Bundle = .main, arguments: [String] = CommandLine.arguments) throws -> Self? {
        let requested = arguments.contains("--update-review")
        guard let marker = bundle.object(forInfoDictionaryKey: "SaytileUpdateReview") as? [String: String] else {
            if requested { throw Failure("A signed disposable update fixture is required") }
            return nil
        }
        guard let id = marker["sessionID"], id.range(of: "^[0-9a-f]{32}$", options: .regularExpression) != nil,
              bundle.bundleIdentifier == "app.saytile.update-fixture." + id,
              let rootPath = marker["root"], rootPath == "/private/tmp/saytile-native-update-" + id,
              let dataPath = marker["dataDirectory"], dataPath == rootPath + "/archive",
              let logPath = marker["eventLog"], logPath == rootPath + "/events.jsonl",
              marker["preferencesSuite"] == "app.saytile.update-fixture." + id + ".preferences",
              marker["expectedSource"] == bundle.object(forInfoDictionaryKey: "SaytileSourceRevision") as? String,
              marker["expectedSource"]?.range(of: "^[0-9a-f]{40}$", options: .regularExpression) != nil,
              let phase = marker["phase"], ["check", "relaunch", "public-empty"].contains(phase) else {
            throw Failure("Invalid update fixture identity or paths")
        }
        let root = URL(fileURLWithPath: rootPath, isDirectory: true)
        let directory = URL(fileURLWithPath: dataPath, isDirectory: true)
        let eventLog = URL(fileURLWithPath: logPath)
        let bundlePath = temporaryAlias(bundle.bundleURL.standardizedFileURL.path)
        guard try canonicalPath(root) == rootPath,
              bundlePath == rootPath + "/Applications/Saytile.app",
              try canonicalPath(bundle.bundleURL) == bundlePath else {
            throw Failure("Update review must run from its owned disposable installation")
        }
        for path in [rootPath, rootPath + "/Applications", bundlePath] {
            var entry = stat()
            guard Darwin.lstat(path, &entry) == 0, entry.st_mode & S_IFMT == S_IFDIR,
                  entry.st_uid == getuid() else { throw Failure("Update fixture directory is aliased or not owned") }
        }
        let attributes = try FileManager.default.attributesOfItem(atPath: rootPath)
        guard attributes[.type] as? FileAttributeType == .typeDirectory,
              (attributes[.ownerAccountID] as? NSNumber)?.uint32Value == getuid(),
              (attributes[.posixPermissions] as? NSNumber)?.intValue == 0o700 else {
            throw Failure("Update fixture root must be private and owned by the current user")
        }
        try DiagnosticDirectory.validate(directory: directory)
        guard try canonicalPath(directory) == dataPath,
              try canonicalPath(eventLog, allowMissingLeaf: true) == logPath else { throw Failure("Symlinked update fixture") }
        var code: SecStaticCode?
        guard SecStaticCodeCreateWithPath(bundle.bundleURL as CFURL, [], &code) == errSecSuccess,
              let code, SecStaticCodeCheckValidity(code, SecCSFlags(rawValue: kSecCSStrictValidate), nil) == errSecSuccess else {
            throw Failure("Update fixture signature did not validate")
        }
        let scenario: String
        if phase == "check" || phase == "public-empty" {
            let allowed = phase == "check" ? ["corrupt", "valid"] : ["public-empty"]
            guard requested,
                  let index = arguments.firstIndex(of: "--data-directory"), arguments.count > index + 1,
                  arguments[index + 1] == dataPath,
                  let mode = arguments.firstIndex(of: "--update-review-case"), arguments.count > mode + 1,
                  allowed.contains(arguments[mode + 1]),
                  bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String == (phase == "check" ? "1" : "2") else {
                throw Failure("Source update review requires its explicit isolated directory and case")
            }
            scenario = arguments[mode + 1]
        } else {
            guard !requested, !arguments.contains("--data-directory"),
                  bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String == "2" else {
                throw Failure("Target update review must be a genuine argument-free Sparkle relaunch")
            }
            scenario = "valid"
        }
        return Self(root: root, directory: directory, preferencesSuite: marker["preferencesSuite"]!,
                    eventLog: eventLog, sessionID: id, phase: phase, scenario: scenario)
    }

    struct Failure: LocalizedError {
        let message: String
        init(_ message: String) { self.message = message }
        var errorDescription: String? { message }
    }

    // Foundation may spell the canonical macOS temporary volume as /tmp even
    // after resolving symlinks. POSIX realpath preserves the actual /private/tmp
    // ownership boundary. No other aliases or arbitrary symlinks are accepted.
    private static func temporaryAlias(_ path: String) -> String {
        path.hasPrefix("/tmp/") ? "/private" + path : path
    }
    private static func canonicalPath(_ url: URL, allowMissingLeaf: Bool = false) throws -> String {
        if let path = Darwin.realpath(url.path, nil) {
            defer { free(path) }
            return String(cString: path)
        }
        guard allowMissingLeaf, errno == ENOENT,
              let parent = Darwin.realpath(url.deletingLastPathComponent().path, nil) else {
            throw Failure("Cannot resolve update fixture ownership")
        }
        defer { free(parent) }
        return String(cString: parent) + "/" + url.lastPathComponent
    }
}

#if canImport(Sparkle)
/// A deterministic *user driver* for a real host-app SPUUpdater. This does not
/// replace Sparkle networking, signature verification, installation or relaunch.
/// It is never reachable in the ordinary app or from a command-line flag alone.
@MainActor
final class UpdateReviewSession: NSObject, SPUUserDriver {
    private let model: AppModel
    private let request: UpdateReviewRequest
    private let bundle: Bundle
    private var controller: AppUpdateController?
    private var deadline: Task<Void, Never>?
    private var finished = false
    private var downloadedBytes: UInt64 = 0

    init(model: AppModel, request: UpdateReviewRequest, bundle: Bundle = .main) {
        self.model = model; self.request = request; self.bundle = bundle
        super.init()
    }

    func start() async {
        NSApp.setActivationPolicy(.prohibited)
        await model.initialLoad()
        event("launched", ["source": bundle.object(forInfoDictionaryKey: "SaytileSourceRevision") as? String ?? "",
                           "build": bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "",
                           "explicit_data_argument": CommandLine.arguments.contains("--data-directory")])
        let expectedCanary = "disposable-update-" + request.sessionID
        let prefs = request.preferences
        if request.phase == "check", request.scenario == "corrupt" {
            guard prefs.object(forKey: "updateReview.canary") == nil else { finish(false, "Fixture preference was not initially empty"); return }
            prefs.set(expectedCanary, forKey: "updateReview.canary")
            guard prefs.synchronize() else { finish(false, "Preference write did not synchronize"); return }
        }
        guard prefs.string(forKey: "updateReview.canary") == expectedCanary else {
            finish(false, "Preference canary did not survive the prior process"); return
        }
        do {
            let rows = try await model.store.listRecordings(limit: 10)
            var versions = 0
            for row in rows { versions += try await model.store.revisions(recordingID: row.id).count }
            guard rows.count == 2, versions == 4, rows.allSatisfy({ $0.isPinned }) else {
                finish(false, "Synthetic archive record/revision/star counts changed"); return
            }
            event("archive_loaded", ["recordings": rows.count, "revisions": versions, "pinned": rows.filter(\.isPinned).count,
                                      "preferences_preserved": true])
        } catch { finish(false, "Cannot load synthetic archive"); return }
        controller = AppUpdateController(model: model, bundle: bundle, isolatedFixture: true, userDriver: self)
        guard model.updateConfigured, let check = model.checkForUpdates else {
            finish(false, "App update controller was not configured"); return
        }
        event("app_check_action", ["configured": true])
        deadline = Task { [weak self] in
            try? await Task.sleep(for: .seconds(150))
            guard !Task.isCancelled else { return }
            self?.finish(false, "Native update cycle timed out")
        }
        if request.phase == "public-empty" {
            do { try await checkThroughNativeSettings() }
            catch { finish(false, "Native settings action failed: \(error.localizedDescription)") }
        } else { check() }
    }

    /// Render the actual product page, then dispatch its actual accessibility
    /// button action. No replacement UI, direct model call, global key or focus.
    private func checkThroughNativeSettings() async throws {
        let before = NSWorkspace.shared.frontmostApplication?.processIdentifier
        let ownPID = ProcessInfo.processInfo.processIdentifier
        let focus = UpdateReviewFocus()
        let observer = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { note in
            if let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
               app.processIdentifier == ownPID {
                MainActor.assumeIsolated { focus.activated = true }
            }
        }
        defer { NSWorkspace.shared.notificationCenter.removeObserver(observer) }
        NSApp.setActivationPolicy(.accessory)
        defer { NSApp.setActivationPolicy(.prohibited) }
        let size = CGSize(width: 920, height: 680)
        let panel = UpdateReviewPanel(contentRect: CGRect(origin: .zero, size: size),
            styleMask: [.titled, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.title = "Saytile isolated native update settings"
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.ignoresMouseEvents = true
        let host = NSHostingView(rootView: SettingsView(model: model, initialPage: .about).preferredColorScheme(.light))
        panel.contentView = host
        panel.setContentSize(size)
        panel.setFrameOrigin(NSPoint(x: (NSScreen.screens.map { $0.frame.maxX }.max() ?? 0) + 64, y: 0))
        guard NSScreen.screens.allSatisfy({ !$0.frame.intersects(panel.frame) }) else {
            throw UpdateReviewRequest.Failure("Native settings fixture intersects a physical display")
        }
        panel.orderBack(nil)
        defer { panel.orderOut(nil); panel.close() }
        var checks: [any NSAccessibilityProtocol] = [], toggles: [any NSAccessibilityProtocol] = []
        for _ in 0..<50 {
            host.layoutSubtreeIfNeeded()
            checks = accessibilityNodes("settings.checkForUpdates", in: host)
            toggles = accessibilityNodes("settings.automaticUpdates", in: host)
            if checks.count == 1, toggles.count == 1, checks[0].isAccessibilityEnabled() { break }
            try await Task.sleep(for: .milliseconds(40))
        }
        guard checks.count == 1, toggles.count == 1, checks[0].isAccessibilityEnabled(),
              toggles[0].isAccessibilityEnabled(), checks[0].accessibilityRole() == .button,
              !panel.canBecomeKey, !panel.canBecomeMain, !panel.isKeyWindow, !panel.isMainWindow,
              !focus.activated, NSWorkspace.shared.frontmostApplication?.processIdentifier != ownPID else {
            throw UpdateReviewRequest.Failure("Unique enabled update controls or keyboard isolation were not verified")
        }
        guard let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds) else {
            throw UpdateReviewRequest.Failure("Cannot capture the native settings view")
        }
        host.cacheDisplay(in: host.bounds, to: bitmap)
        guard let image = bitmap.representation(using: .png, properties: [:]) else {
            throw UpdateReviewRequest.Failure("Cannot encode native settings evidence")
        }
        try image.write(to: request.root.appendingPathComponent("native-settings-about.png"), options: .atomic)
        let pressed = checks[0].accessibilityPerformPress()
        guard pressed else { throw UpdateReviewRequest.Failure("Native check-for-updates AXPress was rejected") }
        guard !focus.activated, !panel.isKeyWindow, !panel.isMainWindow,
              NSWorkspace.shared.frontmostApplication?.processIdentifier != ownPID else {
            throw UpdateReviewRequest.Failure("Native settings action activated the fixture")
        }
        event("settings_control", ["identifier": "settings.checkForUpdates", "action": "accessibilityPerformPress",
            "pressed": pressed, "automatic_updates_control_present": true,
            "width_points": host.bounds.width, "height_points": host.bounds.height,
            "width_pixels": bitmap.pixelsWide, "height_pixels": bitmap.pixelsHigh,
            "candidate_activated": focus.activated,
            "foreground_unchanged": before == NSWorkspace.shared.frontmostApplication?.processIdentifier])
    }

    private func accessibilityNodes(_ identifier: String, in root: NSView) -> [any NSAccessibilityProtocol] {
        var queue: [AnyObject] = [root], visited = Set<ObjectIdentifier>()
        var matches: [any NSAccessibilityProtocol] = []
        while let object = queue.popLast(), visited.count < 4096 {
            guard visited.insert(ObjectIdentifier(object)).inserted else { continue }
            if let node = object as? any NSAccessibilityProtocol {
                if node.accessibilityIdentifier() == identifier { matches.append(node) }
                queue += (node.accessibilityChildren() ?? []).map { $0 as AnyObject }
            }
            if let view = object as? NSView { queue += view.subviews }
        }
        return matches
    }

    private func event(_ name: String, _ fields: [String: Any] = [:]) {
        var record = fields
        record["event"] = name; record["pid"] = ProcessInfo.processInfo.processIdentifier
        record["phase"] = request.phase; record["case"] = request.scenario
        record["timestamp"] = Date.now.timeIntervalSince1970
        do {
            var bytes = try JSONSerialization.data(withJSONObject: record, options: [.sortedKeys])
            bytes.append(0x0A)
            if !FileManager.default.fileExists(atPath: request.eventLog.path) {
                guard FileManager.default.createFile(atPath: request.eventLog.path, contents: nil, attributes: [.posixPermissions: 0o600]) else {
                    throw UpdateReviewRequest.Failure("Cannot create fixture event receipt")
                }
            }
            let handle = try FileHandle(forWritingTo: request.eventLog)
            defer { try? handle.close() }
            try handle.seekToEnd(); try handle.write(contentsOf: bytes); try handle.synchronize()
        } catch {
            // Evidence loss must fail closed; never continue an unobservable install.
            print("NATIVE_UPDATE_REVIEW_RECEIPT_FAILURE")
            Darwin.exit(74)
        }
    }

    private func finish(_ pass: Bool, _ reason: String) {
        guard !finished else { return }
        finished = true; deadline?.cancel()
        event("complete", ["status": pass ? "PASS" : "FAIL", "reason": reason])
        // Use the ordinary async AppDelegate termination/save gate.
        NSApp.terminate(nil)
    }

    private func errorChain(_ error: Error) -> [[String: Any]] {
        var result: [[String: Any]] = [], item: NSError? = error as NSError
        for _ in 0..<8 {
            guard let value = item else { break }
            result.append(["domain": value.domain, "code": value.code])
            item = value.userInfo[NSUnderlyingErrorKey] as? NSError
        }
        return result
    }

    func show(_ request: SPUUpdatePermissionRequest, reply: @escaping (SUUpdatePermissionResponse) -> Void) {
        event("permission_request")
        reply(SUUpdatePermissionResponse(automaticUpdateChecks: false, sendSystemProfile: false))
    }
    func showUserInitiatedUpdateCheck(cancellation: @escaping () -> Void) { event("checking") }
    func showUpdateFound(with appcastItem: SUAppcastItem, state: SPUUserUpdateState, reply: @escaping (SPUUserUpdateChoice) -> Void) {
        event("update_found", ["version": appcastItem.versionString, "user_initiated": state.userInitiated,
                               "stage": state.stage.rawValue])
        guard request.phase == "check", appcastItem.versionString == "2", !appcastItem.isInformationOnlyUpdate else {
            reply(.dismiss); finish(false, "Unexpected update item"); return
        }
        reply(.install)
    }
    func showUpdateReleaseNotes(with downloadData: SPUDownloadData) { event("release_notes") }
    func showUpdateReleaseNotesFailedToDownloadWithError(_ error: Error) { event("release_notes_error", ["errors": errorChain(error)]) }
    func showUpdateNotFoundWithError(_ error: Error, acknowledgement: @escaping () -> Void) {
        event("no_update", ["errors": errorChain(error)])
        acknowledgement()
        let expected = request.phase == "relaunch" || request.phase == "public-empty"
        finish(expected, expected ? "Signed feed verified; no newer version available" : "Source failed to discover version 2")
    }
    func showUpdaterError(_ error: Error, acknowledgement: @escaping () -> Void) {
        let chain = errorChain(error)
        event("update_error", ["errors": chain])
        acknowledgement()
        let rejected = chain.contains { $0["domain"] as? String == SUSparkleErrorDomain && $0["code"] as? Int == 4005 }
        finish(request.scenario == "corrupt" && rejected, rejected ? "Sparkle rejected a corrupted signed archive" : "Unexpected native updater error")
    }
    func showDownloadInitiated(cancellation: @escaping () -> Void) { event("download_started") }
    func showDownloadDidReceiveExpectedContentLength(_ expectedContentLength: UInt64) { event("download_size", ["bytes": expectedContentLength]) }
    func showDownloadDidReceiveData(ofLength length: UInt64) { downloadedBytes += length }
    func showDownloadDidStartExtractingUpdate() { event("extracting", ["downloaded_bytes": downloadedBytes]) }
    func showExtractionReceivedProgress(_ progress: Double) {}
    func showReady(toInstallAndRelaunch reply: @escaping (SPUUserUpdateChoice) -> Void) {
        event("ready_to_install")
        guard request.scenario == "valid" else { reply(.skip); finish(false, "Corrupt archive reached installation"); return }
        reply(.install)
    }
    func showInstallingUpdate(withApplicationTerminated applicationTerminated: Bool, retryTerminatingApplication: @escaping () -> Void) {
        event("installing", ["application_terminated": applicationTerminated])
        // No forced quit or retry: the real AppDelegate must flush before replying.
    }
    func showUpdateInstalledAndRelaunched(_ relaunched: Bool, acknowledgement: @escaping () -> Void) {
        event("installed_callback", ["relaunched": relaunched]); acknowledgement()
    }
    func dismissUpdateInstallation() { event("dismissed") }
}

@MainActor private final class UpdateReviewPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}
@MainActor private final class UpdateReviewFocus {
    var activated = false
}
#endif
