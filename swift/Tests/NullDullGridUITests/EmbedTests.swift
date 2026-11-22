import Foundation
import SwiftUI
import XCTest

@testable import NullDullGrid
@testable import NullDullGridUI

/// URL, frame page, embedder identity, loading modes and navigation policy of the built-in
/// YouTube and Vimeo player (no web view needed).
final class EmbedTests: XCTestCase {
  func testResolvesProvidersLikeGridEmbedUrl() throws {
    let youtube = try XCTUnwrap(GridEmbedPlayer.resolve("https://youtu.be/dQw4w9WgXcQ"))
    XCTAssertEqual(youtube.provider, .youtube)
    XCTAssertEqual(youtube.provider.rawValue, "YouTube")
    XCTAssertEqual(youtube.src, "https://www.youtube-nocookie.com/embed/dQw4w9WgXcQ")

    let vimeo = try XCTUnwrap(GridEmbedPlayer.resolve("https://vimeo.com/76979871"))
    XCTAssertEqual(vimeo.provider, .vimeo)
    XCTAssertEqual(vimeo.src, "https://player.vimeo.com/video/76979871")

    XCTAssertNil(GridEmbedPlayer.resolve("https://example.com/watch?v=dQw4w9WgXcQ"))
    XCTAssertNil(GridEmbedPlayer.resolve("javascript:alert(1)"))
    XCTAssertNil(GridEmbedPlayer.resolve(nil))
  }

  func testPlayerURLAutoplaysOnlyInTapMode() throws {
    let youtube = try XCTUnwrap(GridEmbedPlayer.resolve("https://www.youtube.com/watch?v=dQw4w9WgXcQ"))
    XCTAssertFalse(GridEmbedPlayer.autoplay(.immediate))
    XCTAssertTrue(GridEmbedPlayer.autoplay(.tap))
    XCTAssertEqual(
      youtube.frameSrc(autoplay: GridEmbedPlayer.autoplay(.immediate)),
      "https://www.youtube-nocookie.com/embed/dQw4w9WgXcQ?playsinline=1")
    XCTAssertEqual(
      youtube.frameSrc(autoplay: GridEmbedPlayer.autoplay(.tap)),
      "https://www.youtube-nocookie.com/embed/dQw4w9WgXcQ?playsinline=1&autoplay=1")
    let vimeo = try XCTUnwrap(GridEmbedPlayer.resolve("https://vimeo.com/76979871"))
    XCTAssertEqual(vimeo.frameSrc(autoplay: true), "https://player.vimeo.com/video/76979871?playsinline=1&autoplay=1")
    XCTAssertEqual(
      GridEmbedPlayer.Player(provider: .vimeo, src: "https://player.vimeo.com/video/1?h=x").frameSrc(autoplay: false),
      "https://player.vimeo.com/video/1?h=x&playsinline=1")
  }

  func testLoadingModeDecidesWhenThePlayerExists() {
    // Immediate: as soon as the embed appears, no tap needed.
    XCTAssertFalse(GridEmbedPlayer.showsPlayer(.immediate, appeared: false, tapped: false))
    XCTAssertTrue(GridEmbedPlayer.showsPlayer(.immediate, appeared: true, tapped: false))
    // Tap: only after the tap, however long the poster has been visible.
    XCTAssertFalse(GridEmbedPlayer.showsPlayer(.tap, appeared: false, tapped: false))
    XCTAssertFalse(GridEmbedPlayer.showsPlayer(.tap, appeared: true, tapped: false))
    XCTAssertTrue(GridEmbedPlayer.showsPlayer(.tap, appeared: true, tapped: true))
  }

  /// Existing call sites compile unchanged and get the immediate default; `embedLoading:` opts into tap.
  @MainActor
  func testGridViewDefaultsToImmediateLoading() throws {
    guard #available(iOS 16, macOS 13, tvOS 16, *) else { throw XCTSkip("needs SwiftUI Layout") }
    let document = try GridDocument(
      json: Data(contentsOf: RenderTests.fixtures.appendingPathComponent("documents/kitchen-sink.json")))
    XCTAssertEqual(GridView(document: document).embedLoading, .immediate)
    XCTAssertEqual(GridView(document: document, embedLoading: .tap).embedLoading, .tap)
  }

  func testEmbedderIdentityIsTheBundleIdentifier() {
    XCTAssertEqual(GridEmbedPlayer.embedderOrigin(bundleIdentifier: "com.example.app").absoluteString, "https://com.example.app/")
    XCTAssertEqual(
      GridEmbedPlayer.embedderOrigin(bundleIdentifier: "com.Example.GridTest-Local").absoluteString,
      "https://com.example.gridtest-local/")
    // Characters a host cannot hold are replaced; without a bundle identifier the process name stands in.
    XCTAssertEqual(GridEmbedPlayer.embedderOrigin(bundleIdentifier: "com.example.my_app").absoluteString, "https://com.example.my-app/")
    XCTAssertEqual(GridEmbedPlayer.embedderOrigin(bundleIdentifier: nil, processName: "MyTool").absoluteString, "https://mytool/")
    XCTAssertEqual(GridEmbedPlayer.embedderOrigin(bundleIdentifier: "", processName: "__").absoluteString, "https://app/")
  }

