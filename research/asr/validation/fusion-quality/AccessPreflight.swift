import Foundation
import Security
import LocalAuthentication
let context = LAContext(); context.interactionNotAllowed = true
let query: [String: Any] = [kSecClass as String:kSecClassGenericPassword,kSecAttrService as String:"com.saytile.byok.v1",kSecMatchLimit as String:kSecMatchLimitAll,kSecReturnAttributes as String:true,kSecUseAuthenticationContext as String:context]
var result: CFTypeRef?
let status = SecItemCopyMatching(query as CFDictionary, &result)
let items = result as? [[String: Any]] ?? []
let data = UserDefaults(suiteName:"app.saytile.mac")?.data(forKey:"multiASRConfigurationV1")
let config = data.flatMap { try? JSONSerialization.jsonObject(with:$0) as? [String:Any] }
let models = (config?["models"] as? [[String:Any]] ?? []).filter { $0["enabled"] as? Bool == true }
let summary: [String: Any] = ["keychain_service":"com.saytile.byok.v1","metadata_query_status":status,"matching_item_count":items.count,"secret_values_requested":false,"permission_prompt_allowed":false,"configuration_present":config != nil,"cloud_enabled":config?["cloudEnabled"] as? Bool ?? false,"enabled_services":models.map { ["provider":$0["provider"] as? String ?? "unknown","consent":$0["cloudConsent"] as? Bool ?? false] },"audio_uploaded":false,"paid_requests":0]
let output=try JSONSerialization.data(withJSONObject:summary,options:[.prettyPrinted,.sortedKeys]); print(String(decoding:output,as:UTF8.self))
