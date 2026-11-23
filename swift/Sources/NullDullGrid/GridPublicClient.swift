import Foundation

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

/// An HTTP error from the delivery API, with its status and machine-readable `code`
/// (`REQUEST_FAILED` when the body has none).
///
/// When the pool's workspace has used its monthly public requests, delivery answers `429`
/// `RATE_LIMITED` with ``reason`` ``publicRequestsPausedReason``: check ``isPublicRequestsPaused``
/// and show your own calm notice until ``renewsAt``. Equality compares `status` and `code` only.
public struct GridPublicError: Error, Equatable, Sendable, LocalizedError {
  public let status: Int
  public let code: String
  /// The body's `detail`, when it is a string.
  public let detail: String?
  /// The body's `reason`, when it is a string, for example ``publicRequestsPausedReason``.
  public let reason: String?
  /// The body's `renewsAt`: an ISO 8601 UTC time, sent with a paused allowance.
  public let renewsAt: String?
  /// `Retry-After` in seconds (delta-seconds or an HTTP date), when the response had one.
  public let retryAfter: Int?

  /// The `reason` of the `429` sent while the workspace's monthly public requests are used up.
  public static let publicRequestsPausedReason = "PUBLIC_REQUESTS_PAUSED"

  public init(status: Int, code: String) {
    self.init(status: status, code: code, detail: nil, reason: nil, renewsAt: nil, retryAfter: nil)
  }

  public init(status: Int, code: String, detail: String?, reason: String?, renewsAt: String?, retryAfter: Int?) {
    self.status = status
    self.code = code
    self.detail = detail
    self.reason = reason
    self.renewsAt = renewsAt
    self.retryAfter = retryAfter
  }

  /// True while the pool's workspace has used its monthly public requests. Delivery resumes at
  /// ``renewsAt`` (the start of the next UTC month) or a few minutes after the workspace upgrades.
  public var isPublicRequestsPaused: Bool { status == 429 && reason == Self.publicRequestsPausedReason }

  public var errorDescription: String? { "Grid request failed (\(status): \(code))." }

  public static func == (lhs: GridPublicError, rhs: GridPublicError) -> Bool {
    lhs.status == rhs.status && lhs.code == rhs.code
  }

  /// Parses `Retry-After` as delta-seconds or an HTTP date (seconds from `now`, at least 0).
  static func parseRetryAfter(_ value: String?, now: Date = Date()) -> Int? {
    guard let value = value?.trimmingCharacters(in: .whitespaces), !value.isEmpty else { return nil }
    if value.allSatisfy(\.isASCII), value.allSatisfy(\.isNumber) { return Int(value) }
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = TimeZone(identifier: "GMT")
    formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
    guard let date = formatter.date(from: value) else { return nil }
    return max(0, Int((date.timeIntervalSince(now)).rounded(.up)))
  }
}

/// Problems detected before or after a request, never sent to the server.
public enum GridClientError: Error, Equatable, Sendable, LocalizedError {
  /// Not `nd_pub_…`/`nd_sec_…` followed by 64 lowercase hex characters.
  case invalidAPIKey
  /// A private `nd_sec_` key on a platform where it would ship inside an app bundle.
  case privateKeyInAppBundle
  case invalidBaseURL
  case invalidArgument(String)
  /// The API answered with a redirect; the client never follows them.
  case redirectRejected(status: Int)
  case invalidResponse
  /// The response body was not the expected JSON shape, or its document failed validation.
  case invalidContent(String)

  public var errorDescription: String? {
    switch self {
    case .invalidAPIKey: "Use a NullDull workspace API key (nd_pub_… or nd_sec_…)."
    case .privateKeyInAppBundle: "Never ship a private NullDull API key in an app. Use a public key."
    case .invalidBaseURL: "Use an HTTP(S) Grid API base URL."
    case .invalidArgument(let message): message
    case .redirectRejected(let status): "The Grid API returned a redirect (\(status)); redirects are not followed."
    case .invalidResponse: "The Grid API returned an unexpected response."
    case .invalidContent(let message): "The Grid API returned invalid content: \(message)"
    }
  }
}

/// A workspace API key with the Published Grid content scope.
public struct GridAPIKey: Hashable, Sendable {
  public let rawValue: String
  public var isPublic: Bool { rawValue.hasPrefix("nd_pub_") }

  /// Validates the key format. Public keys (`nd_pub_`) may ship in apps; private keys (`nd_sec_`) belong on servers.
  public init(_ value: String) throws {
    let bytes = Array(value.utf8)
    let prefix = value.hasPrefix("nd_pub_") || value.hasPrefix("nd_sec_")
    guard prefix, bytes.count == 71,
      bytes[7...].allSatisfy({ (0x30...0x39).contains($0) || (0x61...0x66).contains($0) })
    else { throw GridClientError.invalidAPIKey }
    rawValue = value
  }
}

