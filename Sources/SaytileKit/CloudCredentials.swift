import Foundation
import Security
import LocalAuthentication

public enum CloudCredentialPresence: Equatable, Sendable {
    case saved, missing, unavailable(OSStatus)
    public var isSaved: Bool { self == .saved }
    public var label: String {
        switch self {
        case .saved: "密钥已保存"
        case .missing: "待添加密钥"
        case .unavailable: "钥匙串暂不可访问"
        }
    }
}

/// Credentials never enter preferences or diagnostics. Presence checks request
/// only item metadata; secret bytes are read solely when a provider needs them.
public enum CloudCredentialStore {
    private static let store = KeychainCredentialStore(service: SaytileStorageProfile.current.byokService)
    public static func save(_ secret: String, configurationID: UUID, provider: CloudProvider) throws {
        try store.save(secret, configurationID: configurationID, provider: provider)
    }
    public static func read(configurationID: UUID, provider: CloudProvider) throws -> String? {
        try store.read(configurationID: configurationID, provider: provider)
    }
    public static func presence(configurationID: UUID, provider: CloudProvider) -> CloudCredentialPresence {
        store.presence(configurationID: configurationID, provider: provider)
    }
    public static func contains(configurationID: UUID, provider: CloudProvider) -> Bool {
        presence(configurationID: configurationID, provider: provider).isSaved
    }
    public static func delete(configurationID: UUID, provider: CloudProvider) throws {
        try store.delete(configurationID: configurationID, provider: provider)
    }
}

/// Internal instance allows real Security.framework tests to use a fresh service,
/// never the production credential namespace or an existing user's credential.
struct KeychainCredentialStore: Sendable {
    let service: String
    private func query(configurationID: UUID, provider: CloudProvider) -> [String: Any] {
        let context = LAContext(); context.interactionNotAllowed = true
        return [kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service,
                kSecAttrAccount as String: provider.rawValue + "." + configurationID.uuidString,
                kSecUseAuthenticationContext as String: context]
    }
    func save(_ secret: String, configurationID: UUID, provider: CloudProvider) throws {
        let cleaned = secret.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { throw CloudCredentialError.empty }
        let query = query(configurationID: configurationID, provider: provider)
        let data = Data(cleaned.utf8)
        let update = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if update == errSecItemNotFound {
            var item = query
            item[kSecValueData as String] = data
            item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            let status = SecItemAdd(item as CFDictionary, nil)
            guard status == errSecSuccess else { throw CloudCredentialError.keychain(status) }
        } else if update != errSecSuccess { throw CloudCredentialError.keychain(update) }
    }
    func read(configurationID: UUID, provider: CloudProvider) throws -> String? {
        var query = query(configurationID: configurationID, provider: provider)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else { throw CloudCredentialError.keychain(status) }
        guard let data = result as? Data, let value = String(data: data, encoding: .utf8), !value.isEmpty else {
            throw CloudCredentialError.invalidEncoding
        }
        return value
    }
    func presence(configurationID: UUID, provider: CloudProvider) -> CloudCredentialPresence {
        var query = query(configurationID: configurationID, provider: provider)
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        query[kSecReturnAttributes as String] = true
        var metadata: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &metadata)
        switch status {
        case errSecSuccess: return .saved
        case errSecItemNotFound: return .missing
        default: return .unavailable(status)
        }
    }
    func delete(configurationID: UUID, provider: CloudProvider) throws {
        let status = SecItemDelete(query(configurationID: configurationID, provider: provider) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw CloudCredentialError.keychain(status) }
    }
}

public enum CloudCredentialError: LocalizedError, Sendable {
    case empty, invalidEncoding, keychain(OSStatus)
    public var errorDescription: String? {
        switch self {
        case .empty: return "请填写 API Key。"
        case .invalidEncoding: return "已保存的密钥无法读取，请重新保存。"
        case .keychain(let status): return "无法访问钥匙串（\(status)）；密钥没有写入普通设置或日志。"
        }
    }
}
