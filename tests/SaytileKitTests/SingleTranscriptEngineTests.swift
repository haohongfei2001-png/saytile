import Foundation
import Testing
@testable import SaytileKit

@Suite("Single transcript engine configuration")
struct SingleTranscriptEngineTests {
    private func configured() -> RecognitionConfiguration {
        var value = RecognitionConfiguration()
        value.cloudEnabled = true
        for index in value.models.indices {
            value.models[index].cloudConsent = true
            if value.models[index].provider == .qwenMessage { value.models[index].workspaceID = "workspace-test" }
        }
        return value
    }

    @Test func defaultsAreTwoEqualExpertsAndExactlyOneGPT6Core() throws {
        let value = configured()
        let experts = value.enabledModels.filter { $0.purpose.isStreaming }
        let cores = value.enabledModels.filter { $0.purpose == .textFusion }
        #expect(experts.count == 2)
        #expect(experts.filter { $0.purpose == .chineseASR }.count == 1)
        #expect(experts.filter { $0.purpose == .englishASR }.count == 1)
        #expect(cores.count == 1)
        #expect(cores[0].provider == .openAIResponses)
        #expect(cores[0].model == "gpt-6-astra")
        #expect(!value.enabledModels.contains { [.audioReview, .finalASR].contains($0.purpose) })
        try value.validateForCloud()
    }

    @Test func exactlyOneGPTCoreIsMandatory() throws {
        var value = configured()
        var duplicate = try #require(value.models.first { $0.purpose == .textFusion })
        duplicate.id = UUID()
        value.models.append(duplicate)
        #expect(throws: ProviderFailure.self) { try value.validateForCloud() }
    }

    @Test func thirdASRIsAllowedAsAnEvidenceSource() throws {
        var value = configured()
        let index = try #require(value.models.firstIndex { $0.provider == .soniox })
        value.models[index].enabled = true
        value.models[index].cloudConsent = true
        try value.validateForCloud()
    }

    @Test func singleExpertAblationStillRequiresTheSameGPTCore() throws {
        var value = configured()
        let index = try #require(value.models.firstIndex { $0.purpose == .englishASR })
        value.models[index].enabled = false
        try value.validateForCloud(allowSingleExpertBaseline: true)
        #expect(throws: ProviderFailure.self) { try value.validateForCloud() }
    }

    @Test func legacySeparateAudioAndFinalModelsCannotJoinTheDefaultChain() throws {
        var value = configured()
        value.models.append(.init(purpose: .audioReview, provider: .gemini, model: "gemini-3.8-flash", cloudConsent: true))
        #expect(throws: ProviderFailure.self) { try value.validateForCloud() }
    }
    @Test func legacySettingsMigrationDisablesSecondStageModelsAndKeepsGPTIdentity() throws {
        let suite = "com.saytile.tests.single-transcript." + UUID().uuidString
        let preferences = try #require(UserDefaults(suiteName: suite))
        defer { preferences.removePersistentDomain(forName: suite) }
        var old = RecognitionConfiguration()
        old.inputMode = .fast
        old.models.append(.init(purpose: .audioReview, provider: .gemini, model: "gemini-3.8-flash", enabled: true, cloudConsent: true))
        old.models.append(.init(purpose: .finalASR, provider: .elevenLabsFile, model: "scribe_v2", enabled: true, cloudConsent: true))
        let oldGPT = try #require(old.models.first { $0.purpose == .textFusion })
        try old.save(to: preferences)
        let migrated = RecognitionConfiguration.load(from: preferences)
        let active = migrated.enabledModels
        #expect(active.filter { $0.purpose == .textFusion }.count == 1)
        #expect(!active.contains { [.audioReview, .finalASR].contains($0.purpose) })
        #expect(migrated.models.first { $0.purpose == .textFusion }?.id == oldGPT.id)
        #expect(migrated.inputMode == .highestQuality)
    }

    @Test func multilingualSingleExpertUsesSameCore() throws {
        var value = configured()
        for index in value.models.indices where value.models[index].purpose.isStreaming {
            value.models[index].enabled = value.models[index].provider == .soniox
        }
        try value.validateForCloud(allowSingleExpertBaseline: true)
    }

    @Test func migrationIsIdempotentAndNeverReplacesCustomModelOrGrantsConsent() throws {
        let suite = "com.saytile.tests.single-transcript." + UUID().uuidString
        let preferences = try #require(UserDefaults(suiteName: suite))
        defer { preferences.removePersistentDomain(forName: suite) }
        var old = configured()
        let index = try #require(old.models.firstIndex { $0.purpose == .textFusion })
        old.models[index].model = "user-custom-model"
        let id = old.models[index].id
        try old.save(to: preferences)
        let migrated = RecognitionConfiguration.load(from: preferences)
        #expect(!migrated.cloudEnabled)
        #expect(migrated.models[index].model == "user-custom-model")
        #expect(migrated.models[index].id == id)
        #expect(!migrated.models[index].cloudConsent)
        #expect(!migrated.models[index].enabled)
        try migrated.save(to: preferences)
        #expect(RecognitionConfiguration.load(from: preferences) == migrated)
    }

}
