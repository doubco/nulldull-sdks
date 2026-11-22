# Changelog

All NullDull SDKs share one version. This project follows [Semantic Versioning](https://semver.org); `0.x` releases may contain breaking changes in minor versions.

## Unreleased

- Swift: `GridView` and `PublishedGridPageView` without `width:` now follow the width their container proposes when it narrows as well as when it widens. Before, the measured width could only grow, so a container narrower than 390 pt clipped the canvas, rotating back to portrait kept the landscape width, and a macOS window could not be narrowed below the last Grid width. An explicit `width:` behaves as before.
- Kotlin (`nulldull-grid-compose`): the built-in YouTube embed plays again instead of showing "Error 153". The player is now framed in a local page whose origin is the app's application ID (`https://<application id>/`), so YouTube receives the `Referer` it requires from embedders; Vimeo embeds get the same page. Embeds now show a local poster and make no request to YouTube or Vimeo until the viewer taps it; the tap loads the player and starts the video. Links tapped in the player go to `onOpenUrl`.

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
