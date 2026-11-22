# NullDull Swift SDK

The Swift client for reading NullDull with **workspace API keys**:

- **Grid**: published pages, covers and assets for your app or website.
- **Memory**: read-only documents, folders, search, tags and assets.
- **Locale**: export translation catalogs (`.xcstrings`, `.strings`, JSON, Android XML, …) at build time.

> **Early access.** NullDull and this SDK are in early access. Version `0.1.0` may still change before `1.0`. The SDK only reads data; it never writes.

- Swift 5.9+ (builds cleanly in Swift 6 language mode with strict concurrency; every public type is `Sendable`)
- iOS 15, macOS 12, tvOS 15, watchOS 8, visionOS 1
- Foundation only, no dependencies
- `async`/`await`, with `AsyncThrowingStream` pagination

The contract every NullDull SDK follows is [`SPEC.md`](../SPEC.md).

## Install

Swift Package Manager, in `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/doubco/nulldull-sdks", from: "0.1.0"),
],
targets: [
    .target(name: "MyApp", dependencies: [
        .product(name: "NullDull", package: "nulldull-sdks"),
    ]),
]
```

In Xcode: **File → Add Package Dependencies…**, enter `https://github.com/doubco/nulldull-sdks`, choose version `0.1.0` (Up to Next Minor is safest while the API is `0.x`), and add the `NullDull` library to your target.

## Keys

Owners and admins create keys in the NullDull app under **Workspace settings → API keys**.

| Key | Use it | Scopes |
| --- | --- | --- |
| Public `nd_pub_…` | In app bundles and browsers | `grid:published` |
| Private `nd_sec_…` | On servers, in CI and in build tools only | `grid:published`, `memory:read`, `locale:read` |

**Never ship a private key in an app.** Memory and Locale calls also need your **workspace ID**: a key cannot look up its own workspace. Owners and admins can see it in the app.

## Quick start

### Grid

```swift
import NullDull

let nulldull = try NullDullClient(apiKey: "nd_pub_…")

// One page of results, newest first.
let list = try await nulldull.grid.listPages("my-blog", limit: 10)
for summary in list.items {
    print(summary.title, summary.publishedDate)
}

// A published page with its document and asset manifest.
let page = try await nulldull.grid.getPage("my-blog", slug: "hello-world", locale: "en")
print(page.document.nodes.count)          // The document is opaque JSON (see GridDocument).
let image = page.cover.map { URL(string: $0.url)! }   // Absolute, with key= for public keys.

// Download an asset's bytes.
if let cover = page.cover {
    let download = try await nulldull.grid.downloadAsset(cover)
    print(download.contentType ?? "", download.size)
}
```

`locale` defaults to `"en"` and is always sent. Cover and asset URLs come back absolute; for a **public** key on the API's own origin they include `key=`, so `AsyncImage`, fonts and media can load them without headers. A private key is never put into a URL, and no key is ever sent to another origin.

The Grid document is returned as-is. Read it through `page.document.json` (a `JSONValue`), or decode it into your own model with `try page.document.decode(MyDocument.self)`.

### Memory

```swift
let nulldull = try NullDullClient(apiKey: privateKey, workspaceID: "9f8e7d6c-…")

let scopes = try await nulldull.memory.listScopes()
let results = try await nulldull.memory.search("release checklist", tags: ["procedure"])

let unfiled = try await nulldull.memory.listDocuments(folderID: .root)   // only the location root
let inFolder = try await nulldull.memory.listDocuments(folderID: "7c9e6679-…")
let everything = try await nulldull.memory.listDocuments()                 // no folder filter

let document = try await nulldull.memory.getDocument(results.items[0].id)
print(document.content ?? "")

let preview = try await nulldull.memory.downloadAsset(assetID, width: 512)   // resized WebP
```

`folderID` (documents, assets) and `parentID` (folders) take a `FolderFilter`: `nil` means no filter, `.root` means the location root (sent as `root`), and a string literal is a folder ID.

### Locale

```swift
let nulldull = try NullDullClient(apiKey: privateKey, workspaceID: workspaceID)

let export = try await nulldull.locale.export(
    scopeID: workspaceID,          // the workspace root location has the workspace's ID
    format: .xcstrings,
    status: [.approved],
    basename: "Localizable"
)
try export.write(to: URL(fileURLWithPath: "Sources/MyApp/Resources"))
```

An export is always JSON holding text files, never an archive: one file set per language for single-language formats (`en.json`, `values-tr/strings.xml`), one file for `xcstrings`. `write(to:)` refuses absolute paths and `..` segments. `format` defaults to `.json`; `languages` and `status` are comma-joined on the wire. Use `listFormats()` for every format's capabilities.

## Pagination

Every list has a single-page method and a lazy iterator:

```swift
// One page; pass nextCursor back as `after`.
var page = try await nulldull.memory.listDocuments()
while let cursor = page.nextCursor {
    page = try await nulldull.memory.listDocuments(after: cursor)
}

// Or every item across pages. Pages are fetched only as you consume them.
for try await document in nulldull.memory.iterateDocuments(tags: ["rules"]) {
    print(document.name)
}
```

