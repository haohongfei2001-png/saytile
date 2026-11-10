/// Decision for the paired FLEURS/M5 cohort in evidence/local-asr. Preserve a
/// working real-time engine on a machine where Apple's language asset is absent.
public enum LocalModelRecommendation {
    public static let description = "此版优先使用 Apple 中文实时识别。系统资源未就绪时，可下载较轻的 Streaming Paraformer。"
    public static func select(appleInstalled: Bool, sherpaInstalled: Bool) -> LocalASRID {
        if !appleInstalled && sherpaInstalled { return .sherpa }
        return .apple
    }
}
