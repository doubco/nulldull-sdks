import Foundation
import Testing

@testable import NullDull

#if !canImport(FoundationNetworking)
/// Serves canned responses inside a real `URLSession`, including redirects, so the default
/// transport's redirect refusal is tested end to end without the network.
final class StubProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) private static var recorded: [String] = []
    private static let lock = NSLock()

    static var hits: [String] {
        lock.lock()
        defer { lock.unlock() }
        return recorded
    }

    static func record(_ url: String) {
        lock.lock()
        recorded.append(url)
        lock.unlock()
    }

    static func reset() {
        lock.lock()
        recorded = []
        lock.unlock()
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let url = request.url!
        Self.record(url.absoluteString)
        if url.path == "/redirect" || url.path.hasSuffix("/pages") && url.host == "redirect.test" {
            let response = HTTPURLResponse(
                url: url, statusCode: 302, httpVersion: "HTTP/1.1", headerFields: ["Location": "https://evil.example/steal"])!
            client?.urlProtocol(self, wasRedirectedTo: URLRequest(url: URL(string: "https://evil.example/steal")!), redirectResponse: response)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocolDidFinishLoading(self)
            return
        }
        let body = Fixtures.data("grid/page-list-last.json")
        let response = HTTPURLResponse(
            url: url, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "application/json"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

@Suite("URLSessionTransport", .serialized)
struct URLSessionTransportTests {
    private func session() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubProtocol.self]
        return URLSession(configuration: configuration)
    }

    @Test func refusesRedirects() async throws {
        StubProtocol.reset()
        let client = try NullDullClient(apiKey: publicKey, baseURL: URL(string: "https://redirect.test")!, session: session())
        let error = await failure { _ = try await client.grid.listPages("nulldull-blog") }
        #expect(error.code == .requestFailed)
        #expect(error.status == 302)
        #expect(!StubProtocol.hits.contains { $0.contains("evil.example") })
    }

    @Test func sendsRequestsThroughTheSession() async throws {
        let client = try NullDullClient(apiKey: publicKey, baseURL: URL(string: "https://ok.test")!, session: session())
        let list = try await client.grid.listPages("nulldull-blog")
        #expect(list.nextCursor == nil)
    }
}
#endif
