# NullDull Kotlin SDK

The official NullDull SDK for Kotlin and Android. It reads NullDull with **workspace API keys**:

- **Grid**: published pages, covers and assets.
- **Memory**: read-only access to documents, folders, search, tags and assets.
- **Locale**: export translation catalogs at build time.

> **Early access.** `0.1.0` may change before `1.0`. The SDK only reads data.

Kotlin/JVM library with `suspend` functions and `Flow` pagination. Java 11 bytecode, usable from Android (minSdk 24) and any JVM 11+. Dependencies: OkHttp 4, kotlinx.serialization JSON and kotlinx.coroutines.

Documentation: <https://nulldull.com/docs> · Specification: [`SPEC.md`](https://github.com/doubco/nulldull-sdks/blob/main/SPEC.md)

## Install

```kotlin
// build.gradle.kts
dependencies {
    implementation("com.nulldull:nulldull-sdk:0.1.0")
}
```

Android apps need the `INTERNET` permission.

## Keys

Create keys in the NullDull app under **Workspace settings → API keys** (owners and admins).

| Key | Where | Scopes |
| --- | --- | --- |
| Public `nd_pub_…` | Android and other app bundles | `grid:published` |
| Private `nd_sec_…` | Servers and CI only | `grid:published`, `memory:read`, `locale:read` |

Never ship a private key in an app. Memory and Locale also need your **workspace ID**, because a key cannot look up its own workspace. The workspace root location has the same ID.

## Quick start

```kotlin
import com.nulldull.sdk.NullDullClient

val nulldull = NullDullClient(
    apiKey = System.getenv("NULLDULL_PRIVATE_KEY"),      // or a public key for Grid only
    workspaceId = System.getenv("NULLDULL_WORKSPACE_ID"), // needed for memory and locale
)
```

Build one client per key and share it: it holds only configuration and is safe to use from many coroutines. Other options: `baseUrl` (default `https://nulldull.com`), `timeout` (per attempt, default 30 seconds), `maxRetries` (default 2), `httpClient` (your `OkHttpClient`, to share its connection pool or add interceptors) and `userAgent` (a suffix for the `User-Agent` header).

### Grid: published pages

```kotlin
val grid = NullDullClient(apiKey = BuildConfig.NULLDULL_PUBLIC_KEY).grid

// One page of results (newest first)
val list = grid.listPages("my-blog", locale = "en", limit = 20)
list.pool.name
list.items.forEach { println("${it.title} ${it.cover?.url}") }

// Every page, following cursors
grid.iteratePages("my-blog", q = "launch").collect { summary -> println(summary.slug) }

// One page with its document and asset manifest
val page = grid.getPage("my-blog", "hello-world")
page.document // opaque JsonElement: render it with the Grid renderer
page.assets   // id, version, url, filename, mediaType, byteSize, checksum
```

Returned `cover.url` and `assets[].url` are absolute. With a public key they already carry `key=…`, so image loaders (Coil, Glide), fonts and media players, which cannot send headers, can load them directly. To resolve a URL yourself, call `grid.assetUrl(url)`. It adds a public key only to URLs on the API's own origin, and never adds a private key.

```kotlin
val file = grid.downloadAsset(page.assets[0]) // bytes, contentType, filename, size
```

`downloadAsset` sends `Authorization` only to the API's own origin.

### Memory: read-only

```kotlin
val memory = nulldull.memory

val scopes = memory.listScopes()
memory.iterateDocuments(scopeId = "…", tags = listOf("rules")).collect { doc ->
    println("${doc.name} ${doc.labelKind}")
}
val doc = memory.getDocument("…")                  // doc.content is the saved Markdown
val hits = memory.search("release checklist", scopeId = "…")
val link = memory.resolveLink(doc.id, "docs/setup.md#install") // status "found", id, fragment

val topLevel = memory.listFolders(scopeId = "…", parentId = FolderFilter.Root)
val unfiled = memory.listDocuments(folderId = FolderFilter.Root)
val inFolder = memory.listDocuments(folderId = FolderFilter.id("…"))

val asset = memory.getAsset("…")
val original = memory.downloadAsset(asset.id)            // application/octet-stream
val thumb = memory.downloadAsset(asset.id, width = 256)  // resized WebP for images
```

Leaving a folder filter out (`null`) means "any folder". `FolderFilter.Root` sends `root`: top-level folders, or documents and assets that are not in a folder.

### Locale: export catalogs

