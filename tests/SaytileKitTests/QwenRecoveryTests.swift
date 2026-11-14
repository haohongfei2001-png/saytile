import Foundation
import Testing
@testable import SaytileKit

@Suite("Local model preview and download recovery")
struct QwenRecoveryTests {
    // Verbatim partials from the pinned Qwen worker on public FLEURS sample 9eb2d543a0a36152.
    private let original = [
        "嗯。", "致力首選燈。", "致力首选登山目的地。科", "致力首选登山目的地——喀嚓莫山。",
        "致力首选登山目的地——喀察莫山谷，被称为。", "致力首选登山目的地——科查莫山谷，被称为南美洲的优。"
    ]

    @Test func longPreviewResumesAfterTwoAlignedCorrectionsFromTheDecoder() {
        var preview = LocalLiveText(model: .qwen)
        for words in original { #expect(preview.accept(words, final: false) == 0) }
        let corrected = "智利首选登山目的地科查莫山谷，被称为南美洲的优美圣地。"
        #expect(preview.accept(corrected, final: false) == nil)
        #expect(preview.previous == original.last)
        for words in [corrected + "这里有各", corrected + "这里有各式各样的花岗岩。",
                      corrected + "这里有各式各样的花岗岩大石壁和峭。"] {
            #expect(preview.accept(words, final: false) == 0)
            #expect(preview.previous == words)
        }
        let final = corrected + "这里有各式各样的花岗岩大石壁和峭壁。"
        #expect(preview.accept(final, final: true) == final.utf16.count)
    }

    @Test func longPreviewRejectsWidelyChangedPassesDespiteSharedWords() {
        var preview = LocalLiveText(model: .qwen)
        for words in original { #expect(preview.accept(words, final: false) == 0) }
        let unrelated = "智利首选登山目的地实际上完全换到了另一座机场附近的博物馆准备售票。"
        #expect(preview.accept(unrelated, final: false) == nil)
        #expect(preview.accept(unrelated + "下一次会继续。", final: false) == nil)
        #expect(preview.previous == original.last)
    }

    @Test func mixedSpeechCanGrowWhileEarlierWordsChangeTypography() {
        // Consecutive raw hypotheses from the signed native app (ASCEND a0b0e736637c643c).
        let words = ["对，但是。", "对，但是除了。", "对，但是除了self driving。",
            "对，但是除了self-driving car，也。", "对，但是除了self-driving car，也有一些。",
            "对，但是除了self driving car，也有一些比较就。", "对，但是除了self driving car也有一些比较，就是。",
            "对，但是除了Self Driving Car也有一些比较，就是low。", "对，但是除了self driving car也有一些比较，就是lower lower。",
            "对，但是除了self-driving car也有一些比较，就是lower low standard。",
            "对，但是除了Self Driving Car也有一些比较就是Lower Low Standard的。",
            "对，但是除了Self Driving Car也有一些比较就是Lower Low Standard的那些。"]
        var preview = LocalLiveText(model: .qwen)
        for text in words {
            #expect(preview.accept(text, final: false) == 0)
            #expect(preview.previous == text)
        }
        let prior = preview.previous
        for change in ["没有，除了", "对，但是除了SelfDrivingCar不", "对，但是除了Self -5 Driving Car"] {
            #expect(preview.accept(change + "也有一些比较就是Lower Low Standard的那些。", final: false) == nil)
        }
        #expect(preview.previous == prior)
    }

    @Test func rawQwenPeriodStopsBlinkingUntilSupportedByMoreSpeech() {
        var live = LocalLiveText(model: .qwen)
        let first = "这是第一句。"
        #expect(live.accept(first, final: false) == 0)
        #expect(live.presentation == first)
        let raw = "这是第一句。第二句还没说完。"
        #expect(live.accept(raw, final: false) == 0)
        #expect(live.presentation == "这是第一句。第二句还没说完")
        #expect(live.previous == raw)
        let extended = "这是第一句。第二句还没说完。再说一段……"
        #expect(live.accept(extended, final: false) == 0)
        #expect(live.presentation == extended)
        #expect(live.accept(raw, final: true) == raw.utf16.count)
        #expect(live.presentation == raw)

        var other = LocalLiveText(model: .sherpa)
        _ = other.accept(first, final: false)
        _ = other.accept(raw, final: false)
        #expect(other.presentation == raw)
    }

    @Test func wordsAfterAnAppositionCanAppearWhileTheDecoderRestylesOldPauses() {
        // The 38.8 s native trace stalled at 26.52 s despite three genuine
        // growing tails. The rolling decoder restyled these two old boundaries.
        let start = "这里首选登山目的地，科查莫山谷，被称为南美洲的优美圣地，这里有各式各样的"
        let corrected = "这里首选登山目的地——科查莫山谷，被称为南美洲的优美圣地。这里有各式各样的"
        var live = LocalLiveText(model: .qwen)
        for words in [start + "花岗岩", start + "花岗岩大石壁", start + "花岗岩大石壁和峭壁。"] {
            #expect(live.accept(words, final: false) == 0)
        }
        let speech = corrected + "花岗岩大石壁和峭壁，平时你"
        #expect(live.accept(speech + "。", final: false) == 0)
        #expect(live.presentation == speech)
        for invalid in [corrected.replacingOccurrences(of: "——", with: "−"),
                        corrected.replacingOccurrences(of: "——", with: ""),
                        corrected.replacingOccurrences(of: "被称为", with: "不被称为")] {
            #expect(live.accept(invalid + "花岗岩大石壁和峭壁，平时你总能听到。", final: false) == nil)
        }
        #expect(live.presentation == speech)
    }

    @Test func numericalPunctuationCannotReleaseAConflictingHypothesis() {
        let head = "这次测量读数是3。5，下一次测量记录在附表中"
        // Arabic numeric punctuation is significant even when the surrounding
        // sentence and a long suffix of the observation are otherwise unchanged.
        var digits = LocalLiveText(model: .qwen)
        for tail in ["准备", "准备开始", "准备开始统计"] {
            #expect(digits.accept(head + tail, final: false) == 0)
        }
        #expect(digits.accept(head.replacingOccurrences(of: "3。5", with: "3，5") + "准备开始统计了", final: false) == nil)
    }

    @Test func twoPassCorrectionSurvivesAnIndependentEarlierOscillation() {
        let lead = "老虎是全能运动员，游泳跳远能够达到人类大理石的五倍。"
        let suffix = "首选登山目的地科查莫山谷，被称为南美洲的优美圣地"
        var live = LocalLiveText(model: .qwen)
        for tail in ["", "附近", "附近山峰"] {
            #expect(live.accept(lead + "视力" + suffix + tail, final: false) == 0)
        }
        let before = live.presentation
        let wavering = lead.replacingOccurrences(of: "大理石", with: "大力士")
        let earlierPass = wavering + "这里" + suffix + "附近山峰呈现出不同颜色"
        #expect(live.accept(earlierPass, final: false) == nil)
        #expect(live.presentation == before)
        let current = lead + "这里" + suffix + "附近山峰呈现出不同颜色和纹理"
        #expect(live.accept(current, final: false) == 0)
        #expect(live.presentation == current)
    }

    @Test func localConfirmationRefusesUnsupportedWordsAmbiguousAnchorsOrChangedMeaning() {
        let leading = "老虎是全能运动员，游泳跳远能够达到人类大理石的五倍。"
        let alternating = leading.replacingOccurrences(of: "大理石", with: "大力士")
        let anchor = "山谷附近树林密布景色宁静秀美如画"
        func expectBlocked(old: String, prior: String, current: String, suffix: String) {
            var live = LocalLiveText(model: .qwen)
            for n in [4, 2, 0] {
                #expect(live.accept(leading + old + String(suffix.dropLast(n)), final: false) == 0)
            }
            let visible = live.presentation
            #expect(live.accept(alternating + prior + suffix + "平时有人来访", final: false) == nil)
            #expect(live.accept(leading + current + suffix + "平时有人来访和登山", final: false) == nil)
            #expect(live.presentation == visible)
        }
        expectBlocked(old: "视力", prior: "智利", current: "这里", suffix: anchor)
        expectBlocked(old: "不去", prior: "要去", current: "要去", suffix: anchor)
        expectBlocked(old: "十五", prior: "十六", current: "十六", suffix: anchor)
        expectBlocked(old: "视力", prior: "这里", current: "这里", suffix: anchor + anchor)
    }

    @Test func localConfirmationNeedsARealSharedNewWordAndKeepsNegationBoundaries() {
        let lead = "这里的工程师准备在山谷附近建造一座大桥，"
        let unstable = lead.replacingOccurrences(of: "工程师", with: "攻城师")
        let suffix = "沿着河岸可以欣赏远处群山之间的风景"
        let cases = [("", "……", "……？！"), ("", " ", "  "), ("", " 今天", " 明天"),
                     ("不，可以停", "不可以停这项工作", "不可以停这项工作到明天")]
        for (oldEnding, priorEnding, currentEnding) in cases {
            var live = LocalLiveText(model: .qwen)
            for n in [4, 2, 0] {
                #expect(live.accept(lead + "视力" + String(suffix.dropLast(n)) + oldEnding, final: false) == 0)
            }
            let before = live.presentation
            #expect(live.accept(unstable + "这里" + suffix + priorEnding, final: false) == nil)
            #expect(live.accept(lead + "这里" + suffix + currentEnding, final: false) == nil)
            #expect(live.presentation == before)
        }
    }

    @Test func aCommaAfterANegationIsNotAnOptionalStyleChange() {
        var live = LocalLiveText(model: .qwen)
        let statement = "不，可以停这项工作，请大家按照之前的安排"
        for tail in ["", "等待", "等待消息"] { #expect(live.accept(statement + tail, final: false) == 0) }
        let change = "不可以停这项工作，请大家按照之前的安排等待消息。"
        #expect(live.accept(change, final: false) == nil)
        #expect(live.presentation == statement + "等待消息")
    }

    private func fixture(_ variant: String) throws -> LocalModelManifest {
        let revision = try LocalModelManifest.load(.qwen).revision
        let file = LocalModelManifest.File(path: "weights", bytes: 3,
            sha256: "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
        return LocalModelManifest(id: .qwen, repo: "fixture/" + variant, revision: revision, license: "fixture", files: [file])
    }

    @Test func coldReopenVerifiesEqualSizeDamageAndReportsAllRemovableBytes() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let library = LocalModelLibrary(root: root)
        let manifest = try fixture("valid")
        let dir = await library.directory(manifest), stage = dir.appendingPathExtension("partial")
        for folder in [dir, stage] { try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true) }
        let weights = dir.appending(path: "weights")
        try Data("abd".utf8).write(to: weights)
        try Data("a".utf8).write(to: stage.appending(path: "weights"))
        let damaged = await library.status(manifest)
        #expect(!damaged.installed && damaged.error != nil && damaged.bytes == 1 && damaged.diskBytes == 4)
        await #expect(throws: (any Error).self) { try await library.validated(manifest) }
        try Data("abc".utf8).write(to: weights, options: .atomic)
        let repaired = await library.status(manifest)
        #expect(repaired.installed && repaired.error == nil && repaired.bytes == 3 && repaired.diskBytes == 4)
        let reopened = await LocalModelLibrary(root: root).status(manifest)
        #expect(reopened.installed && reopened.error == nil)
        try await library.delete(.qwen)
        let removed = await library.status(manifest)
        #expect(!removed.installed && removed.diskBytes == 0 && removed.error == nil)
    }

    @Test func invalidCompleteResponsePreservesCheckpointForNextDownload() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [WholeWeightResponse.self]
        let library = LocalModelLibrary(root: root, session: URLSession(configuration: config))
        let bad = try fixture("invalid"), good = try fixture("valid")
        let stage = await library.directory(bad).appendingPathExtension("partial")
        try FileManager.default.createDirectory(at: stage, withIntermediateDirectories: true)
        let checkpoint = stage.appending(path: "weights")
        try Data("a".utf8).write(to: checkpoint)
        await #expect(throws: (any Error).self) { try await library.install(bad) }
        #expect(try Data(contentsOf: checkpoint) == Data("a".utf8))
        let interrupted = await library.status(bad)
        #expect(!interrupted.installed && interrupted.bytes == 1 && interrupted.diskBytes == 1)
        try await library.install(good)
        let result = await library.status(good)
        #expect(result.installed && result.bytes == 3 && result.diskBytes == 3)
        let dir = try await library.validated(good)
        #expect(try Data(contentsOf: dir.appending(path: "weights")) == Data("abc".utf8))
    }
}

private final class WholeWeightResponse: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func stopLoading() {}
    override func startLoading() {
        guard let url = request.url else { return }
        let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: "HTTP/1.1",
                                       headerFields: ["Content-Length": "3"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data((url.pathComponents.contains("invalid") ? "abd" : "abc").utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
}
