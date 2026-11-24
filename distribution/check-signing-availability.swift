import Foundation
import LocalAuthentication
import Security

// Read-only attributes query. Never request kSecReturnData, never permit a
// password prompt, and never expose unrelated Keychain accounts in the receipt.
let context = LAContext()
context.interactionNotAllowed = true
var accounts = Set<String>(), notaryServices = Set<String>()
var statuses = [Int32]()
for dataProtection in [false, true] {
    var query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
        kSecMatchLimit as String: kSecMatchLimitAll, kSecReturnAttributes as String: true,
        kSecReturnData as String: false, kSecUseAuthenticationContext as String: context]
    if dataProtection { query[kSecUseDataProtectionKeychain as String] = true }
    var result: CFTypeRef?
    let status = SecItemCopyMatching(query as CFDictionary, &result)
    statuses.append(status)
    for row in result as? [[String: Any]] ?? [] {
        let service = row[kSecAttrService as String] as? String ?? ""
        let label = row[kSecAttrLabel as String] as? String ?? ""
        if service == "https://sparkle-project.org",
           let account = row[kSecAttrAccount as String] as? String, account == "app.saytile.updates.v1" {
            accounts.insert(account)
        }
        if service.lowercased().contains("notary") || label.lowercased().contains("notary") {
            notaryServices.insert(service.isEmpty ? label : service)
        }
    }
}
let environmentNames = ProcessInfo.processInfo.environment.keys.filter { name in
    ["NOTARY", "APPLE_ID", "ASC_KEY", "SPARKLE", "APP_STORE_CONNECT"].contains { name.uppercased().contains($0) }
}.sorted()
let home = FileManager.default.homeDirectoryForCurrentUser
let defaultAPIKeyFileCount = [".appstoreconnect/private_keys", "private_keys"].reduce(0) { count, relative in
    let names = (try? FileManager.default.contentsOfDirectory(atPath: home.appendingPathComponent(relative).path)) ?? []
    return count + names.filter { $0.hasPrefix("AuthKey_") && $0.hasSuffix(".p8") }.count
}
let receipt: [String: Any] = ["security_query_statuses": statuses,
    "saytile_sparkle_accounts": accounts.sorted(), "notary_metadata_services": notaryServices.sorted(),
    "configured_environment_names": environmentNames, "default_api_key_file_count": defaultAPIKeyFileCount,
    "secret_data_requested": false, "key_files_read": false, "keychain_modified": false,
    "interaction_allowed": false, "scope": "user search list and data-protection attributes; known default API-key filename counts only"]
let data = try JSONSerialization.data(withJSONObject: receipt, options: [.prettyPrinted, .sortedKeys])
print(String(decoding: data, as: UTF8.self))
