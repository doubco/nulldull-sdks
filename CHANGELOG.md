# Changelog

All NullDull SDKs share one version. This project follows [Semantic Versioning](https://semver.org); `0.x` releases may contain breaking changes in minor versions.

## Unreleased

- Swift: `GridView` and `PublishedGridPageView` without `width:` now follow the width their container proposes when it narrows as well as when it widens. Before, the measured width could only grow, so a container narrower than 390 pt clipped the canvas, rotating back to portrait kept the landscape width, and a macOS window could not be narrowed below the last Grid width. An explicit `width:` behaves as before.
- Swift (`NullDullGridUI`): YouTube and Vimeo embeds now play inline in a `WKWebView` on iOS, macOS and visionOS, instead of a card that opened the video in another app. **The default changes:** the player loads as soon as the embed appears, so YouTube or Vimeo is contacted when the page is shown, without a tap; the video does not autoplay. The new `embedLoading:` parameter of `GridView` and `PublishedGridPageView` (`GridEmbedLoading.immediate`, the default, or `.tap`) can instead show a local poster that makes no request to YouTube or Vimeo until the viewer taps it; the tap loads the player and starts the video. The player is framed in a local page whose origin is the app's bundle identifier (`https://<bundle identifier>/`, lowercased), so YouTube receives the `Referer` it requires from embedders. Links tapped in the player go through `openURL`. `embed:` still replaces the built-in player in both modes. tvOS has no web view and keeps the card that opens the video. `GridMessages` gains `play` (the poster's accessibility label prefix). Existing call sites compile unchanged.
- Kotlin (`nulldull-grid-compose`): the built-in YouTube embed plays again instead of showing "Error 153". The player is now framed in a local page whose origin is the app's application ID (`https://<application id>/`), so YouTube receives the `Referer` it requires from embedders; Vimeo embeds get the same page. Embeds play inline and, by default, the player loads as soon as the embed is composed, so YouTube or Vimeo is contacted when the embed is shown; the video does not autoplay. The new `embedLoading` parameter of `GridRenderer` and `PublishedGridPage` (`GridEmbedLoading.Immediate`, the default, or `GridEmbedLoading.Tap`) can instead show a local poster that makes no request to YouTube or Vimeo until the viewer taps it; the tap loads the player and starts the video. `renderEmbed` still replaces the built-in player in both modes. Links tapped in the player go to `onOpenUrl`. Existing call sites compile unchanged; code compiled against 0.1.0 must be recompiled, because the composables gained a parameter.

## 0.2.0 (20 November 2026)

Grid renderers, in alpha. The SDK packages are unchanged.

- Swift: two new products in the root `Package.swift`. `NullDullGrid` has the Grid document model and validation, the layout engine, a public content client and static SVG support (Foundation only). `NullDullGridUI` is a SwiftUI renderer for iOS 16, macOS 13, tvOS 16 and visionOS 1. The package's platform minimums and the `NullDull` product are unchanged; the Grid products need Xcode 16 or later.
- Kotlin: `com.nulldull:nulldull-grid-core:0.1.0` (JVM: model, validation, layout engine, Markdown model, content client) and `com.nulldull:nulldull-grid-compose:0.1.0` (Jetpack Compose renderer, Android minSdk 24). They are versioned separately from `nulldull-sdk`.
- `fixtures/grid-renderer/`: fixture documents, golden layout geometry, validation cases, URL and SVG rules, delivery samples and the icon catalog, generated from the TypeScript Grid packages and read by both renderers' tests.
- CI: `swift-grid` and `kotlin-grid` jobs.

## 0.1.0 (20 November 2026, early access)

- `SPEC.md`: the language-neutral contract for workspace API key SDKs. It covers Grid delivery, read-only Memory and Locale export, and defines errors, retries, pagination and conformance.
- `fixtures/`: shared conformance cases (`manifest.json`) and response fixtures taken from the API handlers.
- `node/`: `@nulldull/sdk`, the reference Node.js and TypeScript SDK (ESM and CJS, zero runtime dependencies, Node 18+ and browsers).
