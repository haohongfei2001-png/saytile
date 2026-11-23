import Foundation
import NaturalLanguage

// Mixed runs can make NLTokenizer(.word) omit entire Chinese spans. Tokenize
// contiguous non-ASCII and ASCII runs separately before comparing word types.
let input = try JSONDecoder().decode([String].self, from: FileHandle.standardInput.readDataToEndOfFile())
let tokenizer = NLTokenizer(unit: .word)
let output = input.map { text -> [String] in
    var words: [String] = []
    var start = text.startIndex
    while start < text.endIndex {
        let ascii = text[start].isASCII
        var end = text.index(after: start)
        while end < text.endIndex && text[end].isASCII == ascii {
            end = text.index(after: end)
        }
        let run = String(text[start..<end])
        tokenizer.setLanguage(ascii ? .english : .simplifiedChinese)
        tokenizer.string = run
        words += tokenizer.tokens(for: run.startIndex..<run.endIndex).map { String(run[$0]) }
        start = end
    }
    return words
}
try FileHandle.standardOutput.write(contentsOf: JSONEncoder().encode(output))
