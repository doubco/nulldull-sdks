import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// The SDK version, sent in `User-Agent` as `nulldull-sdk-swift/<version>`.
public let nullDullSDKVersion = "0.1.0"

/// The NullDull client for workspace API keys.
///
/// It holds only configuration and is safe to share between tasks.
///
/// ```swift
/// // Grid with a public key (safe in an app bundle):
/// let client = try NullDullClient(apiKey: "nd_pub_…")
/// let page = try await client.grid.getPage("my-blog", slug: "hello-world")
///
/// // Memory and Locale with a private key (servers and CI only):
/// let server = try NullDullClient(apiKey: secretKey, workspaceID: "9f8e7d6c-…")
/// let results = try await server.memory.search("release checklist")
/// ```
public final class NullDullClient: Sendable {
    /// Which kind of key the client was built with.
    public enum KeyKind: String, Sendable, Hashable {
        /// `nd_pub_…`: Grid delivery only; safe in browser and mobile bundles.
        case publicKey = "public"
        /// `nd_sec_…`: Grid, Memory and Locale; servers only.
        case privateKey = "private"
    }

    /// `https://nulldull.com`.
    public static let defaultBaseURL = URL(string: "https://nulldull.com")!

    /// Published Grid content.
    public let grid: GridAPI
    /// Read-only Memory.
    public let memory: MemoryAPI
    /// Locale export.
    public let locale: LocaleAPI
    /// The API base URL, without a trailing slash.
    public let baseURL: URL
    /// The workspace for `memory` and `locale` calls.
    public let workspaceID: String?
    public let keyKind: KeyKind

    /// Creates a client that sends requests with `URLSession`.
    ///
    /// - Parameters:
    ///   - apiKey: A workspace API key: public `nd_pub_…` or private `nd_sec_…`.
    ///   - workspaceID: Needed for `memory` and `locale`; a key cannot look up its own workspace.
    ///   - baseURL: Default `https://nulldull.com`. HTTP(S), without user info, query or fragment.
    ///   - session: The session to use. The default has no cookies and no cache. Redirects are always refused.
    ///   - timeout: Per-attempt timeout in seconds. Default 30; `0` disables it.
    ///   - maxRetries: Retries for 429/502/503/504 and network errors. Default 2; `0` disables them.
    ///   - userAgent: Appended to `User-Agent: nulldull-sdk-swift/0.1.0`.
    /// - Throws: ``NullDullError`` with code ``NullDullError/Code/invalidArgument`` for bad options.
    public convenience init(
        apiKey: String,
        workspaceID: String? = nil,
        baseURL: URL = NullDullClient.defaultBaseURL,
        session: URLSession = URLSessionTransport.defaultSession,
        timeout: TimeInterval = 30,
        maxRetries: Int = 2,
        userAgent: String? = nil
    ) throws {
        try self.init(
            apiKey: apiKey,
            workspaceID: workspaceID,
            baseURL: baseURL,
            transport: URLSessionTransport(session: session),
            timeout: timeout,
            maxRetries: maxRetries,
            userAgent: userAgent
        )
    }

    /// Creates a client with a custom transport, for tests or your own networking stack.
    ///
    /// - Parameters:
    ///   - apiKey: A workspace API key: public `nd_pub_…` or private `nd_sec_…`.
    ///   - workspaceID: Needed for `memory` and `locale`.
    ///   - baseURL: Default `https://nulldull.com`.
    ///   - transport: Sends each attempt. It must not follow redirects.
    ///   - timeout: Per-attempt timeout in seconds. Default 30; `0` disables it.
    ///   - maxRetries: Retries for 429/502/503/504 and network errors. Default 2.
    ///   - userAgent: Appended to `User-Agent: nulldull-sdk-swift/0.1.0`.
    ///   - sleep: Replaces the wait between retries (milliseconds), for tests.
    public init(
        apiKey: String,
        workspaceID: String? = nil,
        baseURL: URL = NullDullClient.defaultBaseURL,
        transport: any NullDullTransport,
        timeout: TimeInterval = 30,
        maxRetries: Int = 2,
        userAgent: String? = nil,
        sleep: NullDullSleep? = nil
    ) throws {
        guard isAPIKey(apiKey) else {
            throw NullDullError.invalidArgument("apiKey must be a NullDull workspace API key (nd_pub_… or nd_sec_…).")
        }
        if let workspaceID, !isWorkspaceID(workspaceID) {
            throw NullDullError.invalidArgument("workspaceID must be 1–128 letters, numbers, hyphens or underscores.")
        }
        guard timeout.isFinite, timeout >= 0 else {
            throw NullDullError.invalidArgument("timeout must be zero or a positive number of seconds.")
        }
        guard maxRetries >= 0 else { throw NullDullError.invalidArgument("maxRetries must be zero or more.") }
        let (base, origin) = try Self.normalize(baseURL)

        self.baseURL = URL(string: base)!
        self.workspaceID = workspaceID
        self.keyKind = apiKey.hasPrefix("nd_pub_") ? .publicKey : .privateKey
        let suffix = userAgent.flatMap { $0.isEmpty ? nil : " \($0)" } ?? ""
        let requester = Requester(
            apiKey: apiKey,
            baseURL: base,
            origin: origin,
            timeout: timeout,
            maxRetries: maxRetries,
            transport: transport,
            userAgent: "nulldull-sdk-swift/\(nullDullSDKVersion)\(suffix)",
            sleep: sleep ?? defaultSleep
        )
        let access = WorkspaceAccess(workspaceID: workspaceID, isPublicKey: keyKind == .publicKey)
        self.grid = GridAPI(requester: requester, publicKey: keyKind == .publicKey ? apiKey : nil)
        self.memory = MemoryAPI(requester: requester, access: access)
        self.locale = LocaleAPI(requester: requester, access: access)
    }

    private static func normalize(_ url: URL) throws -> (String, Origin) {
        let string = url.absoluteString
        guard let scheme = url.scheme?.lowercased(), scheme == "https" || scheme == "http",
            let host = url.host, !host.isEmpty,
            url.user == nil, url.password == nil, url.query == nil, url.fragment == nil,
            !string.contains("?"), !string.contains("#"),
            let origin = Origin(url)
        else {
            throw NullDullError.invalidArgument("baseURL must be an HTTP(S) URL without credentials, query or fragment.")
        }
        return (string.hasSuffix("/") ? String(string.dropLast()) : string, origin)
    }
}
