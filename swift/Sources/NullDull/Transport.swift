import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Sends one HTTP request and returns the whole response body.
///
/// The client calls the transport once per attempt and handles retries, timeouts and
/// errors itself. The default is ``URLSessionTransport``. Tests (and apps with their own
/// networking stack) can supply any type that conforms.
///
/// A transport MUST NOT follow redirects: return the `3xx` response as is. It should throw
/// for transport failures (DNS, TLS, connection reset); the client reports those as
/// ``NullDullError/Code/networkError`` and retries them.
public protocol NullDullTransport: Sendable {
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

/// The default transport: `URLSession`, with redirects refused, no cookies and no cache.
public struct URLSessionTransport: NullDullTransport {
    public let session: URLSession

    /// A session with no cookie storage and no URL cache. Used when you do not pass your own.
    public static let defaultSession: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.httpCookieAcceptPolicy = .never
        return URLSession(configuration: configuration)
    }()

    public init(session: URLSession = URLSessionTransport.defaultSession) {
        self.session = session
    }

    public func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        #if canImport(FoundationNetworking)
        // swift-corelibs-foundation has no per-task delegates; redirects cannot be refused here.
        let (data, response) = try await session.data(for: request)
        #else
        let (data, response) = try await session.data(for: request, delegate: RedirectRefuser.shared)
        #endif
        guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        return (data, http)
    }
}

#if !canImport(FoundationNetworking)
/// Refuses every redirect so the API key is never sent to another origin. The `3xx`
/// response is returned to the client, which raises ``NullDullError/Code/requestFailed``.
final class RedirectRefuser: NSObject, URLSessionTaskDelegate, Sendable {
    static let shared = RedirectRefuser()

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping @Sendable (URLRequest?) -> Void
    ) {
        completionHandler(nil)
    }
}
#endif
