# Changelog

All NullDull SDKs share one version, the repository's release tag; the Kotlin Grid renderer artifacts have their own version, given in each entry. This project follows [Semantic Versioning](https://semver.org); `0.x` releases may contain breaking changes in minor versions.

## Unreleased

- Swift pauses embedded media when the scene loses activity. Android releases the embedded player when its lifecycle stops and reloads without autoplay on return.

- Swift hosts can map GridTheme.fontNames to registered PostScript names for built-in families. Uploaded fonts have priority.

- Swift Grid reads expose GridNetworkError with the underlying URL error code. Cancellation continues to throw CancellationError.

- Regenerated geometry for the current editorial snapshots at eight widths, the legacy delivery sample and the native icon catalog. The suite now covers 52 editorial pages and 16 other documents.

### Paused public requests (all SDKs and both Grid content clients)

When a workspace on the Free plan has used its monthly public requests, Grid delivery answers `429 RATE_LIMITED` with `reason` and `detail` `PUBLIC_REQUESTS_PAUSED`, a `renewsAt` time (the start of the next UTC month) and a `Retry-After` until then ([SPEC.md 5.4](SPEC.md#54-paused-public-requests-public_requests_paused)). The errors now carry that information, so an app can show a calm notice instead of a generic error. No breaking changes: existing fields, constructors and error handling are unchanged.

- New error fields `reason` and `renewsAt` (the ISO 8601 string as sent), read from the body: Node and React `NullDullError.reason`/`renewsAt`; Python `NullDullError.reason`/`renews_at`; Go `Error.Reason`/`RenewsAt`; Swift `NullDullError.reason`/`renewsAt`; Kotlin `NullDullException.reason`/`renewsAt`.
- A paused check, true for a `429` with that reason: Node `error.publicRequestsPaused`, `isPublicRequestsPaused(error)` and `PUBLIC_REQUESTS_PAUSED`; Python `public_requests_paused`, `is_public_requests_paused(error)` and `PUBLIC_REQUESTS_PAUSED`; Go `PublicRequestsPaused()`, `IsPublicRequestsPaused(err)` (works through wrapping) and `ReasonPublicRequestsPaused`; Swift `isPublicRequestsPaused` and `NullDullError.publicRequestsPausedReason`; Kotlin `isPublicRequestsPaused` and `NullDullException.PUBLIC_REQUESTS_PAUSED`.
- This error is never retried, even if a proxy dropped its `Retry-After`. Before, its long `Retry-After` already stopped retries; a paused `429` without one would have been retried twice.
- Grid content clients: Swift `GridPublicError` (`NullDullGrid`) and Kotlin `GridPublicException` (`nulldull-grid-core`) gain `detail`, `reason`, `renewsAt`, `retryAfter` (seconds, from delta-seconds or an HTTP date) and `isPublicRequestsPaused`. Their existing `(status, code)` initializer and constructor remain; Swift equality still compares `status` and `code` only. The clients still never retry. `GridView`, `PublishedGridPageView`, `GridRenderer` and `PublishedGridPage` only draw loaded pages and show no load errors, so the host app shows the notice.
- `fixtures/`: new conformance case `grid.listPages.publicRequestsPaused` and body `errors/public-requests-paused.json`.

### Swift (`NullDullGridUI`)

- Fixed: a horizontal Grid whose canvas width lies between two view widths (portrait and landscape, or a resized macOS or iPad window) rebuilt every node view each time the width crossed the canvas width, because the canvas moved in and out of its horizontal `ScrollView`. A tapped embed went back to its poster and its web view was torn down, and custom nodes lost their state. A document with a horizontal layout (base, breakpoint or `layout:`) is now always shown in the scroll view, which scrolls, bounces and shows indicators only while the canvas is wider than the view. Vertical and flow documents still render as a plain canvas. Because `ImageRenderer` cannot draw a `ScrollView`, it now renders horizontal documents blank even when they fit; before, only overflowing ones.

## 0.3.0 (22 November 2026)

Grid renderers, still alpha: Swift tag `0.3.0` (`NullDullGrid`, `NullDullGridUI`) and Kotlin `com.nulldull:nulldull-grid-core:0.2.0` and `com.nulldull:nulldull-grid-compose:0.2.0`. The SDK packages are unchanged: `@nulldull/sdk`, `@nulldull/react`, `nulldull` (Python), the Go module and `com.nulldull:nulldull-sdk` are not re-released, and the Swift `NullDull` product in tag `0.3.0` is the same code as in `0.1.0` (it still reports version `0.1.0`).

### Behavior changes to know before upgrading

- **YouTube and Vimeo embeds load immediately by default** (Swift and Kotlin). The built-in player is created as soon as the embed is shown, without a tap, so your app contacts YouTube or Vimeo when the page is displayed, including embeds further down the page that the viewer has not scrolled to. The video still does not autoplay. To make no request to the provider until the viewer taps a local poster, pass `embedLoading: .tap` (Swift) or `embedLoading = GridEmbedLoading.Tap` (Kotlin); the tap then loads the player and starts the video. To wait for consent, keep replacing the player with `embed:` (Swift) or `renderEmbed` (Kotlin), which take precedence in both modes.
- **Embeds send a `Referer` naming your app.** YouTube requires embedders to identify themselves and shows "Error 153" without it, so the player is framed in a local page whose origin is your app's identity, lowercased: `https://<bundle identifier>/` on Apple platforms and `https://<application id>/` on Android. YouTube and Vimeo therefore receive your bundle identifier or application ID. Nothing is fetched from that origin, and you need no setup.
- **Swift: `GridView` no longer keeps a 390 pt minimum width.** Without `width:`, `GridView` and `PublishedGridPageView` now follow the width their container proposes when it narrows as well as when it widens. Before, the measured width could only grow: a container narrower than 390 pt clipped the canvas, rotating back to portrait kept the landscape width, and a macOS window could not be narrowed below the last Grid width. `initialWidth` (390) is still used until the first layout, and an explicit `width:` behaves as before.
- **Kotlin: recompile against `nulldull-grid-compose` 0.2.0.** `GridRenderer` and `PublishedGridPage` gained a parameter, so code compiled against 0.1.0 is not binary compatible. Existing call sites compile unchanged, including a trailing `onOpenUrl` lambda.

### Swift (`NullDullGridUI`)

- YouTube and Vimeo embeds play inline in a `WKWebView` on iOS, macOS and visionOS, instead of a card that opened the video in another app. The web view has JavaScript for the player only, no script message handlers, no file access and a non-persistent website data store; links tapped in the player go through the environment's `openURL`. tvOS has no web view and keeps the card that opens the video, in both loading modes.
- New: `GridEmbedLoading` (`.immediate`, the default, and `.tap`) and the `embedLoading:` parameter of `GridView` and `PublishedGridPageView`. `GridMessages` gains `play` (the poster's accessibility label prefix). Existing call sites compile unchanged.
- `NullDullGridUI` now links WebKit on iOS, macOS and visionOS.

### Kotlin (`nulldull-grid-compose`, `nulldull-grid-core`)

- The built-in YouTube player plays again instead of showing "Error 153", and Vimeo uses the same framed page. Embeds play inline in a WebView with no JavaScript bridge, no file or content access and no third-party cookies; links tapped in the player go to `onOpenUrl`.
- New: `GridEmbedLoading` (`Immediate`, the default, and `Tap`) and the `embedLoading` parameter of `GridRenderer` and `PublishedGridPage`.
- Fixed: if the WebView renderer crashed or was reclaimed by the system, the app showing the page was killed. The embed is now removed instead.
- Fixed: in tap mode, rotating the device (or any other activity recreation) put a playing embed back to its poster, so the viewer had to tap again. The tap is now saved with the embed's URL and name: after recreation the player loads again and starts from the beginning, because the WebView is new and the playback position is not kept. When the document changes an embed's URL or name, the old player and tap are discarded in both modes, as in the Swift renderer (before, Kotlin ignored a name change).
- Fixed (`nulldull-grid-core`): `GridUrl.embed` accepts only ASCII YouTube IDs and Vimeo numbers, as the TypeScript and Swift rules do. On Android, non-ASCII letters or digits could pass.
- `nulldull-grid-core` has no API changes; it is released at `0.2.0` because both Grid artifacts share one version.

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
