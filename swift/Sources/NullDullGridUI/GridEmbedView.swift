import Foundation
import NullDullGrid
import SwiftUI

#if canImport(WebKit) && !os(tvOS)
  import WebKit
#endif

@available(iOS 16, macOS 13, tvOS 16, *)
struct GridEmbedLoadingKey: EnvironmentKey {
  static let defaultValue: GridEmbedLoading = .immediate
}

@available(iOS 16, macOS 13, tvOS 16, *)
extension EnvironmentValues {
  /// Set by `GridView` from its `embedLoading:` argument.
  var gridEmbedLoading: GridEmbedLoading {
    get { self[GridEmbedLoadingKey.self] }
    set { self[GridEmbedLoadingKey.self] = newValue }
  }
}

/// Default embed rendering for restricted embeds (YouTube on its privacy-enhanced host, and Vimeo).
///
/// With WebKit (iOS, macOS, visionOS) the provider's player plays inline: it loads as soon as the
/// embed appears (`.immediate`), or after the viewer taps a local poster (`.tap`), which also starts
/// the video. tvOS has no web view, so there the card opens the video through `openURL`. Other
/// URLs show a link or text. Supply `embed:` on `GridView` to replace all of this.
@available(iOS 16, macOS 13, tvOS 16, *)
struct GridEmbedContent: View {
  let node: GridBuiltinNode
  let messages: GridMessages
  @Environment(\.gridEmbedLoading) private var loading
  @State private var appeared = false
  @State private var tapped = false

  /// What the player is built from. The web view loads its page once, so `GridNodeView` gives the
  /// content this identity: when the document changes the node's URL or name, the old player
  /// (and a tap on the old poster) is discarded instead of staying on screen.
  static func identity(_ node: GridBuiltinNode) -> [String?] { [node.url, node.name] }

  var body: some View {
    if let player = GridEmbedPlayer.resolve(node.url) {
      #if canImport(WebKit) && !os(tvOS)
        if GridEmbedPlayer.showsPlayer(loading, appeared: appeared, tapped: tapped) {
          GridEmbedWebView(
            player: player, title: node.name, autoplay: tapped && GridEmbedPlayer.autoplay(loading),
            origin: GridEmbedPlayer.appEmbedderOrigin
          )
          .accessibilityLabel(Text(node.name))
        } else {
          GridEmbedPoster(node: node, provider: player.provider, label: messages.play) { tapped = true }
            .modifier(GridEmbedVisibility(appeared: $appeared))
        }
      #else
        GridEmbedCard(node: node, provider: player.provider, messages: messages)
      #endif
    } else if let href = GridURL.safeHref(node.url), let url = URL(string: href) {
      GridLinkButton(url: url) { Text(node.name).underline() }
        .font(.system(size: 12, weight: .medium))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    } else {
      GridPlaceholder(text: (node.url?.isEmpty == false ? node.url : nil) ?? node.name)
    }
  }
}

/// Latch the first visible pixel so scrolling away keeps the player and its position.
@available(iOS 16, macOS 13, tvOS 16, *)
private struct GridEmbedVisibility: ViewModifier {
  @Binding var appeared: Bool

  func body(content: Content) -> some View {
    if #available(iOS 18, macOS 15, tvOS 18, visionOS 2, *) {
      content.onScrollVisibilityChange(threshold: 0.001) { visible in
        if visible { appeared = true }
      }
    } else {
      content.onAppear { appeared = true }
    }
  }
}

/// Local poster with a play button, the node name and the provider; makes no network request.
@available(iOS 16, macOS 13, tvOS 16, *)
struct GridEmbedPoster: View {
  let node: GridBuiltinNode
  let provider: GridEmbedPlayer.Provider
  let label: String
  let onPlay: () -> Void

  var body: some View {
    Button(action: onPlay) {
      VStack(spacing: 8) {
        Image(systemName: "play.circle.fill").font(.system(size: 44))
        Text(node.name).font(.system(size: 13, weight: .semibold)).lineLimit(2)
        Text(provider.rawValue).font(.system(size: 12, weight: .medium)).opacity(0.7)
      }
      .multilineTextAlignment(.center)
      .padding(8)
      .frame(maxWidth: .infinity, maxHeight: .infinity)
      .background(Color.primary.opacity(0.12))
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(Text("\(label) \(node.name)"))
    .accessibilityValue(Text(provider.rawValue))
    .accessibilityAddTraits(.isButton)
  }
}

/// tvOS: no web view, so the card opens the video on the provider through `openURL`.
@available(iOS 16, macOS 13, tvOS 16, *)
struct GridEmbedCard: View {
  let node: GridBuiltinNode
  let provider: GridEmbedPlayer.Provider
  let messages: GridMessages

