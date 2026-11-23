import Foundation
import Testing
@testable import SaytileKit

@Suite("Single transcript engine configuration")
struct SingleTranscriptEngineTests {
    private func configured() -> RecognitionConfiguration {
        var value = RecognitionConfiguration()
        value.languagePreference = .chinese
        value.cloudEnabled = true
        for index in value.models.indices {
            value.models[index].cloudConsent = true
            if value.models[index].provider == .qwenMessage { value.models[index].workspaceID = "workspace-test" }
        }
        return value
    }

    @Test func explicitLanguageResolvesExactlyOneASRAndOneGPT6Core() throws {
        let value = configured()
        let activeASR = value.activeModels.filter { $0.purpose.isStreaming }
        let cores = value.activeModels.filter { $0.purpose == .textFusion }
        #expect(activeASR.count == 1)
        #expect(cores.count == 1)
        #expect(cores[0].provider == .openAIResponses)
        #expect(cores[0].model == "gpt-6-astra")
        #expect(!value.activeModels.contains { [.audioReview, .finalASR].contains($0.purpose) })
        try value.validateForCloud()
    }

    @Test func recordingSnapshotRequiresTheCheckedProviderEvenWhenAnotherModelHasConsent() throws {
        var config = configured()
        config.checkedASRConfigurationID = try #require(config.selectedASRModel).id
        let factory = RecognitionSessionFactory(configuration: config)
        let inFlight = factory.snapshot
        config.languagePreference = .english
        factory.update(config)
        #expect(inFlight.configuration.selectedASRModel?.provider == .qwenMessage)
        #expect(inFlight.configuration.cloudEnabled)
        #expect(!factory.snapshot.configuration.cloudEnabled)
        config.checkedASRConfigurationID = try #require(config.selectedASRModel).id
        factory.update(config)
        #expect(factory.snapshot.configuration.cloudEnabled)
        #expect(factory.snapshot.configuration.selectedASRModel?.provider == .assemblyAI)
    }

    @Test func exactlyOneGPTCoreIsMandatory() throws {
        var value = configured()
        var duplicate = try #require(value.models.first { $0.purpose == .textFusion })
        duplicate.id = UUID()
        value.models.append(duplicate)
        #expect(throws: ProviderFailure.self) { try value.validateForCloud() }
    }

    @Test func languagePreferenceSelectsOneASRWithoutExposingParallelProviders() throws {
        var value = configured()
        value.languagePreference = .chineseEnglishMixed
        let selected = try #require(value.selectedASRModel)
        #expect(selected.provider == .soniox)
        #expect(value.activeModels.filter { $0.purpose.isStreaming }.count == 1)
        try value.validateForCloud()
        let runtime = try value.resolvedForCurrentLanguage()
        #expect(runtime.enabledModels.filter { $0.purpose.isStreaming }.count == 1)
        #expect(runtime.enabledModels.first { $0.purpose.isStreaming }?.provider == .soniox)
    }

    @Test func eosReviewCannotBypassGPT429RetryAfterOrConfigurationBlock() {
        let now = Date(timeIntervalSince1970: 1_000)
        let retryAfter = now.addingTimeInterval(60)
        #expect(!GPTReviewRetryPolicy.isEligible(blocked: false, failures: 1, retryAfter: retryAfter, now: now))
        #expect(GPTReviewRetryPolicy.isEligible(blocked: false, failures: 1, retryAfter: retryAfter, now: now.addingTimeInterval(60.1)))
        #expect(!GPTReviewRetryPolicy.isEligible(blocked: true, failures: 0, retryAfter: .distantPast, now: now))
        #expect(GPTReviewRetryPolicy.retryDelay(failures: 1, providerMinimum: 60) == 60)
        #expect(GPTReviewRetryPolicy.retryDelay(failures: 2, providerMinimum: 0) == 4)
    }

    @Test func modelUsageRetainsCachedAndReasoningTokenBreakdown() throws {
        let record = ModelUsageRecord(runID: UUID(), inputTokens: 100, outputTokens: 20,
                                      cachedInputTokens: 30, reasoningTokens: 8, estimatedCost: nil)
        let decoded = try JSONDecoder().decode(ModelUsageRecord.self, from: JSONEncoder().encode(record))
        #expect(decoded.inputTokens == 100 && decoded.outputTokens == 20)
        #expect(decoded.cachedInputTokens == 30 && decoded.reasoningTokens == 8)
        #expect(decoded.estimatedCost == nil)
    }

    @Test func languageProfilePrefersObservedUsageOverLocaleAndDetectsMixedSpeech() {
        #expect(LanguageProfile.resolve(.auto, locale: Locale(identifier: "en"), history: []) == .auto)
        #expect(LanguageProfile.resolve(.auto, locale: Locale(identifier: "zh"), history: ["en"]) == .auto)
        #expect(LanguageProfile.resolve(.auto, locale: Locale(identifier: "zh-Hant"), history: ["en", "en", "en"]) == .english)
        #expect(LanguageProfile.resolve(.auto, locale: Locale(identifier: "en"), history: ["zh", "zh", "zh"]) == .chinese)
        #expect(LanguageProfile.resolve(.auto, locale: Locale(identifier: "zh"), history: ["mixed", "mixed"]) == .chineseEnglishMixed)
        #expect(LanguageProfile.resolve(.chineseEnglishMixed, locale: Locale(identifier: "en"), history: []) == .chineseEnglishMixed)
        #expect(ASRModelRegistry.provider(for: .chinese) == .qwenMessage)
        #expect(ASRModelRegistry.provider(for: .english) == .assemblyAI)
        #expect(ASRModelRegistry.provider(for: .chineseEnglishMixed) == .soniox)
    }

    @Test func englishPreferenceSelectsAssemblyAndKeepsTheSameGPTCore() throws {
        var value = configured(); value.languagePreference = .english
        #expect(value.selectedASRModel?.provider == .assemblyAI)
        try value.validateForCloud()
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
        value.languagePreference = .chineseEnglishMixed
        try value.validateForCloud()
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
