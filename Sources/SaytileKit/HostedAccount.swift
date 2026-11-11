import Foundation
import Combine

/// Persists only the selected source, upload consent and an opaque session in its own Keychain service.
@MainActor public final class HostedAccount: ObservableObject {
    @Published public private(set) var selected: Bool
    @Published public private(set) var consent: Bool
    @Published public private(set) var signedIn = false
    @Published public private(set) var busy = false
    @Published public private(set) var status = "未登录 · 本机识别可用"
    @Published public private(set) var remainingMS: Int64?
    @Published public private(set) var billingAvailable = false
    @Published public private(set) var plan: String?
    @Published public private(set) var validUntil: String?
    private let defaults: UserDefaults
    private let origin: URL?
    private let keychain: KeychainCredentialStore
    typealias Request = @Sendable (URL,String?,[String:String]?,String?) async throws -> Data
    private let request: Request
    private let slot = UUID(uuidString:"5A1711E0-0000-4000-8000-000000000001")!
    private struct Tokens: Codable { let access_token: String; let refresh_token: String; let expires_at: Double }
    private struct Config: Decodable { let url: URL; let publishableKey: String }
    private struct Saved: Codable { let project: URL; let tokens: Tokens }
    private struct Account: Decodable { let billing: Bool?; let active: Bool; let available: Bool; let remaining_ms: Int64; let plan: String?; let valid_until: String? }
    private var saved: Saved?
    private var config: Config?
    private var current: HostedAccess?
    private var timer: Task<Void,Never>?
    private var generation = UUID()
    private var loaded = false
    private var onRoute: ((HostedRoute,Bool)->Void)?
    public convenience init(preferences: UserDefaults, production: Bool) {
        self.init(preferences:preferences, production:production,
            origin:production ? URL(string:"https://saytile-cloud.vercel.app") : nil,
            keychain:KeychainCredentialStore(service:"com.saytile.hosted.auth.v1"),
            request: { try await HostedNetwork.request($0,bearer:$1,payload:$2,key:$3) })
    }
    init(preferences: UserDefaults, production: Bool, origin: URL?, keychain: KeychainCredentialStore,
         request: @escaping Request) {
        self.keychain=keychain;self.request=request
        defaults = preferences
        selected = preferences.object(forKey:"hosted.selected.v1") as? Bool ?? false
        consent = preferences.bool(forKey:"hosted.zh-consent.v1")
        self.origin=origin
    }
    public func bind(_ fn: @escaping (HostedRoute,Bool)->Void) {
        onRoute=fn; apply()
        timer = Task { [weak self] in
            while !Task.isCancelled { if self?.selected == true { await self?.refresh() }
                do { try await Task.sleep(for:.seconds(60)) } catch { return } }
        }
    }
    deinit { timer?.cancel() }
    private func apply(_ revoke: Bool = false) {
        if !selected { onRoute?(.byok,revoke) }
        else if consent,let current,current.expiry > Date() { onRoute?(.connected(current),revoke) }
        else { onRoute?(.local,revoke) }
    }
    public func select(_ hosted: Bool) {
        guard hosted != selected else { return }
        selected=hosted;defaults.set(hosted,forKey:"hosted.selected.v1");current=nil;apply()
        if hosted { Task { await refresh() } }
    }
    public func authorize(_ enabled: Bool) {
        consent=enabled;defaults.set(enabled,forKey:"hosted.zh-consent.v1");apply(!enabled)
    }
    private func project() async throws -> Config {
        if let config { return config }
        guard let origin else { throw ProviderFailure.connection }
        let data = try await request(origin.appending(path:"v1/config"),nil,nil,nil)
        let c = try JSONDecoder().decode(Config.self,from:data)
        guard c.url.absoluteString.range(of:"^https://[a-z0-9-]+[.]supabase[.]co$",options:.regularExpression) != nil, !c.publishableKey.isEmpty else { throw ProviderFailure.connection }
        config=c;return c
    }
    private func persist(_ record: Saved) throws {
        guard origin != nil else { throw ProviderFailure.permission }
        try keychain.save(String(decoding:try JSONEncoder().encode(record),as:UTF8.self),configurationID:slot,provider:.openAIResponses)
        defaults.removeObject(forKey:"hosted.restore-blocked.v1");saved=record;signedIn=true;loaded=true
    }
    private func perform(_ fn: (UUID) async throws -> Void) async {
        guard selected,!busy,origin != nil else {return};busy=true;let g=generation
        defer {if g==generation { busy=false }}
        do { try await fn(g) } catch {
            guard g==generation else { return };current=nil;apply()
            if case ProviderFailure.authorization = error { status="登录已失效或验证码无效 · 本机识别可用" }
            else { status="云服务暂不可用 · 原音仍保存在本机" }
        }
    }
    public func sendCode(email:String) async {
        await perform { g in let c=try await project(); guard g==generation else {return}
            _ = try await request(c.url.appending(path:"auth/v1/otp"),nil,["email":email],c.publishableKey)
            if g==generation {status="请查看邮箱中的一次性验证码"} }
    }
    public func verify(email:String,code:String) async {
        await perform { g in let c=try await project(); guard g==generation else {return}
            let data=try await request(c.url.appending(path:"auth/v1/verify"),nil,["email":email,"token":code,"type":"email"],c.publishableKey)
            guard g==generation else {return};try persist(.init(project:c.url,tokens:try JSONDecoder().decode(Tokens.self,from:data)))
            try await account(g) }
    }
    public func refresh() async {
        await perform { g in
            if !loaded { let raw=defaults.bool(forKey:"hosted.restore-blocked.v1") ? nil : try keychain.read(configurationID:slot,provider:.openAIResponses)
                if let raw { saved=try JSONDecoder().decode(Saved.self,from:Data(raw.utf8)) }
                loaded=true;signedIn=saved != nil }
            guard saved != nil else { return };try await account(g) }
    }
    private func account(_ g: UUID) async throws {
        let c=try await project()
        guard g==generation,let record=saved,record.project==c.url,let origin else {throw ProviderFailure.authorization}
        var tokens=record.tokens
        if tokens.expires_at < Date().timeIntervalSince1970+180 {
            let url=c.url.appending(path:"auth/v1/token").appending(queryItems:[URLQueryItem(name:"grant_type",value:"refresh_token")])
            let data=try await request(url,nil,["refresh_token":tokens.refresh_token],c.publishableKey)
            guard g==generation else {return};tokens=try JSONDecoder().decode(Tokens.self,from:data)
            try persist(.init(project:c.url,tokens:tokens))
        }
        let data=try await request(origin.appending(path:"v1/account"),tokens.access_token,nil,nil)
        guard g==generation else {return}
        let a=try JSONDecoder().decode(Account.self,from:data)
        billingAvailable=a.billing == true;remainingMS=a.remaining_ms;plan=a.plan;validUntil=a.valid_until
        current = a.active && a.available && a.remaining_ms>=35000 ? .init(origin:origin,bearer:tokens.access_token,expiry:Date(timeIntervalSince1970:tokens.expires_at)) : nil
        status = !a.active ? "尚无有效权益" : !a.available ? "托管服务已暂停" : current == nil ? "剩余额度不足" : "中文识别可用"
        apply()
    }
    public func signOut() async {
        guard origin != nil else {return}
        defaults.set(true,forKey:"hosted.restore-blocked.v1")
        let old=saved;generation=UUID();busy=false;current=nil;consent=false;defaults.set(false,forKey:"hosted.zh-consent.v1")
        apply(true);billingAvailable=false;signedIn=false;saved=nil;loaded=true;remainingMS=nil;plan=nil;validUntil=nil;status="已退出 · 本机识别可用"
        do { try keychain.delete(configurationID:slot,provider:.openAIResponses) } catch { status="钥匙串暂不可用；请再次退出以清除本机会话" }
        if let old, let c=try? await project(), old.project==c.url {
            _ = try? await request(c.url.appending(path:"auth/v1/logout"),old.tokens.access_token,[:],c.publishableKey)
        }
    }
    public func billingURL(portal:Bool) async -> URL? {
        var result:URL?
        await perform { g in guard let origin,let record=saved else {throw ProviderFailure.authorization}
            let data=try await request(origin.appending(path:portal ? "v1/portal":"v1/checkout"),record.tokens.access_token,[:],nil)
            struct Link: Decodable { let url:URL }
            let url = try JSONDecoder().decode(Link.self,from:data).url
            guard g==generation,url.scheme=="https",url.user==nil,url.password==nil,url.port==nil,["checkout.stripe.com","billing.stripe.com"].contains(url.host) else {throw ProviderFailure.connection}
            result=url }
        return result
    }
}
