# NullDull SDK specification

Version 0.1.0 (early access). This is the one contract every NullDull SDK implements: Node/TypeScript (`node/`, the reference implementation), React, Python, Go, Swift and Kotlin. The facts below are taken from the NullDull API source. Where this document and an SDK disagree, the SDK is wrong. Where this document and the live API disagree, open an issue and fix this document first.

The words MUST, MUST NOT, SHOULD and MAY are used as in RFC 2119.

## 1. Scope

The SDKs cover **workspace API keys only**: read-only product integrations. They do not cover device login, agent connections, browser sessions, writes, Secrets, private Grid, Tasks or administration. The server rejects API keys on all of those routes anyway.

| Key | Prefix | Scopes it can hold | Can call |
| --- | --- | --- | --- |
| Public | `nd_pub_` | `grid:published` | Grid delivery (`grid.*`) |
| Private | `nd_sec_` | `grid:published`, `memory:read`, `locale:read` | Grid delivery with `grid:published`; Memory reads with `memory:read`; Locale export and formats with `locale:read` |

A key matches `^nd_(pub|sec)_[a-f0-9]{64}$`. It is always sent as `Authorization: Bearer <key>`.

A private key acts as a read-only agent of **the member who created it**, limited to that member's current access. Removing the member, or revoking, rotating or rescoping the key, takes effect on the next request.

Public keys are safe to ship in browser and mobile bundles. Private keys belong on servers only.

## 2. Hosts and paths

| Product | Public path prefix (appended to `baseUrl`) |
| --- | --- |
| Grid delivery | `/api/grid/v1` |
| Memory and Locale (platform API) | `/api/platform` |

The default `baseUrl` is `https://nulldull.com`. The web worker forwards `/api/platform/…` to the API as `/v1/platform/…` and `/api/grid/v1/…` as `/v1/grid/…`; SDKs only use the public paths.

Platform paths are scoped to a workspace: `/api/platform/workspaces/{workspaceId}/…`.

### 2.1 Workspace discovery: there is none

An API key cannot find out its own workspace ID. The server only lets a private key call routes under `/workspaces/{its own workspaceId}/…`. `GET /session`, `GET /workspaces` and `/connection` are refused (403) for keys. A wrong workspace ID gets `403 FORBIDDEN`, the same answer as a missing scope. Grid responses never include a workspace ID.

So `workspaceId` is **required for every `memory.*` and `locale.*` call**. Owners and admins can see it in the app. The workspace's root location (scope) has the same ID as the workspace. Grid calls do not need it.

## 3. Client construction

```
NullDullClient(options)
```

| Option | Type | Default | Rules |
| --- | --- | --- | --- |
| `apiKey` | string | required | Must match the key pattern, or construction fails with `INVALID_ARGUMENT`. |
| `baseUrl` | string | `https://nulldull.com` | `http:` or `https:`, no user info, query or fragment. One trailing `/` is removed. Paths are appended to it as given. |
| `workspaceId` | string | none | `^[a-zA-Z0-9_-]{1,128}$`. Needed for `memory.*` and `locale.*` (see 2.1). |
| `timeout` | duration | 30 s | Applies to each attempt separately. `0` or none means no timeout. |
| `maxRetries` | integer | 2 | Retries after the first attempt. `0` turns retries off. |
| `fetch` / HTTP client | platform type | platform default | Must be injectable so tests can mock HTTP. Node: a `fetch`-compatible function. Python: an `httpx`-style transport. Go: `*http.Client`. Swift: `URLSession`. Kotlin: an `OkHttpClient` or Ktor engine. |
| `userAgent` | string | none | Optional suffix, sent as `nulldull-sdk-<lang>/<version> <suffix>`. |

JavaScript SDKs only: when the client is built in a browser (`window` and `document` exist) with a **private** key, construction fails with `INVALID_ARGUMENT`, unless the caller passes `dangerouslyAllowPrivateKeyInBrowser: true`. `@nulldull/grid-react`'s `createGridClient` does the same check.

The client exposes three namespaces: `grid`, `memory` and `locale`. It holds no mutable state besides its configuration and is safe to share between concurrent callers.

## 4. Requests

Every SDK request is a `GET`.

Headers on every request:

- `Authorization: Bearer <apiKey>`
- `Accept: application/json` for JSON calls and `*/*` for downloads.
- `User-Agent: nulldull-sdk-<lang>/<version>`, for example `nulldull-sdk-node/0.1.0`, `nulldull-sdk-python/0.1.0` or `nulldull-sdk-go/0.1.0`. Browser JavaScript MUST NOT set it: browsers ignore or forbid it, and Grid's CORS policy only allows `Authorization`, `Range` and `If-None-Match`. Do not add other custom headers, for the same CORS reason.

Other request rules:

