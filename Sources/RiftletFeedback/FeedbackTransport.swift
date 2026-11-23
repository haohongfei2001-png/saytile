import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public enum FeedbackRequest: Sendable { case submit, status, delete }
public protocol FeedbackTransport: Sendable {
    var configured: Bool { get }
    func perform(_ action: FeedbackRequest, record: FeedbackRecord, secret: String) async throws -> FeedbackReceipt
}
public struct DisabledFeedbackTransport: FeedbackTransport {
    public let configured = false
    public init() {}
    public func perform(_ action: FeedbackRequest, record: FeedbackRecord, secret: String) async throws -> FeedbackReceipt { throw FeedbackFailure.endpointUnavailable }
}

private final class NoFeedbackRedirect: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) { completionHandler(nil) }
}

public struct HTTPSFeedbackTransport: FeedbackTransport {
    public let configured = true
    private let endpoint: URL
    public init(endpoint: URL) throws {
        guard endpoint.scheme == "https", let host = endpoint.host, !host.isEmpty,
              endpoint.user == nil, endpoint.password == nil, endpoint.query == nil, endpoint.fragment == nil,
              endpoint.port == nil || endpoint.port == 443, endpoint.path == "/v1/feedback" else { throw FeedbackFailure.endpointUnavailable }
        self.endpoint = endpoint
    }
    public func perform(_ action: FeedbackRequest, record: FeedbackRecord, secret: String) async throws -> FeedbackReceipt {
        guard UUID(uuidString: record.id) != nil, secret.range(of: "^[0-9a-f]{64}$", options: .regularExpression) != nil else { throw FeedbackFailure.secretUnavailable }
        let url: URL
        switch action { case .submit: url = endpoint; default: url = endpoint.appendingPathComponent(record.id) }
        var request = URLRequest(url: url); request.timeoutInterval = 20
        request.setValue("Bearer " + secret, forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        switch action {
        case .submit:
            request.httpMethod = "POST"; request.httpBody = record.bytes
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        case .status: request.httpMethod = "GET"
        case .delete: request.httpMethod = "DELETE"
        }
        let config = URLSessionConfiguration.ephemeral
        config.httpCookieStorage = nil; config.httpShouldSetCookies = false; config.urlCache = nil
        config.urlCredentialStorage = nil; config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.timeoutIntervalForResource = 30
        let session = URLSession(configuration: config, delegate: NoFeedbackRedirect(), delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        let data: Data, response: URLResponse
        #if os(macOS)
        let (stream, received) = try await session.bytes(for: request)
        response = received
        var buffer = Data()
        for try await byte in stream {
            guard buffer.count < 32768 else { throw FeedbackFailure.invalidResponse }
            buffer.append(byte)
        }
        data = buffer
        #else
        (data, response) = try await session.data(for: request)
        #endif
        guard let http = response as? HTTPURLResponse, http.url?.host == endpoint.host, data.count <= 32768 else { throw FeedbackFailure.invalidResponse }
        if http.statusCode == 429 {
            let delay = Int(http.value(forHTTPHeaderField: "Retry-After") ?? "") ?? 300
            throw FeedbackFailure.rateLimited(max(1, min(86400, delay)))
        }
        if http.statusCode == 409 { throw FeedbackFailure.conflict }
        if [400, 401, 403, 413, 422].contains(http.statusCode) { throw FeedbackFailure.rejected }
        guard (200...299).contains(http.statusCode), http.value(forHTTPHeaderField: "Content-Type")?.lowercased().hasPrefix("application/json") == true else { throw FeedbackFailure.transport }
        let receipt: FeedbackReceipt
        do { receipt = try JSONDecoder().decode(FeedbackReceipt.self, from: data) }
        catch { throw FeedbackFailure.invalidResponse }
        try receipt.validate(for: record.id)
        return receipt
    }
}

/// No network, conspicuously labelled by the separate demo executable.
public actor DemoFeedbackTransport: FeedbackTransport {
    public nonisolated let configured = true
    private var received: Set<String> = []
    public init() {}
    public func perform(_ action: FeedbackRequest, record: FeedbackRecord, secret: String) async throws -> FeedbackReceipt {
        switch action {
        case .submit: received.insert(record.id); return FeedbackReceipt(id: record.id)
        case .status: return FeedbackReceipt(id: record.id)
        case .delete: received.remove(record.id); return FeedbackReceipt(id: record.id, state: "deleted")
        }
    }
}
