import Foundation

/// A saved recording may return only to service scopes explicitly authorized for
/// that recording. No credential, transcript or topic context is persisted here.
struct RecordingCloudAuthorizationScope: Codable, Hashable, Sendable {
    let configurationID: UUID
    let provider: CloudProvider
    let model: String
    let region: String
    let workspaceID: String
    let purpose: RecognitionPurpose
    let credentialGeneration: UUID?

    init(_ configuration: ModelConfiguration) {
        configurationID = configuration.id
        provider = configuration.provider
        model = configuration.model
        region = configuration.region
        workspaceID = configuration.workspaceID
        purpose = configuration.purpose
        credentialGeneration = configuration.credentialGeneration
    }

    /// Canonical structured storage avoids ambiguous delimiter-based identities.
    var storageKey: String {
        get throws {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            return String(decoding: try encoder.encode(self), as: UTF8.self)
        }
    }

    static func required(for configuration: RecognitionConfiguration) throws -> Set<Self> {
        try configuration.validateForCloud()
        let active = configuration.activeModels
        guard configuration.cloudEnabled,
              active.contains(where: { $0.purpose.isStreaming }),
              Set(active.map(\.id)).count == active.count else {
            throw ProviderFailure.configuration("本段原音尚未获得有效云端处理授权。")
        }
        for item in active {
            try item.validate()
            guard item.cloudConsent else { throw ProviderFailure.authorization }
        }
        // Include text fusion: changing its destination must not silently send
        // historical transcripts to another account, region or model either.
        return Set(active.map(Self.init))
    }
}
