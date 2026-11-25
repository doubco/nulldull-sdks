# nulldull

The official NullDull SDK for Python. It reads NullDull with **workspace API keys**:

- **Grid**: published pages, covers and assets.
- **Memory**: read-only access to documents, folders, search, tags and assets.
- **Locale**: export translation catalogs at build time.

> **Early access.** Version 0.4.0 is in preparation. The SDK only reads data.

Sync and asyncio clients, full type hints (`py.typed`), one runtime dependency ([httpx](https://www.python-httpx.org)). Python 3.9+.

Documentation: <https://nulldull.com/docs> · Specification: [`SPEC.md`](https://github.com/doubco/nulldull-sdks/blob/main/SPEC.md)

## Install

```sh
pip install nulldull
# or
uv add nulldull
```

## Keys

Create keys in the NullDull app under **Workspace settings → API keys** (owners and admins).

| Key | Where | Scopes |
| --- | --- | --- |
| Public `nd_pub_…` | Browser and mobile bundles | `grid:published` |
| Private `nd_sec_…` | Servers and CI only | `grid:published`, `memory:read`, `locale:read` |

Memory and Locale also need your **workspace ID**, because a key cannot look up its own workspace. The workspace root location has the same ID.

## Quick start

```python
import os
from nulldull import NullDull

nulldull = NullDull(
    os.environ["NULLDULL_PRIVATE_KEY"],  # or a public key for Grid only
    workspace_id=os.environ.get("NULLDULL_WORKSPACE_ID"),  # needed for memory and locale
)
```

The client is safe to share between threads. Use it as a context manager, or call `nulldull.close()`, to release its connection pool.

### asyncio

`AsyncNullDull` has the same methods; await them and use `async for` with the iterators:

```python
from nulldull import AsyncNullDull

async with AsyncNullDull(os.environ["NULLDULL_PUBLIC_KEY"]) as nulldull:
    page = await nulldull.grid.get_page("my-blog", "hello-world")
    async for summary in nulldull.grid.iterate_pages("my-blog"):
        print(summary["title"])
```

Responses are the API's JSON objects as plain `dict`s, with the API's own camelCase keys (`nextCursor`, `publishedAt`). They are typed with `TypedDict`s in `nulldull.types`. Unknown fields and enum values are kept as they are.

### Grid: published pages

```python
grid = NullDull("nd_pub_…").grid

# One page of results (newest first). locale defaults to "en".
result = grid.list_pages("my-blog", locale="en", limit=20)
result["pool"], result["items"], result["nextCursor"]

# Every page, following cursors
for summary in grid.iterate_pages("my-blog", q="launch"):
    cover = summary.get("cover")
    print(summary["title"], cover["url"] if cover else None)

# One page with its document and asset manifest
page = grid.get_page("my-blog", "hello-world")
page["document"]  # opaque JSON; render it with @nulldull/grid-react's GridRenderer
page.get("pageTargets", {}).get("~1")  # current readable target for this document's alias
page["assets"]  # [{"id", "version", "url", "filename", "mediaType", "byteSize", "checksum"}]
```

Returned `cover.url` and `assets[].url` are absolute. With a public key they carry `key=…`, so they work in `<img>`, CSS fonts and `<video>`, which cannot send headers. To resolve a URL yourself, call `grid.asset_url(url)`. It adds a public key only to URLs on the API's own origin, and never adds a private key.

```python
file = grid.download_asset(page["assets"][0])  # Download(bytes, content_type, filename, size)
```

`download_asset` sends `Authorization` only to the API's own origin.

### Memory: read-only

```python
memory = nulldull.memory

scopes = memory.list_scopes()
for doc in memory.iterate_documents(scope_id="…", tags=["rules"]):
    print(doc["name"], doc["labelKind"])

doc = memory.get_document("…")  # doc["content"] is the saved Markdown
hits = memory.search("release checklist", scope_id="…")
link = memory.resolve_link(doc["id"], "docs/setup.md#install")  # {"status": "found", "id", "fragment"}

folders = memory.list_folders(scope_id="…", parent_id=None)  # None = top level
unfiled = memory.list_documents(folder_id=None)  # None = location root
everything = memory.list_documents()  # leave it out: no folder filter

asset = memory.get_asset("…")
original = memory.download_asset(asset["id"])  # application/octet-stream
thumb = memory.download_asset(asset["id"], width=256)  # resized WebP for images
```

### Locale: export catalogs

```python
from pathlib import Path

locale = nulldull.locale
formats = locale.list_formats()["items"]  # json, world, world-cldr, xcstrings, apple-strings, android-xml

exported = locale.export(
    workspace_id,  # the location that holds the catalog
    format="android-xml",  # default "json"
    languages=["en", "tr"],  # default: every configured language
    status=["approved"],  # default: every status
)
# exported["files"]: [{"path": "values/strings.xml", ...}, {"path": "values-tr/strings.xml", ...}]
out = Path("app/src/main/res").resolve()
for file in exported["files"]:
    target = (out / file["path"]).resolve()
    if out not in target.parents:
        raise ValueError(f"unsafe path {file['path']!r}")
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_text(file["content"], encoding="utf-8")
```

The export is always JSON with text `files` and is never an archive. Single-language formats give one file set per language. `xcstrings` gives one file holding every language. Exports are limited to 2,000 keys and 2 million characters.

## Pagination

Every `list_*` method returns one page, `{"items": [...], "nextCursor": ...}`. Pass `nextCursor` back as `after`:

```python
after = None
while True:
    page = memory.list_documents(after=after)
    ...
    after = page["nextCursor"]
    if after is None:
        break
```

Every `iterate_*` method returns a lazy iterator (an async iterator on `AsyncNullDull`) over the items of all pages. An empty page with a cursor is not the end (Grid search scans in windows), and the iterators handle that for you. If the API ever returns the same cursor twice, iteration stops with `INVALID_RESPONSE`.

## Errors

Every failure is a `NullDullError`:

```python
from nulldull import NullDullError

try:
    nulldull.memory.get_document("…")
except NullDullError as error:
    error.status  # HTTP status, or 0 for client-side errors
    error.code  # "FORBIDDEN", "NOT_FOUND", "RATE_LIMITED", "TIMEOUT", …
    error.detail  # e.g. "LOCALE_EXPORT_TOO_LARGE"
    error.message  # also str(error)
    error.request_id  # X-Request-Id or CF-Ray, for support
    error.retry_after  # seconds, on 429
    error.reason  # e.g. "PUBLIC_REQUESTS_PAUSED", or None
    error.renews_at  # ISO 8601 UTC time the paused allowance renews, or None
    error.body  # the full JSON error body
```

| Code | Meaning |
| --- | --- |
| `INVALID_INPUT` (400) | A bad parameter. Locale errors add `detail`. |
| `UNAUTHENTICATED`, `INVALID_KEY`, `KEY_REQUIRED` (401) | Missing, revoked or rotated key. |
| `FORBIDDEN` (403) | Missing scope or wrong `workspace_id`. Unreadable documents and folders also answer 403. |
| `NOT_FOUND` (404) | Missing or invisible resource, or a pool owned by another workspace. |
| `RATE_LIMITED` (429) | See `retry_after`. With `reason` `PUBLIC_REQUESTS_PAUSED`, see below. |
| `SERVICE_UNAVAILABLE`, `NOT_CONFIGURED` (503) | Temporary failure, or a feature not configured in this environment. |
| `REQUEST_FAILED` | A non-JSON error body, or a redirect (redirects are never followed). |
| `INVALID_ARGUMENT`, `WORKSPACE_REQUIRED`, `PRIVATE_KEY_REQUIRED` (0) | Caught before any request was sent. |
| `NETWORK_ERROR`, `TIMEOUT`, `INVALID_RESPONSE` (0) | Transport problems. |

### Paused public requests

When a Free workspace has used its monthly public requests, Grid delivery answers `429 RATE_LIMITED` with `reason` and `detail` `PUBLIC_REQUESTS_PAUSED`, `renews_at` (the first instant of the next UTC month) and a `Retry-After` until then, so the SDK raises it at once without retrying. `HEAD` requests count too. Delivery resumes about two and a half minutes after an upgrade, or when the month renews. Show a calm message instead of a generic error:

```python
from nulldull import is_public_requests_paused

try:
    page = nulldull.grid.get_page("my-blog", "welcome")
except NullDullError as error:
    if is_public_requests_paused(error):  # or error.public_requests_paused
        ...  # "This content is temporarily unavailable." Try again after error.renews_at.
    else:
        raise
```

## Retries and timeouts

Requests are retried up to `max_retries` times (default 2) on `429`, `502`, `503`, `504` and network errors:

- With `Retry-After` of 30 seconds or less, the SDK waits that long and retries.
- With a longer `Retry-After`, it raises the error at once with `retry_after` set.
- Otherwise it backs off 0.5 s and then 1 s.

Timeouts are not retried. Each attempt times out after `timeout` seconds (default 30). With `AsyncNullDull`, cancel a call the asyncio way (`asyncio.timeout`, `task.cancel()`); the SDK lets `asyncio.CancelledError` propagate.

## Options

| Option | Default | |
| --- | --- | --- |
| `api_key` | required | `nd_pub_…` or `nd_sec_…` |
| `base_url` | `https://nulldull.com` | Point at another NullDull environment. |
| `workspace_id` | none | Required for `memory` and `locale`. |
| `timeout` | `30.0` | Seconds per attempt; `0` or `None` disables it. |
| `max_retries` | `2` | `0` disables retries. |
| `transport` | httpx default | An `httpx.BaseTransport` (`httpx.AsyncBaseTransport` for async), e.g. `httpx.MockTransport` in tests. |
| `http_client` | none | Your own `httpx.Client` / `httpx.AsyncClient`. The SDK does not close it. |
| `user_agent` | none | Appended to `nulldull-sdk-python/0.4.0`. |

The SDK sends only `Authorization`, `Accept` and `User-Agent`, never cookies, and does not follow redirects.

## Testing

```sh
uv sync
uv run pytest            # unit and conformance tests (shared fixtures, httpx.MockTransport)
uv run mypy && uv run ruff check .

# Live tests; set NULLDULL_PUBLIC_KEY + NULLDULL_GRID_POOL and/or
# NULLDULL_PRIVATE_KEY + NULLDULL_WORKSPACE_ID (optional NULLDULL_BASE_URL, NULLDULL_LOCALE_SCOPE_ID)
uv run pytest tests/test_live.py
```

## License

[MIT](https://github.com/doubco/nulldull-sdks/blob/main/python/LICENSE) © 2026 NullDull
