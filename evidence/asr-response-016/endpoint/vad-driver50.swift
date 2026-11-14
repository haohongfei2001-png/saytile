import CryptoKit

struct CorpusRow: Decodable {
    let id: String
    let source: String
    let reference: String
    let audio_sha256: String
}
struct SampleRange: Codable, Equatable {
    let start: Int
    let end: Int
}
struct SegmentReceipt: Codable, Equatable {
    let speechStart: Int64
    let speechEnd: Int64
    let retained: SampleRange
    let pcmFrames: Int
    let pcmSHA256: String
    let matchesInputBytes: Bool
}
struct VADReceipt: Codable {
    let quietFrames: Int
    let segments: [SegmentReceipt]
    let totalRetainedPCMFrames: Int
    let concatenatedRetainedPCMSHA256: String
    let unretainedInputRanges: [SampleRange]
}
struct NewCut: Codable {
    let withinBaselineSegment: Int
    let previousSpeechEnd: Int64
    let nextSpeechStart: Int64
    let observedSpeechGapSeconds: Double
}
struct ComparisonReceipt: Codable {
    let id: String
    let source: String
    let audioSHA256: String
    let inputPCMFrames: Int
    let inputPCMSHA256: String
    let baseline: VADReceipt
    let candidate: VADReceipt
    let contextChanged: Bool
    let newInteriorCuts: [NewCut]
}
func requireAudit(_ condition: @autoclosure () -> Bool, _ message: String) throws {
    if !condition() { throw AudioFailure.message(message) }
}
func digest(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }
func wavPCM(_ data: Data) throws -> Data {
    func label(_ range: Range<Int>) -> String { String(decoding: data[range], as: UTF8.self) }
    func u16(_ offset: Int) -> Int { Int(data[offset]) | Int(data[offset + 1]) << 8 }
    func u32(_ offset: Int) -> Int { u16(offset) | u16(offset + 2) << 16 }
    try requireAudit(data.count >= 44 && label(0..<4) == "RIFF" && label(8..<12) == "WAVE", "Invalid WAV header")
    var position = 12, formatValid = false, pcm: Data?
    while position + 8 <= data.count {
        let name = label(position..<(position + 4)), size = u32(position + 4)
        let start = position + 8, end = start + size
        try requireAudit(end <= data.count, "Truncated WAV chunk")
        if name == "fmt " {
            try requireAudit(size >= 16, "Truncated WAV format")
            formatValid = u16(start) == 1 && u16(start + 2) == 1 && u32(start + 4) == 16_000
                && u16(start + 12) == 2 && u16(start + 14) == 16
        } else if name == "data" {
            try requireAudit(pcm == nil && size.isMultiple(of: 2), "Multiple or partial PCM chunks")
            pcm = Data(data[start..<end])
        }
        position = end + size % 2
    }
    try requireAudit(formatValid && pcm != nil, "Expected mono 16 kHz PCM16")
    return pcm!
}
func segmentation(_ pcm: Data, quietFrames: Int) throws -> VADReceipt {
    let vad = try VoiceSegmenter(endSilenceFrames: quietFrames)
    var activeStart: Int64?, retainedStart = 0, activePCM = Data(), allPCM = Data()
    var segments: [SegmentReceipt] = []
    func receive(_ events: [VoiceSegmenter.Event], inputFramesThrough: Int) throws {
        for event in events {
            switch event {
            case let .begin(preRoll, sample):
                try requireAudit(activeStart == nil, "Overlapping active recordings")
                activeStart = sample
                activePCM = preRoll.reduce(into: Data()) { $0.append($1) }
                retainedStart = inputFramesThrough - activePCM.count / 2
                try requireAudit(retainedStart >= 0, "Pre-roll preceding supplied input")
            case let .audio(data):
                try requireAudit(activeStart != nil, "Audio without an active recording")
                activePCM.append(data)
            case let .end(sample):
                guard let start = activeStart else { throw AudioFailure.message("End without a recording") }
                let retainedEnd = retainedStart + activePCM.count / 2
                try requireAudit(retainedEnd * 2 <= pcm.count, "Retained range outside input")
                let matches = activePCM == pcm.subdata(in: (retainedStart * 2)..<(retainedEnd * 2))
                try requireAudit(matches, "Retained audio differs from its exact source byte range")
                segments.append(.init(speechStart: start, speechEnd: sample,
                    retained: .init(start: retainedStart, end: retainedEnd),
                    pcmFrames: activePCM.count / 2, pcmSHA256: digest(activePCM), matchesInputBytes: matches))
                allPCM.append(activePCM)
                activeStart = nil; activePCM.removeAll(keepingCapacity: true)
            }
        }
    }
    // One exact WebRTC frame per call makes the actual pre-roll byte origin
    // observable without changing the production segmenter or its event types.
    var offset = 0
    while offset < pcm.count {
        let end = min(offset + 640, pcm.count)
        try receive(vad.accept(pcm.subdata(in: offset..<end)), inputFramesThrough: end / 2)
        offset = end
    }
    try receive(vad.finish(), inputFramesThrough: pcm.count / 2)
    try requireAudit(activeStart == nil && !vad.speaking, "Unfinished recording at EOF")
    var gaps: [SampleRange] = [], coveredThrough = 0
    for segment in segments {
        if segment.retained.start > coveredThrough { gaps.append(.init(start: coveredThrough, end: segment.retained.start)) }
        coveredThrough = max(coveredThrough, segment.retained.end)
    }
    if coveredThrough < pcm.count / 2 { gaps.append(.init(start: coveredThrough, end: pcm.count / 2)) }
    return .init(quietFrames: quietFrames, segments: segments, totalRetainedPCMFrames: allPCM.count / 2,
                 concatenatedRetainedPCMSHA256: digest(allPCM), unretainedInputRanges: gaps)
}

