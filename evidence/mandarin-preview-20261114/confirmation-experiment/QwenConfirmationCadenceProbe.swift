import Foundation
@main enum Check {
    static func main() {
        let lead = "他们的热行为不像地球上的大型洞穴那么稳定"
        let correction = "它们的热行为不像地球上的大型洞穴那么稳定"
        let decide = QwenConfirmationCadence.shouldConfirm
        precondition(decide(lead, correction + "气温也变化了。", 16_000))
        precondition(!decide(lead, correction + "气温也变化了。", 15_999))
        precondition(!decide(lead, lead + "气温也变化了。", 32_000))
        precondition(!decide(lead, correction + "……", 32_000))
        precondition(!decide(lead, correction, 32_000))
        precondition(!decide(lead, lead.dropLast() + "定温变化了。", 32_000))
        precondition(!decide(lead, "另一次完全不同的长句甚至没有任何有效对齐但依旧在增长。", 32_000))
        print("7 deterministic scheduling decisions pass")
    }
}
