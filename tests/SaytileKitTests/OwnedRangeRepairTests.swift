import Foundation
import Testing
@testable import SaytileKit

/// Actual coordinator + Store, with only the operating system boundary replaced.
/// No real AX, clipboard, key events, application activation or audio is used.
@MainActor
private final class OwnedRangeOS: InputAccess {
    var hasPermission = true
    var text = "用户前缀｜用户后缀"
    var target = InputTargetSnapshot(processID: 987654, applicationID: "test.owned", applicationName: "Synthetic owned range",
        windowID: UUID(), elementID: UUID(), pageIdentity: "fixture://page/1", selectionLocation: 5,
        selectionLength: 0, isWeb: false, isEditable: true, isSensitive: false, canSetSelectedText: true)
    var insertions: [String] = []
    var replacements: [(Int, String, String)] = []
    var confirmsInsertion = true
    var supportsReplacement = true
    var throwsAfterReplacement = false
    var witnessAvailable = true
    var observedSupport = InputObservationSupport(focus: true, content: true, page: true)
    var onChange: (@MainActor (InputTargetChange) -> Void)?
    var beforeReplacement: (@MainActor () -> Void)?
    var afterSelection: (@MainActor () -> Void)?
    func snapshot() throws -> InputTargetSnapshot { target }
    func textWitness(at expected: InputTargetSnapshot) -> String? { witnessAvailable && target == expected ? text : nil }
    func matchesText(_ value: String, utf16Start: Int, at expected: InputTargetSnapshot) -> Bool? {
        guard target == expected else { return false }
        return RecognitionUTF16.slice(text, start: utf16Start, end: utf16Start + value.utf16.count)?.utf8.elementsEqual(value.utf8)
    }
    func observe(_ expected: InputTargetSnapshot, onChange: @escaping @MainActor (InputTargetChange) -> Void) -> InputObservationSupport {
        self.onChange = onChange; return observedSupport
    }
    func stopObserving() { onChange = nil }
    func dispatch(_ value: String, to expected: InputTargetSnapshot) throws -> Bool {
        guard target == expected, let updated = OwnedInputText.replacing(text, start: target.selectionLocation,
            expected: "", replacement: value) else { return false }
        insertions.append(value); text = updated; target.selectionLocation += value.utf16.count
        onChange?(.contentOrSelection)
        return true
    }
    func verify(_ value: String, at before: InputTargetSnapshot) -> InputTargetSnapshot? {
        guard confirmsInsertion, target.sameTarget(as: before), target.selectionLength == 0,
              target.selectionLocation == before.selectionLocation + value.utf16.count,
              matchesText(value, utf16Start: before.selectionLocation, at: target) == true else { return nil }
        return target
    }
    func replaceOwned(_ expectedText: String, with replacement: String, start: Int,
                      witness: String, at expected: InputTargetSnapshot, isCurrent: @MainActor () -> Bool) throws -> Bool {
        beforeReplacement?()
        guard isCurrent(), supportsReplacement, target == expected, text.utf8.elementsEqual(witness.utf8),
              let updated = OwnedInputText.replacing(text, start: start, expected: expectedText, replacement: replacement) else { return false }
        target.selectionLocation = start; target.selectionLength = expectedText.utf16.count
        onChange?(.contentOrSelection) // The real selected-range setter's intermediate notification.
        afterSelection?()
        guard isCurrent() else { throw NativeInputError.targetChanged }
        replacements.append((start, expectedText, replacement))
        text = updated; target.selectionLocation = start + replacement.utf16.count; target.selectionLength = 0
        onChange?(.contentOrSelection)
        if throwsAfterReplacement { throw NativeInputError.unsupported }
        return true
    }
}

