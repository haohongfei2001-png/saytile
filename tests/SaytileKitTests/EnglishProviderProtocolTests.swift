import Foundation
import Testing
@testable import SaytileKit

@Suite("English provider wire contracts; no cloud calls")
struct EnglishProviderProtocolTests {
    private func config(_ provider: CloudProvider, _ model: String, purpose: RecognitionPurpose = .englishASR) -> ModelConfiguration {
        ModelConfiguration(purpose: purpose, provider: provider, model: model, cloudConsent: true)
    }
    private func object(_ json: String) throws -> [String: Any] {
        try #require(JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any])
    }

    @Test func assemblyUsesExplicitStreamingModelAndHeaderAuthentication() throws {
        var configuration = config(.assemblyAI, "universal-3-6-pro")
        configuration.region = "eu"
        let request = try AssemblyStreamingProvider.request(configuration: configuration, credential: "fixture-key")
        #expect(request.url?.host == "streaming.eu.assemblyai.com")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "fixture-key")
        let url = try #require(request.url)
        let query = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems)
        #expect(query.first { $0.name == "speech_model" }?.value == "universal-3-6-pro")
        #expect(query.first { $0.name == "mode" }?.value == "max_accuracy")
        #expect(query.first { $0.name == "sample_rate" }?.value == "16000")
        #expect(!query.contains { $0.name == "token" || $0.name == "language_codes" })
        #expect(!request.url!.absoluteString.contains("fixture-key"))
    }

    @Test func assemblyChecksTheServersAppliedModelAndAccuracyMode() throws {
        let configuration = config(.assemblyAI, "universal-3-6-pro")
        let correct = try object(#"{"type":"Begin","id":"session","configuration":{"model":"universal-3-6-pro","mode":"max_accuracy"}}"#)
        #expect(try AssemblyStreamingProvider.verifyBegin(correct, configuration: configuration) == "session")
        #expect(throws: Error.self) {
            try AssemblyStreamingProvider.verifyBegin(object(#"{"type":"Begin","configuration":{"model":"universal-3-5-pro","mode":"max_accuracy"}}"#), configuration: configuration)
        }
        #expect(throws: Error.self) {
            try AssemblyStreamingProvider.verifyBegin(object(#"{"type":"Begin","configuration":{"model":"universal-3-6-pro","mode":"balanced"}}"#), configuration: configuration)
        }
    }

    @Test func cloudPermissionAndCredentialValidationHappenBeforeNetworking() {
        var configuration = config(.assemblyAI, "universal-3-6-pro")
        configuration.cloudConsent = false
        #expect(throws: Error.self) { try AssemblyStreamingProvider.request(configuration: configuration, credential: "key") }
        configuration.cloudConsent = true
        #expect(throws: Error.self) { try AssemblyStreamingProvider.request(configuration: configuration, credential: "key\r\nInjected: x") }
        configuration.region = "unverified-region"
        #expect(throws: Error.self) { try AssemblyStreamingProvider.request(configuration: configuration, credential: "key") }
    }

    @Test func assemblyReplacesTurnAndPreservesNegationNumbersUnicodeAndRawConfidence() throws {
        var state = AssemblyTranscriptAccumulator(requestID: "fixture-session")
        let partial = try state.accept(object(#"{"turn_order":0,"transcript":"Pay 50 😀","end_of_turn":false,"words":[{"text":"Pay","start":0,"end":500,"confidence":0.7},{"text":"50","start":500,"end":900},{"text":"😀","start":900,"end":1000}]}"#), duration: 2)
        #expect(partial.stableUTF16Length == 0)
        #expect(partial.tokens.first?.isFinal == false)
        let revised = try state.accept(object(#"{"turn_order":0,"transcript":"Do not pay 15 😀","turn_is_formatted":true,"end_of_turn":true,"language_code":"en","words":[{"text":"Do","start":0,"end":400},{"text":"not","start":500,"end":750,"confidence":0.91},{"text":"pay","start":800,"end":1000},{"text":"15","start":1100,"end":1200},{"text":"😀","start":1200,"end":1300}]}"#), duration: 2)
        #expect(revised.text == "Do not pay 15 😀")
        #expect(revised.stableUTF16Length == revised.text.utf16.count)
        #expect(revised.tokens.dropFirst().first?.startSeconds == 0.5)
        #expect(revised.tokens.dropFirst().first?.endSeconds == 0.75)
        #expect(revised.tokens.dropFirst().first?.rawConfidence == 0.91)
        #expect(!revised.isComplete)
        #expect(revised.requestID == "fixture-session")
    }

    @Test func intentionalRepeatedTurnsAreNotDeduplicated() throws {
        var state = AssemblyTranscriptAccumulator(requestID: nil)
        _ = try state.accept(object(#"{"turn_order":0,"transcript":"yes","turn_is_formatted":true,"end_of_turn":true}"#), duration: 1)
        let event = try state.accept(object(#"{"turn_order":1,"transcript":"yes","turn_is_formatted":true,"end_of_turn":true}"#), duration: 2)
        #expect(event.text == "yes yes")
        #expect(event.stableUTF16Length == 7)
    }

    @Test func missingOrUnfinishedEarlierTurnBlocksStablePrefix() throws {
        var state = AssemblyTranscriptAccumulator(requestID: nil)
        let missing = try state.accept(object(#"{"turn_order":1,"transcript":"second","turn_is_formatted":true,"end_of_turn":true}"#), duration: 2)
        #expect(missing.stableUTF16Length == 0)
        #expect(!state.allTurnsFinal)
        let partial = try state.accept(object(#"{"turn_order":0,"transcript":"first","end_of_turn":false}"#), duration: 2)
        #expect(partial.text == "first second")
        #expect(partial.stableUTF16Length == 0)
        #expect(!state.allTurnsFinal)
        let final = try state.accept(object(#"{"turn_order":0,"transcript":"first","turn_is_formatted":true,"end_of_turn":true}"#), duration: 2)
        #expect(final.stableUTF16Length == final.text.utf16.count)
        #expect(state.allTurnsFinal)
    }

    @Test func malformedWordTimesAreNeverInvented() throws {
        var state = AssemblyTranscriptAccumulator(requestID: nil)
        #expect(throws: Error.self) {
            try state.accept(object(#"{"turn_order":0,"transcript":"no","turn_is_formatted":true,"end_of_turn":true,"words":[{"text":"no","start":900,"end":200}]}"#), duration: 1)
        }
    }

    @Test func assemblyPartialUsesOnlyContiguousFinalWordsAndPreservesSeparators() throws {
        var state = AssemblyTranscriptAccumulator(requestID: nil)
        let event = try state.accept(object(#"{"turn_order":0,"transcript":"I do not pay 15.","end_of_turn":false,"words":[{"text":"I","start":0,"end":100,"word_is_final":true},{"text":"do","start":100,"end":200,"word_is_final":true},{"text":"not","start":200,"end":300,"word_is_final":false},{"text":"pay","start":300,"end":400,"word_is_final":true},{"text":"15.","start":400,"end":500,"word_is_final":true}]}"#), duration: 1)
        #expect(event.tokens.map(\.text) == ["I", "do", "not", "pay", "15."])
        #expect(event.tokens[1].text == "do")
        #expect(event.stableUTF16Length == "I do".utf16.count)
        #expect(event.tokens[1].startSeconds == 0.1)
        #expect(!state.allTurnsFinal)
    }

    @Test func punctuationIsCopiedFromTranscriptWithoutInventingAudioTime() throws {
        let words: [ProviderToken] = [
            .init(text: "Hello", startSeconds: 0.2, endSeconds: 0.5, isFinal: true),
            .init(text: "world", startSeconds: 0.8, endSeconds: 1.2, isFinal: true)
        ]
        let aligned = try #require(EnglishProviderSupport.align(words, to: "Hello,  world!", utteranceFinal: true))
        #expect(aligned.map(\.text).joined() == "Hello,  world!")
        #expect(aligned[1].text == ",  world!")
        #expect(aligned[1].startSeconds == 0.8)
        #expect(aligned[1].endSeconds == 1.2)
        #expect(EnglishProviderSupport.align(words, to: "Hello brave world!", utteranceFinal: true) == nil)
    }

    @Test func unmatchedFormattedWordsDowngradeTimingWithoutLosingText() throws {
        var state = AssemblyTranscriptAccumulator(requestID: nil)
        let event = try state.accept(object(#"{"turn_order":0,"transcript":"Pay $15.","end_of_turn":true,"turn_is_formatted":true,"words":[{"text":"Pay","start":0,"end":200},{"text":"fifteen","start":200,"end":600}]}"#), duration: 1)
        #expect(event.text == "Pay $15.")
        #expect(event.tokens.map(\.text) == ["Pay", "fifteen"])
        #expect(event.timingGranularity == "utterance")
        #expect(event.stableUTF16Length == event.text.utf16.count)
    }

    @Test func unformattedFinalDoesNotClaimFormattedTurnCompletion() throws {
        var state = AssemblyTranscriptAccumulator(requestID: nil)
        let event = try state.accept(object(#"{"turn_order":0,"transcript":"hello","end_of_turn":true,"turn_is_formatted":false,"words":[{"text":"hello","start":0,"end":200,"word_is_final":true}]}"#), duration: 1)
        #expect(event.stableUTF16Length == 5)
        #expect(!state.allTurnsFinal)
    }

    @Test func elevenRealtimeIsDistinctAndNeverEnablesParaphrasing() throws {
        let request = try ElevenLabsStreamingProvider.request(configuration: config(.elevenLabsRealtime, "scribe_v2_realtime"), credential: "fixture-key")
        #expect(request.value(forHTTPHeaderField: "xi-api-key") == "fixture-key")
        let url = try #require(request.url)
        let query = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems)
        #expect(query.first { $0.name == "model_id" }?.value == "scribe_v2_realtime")
        #expect(query.first { $0.name == "commit_strategy" }?.value == "manual")
        #expect(query.first { $0.name == "no_verbatim" }?.value == "false")
        #expect(!query.contains { $0.name == "transcript_edit" || $0.name == "language_code" })
        let bytes = Data([0, 128, 255, 127])
        let message = try object(ElevenLabsStreamingProvider.audioMessage(bytes, commit: true))
        let encodedAudio = try #require(message["audio_base_64"] as? String)
        #expect(Data(base64Encoded: encodedAudio) == bytes)
        #expect(message["commit"] as? Bool == true)
    }

    @Test func delayedElevenTimestampsReplaceTheCommittedCandidate() throws {
        var state = ElevenLabsTranscriptAccumulator(requestID: "fixture-session")
        let partialResult = try state.accept(object(#"{"message_type":"partial_transcript","text":"no no"}"#), duration: 1, inputEnded: false)
        let partial = try #require(partialResult)
        #expect(partial.stableUTF16Length == 0)
        let committedResult = try state.accept(object(#"{"message_type":"committed_transcript","text":"no no"}"#), duration: 1, inputEnded: true)
        let committed = try #require(committedResult)
        #expect(!committed.isComplete)
        let timedResult = try state.accept(object(#"{"message_type":"committed_transcript_with_timestamps","text":"no no","language_code":"en","words":[{"text":"no","start":0.2,"end":0.4,"type":"word"},{"text":"no","start":0.6,"end":0.8,"type":"word"}]}"#), duration: 1, inputEnded: true)
        let timed = try #require(timedResult)
        #expect(timed.text == "no no")
        #expect(timed.tokens.count == 2)
        #expect(timed.tokens.last?.startSeconds == 0.6)
        #expect(timed.isComplete)
        let keepalive = try state.accept(object(#"{"message_type":"partial_transcript","text":""}"#), duration: 1, inputEnded: true)
        #expect(keepalive == nil)
    }

    @Test func unexpectedOrContradictoryElevenCommitIsRejected() throws {
        var state = ElevenLabsTranscriptAccumulator(requestID: nil)
        #expect(throws: Error.self) {
            try state.accept(object(#"{"message_type":"committed_transcript","text":"15"}"#), duration: 1, inputEnded: false)
        }
        _ = try state.accept(object(#"{"message_type":"committed_transcript","text":"15"}"#), duration: 1, inputEnded: true)
        #expect(throws: Error.self) {
            try state.accept(object(#"{"message_type":"committed_transcript_with_timestamps","text":"50","words":[]}"#), duration: 1, inputEnded: true)
        }
    }

    @Test func fileRequestsContainBinaryMultipartAndProviderSpecificAuthentication() throws {
        let pcm = Data(repeating: 0x7f, count: 3_200)
        let eleven = try FinalASRProvider.request(pcm: pcm, configuration: config(.elevenLabsFile, "scribe_v2", purpose: .finalASR), credential: "fixture-key", boundary: "test-boundary")
        #expect(eleven.url?.absoluteString == "https://api.elevenlabs.io/v1/speech-to-text")
        #expect(eleven.value(forHTTPHeaderField: "xi-api-key") == "fixture-key")
        let elevenBody = try #require(eleven.httpBody)
        #expect(elevenBody.range(of: pcm) != nil)
        #expect(elevenBody.range(of: Data("pcm_s16le_16".utf8)) != nil)
        #expect(elevenBody.range(of: Data("\r\n--test-boundary--\r\n".utf8)) != nil)
        #expect(elevenBody.range(of: Data("transcript_edit".utf8)) == nil)
        var openAIConfig = config(.openAITranscription, "gpt-transcribe", purpose: .finalASR)
        openAIConfig.context = "SwiftUI 与 SQLite 的原文听写"
        let openAI = try FinalASRProvider.request(pcm: pcm, configuration: openAIConfig, credential: "fixture-key", boundary: "test-boundary")
        #expect(openAI.value(forHTTPHeaderField: "Authorization") == "Bearer fixture-key")
        let openAIBody = try #require(openAI.httpBody)
        #expect(openAIBody.range(of: PCMJournal.header(frames: 1_600) + pcm) != nil)
        #expect(openAIBody.range(of: Data("name=\"model\"\r\n\r\ngpt-transcribe\r\n".utf8)) != nil)
        #expect(openAIBody.range(of: Data("language".utf8)) == nil)
        #expect(openAIBody.range(of: Data("name=\"prompt\"\r\n\r\nSwiftUI 与 SQLite 的原文听写\r\n".utf8)) != nil)
    }

    @Test func fileResultsKeepWordsInSecondsAndDoNotFabricateConfidence() throws {
        let eleven = try FinalASRProvider.parse(Data(#"{"text":"Do not pay 15.","language_code":"eng","words":[{"text":"Do","start":0.0,"end":0.2,"type":"word"},{"text":"not","start":0.3,"end":0.5,"type":"word","logprob":-0.01},{"text":"pay","start":0.5,"end":0.8,"type":"word"},{"text":"15.","start":0.8,"end":1.0,"type":"word"}]}"#.utf8), provider: .elevenLabsFile, duration: 2, requestID: "file-id")
        #expect(eleven.tokens.dropFirst().first?.startSeconds == 0.3)
        #expect(eleven.tokens.first?.rawConfidence == nil)
        #expect(eleven.isComplete)
        let openAI = try FinalASRProvider.parse(Data(#"{"text":"我想使用 SQLite 😀","languages":[{"code":"zh"},{"code":"en"}]}"#.utf8), provider: .openAITranscription, duration: 2, requestID: nil)
        #expect(openAI.tokens.isEmpty)
        #expect(openAI.timingGranularity == "utterance")
        #expect(openAI.language == nil)
        #expect(openAI.stableUTF16Length == openAI.text.utf16.count)
        #expect(openAI.text == "我想使用 SQLite 😀")
    }

    @Test func badPCMCannotSilentlyBecomeAnAudioRequest() {
        let configuration = config(.openAITranscription, "gpt-transcribe", purpose: .finalASR)
        #expect(throws: Error.self) { try FinalASRProvider.request(pcm: Data([1]), configuration: configuration, credential: "fixture-key") }
        #expect(throws: Error.self) { try FinalASRProvider.request(pcm: Data(repeating: 0, count: 3_201), configuration: configuration, credential: "fixture-key") }
        #expect(throws: Error.self) { try FinalASRProvider.request(pcm: Data(repeating: 0, count: 3_200), configuration: configuration, credential: "fixture-key", boundary: "bad\r\nheader") }
    }

    @Test func invalidModelOrRequestErrorsAreSanitizedAndNotRetried() {
        for status in [400, 404, 422] {
            let failure = ProviderFailure.http(status)
            #expect(!failure.canRetryAutomatically)
            if case .configuration = failure {} else { Issue.record("Invalid request status must be configuration failure") }
            #expect(failure.errorDescription?.contains("http") == false)
        }
        #expect(ProviderFailure.http(503).canRetryAutomatically)
    }
}
