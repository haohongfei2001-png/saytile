import Foundation

public enum SaytileStorageProfile: Sendable {
    case standard, personal, designExperience, sharedVoicePreview, mandarinCandidate, privateArchiveCandidate

    public static let privateArchiveCandidateID = "app.saytile.mac.icloud-candidate"
    public static let mandarinCandidateID = "app.saytile.mac.mandarin-candidate"
    public static let sharedVoiceBundleID = "app.saytile.mac.shared-voice-preview"
    public static let designBundleID = "app.saytile.mac.design-experience"
    public static let current: Self = {
        if Bundle.main.bundleIdentifier == privateArchiveCandidateID { return .privateArchiveCandidate }
        if Bundle.main.bundleIdentifier == mandarinCandidateID { return .mandarinCandidate }
        if Bundle.main.bundleIdentifier == sharedVoiceBundleID { return .sharedVoicePreview }
        if Bundle.main.bundleIdentifier == designBundleID { return .designExperience }
        return Bundle.main.object(forInfoDictionaryKey: "SaytilePersonalExperience") as? Bool == true ? .personal : .standard
    }()
    private var suite: String? {
        switch self { case .standard: nil; case .personal: "app.saytile.mac.personal"; case .designExperience: Self.designBundleID; case .sharedVoicePreview: Self.sharedVoiceBundleID; case .mandarinCandidate: Self.mandarinCandidateID; case .privateArchiveCandidate: Self.privateArchiveCandidateID }
    }
    public var archiveDirectory: URL {
        let folder = switch self { case .standard: "Saytile"; case .personal: "Saytile Personal"; case .designExperience: "Saytile Design Experience"; case .sharedVoicePreview: "Saytile Shared Voice Preview"; case .mandarinCandidate: "Saytile Mandarin Candidate"; case .privateArchiveCandidate: "Saytile iCloud Candidate" }
        return FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent(folder, isDirectory: true)
    }
    public var preferences: UserDefaults { suite.flatMap(UserDefaults.init(suiteName:)) ?? .standard }
    var byokService: String { suite.map { $0 + ".byok.v1" } ?? "com.saytile.byok.v1" }
    var hostedService: String { suite.map { $0 + ".hosted.auth.v1" } ?? "com.saytile.hosted.auth.v1" }
    static var languagePreferences: UserDefaults? { CommandLine.arguments.contains("--data-directory") ? nil : current.preferences }
}
