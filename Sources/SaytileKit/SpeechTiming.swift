import Foundation

public struct SpeechTimingEvent: Sendable, Codable {
    public let kind: String
    public let elapsedSeconds: Double
}
