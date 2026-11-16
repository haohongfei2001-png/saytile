import Foundation

/// The host persists this separately from panel preferences. Missing/unknown values
/// preserve the installed purple appearance, including a user's custom controls.
public enum BrandAppearance: String, CaseIterable, Codable, Identifiable, Sendable {
    case purple, black
    public var id: Self { self }
    public static let preferenceKey = "brandAppearance.v1"
    public var title: String { self == .purple ? "原紫色" : "黑色" }

    public static func load(from preferences: UserDefaults) -> Self {
        preferences.string(forKey: preferenceKey).flatMap(Self.init(rawValue:)) ?? .purple
    }
    public func save(to preferences: UserDefaults) {
        preferences.set(rawValue, forKey: Self.preferenceKey)
    }
}
