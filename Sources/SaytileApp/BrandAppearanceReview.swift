import AppKit
import SwiftUI
import SaytileVoiceUI

// Opt-in renderer inside the existing --ui-review / isolated-directory gate.
// No microphone, cloud request, production preferences, or global input actions.
extension AppDelegate {
    @MainActor func reviewBrandAppearance(model: AppModel, output: URL) async throws {
        let saved = model.panelAppearance
        let capture = model.panelCaptureLabel
        let recognition = model.recognitionConfiguration
        defer { model.brandAppearance = .purple; model.panelAppearance = saved }
        for brand in BrandAppearance.allCases {
            guard let image = SaytileBrand.icon(for: brand), image.isValid,
                  let mark = SaytileBrand.mark(for: brand), mark.isValid,
                  SaytileBrand.menuBarMark(for: brand)?.isTemplate == true else {
                throw ReviewFailure("missing bundled brand image or menu template")
            }
        }
        guard SaytileBrand.mark(for: .black, dark: true)?.isValid == true else {
            throw ReviewFailure("missing dark-system neutral lettering")
        }
        model.brandAppearance = .purple
        try await reviewValidatedWindow(SettingsView(model: model, initialPage: .appearance),
            size: CGSize(width: 880, height: 900), name: "brand-purple-settings", output: output)
        model.brandAppearance = .black
        guard model.effectivePanelAppearance.buttonColor == .black, model.panelAppearance == saved,
              model.panelCaptureLabel == capture, model.recognitionConfiguration == recognition else {
            throw ReviewFailure("brand change altered an unrelated preference or capture state")
        }
        try await reviewValidatedWindow(SettingsView(model: model, initialPage: .appearance),
            size: CGSize(width: 880, height: 900), name: "brand-black-settings", output: output)
        try await reviewValidatedWindow(SettingsView(model: model, initialPage: .appearance),
            size: CGSize(width: 880, height: 900), name: "brand-black-dark-settings", output: output, colorScheme: .dark)
        try await reviewValidatedWindow(InputPanelWindowView(model: model),
            size: CGSize(width: 340, height: 240), name: "brand-black-panel", output: output)
        try await reviewValidatedWindow(SettingsView(model: model, initialPage: .archive),
            size: CGSize(width: 880, height: 640), name: "brand-black-archive", output: output)
        model.brandAppearance = .purple
        guard model.effectivePanelAppearance == saved else { throw ReviewFailure("purple failed to restore the saved panel appearance") }
        let receipt: [String: Any] = [
            "source": "production native SwiftUI/AppKit views",
            "selection": "approved comparison image 2",
            "native_rendering": true, "bundled_assets_valid": true,
            "brand_round_trip_preserves_panel_preferences": true,
            "capture_and_recognition_unchanged": true,
            "microphone_used": false, "cloud_used": false,
            "actual_user_click_tested": false,
            "installation_or_Finder_icon_tested": false
        ]
        try JSONSerialization.data(withJSONObject: receipt, options: [.prettyPrinted, .sortedKeys])
            .write(to: output.appendingPathComponent("brand-receipt.json"))
        print("BRAND_REVIEW_PASS native renderings and model transitions; no claim of physical user clicks or installed Finder icon")
    }
}