@MainActor
private final class OwnedFixture {
    let directory: URL
    let store: SaytileStore
    let os = OwnedRangeOS()
    let input: NativeInputCoordinator
    let binding: InputBindingInfo
    let record: Recording
    let ticket: RecognitionTicket
    let runs: [ModelRunTicket]
    var sequence: Int64 = 0
    init(observable: Bool = true, createRuns: Bool = true) async throws {
        directory = URL(fileURLWithPath: "/tmp/saytile-owned-20261107/fixtures/" + UUID().uuidString)
        store = try SaytileStore(directory: directory)
        os.observedSupport = .init(focus: true, content: observable, page: true)
        input = NativeInputCoordinator(store: store, access: os)
        binding = try await input.bindCurrentTarget()
        record = try await store.createRecording()
        ticket = try await store.beginFusionRecognition(recordingID: record.id)
        var models: [ModelRunTicket] = []
        for purpose in createRuns ? [RecognitionPurpose.chineseASR, .englishASR] : [] {
            models.append(try await store.beginModelRun(ticket: ticket, configuration: .init(purpose: purpose,
                provider: purpose == .chineseASR ? .qwenMessage : .assemblyAI, model: "synthetic-owned-range")))
        }
        runs = models
    }
    func candidates(_ text: String, complete: Bool = true) async throws -> [RecognitionCandidate] {
        sequence += 1
        let values = runs.map { RecognitionCandidate(run: $0, sequence: sequence, text: text,
            stableUTF16Length: text.utf16.count, audioEndSeconds: 1, isComplete: complete) }
        for value in values { #expect(try await store.appendRecognitionCandidate(value)) }
        return values
    }
    func publish(_ text: String, reviewed: Bool = true, complete: Bool = true,
                 unresolved: Bool = false) async throws -> FusionPublication {
        let values = try await candidates(text, complete: complete)
        let prefix = try await store.fusionReservedPrefix(recordingID: record.id)
        let proposal = reviewed
            ? try PrecisionFusion.validateSelection(spans: [.init(candidateID: values[0].id, utf16Start: 0,
                utf16End: text.utf16.count)], candidates: values, committedPrefix: prefix, unresolved: unresolved)
            : PrecisionFusion.evaluate(candidates: values, mode: .highestQuality, committedPrefix: prefix)
        return try await store.publishFusion(ticket: ticket, proposal: proposal)
    }
    func initial(_ text: String = "50😀") async throws -> TranscriptRevision {
        let revision = try #require(try await publish(text).revision)
        let result = await input.insertStable(recordingID: record.id, revisionID: revision.id,
            stableUTF16End: text.utf16.count, recordingStartedAt: record.createdAt)
        #expect(result == (os.confirmsInsertion ? .confirmed : .unverified))
        return revision
    }
    func correction(_ text: String = "500👩🏽‍💻") async throws -> TranscriptRevision {
        _ = try await publish(text)
        return try #require(try await store.ownedCorrectionCandidates(bindingID: binding.id).first)
    }
    func independent() async throws {
        let next = try await store.createRecording(), nextTicket = try await store.beginRecognition(recordingID: next.id)
        try await store.applyRecognition(ticket: nextTicket, text: "独立后段", isFinal: true)
        let revision = try #require(try await store.latestDispatchableRevision(recordingID: next.id))
        #expect(await input.insertStable(recordingID: next.id, revisionID: revision.id,
            stableUTF16End: revision.text.utf16.count, recordingStartedAt: next.createdAt) == .confirmed)
    }
    func close() async throws { input.invalidate(); try await store.close(); try FileManager.default.removeItem(at: directory) }
}

