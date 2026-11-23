import Foundation
import Testing
@testable import SaytileKit

@Suite("Meta Muse actual streaming protocol; no cloud calls")
struct MetaProviderProtocolTests {
    private var configuration: ModelConfiguration {
        .init(purpose: .englishASR, provider: .meta, model: "muse-voice-transcribe-1.0", cloudConsent: true)
    }
    private func object(_ value: String) throws -> [String: Any] {
        try #require(JSONSerialization.jsonObject(with: Data(value.utf8)) as? [String: Any])
    }

    @Test func authenticationUsesFirstFrameAndSharedPCMEncoding() throws {
        let request = try MetaStreamingProvider.request(configuration: configuration, credential: "fixture-key")
        #expect(request.url?.absoluteString == "wss://api.meta.ai/v1/asr/realtime")
        #expect(request.value(forHTTPHeaderField: "Authorization") == nil)
        #expect(!request.url!.absoluteString.contains("fixture-key"))
        let handshake = try object(MetaStreamingProvider.handshake(configuration: configuration, credential: "fixture-key"))
        let authorization = try #require(handshake["authorization"] as? [String: String])
        #expect(authorization["accessToken"] == "Bearer fixture-key")
        #expect(handshake["audioEncoding"] as? String == "PCM_16KHZ")
        #expect(handshake["mode"] as? String == "ENDPOINTING")
        #expect(handshake["partialMode"] as? String == "CUMULATIVE")
        #expect(handshake["languageBias"] as? [String] == ["Mandarin Chinese", "English"])
        #expect(handshake["model"] as? String == "muse-voice-transcribe-1.0")
    }