  func testFramePageHoldsOnlyTheSandboxedPlayer() throws {
    let player = try XCTUnwrap(GridEmbedPlayer.resolve("https://www.youtube.com/watch?v=dQw4w9WgXcQ"))
    let html = GridEmbedPlayer.html(player, title: "Say \"hi\" <script>alert(1)</script> & 'bye'", autoplay: true)
    XCTAssertTrue(html.contains("src=\"https://www.youtube-nocookie.com/embed/dQw4w9WgXcQ?playsinline=1&amp;autoplay=1\""), html)
    XCTAssertTrue(
      html.contains("title=\"Say &quot;hi&quot; &lt;script&gt;alert(1)&lt;/script&gt; &amp; &#39;bye&#39;\""), html)
    XCTAssertTrue(
      html.contains(
        "sandbox=\"allow-scripts allow-same-origin allow-presentation allow-popups allow-top-navigation-by-user-activation\""),
      html)
    XCTAssertTrue(html.contains("allow=\"autoplay; encrypted-media; fullscreen; picture-in-picture\""), html)
    XCTAssertTrue(html.contains("referrerpolicy=\"strict-origin-when-cross-origin\""), html)
    XCTAssertFalse(html.contains("<script"), html)
    // Nothing may be fetched from the identity origin (it is not a server the app controls).
    XCTAssertTrue(html.contains("<link rel=\"icon\" href=\"data:,\">"), html)
    // The player fills the page, which fills the web view.
    XCTAssertTrue(html.contains("html,body{margin:0;padding:0;width:100%;height:100%"), html)
    XCTAssertTrue(html.contains("iframe{display:block;border:0;width:100%;height:100%}"), html)
    XCTAssertEqual(html.components(separatedBy: "<iframe").count - 1, 1)
    XCTAssertFalse(GridEmbedPlayer.html(player, title: "x", autoplay: false).contains("autoplay=1"))
  }

  /// A quote, apostrophe, `&`, `<` or `>` followed by a combining mark is one `Character` but two
  /// code points for the HTML tokenizer; every one of them must still be escaped, or a node name
  /// could close the `title` attribute and add an event handler to the frame page.
  func testTitleEscapingCannotBeBypassedWithCombiningMarks() throws {
    let player = try XCTUnwrap(GridEmbedPlayer.resolve("https://www.youtube.com/watch?v=dQw4w9WgXcQ"))
    let mark = "\u{301}"
    let title = "x\"\(mark) onload=location=`https://evil.example/` y='\(mark)&\(mark)<\(mark)>\(mark)"
    let html = GridEmbedPlayer.html(player, title: title, autoplay: false)
    let start = try XCTUnwrap(html.range(of: " title=\""))
    let end = try XCTUnwrap(html.range(of: "\" sandbox=", range: start.upperBound..<html.endIndex))
    let value = html.unicodeScalars[start.upperBound..<end.lowerBound]
    for forbidden in ["\"", "'", "<", ">"] as [Unicode.Scalar] {
      XCTAssertFalse(value.contains(forbidden), "raw \(forbidden) in title: \(String(value))")
    }
    XCTAssertEqual(
      String(value),
      "x&quot;\(mark) onload=location=`https://evil.example/` y=&#39;\(mark)&amp;\(mark)&lt;\(mark)&gt;\(mark)")
    XCTAssertEqual(GridEmbedPlayer.escape("e\u{301}\u{1F600}"), "e\u{301}\u{1F600}")
  }

  func testNavigationLeavesThePlayerThroughOpenURL() {
    let identity = URL(string: "https://com.example.app/")!
    let watch = URL(string: "https://www.youtube.com/watch?v=dQw4w9WgXcQ")!
    // The frame page itself loads once.
    XCTAssertEqual(
      GridEmbedPlayer.navigation(url: identity, targetsMainFrame: true, opensNewWindow: false, isInitialLoad: true), .allow)
    // The player's own frames load normally.
    XCTAssertEqual(
      GridEmbedPlayer.navigation(
        url: URL(string: "https://www.youtube-nocookie.com/embed/x"), targetsMainFrame: false, opensNewWindow: false,
        isInitialLoad: false), .allow)
    // Later top-level navigations and new windows (the YouTube logo, the title) go to openURL.
    XCTAssertEqual(
      GridEmbedPlayer.navigation(url: watch, targetsMainFrame: true, opensNewWindow: false, isInitialLoad: false), .open(watch))
    XCTAssertEqual(
      GridEmbedPlayer.navigation(url: watch, targetsMainFrame: false, opensNewWindow: true, isInitialLoad: false), .open(watch))
    XCTAssertEqual(
      GridEmbedPlayer.navigation(url: identity, targetsMainFrame: true, opensNewWindow: false, isInitialLoad: false),
      .open(identity))
    // Unsafe schemes are dropped.
    for bad in ["javascript:alert(1)", "file:///etc/passwd", "myapp://x", "https://user:pw@example.com/"] {
      XCTAssertEqual(
        GridEmbedPlayer.navigation(url: URL(string: bad), targetsMainFrame: true, opensNewWindow: false, isInitialLoad: false),
        .cancel, bad)
    }
    XCTAssertEqual(GridEmbedPlayer.navigation(url: nil, targetsMainFrame: false, opensNewWindow: true, isInitialLoad: false), .cancel)
  }
}
