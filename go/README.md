# NullDull Go SDK

The official NullDull SDK for Go. It reads NullDull with **workspace API keys**:

- **Grid**: published pages, covers and assets.
- **Memory**: read-only access to documents, folders, search, tags and assets.
- **Locale**: export translation catalogs at build time.

> **Early access.** `0.1.0` may change before `1.0`. The SDK only reads data.

Standard library only. Go 1.23 or newer (iterators use `iter.Seq2`).

Documentation: <https://nulldull.com/docs> · Specification: [`SPEC.md`](https://github.com/doubco/nulldull-sdks/blob/main/SPEC.md) · API reference: [pkg.go.dev](https://pkg.go.dev/github.com/doubco/nulldull-sdks/go)

## Install

```sh
go get github.com/doubco/nulldull-sdks/go@latest
```

Releases are tagged `go/vX.Y.Z` (for example `go/v0.1.0`) in the `nulldull-sdks` monorepo.

```go
import nulldull "github.com/doubco/nulldull-sdks/go"
```

## Keys

Create keys in the NullDull app under **Workspace settings → API keys** (owners and admins).

| Key | Where | Scopes |
| --- | --- | --- |
| Public `nd_pub_…` | Apps and browser bundles | `grid:published` |
| Private `nd_sec_…` | Servers and CI only | `grid:published`, `memory:read`, `locale:read` |

Memory and Locale also need your **workspace ID**, because a key cannot look up its own workspace. The workspace root location has the same ID.

## Quick start

```go
client, err := nulldull.New(os.Getenv("NULLDULL_PRIVATE_KEY"), // or a public key for Grid only
	nulldull.WithWorkspaceID(os.Getenv("NULLDULL_WORKSPACE_ID")), // needed for Memory and Locale
)
if err != nil {
	log.Fatal(err)
}
ctx := context.Background()
```

Every method takes a `context.Context` first. Optional parameters are a struct pointer; pass `nil` for the defaults.

### Grid: published pages

```go
grid := client.Grid

// One page of results (newest first)
list, err := grid.ListPages(ctx, "my-blog", &nulldull.ListPagesParams{Locale: "en", Limit: 20})
// list.Pool, list.Items, list.NextCursor

// Every page, following cursors
for summary, err := range grid.IteratePages(ctx, "my-blog", &nulldull.ListPagesParams{Q: "launch"}) {
	if err != nil {
		return err
	}
	fmt.Println(summary.Title)
}

// One page with its document and asset manifest
page, err := grid.GetPage(ctx, "my-blog", "hello-world", nil)
page.Document // json.RawMessage: render it with @nulldull/grid-react, or decode what you need
page.Assets   // []GridAssetRef{ID, Version, URL, Filename, MediaType, ByteSize, Checksum}
```

`Locale` defaults to `"en"` and is always sent. Returned cover and asset URLs are absolute. With a public key they already carry `key=…`, so they work in `<img>`, CSS fonts and `<video>`, which cannot send headers. To resolve a URL yourself, call `grid.AssetURL(url)`. It adds a public key only to URLs on the API's own origin, and never adds a private key.

```go
file, err := grid.DownloadAsset(ctx, page.Assets[0].URL) // file.Bytes, ContentType, Filename, Size
```

`DownloadAsset` sends `Authorization` only to the API's own origin.

### Memory: read-only