    @Test func acknowledgementHasNoTypeAndRequiresARealSessionID() throws {
        let id = try MetaStreamingProvider.sessionID(object(#"{"sessionId":"fixture-session"}"#))
        #expect(id == "fixture-session")
        #expect(throws: Error.self) { try MetaStreamingProvider.sessionID(object(#"{"type":"session_started","sessionId":"x"}"#)) }
        #expect(throws: Error.self) { try MetaStreamingProvider.sessionID(object(#"{"sessionId":""}"#)) }
    }

    @Test func partialsReplaceAndSpeechEndDoesNotFinalize() throws {
        var decoder = MetaTranscriptAccumulator(requestID: "fixture-session")
        _ = try decoder.accept(object(#"{"type":"speechStart","turnId":42,"audioProcessedMs":200}"#))
        _ = try decoder.accept(object(#"{"type":"transcript","transcript":"Pay 50","final":false,"audioProcessedMs":900}"#))
        let revisedResult = try decoder.accept(object(#"{"type":"transcript","transcript":"Do not pay 15 😀","final":true,"audioProcessedMs":1800}"#))
        let revised = try #require(revisedResult)
        #expect(revised.text == "Do not pay 15 😀")
        #expect(revised.stableUTF16Length == 0)
        #expect(!revised.isComplete)
        let boundaryResult = try decoder.accept(object(#"{"type":"speechEnd","turnId":42,"audioProcessedMs":2000}"#))
        let boundary = try #require(boundaryResult)
        #expect(boundary.stableUTF16Length == 0)
        let completeResult = try decoder.accept(object(#"{"type":"speechComplete","turnId":42,"transcript":"Do not pay 15 😀.","audioProcessedMs":2200}"#))
        let complete = try #require(completeResult)
        #expect(complete.stableUTF16Length == complete.text.utf16.count)
        #expect(!complete.isComplete)
        #expect(complete.timingGranularity == "turn-progress")
        #expect(complete.tokens.count == 1)
        #expect(complete.tokens[0].startSeconds == 0.2)
        #expect(complete.tokens[0].endSeconds == 2)
        #expect(complete.tokens[0].rawConfidence == nil)
        #expect(complete.language == nil)
    }

    @Test func lateEarlierCompletionDoesNotStealLatestTurnPartials() throws {
        var decoder = MetaTranscriptAccumulator(requestID: "fixture-session")
        _ = try decoder.accept(object(#"{"type":"speechStart","turnId":42,"audioProcessedMs":0}"#))
        _ = try decoder.accept(object(#"{"type":"transcript","transcript":"first","final":false,"audioProcessedMs":500}"#))
        _ = try decoder.accept(object(#"{"type":"speechEnd","turnId":42,"audioProcessedMs":1000}"#))
        _ = try decoder.accept(object(#"{"type":"speechStart","turnId":7,"audioProcessedMs":1200}"#))
        _ = try decoder.accept(object(#"{"type":"transcript","transcript":"sec","final":false,"audioProcessedMs":1500}"#))
        _ = try decoder.accept(object(#"{"type":"speechComplete","turnId":42,"transcript":"First.","audioProcessedMs":1000}"#))
        let result = try decoder.accept(object(#"{"type":"transcript","transcript":"second","final":false,"audioProcessedMs":1800}"#))
        let event = try #require(result)
        #expect(event.text == "First. second")
        #expect(event.stableUTF16Length == "First.".utf16.count)
        #expect(event.tokens.map(\.text) == ["First.", "second"])
        #expect(event.tokens.last?.startSeconds == 1.2)
    }

    @Test func onlyEOSEveryCompletedTurnAndNormalCloseCanCompleteSession() throws {
        var decoder = MetaTranscriptAccumulator(requestID: "fixture-session")
        _ = try decoder.accept(object(#"{"type":"speechStart","turnId":1,"audioProcessedMs":0}"#))
        _ = try decoder.accept(object(#"{"type":"transcript","transcript":"yes yes","final":false,"audioProcessedMs":500}"#))
        #expect(throws: Error.self) { try decoder.completedEvent(endStreamSent: true, normalClose: true, duration: 1) }
        _ = try decoder.accept(object(#"{"type":"speechEnd","turnId":1,"audioProcessedMs":800}"#))
        _ = try decoder.accept(object(#"{"type":"speechComplete","turnId":1,"transcript":"yes yes","audioProcessedMs":900}"#))
        #expect(throws: Error.self) { try decoder.completedEvent(endStreamSent: false, normalClose: true, duration: 1) }
        #expect(throws: Error.self) { try decoder.completedEvent(endStreamSent: true, normalClose: false, duration: 1) }
        let event = try decoder.completedEvent(endStreamSent: true, normalClose: true, duration: 1)
        #expect(event.isComplete)
        #expect(event.text == "yes yes")
        #expect(event.audioEndSeconds == 1)
    }

    @Test func missingBoundaryInvalidTimeAndUnknownTurnAreNotInvented() throws {
        var decoder = MetaTranscriptAccumulator(requestID: "fixture-session")
        #expect(throws: Error.self) { try decoder.accept(object(#"{"type":"speechStart","turnId":1,"audioProcessedMs":true}"#)) }
        _ = try decoder.accept(object(#"{"type":"speechStart","turnId":1,"audioProcessedMs":0}"#))
        #expect(throws: Error.self) { try decoder.accept(object(#"{"type":"speechComplete","turnId":1,"transcript":"hello","audioProcessedMs":1000}"#)) }
        #expect(throws: Error.self) { try decoder.accept(object(#"{"type":"speechEnd","turnId":2,"audioProcessedMs":1000}"#)) }
        let unknown = try decoder.accept(object(#"{"type":"future-metadata","extra":"value"}"#))
        #expect(unknown == nil)
    }

    @Test func errorDetailsRemainSanitizedAndConfigurationIsExplicit() throws {
        let failure = MetaTranscriptAccumulator.error(try object(#"{"type":"error","errorType":"authentication_error","message":"secret-user-text fixture-key"}"#))
        #expect(!failure.canRetryAutomatically)
        #expect(failure.errorDescription?.contains("secret-user-text") == false)
        #expect(failure.errorDescription?.contains("fixture-key") == false)
        var denied = configuration; denied.cloudConsent = false
        #expect(throws: Error.self) { try MetaStreamingProvider.request(configuration: denied, credential: "fixture-key") }
        let policyCode = try #require(URLSessionWebSocketTask.CloseCode(rawValue: 1008))
        #expect(!MetaStreamingProvider.closeFailure(policyCode).canRetryAutomatically)
    }

    @Test func recommendationIsOptionalAndDoesNotReplaceTheDefaultExpert() {
        let models = RecognitionConfiguration().models
        #expect(models.contains { $0.provider == .meta && $0.model == "muse-voice-transcribe-1.0" && !$0.enabled && $0.purpose == .englishASR })
        #expect(models.contains { $0.provider == .assemblyAI && $0.enabled && $0.purpose == .englishASR })
        #expect(CloudProvider.meta.supports(.englishASR))
        #expect(!CloudProvider.meta.supports(.finalASR))
    }
}