@Suite("Owned range correction production path with synthetic OS and SQLite")
@MainActor
struct OwnedRangeRepairTests {
    @Test func lengthChangingRepairPreservesUserPrefixSuffixAndAppendsOnlyNewSuffix() async throws {
        let f = try await OwnedFixture()
        let original = try await f.initial(), correction = try await f.correction()
        // Corrections are approved archives, never ordinary append candidates before verification.
        #expect(try await f.store.latestDispatchableRevision(recordingID: f.record.id)?.id == original.id)
        #expect(await f.input.repairOwned(revision: correction) == .confirmed)
        #expect(f.os.text == "用户前缀｜500👩🏽‍💻用户后缀")
        #expect(f.os.target.selectionLocation == 5 + correction.text.utf16.count)
        #expect(f.os.target.selectionLength == 0)
        #expect(f.os.replacements.count == 1)
        #expect(f.os.replacements.first?.0 == 5)
        #expect(f.os.replacements.first?.1 == "50😀")
        #expect(try await f.store.fusionReservedPrefix(recordingID: f.record.id) == correction.text)
        #expect(try await f.store.latestDispatchableRevision(recordingID: f.record.id)?.id == correction.id)
        #expect(try await f.store.ownedCorrectionCandidates(bindingID: f.binding.id).isEmpty)
        _ = await f.input.repairOwned(revision: correction)
        #expect(f.os.replacements.count == 1)
        let next = try #require(try await f.publish(correction.text + "，后续。").revision)
        #expect(await f.input.insertStable(recordingID: f.record.id, revisionID: next.id,
            stableUTF16End: next.text.utf16.count, recordingStartedAt: f.record.createdAt) == .confirmed)
        #expect(f.os.insertions == ["50😀", "，后续。"])
        #expect(f.os.text == "用户前缀｜500👩🏽‍💻，后续。用户后缀")
        #expect(await f.input.insertStable(recordingID: f.record.id, revisionID: next.id,
            stableUTF16End: next.text.utf16.count, recordingStartedAt: f.record.createdAt) == .noNewText)
        let db = try StoreDatabase(url: f.directory.appendingPathComponent("Saytile.sqlite"))
        let ops = try db.rows("SELECT revision_id,start_utf16,end_utf16,text FROM dispatches ORDER BY rowid")
        #expect(ops.count == 2 && ops[0]["revision_id"] == original.id.uuidString)
        #expect(ops[0]["end_utf16"] == ops[1]["start_utf16"])
        #expect(try db.rows("SELECT state FROM owned_corrections").first?["state"] == "confirmed")
        try db.close(); try await f.close()
    }

    @Test func localRecoveryAfterShorteningRepairKeepsEffectivePrefixAndAddsOnlySuffix() async throws {
        let f = try await OwnedFixture()
        _ = try await f.initial("500👩🏽‍💻")
        let correction = try await f.correction("50😀")
        #expect(await f.input.repairOwned(revision: correction) == .confirmed)
        let localTicket = try await f.store.beginRecognition(recordingID: f.record.id)
        let ingress = LocalCandidateIngress(store: f.store, ticket: localTicket)
        try await ingress.receive(.init(text: "50😀", stableUTF16Length: "50😀".utf16.count,
            audioEndSeconds: 1, timingGranularity: "utterance", isComplete: false))
        let same = try #require(try await f.store.latestDispatchableRevision(recordingID: f.record.id))
        #expect(await f.input.insertStable(recordingID: f.record.id, revisionID: same.id,
            stableUTF16End: same.text.utf16.count, recordingStartedAt: f.record.createdAt) == .noNewText)
        try await ingress.receive(.init(text: "50😀尾", stableUTF16Length: "50😀尾".utf16.count,
            audioEndSeconds: 2, timingGranularity: "utterance", isComplete: true))
        try await ingress.finish()
        let next = try #require(try await f.store.latestDispatchableRevision(recordingID: f.record.id))
        let ready = try await f.store.directInputCandidates(bindingID: f.binding.id, createdSince: f.binding.boundAt)
        #expect(ready.contains { $0.id == f.record.id })
        #expect(await f.input.insertStable(recordingID: f.record.id, revisionID: next.id,
            stableUTF16End: next.text.utf16.count, recordingStartedAt: f.record.createdAt) == .confirmed)
        #expect(f.os.text == "用户前缀｜50😀尾用户后缀")
        #expect(f.os.insertions == ["500👩🏽‍💻", "尾"])
        #expect(f.os.replacements.count == 1)
        try await f.close()
    }

    @Test func shorterRepairKeepsInsertionLedgerMonotone() async throws {
        let f = try await OwnedFixture()
        _ = try await f.initial("500👩🏽‍💻")
        let correction = try await f.correction("50😀")
        #expect(await f.input.repairOwned(revision: correction) == .confirmed)
        let head = try #require(try await f.publish("50😀尾").revision)
        #expect(await f.input.insertStable(recordingID: f.record.id, revisionID: head.id,
            stableUTF16End: head.text.utf16.count, recordingStartedAt: f.record.createdAt) == .confirmed)
        #expect(f.os.text == "用户前缀｜50😀尾用户后缀")
        #expect(f.os.insertions == ["500👩🏽‍💻", "尾"])
        try await f.close()
    }

    @Test(arguments: ["ownedEdit", "prefixEdit", "suffixEdit", "focus", "page", "control", "selection", "caret", "canonical"])
    func changedTargetNeverMutated(change: String) async throws {
        let f = try await OwnedFixture()
        _ = try await f.initial("50é")
        let correction = try await f.correction("500é")
        switch change {
        case "ownedEdit": f.os.text = "用户前缀｜99é用户后缀"
        case "prefixEdit": f.os.text = "别人前缀｜50é用户后缀"
        case "suffixEdit": f.os.text = "用户前缀｜50é别人后缀"
        case "focus": f.os.target.processID += 1
        case "page": f.os.target.pageIdentity = "fixture://page/2"
        case "control": f.os.target.elementID = UUID()
        case "selection": f.os.target.selectionLength = 1
        case "caret": f.os.target.selectionLocation -= 1
        default: f.os.text = "用户前缀｜50e\u{301}用户后缀" // String == is insufficient.
        }
        let before = f.os.text
        #expect(await f.input.repairOwned(revision: correction) == .correctionPending)
        #expect(f.os.text.utf8.elementsEqual(before.utf8))
        #expect(f.os.replacements.isEmpty)
        #expect(f.input.binding == nil)
        try await f.close()
    }

    @Test func userEditAndUndoStillInvalidatesOwnership() async throws {
        let f = try await OwnedFixture()
        _ = try await f.initial()
        let correction = try await f.correction()
        f.os.onChange?(.contentOrSelection) // Even byte-identical undo must not reclaim ownership.
        #expect(await f.input.repairOwned(revision: correction) == .correctionPending)
        #expect(f.os.replacements.isEmpty)
        try await f.close()
    }

    @Test func unsupportedReplacementPendingDoesNotBlockIndependentRecord() async throws {
        let f = try await OwnedFixture()
        _ = try await f.initial()
        let correction = try await f.correction()
        f.os.supportsReplacement = false
        #expect(await f.input.repairOwned(revision: correction) == .correctionPending)
        #expect(f.os.replacements.isEmpty && f.input.binding != nil)
        #expect(try await f.store.ownedCorrectionCandidates(bindingID: f.binding.id).isEmpty)
        try await f.independent()
        try await f.close()
    }

    @Test func unconfirmedInitialInsertionCannotCreateOwnershipAndDoesNotBlockNewRecord() async throws {
        let f = try await OwnedFixture()
        f.os.confirmsInsertion = false
        _ = try await f.initial()
        let correction = try await f.correction()
        #expect(await f.input.repairOwned(revision: correction) == .correctionPending)
        #expect(f.os.replacements.isEmpty)
        f.os.confirmsInsertion = true
        try await f.independent()
        try await f.close()
    }

    @Test func laterInsertionDefersEarlierCorrectionWithoutGlobalBlock() async throws {
        let f = try await OwnedFixture()
        _ = try await f.initial()
        try await f.independent()
        let correction = try await f.correction()
        #expect(await f.input.repairOwned(revision: correction) == .correctionPending)
        #expect(f.os.replacements.isEmpty)
        try await f.independent()
        try await f.close()
    }

    @Test func uncertainReplacementConsumedOnceAndRestartCannotReplay() async throws {
        let f = try await OwnedFixture()
        _ = try await f.initial()
        let correction = try await f.correction()
        f.os.throwsAfterReplacement = true
        #expect(await f.input.repairOwned(revision: correction) == .correctionPending)
        _ = await f.input.repairOwned(revision: correction)
        #expect(f.os.replacements.count == 1)
        try await f.store.close()
        let reopened = try SaytileStore(directory: f.directory)
        let input = NativeInputCoordinator(store: reopened, access: f.os)
        #expect(await input.repairOwned(revision: correction) == .correctionPending)
        #expect(try await reopened.ownedCorrectionCandidates(bindingID: f.binding.id).isEmpty)
        let newBinding = try await input.bindCurrentTarget()
        #expect(try await reopened.ownedCorrectionCandidates(bindingID: newBinding.id).isEmpty)
        #expect(f.os.replacements.count == 1)
        try await reopened.close(); try FileManager.default.removeItem(at: f.directory)
    }

    @Test func crashAfterReservationIsUnverifiedAndCannotReserveAgain() async throws {
        let f = try await OwnedFixture()
        _ = try await f.initial()
        let revision = try await f.correction()
        let op = try #require(try await f.store.reserveOwnedCorrection(bindingID: f.binding.id, revision: revision,
            targetStart: 5, expectedText: "50😀"))
        #expect(try await f.store.ownedCorrectionState(id: op.id) == "dispatching")
        #expect(try await f.store.reserveOwnedCorrection(bindingID: f.binding.id, revision: revision,
            targetStart: 5, expectedText: "50😀") == nil)
        try await f.store.close()
        let reopened = try SaytileStore(directory: f.directory)
        #expect(try await reopened.ownedCorrectionState(id: op.id) == "unverified")
        #expect(try await reopened.reserveOwnedCorrection(bindingID: f.binding.id, revision: revision,
            targetStart: 5, expectedText: "50😀") == nil)
        #expect(f.os.replacements.isEmpty)
        try await reopened.close(); try FileManager.default.removeItem(at: f.directory)
    }

    @Test func newerEvidenceRevokesStaleCorrectionEvenBeforePublication() async throws {
        let f = try await OwnedFixture()
        _ = try await f.initial()
        let stale = try await f.correction()
        _ = try await f.candidates("5000😀")
        #expect(await f.input.repairOwned(revision: stale) == .correctionPending)
        #expect(f.os.replacements.isEmpty)
        try await f.close()
    }

    @Test(arguments: ["raw", "partial", "unresolved", "draft", "edit", "unobservable", "unreadable"])
    func incompleteOrUnownedEvidenceCannotRepair(mode: String) async throws {
        let f = try await OwnedFixture(observable: mode != "unobservable")
        if mode == "unreadable" { f.os.witnessAvailable = false }
        _ = try await f.initial()
        if mode == "draft" { try await f.store.saveDraft(recordingID: f.record.id, text: "我的草稿") }
        if mode == "edit" { _ = try await f.store.saveEdit(recordingID: f.record.id, text: "我的修改") }
        _ = try await f.publish("500😀", reviewed: mode != "raw", complete: mode != "partial", unresolved: mode == "unresolved")
        let corrections = try await f.store.ownedCorrectionCandidates(bindingID: f.binding.id)
        if ["raw", "partial", "unresolved"].contains(mode) { #expect(corrections.isEmpty) }
        else {
            let correction = try #require(corrections.first)
            #expect(await f.input.repairOwned(revision: correction) == .correctionPending)
        }
        #expect(f.os.replacements.isEmpty)
        if mode == "draft" { #expect(try await f.store.loadDraft(recordingID: f.record.id) == "我的草稿") }
        if mode == "edit" { #expect(try await f.store.recording(id: f.record.id)?.text == "我的修改") }
        try await f.close()
    }

    @Test func contextualGraphemeBoundariesAndByteIdentityAreMandatory() {
        #expect(OwnedInputText.replacing("a\u{301}尾", start: 1, expected: "\u{301}", replacement: "b") == nil)
        #expect(OwnedInputText.replacing("😀尾", start: 1, expected: "", replacement: "b") == nil)
        #expect(OwnedInputText.replacing("a尾", start: 1, expected: "", replacement: "\u{301}") == nil)
        #expect(OwnedInputText.replacing("e\u{301}尾", start: 0, expected: "é", replacement: "e") == nil)
        #expect(OwnedInputText.replacing("用户50😀尾", start: 2, expected: "50😀", replacement: "500👩🏽‍💻") == "用户500👩🏽‍💻尾")
    }
}

private struct OwnedEngineProvider: StreamingASRProvider {
    func run(audio: AsyncStream<Data>, configuration: ModelConfiguration, credential: String,
             emit: @escaping @Sendable (ProviderTranscriptEvent) async throws -> Void) async throws {
        var emitted = false
        for await _ in audio where !emitted {
            emitted = true
            try await emit(.init(text: "50😀", stableUTF16Length: 4, audioEndSeconds: 1, isComplete: false))
        }
        try await emit(.init(text: "500👩🏽‍💻", stableUTF16Length: "500👩🏽‍💻".utf16.count, audioEndSeconds: 1, isComplete: true))
    }
}

extension OwnedRangeRepairTests {
    @Test func realGPTCoreFinalizationPublishesActionableCorrectionFromFakeProviders() async throws {
        let f = try await OwnedFixture(createRuns: false)
        var configuration = RecognitionConfiguration()
        configuration.cloudEnabled = true
        for i in configuration.models.indices {
            configuration.models[i].cloudConsent = true
            if configuration.models[i].provider == .qwenMessage { configuration.models[i].workspaceID = "synthetic" }
        }
        let dependencies = RecognitionPipelineDependencies(credential: { _ in "synthetic-not-a-key" },
            streaming: { _ in OwnedEngineProvider() },
            transcribe: { _, _, _ in throw ProviderFailure.incomplete },
            arbitrate: { evidence, _, _, _, _ in
                let item = try #require(evidence.first)
                return (.init(selections: [.init(candidateID: item.candidateID, utf16Start: 0, utf16End: item.text.utf16.count)],
                    unresolved: false, needsAudioReview: false, reasonCode: "synthetic-reviewed"),
                    .init(requestID: "synthetic", inputTokens: nil, outputTokens: nil, elapsedSeconds: 0))
            }, listen: { _, _, _ in throw ProviderFailure.incomplete })
        let session = MultiRecognitionSession(store: f.store, ticket: f.ticket, configuration: configuration, dependencies: dependencies)
        session.append(Data(repeating: 0, count: 32_000))
        let deadline = ContinuousClock.now.advanced(by: .seconds(5))
        var head: TranscriptRevision?
        while head == nil, ContinuousClock.now < deadline {
            head = try await f.store.latestDispatchableRevision(recordingID: f.record.id)
            try await Task.sleep(for: .milliseconds(10))
        }
        guard let head else { session.cancel(); await session.wait(); Issue.record("Fake GPT engine did not publish within deadline"); try await f.close(); return }
        #expect(head.text == "50😀")
        #expect(await f.input.insertStable(recordingID: f.record.id, revisionID: head.id,
            stableUTF16End: head.text.utf16.count, recordingStartedAt: f.record.createdAt) == .confirmed)
        session.finish(); await session.wait()
        #expect(try await f.store.recording(id: f.record.id)?.recognitionState == .completed)
        let correction = try #require(try await f.store.ownedCorrectionCandidates(bindingID: f.binding.id).first)
        #expect(correction.text == "500👩🏽‍💻")
        #expect(await f.input.repairOwned(revision: correction) == .confirmed)
        #expect(f.os.text == "用户前缀｜500👩🏽‍💻用户后缀")
        #expect(f.os.insertions == ["50😀"] && f.os.replacements.count == 1)
        try await f.close()
    }

    @Test func v3MigrationPreservesLedgerAndInvalidatesOnlyRuntimeOwnership() async throws {
        let f = try await OwnedFixture()
        let revision = try await f.initial()
        try await f.store.close()
        let old = try StoreDatabase(url: f.directory.appendingPathComponent("Saytile.sqlite"))
        try old.script("DROP TABLE owned_corrections; DROP TABLE owned_correction_heads; DROP TABLE owned_input_ranges; PRAGMA user_version=3;")
        try old.close()
        let reopened = try SaytileStore(directory: f.directory)
        #expect(try await reopened.revisions(recordingID: f.record.id).contains { $0.id == revision.id })
        #expect(try await reopened.fusionReservedPrefix(recordingID: f.record.id) == "50😀")
        let check = try StoreDatabase(url: f.directory.appendingPathComponent("Saytile.sqlite"))
        #expect(try check.rows("PRAGMA user_version").first?["user_version"] == "5")
        #expect(try check.rows("SELECT state FROM dispatches").first?["state"] == "confirmed")
        #expect(try check.rows("SELECT * FROM owned_input_ranges").isEmpty)
        try check.close(); try await reopened.close(); try FileManager.default.removeItem(at: f.directory)
    }

    @Test func deleteAudioKeepsCorrectionHistoryButDeleteRecordErasesIt() async throws {
        let f = try await OwnedFixture()
        _ = try await f.initial()
        let revision = try await f.correction()
        #expect(await f.input.repairOwned(revision: revision) == .confirmed)
        try await f.store.finishRecording(id: f.record.id)
        try await f.store.deleteAudio(recordingID: f.record.id)
        #expect(try await f.store.revisions(recordingID: f.record.id).contains { $0.id == revision.id })
        let db = try StoreDatabase(url: f.directory.appendingPathComponent("Saytile.sqlite"))
        #expect(try db.rows("SELECT state FROM owned_corrections").first?["state"] == "confirmed")
        try await f.store.deleteRecord(recordingID: f.record.id)
        #expect(try db.rows("SELECT * FROM owned_corrections").isEmpty)
        #expect(try db.rows("SELECT * FROM owned_input_ranges").isEmpty)
        #expect(try db.rows("SELECT * FROM owned_correction_heads").isEmpty)
        try db.close(); try await f.close()
    }
}