Iterators return `AsyncThrowingStream<Item, any Error>`. They follow `nextCursor` until it is `nil`, continue through empty pages that still have a cursor (Grid search can return those), start from `after` when given, and throw `INVALID_RESPONSE` if the API repeats a cursor. Breaking out of the loop stops fetching.

## Errors

Every failure is a `NullDullError`:

| Property | Meaning |
| --- | --- |
| `status` | HTTP status, or `0` for client-side errors |
| `code` | The API's code (`.notFound`, `.forbidden`, `.rateLimited`, …) or a client code |
| `message` | The API's message, or `NullDull request failed (<status> <code>).` |
| `detail` | For example `LOCALE_EXPORT_TOO_LARGE` |
| `requestID` | `X-Request-Id`, or else `CF-Ray`; include it when you report a problem |
| `retryAfter` | `Retry-After` in seconds, when the response had one |
| `body` | The whole JSON error body (`[String: JSONValue]`) |

```swift
do {
    let page = try await nulldull.grid.getPage("my-blog", slug: slug)
} catch let error as NullDullError {
    switch error.code {
    case .notFound: showUnpublished()
    case .rateLimited: retryLater(after: error.retryAfter)
    default: log(error.message, error.requestID ?? "")
    }
}
```

Client codes (`status` 0): `INVALID_ARGUMENT` (bad options or arguments, before any request), `WORKSPACE_REQUIRED`, `PRIVATE_KEY_REQUIRED`, `NETWORK_ERROR`, `TIMEOUT`, `ABORTED` (the task was cancelled) and `INVALID_RESPONSE`. A non-JSON error body, or a redirect, is `REQUEST_FAILED`.

## Retries, timeouts and cancellation

- `429`, `502`, `503`, `504` and network errors are retried up to `maxRetries` times (default 2), after 500 ms and then 1000 ms.
- A `Retry-After` of 30 seconds or less is waited for exactly. A longer one is thrown at once with `retryAfter` set, so you decide.
- Other statuses, timeouts and invalid responses are never retried.
- `timeout` (default 30 s, `0` disables it) applies to each attempt.
- Cancelling the calling task, including during a retry wait, throws `ABORTED`.
- Redirects are never followed, so the key cannot leak to another origin. Requests send no cookies and skip HTTP caches.

```swift
let nulldull = try NullDullClient(apiKey: key, timeout: 10, maxRetries: 0, userAgent: "my-app/2.0")
```

## Forward compatibility

Models expose typed, Swift-cased properties (`scopeID` for the wire name `scopeId`), and every model keeps the API's original object as `raw: JSONValue`, so fields added later are still reachable. Enum-like strings decode unknown values as `.unknown("value")` instead of failing, and encoding a model writes `raw` back unchanged.

## Testing your code

Pass any `NullDullTransport` to answer requests without the network:

```swift
struct StubTransport: NullDullTransport {
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let body = Data(#"{"items":[],"nextCursor":null}"#.utf8)
        return (body, HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
    }
}

let client = try NullDullClient(
    apiKey: "nd_sec_" + String(repeating: "0", count: 64),
    workspaceID: "ws",
    transport: StubTransport(),
    sleep: { _ in }   // skip retry waits
)
```

You can also pass your own `URLSession` with `session:`; redirects are still refused.

## Grid renderer (alpha)

The same package also has two products that render Grid documents natively. They are separate from the `NullDull` SDK product and do not depend on it.

> **Alpha.** The Grid renderer products are in early access and their API may change in any `0.x` release. They were released in tag `0.2.0` on 20 November 2026.

| Product | Contents | Frameworks | Platforms |
| --- | --- | --- | --- |
| `NullDullGrid` | Document model and validation, layout engine, public content client, static SVG support | Foundation | Same as `NullDull` |
| `NullDullGridUI` | SwiftUI renderer | SwiftUI, AVKit, Core Text, WebKit (not on tvOS) | iOS 16, macOS 13, tvOS 16, visionOS 1; not watchOS |

Building the Grid products needs Xcode 16 or later (Swift 6 toolchain). The `NullDull` product still builds with Swift 5.9.

```swift
dependencies: [
    .package(url: "https://github.com/doubco/nulldull-sdks", from: "0.2.0"),
],
targets: [
    .target(name: "MyApp", dependencies: [
        .product(name: "NullDullGrid", package: "nulldull-sdks"),
        .product(name: "NullDullGridUI", package: "nulldull-sdks"),
    ]),
]
```

```swift
import NullDullGrid
import NullDullGridUI

let grid = try GridPublicClient(
    baseURL: URL(string: "https://nulldull.com/api/grid/v1")!,
    apiKey: "nd_pub_…"  // a public key with the grid:published scope
)

struct ArticleView: View {
    let grid: GridPublicClient
    @State private var page: PublicGridPage?

    var body: some View {
        ScrollView {
            if let page { PublishedGridPageView(page: page) }
        }
        .task { page = try? await grid.page(pool: "my-blog", slug: "hello-world") }
    }
}
```

