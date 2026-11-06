import Foundation
import Security

/// Credentials are independent from model settings and never serialized into UserDefaults.
/// Each configuration has its own Keychain account, including two models at one vendor.
public enum CloudCredentialStore {
    private static let service = "com.saytile.byok.v1"
    public static func save(_ secret: String, configurationID: UUID, provider: CloudProvider) throws {
        let cleaned = secret.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { throw CloudCredentialError.empty }
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                  kSecAttrService as String: service,
                                  kSecAttrAccount as String: provider.rawValue + "." + configurationID.uuidString]
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
    public static func read(configurationID: UUID, provider: CloudProvider) throws -> String? {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                  kSecAttrService as String: service,
                                  kSecAttrAccount as String: provider.rawValue + "." + configurationID.uuidString,
                                  kSecReturnData as String: true,
                                  kSecMatchLimit as String: kSecMatchLimitOne,
                                  kSecUseAuthenticationUI as String: kSecUseAuthenticationUIFail]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data,
              let value = String(data: data, encoding: .utf8) else { throw CloudCredentialError.keychain(status) }
        return value
    }
    public static func contains(configurationID: UUID, provider: CloudProvider) -> Bool {
        (try? read(configurationID: configurationID, provider: provider)) != nil
    }
    public static func delete(configurationID: UUID, provider: CloudProvider) throws {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                  kSecAttrService as String: service,
                                  kSecAttrAccount as String: provider.rawValue + "." + configurationID.uuidString]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw CloudCredentialError.keychain(status) }
    }
}

public enum CloudCredentialError: LocalizedError, Sendable {
    case empty, keychain(OSStatus)
    public var errorDescription: String? {
        switch self {
        case .empty: return "请填写 API Key。"
        case .keychain(let status): return "无法访问钥匙串（\(status)）；密钥没有写入普通设置或日志。"
        }
    }
}
