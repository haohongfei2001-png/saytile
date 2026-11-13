/// Prefer a verified local installation. Apple can prepare its system language asset
/// when none of the engines is available yet. A running ticket keeps its own choice.
public enum LocalModelRecommendation {
    public static let preferred: LocalASRID = .apple

    public static func select(preferred: LocalASRID, requested: LocalASRID?,
                              available: Set<LocalASRID>, unavailable: Set<LocalASRID> = []) -> LocalASRID {
        let choices = [requested, preferred, .apple, .sherpa, .qwen].compactMap { $0 }
        return choices.first { available.contains($0) && !unavailable.contains($0) } ?? .apple
    }
}