For documents obtained elsewhere (for example from `NullDullClient.grid.getPage`), decode them with `GridDocument(json:)` and render them with `GridView(document:resolveAsset:)`. `GridView` picks the breakpoint from its width: without `width:` it takes the width its container proposes and follows it as it changes (rotation, window resizing), starting from `initialWidth` (390) until the first layout; pass `width:` when you already know it. `theme:`, `customNodes:` (a `GridCustomNodeRegistry`), `embed:`, `embedLoading:`, `messages:` and `label:` customize it.

- `NullDull` and `NullDullGrid` both declare `GridDocument` and `JSONValue`. In a file that imports both modules, qualify the name (`NullDullGrid.GridDocument`).
- The client follows the same key rules as the SDK: only public `nd_pub_` keys belong in apps (iOS, tvOS and visionOS reject `nd_sec_` keys), a key is added as `key=` only to asset URLs on the API's own origin, and redirects are refused.
- Links and assets must be credential-free `http`/`https` URLs. Markdown HTML is shown as text. Custom node properties are inert strings, and only views registered in `GridCustomNodeRegistry` run. Uploaded SVG files pass a static allowlist and are drawn natively; nothing in them is executed or fetched.
- VoiceOver labels, Dynamic Type for flowing text, and light and dark appearance are supported. Video and audio never autoplay.
- Restricted embeds (YouTube on `youtube-nocookie.com`, and Vimeo) play inline in a `WKWebView`. `embedLoading:` on `GridView` and `PublishedGridPageView` chooses when the player loads:
  - `.immediate` (the default): the player loads as soon as the embed appears, without a tap, so the app contacts YouTube or Vimeo when the page is shown. `GridView` lays out every node of the page, so this includes embeds further down a long page that the viewer has not scrolled to yet. The video starts only when the viewer presses the player's play button.
  - `.tap`: a local poster with the node name, the provider and a play button is shown first, and no request is made to YouTube or Vimeo until the viewer taps it. The tap loads the player and starts the video.

  ```swift
  GridView(document: document, resolveAsset: resolve, embedLoading: .tap)
  ```

  The web view runs JavaScript for the player only, with no script message handlers, file access or persistent website data, and plays inline. Links that leave the player (the title, the YouTube logo) go through the environment's `openURL`, so you can intercept them. YouTube requires embedders to identify themselves with an HTTP `Referer` (without one it shows "Error 153"), so the player is framed in a local page whose origin is your app's bundle identifier, lowercased, for example `https://com.example.app/`, as [YouTube documents for apps](https://developers.google.com/youtube/terms/required-minimum-functionality#embedded-player-api-client-identity). YouTube and Vimeo therefore receive your bundle identifier. You need no setup for this. Pass `embed:` to replace the built-in player entirely, for example to wait for consent; `embedLoading:` is then ignored.
- tvOS has no web view, so there an embed shows a card that opens the video on YouTube or Vimeo through `openURL` (label: `GridMessages.openEmbed`), in both loading modes.

Known differences from the web renderer: groove and ridge borders draw solid; Markdown footnotes show as literal text; `justify` alignment renders left-aligned; code blocks are clipped instead of scrolling; `cover` video plays as `contain`; SVG gradients, clip paths, masks and percentage lengths show a "Preview unavailable" fallback.

The layout engine is tested against golden geometry generated from the TypeScript renderer, in [`fixtures/grid-renderer`](../fixtures/grid-renderer) (shared with the Kotlin renderer).

## Development

Swift Package Manager resolves the package from the repository root, so run everything there:

```sh
swift build
swift test                                  # all products
swift test --filter NullDullTests           # the SDK only
swift test --filter 'NullDullGridTests|NullDullGridUITests'   # the Grid renderer only
xcodebuild -scheme NullDull -destination 'generic/platform=iOS Simulator' build
xcodebuild -scheme NullDullGridUI -destination 'generic/platform=iOS Simulator' build
```

Grid render review images: `GRID_RENDER_OUTPUT=/tmp/shots swift test --filter testWritesReviewImagesWhenRequested`.

The unit tests run every case in the shared [`fixtures/manifest.json`](../fixtures/manifest.json) and the SPEC conformance list against a mock transport. The fixtures are read in place, not copied.

Optional live tests are skipped unless these are set (key values are never printed):

| Variable | Used for |
| --- | --- |
| `NULLDULL_PUBLIC_KEY` and `NULLDULL_GRID_POOL` | Grid list, iterate, get page, download and errors |
| `NULLDULL_PRIVATE_KEY` and `NULLDULL_WORKSPACE_ID` | Memory scopes, documents, search and tags; Locale formats and export |
| `NULLDULL_LOCALE_SCOPE_ID` (optional) | Locale export location (default: the workspace root) |
| `NULLDULL_BASE_URL` (optional) | Point at staging or a local API |

```sh
NULLDULL_PUBLIC_KEY=nd_pub_… NULLDULL_GRID_POOL=my-blog swift test --filter Live
```

## License

[MIT](../LICENSE) © 2026 NullDull
