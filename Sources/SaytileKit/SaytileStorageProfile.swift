import Foundation

/// Ordinary launches retain the product bundle ID. The signed experience package
/// reuses the separate archive and credential services established by build 261.
public enum SaytileStorageProfile: Sendable {
    case standard, personal

    public static let current: Self = Bundle.main.object(forInfoDictionaryKey: "SaytilePersonalExperience") as? Bool == true ? .personal : .standard

    public var archiveDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(self == .personal ? "Saytile Personal" : "Saytile", isDirectory: true)
    }

    public var preferences: UserDefaults {
        self == .personal ? UserDefaults(suiteName: "app.saytile.mac.personal")! : .standard
    }

    var byokService: String {
        self == .personal ? "app.saytile.mac.personal.byok.v1" : "com.saytile.byok.v1"
    }

    var hostedService: String {
        self == .personal ? "app.saytile.mac.personal.hosted.auth.v1" : "com.saytile.hosted.auth.v1"
    }

    static var languagePreferences: UserDefaults? {
        CommandLine.arguments.contains("--data-directory") ? nil : current.preferences
    }
}
