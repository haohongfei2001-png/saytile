import Foundation
import Testing
@testable import RiftletFeedback

@Suite struct FeedbackProductTests {
    private let id = UUID(uuidString: "9c40dd33-d68e-4560-8c2e-d2202182d402")!

    @Test func absentProductPreservesLegacyCanonicalBytesAndDecoding() throws {
        let envelope = try FeedbackEnvelope(draft: .init(text: "中文 / feedback", revision: 1), id: id,
            appVersion: "0.19", now: Date(timeIntervalSince1970: 1700000000))
        let expected = #"{"appVersion":"0.19","createdAt":1700000000,"id":"9c40dd33-d68e-4560-8c2e-d2202182d402","kind":"problem","schema":1,"text":"中文 / feedback"}"#
        #expect(try envelope.encoded() == Data(expected.utf8))
        #expect(try JSONDecoder().decode(FeedbackEnvelope.self, from: Data(expected.utf8)) == envelope)
        #expect(envelope.product == nil)
    }

    @Test func explicitProductIsClosedAndIncludedInFrozenEnvelope() throws {
        for product in FeedbackProduct.allCases {
            let envelope = try FeedbackEnvelope(draft: .init(text: "产品反馈"), id: id,
                appVersion: "0.19", product: product)
            let bytes = try envelope.encoded()
            let json = try #require(JSONSerialization.jsonObject(with: bytes) as? [String: Any])
            #expect(json["product"] as? String == product.rawValue)
            #expect(Set(json.keys) == Set(["schema", "id", "kind", "text", "appVersion", "createdAt", "product"]))
            #expect(try JSONDecoder().decode(FeedbackEnvelope.self, from: bytes) == envelope)
        }
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(FeedbackProduct.self, from: Data("\"arbitrary-host\"".utf8))
        }
    }

    @Test func reportCapabilitiesUseSeparateProductAndCandidateNamespaces() {
        let riftlet = KeychainFeedbackSecrets(namespace: "Riftlet")
        let saytile = KeychainFeedbackSecrets(namespace: "app.saytile.mac")
        let candidate = KeychainFeedbackSecrets(namespace: "app.saytile.mac.mandarin-candidate")
        #expect(riftlet.service == "com.riftlet.feedback.v1.Riftlet")
        #expect(Set([riftlet.service, saytile.service, candidate.service]).count == 3)
        // This contract inspects service strings only. No real Keychain item is read or created.
    }

    @Test func productAndBytesSurviveOfflineEnqueueRestartAndLaterDraftChanges() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("saytile-feedback-product-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try FeedbackStore(directory: directory)
        let secrets = MemoryFeedbackSecrets()
        let engine = FeedbackEngine(store: store, secrets: secrets, transport: DisabledFeedbackTransport())
        let first = try await engine.enqueue(.init(text: "必须留在Saytile分类", revision: 1), appVersion: "0.19", product: .saytile)
        let repeated = try await engine.enqueue(.init(text: "必须留在Saytile分类", revision: 1), appVersion: "0.20", product: .saytile)
        #expect(first == repeated)
        let initial = try #require(await store.records().first)
        #expect(initial.envelope.product == .saytile)
        #expect(initial.envelope.appVersion == "0.19")
        try await store.saveDraft(.init(text: "后续草稿不得改写已提交正文", revision: 3))
        await engine.pump()
        #expect(try await store.records().first?.attempts == 0)
        await engine.stop()
        try await store.closeForTesting(clean: true)
        let reopened = try FeedbackStore(directory: directory)
        let retained = try #require(await reopened.records().first)
        #expect(retained.id == first && retained.envelope.product == .saytile)
        #expect(retained.bytes == initial.bytes && retained.state == .queued)
        #expect(try await reopened.draft().text == "后续草稿不得改写已提交正文")
        try await reopened.closeForTesting(clean: true)
    }
}
