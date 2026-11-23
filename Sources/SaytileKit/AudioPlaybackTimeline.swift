import Foundation

struct AudioPlaybackItem: Sendable, Equatable {
    let recordingID: UUID
    let url: URL
    let duration: Double
}

struct AudioPlaybackTimeline: Sendable, Equatable {
    let durations: [Double]
    let starts: [Double]
    let duration: Double
    init(durations: [Double]) {
        self.durations = durations.map { $0.isFinite ? max(0, $0) : 0 }
        var cursor = 0.0; var starts: [Double] = []
        for duration in self.durations { starts.append(cursor); cursor += duration }
        self.starts = starts; self.duration = cursor
    }
    func location(at seconds: Double) -> (index: Int, offset: Double)? {
        guard !durations.isEmpty else { return nil }
        let value = seconds.isFinite ? min(duration, max(0, seconds)) : 0
        let index = durations.indices.first { value < starts[$0] + durations[$0] } ?? durations.count - 1
        return (index, min(durations[index], max(0, value - starts[index])))
    }
}
