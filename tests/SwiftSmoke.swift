import Foundation
@main struct Smoke {
    static func main() throws {
        precondition(tryValue("你😀好", 3) == "你😀")
        precondition(tryValue("你😀好", 4) == "你😀好")
        precondition(tryValue("你😀好", 0) == "")
        precondition(tryValue("你😀好", 2) == nil)
        precondition(tryValue("你😀好", -1) == nil)
        precondition(tryValue("你😀好", 5) == nil)
        print("PASS: 6 UTF-16 boundary assertions (Foundation only; no native audio/input)")
    }
    static func tryValue(_ value: String, _ end: Int) -> String? {
        try? checkedUTF16Prefix(value, through: end)
    }
}
