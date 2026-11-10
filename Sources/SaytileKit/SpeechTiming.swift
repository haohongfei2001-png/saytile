import Foundation

public struct SpeechTimingEvent: Sendable, Codable {
    public let kind: String
    public let elapsedSeconds: Double
    public let text: String?
    init(kind: String, elapsedSeconds: Double, text: String? = nil) {
        self.kind = kind; self.elapsedSeconds = elapsedSeconds; self.text = text
    }
}