```kotlin
val locale = nulldull.locale
val formats = locale.listFormats().items // json, world, world-cldr, xcstrings, apple-strings, android-xml

val exported = locale.export(
    scopeId = workspaceId,
    format = LocaleFormatId.ANDROID_XML,
    languages = listOf("en", "tr"),
    status = listOf(LocaleKeyStatus.APPROVED),
)
// exported.files: values/strings.xml, values-tr/strings.xml
exported.writeTo(File("app/src/main/res")) // rejects absolute paths and ".." segments
```

The export is always JSON with text `files` and is never an archive. Single-language formats give one file set per language. `xcstrings` gives one file holding every language. Exports are limited to 2,000 keys and 2 million characters.

## Responses

Every result is a typed view over the API's JSON. Typed properties cover the documented fields; `json` holds the object exactly as sent, so fields added by the API later are already there:

```kotlin
val page = grid.getPage("my-blog", "hello-world")
page.title
page.json["someNewField"]
```

Decoding never fails on unknown fields or unknown enum values. Enum-like values (`kind`, `status`, `labelKind`, …) are plain strings; constants are in `FileKind`, `FileLifecycle`, `LocaleFormatId` and `LocaleKeyStatus`.

## Pagination

Every `listX` method returns one page with `items` and `nextCursor`. Pass `nextCursor` back as `after`:

```kotlin
var after: String? = null
do {
    val page = memory.listDocuments(after = after)
    page.items.forEach(::println)
    after = page.nextCursor
} while (after != null)
```

Or let `iterateX` do it. It returns a cold `Flow` of items: nothing is requested until you collect, and you can stop early with `take` or `first`:

```kotlin
val firstTen = memory.iterateDocuments().take(10).toList()
```

Cursors are opaque. Grid search can return an empty page that still has a cursor; iteration keeps going until `nextCursor` is `null`.

## Errors

Every failure throws `NullDullException`:

```kotlin
try {
    grid.getPage("my-blog", "missing")
} catch (e: NullDullException) {
    e.status     // HTTP status, or 0 for client-side errors
    e.code       // "NOT_FOUND", "FORBIDDEN", "RATE_LIMITED", "INVALID_ARGUMENT", "TIMEOUT", …
    e.message    // human-readable
    e.detail     // e.g. "LOCALE_EXPORT_TOO_LARGE"
    e.requestId  // X-Request-Id or CF-Ray: quote it in support requests
    e.retryAfter // seconds, when the server sent Retry-After
    e.reason     // the body's reason, e.g. "PUBLIC_REQUESTS_PAUSED"
    e.renewsAt   // the body's renewsAt (ISO 8601 UTC), when present
    e.body       // the whole JSON error body (Locale errors add key, language, issues)
}
```

When a Free workspace has used its monthly public requests, Grid delivery answers `429 RATE_LIMITED` with `reason` `PUBLIC_REQUESTS_PAUSED` until the allowance renews at the start of the next UTC month (or shortly after an upgrade). `e.isPublicRequestsPaused` is then true, `e.renewsAt` says when it renews and `retryAfter` is days long, so the SDK does not retry. Show a calm "temporarily unavailable" message rather than a generic error:

```kotlin
} catch (e: NullDullException) {
    if (e.isPublicRequestsPaused) showPaused(e.renewsAt) else throw e
}
```

| Code | Status | Meaning |
| --- | --- | --- |
| `INVALID_ARGUMENT` | 0 | Bad option or argument; nothing was sent |
| `WORKSPACE_REQUIRED` | 0 | Memory/Locale call without `workspaceId` |
| `PRIVATE_KEY_REQUIRED` | 0 | Memory/Locale call with a public key |
| `NETWORK_ERROR` | 0 | Could not reach NullDull (retried) |
| `TIMEOUT` | 0 | One attempt exceeded `timeout` (not retried) |
| `ABORTED` | 0 | The HTTP call was cancelled outside the coroutine |
| `INVALID_RESPONSE` | 0 or 2xx | Response was not the expected JSON, or a cursor repeated |
| `REQUEST_FAILED` | 3xx–5xx | Error without a JSON body, or a redirect (never followed) |
| `INVALID_INPUT` | 400 | The server rejected a parameter |
| `UNAUTHENTICATED`, `INVALID_KEY`, `KEY_REQUIRED` | 401 | Missing, revoked or rotated key |
| `FORBIDDEN` | 403 | Missing scope, wrong workspace, or an unreadable document or folder |
| `NOT_FOUND`, `NOT_AVAILABLE` | 404 | Missing resource or pool |
| `RATE_LIMITED` | 429 | Too many requests, or (with `reason` `PUBLIC_REQUESTS_PAUSED`) the workspace's monthly public requests are used up |
| `SERVICE_UNAVAILABLE`, `NOT_CONFIGURED` | 503 | Temporary failure, or a feature not configured |

