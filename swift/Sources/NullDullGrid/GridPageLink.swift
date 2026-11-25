import Foundation

/// A version-1 destination in a published document. The alias is local to this document.
public struct GridPageLink: Hashable, Sendable {
  public let entryId: String
  public let anchor: String?
  public var version: Int { 1 }

  public init?(entryId: String, anchor: String? = nil) {
    guard entryId.hasPrefix("~"), let ordinal = Int(entryId.dropFirst()),
      (1...64).contains(ordinal), entryId == "~\(ordinal)" else { return nil }
    if let anchor {
      guard (1...128).contains(anchor.utf8.count),
        anchor.utf8.allSatisfy({ (65...90).contains($0) || (97...122).contains($0)
          || (48...57).contains($0) || [45, 46, 95, 126].contains($0) }) else { return nil }
    }
    self.entryId = entryId
    self.anchor = anchor
  }

  public init?(destination: String) {
    let prefix = "grid-page:v1:"
    guard destination.hasPrefix(prefix) else { return nil }
    let parts = destination.dropFirst(prefix.count).split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false)
    self.init(entryId: String(parts[0]), anchor: parts.count == 2 ? String(parts[1]) : nil)
  }

  init(json: JSONValue) throws {
    guard case .object(let o) = json, o.keys.allSatisfy({ ["version", "entryId", "anchor"].contains($0) }),
      o["version"] == .number(1), case .string(let id)? = o["entryId"] else {
      throw GridValidationError("Invalid Grid page reference.")
    }
    let anchor: String?
    switch o["anchor"] {
    case nil: anchor = nil
    case .string(let value): anchor = value
    default: throw GridValidationError("Invalid Grid page reference.")
    }
    guard let link = Self(entryId: id, anchor: anchor) else { throw GridValidationError("Invalid Grid page reference.") }
    self = link
  }

  var json: JSONValue {
    var o = JSONObject([("version", .number(1)), ("entryId", .string(entryId))])
    o["anchor"] = anchor.map(JSONValue.string)
    return .object(o)
  }

  public func resolvedURL(in targets: [String: PublishedGridPageTarget], using resolver: GridPageLinkResolver?) -> URL? {
    guard let target = targets[entryId], target.published, let href = resolver?(target, anchor),
      !href.isEmpty, !href.contains("\\"), !href.unicodeScalars.contains(where: { $0.properties.isWhitespace || $0 == "\u{FEFF}" })
    else { return nil }
    if href.hasPrefix("/") { return href.hasPrefix("//") ? nil : URL(string: href) }
    return GridURL(parsing: href)?.pageURL
  }
}

private extension GridURL {
  /// Browsers validate bracketed literals and parse hosts ending in a number as IPv4.
  var pageURL: URL? {
    if host.hasPrefix("[") {
      var address = in6_addr()
      guard host.hasSuffix("]"), inet_pton(AF_INET6, String(host.dropFirst().dropLast()), &address) == 1 else { return nil }
    } else {
      let domain = host.hasSuffix(".") ? String(host.dropLast()) : host
      let last = domain.split(separator: ".", omittingEmptySubsequences: false).last ?? ""
      let numeric = !last.isEmpty && last.utf8.allSatisfy { (48...57).contains($0) }
      let hex = last.hasPrefix("0x") && last.dropFirst(2).allSatisfy { $0.isASCII && $0.isHexDigit }
      if numeric || hex {
        var address = in_addr()
        guard inet_aton(domain, &address) == 1, var parts = URLComponents(string: href) else { return nil }
        parts.host = withUnsafeBytes(of: &address.s_addr) { $0.map(String.init).joined(separator: ".") }
        return parts.url
      }
    }
    return url
  }
}

/// The target's current publication coordinates from the page detail response.
public struct PublishedGridPageTarget: Codable, Hashable, Sendable {
  public let entryId: String
  public let published: Bool
  public let pool: String
  public let slug: String
  public let locale: String

  public init(entryId: String, published: Bool = true, pool: String, slug: String, locale: String) {
    self.entryId = entryId
    self.published = published
    self.pool = pool
    self.slug = slug
    self.locale = locale
  }
}

/// Return a credential-free HTTP(S) URL, an app-handled root-relative path, or nil.
public typealias GridPageLinkResolver = (PublishedGridPageTarget, _ anchor: String?) -> String?
