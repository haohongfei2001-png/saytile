import Foundation

public enum SaytileStorageProfile: Sendable {
    case standard, personal, designExperience

    public static let designBundleID = "app.saytile.mac.design-experience"
    public static let current: Self = {
        if Bundle.main.bundleIdentifier == designBundleID { return .designExperience }
        return Bundle.main.object(forInfoDictionaryKey: "SaytilePersonalExperience") as? Bool == true ? .personal : .standard
    }()
    private var suite: String? {
        switch self { case .standard: nil; case .personal: "app.saytile.mac.personal"; case .designExperience: Self.designBundleID }
    }
    public var archiveDirectory: URL {
        let folder = switch self { case .standard: "Saytile"; case .personal: "Saytile Personal"; case .designExperience: "Saytile Design Experience" }
        return FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent(folder, isDirectory: true)
    }
    public var preferences: UserDefaults { suite.flatMap(UserDefaults.init(suiteName:)) ?? .standard }
    var byokService: String { suite.map { $0 + ".byok.v1" } ?? "com.saytile.byok.v1" }
    var hostedService: String { suite.map { $0 + ".hosted.auth.v1" } ?? "com.saytile.hosted.auth.v1" }
    static var languagePreferences: UserDefaults? { CommandLine.arguments.contains("--data-directory") ? nil : current.preferences }
}