// Usage: binary WAV_DIRECTORY OUTPUT_JSONL MANIFEST_JSON [MANIFEST_JSON ...]
let args = CommandLine.arguments
try requireAudit(args.count >= 4, "Usage: vad-compare WAV_DIRECTORY OUTPUT_JSONL MANIFEST_JSON ...")
let wavDirectory = URL(fileURLWithPath: args[1], isDirectory: true)
let output = URL(fileURLWithPath: args[2])
try requireAudit(!FileManager.default.fileExists(atPath: output.path), "Refusing to replace existing evidence")
let decoder = JSONDecoder(), encoder = JSONEncoder()
encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
var rows: [CorpusRow] = []
for path in args.dropFirst(3) { rows += try decoder.decode([CorpusRow].self, from: Data(contentsOf: URL(fileURLWithPath: path))) }
try requireAudit(Set(rows.map(\.id)).count == rows.count, "Duplicate corpus ID")
try Data().write(to: output, options: .withoutOverwriting)
let writer = try FileHandle(forWritingTo: output)
defer { try? writer.close() }
var changed: [String] = [], split: [String] = []
for row in rows {
    let wav = try Data(contentsOf: wavDirectory.appendingPathComponent(row.id + ".wav"))
    try requireAudit(digest(wav) == row.audio_sha256, "Audio digest mismatch: " + row.id)
    let pcm = try wavPCM(wav)
    let baseline = try segmentation(pcm, quietFrames: 75), candidate = try segmentation(pcm, quietFrames: 50)
    let oldContext = baseline.segments.map { [$0.speechStart, $0.speechEnd] }
    let newContext = candidate.segments.map { [$0.speechStart, $0.speechEnd] }
    var cuts: [NewCut] = []
    for i in candidate.segments.indices.dropFirst() {
        let current = candidate.segments[i], prior = candidate.segments[i - 1]
        if let oldIndex = baseline.segments.firstIndex(where: {
            $0.speechStart < current.speechStart && current.speechStart < $0.speechEnd
        }) {
            cuts.append(.init(withinBaselineSegment: oldIndex, previousSpeechEnd: prior.speechEnd,
                nextSpeechStart: current.speechStart,
                observedSpeechGapSeconds: Double(current.speechStart - prior.speechEnd) / 16_000))
        }
    }
    let receipt = ComparisonReceipt(id: row.id, source: row.source, audioSHA256: digest(wav),
        inputPCMFrames: pcm.count / 2, inputPCMSHA256: digest(pcm), baseline: baseline, candidate: candidate,
        contextChanged: oldContext != newContext, newInteriorCuts: cuts)
    if receipt.contextChanged { changed.append(row.id) }
    if !cuts.isEmpty { split.append(row.id) }
    try writer.write(contentsOf: encoder.encode(receipt) + Data([10]))
}
try writer.synchronize()
let summary: [String: Any] = ["rows": rows.count, "contextChanged": changed, "newInteriorSplit": split,
 "scope": "Real VoiceSegmenter and WebRTC only; no ASR, no microphone, no accuracy claims; unretained ranges include standby silence."]
print(String(decoding: try JSONSerialization.data(withJSONObject: summary, options: [.sortedKeys]), as: UTF8.self))
