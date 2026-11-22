import Foundation
import NullDullGrid

/// When the built-in player for restricted embeds (YouTube, Vimeo) loads.
///
/// The same option exists in every NullDull Grid renderer ("embed loading": immediate or tap).
public enum GridEmbedLoading: Sendable, Hashable {
  /// Create the player as soon as the embed appears, without a tap. The video does not start
  /// until the viewer presses the player's play button. Default.
  case immediate
  /// Show a local poster with the node name, the provider and a play button, and make no request
  /// to the provider until the viewer taps it. The tap loads the player and starts the video.
  case tap
}

/// The parts of the built-in embed player that need no UI: the player URL, the local frame
/// page, the embedder identity and the navigation policy. `GridEmbedView` puts them in a web view.
///
/// YouTube's embedded player requires the embedder to identify itself with an HTTP `Referer` and
/// blocks playback with "error 153" when it is missing. A web view that loads the player URL as its
/// top-level page sends none, so the player is framed in a small local HTML page loaded with
/// `loadHTMLString(_:baseURL:)`, whose base URL is the app's identity `https://<bundle identifier>/`
/// (the format YouTube documents for apps). Vimeo gets the same page and identity.
enum GridEmbedPlayer {
  enum Provider: String, Sendable {
    case youtube = "YouTube"
    case vimeo = "Vimeo"
  }

  /// A resolved embed: the provider and the player URL the web renderer frames.
  struct Player: Hashable, Sendable {
    let provider: Provider
    let src: String

    /// The URL the frame page loads. `playsinline=1` keeps YouTube from switching to full screen
    /// on iOS when playback starts (Vimeo plays inline by default and accepts the same parameter).
    /// `autoplay=1` is added only when the player was created by the viewer's tap.
    func frameSrc(autoplay: Bool) -> String {
      var url = src + (src.contains("?") ? "&" : "?") + "playsinline=1"
      if autoplay { url += "&autoplay=1" }
      return url
    }
  }

  static func resolve(_ url: String?) -> Player? {
    guard let embed = GridEmbed(url) else { return nil }
    return Player(provider: embed.provider == .youtube ? .youtube : .vimeo, src: embed.playerURL)
  }

  /// Whether the player autoplays once created: only when the viewer's tap created it.
  static func autoplay(_ loading: GridEmbedLoading) -> Bool { loading == .tap }

  /// Whether the player exists yet: immediately once the embed has appeared, or after the tap.
  static func showsPlayer(_ loading: GridEmbedLoading, appeared: Bool, tapped: Bool) -> Bool {
    switch loading {
    case .immediate: return appeared || tapped
    case .tap: return tapped
    }
  }

  /// The embedder identity sent as `Referer`: `https://` plus the app's bundle identifier,
  /// lowercased, e.g. `https://com.example.app/`. Without a bundle identifier (a command-line tool)
  /// the process name stands in. Characters that cannot appear in a host name become `-`.
  static func embedderOrigin(bundleIdentifier: String?, processName: String = ProcessInfo.processInfo.processName) -> URL {
    let raw = (bundleIdentifier?.isEmpty == false ? bundleIdentifier! : processName).lowercased()
    var host = String(raw.unicodeScalars.map { scalar -> Character in
      let c = Character(scalar)
      return c.isASCII && (c.isLetter || c.isNumber || c == "." || c == "-") ? c : "-"
    })
    host = host.trimmingCharacters(in: CharacterSet(charactersIn: ".-"))
    if host.isEmpty { host = "app" }
    return URL(string: "https://\(host)/")!
  }

  /// The identity of this app (`Bundle.main`).
  static var appEmbedderOrigin: URL { embedderOrigin(bundleIdentifier: Bundle.main.bundleIdentifier) }

