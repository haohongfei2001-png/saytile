import Foundation
@testable import SaytileKit

private actor AuthFixture {
    var refreshed = false, loggedOut = false
    private(set) var requestCount = 0
    func respond(_ url:URL,_ bearer:String?,_ body:[String:String]?,_ key:String?) throws -> Data {
        requestCount += 1
        let value:[String:Any]
        switch url.path {
        case "/v1/config": value=["url":"https://fixture.supabase.co","publishableKey":"sb_publishable_fixture"]
        case "/auth/v1/otp":
            precondition(key=="sb_publishable_fixture" && body?["email"]=="synthetic@example.invalid")
            value=[:]
        case "/auth/v1/verify":
            precondition(body?["token"]=="000000" && body?["type"]=="email")
            value=["access_token":"synthetic-only","refresh_token":"fixture-refresh","expires_at":0]
        case "/auth/v1/token":
            precondition(body?["refresh_token"]=="fixture-refresh");refreshed=true
            value=["access_token":"fixture-renewed","refresh_token":"rotated-fixture","expires_at":Date().timeIntervalSince1970+3600]
        case "/v1/account":
            precondition(bearer=="fixture-renewed");value=["active":true,"available":true,"billing":false,"remaining_ms":90000,"plan":"fixture"]
        case "/auth/v1/logout": precondition(bearer=="fixture-renewed");loggedOut=true;value=[:]
        default: throw ProviderFailure.incomplete
        }
        return try JSONSerialization.data(withJSONObject:value)
    }
}
@MainActor enum HostedAccountProbe {
    static func run() async throws {
        let tag="app.saytile.account.fixture."+UUID().uuidString
        guard let prefs=UserDefaults(suiteName:tag) else {throw ProviderFailure.incomplete}
        defer {prefs.removePersistentDomain(forName:tag)}
        let store=KeychainCredentialStore(service:tag),fixture=AuthFixture()
        let slot=UUID(uuidString:"5A1711E0-0000-4000-8000-000000000001")!
        defer {try? store.delete(configurationID:slot,provider:.openAIResponses)}
        func make()->HostedAccount {
            HostedAccount(preferences:prefs,production:true,origin:URL(string:"https://fixture.invalid")!,keychain:store,
                          request:{ try await fixture.respond($0,$1,$2,$3) })
        }
        let a=make();precondition(!a.selected && !a.consent)
        var accountRoutes = [HostedRoute]()
        a.bind { route, _ in accountRoutes.append(route) }
        a.displaySavedAccount()
        let callsAfterBrowsing = await fixture.requestCount
        precondition(callsAfterBrowsing == 0 && accountRoutes == [.byok])
        await a.sendCode(email:"synthetic@example.invalid");await a.verify(email:"synthetic@example.invalid",code:"000000")
        guard a.signedIn,a.remainingMS==90000,await fixture.refreshed else {throw ProviderFailure.incomplete}
        precondition(!a.selected && !a.consent && accountRoutes == [.byok])
        let b=make()
        let beforeRestore = await fixture.requestCount
        b.displaySavedAccount()
        let afterRestore = await fixture.requestCount
        precondition(b.signedIn && !b.selected && !b.consent && beforeRestore == afterRestore)
        b.select(true);await b.refresh()
        guard b.signedIn,b.remainingMS==90000 else {throw ProviderFailure.incomplete}
        var route=HostedRoute.byok
        var revoked = false
        b.bind { route=$0; revoked=$1 };precondition(route == .local)
        b.authorize(true);guard case .connected=route else {throw ProviderFailure.incomplete}
        b.select(false);precondition(route == .byok && b.signedIn)
        await b.signOut()
        precondition(route == .byok && !revoked)
        let c=make();c.select(true);await c.refresh()
        guard !c.signedIn,await fixture.loggedOut,try store.read(configurationID:slot,provider:.openAIResponses)==nil else {throw ProviderFailure.incomplete}
        print("PASS isolated macOS Keychain save/restore/delete, account browsing with zero requests, independent OTP sign-in, rotated refresh, opt-in upload, local logout fence, BYOK switch")
    }
}