/// Read-only client for published Grid content (`/api/grid/v1`).
///
/// It sends the API key as a bearer token, never sends cookies, bypasses HTTP
/// caches (withdrawals take effect immediately), refuses redirects, validates
/// every returned document and resolves asset URLs. Only a public `nd_pub_` key
/// is added to asset URLs, which images, fonts and media load without headers.
/// Cancelling the calling `Task` cancels the request.
public struct GridPublicClient: Sendable {
  public let baseURL: URL
  public let apiKey: GridAPIKey?
  private let session: URLSession

  /// - Parameters:
  ///   - baseURL: for example `https://nulldull.com/api/grid/v1`.
  ///   - apiKey: a public `nd_pub_…` key for apps. On iOS, tvOS, visionOS and watchOS a private key is
  ///     rejected; on macOS and Linux it is accepted for server or tooling use but never placed in a URL.
  ///   - session: injectable for tests, proxies or custom configuration.
  public init(baseURL: URL, apiKey: String? = nil, session: URLSession = .shared) throws {
    let key = try apiKey.map(GridAPIKey.init)
    #if os(iOS) || os(tvOS) || os(visionOS) || os(watchOS)
      if let key, !key.isPublic { throw GridClientError.privateKeyInAppBundle }
    #endif
    guard let scheme = baseURL.scheme?.lowercased(), scheme == "https" || scheme == "http",
      baseURL.host?.isEmpty == false, baseURL.user == nil, baseURL.password == nil, baseURL.query == nil,
      baseURL.fragment == nil
    else { throw GridClientError.invalidBaseURL }
    self.baseURL = baseURL
    self.apiKey = key
    self.session = session
  }

  private var root: String {
    var text = baseURL.absoluteString
    if text.hasSuffix("/") { text.removeLast() }
    return text
  }

  private var origin: String {
    var components = URLComponents()
    components.scheme = baseURL.scheme?.lowercased()
    components.host = baseURL.host
    components.port = baseURL.port
    return components.string ?? root
  }

  /// Resolves an API-returned asset path against the API origin and appends a public key as `key`
  /// when the asset is on the API's own origin (scheme, host and port). Assets on any other host never
  /// receive the key, so it cannot leak to a third party.
  public func assetURL(_ value: String) -> URL? {
    let resolved: URL?
    if value.hasPrefix("//") {
      resolved = URL(string: "\(baseURL.scheme ?? "https"):\(value)")
    } else if value.hasPrefix("/") {
      resolved = URL(string: origin + value)
    } else {
      resolved = URL(string: value, relativeTo: URL(string: origin + "/"))?.absoluteURL
    }
    guard let resolved, var components = URLComponents(url: resolved, resolvingAgainstBaseURL: true) else {
      return nil
    }
    if let apiKey, apiKey.isPublic, isAPIOrigin(components),
      !(components.queryItems ?? []).contains(where: { $0.name == "key" })
    {
      components.queryItems = (components.queryItems ?? []) + [URLQueryItem(name: "key", value: apiKey.rawValue)]
    }
    return components.url
  }

  private func isAPIOrigin(_ components: URLComponents) -> Bool {
    func port(_ scheme: String?, _ port: Int?) -> Int? { port ?? (scheme == "https" ? 443 : scheme == "http" ? 80 : nil) }
    let scheme = components.scheme?.lowercased()
    let apiScheme = baseURL.scheme?.lowercased()
    return scheme == apiScheme && components.host?.lowercased() == baseURL.host?.lowercased()
      && port(scheme, components.port) == port(apiScheme, baseURL.port)
  }

  /// `GET /pools/{pool}/pages/{slug}?locale=…`: one published page with a validated document.
  public func page(pool: String, slug: String, locale: String = "en") async throws -> PublicGridPage {
    try check(pool, isPool: true)
    try check(slug, isPool: false)
    try checkLocale(locale)
    var page: PublicGridPage = try await read("/pools/\(pool)/pages/\(slug)?locale=\(locale)")
    page.summary.cover = page.summary.cover.map(resolve)
    page.assets = page.assets.map { asset in
      var asset = asset
      asset.url = assetURL(asset.url)?.absoluteString ?? asset.url
      return asset
    }
    return page
  }