extension OwnedRangeRepairTests {
    @Test func durableReservationPrecedesSelectedRangeAndInvalidationPreventsTextSetter() async throws {
        let f = try await OwnedFixture()
        _ = try await f.initial()
        let correction = try await f.correction()
        let db = try StoreDatabase(url: f.directory.appendingPathComponent("Saytile.sqlite"))
        f.os.beforeReplacement = {
            #expect((try? db.rows("SELECT state FROM owned_corrections").first?["state"]) == "dispatching")
            #expect((try? db.rows("SELECT valid FROM owned_input_ranges").first?["valid"]) == "0")
        }
        f.os.afterSelection = { f.os.onChange?(.focusOrDocument) }
        let before = f.os.text
        #expect(await f.input.repairOwned(revision: correction) == .correctionPending)
        #expect(f.os.text == before && f.os.replacements.isEmpty)
        #expect(try db.rows("SELECT state FROM owned_corrections").first?["state"] == "unverified")
        #expect(f.input.binding == nil)
        try db.close(); try await f.close()
    }
}


extension OwnedRangeRepairTests {
    @Test(arguments: ["queued", "failedExpert", "failedSession", "newGeneration"])
    func cancelledOrFailedEvidenceCannotAuthorizePreviouslyApprovedRepair(state: String) async throws {
        let f = try await OwnedFixture()
        _ = try await f.initial()
        let correction = try await f.correction()
        switch state {
        case "queued": try await f.store.queueRecognition(recordingID: f.record.id)
        case "failedExpert": try await f.store.finishModelRun(f.runs[0], error: "synthetic failure")
        case "failedSession": try await f.store.failRecognition(ticket: f.ticket, message: "synthetic failure")
        default: _ = try await f.store.beginFusionRecognition(recordingID: f.record.id)
        }
        #expect(await f.input.repairOwned(revision: correction) == .correctionPending)
        #expect(f.os.replacements.isEmpty)
        try await f.close()
    }
}
