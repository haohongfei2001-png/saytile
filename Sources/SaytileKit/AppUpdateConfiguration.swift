import Foundation

/// Update identity comes from the signed bundle, never editable preferences.
public struct AppUpdateConfiguration: Equatable, Sendable {
    public let feedURL: URL
    public let publicKey: String
    public let channel: String

    public enum Failure: Error, LocalizedError {
        case missing, identity, feed, signature
        public var errorDescription: String? {
            switch self {
            case .missing: "此安装包尚未配置应用内更新。"
            case .identity: "更新渠道与当前应用不匹配，已停止检查。"
            case .feed: "更新地址无效，已停止检查。"
            case .signature: "更新签名配置无效，已停止检查。"
            }
        }
    }

    public init(info: [String: Any], bundleID: String?, isolatedFixture: Bool = false) throws {
        guard let address = info["SUFeedURL"] as? String,
              let key = info["SUPublicEDKey"] as? String else { throw Failure.missing }
        guard let bundleID, info["SaytileUpdateBundleIdentifier"] as? String == bundleID,
              let channel = info["SaytileUpdateChannel"] as? String else { throw Failure.identity }
        let fixture = isolatedFixture && bundleID.hasPrefix("app.saytile.update-fixture.") && channel == "fixture"
        guard fixture || (bundleID == "app.saytile.mac" && channel == "standard") ||
              (bundleID == SaytileStorageProfile.mandarinCandidateID && channel == "mandarin") else {
            throw Failure.identity
        }
        guard let parts = URLComponents(string: address), let url = parts.url,
              let host = parts.host, !host.isEmpty, parts.user == nil, parts.password == nil,
              parts.fragment == nil, parts.query == nil,
              parts.scheme == "https" || (fixture && parts.scheme == "http" && host == "127.0.0.1") else {
            throw Failure.feed
        }
        guard Data(base64Encoded: key)?.count == 32,
              info["SURequireSignedFeed"] as? Bool == true,
              info["SUVerifyUpdateBeforeExtraction"] as? Bool == true,
              info["SUAllowsAutomaticUpdates"] as? Bool == false,
              info["SUSendProfileInfo"] as? Bool == false else { throw Failure.signature }
        self.feedURL = url; self.publicKey = key; self.channel = channel
    }
}
