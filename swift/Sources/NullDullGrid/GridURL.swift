import Foundation

/// An absolute http(s) URL parsed and serialized the way the WHATWG URL
/// standard (JavaScript's `new URL(value).href`) does for the cases Grid uses:
/// scheme/host case folding, default ports, dot segments and percent-encoding.
/// Anything else, and any URL with a username or password, is rejected.
///
/// Known differences from browsers, all of which fail closed or keep the host
/// as written: internationalized host names are lower-cased but not
/// Punycode-encoded, IPv6 literals are not re-compressed and numeric IPv4
/// shorthands are not expanded.
public struct GridURL: Hashable, Sendable {
  public let scheme: String
  public let host: String
  public let port: Int?
  public let path: String
  public let query: String?
  public let fragment: String?

  public var href: String {
    var result = "\(scheme)://\(host)"
    if let port { result += ":\(port)" }
    result += path
    if let query { result += "?\(query)" }
    if let fragment { result += "#\(fragment)" }
    return result
  }

  public var url: URL? { URL(string: href) }

  /// The normalized href of a credential-free http(s) URL, as `safeGridUrl`/`gridLink` return it.
  public static func safeHref(_ value: String?) -> String? {
    guard let value, let parsed = GridURL(parsing: value) else { return nil }
    return parsed.href
  }

  /// Search parameters decoded like `URLSearchParams` (`+` is a space).
  public func queryItem(_ name: String) -> String? {
    guard let query else { return nil }
    for pair in query.split(separator: "&", omittingEmptySubsequences: true) {
      let parts = pair.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
      let key = GridURL.formDecode(String(parts[0]))
      if key == name { return parts.count > 1 ? GridURL.formDecode(String(parts[1])) : "" }
    }
    return nil
  }

  static func formDecode(_ value: String) -> String {
    let spaced = value.replacingOccurrences(of: "+", with: " ")
    return spaced.removingPercentEncoding ?? spaced
  }

  public init?(parsing input: String) { self.init(parsing: input, pageRoute: false) }

  init?(parsing input: String, pageRoute: Bool) {
    // Strip leading/trailing C0 controls and spaces; drop tabs and newlines anywhere.
    var scalars = Array(input.unicodeScalars)
    while let first = scalars.first, first.value <= 0x20 { scalars.removeFirst() }
    while let last = scalars.last, last.value <= 0x20 { scalars.removeLast() }
    scalars.removeAll { $0 == "\t" || $0 == "\n" || $0 == "\r" }
    let text = String(String.UnicodeScalarView(scalars))

    guard let colon = text.firstIndex(of: ":") else { return nil }
    let scheme = text[..<colon].lowercased()
    guard scheme == "http" || scheme == "https" else { return nil }
    var rest = Substring(text[text.index(after: colon)...])
    while let first = rest.first, first == "/" || first == "\\" { rest.removeFirst() }

    let authorityEnd = rest.firstIndex { "/\\?#".contains($0) } ?? rest.endIndex
    var authority = rest[..<authorityEnd]
    var remainder = rest[authorityEnd...]

    if let at = authority.lastIndex(of: "@") {
      let userinfo = authority[..<at]
      // Any username or password makes the URL unsafe (an empty "@" is allowed).
      if userinfo.contains(where: { $0 != ":" }) || (pageRoute && userinfo.count > 1) { return nil }
      authority = authority[authority.index(after: at)...]
    }

    var hostPart = authority
    var portText: Substring?
    if authority.hasPrefix("[") {
      guard let close = authority.firstIndex(of: "]") else { return nil }
      hostPart = authority[...close]
      let after = authority[authority.index(after: close)...]
      if !after.isEmpty {
        guard after.hasPrefix(":") else { return nil }
        portText = after.dropFirst()
      }
    } else if let colon = authority.lastIndex(of: ":") {
      hostPart = authority[..<colon]
      portText = authority[authority.index(after: colon)...]
    }

    guard !hostPart.isEmpty, let decodedHost = String(hostPart).removingPercentEncoding else { return nil }
    let host = decodedHost.lowercased()
    let forbidden: Set<Character> = [" ", "#", "%", "/", ":", "<", ">", "?", "@", "[", "\\", "]", "^", "|"]
    if !host.hasPrefix("[") {
      if host.contains(where: { forbidden.contains($0) || ($0.asciiValue.map { $0 < 0x20 || $0 == 0x7F } ?? false) }) {
        return nil
      }
    } else if !host.dropFirst().dropLast().allSatisfy({ $0.isHexDigit || $0 == ":" || $0 == "." }) {
      return nil
    }

    var port: Int?
    if let portText, !portText.isEmpty {
      guard portText.allSatisfy({ $0.isASCII && $0.isNumber }) else { return nil }
      let digits = portText.drop { $0 == "0" }
      guard digits.count <= 5, let value = Int(digits.isEmpty ? "0" : String(digits)), value <= 65535 else {
        return nil
      }
      port = (scheme == "http" && value == 80) || (scheme == "https" && value == 443) ? nil : value
    }

    var fragment: String?
    if let hash = remainder.firstIndex(of: "#") {
      fragment = GridURL.encode(remainder[remainder.index(after: hash)...], GridURL.fragmentSet)
      remainder = remainder[..<hash]
    }
    var query: String?
    if let mark = remainder.firstIndex(of: "?") {
      query = GridURL.encode(remainder[remainder.index(after: mark)...], GridURL.querySet)
      remainder = remainder[..<mark]
    }

    let rawPath = remainder.replacingOccurrences(of: "\\", with: "/")
    var segments = rawPath.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
    if rawPath.hasPrefix("/") { segments.removeFirst() }
    var output: [String] = []
    for (index, segment) in segments.enumerated() {
      let last = index == segments.count - 1
      let lower = segment.lowercased()
      if ["..", ".%2e", "%2e.", "%2e%2e"].contains(lower) {
        if !output.isEmpty { output.removeLast() }
        if last { output.append("") }
      } else if [".", "%2e"].contains(lower) {
        if last { output.append("") }
      } else {
        output.append(GridURL.encode(Substring(segment), GridURL.pathSet))
      }
    }
    self.scheme = scheme
    self.host = host
    self.port = port
    self.path = "/" + output.joined(separator: "/")
    self.query = query
    self.fragment = fragment
  }

