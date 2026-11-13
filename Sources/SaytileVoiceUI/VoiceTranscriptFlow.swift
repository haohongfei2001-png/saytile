import Foundation

/// Joins recognizer segments for display and copy. Line breaks inside a segment
/// belong to its text and are preserved verbatim.
public enum VoiceTranscriptFlow {
    public static func join(_ segments: [String]) -> String {
        var result = ""
        var preceding: String?
        for segment in segments where !segment.isEmpty {
            if let preceding { result += separator(between: preceding, and: segment) }
            result += segment
            preceding = segment
        }
        return result
    }

    static func separator(between left: String, and right: String) -> String {
        guard let end = left.unicodeScalars.last, let start = right.unicodeScalars.first,
              isLatinWord(start) else { return "" }
        if isLatinWord(end) || CharacterSet.nonBaseCharacters.contains(end)
            || ".,!?;:)]".unicodeScalars.contains(end) { return " " }
        return ""
    }

    private static func isLatinWord(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.value {
        case 0x30...0x39, 0x41...0x5A, 0x61...0x7A: return true
        case 0xC0...0x024F, 0x1E00...0x1EFF: return CharacterSet.letters.contains(scalar)
        default: return false
        }
    }
}