  var body: some View {
    if let embed = GridEmbed(node.url), let url = URL(string: embed.pageURL) {
      GridLinkButton(url: url) {
        VStack(spacing: 8) {
          Image(systemName: "play.rectangle.fill").font(.system(size: 28))
          Text(node.name).font(.system(size: 13, weight: .semibold)).lineLimit(2)
          Text(String(format: messages.openEmbed, provider.rawValue)).font(.system(size: 12, weight: .medium)).opacity(0.7)
        }
        .multilineTextAlignment(.center)
        .padding(8)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.primary.opacity(0.06))
        .contentShape(Rectangle())
      }
      .accessibilityLabel(Text(node.name))
      .accessibilityHint(Text(String(format: messages.openEmbed, provider.rawValue)))
    }
  }
}

#if canImport(WebKit) && !os(tvOS)
  /// The player in a `WKWebView`: JavaScript on (the players need it), no script message handlers or
  /// user scripts, no file access (the page is a string with an https base URL), a non-persistent
  /// website data store, no windows opened by script, inline playback, and every top-level
  /// navigation or new window (a link in the player) handed to `openURL` instead of replacing the player.
  @available(iOS 16, macOS 13, *)
  @MainActor
  struct GridEmbedWebView {
    let player: GridEmbedPlayer.Player
    let title: String
    let autoplay: Bool
    let origin: URL

    @MainActor
    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate {
      var openURL: OpenURLAction?
      var isInitialLoad = true

      func webView(
        _ webView: WKWebView, decidePolicyFor action: WKNavigationAction,
        decisionHandler: @escaping @MainActor @Sendable (WKNavigationActionPolicy) -> Void
      ) {
        let decision = GridEmbedPlayer.navigation(
          url: action.request.url, targetsMainFrame: action.targetFrame?.isMainFrame == true,
          opensNewWindow: action.targetFrame == nil, isInitialLoad: isInitialLoad)
        switch decision {
        case .allow:
          if action.targetFrame?.isMainFrame == true { isInitialLoad = false }
          decisionHandler(.allow)
        case .open(let url):
          decisionHandler(.cancel)
          openURL?(url)
        case .cancel:
          decisionHandler(.cancel)
        }
      }

      /// `window.open` from the player (the YouTube logo) asks for a new window without consulting the
      /// navigation policy first: hand its URL to `openURL` and never create the window.
      func webView(
        _ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
        for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures
      ) -> WKWebView? {
        if case .open(let url) = GridEmbedPlayer.navigation(
          url: navigationAction.request.url, targetsMainFrame: false, opensNewWindow: true, isInitialLoad: false)
        {
          openURL?(url)
        }
        return nil
      }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeWebView(_ coordinator: Coordinator) -> WKWebView {
      let configuration = WKWebViewConfiguration()
      configuration.websiteDataStore = .nonPersistent()
      configuration.preferences.javaScriptCanOpenWindowsAutomatically = false
      configuration.defaultWebpagePreferences.allowsContentJavaScript = true
      // The tap that created the player counts as the viewer's gesture; otherwise playback waits
      // for the player's own play button.
      configuration.mediaTypesRequiringUserActionForPlayback = autoplay ? [] : .all
      #if os(iOS) || os(visionOS)
        configuration.allowsInlineMediaPlayback = true
      #endif
      let webView = WKWebView(frame: .zero, configuration: configuration)
      webView.navigationDelegate = coordinator
      webView.uiDelegate = coordinator
      webView.allowsLinkPreview = false
      #if os(iOS) || os(visionOS)
        webView.isOpaque = false
        webView.backgroundColor = .black
        webView.scrollView.isScrollEnabled = false
        webView.scrollView.bounces = false
        webView.scrollView.contentInsetAdjustmentBehavior = .never
      #endif
      webView.loadHTMLString(GridEmbedPlayer.html(player, title: title, autoplay: autoplay), baseURL: origin)
      return webView
    }

    static func tearDown(_ webView: WKWebView) {
      webView.stopLoading()
      webView.pauseAllMediaPlayback(completionHandler: nil)
      webView.navigationDelegate = nil
      webView.uiDelegate = nil
    }
  }

  #if os(macOS)
    @available(macOS 13, *)
    extension GridEmbedWebView: NSViewRepresentable {
      func makeNSView(context: Context) -> WKWebView {
        context.coordinator.openURL = context.environment.openURL
        return makeWebView(context.coordinator)
      }

      func updateNSView(_ webView: WKWebView, context: Context) {
        context.coordinator.openURL = context.environment.openURL
        if context.environment.scenePhase != .active { webView.pauseAllMediaPlayback(completionHandler: nil) }
      }

      static func dismantleNSView(_ webView: WKWebView, coordinator: Coordinator) { tearDown(webView) }
    }
  #else
    @available(iOS 16, *)
    extension GridEmbedWebView: UIViewRepresentable {
      func makeUIView(context: Context) -> WKWebView {
        context.coordinator.openURL = context.environment.openURL
        return makeWebView(context.coordinator)
      }

      func updateUIView(_ webView: WKWebView, context: Context) {
        context.coordinator.openURL = context.environment.openURL
        if context.environment.scenePhase != .active { webView.pauseAllMediaPlayback(completionHandler: nil) }
      }

      static func dismantleUIView(_ webView: WKWebView, coordinator: Coordinator) { tearDown(webView) }
    }
  #endif
#endif
