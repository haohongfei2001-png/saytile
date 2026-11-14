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
        #expect(live.presentation == "这是第一句")
        #expect(live.previous == first)
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

    @Test func mixedSpeechResumesAfterTwoRealObservationsOfANewLatinWordBoundary() {
        let head = "当然，我小时候我也没有", visible = "，但是呢，我是小时候比较早接触"
        let restyled = "，但是呢我是小时候比较早接触"
        let updated = "当然我小时候我也没有smart phone"
        func prepared() -> LocalLiveText {
            var live = LocalLiveText(model: .qwen)
            for tail in ["", "，但是呢", visible] { _ = live.accept(head + "Smartphone" + tail + "。", final: false) }
            return live
        }
        var live = prepared()
        #expect(live.accept(head + "smart phone" + visible + "个。", final: false) == nil)
        let next = updated + restyled + "的那个。"
        #expect(live.accept(next, final: false) == 0)
        #expect(live.previous == next)
        #expect(live.presentation == String(next.dropLast()))
        let final = head + "Smartphone" + visible + "过那个电脑。"
        #expect(live.accept(final, final: true) == final.utf16.count)
        #expect(live.presentation == final)

        for replacement in ["smart-phone", "sm artphone", "smart  phone", "smart ph0ne", "smart phones", "smart phоne"] {
            var unconfirmed = prepared()
            _ = unconfirmed.accept(head + replacement + visible + "个。", final: false)
            #expect(unconfirmed.accept(next, final: false) == nil)
        }
        for replacement in ["smart  phone", "smart phone2", "smart-ph0ne"] {
            var invalid = prepared()
            _ = invalid.accept(head + replacement + visible + "个。", final: false)
            #expect(invalid.accept("当然我小时候我也没有" + replacement + restyled + "过那个电脑。", final: false) == nil)
        }
    }

    @Test func firstRollingWordAppearsImmediatelyAndGetsItsFinalPunctuationAtEOS() {
        var live = LocalLiveText(model: .qwen)
        #expect(live.accept("我。", final: false) == 0)
        #expect(live.presentation == "我")
        #expect(live.accept("我觉得", final: false) == 0)
        #expect(live.presentation == "我觉得")
        #expect(live.accept("我觉得。", final: true) == 4)
        #expect(live.presentation == "我觉得。")

        var short = LocalLiveText(model: .qwen)
        #expect(short.accept("对。", final: false) == 0)
        #expect(short.presentation == "对")
        #expect(short.accept("对。", final: true) == 2)
        #expect(short.presentation == "对。")
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

    @Test func establishedWordAndUnfinishedTailCanBothBeCorrectedByGrowingPasses() {
        // Public FLEURS trace f8646a257c0c4273. The two changes occur in
        // different parts of the same raw hypothesis, with new speech at its end.
        let middle = "们的热行为不像地球上的大型洞穴那么稳定。这些大型洞穴通常会保持相当恒定的温度，但它们与地下深雪的情况很相似。亚"
        var live = LocalLiveText(model: .qwen)
        for tail in ["", "亚", "亚历。"] {
            #expect(live.accept("它" + middle.dropLast() + tail, final: false) == 0)
        }
        let visible = live.presentation
        let corrected = "他" + middle + "利桑那州"
        #expect(live.accept(corrected + "。", final: false) == nil)
        #expect(live.presentation == visible)
        #expect(live.accept(corrected + "奇甘镇。", final: false) == 0)
        #expect(live.presentation == corrected + "奇甘镇")
        #expect(live.accept(corrected + "奇甘镇，美国地质调查局。", final: false) == 0)
    }

    @Test func aSecondChangeAtTheRightEdgeCannotBypassProtectedEvidence() {
        let middle = "今天下午会议结束之后才会公布山谷附近遗址的名字"
        func check(_ early: String, _ newEarly: String, _ oldTail: String, _ newTail: String,
                   body: String, priorWord: String? = nil, secondExtension: String = "和地图") {
            var live = LocalLiveText(model: .qwen)
            for n in [4, 2, 0] {
                #expect(live.accept(early + String(body.dropLast(n)) + oldTail, final: false) == 0)
            }
            let visible = live.presentation
            #expect(live.accept(newEarly + body + (priorWord ?? newTail) + "附近", final: false) == nil)
            #expect(live.accept(newEarly + body + newTail + "附近" + secondExtension, final: false) == nil)
            #expect(live.presentation == visible)
        }
        check("不去", "要去", "亚历", "亚利", body: middle)
        check("它们", "他们", "一百", "一千", body: middle)
        check("它们", "他们", "亚历", "亚利", body: middle, priorWord: "亚力")
        check("它们", "他们", "亚历", "亚利", body: middle, secondExtension: "……")
        check("它们", "他们", "亚历", "亚利", body: middle + "亚" + middle)
    }

    @Test func twoLexicallyIdenticalPassesCanCorroborateNewWordsAcrossARephrasedPause() {
        // The signed 466 window had no new useful word for 2.196 s on the
        // 38.8 s public replay while these two lexical hypotheses agreed.
        let head = "老虎是全能运动员，游泳跳远能够达到人类大力士的五倍。"
        let correction = head.replacingOccurrences(of: "大力士", with: "大理石")
        let tail = "这里首选登山目的地——科查莫山谷，被称为南美洲的优美圣地。这里有各式各样的花岗岩大石壁和峭壁。平时你总能在这里听到游客和小"
        let restyled = tail.replacingOccurrences(of: "——", with: "，").replacingOccurrences(of: "。", with: "，")
        func primed() -> LocalLiveText {
            var gate = LocalLiveText(model: .qwen)
            for n in [6, 3, 0] { _ = gate.accept(head + String(tail.dropLast(n)), final: false) }
            return gate
        }

        var live = primed()
        let first = correction + restyled + "摊贩的声音。"
        let corroborated = correction + tail + "摊贩的声音。"
        #expect(live.accept(first, final: false) == nil)
        #expect(live.accept(corroborated, final: false) == 0)
        #expect(live.presentation == String(corroborated.dropLast()))

        var ambiguous = primed()
        #expect(ambiguous.accept(first, final: false) == nil)
        #expect(ambiguous.accept(correction + tail + "摊贩的笑声。", final: false) == nil)
        #expect(ambiguous.presentation == head + tail)
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
