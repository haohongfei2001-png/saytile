import Foundation
import Testing
@testable import SaytileKit

@Suite("On-device streaming and model integrity")
struct LocalModelTests {
    @Test func pinnedCatalogSeparatesBatchFromStreaming() throws {
        #expect(LocalASRID.allCases.filter { $0.capability == .streaming } == [.apple,.sherpa,.nemotron,.zipformer])
        #expect(LocalASRID.consumer == [.apple,.sherpa,.qwen])
        #expect(!LocalASRID.consumer.contains(.zipformer))
        #expect(LocalASRID.qwen.capability == .chunked)
        #expect(Set(LocalASRID.allCases.map(\.evidenceID)).count == 8)
        for id in LocalASRID.allCases where id != .apple {
            let manifest = try LocalModelManifest.load(id)
            #expect(manifest.size > 0)
            #expect(manifest.id == id)
        }
    }
    @Test func chunkCorrectionsStayInTheTailWithoutManufacturingEvidence() {
        var text = LocalLiveText(model: .qwen)
        #expect(text.accept("我们计划星期五下午三点开会确认", final: false) == 0)
        #expect(text.accept("我们计划星期五下午三点开会确认时间", final: false) == 0)
        #expect(text.accept("完全不同的一句话", final: false) == nil)
        #expect(text.accept("我们计划星期五下午四点开会确认时间", final: false) == 0)
        #expect(text.accept("最终原话", final: true) == 4)
        #expect(LocalModelRecommendation.select(appleInstalled: false, sherpaInstalled: true) == .sherpa)
    }
    @Test func confirmedNumberRenderingCanResumeAPreviewButCannotCreateDispatchEvidence() {
        var q = LocalLiveText(model: .qwen)
        for text in ["二十九岁的马拉巴拉。", "二十九岁的马拉巴拉斯巴拉米尼亚。",
                     "二十九岁的马拉巴拉斯巴拉米尼亚医生在俄。"] {
            #expect(q.accept(text, final: false) == 0)
        }
        #expect(q.accept("29歲的Malala Sabra Miliam一生在俄亥俄州新。", final: false) == nil)
        #expect(q.accept("29岁的马拉巴拉斯巴拉米亚姆医生在俄亥俄州新近亚提市以北。", final: false) == nil)
        #expect(q.accept("29岁的马拉巴拉斯巴拉米亚姆医生在俄亥俄州新近亚提市，以北约15公里。", final: false) == 0)
        let unrelated = "同样的长度不能证明完全不同的识别结果有权替换此前的预览。"
        #expect(q.accept(unrelated, final: false) == nil)
        #expect(q.accept(unrelated + "更多", final: false) == nil)
    }
    @Test func changedSameLengthWeightsCannotBeOpened() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let library = LocalModelLibrary(root: root)
        let file = LocalModelManifest.File(path: "weights", bytes: 3,
            sha256: "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
        let manifest = LocalModelManifest(id: .sherpa, repo: "fixture/model", revision: "fixture", license: "fixture", files: [file])
        let directory = await library.directory(manifest)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appending(path: file.path)
        try Data("abc".utf8).write(to: url)
        #expect(try await library.validated(manifest) == directory)
        try Data("abd".utf8).write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSince1970: 1234)], ofItemAtPath: url.path)
        await #expect(throws: (any Error).self) { try await library.validated(manifest) }
    }
    @Test func shortPipeLineArrivesWithInputStillOpen() async throws {
        let dir = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let executable = dir.appending(path: "SaytileSherpa")
        try Data("#!/bin/sh\nprintf '%s\\n' '{\"kind\":\"partial\",\"text\":\"测试\",\"frames\":320}'\nread waiting\n".utf8).write(to: executable)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: executable.path)
        let worker = try ModelWorker(id: .sherpa, directory: dir, helpers: dir, stride: 19_200)
        defer { worker.stop() }
        let timeout = Task { do { try await Task.sleep(for: .seconds(3)) } catch { return }; worker.stop() }
        defer { timeout.cancel() }
        var iterator = worker.events.makeAsyncIterator()
        let event = try await iterator.next()
        #expect(event?.text == "测试")
        #expect(worker.process.isRunning)
    }
    @Test(arguments: ["verified","revoked","offline"]) func localFinalReviewRetainsEvidence(mode: String) async throws {
        let dir = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = try SaytileStore(directory: dir)
        let recording = try await store.createRecording()
        let ticket = try await store.beginRecognition(recordingID: recording.id)
        let item = ModelConfiguration(purpose: .textFusion, provider: .openAIResponses, model: "gpt-6-astra")
        var dependencies = RecognitionPipelineDependencies.live
        dependencies.credential = { _ in "fixture" }
        dependencies.arbitrate = { evidence, prefix, context, _, _ in
            #expect(mode != "revoked")
            #expect(evidence.count == 1 && prefix.isEmpty && context.isEmpty)
            #expect(evidence.first?.provider == LocalASRID.sherpa.rawValue)
            if mode == "offline" { throw URLError(.notConnectedToInternet) }
            let candidate = try #require(evidence.first)
            let selection = ReviewSelection(candidateID: candidate.candidateID, utf16Start: 0, utf16End: candidate.text.utf16.count)
            return (.init(selections: [selection], unresolved: false, needsAudioReview: false, reasonCode: "single-source-supported"),
                    .init(requestID: "fixture", inputTokens: 10, outputTokens: 5, elapsedSeconds: 0))
        }
        let review = try #require(LocalTextReview(model: item, dependencies: dependencies))
        let ingress = LocalCandidateIngress(store: store, ticket: ticket, model: .sherpa, review: review)
        try await ingress.receive(.init(text: "不是", stableUTF16Length: 0, audioEndSeconds: 0.8))
        #expect(try await store.recording(id: recording.id)?.text == "不是")
        #expect(try await store.modelRuns(recordingID: recording.id).count == 1)
        if mode == "revoked" { review.revoke() }
        let text = "不是三十，是十三。"
        try await ingress.receive(.init(text: text, stableUTF16Length: text.utf16.count, audioEndSeconds: 2, isComplete: true))
        try await ingress.finish()
        #expect(try await store.recording(id: recording.id)?.text == text)
        #expect(try await store.recording(id: recording.id)?.recognitionState == .completed)
        #expect(try await store.modelRuns(recordingID: recording.id).count == (mode == "revoked" ? 1 : 2))
        if mode == "verified" { #expect(try await store.modelUsage(recordingID: recording.id).first?.audioSeconds == 0) }
    }
}