```go
memory := client.Memory

scopes, err := memory.ListScopes(ctx, nil)
for doc, err := range memory.IterateDocuments(ctx, &nulldull.ListDocumentsParams{ScopeID: "…", Tags: []string{"rules"}}) {
	if err != nil {
		return err
	}
	fmt.Println(doc.ID, doc.Name)
}
doc, err := memory.GetDocument(ctx, "…")          // *doc.Content is the saved Markdown
hits, err := memory.Search(ctx, "release checklist", &nulldull.SearchParams{ScopeID: "…"})
link, err := memory.ResolveLink(ctx, doc.ID, "docs/setup.md#install") // Status "found", ID, Fragment

folders, err := memory.ListFolders(ctx, &nulldull.ListFoldersParams{ScopeID: "…", Root: true}) // top level
unfiled, err := memory.ListDocuments(ctx, &nulldull.ListDocumentsParams{Root: true})          // location root

asset, err := memory.GetAsset(ctx, "…", nil)
original, err := memory.DownloadAsset(ctx, asset.ID, nil)                                   // application/octet-stream
thumb, err := memory.DownloadAsset(ctx, asset.ID, &nulldull.DownloadAssetParams{Width: 256}) // resized WebP for images
```

Folder filters: leave `FolderID`/`ParentID` empty for no filter, set an ID for one folder, or set `Root: true` for the location root (sent as `root`). Go has no separate "undefined", so `Root` stands in for the `null` used by other SDKs.

### Locale: export catalogs

```go
formats, err := client.Locale.ListFormats(ctx) // json, world, world-cldr, xcstrings, apple-strings, android-xml

exported, err := client.Locale.Export(ctx, workspaceID, &nulldull.ExportParams{
	Format:    nulldull.FormatAndroidXML,
	Languages: []string{"en", "tr"},
	Status:    []nulldull.LocaleKeyStatus{nulldull.StatusApproved},
})
// exported.Files: values/strings.xml, values-tr/strings.xml
for _, file := range exported.Files {
	target := filepath.Join("app/src/main/res", filepath.FromSlash(file.Path))
	// Reject absolute paths and ".." before writing in real code.
	os.MkdirAll(filepath.Dir(target), 0o755)
	os.WriteFile(target, []byte(file.Content), 0o644)
}
```

The export is always JSON with text `Files` and is never an archive. `Format` defaults to `json`. Single-language formats give one file set per language; `xcstrings` gives one file holding every language. Exports are limited to 2,000 keys and 2 million characters.

## Pagination

Every `ListX` method returns one page with `Items` and `NextCursor`. Pass `NextCursor` back as `After` until it is `nil`:

```go
params := &nulldull.ListDocumentsParams{}
for {
	page, err := memory.ListDocuments(ctx, params)
	if err != nil {
		return err
	}
	// … page.Items
	if page.NextCursor == nil {
		break
	}
	params.After = *page.NextCursor
}
```

Every `IterateX` method returns an `iter.Seq2[T, error]` over the items of all pages, fetched lazily as you range; `break` stops early. An error is yielded once and ends the sequence. An empty page with a cursor is not the end (Grid search scans in windows), and the iterators handle that for you.

## Errors

Every failure is a `*nulldull.Error`:

```go
doc, err := client.Memory.GetDocument(ctx, "…")
var apiErr *nulldull.Error
if errors.As(err, &apiErr) {
	apiErr.Status     // HTTP status, or 0 for client-side errors
	apiErr.Code       // "FORBIDDEN", "NOT_FOUND", "RATE_LIMITED", "TIMEOUT", …
	apiErr.Detail     // e.g. "LOCALE_EXPORT_TOO_LARGE", or ""
	apiErr.Message    // also err.Error()
	apiErr.RequestID  // X-Request-Id or CF-Ray, for support
	apiErr.RetryAfter // *int seconds, on 429
	apiErr.Reason     // e.g. "PUBLIC_REQUESTS_PAUSED", or ""
	apiErr.RenewsAt   // ISO 8601 UTC time the paused allowance renews, or ""
	apiErr.Body       // the full JSON error body
}
```

`ABORTED`, `TIMEOUT` and `NETWORK_ERROR` errors wrap their cause, so `errors.Is(err, context.Canceled)` works.

