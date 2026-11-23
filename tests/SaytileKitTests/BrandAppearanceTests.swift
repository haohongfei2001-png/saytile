import AppKit
import Foundation
import Testing
@testable import SaytileVoiceUI

@Suite @MainActor struct BrandAppearanceTests {
    @Test func isolatedPersistenceAndInvalidValueFallback() throws {
        let suite = "app.saytile.brand.tests." + UUID().uuidString
        let preferences = try #require(UserDefaults(suiteName: suite))
        defer { preferences.removePersistentDomain(forName: suite) }
        #expect(BrandAppearance.load(from: preferences) == .purple)
        BrandAppearance.black.save(to: preferences)
        #expect(BrandAppearance.load(from: preferences) == .black)
        BrandAppearance.purple.save(to: preferences)
        #expect(BrandAppearance.load(from: preferences) == .purple)
        preferences.set("future-theme", forKey: BrandAppearance.preferenceKey)
        #expect(BrandAppearance.load(from: preferences) == .purple)
        preferences.set(42, forKey: BrandAppearance.preferenceKey)
        #expect(BrandAppearance.load(from: preferences) == .purple)
    }

    @Test func blackIsAchromaticNotTheBlueGrayGraphitePreset() throws {
        let color = try #require(PanelButtonColorPreset.black.nsColor.usingColorSpace(.sRGB))
        #expect(color.redComponent == 0 && color.greenComponent == 0 && color.blueComponent == 0)
        #expect(color.alphaComponent == 1)
        #expect(PanelButtonColorPreset.black != .graphite)
    }

    @Test func allPanelChoicesSurviveBrandRoundTrip() throws {
        for panel in PanelColorPreset.allCases {
            for button in PanelButtonColorPreset.allCases {
                for opacity in PanelOpacityPreset.allCases {
                    for text in PanelTextSizePreset.allCases {
                        let saved = VoicePanelAppearance(panelColor: panel, buttonColor: button, opacity: opacity, textSize: text)
                        let black = saved.resolved(for: .black)
                        #expect(black.buttonColor == .black)
                        #expect(black.panelColor == panel && black.opacity == opacity && black.textSize == text)
                        #expect(saved.resolved(for: .purple) == saved)
                        #expect(try JSONDecoder().decode(VoicePanelAppearance.self, from: JSONEncoder().encode(black)) == black)
                    }
                }
            }
        }
    }

    @Test func legacyAndOtherHostsKeepTheirOriginalDefaults() throws {
        let legacy = Data(#"{"panelColor":"original","buttonColor":"violet","opacity":"original","textSize":"standard"}"#.utf8)
        let decoded = try JSONDecoder().decode(VoicePanelAppearance.self, from: legacy)
        #expect(decoded == VoicePanelAppearance())
        #expect(decoded.resolved(for: .purple) == decoded)
        #expect(BrandAppearance.allCases == [.purple, .black])
    }
}