  /// The local page that frames the player. The iframe keeps the web renderer's sandbox, and adds
  /// `allow-popups` and `allow-top-navigation-by-user-activation` so links the viewer taps in the
  /// player (the title, the YouTube logo) reach the navigation policy, which hands them to the
  /// renderer's open-URL path instead of navigating. The referrer policy sends only the origin
  /// (the app identity) to the provider.
  static func html(_ player: Player, title: String, autoplay: Bool) -> String {
    var html = "<!doctype html><html><head><meta charset=\"utf-8\">"
    // The frame page itself never runs script: if markup ever got into it, nothing would execute.
    // The policy does not reach the cross-origin player, which keeps its own.
    html += "<meta http-equiv=\"Content-Security-Policy\" content=\"\(contentSecurityPolicy)\">"
    html += "<meta name=\"viewport\" content=\"width=device-width,initial-scale=1\">"
    html += "<meta name=\"referrer\" content=\"strict-origin-when-cross-origin\">"
    // The base URL is an identity, not a server: an inline icon stops a request for /favicon.ico.
    html += "<link rel=\"icon\" href=\"data:,\">"
    html += "<style>html,body{margin:0;padding:0;width:100%;height:100%;overflow:hidden;background:#000}"
    html += "iframe{display:block;border:0;width:100%;height:100%}</style></head><body>"
    html += "<iframe src=\"\(escape(player.frameSrc(autoplay: autoplay)))\" title=\"\(escape(title))\""
    html += " sandbox=\"allow-scripts allow-same-origin allow-presentation allow-popups allow-top-navigation-by-user-activation\""
    html += " allow=\"autoplay; encrypted-media; fullscreen; picture-in-picture\""
    html += " allowfullscreen referrerpolicy=\"strict-origin-when-cross-origin\"></iframe>"
    html += "</body></html>"
    return html
  }

  /// The frame page's policy: no script, plugins, `<base>` or form submissions of its own.
  static let contentSecurityPolicy = "script-src 'none'; object-src 'none'; base-uri 'none'; form-action 'none'"

  /// Escapes text for an HTML attribute value. It works on Unicode scalars, as the HTML tokenizer
  /// does: iterating `Character`s would miss a quote followed by a combining mark (one grapheme
  /// cluster, so not equal to `"`), and a document's node name could then close the attribute and
  /// add event handlers to the frame page.
  static func escape(_ value: String) -> String {
    var out = String.UnicodeScalarView()
    for scalar in value.unicodeScalars {
      switch scalar {
      case "&": out.append(contentsOf: "&amp;".unicodeScalars)
      case "<": out.append(contentsOf: "&lt;".unicodeScalars)
      case ">": out.append(contentsOf: "&gt;".unicodeScalars)
      case "\"": out.append(contentsOf: "&quot;".unicodeScalars)
      case "'": out.append(contentsOf: "&#39;".unicodeScalars)
      default: out.append(scalar)
      }
    }
    return String(out)
  }

  enum Navigation: Equatable {
    /// Let the web view load it (the frame page itself, and the player's own frames).
    case allow
    /// Cancel it and open this URL through the renderer's `openURL`.
    case open(URL)
    /// Cancel it.
    case cancel
  }

  /// The web view's navigation policy. The top-level page is the local frame page, loaded once;
  /// any later top-level navigation, or a new window (no target frame), means leaving the player,
  /// so a safe http(s) URL goes to `openURL` and anything else is dropped.
  ///
  /// - Parameters:
  ///   - targetsMainFrame: the navigation replaces the top-level page.
  ///   - opensNewWindow: the navigation has no target frame (`target=_blank`, `window.open`).
  ///   - isInitialLoad: the frame page has not been loaded yet.
  static func navigation(url: URL?, targetsMainFrame: Bool, opensNewWindow: Bool, isInitialLoad: Bool) -> Navigation {
    if !targetsMainFrame && !opensNewWindow { return .allow }
    if targetsMainFrame && !opensNewWindow && isInitialLoad { return .allow }
    if let href = GridURL.safeHref(url?.absoluteString), let target = URL(string: href) { return .open(target) }
    return .cancel
  }
}
