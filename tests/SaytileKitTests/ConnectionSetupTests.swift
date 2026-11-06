import Foundation
import Testing
@testable import SaytileKit

@Suite("Isolated connection setup without provider requests")
struct ConnectionSetupTests {
    private func directory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("saytile-setup-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
    private func ready() -> RecognitionConfiguration {
        var result = RecognitionConfiguration()
        result.cloudEnabled = true; result.automaticRecovery = false
        for index in result.models.indices where result.models[index].enabled {
            result.models[index].cloudConsent = true
            if result.models[index].provider == .qwenMessage { result.models[index].workspaceID = "synthetic-workspace" }
        }
        return result
    }
    @Test func existingDataAndExternalOutputAreRejectedBeforeStore() throws {
        let root = try directory(); defer { try? FileManager.default.removeItem(at: root) }
        #expect(throws: (any Error).self) { try ConnectionSetupRequest(directory: root, output: root.deletingLastPathComponent().appendingPathComponent("outside.json")) }
        try Data("preserve".utf8).write(to: root.appendingPathComponent("existing.txt"))
        #expect(throws: (any Error).self) { try ConnectionSetupRequest(directory: root, output: root.appendingPathComponent("config.json")) }
        #expect(try String(contentsOf: root.appendingPathComponent("existing.txt"), encoding: .utf8) == "preserve")
        #expect(!FileManager.default.fileExists(atPath: root.appendingPathComponent("Saytile.sqlite").path))
    }
    @Test func productionTreeIsRejectedWithoutTouchingIt() throws {
        let production = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Saytile", isDirectory: true)
        // These paths are rejected lexically before any directory inspection or creation.
        for root in [production, production.appendingPathComponent("Audio/setup-" + UUID().uuidString)] {
            #expect(throws: (any Error).self) {
                try ConnectionSetupRequest(directory: root, output: root.appendingPathComponent("configuration.json"))
            }
        }
    }
    @Test func unappliedMissingConsentMissingKeysAndWrongCoreCannotExport() throws {
        let root = try directory(); defer { try? FileManager.default.removeItem(at: root) }
        let request = try ConnectionSetupRequest(directory: root, output: root.appendingPathComponent("config.json"))
        let configuration = ready()
        #expect(throws: (any Error).self) { try request.exportApplied(configuration, hasUnappliedChanges: true, presence: { _ in .saved }) }
        #expect(throws: (any Error).self) { try request.exportApplied(configuration, hasUnappliedChanges: false, presence: { _ in .missing }) }
        var invalid = configuration; invalid.automaticRecovery = true
        #expect(throws: (any Error).self) { try request.exportApplied(invalid, hasUnappliedChanges: false, presence: { _ in .saved }) }
        invalid = configuration; invalid.models[0].cloudConsent = false
        #expect(throws: (any Error).self) { try request.exportApplied(invalid, hasUnappliedChanges: false, presence: { _ in .saved }) }
        invalid = configuration; invalid.models.removeAll { $0.purpose == .audioReview }
        #expect(throws: (any Error).self) { try request.exportApplied(invalid, hasUnappliedChanges: false, presence: { _ in .saved }) }
        #expect(!FileManager.default.fileExists(atPath: request.output.path))
    }
    @Test func syntheticMetadataExportsAppliedConfigurationOnceWithoutSecretValues() throws {
        let root = try directory(); defer { try? FileManager.default.removeItem(at: root) }
        let request = try ConnectionSetupRequest(directory: root, output: root.appendingPathComponent("config.json"))
        let config = ready()
        try request.exportApplied(config, hasUnappliedChanges: false, presence: { _ in .saved })
        let bytes = try Data(contentsOf: request.output)
        #expect(try JSONDecoder().decode(RecognitionConfiguration.self, from: bytes) == config)
        #expect(!String(decoding: bytes, as: UTF8.self).contains("apiKey"))
        #expect(throws: (any Error).self) { try request.exportApplied(config, hasUnappliedChanges: false, presence: { _ in .saved }) }
        #expect(try Data(contentsOf: request.output) == bytes)
    }
}
