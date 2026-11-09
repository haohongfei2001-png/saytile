import CryptoKit
import Foundation
import SaytileKit

// Compiled separately against the DMG's v5 sources and the candidate's v6 sources.
// Every account is generated for this rehearsal. No default credential IDs are used.
private struct Fixture: Codable {
    var credentials: [UUID]
    var hashes: [String]
    let suite: String
    let allowed: UUID
    let localOnly: UUID
}

@main struct UpgradeContinuity {
    static func require(_ ok: Bool, _ label: String) throws {
        if !ok { throw NSError(domain: "RC2UpgradeFixture." + label, code: 1) }
    }
    static func digest(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
    static func main() async throws {
        let args = CommandLine.arguments
        let data = URL(fileURLWithPath: args[2], isDirectory: true)
        let file = URL(fileURLWithPath: args[3])
        let providers: [CloudProvider] = [.assemblyAI, .openAIResponses]
        if args[1] == "seed" {
            var config = RecognitionConfiguration()
            config.languagePreference = .english
            config.cloudEnabled = true
            config.automaticRecovery = false
            config.models = [
                .init(purpose: .englishASR, provider: providers[0], model: "universal-3-6-pro", cloudConsent: true, credentialGeneration: UUID()),
                .init(purpose: .textFusion, provider: providers[1], model: "gpt-6-astra", cloudConsent: true, credentialGeneration: UUID())
            ]
            try config.validateForCloud()
            let store = try SaytileStore(directory: data)
            let allowed = try await store.createRecording(), local = try await store.createRecording()
            try await store.finishRecording(id: allowed.id)
            try await store.finishRecording(id: local.id)
            try await store.authorizeCloudRecovery(recordingID: allowed.id, configuration: config)
            try await store.close()
            let suite = "app.saytile.integration.fixture." + UUID().uuidString
            let prefs = UserDefaults(suiteName: suite)!
            try config.save(to: prefs)
            // Preserve a simulator receipt without claiming that a live check ran.
            let receipt: [String: Any] = ["configurationFingerprint": CloudConnectionVerifier.fingerprint(config),
                "date": 0, "live": false, "services": [], "transcript": "", "pipelineCompleted": false,
                "elapsedSeconds": 0, "reviewRequests": 0]
            prefs.set(try JSONSerialization.data(withJSONObject: receipt), forKey: "cloudConnectionReceipt.v1")
            try require(prefs.synchronize(), "persist")
            var fixture = Fixture(credentials: [], hashes: [], suite: suite, allowed: allowed.id, localOnly: local.id)
            try JSONEncoder().encode(fixture).write(to: file, options: .withoutOverwriting)
            for item in config.models {
                try require(CloudCredentialStore.presence(configurationID: item.id, provider: item.provider) == .missing, "freshAccount")
                let synthetic = "offline-test-" + UUID().uuidString
                fixture.credentials.append(item.id)
                fixture.hashes.append(digest(Data(synthetic.utf8)))
                try JSONEncoder().encode(fixture).write(to: file, options: .atomic)
                try CloudCredentialStore.save(synthetic, configurationID: item.id, provider: item.provider)
            }
            print("BASELINE_SEED_PASS synthetic ASR + GPT, explicit scoped consent and a local-only row")
            return
        }
        let fixture = try JSONDecoder().decode(Fixture.self, from: Data(contentsOf: file))
        let prefs = UserDefaults(suiteName: fixture.suite)!
        if args[1] == "cleanup" {
            for (index,id) in fixture.credentials.enumerated() {
                try CloudCredentialStore.delete(configurationID: id, provider: providers[index])
                try require(!CloudCredentialStore.contains(configurationID: id, provider: providers[index]), "cleanup")
            }
            prefs.removePersistentDomain(forName: fixture.suite)
            print("CLEANUP_PASS synthetic accounts and isolated defaults removed")
            return
        }
        try require(args[1] == "verify" && fixture.credentials.count == 2, "mode")
        let config = RecognitionConfiguration.load(from: prefs)
        try require(config.models.map(\.id) == fixture.credentials && config.cloudEnabled && !config.automaticRecovery, "legacyConfiguration")
        try config.validateForCloud()
        let receipt = try JSONDecoder().decode(CloudConnectionReport.self, from: prefs.data(forKey: "cloudConnectionReceipt.v1")!)
        try require(receipt.matches(config) && !receipt.canEnableCloud, "receiptScope")
        for (index,item) in config.models.enumerated() {
            try require(CloudCredentialStore.presence(configurationID: item.id, provider: item.provider) == .saved, "keychainMetadata")
            let value = try CloudCredentialStore.read(configurationID: item.id, provider: item.provider) ?? ""
            try require(digest(Data(value.utf8)) == fixture.hashes[index], "keychainContinuity")
        }
        let store = try SaytileStore(directory: data)
        try require(try await store.permitsAutomaticCloudRecovery(recordingID: fixture.allowed, configuration: config), "retainedGrant")
        try require(try await !store.permitsAutomaticCloudRecovery(recordingID: fixture.localOnly, configuration: config), "localOnly")
        var rotated = config
        rotated.models[0].credentialGeneration = UUID()
        try require(try await !store.permitsAutomaticCloudRecovery(recordingID: fixture.allowed, configuration: rotated), "foreignAccount")
        try await store.close()
        print("CONTINUITY_PASS model IDs, receipt fingerprint, two Keychain canaries, allowed, local-only and changed-account scopes")
    }
}
