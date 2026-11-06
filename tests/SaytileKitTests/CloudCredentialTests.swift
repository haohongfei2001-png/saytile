import Foundation
import Testing
@testable import SaytileKit

@Suite("Isolated real Keychain credentials")
struct CloudCredentialTests {
    @Test func createReplaceReadDeleteKeepsAccountProviderAndServiceIsolation() throws {
        let service = "com.saytile.tests.credentials." + UUID().uuidString
        let store = KeychainCredentialStore(service: service)
        let other = KeychainCredentialStore(service: service + ".other")
        let id = UUID(), second = UUID()
        defer {
            try? store.delete(configurationID: id, provider: .assemblyAI)
            try? store.delete(configurationID: second, provider: .assemblyAI)
            try? store.delete(configurationID: id, provider: .meta)
        }
        #expect(store.presence(configurationID: id, provider: .assemblyAI) == .missing)
        try store.save("synthetic-only-first", configurationID: id, provider: .assemblyAI)
        try store.save("synthetic-only-second", configurationID: second, provider: .assemblyAI)
        try store.save("synthetic-only-other-provider", configurationID: id, provider: .meta)
        #expect(store.presence(configurationID: id, provider: .assemblyAI) == .saved)
        #expect(other.presence(configurationID: id, provider: .assemblyAI) == .missing)
        #expect(try other.read(configurationID: id, provider: .assemblyAI) == nil)
        try store.save("  synthetic-only-replaced\n", configurationID: id, provider: .assemblyAI)
        #expect(try store.read(configurationID: id, provider: .assemblyAI) == "synthetic-only-replaced")
        #expect(try store.read(configurationID: second, provider: .assemblyAI) == "synthetic-only-second")
        #expect(try store.read(configurationID: id, provider: .meta) == "synthetic-only-other-provider")
        try store.delete(configurationID: id, provider: .assemblyAI)
        try store.delete(configurationID: id, provider: .assemblyAI)
        #expect(store.presence(configurationID: id, provider: .assemblyAI) == .missing)
        #expect(try store.read(configurationID: id, provider: .assemblyAI) == nil)
        #expect(store.presence(configurationID: second, provider: .assemblyAI) == .saved)
        #expect(store.presence(configurationID: id, provider: .meta) == .saved)
    }

    @Test func invalidReplacementNeverErasesStoredDummyCredential() throws {
        let store = KeychainCredentialStore(service: "com.saytile.tests.credentials." + UUID().uuidString)
        let id = UUID()
        defer { try? store.delete(configurationID: id, provider: .gemini) }
        try store.save("synthetic-existing", configurationID: id, provider: .gemini)
        #expect(throws: CloudCredentialError.self) { try store.save(" \n ", configurationID: id, provider: .gemini) }
        #expect(try store.read(configurationID: id, provider: .gemini) == "synthetic-existing")
    }
}

@Suite("Recognition setup configuration")
struct RecognitionSetupTests {
    @Test func defaultsIncludeTwoExpertsAndOneCoreAndKeepOptionalExpertsOffAndConsentOff() throws {
        let config = RecognitionConfiguration()
        #expect(!config.cloudEnabled)
        #expect(config.inputMode == .highestQuality)
        #expect(Set(config.enabledModels.map(\.provider)) == [.qwenMessage, .assemblyAI, .openAIResponses])
        #expect(config.models.allSatisfy { !$0.cloudConsent })
        #expect(config.models.filter { $0.provider == .soniox || $0.provider == .meta }.allSatisfy { !$0.enabled })
        #expect(Set(config.models.map(\.id)).count == config.models.count)
    }

    @Test func providerChangeKeepsCredentialIdentityButResetsAuthorizationRegionAndCharges() throws {
        var item = ModelConfiguration(purpose: .englishASR, provider: .assemblyAI, model: "custom", cloudConsent: true,
                                      region: "eu", workspaceID: "old-workspace", audioHourRate: 1)
        let id = item.id
        item.provider = .qwenMessage; item.resetForProviderChange()
        #expect(item.id == id)
        #expect(!item.cloudConsent)
        #expect(item.region == "cn-beijing")
        #expect(item.workspaceID.isEmpty)
        #expect(item.model == "qwen-audio-3.1-asr-flash-message")
        #expect(item.audioHourRate == nil)
        #expect(throws: ProviderFailure.self) { try item.validate() }
        item.workspaceID = "synthetic-workspace"; try item.validate()
    }

    @Test func settingsRoundTripRetainsStableIDsAndNeverContainsCredentialBytes() throws {
        let name = "com.saytile.tests.preferences." + UUID().uuidString
        let preferences = try #require(UserDefaults(suiteName: name))
        defer { preferences.removePersistentDomain(forName: name) }
        var original = RecognitionConfiguration()
        original.inputMode = .fast
        original.topicContext = "synthetic-topic"
        original.models[1].cloudConsent = true
        try original.save(to: preferences)
        original.inputMode = .highestQuality // legacy fast mode is intentionally migrated
        #expect(RecognitionConfiguration.load(from: preferences) == original)
        #expect(RecognitionConfiguration.load(from: preferences).models.map(\.id) == original.models.map(\.id))
        let json = try #require(preferences.data(forKey: "multiASRConfigurationV1"))
        let object = try #require(JSONSerialization.jsonObject(with: json) as? [String: Any])
        let models = try #require(object["models"] as? [[String: Any]])
        #expect(models.allSatisfy { $0["apiKey"] == nil && $0["secret"] == nil && $0["credential"] == nil })
    }
}