### Retries, timeouts and cancellation

- HTTP `429`, `502`, `503`, `504` and network errors are retried up to `maxRetries` times (default 2): after 500 ms, then 1000 ms.
- When the response has `Retry-After` of 30 seconds or less, the SDK waits exactly that long. When it is longer, it throws at once with `retryAfter` set, so you decide when to try again.
- `timeout` applies to each attempt, including reading the body. Timeouts are not retried. `Duration.ZERO` disables it.
- Cancelling the calling coroutine cancels the HTTP call and throws `CancellationException`, as usual for coroutines. Use `withTimeout` for an overall deadline.
- Redirects are never followed, cookies are never sent and responses are never cached.

## Grid renderer (alpha)

Two further artifacts render Grid documents natively on Android. They are versioned separately from `nulldull-sdk` and do not depend on it.

> **Alpha.** The Grid renderer artifacts are in early access, at version `0.2.0` (22 November 2026), and their API may change before `1.0`. Version `0.1.0` was the first release on Maven Central, on 20 November 2026.

| Artifact | Kind | Contents |
| --- | --- | --- |
| `com.nulldull:nulldull-grid-core:0.2.0` | JVM library (no Android dependency) | Document model and validation, layout engine, Markdown model, URL and SVG safety rules, coroutine content client |
| `com.nulldull:nulldull-grid-compose:0.2.0` | Android library (AAR) | Jetpack Compose renderer |

```kotlin
// build.gradle.kts
dependencies {
    implementation("com.nulldull:nulldull-grid-compose:0.2.0") // brings nulldull-grid-core
}
```

Requirements: `nulldull-grid-core` targets Java 17 bytecode (Kotlin 2.2, kotlinx.serialization 1.9, kotlinx.coroutines 1.10, `org.jetbrains:markdown`). `nulldull-grid-compose` needs minSdk 24 and compileSdk 36, uses Compose BOM 2025.08.00 (no Material dependency) and Coil 3.3 for images and SVG, and declares `INTERNET`. Packages are `com.nulldull.grid` and `com.nulldull.grid.compose`.

```kotlin
val grid = GridClient(
    baseUrl = "https://nulldull.com/api/grid/v1",
    apiKey = "nd_pub_…", // a public key with the grid:published scope
)

@Composable
fun Article(slug: String) {
    val page by produceState<PublicGridPage?>(null, slug) { value = grid.getPage("my-blog", slug) }
    page?.let {
        PublishedGridPage(
            page = it,
            modifier = Modifier.verticalScroll(rememberScrollState()),
            customNodes = mapOf("callout" to { node -> Callout(node.property("text").orEmpty()) }),
        )
    }
}
```

### Routing Grid page links (prepared for Kotlin Grid 0.3.0)

The resolver receives the target's stable `entryId`, current pool, slug and locale, and the link's optional anchor. Return a credential-free HTTP(S) URL for the platform URI handler, or a path beginning with one slash for your own navigation handler.

```kotlin
PublishedGridPage(
    page = page,
    resolvePageLink = { target, anchor ->
        if (target.pool == "manual") {
            "/${target.locale}/${target.slug}" + (anchor?.let { "#$it" } ?: "")
        } else null
    },
    onOpenUrl = { href ->
        if (href.startsWith("/")) router.navigate(href)
        else uriHandler.openUri(href)
    },
)
```

Here `router` is the app's navigator and `uriHandler` is `LocalUriHandler.current` captured in the composable. The resolver runs during rendering. Only the tap handler navigates. A missing binding, a missing resolver, a `null` result, or unsafe output leaves the label as text. With a separately decoded document, pass its matching `pageTargets` and `resolvePageLink` to `GridRenderer`.

For documents obtained elsewhere (for example from `NullDullClient.grid.getPage`), decode them with `GridDocument.decode(json)` (throws `GridValidationException`) and render them with `GridRenderer(document, resolveAsset = { id -> urls[id] })`.

