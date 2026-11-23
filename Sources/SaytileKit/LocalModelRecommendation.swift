/// Prefer a verified local installation. Apple can prepare its system language asset
/// when none of the engines is available yet. A running ticket keeps its own choice.
public enum LocalModelRecommendation {
    // M5 native-panel and same-audio archive results are in evidence/mandarin-quality-20261114.
    public static let preferred: LocalASRID = .qwen

    public static func select(preferred: LocalASRID, requested: LocalASRID?,
                              available: Set<LocalASRID>, unavailable: Set<LocalASRID> = []) -> LocalASRID {
        let choices = [requested, preferred, .apple, .sherpa, .qwen].compactMap { $0 }
        return choices.first { available.contains($0) && !unavailable.contains($0) } ?? .apple
    }
}
