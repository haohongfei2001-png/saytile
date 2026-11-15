import AppKit
import SwiftUI

/// Host-owned preferences, shared rendering. The default is the existing panel,
/// not a new theme; missing preferences therefore leave both hosts unchanged.
public struct VoicePanelAppearance: Codable, Equatable, Sendable {
    public var panelColor: PanelColorPreset
    public var buttonColor: PanelButtonColorPreset
    public var opacity: PanelOpacityPreset
    public var textSize: PanelTextSizePreset

    public init(panelColor: PanelColorPreset = .original, buttonColor: PanelButtonColorPreset = .violet,
                opacity: PanelOpacityPreset = .original, textSize: PanelTextSizePreset = .standard) {
        self.panelColor = panelColor
        self.buttonColor = buttonColor
        self.opacity = opacity
        self.textSize = textSize
    }
}

public enum PanelColorPreset: String, CaseIterable, Codable, Sendable {
    case original, blue, warm
    public var title: String {
        switch self { case .original: "原色"; case .blue: "雾蓝"; case .warm: "暖白" }
    }
    public var color: Color {
        switch self {
        case .original: .white
        case .blue: Color(red: 0.90, green: 0.95, blue: 1)
        case .warm: Color(red: 1, green: 0.965, blue: 0.92)
        }
    }
}

public enum PanelButtonColorPreset: String, CaseIterable, Codable, Sendable {
    case violet, blue, graphite
    public var title: String {
        switch self { case .violet: "紫色"; case .blue: "蓝色"; case .graphite: "石墨" }
    }
    public var color: Color { Color(nsColor: nsColor) }
    var nsColor: NSColor {
        switch self {
        case .violet: NSColor(srgbRed: 0.55, green: 0.23, blue: 0.98, alpha: 1)
        case .blue: NSColor(srgbRed: 0.16, green: 0.35, blue: 0.78, alpha: 1)
        case .graphite: NSColor(srgbRed: 0.28, green: 0.30, blue: 0.35, alpha: 1)
        }
    }
    var glyph: LinearGradient {
        switch self {
        case .violet: ReferencePanelStyle.glyph
        case .blue: LinearGradient(colors: [Color(red: 0.26, green: 0.47, blue: 0.91), color], startPoint: .top, endPoint: .bottom)
        case .graphite: LinearGradient(colors: [Color(red: 0.42, green: 0.45, blue: 0.50), color], startPoint: .top, endPoint: .bottom)
        }
    }
    var copyInk: Color { self == .violet ? ReferencePanelStyle.copyInk : color }
    var controlFill: Color {
        switch self {
        case .violet: .white
        case .blue: Color(red: 0.94, green: 0.97, blue: 1)
        case .graphite: Color(red: 0.95, green: 0.96, blue: 0.97)
        }
    }
}

public enum PanelOpacityPreset: String, CaseIterable, Codable, Sendable {
    case original, mist, dense, opaque
    public var title: String {
        switch self { case .original: "通透（默认）"; case .mist: "柔雾"; case .dense: "浓雾"; case .opaque: "不透明" }
    }

    /// Fullscreen and the system accessibility preference may strengthen the
    /// chosen material, but can never make an opaque selection transparent.
    func material(fullscreen: Bool, reduceTransparency: Bool) -> VoicePanelMaterial {
        let normal: VoicePanelMaterial
        switch self {
        case .original: normal = .init(cardWash: 0.42, cardBlur: 0.10, railWash: 0.27, railBlur: 0.12)
        case .mist: normal = .init(cardWash: 0.58, cardBlur: 0.35, railWash: 0.43, railBlur: 0.35)
        case .dense: normal = .init(cardWash: 0.76, cardBlur: 0.65, railWash: 0.65, railBlur: 0.65)
        case .opaque: normal = .init(cardWash: 1, cardBlur: 1, railWash: 1, railBlur: 1)
        }
        if reduceTransparency {
            return .init(cardWash: 1, cardBlur: 1, railWash: max(0.94, normal.railWash), railBlur: 1)
        }
        guard fullscreen else { return normal }
        return .init(cardWash: max(0.64, normal.cardWash), cardBlur: max(0.85, normal.cardBlur),
                     railWash: max(0.50, normal.railWash), railBlur: max(0.80, normal.railBlur))
    }
}

struct VoicePanelMaterial: Equatable, Sendable {
    let cardWash, cardBlur, railWash, railBlur: Double
}

public enum PanelTextSizePreset: String, CaseIterable, Codable, Sendable {
    case small, standard, large, extraLarge
    public var title: String {
        switch self { case .small: "小"; case .standard: "默认"; case .large: "大"; case .extraLarge: "特大" }
    }
    public var pointSize: CGFloat {
        switch self { case .small: 12; case .standard: 14.04; case .large: 16; case .extraLarge: 18 }
    }
    var typeScale: CGFloat { self == .standard ? 0.72 : pointSize / ReferencePanelStyle.fontSize }
}

private struct VoicePanelAppearanceKey: EnvironmentKey {
    static let defaultValue = VoicePanelAppearance()
}

public extension EnvironmentValues {
    var voicePanelAppearance: VoicePanelAppearance {
        get { self[VoicePanelAppearanceKey.self] }
        set { self[VoicePanelAppearanceKey.self] = newValue }
    }
}
