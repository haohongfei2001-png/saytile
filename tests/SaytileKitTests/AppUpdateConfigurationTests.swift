import Foundation
import Testing
@testable import SaytileKit

struct AppUpdateConfigurationTests {
    private func info(_ id: String = "app.saytile.mac", channel: String = "standard") -> [String: Any] {
        ["SUFeedURL": "https://updates.example.test/standard/appcast.xml",
         "SUPublicEDKey": Data(repeating: 1, count: 32).base64EncodedString(),
         "SaytileUpdateBundleIdentifier": id, "SaytileUpdateChannel": channel,
         "SURequireSignedFeed": true, "SUVerifyUpdateBeforeExtraction": true,
         "SUAllowsAutomaticUpdates": false, "SUSendProfileInfo": false]
    }
    @Test func eachProductIdentityHasItsOwnConfiguration() throws {
        let standard = try AppUpdateConfiguration(info: info(), bundleID: "app.saytile.mac")
        #expect(standard.channel == "standard")
        let id = SaytileStorageProfile.mandarinCandidateID
        #expect(try AppUpdateConfiguration(info: info(id, channel: "mandarin"), bundleID: id).channel == "mandarin")
        #expect(throws: AppUpdateConfiguration.Failure.self) { try AppUpdateConfiguration(info: info(), bundleID: id) }
        #expect(throws: AppUpdateConfiguration.Failure.self) { try AppUpdateConfiguration(info: info(id), bundleID: id) }
    }
    @Test(arguments: ["http://updates.example.test/feed.xml", "https://u:p@example.test/feed.xml",
                      "https://example.test/feed.xml#part", "https://example.test/feed.xml?token=fixture", "file:///tmp/feed.xml"])
    func rejectsUnsafeOrAmbiguousFeed(url: String) {
        var values = info(); values["SUFeedURL"] = url
        #expect(throws: AppUpdateConfiguration.Failure.self) { try AppUpdateConfiguration(info: values, bundleID: "app.saytile.mac") }
    }
    @Test(arguments: ["SURequireSignedFeed", "SUVerifyUpdateBeforeExtraction", "SUAllowsAutomaticUpdates", "SUSendProfileInfo"])
    func signatureAndPrivacyCannotBeWeakened(key: String) {
        var values = info(); values[key] = !(values[key] as! Bool)
        #expect(throws: AppUpdateConfiguration.Failure.self) { try AppUpdateConfiguration(info: values, bundleID: "app.saytile.mac") }
    }
    @Test func missingOrMalformedKeyRefusesUpdates() {
        var values = info(); values["SUPublicEDKey"] = Data(repeating: 1, count: 31).base64EncodedString()
        #expect(throws: AppUpdateConfiguration.Failure.self) { try AppUpdateConfiguration(info: values, bundleID: "app.saytile.mac") }
        values.removeValue(forKey: "SUFeedURL")
        #expect(throws: AppUpdateConfiguration.Failure.self) { try AppUpdateConfiguration(info: values, bundleID: "app.saytile.mac") }
    }
    @Test func loopbackOnlyWorksForExplicitIsolatedFixture() throws {
        let id = "app.saytile.update-fixture.test"
        var values = info(id, channel: "fixture"); values["SUFeedURL"] = "http://127.0.0.1:48121/appcast.xml"
        #expect(throws: AppUpdateConfiguration.Failure.self) { try AppUpdateConfiguration(info: values, bundleID: id) }
        #expect(try AppUpdateConfiguration(info: values, bundleID: id, isolatedFixture: true).channel == "fixture")
        values["SaytileUpdateBundleIdentifier"] = "app.saytile.mac"
        #expect(throws: AppUpdateConfiguration.Failure.self) { try AppUpdateConfiguration(info: values, bundleID: "app.saytile.mac", isolatedFixture: true) }
    }
}
