import Foundation

/// A one-time, isolated connection setup. It cannot open an existing archive.
public struct ConnectionSetupRequest: Sendable {
    public let directory: URL
    public let output: URL
    public init(directory: URL, output: URL) throws {
        let root = directory.standardizedFileURL
        let destination = output.standardizedFileURL
        try DiagnosticDirectory.validate(directory: directory)
        guard destination.deletingLastPathComponent() == root,
              destination.pathExtension == "json" else {
            throw ProviderFailure.configuration("连接设置需要全新的独立目录，配置文件须为该目录内的 JSON 文件。")
        }
        try StorePath.rejectSymbolicLink(root)
        try StorePath.rejectSymbolicLink(destination)
        if FileManager.default.fileExists(atPath: root.path) {
            guard try FileManager.default.contentsOfDirectory(atPath: root.path).isEmpty else {
                throw ProviderFailure.configuration("连接设置只使用空的独立目录，不打开已有资料。")
            }
        }
        self.directory = root; self.output = destination
    }

    public func exportApplied(_ configuration: RecognitionConfiguration, hasUnappliedChanges: Bool,
                              presence: (ModelConfiguration) -> CloudCredentialPresence = {
                                  CloudCredentialStore.presence(configurationID: $0.id, provider: $0.provider)
                              }) throws {
        guard !hasUnappliedChanges else { throw ProviderFailure.configuration("请先保存并应用修改，再完成连接设置。") }
        guard configuration.cloudEnabled, configuration.inputMode == .highestQuality,
              !configuration.automaticRecovery else {
            throw ProviderFailure.configuration("请启用最高质量识别；独立连接设置保持自动恢复关闭。")
        }
        try configuration.validateForCloud()
        let required: [(RecognitionPurpose, CloudProvider)] = [(.chineseASR, .qwenMessage), (.englishASR, .assemblyAI),
            (.textFusion, .openAIResponses)]
        guard required.allSatisfy({ role, provider in configuration.enabledModels.contains { $0.purpose == role && $0.provider == provider } }) else {
            throw ProviderFailure.configuration("请准备两位音频专家与一个 GPT-6 Astra 融合核心。")
        }
        for item in configuration.enabledModels {
            switch presence(item) {
            case .saved: break
            case .missing: throw ProviderFailure.configuration("请先保存\(item.purpose.label)的 API Key。")
            case .unavailable(let status): throw CloudCredentialError.keychain(status)
            }
        }
        try StorePath.rejectSymbolicLink(output)
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        // Never replace a previously completed setup or export credential values.
        try encoder.encode(configuration).write(to: output, options: [.withoutOverwriting])
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: output.path)
    }
}
