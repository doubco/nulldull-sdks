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
    e.body       // the whole JSON error body (Locale errors add key, language, issues)
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
| `RATE_LIMITED` | 429 | Too many requests |
| `SERVICE_UNAVAILABLE`, `NOT_CONFIGURED` | 503 | Temporary failure, or a feature not configured |

### Retries, timeouts and cancellation

- HTTP `429`, `502`, `503`, `504` and network errors are retried up to `maxRetries` times (default 2): after 500 ms, then 1000 ms.
- When the response has `Retry-After` of 30 seconds or less, the SDK waits exactly that long. When it is longer, it throws at once with `retryAfter` set, so you decide when to try again.
- `timeout` applies to each attempt, including reading the body. Timeouts are not retried. `Duration.ZERO` disables it.
- Cancelling the calling coroutine cancels the HTTP call and throws `CancellationException`, as usual for coroutines. Use `withTimeout` for an overall deadline.
- Redirects are never followed, cookies are never sent and responses are never cached.

## Testing

```sh
./gradlew build
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

`./gradlew publishToMavenLocal` builds the jar, sources jar, Dokka javadoc jar and POM without signing keys. Releases to Maven Central use `./gradlew publishToMavenCentral` with `mavenCentralUsername`, `mavenCentralPassword` and `signingInMemoryKey` (plus `signingInMemoryKeyPassword`) provided as Gradle properties or `ORG_GRADLE_PROJECT_…` environment variables. Signing turns on only when a signing key is present.

## License

[MIT](../LICENSE) © 2026 NullDull