- Path segments are percent-encoded (`encodeURIComponent` semantics). IDs are opaque strings; do not validate their format client-side beyond being non-empty strings. The server only accepts `[a-zA-Z0-9_-]` for IDs and answers `403` or `404` otherwise.
- Query parameters whose value is absent (null, undefined, nil, None) are left out. Strings are sent as given. Integers are sent in decimal. Booleans are sent as `true`. A list parameter is sent as the same key repeated (`tag=a&tag=b`), unless a method says it is comma-joined.
- Do not follow redirects (Node: `redirect: "manual"`). A `3xx` is an error (code `REQUEST_FAILED`). This keeps the key from being sent to another origin.
- Do not send cookies (`credentials: "omit"` in browsers).
- Do not use HTTP caches. Every response is `Cache-Control: no-store`.

## 5. Responses and errors

A `2xx` JSON response is returned as the decoded object, with no renaming. Field names stay exactly as the API sends them (camelCase). Typed SDKs MAY expose language-cased properties but MUST round-trip unknown fields or keep the raw object reachable. New fields can appear at any time; decoding MUST NOT fail on unknown fields or unknown enum values.

### 5.1 The error type

Every failure is raised as a single error type: `NullDullError` (Python `NullDullError`, Go `*nulldull.Error`, Swift `NullDullError`, Kotlin `NullDullException`).

| Field | Type | Meaning |
| --- | --- | --- |
| `status` | int | HTTP status. `0` for client-side errors (no response). |
| `code` | string | The response body's `code` when it is a string; otherwise one of the client codes below. |
| `message` | string | The body's `message` when present; otherwise `NullDull request failed (<status> <code>).` Client errors have their own message. |
| `detail` | string or null | The body's `detail` (for example `LOCALE_EXPORT_TOO_LARGE`). |
| `requestId` | string or null | The `X-Request-Id` response header, or else `CF-Ray`. Production responses carry `CF-Ray`. |
| `retryAfter` | number or null | `Retry-After` in seconds, when the response had one. |
| `body` | object or null | The whole decoded JSON error body. Locale errors put `key`, `language` and `issues` here; some `409`s put `reason` here. |
| `reason` | string or null | The body's `reason` when it is a string, for example `PUBLIC_REQUESTS_PAUSED` (5.4) or `QUOTA_EXCEEDED`. |
| `renewsAt` | string or null | The body's `renewsAt` when it is a string: an ISO 8601 UTC time, sent with `PUBLIC_REQUESTS_PAUSED`. |

Every error type also offers a paused check, true when `status` is `429` and `reason` is `PUBLIC_REQUESTS_PAUSED` (Node `error.publicRequestsPaused` and `isPublicRequestsPaused(error)`, Python `public_requests_paused` and `is_public_requests_paused(error)`, Go `PublicRequestsPaused()` and `IsPublicRequestsPaused(err)`, Swift and Kotlin `isPublicRequestsPaused`). Language casing applies (`renews_at` in Python, `RenewsAt` in Go). `reason` and `renewsAt` were added after 0.1.0; they are also in `body`.

The error's language-native message (`Error.message`, `str(e)`, `Error()`) is `message`.

### 5.2 Server error codes

Error bodies are JSON shaped like `{"code": "...", "message"?: "...", "detail"?: "...", ...}`.

| Status | Codes | When |
| --- | --- | --- |
| 400 | `INVALID_INPUT`, `INVALID_JSON` | Bad query value (Grid locale/limit/cursor, search shorter than 2 characters, bad Locale format, language or status). Locale adds `detail`: `LOCALE_EXPORT_TOO_LARGE`, `LOCALE_FORMAT_UNKNOWN`, `LOCALE_FORMAT_UNREPRESENTABLE`, `LOCALE_FORMAT_COLLISION`, `LOCALE_FORMAT_LANGUAGE_REQUIRED`, … |
| 401 | `UNAUTHENTICATED` (platform), `INVALID_KEY`, `KEY_REQUIRED` (Grid) | Missing, malformed, revoked or rotated key. A public key on the platform API also gets `401 UNAUTHENTICATED`. |
| 403 | `FORBIDDEN` | Missing scope, wrong workspace ID, or a route keys cannot use. |
| 404 | `NOT_FOUND`, `NOT_AVAILABLE` | Missing or invisible resource or pool, or the platform is switched off. |
| 409 | `CONFLICT`, … | Not expected on read routes. |
| 413 | `REQUEST_TOO_LARGE` | Not expected on read routes. |
| 429 | `RATE_LIMITED` | Rate limited per client IP. Comes with `Retry-After` (usually `60`). Grid delivery also answers `429` with `reason` `PUBLIC_REQUESTS_PAUSED` (5.4). |
| 503 | `SERVICE_UNAVAILABLE`, `NOT_CONFIGURED`, `NOT_AVAILABLE` | Temporary failure, or a feature not configured in this environment. |