  static let fragmentSet: Set<UInt8> = [0x20, 0x22, 0x3C, 0x3E, 0x60]
  static let querySet: Set<UInt8> = [0x20, 0x22, 0x23, 0x3C, 0x3E, 0x27]
  static let pathSet: Set<UInt8> = [0x20, 0x22, 0x23, 0x3C, 0x3E, 0x3F, 0x60, 0x7B, 0x7D]

  static func encode(_ value: Substring, _ set: Set<UInt8>) -> String {
    var out = ""
    for byte in value.utf8 {
      if byte < 0x21 || byte > 0x7E || set.contains(byte) {
        out += String(format: "%%%02X", byte)
      } else {
        out.unicodeScalars.append(Unicode.Scalar(byte))
      }
    }
    return out
  }
}

/// Restricted video embeds, as `gridEmbedUrl` resolves them: YouTube (privacy-enhanced host) and Vimeo only.
public struct GridEmbed: Hashable, Sendable {
  public enum Provider: String, Sendable { case youtube, vimeo }
  public let provider: Provider
  /// The player URL the web renderer frames.
  public let playerURL: String
  /// The safe page URL the author entered.
  public let pageURL: String

  public init?(_ value: String?) {
    guard let value, let url = GridURL(parsing: value) else { return nil }
    let host = url.host
    var id: String?
    if host == "youtu.be" {
      id = String(url.path.dropFirst())
    } else if host == "youtube.com" || host == "www.youtube.com" {
      if let v = url.queryItem("v"), !v.isEmpty {
        id = v
      } else {
        let parts = url.path.split(separator: "/", omittingEmptySubsequences: false)
        if parts.count == 3, parts[0].isEmpty, parts[1] == "embed" || parts[1] == "shorts", !parts[2].isEmpty,
          parts[2].allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "_" || $0 == "-") })
        {
          id = String(parts[2])
        }
      }
    }
    if let id, id.utf8.count == 11,
      id.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "_" || $0 == "-") })
    {
      provider = .youtube
      playerURL = "https://www.youtube-nocookie.com/embed/\(id)"
      pageURL = url.href
      return
    }
    if host == "vimeo.com" || host == "www.vimeo.com", url.path.count > 1, url.path.dropFirst().allSatisfy({ $0.isASCII && $0.isNumber }) {
      provider = .vimeo
      playerURL = "https://player.vimeo.com/video\(url.path)"
      pageURL = url.href
      return
    }
    return nil
  }
}