  /// `GET /pools/{pool}/pages`: published page summaries.
  /// - Parameters:
  ///   - query: literal substring search (`q`).
  ///   - folderId: the direct parent folder captured at publication.
  ///   - limit: 1–50 on the server.
  ///   - after: the previous response's `nextCursor`.
  public func pages(
    pool: String, locale: String = "en", query: String? = nil, folderId: String? = nil, limit: Int? = nil,
    after: String? = nil
  ) async throws -> PublicGridPageList {
    try check(pool, isPool: true)
    try checkLocale(locale)
    var items: [(String, String)] = [("locale", locale)]
    if let after, !after.isEmpty { items.append(("after", after)) }
    if let query, !query.isEmpty { items.append(("q", query)) }
    if let folderId {
      guard GridValidator.isGridId(folderId) else { throw GridClientError.invalidArgument("Invalid identifier.") }
      items.append(("folderId", folderId))
    }
    if let limit { items.append(("limit", String(limit))) }
    let search = items.map { "\(GridPublicClient.formEncode($0.0))=\(GridPublicClient.formEncode($0.1))" }
      .joined(separator: "&")
    var list: PublicGridPageList = try await read("/pools/\(pool)/pages?\(search)")
    list.items = list.items.map { item in
      var item = item
      item.cover = item.cover.map(resolve)
      return item
    }
    return list
  }

  private func resolve(_ cover: PublicGridCover) -> PublicGridCover {
    var cover = cover
    cover.url = assetURL(cover.url)?.absoluteString ?? cover.url
    return cover
  }

  private func check(_ value: String, isPool: Bool) throws {
    guard GridPublicArguments.isPublicKey(value) else {
      throw GridClientError.invalidArgument("Use 1–96 lowercase letters, numbers and single hyphens.")
    }
  }

  private func checkLocale(_ value: String) throws {
    guard GridPublicArguments.isLocale(value) else {
      throw GridClientError.invalidArgument("Use a lowercase language tag, such as en or pt-br.")
    }
  }

  /// `application/x-www-form-urlencoded`, as `URLSearchParams` serializes.
  static func formEncode(_ value: String) -> String {
    var out = ""
    for byte in value.utf8 {
      switch byte {
      case 0x30...0x39, 0x41...0x5A, 0x61...0x7A, UInt8(ascii: "*"), UInt8(ascii: "-"), UInt8(ascii: "."),
        UInt8(ascii: "_"):
        out.unicodeScalars.append(Unicode.Scalar(byte))
      case 0x20: out += "+"
      default: out += String(format: "%%%02X", byte)
      }
    }
    return out
  }

  private func read<T: Decodable>(_ path: String) async throws -> T {
    guard let url = URL(string: root + path) else { throw GridClientError.invalidBaseURL }
    var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalAndRemoteCacheData)
    request.httpMethod = "GET"
    request.httpShouldHandleCookies = false
    request.setValue("application/json", forHTTPHeaderField: "Accept")
    if let apiKey { request.setValue("Bearer \(apiKey.rawValue)", forHTTPHeaderField: "Authorization") }
    let (data, response): (Data, URLResponse)
    do {
      (data, response) = try await session.data(for: request, delegate: NoRedirects.shared)
    } catch let error as URLError where error.code == .cancelled {
      throw CancellationError()
    }
    try Task.checkCancellation()
    guard let http = response as? HTTPURLResponse else { throw GridClientError.invalidResponse }
    if (300..<400).contains(http.statusCode) { throw GridClientError.redirectRejected(status: http.statusCode) }
    guard (200..<300).contains(http.statusCode) else {
      let body = try? JSONValue.parse(data)
      func text(_ key: String) -> String? {
        if case .string(let value)? = body?[key] { return value }
        return nil
      }
      throw GridPublicError(
        status: http.statusCode, code: text("code") ?? "REQUEST_FAILED", detail: text("detail"),
        reason: text("reason"), renewsAt: text("renewsAt"),
        retryAfter: GridPublicError.parseRetryAfter(http.value(forHTTPHeaderField: "Retry-After")))
    }
    do {
      return try JSONDecoder().decode(T.self, from: data)
    } catch let error as GridValidationError {
      throw GridClientError.invalidContent(error.message)
    } catch let DecodingError.dataCorrupted(context) {
      throw GridClientError.invalidContent(context.underlyingError.map { "\($0)" } ?? context.debugDescription)
    } catch {
      throw GridClientError.invalidContent("\(error)")
    }
  }
}

/// Refuses every redirect, like `fetch(…, { redirect: "error" })`.
final class NoRedirects: NSObject, URLSessionTaskDelegate, Sendable {
  static let shared = NoRedirects()
  func urlSession(
    _ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
    newRequest request: URLRequest
  ) async -> URLRequest? {
    nil
  }
}