| Code | Meaning |
| --- | --- |
| `INVALID_INPUT` (400) | A bad parameter. Locale errors add `Detail`. |
| `UNAUTHENTICATED`, `INVALID_KEY`, `KEY_REQUIRED` (401) | Missing, revoked or rotated key. |
| `FORBIDDEN` (403) | Missing scope or wrong workspace ID. Unreadable documents and folders also answer 403. |
| `NOT_FOUND` (404) | Missing or invisible resource, or a pool owned by another workspace. |
| `RATE_LIMITED` (429) | See `RetryAfter`. With `Reason` `PUBLIC_REQUESTS_PAUSED`, see below. |
| `SERVICE_UNAVAILABLE`, `NOT_CONFIGURED` (503) | Temporary failure, or a feature not configured in this environment. |
| `REQUEST_FAILED` | An HTTP error without a JSON `code`, including redirects. |
| `INVALID_ARGUMENT`, `WORKSPACE_REQUIRED`, `PRIVATE_KEY_REQUIRED` (0) | Caught before any request was sent. |
| `NETWORK_ERROR`, `TIMEOUT`, `ABORTED`, `INVALID_RESPONSE` (0) | Transport problems. |

### Paused public requests

When a Free workspace has used its monthly public requests, Grid delivery answers `429 RATE_LIMITED` with `Reason` and `Detail` `PUBLIC_REQUESTS_PAUSED`, `RenewsAt` (the first instant of the next UTC month) and a `Retry-After` until then, so the SDK returns it at once without retrying. `HEAD` requests count too. Delivery resumes about two and a half minutes after an upgrade, or when the month renews. Show a calm message instead of a generic error:

```go
page, err := client.Grid.GetPage(ctx, "my-blog", "welcome", nil)
if nulldull.IsPublicRequestsPaused(err) { // or apiErr.PublicRequestsPaused()
	// "This content is temporarily unavailable." Try again after apiErr.RenewsAt.
}
```

## Retries, timeouts and cancellation

Requests are retried up to 2 times (`WithMaxRetries`) on `429`, `502`, `503`, `504` and network errors:

- With `Retry-After` of 30 seconds or less, the SDK waits that long and retries.
- With a longer `Retry-After`, it returns the error at once with `RetryAfter` set.
- Otherwise it backs off 500 ms and then 1 s.

Each attempt times out after 30 seconds (`WithTimeout`), returning `TIMEOUT`, which is not retried. Cancelling the context, or reaching its deadline, returns `ABORTED`, also while waiting to retry. Redirects are never followed, so the key is never sent to another origin.

## Options

| Option | Default | |
| --- | --- | --- |
| `apiKey` (first argument) | required | `nd_pub_…` or `nd_sec_…` |
| `WithBaseURL` | `https://nulldull.com` | Point at another NullDull environment. |
| `WithWorkspaceID` | none | Required for Memory and Locale. |
| `WithTimeout` | `30 * time.Second` | Per attempt; `0` disables it. |
| `WithMaxRetries` | `2` | `0` disables retries. |
| `WithHTTPClient` | `&http.Client{}` | Proxies, custom transports or test mocks. The SDK uses a copy that never follows redirects and has no cookie jar. |
| `WithUserAgent` | none | Appended to `nulldull-sdk-go/0.1.0`. |
| `WithSleep` | real timer | Replaces the wait between retries, for tests. |

## Unknown fields

Response structs use Go field names with the API's JSON names. Fields the SDK does not model yet are kept in each struct's `Extra` map and written back by `json.Marshal`, so nothing is lost. Enum-like strings (`FileKind`, `LocaleKeyStatus`, …) accept values that have no constant yet.

## Testing

```sh
go test -race ./...   # unit and conformance tests (shared ../fixtures, mocked transport)

# Live tests, skipped unless set:
NULLDULL_PUBLIC_KEY=… NULLDULL_GRID_POOL=… go test -run TestLive ./...
NULLDULL_PRIVATE_KEY=… NULLDULL_WORKSPACE_ID=… go test -run TestLive ./...
# Optional: NULLDULL_LOCALE_SCOPE_ID, NULLDULL_BASE_URL
```

## License

[MIT](LICENSE) © 2026 NullDull