A non-JSON error body (for example a router's plain-text `404 Not Found`, or an HTML `502`) gets code `REQUEST_FAILED`.

Note: `GET /documents/{id}` and `GET /folders/{id}` answer `403 FORBIDDEN` (not 404) for a missing or unreadable item. Assets answer `404 NOT_FOUND`.

### 5.3 Client error codes (`status` 0)

| Code | When |
| --- | --- |
| `INVALID_ARGUMENT` | Bad client options or method arguments, found before any request. |
| `WORKSPACE_REQUIRED` | A `memory.*` or `locale.*` call on a client without `workspaceId`. |
| `PRIVATE_KEY_REQUIRED` | A `memory.*` or `locale.*` call with a public key. No request is sent. |
| `NETWORK_ERROR` | The transport failed (DNS, TLS, connection reset). |
| `TIMEOUT` | One attempt took longer than `timeout`. |
| `ABORTED` | The caller cancelled (AbortSignal, context, Task cancellation). |
| `INVALID_RESPONSE` | A `2xx` body was not valid JSON, or a cursor did not advance during iteration. |

### 5.4 Paused public requests (`PUBLIC_REQUESTS_PAUSED`)

Once early access has ended, every public Grid delivery (page, listing or asset, covers included; `GET` or `HEAD`; `200`, `206` or `304`) counts toward the pool's workspace's monthly public requests. A workspace on the Free plan that has used them is paused: every Grid read of its pools, keyed or anonymous, answers

- status `429`, `Cache-Control: no-store`, and `Retry-After` in seconds until the first instant of the next UTC month (so far more than 30);
- the body `{"code": "RATE_LIMITED", "reason": "PUBLIC_REQUESTS_PAUSED", "detail": "PUBLIC_REQUESTS_PAUSED", "message": "...", "period": "YYYY-MM", "renewsAt": "<ISO 8601 UTC>"}`. `detail` repeats `reason` for clients that keep only `detail`. Branch on `reason`, never on `message`.

Base and Unlimited workspaces are never paused, and nothing is counted or refused while early access is open. The pause lifts at `renewsAt` (the start of the next UTC month), or within about two and a half minutes after the workspace upgrades or is gifted a plan. Memory and Locale routes never send it.

SDKs MUST NOT retry it, whatever its `Retry-After` (6). Renderers and hooks MUST NOT show a misleading state for it (for example "not found" or an empty list): they surface the error so the app can show a calm notice until `renewsAt`.

## 6. Retries

Only `GET` is retried, which covers every SDK call.

- **Retryable:** HTTP `429`, `502`, `503` and `504`, and `NETWORK_ERROR`. Nothing else: not `TIMEOUT`, `ABORTED`, other `4xx`/`5xx` or `INVALID_RESPONSE`, and never a `429` whose `reason` is `PUBLIC_REQUESTS_PAUSED`, even without `Retry-After` (5.4).
- **Budget:** at most `maxRetries` retries (default 2), so at most 3 attempts in total.
- **Delay when the response has `Retry-After`** (delta-seconds or an HTTP date): wait exactly that long, but only if it is **30 seconds or less**. If it is longer, do not retry: raise the error at once with `retryAfter` set, so the caller can decide. (The platform rate limiter sends `60`, so most real `429`s are raised immediately.)
- **Delay otherwise:** `500 ms × 2^(n−1)` before retry `n`, which gives 500 ms and then 1000 ms. No jitter in 0.1.0, so test timings are exact.
- Throw away the body of a failed attempt before retrying.
- When retries run out, raise the error from the last attempt.
- Cancellation during a wait raises `ABORTED` immediately.
- SDKs SHOULD let tests replace the sleep function. Conformance tests check the requested delays (`sleeps` in the fixtures) and do not actually wait.

## 7. Pagination

List endpoints return `{ "items": [...], "nextCursor": string | null, ... }`. To get the next page, send the cursor back as `after`. Cursors are opaque strings: never parse, build or change them.

- **Single page:** `listX(params)` returns the page object exactly as sent, including extra fields such as Grid's `pool` or folders' `here`. `params.after` picks the page.
- **Iteration:** `iterateX(params)` returns a lazy sequence of **items** across pages (Node: `AsyncIterable`; Python: a generator plus an async generator; Go: `iter.Seq2[T, error]` or a `Next()`-style iterator; Swift: `AsyncThrowingStream`; Kotlin: `Flow`). It starts at `params.after` when given and stops when `nextCursor` is `null`.
- **An empty page is not the end.** Grid search scans a bounded window per request and can return `items: []` with a non-null `nextCursor`. Keep going until the cursor is `null`.
- **Loop guard:** if a page returns the same `nextCursor` that was just sent, stop with `INVALID_RESPONSE`.
- Page sizes are fixed by the server: Memory scopes, folders, documents, assets and asset versions return up to 50 items; search and tags up to 20. Only Grid accepts `limit` (1–50, default 20).

Cursor formats, for information only: Grid cursors are base64 JSON bound to pool, locale, `q` and `folderId`, and fail with `400 INVALID_INPUT` if reused with other filters. Memory cursors are the last item's ID. Tag cursors are `count:tag`.

## 8. Methods

The canonical names are camelCase. Each language uses its own conventions (section 10). `?` marks an optional parameter. "Page<T>" means `{items: T[], nextCursor: string | null}`.

### 8.1 Grid: published content (`grid:published`)

Works with public keys and with private keys that hold `grid:published`. No `workspaceId` is needed: the key's workspace must own the pool, and a pool owned by another workspace looks absent (`404`).

| Method | HTTP | Returns |
| --- | --- | --- |
| `grid.listPages(pool, {locale?, q?, folderId?, limit?, after?})` | `GET /api/grid/v1/pools/{pool}/pages?locale=&q=&folderId=&limit=&after=` | `GridPageList` |
| `grid.iteratePages(pool, {locale?, q?, folderId?, limit?, after?})` | the same, following `nextCursor` | items of `GridPageSummary` |
| `grid.getPage(pool, slug, {locale?})` | `GET /api/grid/v1/pools/{pool}/pages/{slug}?locale=` | `GridPage` |
| `grid.assetUrl(url)` | none (local) | absolute URL string |
| `grid.downloadAsset(urlOrAsset)` | `GET <asset url>` | `Download` |

Parameters:

- `pool` and `slug`: `^[a-z0-9]+(?:-[a-z0-9]+)*$`, at most 96 characters. Validate client-side and fail with `INVALID_ARGUMENT`.
- `locale`: defaults to `"en"` and is **always sent**. Must match `^[a-z]{2,3}(?:-[a-z0-9]{2,8})*$` (lowercase, for example `pt-br`), at most 35 characters.
- `q`: literal search over title and summary, at most 160 characters. Sent only when it is non-empty.
- `folderId`: only pages whose direct parent folder at publication time was this folder.
- `limit`: integer from 1 to 50. Validate client-side.

Returned asset URLs: list items' `cover.url`, and the page's `cover.url` and every `assets[].url`, are replaced with `grid.assetUrl(url)` before being returned. Nothing else is changed. The document is returned as-is; SDKs do not validate or render it.

**`grid.assetUrl(url)`** mirrors `createGridClient` in `@nulldull/grid-react`:

1. Resolve `url` against the **origin** of `baseUrl`. The server returns root-relative paths such as `/api/grid/v1/pools/…/assets/…?locale=en&version=3`.
2. If the client's key is **public**, the resolved URL has the same origin as `baseUrl` (same scheme, case-insensitive host and port, with default ports equal to omitted ones), and there is no `key` query parameter yet, add `key=<public key>`. Images, fonts and media cannot send headers, so this is the only way they can authenticate.
3. Never add a private key to a URL. Never add any key to a URL on another origin, including protocol-relative and look-alike hosts.

Keyed responses already include `&key=` for public keys, so step 2 usually changes nothing. Asset URLs pin a publication `version` and return `404` once the page is republished or withdrawn.

**`grid.downloadAsset(urlOrAsset)`** takes a URL string or any object with a `url` (an asset or a cover). It resolves the URL with `assetUrl`. It sends `Authorization` **only when the URL has the same origin as `baseUrl`**, and it never sends credentials to another origin.

### 8.2 Memory: read-only (`memory:read`, private key, `workspaceId`)

All paths are under `/api/platform/workspaces/{workspaceId}`.

| Method | HTTP | Returns |
| --- | --- | --- |
| `memory.listScopes({after?})` | `GET /scopes?after=` | `Page<Scope>` |
| `memory.iterateScopes({after?})` | the same | items of `Scope` |
| `memory.listFolders({scopeId?, parentId?, after?})` | `GET /folders?scopeId=&parentId=&after=` | `FolderList` |
| `memory.iterateFolders({scopeId?, parentId?, after?})` | the same | items of `FolderSummary` |
| `memory.getFolder(folderId)` | `GET /folders/{folderId}` | `Folder` |
| `memory.listDocuments({scopeId?, folderId?, tags?, kind?, lifecycle?, after?})` | `GET /documents?scopeId=&folderId=&tag=&kind=&lifecycle=&after=` | `Page<DocumentSummary>` |
| `memory.iterateDocuments({…same})` | the same | items of `DocumentSummary` |
| `memory.getDocument(documentId)` | `GET /documents/{documentId}` | `Document` |
| `memory.resolveLink(documentId, href)` | `GET /documents/{documentId}/resolve-link?href=` | `LinkResolution` |
| `memory.search(q, {scopeId?, tags?, kind?, lifecycle?, after?})` | `GET /search?q=&scopeId=&tag=&kind=&lifecycle=&after=` | `Page<SearchResult>` |
| `memory.iterateSearch(q, {…same})` | the same | items of `SearchResult` |
| `memory.listTags({scopeId?, q?, after?})` | `GET /tags?scopeId=&q=&after=` | `Page<TagCount>` |
| `memory.iterateTags({…same})` | the same | items of `TagCount` |
| `memory.listAssets({scopeId?, folderId?, q?, tags?, after?})` | `GET /assets?scopeId=&folderId=&q=&tag=&after=` | `Page<Asset>` |
| `memory.iterateAssets({…same})` | the same | items of `Asset` |
| `memory.getAsset(assetId, {revisionId?})` | `GET /assets/{assetId}?revisionId=` | `Asset` |
| `memory.listAssetVersions(assetId, {after?})` | `GET /assets/{assetId}/versions?after=` | `Page<AssetVersion>` |
| `memory.iterateAssetVersions(assetId, {after?})` | the same | items of `AssetVersion` |
| `memory.downloadAsset(assetId, {revisionId?, preview?, width?})` | `GET /assets/{assetId}/download?revisionId=&preview=true&w=` | `Download` |

Parameter rules:

- `folderId` (documents, assets) and `parentId` (folders): a string ID, or **null for the location root**, which is sent as the literal `root`. Leaving the parameter out (undefined) means no folder filter. Languages without a separate undefined value (Go, Kotlin, Swift) use an explicit "root" option, for example `Root: true` or `FolderFilter.root`.
- `tags`: a list sent as repeated `tag=` parameters. Every listed tag must be present on the item. Tags are lowercase, at most 8, each 1–48 characters.
- `kind`: one of `rules`, `tasks`, `plan`, `reference`, `procedure`, `notes`, `unknown`. `lifecycle`: one of `maintained`, `one-time`, `unknown`. Send them as given; the server validates (`400`).
- `q` for search: 2–160 characters, a literal case-insensitive substring of name, content or tags. Shorter queries get `400 INVALID_INPUT`. SDKs do not pre-validate. `q` for tags: at most 48 characters. `q` for assets: at most 160 characters.
- Asset versions are listed newest first.
- `downloadAsset`: `width` is sent as `w`. Setting `width` also sends `preview=true`; `preview: true` alone sends only `preview=true`. Never send `submissionId`, because keys are refused when it is present. The server rounds widths up to 64, 128, 256, 512, 1024 or 2048. Only PNG, JPEG, WebP and AVIF images are resized (to WebP). Other types, and widths over 2048, return the original.

### 8.3 Locale: export (`locale:read`, private key, `workspaceId`)

| Method | HTTP | Returns |
| --- | --- | --- |
| `locale.listFormats()` | `GET /api/platform/workspaces/{ws}/locale/formats` | `LocaleFormatList` |
| `locale.export(scopeId, {format?, languages?, status?, basename?})` | `GET /api/platform/workspaces/{ws}/locale/export?scopeId=&format=&languages=&status=&basename=` | `LocaleExport` |

- `scopeId` is required: the location that holds the Locale library. The workspace root location's ID equals `workspaceId`.
- `format`: defaults to `"json"` and is **always sent**. Known IDs are `json`, `world`, `world-cldr`, `xcstrings`, `apple-strings` and `android-xml`. Send unknown IDs anyway; the server answers `400` with `detail: LOCALE_FORMAT_UNKNOWN`.
- `languages`: a list, **comma-joined** into one `languages=` parameter (for example `languages=en,tr`), at most 50. When left out, the server exports every configured language.
- `status`: a list of `draft`, `needs_review` and `approved`, **comma-joined** into one `status=`. When left out, keys of every status are exported.
- `basename`: `^[A-Za-z0-9_][A-Za-z0-9_.-]{0,63}$`, the base file name without extension.
- SDKs MUST NOT send the legacy single `language=` parameter. With `language` alone, a `json` or `world` export returns an old `{content}` shape. Always using `languages` guarantees the shape below.

**The export is always JSON. It is never an archive or raw file bytes:**

```json
{ "format": "json",
  "files": [ { "path": "en.json", "contentType": "application/json", "content": "{…}\n" },
             { "path": "tr.json", "contentType": "application/json", "content": "{…}\n" } ],
  "notes": [],
  "contentVersion": 42 }
```

- Single-language formats (`layout: "single"`: `json`, `world`, `world-cldr`, `apple-strings`, `android-xml`) give **one file set per language**. Examples: `en.json` and `tr.json`; `values/strings.xml` (source language) and `values-tr/strings.xml`; `en.lproj/Localizable.strings` plus an optional `.stringsdict`.
- Multi-language formats (`layout: "multi"`: `xcstrings`) give **one file** holding every language, such as `Localizable.xcstrings`.
- `content` is always text (UTF-8). Paths are relative and may contain `/`. Callers write them under an output directory. SDKs MAY offer a helper that writes the files, but it MUST reject absolute paths and `..` segments.
- `notes[]` items are `{code, key, language?}`, for example `LOCALE_FORMAT_DESCRIPTION_OMITTED`.
- Limits: 2,000 keys and 2,000,000 characters. Exports over either limit fail with `400 INVALID_INPUT` and `detail: LOCALE_EXPORT_TOO_LARGE`.

## 9. Types

Every type is the API's JSON object. Fields marked `?` may be missing; `| null` fields are always present but can be null. Times are Unix epoch **milliseconds** as integers. Enum-like strings MUST accept unknown values.

### Grid

```ts
GridAssetRef = { id: string; version: number; url: string; filename: string; mediaType: string; byteSize: number; checksum: string /* SHA-256 hex */ }
GridCover = GridAssetRef & { alt: string }   // "" = decorative
GridPageSummary = {
  id: string; pool: string; slug: string; locale: string; title: string; summary: string;
  version: number;        // publication version
  sourceVersion: number;  // editor version that was published
  publishedAt: number; folderId?: string | null; cover?: GridCover | null }
GridPage = GridPageSummary & { document: GridDocument; assets: GridAssetRef[] }
GridPageList = { pool: { key: string; name: string }; items: GridPageSummary[]; nextCursor: string | null }
GridDocument = { layout: object; breakpoints: object[]; baseLayoutIndex?: number; baseLayoutName?: string; nodes: object[] }
               // The full schema belongs to @nulldull/grid-core. SDKs treat nested values as opaque JSON.
```

### Memory

```ts
LocationIcon = { iconKind?: "symbol" | "emoji" | "image" | null; iconValue?: string | null; iconVersion?: number }
Scope = LocationIcon & { id: string; name: string; kind: "workspace" | "customer-product" | "project"; parentId: string | null }
LocationPathItem = Scope       // root first, up to three levels
Placement = { repository: string | null; path: string; folderPath: string }   // folderPath: "a/b" ("" at root)
FileLabels = { tags: string[]; labelKind: FileKind | null; labelLifecycle: FileLifecycle | null;
               labelSource: "ai" | "manual" | null; labelStatus: "ready" | "pending" | "failed" | "unclassified" }
FolderBase = { workspaceId: string; id: string; scopeId: string; parentId: string | null; name: string; createdBy: string;
               preferredRepository: string | null; preferredPath: string | null; metadataVersion: number }
FolderSummary = FolderBase & { folderCount: number; documentCount: number; assetCount: number; secretCount: number; placement: Placement }
FolderList = Page<FolderSummary> & { here?: { folders: number; documents: number; assets: number; secrets: number } }
             // `here` only on the first page when both scopeId and parentId were given
Folder = FolderBase & { canManage: boolean; canDelete: boolean; placement: Placement;
                        ancestors: { id: string; name: string }[]; contents: "empty" | "visible" | "hidden" }
DocumentSummary = FileLabels & { id: string; name: string; scopeId: string; folderId: string | null; headRevisionId: string | null;
                  preferredRepository: string | null; preferredPath: string | null; metadataVersion: number; role: "senior" | "junior" }
Document = DocumentSummary & { headAuthorMemberId: string | null; content: string | null /* Markdown, ≤ 128 KiB */;
                               contentHash: string | null; placement: Placement; locationPath: LocationPathItem[] }
SearchResult = FileLabels & { id; name; scopeId; folderId; headRevisionId; metadataVersion; role;
                              excerpt: string /* ≤ 240 chars around the match */; locationPath: LocationPathItem[]; folderPath: string }
TagCount = { tag: string; count: number }   // most used first
LinkResolution = { status: "found"; id: string; fragment: string } | { status: "unavailable" } | { status: "ambiguous" }
AssetObject = { id: string; filename: string; mediaType: string; byteSize: number; checksum: string; authorMemberId: string; createdAt: number }
Asset = { id: string; name: string; scopeId: string; kind: "asset"; folderId: string | null; folderPath: { id: string; name: string }[];
          headRevisionId: string | null; revisionId: string | null; metadataVersion: number; role: "senior" | "junior";
          description: string; tags: string[]; tagSource: "manual" | "ai"; summary: string | null;
          insightStatus: string /* "ready" | "pending" | "failed" | "unavailable" | … */;
          object: AssetObject | null /* null before the first upload */; locationPath: LocationPathItem[] }
AssetVersion = { id: string; createdAt: number; authorMemberId: string }
```

`FileKind` = `rules | tasks | plan | reference | procedure | notes | unknown`. `FileLifecycle` = `maintained | one-time | unknown`.

### Locale

```ts
LocaleFormat = { id: string; label: string;
  capabilities: { layout: "single" | "multi"; plurals: "cldr" | "one-other" | "none"; variables: "named" | "positional";
                  status: boolean; description: boolean; variableTypes: boolean };
  files: { role: string; extension: string; contentType: string; required: boolean }[] }
LocaleFormatList = { items: LocaleFormat[] }
LocaleFile = { path: string; contentType: string; content: string }
LocaleExport = { format: string; files: LocaleFile[]; notes: { code: string; key: string; language?: string }[]; contentVersion: number }
```

### Download

```ts
Download = { bytes: <byte array>; contentType: string | null; filename: string | null; size: number }
```

- `bytes`: the whole body (Node `Uint8Array`, Python `bytes`, Go `[]byte`, Swift `Data`, Kotlin `ByteArray`). SDKs MAY also offer a streaming variant, named `…Stream` in languages that have one.
- `contentType`: the `Content-Type` header. Memory downloads that are not previews are always served as `application/octet-stream` attachments; the real media type is in `Asset.object.mediaType`.
- `filename`: from `Content-Disposition`. Prefer `filename*=UTF-8''<percent-encoded>` (decode it), then `filename="…"`, else `null`. Resized previews have no filename.
- `size`: the byte length of `bytes`.

## 10. Method naming table

| Canonical | Node / React (TS) | Python | Go | Swift | Kotlin |
| --- | --- | --- | --- | --- | --- |
| `grid.listPages` | `grid.listPages` | `grid.list_pages` | `Grid.ListPages` | `grid.listPages` | `grid.listPages` |
| `grid.iteratePages` | `grid.iteratePages` | `grid.iterate_pages` | `Grid.IteratePages` | `grid.iteratePages` | `grid.iteratePages` |
| `grid.getPage` | `grid.getPage` | `grid.get_page` | `Grid.GetPage` | `grid.getPage` | `grid.getPage` |
| `grid.assetUrl` | `grid.assetUrl` | `grid.asset_url` | `Grid.AssetURL` | `grid.assetURL` | `grid.assetUrl` |
| `grid.downloadAsset` | `grid.downloadAsset` | `grid.download_asset` | `Grid.DownloadAsset` | `grid.downloadAsset` | `grid.downloadAsset` |
| `memory.listScopes` | `memory.listScopes` | `memory.list_scopes` | `Memory.ListScopes` | `memory.listScopes` | `memory.listScopes` |
| `memory.iterateScopes` | `memory.iterateScopes` | `memory.iterate_scopes` | `Memory.IterateScopes` | `memory.iterateScopes` | `memory.iterateScopes` |
| `memory.listFolders` | `memory.listFolders` | `memory.list_folders` | `Memory.ListFolders` | `memory.listFolders` | `memory.listFolders` |
| `memory.iterateFolders` | `memory.iterateFolders` | `memory.iterate_folders` | `Memory.IterateFolders` | `memory.iterateFolders` | `memory.iterateFolders` |
| `memory.getFolder` | `memory.getFolder` | `memory.get_folder` | `Memory.GetFolder` | `memory.getFolder` | `memory.getFolder` |
| `memory.listDocuments` | `memory.listDocuments` | `memory.list_documents` | `Memory.ListDocuments` | `memory.listDocuments` | `memory.listDocuments` |
| `memory.iterateDocuments` | `memory.iterateDocuments` | `memory.iterate_documents` | `Memory.IterateDocuments` | `memory.iterateDocuments` | `memory.iterateDocuments` |
| `memory.getDocument` | `memory.getDocument` | `memory.get_document` | `Memory.GetDocument` | `memory.getDocument` | `memory.getDocument` |
| `memory.resolveLink` | `memory.resolveLink` | `memory.resolve_link` | `Memory.ResolveLink` | `memory.resolveLink` | `memory.resolveLink` |
| `memory.search` | `memory.search` | `memory.search` | `Memory.Search` | `memory.search` | `memory.search` |
| `memory.iterateSearch` | `memory.iterateSearch` | `memory.iterate_search` | `Memory.IterateSearch` | `memory.iterateSearch` | `memory.iterateSearch` |
| `memory.listTags` | `memory.listTags` | `memory.list_tags` | `Memory.ListTags` | `memory.listTags` | `memory.listTags` |
| `memory.iterateTags` | `memory.iterateTags` | `memory.iterate_tags` | `Memory.IterateTags` | `memory.iterateTags` | `memory.iterateTags` |
| `memory.listAssets` | `memory.listAssets` | `memory.list_assets` | `Memory.ListAssets` | `memory.listAssets` | `memory.listAssets` |
| `memory.iterateAssets` | `memory.iterateAssets` | `memory.iterate_assets` | `Memory.IterateAssets` | `memory.iterateAssets` | `memory.iterateAssets` |
| `memory.getAsset` | `memory.getAsset` | `memory.get_asset` | `Memory.GetAsset` | `memory.getAsset` | `memory.getAsset` |
| `memory.listAssetVersions` | `memory.listAssetVersions` | `memory.list_asset_versions` | `Memory.ListAssetVersions` | `memory.listAssetVersions` | `memory.listAssetVersions` |
| `memory.iterateAssetVersions` | `memory.iterateAssetVersions` | `memory.iterate_asset_versions` | `Memory.IterateAssetVersions` | `memory.iterateAssetVersions` | `memory.iterateAssetVersions` |
| `memory.downloadAsset` | `memory.downloadAsset` | `memory.download_asset` | `Memory.DownloadAsset` | `memory.downloadAsset` | `memory.downloadAsset` |
| `locale.listFormats` | `locale.listFormats` | `locale.list_formats` | `Locale.ListFormats` | `locale.listFormats` | `locale.listFormats` |
| `locale.export` | `locale.export` | `locale.export` | `Locale.Export` | `locale.export` (escape the keyword if needed) | `locale.export` |

Packages: npm `@nulldull/sdk`; PyPI `nulldull`; Go module `github.com/doubco/nulldull-sdks/go`; SwiftPM product `NullDull`; Maven `com.nulldull:nulldull-sdk`. These names are not reserved yet.

Language adaptations: Python offers a sync `NullDull` client and an `AsyncNullDull` client with the same methods. Go passes `context.Context` as the first argument and options as a struct. Swift uses `async throws`. Kotlin uses `suspend` functions. Option structs use each language's casing (`scope_id`, `ScopeID`), but the wire names stay as in section 8.

## 11. Conformance

The fixtures in [`fixtures/`](fixtures) are shared by every SDK's test suite. [`fixtures/manifest.json`](fixtures/manifest.json) lists the cases. Each case has:

- `key`: `"public"` or `"private"`: which key from `config` to build the client with (`config.baseUrl` and `config.workspaceId` too).
- `call`: the canonical method and its arguments as JSON. Map them to your language. Arguments use canonical camelCase names; a `null` folder or parent means root.
- `exchanges`: the HTTP requests the SDK must send, in order, each with the canned `response` to return. `query` maps names to **lists** of values (repeated keys). Compare query parameters as a multimap, ignoring order. Responses come from `bodyFile` (relative to `fixtures/`), `body` (text) or `bodyBase64` (bytes).
- `expect`: one of
  - `resultFile`: the returned value must deep-equal this file, except the dot paths in `except`, which are checked by `checks` (`{path, equals}`; numeric segments index arrays).
  - `itemCount` (iteration): how many items the iterator yields in total; `checks` paths then index the list of items.
  - `download`: `contentType`, `filename`, `size`, `bytesBase64`.
  - `error`: the `NullDullError` fields to compare. Any listed field must match exactly; `null` means it must be null. A `body` object must be a subset of the error's `body`.
  - `attempts`: how many HTTP requests were sent in total (defaults to the number of exchanges). `sleeps`: the retry delays requested, in milliseconds.

Every SDK MUST pass all manifest cases and MUST also test these behaviours:

1. Construction: rejects a malformed key, a non-HTTP(S) `baseUrl`, a `baseUrl` with a query, fragment or user info, and a malformed `workspaceId` (`INVALID_ARGUMENT`). Strips a trailing slash from `baseUrl`.
2. Every request sends `Authorization: Bearer <key>`, the right `Accept`, and `User-Agent: nulldull-sdk-<lang>/0.1.0` (server-side SDKs). Browser builds send no `User-Agent`.
3. `memory.*` and `locale.*` without `workspaceId` raise `WORKSPACE_REQUIRED`, and with a public key raise `PRIVATE_KEY_REQUIRED`, both without any HTTP request.
4. Grid validates `pool`, `slug`, `locale` and `limit` client-side (`INVALID_ARGUMENT`, no request). It always sends `locale` (default `en`).
5. `grid.assetUrl`: resolves relative URLs against the `baseUrl` origin. Adds `key` only for public keys and same-origin URLs. Never adds a key to another origin (`https://cdn.example.com/…`, `//evil.example/…`, `https://nulldull.com.evil.example/…`) or for a private key. Keeps an existing `key`. Treats `https://nulldull.com:443` as the same origin as `https://nulldull.com`.
6. `grid.downloadAsset` sends `Authorization` only to the `baseUrl` origin.
7. List results normalize `cover.url`; page results normalize `cover.url` and `assets[].url`.
8. Iteration continues through an empty page that has a cursor, stops at `nextCursor: null`, starts from `after` when given, and raises `INVALID_RESPONSE` when a cursor repeats.
9. Errors: every field in 5.1 is filled from the body and headers (`CF-Ray` becomes `requestId`, `Retry-After` becomes `retryAfter`, the body's `reason` and `renewsAt` become `reason` and `renewsAt`), and the paused check is true only for a `429` with `reason` `PUBLIC_REQUESTS_PAUSED`. A non-JSON body gives `REQUEST_FAILED`. Invalid JSON on a `2xx` gives `INVALID_RESPONSE`.
10. Retries: `429` with `Retry-After ≤ 30` waits that long and retries. `429` with `Retry-After > 30` is raised without a retry. A `PUBLIC_REQUESTS_PAUSED` `429` is raised without a retry with or without `Retry-After` (manifest case `grid.listPages.publicRequestsPaused`, plus a test without the header). `502`, `503` and `504` back off 500 ms and then 1000 ms. `maxRetries: 0` disables retries. `400`, `401`, `403` and `404` are never retried. Network errors are retried. Timeouts are not retried.
11. Timeouts raise `TIMEOUT`, and caller cancellation raises `ABORTED`.
12. `memory` folder filters: `null` or root sends `root`, and an omitted filter sends nothing. `tags` become repeated `tag`. `downloadAsset({width})` sends `preview=true&w=`.
13. `locale.export` always sends `format` (default `json`), comma-joins `languages` and `status`, and never sends `language`.
14. Downloads decode RFC 5987 `filename*` and fall back to `filename="…"`.

### Live tests

Each SDK has an optional live suite, skipped unless its environment variables are set:

| Variable | Used for |
| --- | --- |
| `NULLDULL_PUBLIC_KEY` and `NULLDULL_GRID_POOL` | Grid list, iterate, get page and asset URL against the real API |
| `NULLDULL_PRIVATE_KEY` and `NULLDULL_WORKSPACE_ID` | Memory scopes, documents, search and tags; Locale formats |
| `NULLDULL_LOCALE_SCOPE_ID` (optional, defaults to the workspace ID) | Locale export |
| `NULLDULL_BASE_URL` (optional) | Point at staging or a local API |

Live tests MUST NOT print or log key values.

## 12. Versioning

All SDKs share one version number, released together. `0.x` releases may change the API in a minor version. The `User-Agent` version is the SDK's own version. When the API adds fields, the SDKs do not need a new release (see section 5).
