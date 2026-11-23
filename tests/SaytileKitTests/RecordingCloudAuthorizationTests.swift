import Foundation
import Testing
@testable import SaytileKit

private func authorizedConfiguration() -> RecognitionConfiguration {
    var configuration = RecognitionConfiguration()
    configuration.languagePreference = .chinese
    configuration.cloudEnabled = true
    for index in configuration.models.indices {
        configuration.models[index].cloudConsent = true
        if configuration.models[index].provider == .qwenMessage {
            configuration.models[index].workspaceID = "fixture-workspace"
        }
    }
    return configuration
}

private struct ScopeFixture {
    let directory: URL
    let store: SaytileStore
    init() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("saytile-cloud-scope-" + UUID().uuidString)
        store = try SaytileStore(directory: directory)
    }
    func inspect() throws -> StoreDatabase { try StoreDatabase(url: directory.appendingPathComponent("Saytile.sqlite")) }
    func clean() { try? FileManager.default.removeItem(at: directory) }
}

@Suite("Saved audio cloud authorization scopes")
struct RecordingCloudAuthorizationTests {
    @Test func schemaFourUpgradeLeavesExistingLocalAudioUnauthorized() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("saytile-cloud-scope-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let initial = try SaytileStore(directory: root)
        let record = try await initial.createRecording()
        try await initial.saveEdit(recordingID: record.id, text: "本地档案不得因添加凭据上传")
        let localTicket = try await initial.beginRecognition(recordingID: record.id)
        _ = try await initial.beginLocalCandidateRun(ticket: localTicket)
        try await initial.finishRecording(id: record.id)
        let previousCloudRecord = try await initial.createRecording()
        let previousCloudTicket = try await initial.beginFusionRecognition(recordingID: previousCloudRecord.id)
        _ = try await initial.beginModelRun(ticket: previousCloudTicket, configuration: authorizedConfiguration().models[0])
        try await initial.finishRecording(id: previousCloudRecord.id)
        try await initial.close()
        let prior = try StoreDatabase(url: root.appendingPathComponent("Saytile.sqlite"))
        try prior.script("DROP TABLE IF EXISTS recording_cloud_authorizations; PRAGMA user_version=4;")
        try prior.close()

        let upgraded = try SaytileStore(directory: root)
        #expect(try await upgraded.recording(id: record.id)?.text == "本地档案不得因添加凭据上传")
        #expect(try await !upgraded.permitsAutomaticCloudRecovery(recordingID: record.id, configuration: authorizedConfiguration()))
        #expect(try await !upgraded.permitsAutomaticCloudRecovery(recordingID: previousCloudRecord.id, configuration: authorizedConfiguration()))
        let inspect = try StoreDatabase(url: root.appendingPathComponent("Saytile.sqlite"))
        #expect(try inspect.rows("PRAGMA user_version").first?["user_version"] == "6")
        #expect(try inspect.rows("SELECT name FROM sqlite_master WHERE type='table' AND name='recording_cloud_authorizations'").count == 1)
        #expect(try inspect.rows("SELECT * FROM recording_cloud_authorizations").isEmpty)
        #expect(try inspect.rows("SELECT * FROM model_runs").count == 2)
        try inspect.close()
        try await upgraded.close()
    }

    @Test func explicitScopeSurvivesRestartWithoutGrantingOtherRecordings() async throws {
        let fixture = try ScopeFixture(); defer { fixture.clean() }
        let cloud = try await fixture.store.createRecording()
        let local = try await fixture.store.createRecording()
        let configuration = authorizedConfiguration()
        #expect(try await !fixture.store.permitsAutomaticCloudRecovery(recordingID: cloud.id, configuration: configuration))
        try await fixture.store.authorizeCloudRecovery(recordingID: cloud.id, configuration: configuration)
        try await fixture.store.authorizeCloudRecovery(recordingID: cloud.id, configuration: configuration)
        #expect(try await fixture.store.permitsAutomaticCloudRecovery(recordingID: cloud.id, configuration: configuration))
        #expect(try await !fixture.store.permitsAutomaticCloudRecovery(recordingID: local.id, configuration: configuration))
        let inspect = try fixture.inspect()
        #expect(try inspect.rows("SELECT * FROM recording_cloud_authorizations").count == configuration.activeModels.count)
        try inspect.close(); try await fixture.store.close()
        let reopened = try SaytileStore(directory: fixture.directory)
        #expect(try await reopened.permitsAutomaticCloudRecovery(recordingID: cloud.id, configuration: configuration))
        #expect(try await !reopened.permitsAutomaticCloudRecovery(recordingID: local.id, configuration: configuration))
        try await reopened.close()
    }