- `GridClient` follows the same key rules as the SDK: a private `nd_sec_` key is refused unless `allowPrivateKey = true` (server-side JVM use) and is never put in a URL; a public key is added as `key=` only to asset URLs on the API's own origin. `GridHttpEngine` is a one-method interface, so you can inject OkHttp, Ktor or a test double; engines must not follow redirects, send cookies or cache.
- An HTTP error throws `GridPublicException` with `status`, `code`, `detail`, `reason`, `renewsAt` and `retryAfter` (seconds). The client never retries. When the workspace's public requests are paused (`isPublicRequestsPaused`: `429` with `reason` `PUBLIC_REQUESTS_PAUSED`), show your own calm "temporarily unavailable" state until `renewsAt`. `GridRenderer` and `PublishedGridPage` only render a page you already loaded, so they never show a load error themselves.
- External links and assets must be credential-free `http`/`https` URLs. Custom node properties are inert. Downloaded SVG files pass the same static allowlist as the web renderer before AndroidSVG draws them.
- TalkBack descriptions, system font scale for flowing text, and light and dark themes (`GridTheme`) are supported. Video and audio never autoplay. Each node has the test tag `grid:<node id>`.
- Restricted embeds (YouTube on `youtube-nocookie.com`, and Vimeo) play inline, in a WebView inside the node. The `embedLoading` parameter of `GridRenderer` and `PublishedGridPage` sets when the player loads:
  - `GridEmbedLoading.Immediate` (the default) loads the player as soon as the embed is composed, without a tap. This means a request to YouTube or Vimeo happens as soon as the embed is shown. `GridRenderer` composes every node of the page, so this includes embeds further down a long page that the viewer has not scrolled to yet. The video does not autoplay: the viewer starts it with the player's own play button.
  - `GridEmbedLoading.Tap` shows a local poster with the node name, the provider and a play button, and makes no request to the provider until the viewer taps it. The tap loads the player and starts the video. The tap is kept in saved state, so after a rotation, or when a lazy list scrolls the page away and back, the player loads and starts again from the beginning instead of showing the poster.

  ```kotlin
  PublishedGridPage(page = page, embedLoading = GridEmbedLoading.Tap)
  ```

  The WebView runs JavaScript for the player only, has no JavaScript bridge, file or content access, or third-party cookies, and opens links that leave the player through `onOpenUrl`. Unlike the Swift renderer's non-persistent web view, it uses your app's default WebView data, so what the players keep in DOM storage and the HTTP cache persists between launches. YouTube requires the embedder to identify itself with an HTTP `Referer` (without one it shows "Error 153"), so the player is framed in a local page whose origin is your application ID, for example `https://com.example.app/`, as [YouTube documents for apps](https://developers.google.com/youtube/terms/required-minimum-functionality#embedded-player-api-client-identity). YouTube and Vimeo therefore receive a `Referer` naming your app's package. You need no setup for this. Pass `renderEmbed` to replace the built-in player in either mode, for example to wait for consent.

Known differences from the web renderer: groove and ridge borders draw solid; Markdown footnotes are plain text; WOFF and WOFF2 fonts fall back to the node's family; animated images show their first frame; video uses the platform `VideoView` (`cover` renders as `contain`), and audio has play and pause only. Replace them with `renderVideo` and `renderAudio`.

The layout engine and validator are tested against golden geometry and validation cases generated from the TypeScript renderer, in [`fixtures/grid-renderer`](../fixtures/grid-renderer) (shared with the Swift renderer).

## Testing

```sh
./gradlew build          # the SDK and the Grid renderer modules (needs an Android SDK: ANDROID_HOME or local.properties)
./gradlew :sdk:build     # the SDK only; no Android SDK needed
```

The unit tests run every case in the shared [`fixtures/manifest.json`](../fixtures/manifest.json) against MockWebServer, plus the behaviours in SPEC.md section 11. Optional live tests run against the real API when these are set:

| Variable | Used for |
| --- | --- |
| `NULLDULL_PUBLIC_KEY` and `NULLDULL_GRID_POOL` | Grid |
| `NULLDULL_PRIVATE_KEY` and `NULLDULL_WORKSPACE_ID` | Memory and Locale |
| `NULLDULL_LOCALE_SCOPE_ID` (optional) | Locale export location |
| `NULLDULL_BASE_URL` (optional) | Another API origin |

```sh
NULLDULL_PUBLIC_KEY=… NULLDULL_GRID_POOL=my-blog ./gradlew :sdk:test --tests 'com.nulldull.sdk.LiveTest*' --rerun
```

## Publishing

`./gradlew publishToMavenLocal` builds the jar, sources jar, Dokka javadoc jar and POM without signing keys, for `nulldull-sdk` and `nulldull-grid-core`. For `nulldull-grid-compose` it builds the AAR, sources jar and POM; its javadoc jar holds only this README, because the KDoc ships in the sources jar. Releases to Maven Central use `./gradlew publishToMavenCentral` with `mavenCentralUsername`, `mavenCentralPassword` and `signingInMemoryKey` (plus `signingInMemoryKeyPassword`) provided as Gradle properties or `ORG_GRADLE_PROJECT_…` environment variables. Signing turns on only when a signing key is present.

## License

[MIT](../LICENSE) © 2026 NullDull
