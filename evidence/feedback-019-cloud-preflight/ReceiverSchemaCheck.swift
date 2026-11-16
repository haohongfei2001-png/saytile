import Foundation

final class Direct: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping @Sendable (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}

let endpoint = URL(string: "https://riftlet-feedback-receiver.haohongfei2001.workers.dev/v1/feedback")!
let cfg = URLSessionConfiguration.ephemeral
cfg.httpShouldSetCookies = false
cfg.urlCredentialStorage = nil
cfg.timeoutIntervalForRequest = 15
cfg.timeoutIntervalForResource = 25
let session = URLSession(configuration: cfg, delegate: Direct(), delegateQueue: nil)
let id = UUID().uuidString.lowercased()
let capability = (UUID().uuidString + UUID().uuidString).replacingOccurrences(of: "-", with: "").lowercased()
func probe(_ kind: String) async throws -> (Int, String) {
    let lookup = kind == "lookup"
    var req = URLRequest(url: lookup ? endpoint.appendingPathComponent(id) : endpoint)
    req.httpMethod = lookup ? "GET" : "POST"
    req.setValue("Bearer " + capability, forHTTPHeaderField: "Authorization")
    if !lookup {
        var fields: [String: Any] = ["schema":1, "id":id,"kind":"problem","createdAt":0,"appVersion":"0.19",
                                    "text":"Expired synthetic schema check"]
        if kind == "tagged" {fields["product"] = "saytile"}
        req.setValue("application/json", forHTTPHeaderField:"Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: fields)
    }
    let (bytes, raw) = try await session.data(for: req)
    guard let http = raw as? HTTPURLResponse, http.url == req.url else { throw URLError(.badServerResponse) }
    let code = (try? JSONSerialization.jsonObject(with: bytes) as? [String: Any])?["error"] as? String
    let known = ["schema","submission_age","not_found","unavailable","unauthorized","rate_limited"]
    let label = code.flatMap {known.contains($0) ? $0 : nil} ?? "unclassified"
    print(kind, http.statusCode, label)
    return (http.statusCode, label)
}
print("fixture", id)
do {
    guard try await probe("legacy") == (422, "submission_age") else { throw URLError(.badServerResponse) }
    let tagged = try await probe("tagged")
    let lookup = try await probe("lookup")
    guard tagged.0 == 422, ["schema","submission_age"].contains(tagged.1), lookup == (404,"not_found") else {
        throw URLError(.badServerResponse)
    }
} catch { let err = error as NSError; print("indeterminate", err.domain, err.code); exit(1) }