    @Test(arguments: ["identity", "provider", "model", "region", "workspace", "purpose", "fusionRegion", "fusionModel", "credentialGeneration"])
    func changedDestinationCannotInheritSavedAudioPermission(change: String) async throws {
        let fixture = try ScopeFixture(); defer { fixture.clean() }
        let record = try await fixture.store.createRecording()
        let original = authorizedConfiguration()
        try await fixture.store.authorizeCloudRecovery(recordingID: record.id, configuration: original)
        var changed = original
        let expert = try #require(changed.models.firstIndex { $0.provider == .qwenMessage })
        let fusion = try #require(changed.models.firstIndex { $0.purpose == .textFusion })
        switch change {
        case "identity": changed.models[expert].id = UUID()
        case "provider": changed.models[expert].provider = .soniox
        case "model": changed.models[expert].model += "-new"
        case "region": changed.models[expert].region = "ap-southeast-1"
        case "workspace": changed.models[expert].workspaceID = "another-workspace"
        case "purpose": changed.models[expert].purpose = .multilingualASR
        case "fusionRegion": changed.models[fusion].region = "eu"
        case "fusionModel": changed.models[fusion].model += "-new"
        case "credentialGeneration": changed.models[fusion].credentialGeneration = UUID()
        default: Issue.record("Unknown scope change")
        }
        #expect(try await !fixture.store.permitsAutomaticCloudRecovery(recordingID: record.id, configuration: changed))
        #expect(try await fixture.store.permitsAutomaticCloudRecovery(recordingID: record.id, configuration: original))
        // Only a new explicit authorization can add the changed destination.
        if ["provider", "purpose", "fusionModel"].contains(change) {
            await #expect(throws: ProviderFailure.self) {
                try await fixture.store.authorizeCloudRecovery(recordingID: record.id, configuration: changed)
            }
            #expect(try await !fixture.store.permitsAutomaticCloudRecovery(recordingID: record.id, configuration: changed))
        } else {
            try await fixture.store.authorizeCloudRecovery(recordingID: record.id, configuration: changed)
            #expect(try await fixture.store.permitsAutomaticCloudRecovery(recordingID: record.id, configuration: changed))
        }
        try await fixture.store.close()
    }

    @Test func subsetAndNonDestinationChangesDoNotRequireAnotherGrant() async throws {
        let fixture = try ScopeFixture(); defer { fixture.clean() }
        let record = try await fixture.store.createRecording()
        var original = authorizedConfiguration()
        original.topicContext = "fixture-private-topic"
        for index in original.models.indices { original.models[index].context = "fixture-private-context" }
        try await fixture.store.authorizeCloudRecovery(recordingID: record.id, configuration: original)
        let inspect = try fixture.inspect()
        #expect(try inspect.rows("SELECT scope FROM recording_cloud_authorizations").allSatisfy { !$0["scope", default: ""].contains("fixture-private") })
        try inspect.close()
        var reordered = original
        reordered.models.reverse(); reordered.inputMode = .fast; reordered.topicContext = "新的当前话题"
        for index in reordered.models.indices {
            reordered.models[index].context = "新的提示"
            reordered.models[index].reasoningEffort = "max"
            reordered.models[index].audioHourRate = 1
        }
        #expect(try await fixture.store.permitsAutomaticCloudRecovery(recordingID: record.id, configuration: reordered))
        let english = try #require(reordered.models.firstIndex { $0.purpose == .englishASR })
        reordered.models[english].enabled = false
        #expect(try await fixture.store.permitsAutomaticCloudRecovery(recordingID: record.id, configuration: reordered))
        let extra = ModelConfiguration(purpose: .multilingualASR, provider: .soniox, model: "stt-rt-v6", cloudConsent: true)
        reordered.models.append(extra)
        #expect(try await fixture.store.permitsAutomaticCloudRecovery(recordingID: record.id, configuration: reordered))
        reordered.languagePreference = .chineseEnglishMixed
        #expect(try await !fixture.store.permitsAutomaticCloudRecovery(recordingID: record.id, configuration: reordered))
        try await fixture.store.close()
    }

    @Test(arguments: ["disabled", "empty", "noAudio", "consent", "invalidModel", "duplicateIdentity"])
    func invalidOrUnconsentedConfigurationNeverGrantsPartialPermission(change: String) async throws {
        let fixture = try ScopeFixture(); defer { fixture.clean() }
        let record = try await fixture.store.createRecording()
        var configuration = authorizedConfiguration()
        let fusion = try #require(configuration.models.firstIndex { $0.enabled && $0.purpose == .textFusion })
        switch change {
        case "disabled": configuration.cloudEnabled = false
        case "empty": configuration.models = []
        case "noAudio": configuration.models.removeAll { $0.purpose.isStreaming }
        case "consent": configuration.models[fusion].cloudConsent = false
        case "invalidModel": configuration.models[fusion].model = ""
        case "duplicateIdentity": configuration.models[1].id = configuration.models[0].id
        default: Issue.record("Unknown configuration change")
        }
        await #expect(throws: ProviderFailure.self) {
            try await fixture.store.authorizeCloudRecovery(recordingID: record.id, configuration: configuration)
        }
        #expect(try await !fixture.store.permitsAutomaticCloudRecovery(recordingID: record.id, configuration: configuration))
        let inspect = try fixture.inspect()
        #expect(try inspect.rows("SELECT * FROM recording_cloud_authorizations").isEmpty)
        try inspect.close(); try await fixture.store.close()
    }

    @Test func grantTransactionRollsBackAndDatabaseFailureIsNotReportedAsPermission() async throws {
        let fixture = try ScopeFixture(); defer { fixture.clean() }
        let record = try await fixture.store.createRecording()
        let configuration = authorizedConfiguration()
        let inspect = try fixture.inspect()
        try inspect.script("""
            CREATE TRIGGER fail_second_scope BEFORE INSERT ON recording_cloud_authorizations
            WHEN (SELECT COUNT(*) FROM recording_cloud_authorizations)>=1
            BEGIN SELECT RAISE(ABORT,'fixture durability failure'); END;
            """)
        await #expect(throws: StoreError.self) {
            try await fixture.store.authorizeCloudRecovery(recordingID: record.id, configuration: configuration)
        }
        #expect(try inspect.rows("SELECT * FROM recording_cloud_authorizations").isEmpty)
        #expect(try await !fixture.store.permitsAutomaticCloudRecovery(recordingID: record.id, configuration: configuration))
        try inspect.close(); try await fixture.store.close()
        await #expect(throws: StoreError.self) {
            try await fixture.store.permitsAutomaticCloudRecovery(recordingID: record.id, configuration: configuration)
        }
    }

    @Test func audioErasureKeepsMetadataButRecordErasureRemovesAuthorization() async throws {
        let fixture = try ScopeFixture(); defer { fixture.clean() }
        let record = try await fixture.store.createRecording()
        let configuration = authorizedConfiguration()
        try await fixture.store.authorizeCloudRecovery(recordingID: record.id, configuration: configuration)
        try await fixture.store.saveEdit(recordingID: record.id, text: "删除原音仍保留文字")
        try await fixture.store.finishRecording(id: record.id)
        try await fixture.store.deleteAudio(recordingID: record.id)
        #expect(try await fixture.store.recording(id: record.id)?.text == "删除原音仍保留文字")
        #expect(try await !fixture.store.permitsAutomaticCloudRecovery(recordingID: record.id, configuration: configuration))
        let inspect = try fixture.inspect()
        #expect(try inspect.rows("SELECT * FROM recording_cloud_authorizations").count == configuration.activeModels.count)
        await #expect(throws: StoreError.self) {
            try await fixture.store.authorizeCloudRecovery(recordingID: record.id, configuration: configuration)
        }
        try await fixture.store.deleteRecord(recordingID: record.id)
        #expect(try inspect.rows("SELECT * FROM recording_cloud_authorizations").isEmpty)
        #expect(try await fixture.store.recording(id: record.id) == nil)
        try inspect.close(); try await fixture.store.close()
    }

    @Test func physicalRecordDeletionCascadesAndMalformedScopeFailsClosed() async throws {
        let fixture = try ScopeFixture(); defer { fixture.clean() }
        let record = try await fixture.store.createRecording()
        let configuration = authorizedConfiguration()
        try await fixture.store.authorizeCloudRecovery(recordingID: record.id, configuration: configuration)
        let inspect = try fixture.inspect()
        try inspect.execute("UPDATE recording_cloud_authorizations SET scope='malformed' WHERE rowid=(SELECT MIN(rowid) FROM recording_cloud_authorizations)")
        #expect(try await !fixture.store.permitsAutomaticCloudRecovery(recordingID: record.id, configuration: configuration))
        try inspect.execute("PRAGMA foreign_keys=ON")
        try inspect.execute("DELETE FROM recordings WHERE id=?", [.text(record.id.uuidString)])
        #expect(try inspect.rows("SELECT * FROM recording_cloud_authorizations").isEmpty)
        try inspect.close(); try await fixture.store.close()
    }
}
