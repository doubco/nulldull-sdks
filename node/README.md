# @nulldull/sdk

The official NullDull SDK for Node.js and browsers. It reads NullDull with **workspace API keys**:

- **Grid**: published pages, covers and assets.
- **Memory**: read-only access to documents, folders, search, tags and assets.
- **Locale**: export translation catalogs at build time.

> **Early access.** `0.1.0` may change before `1.0`. The SDK only reads data.

ESM and CommonJS, full TypeScript types, zero runtime dependencies. Runs on Node.js 18+, modern browsers, Deno, Bun and Cloudflare Workers (anything with `fetch`).

Documentation: <https://nulldull.com/docs> · Specification: [`SPEC.md`](https://github.com/doubco/nulldull-sdks/blob/main/SPEC.md)

## Install

```sh
npm install @nulldull/sdk
```

## Keys

Create keys in the NullDull app under **Workspace settings → API keys** (owners and admins).

| Key | Where | Scopes |
| --- | --- | --- |
| Public `nd_pub_…` | Browser and mobile bundles | `grid:published` |
| Private `nd_sec_…` | Servers and CI only | `grid:published`, `memory:read`, `locale:read` |

Memory and Locale also need your **workspace ID**, because a key cannot look up its own workspace. The workspace root location has the same ID.

## Quick start

```ts
import { NullDullClient } from "@nulldull/sdk";

const nulldull = new NullDullClient({
  apiKey: process.env.NULLDULL_PRIVATE_KEY!,   // or a public key for Grid only
  workspaceId: process.env.NULLDULL_WORKSPACE_ID, // needed for memory and locale
});
```

CommonJS works too: `const { NullDullClient } = require("@nulldull/sdk")`.

### Grid: published pages

```ts
const grid = new NullDullClient({ apiKey: "nd_pub_…" }).grid;

// One page of results (newest first)
const { pool, items, nextCursor } = await grid.listPages("my-blog", { locale: "en", limit: 20 });

// Every page, following cursors
for await (const summary of grid.iteratePages("my-blog", { q: "launch" })) {
  console.log(summary.title, summary.cover?.url);
}

// One page with its document and asset manifest
const page = await grid.getPage("my-blog", "hello-world");
page.document; // render with @nulldull/grid-react's GridRenderer
page.assets;   // [{ id, version, url, filename, mediaType, byteSize, checksum }]
```

Returned `cover.url` and `assets[].url` are absolute. With a public key they already carry `key=…`, so they work in `<img>`, CSS fonts and `<video>`, which cannot send headers. To resolve a URL yourself, call `grid.assetUrl(url)`. It adds a public key only to URLs on the API's own origin, and never adds a private key.

```ts
const file = await grid.downloadAsset(page.assets[0]); // { bytes, contentType, filename, size }
```

### Memory: read-only

```ts
const { memory } = nulldull;

const scopes = await memory.listScopes();
for await (const doc of memory.iterateDocuments({ scopeId: "…", tags: ["rules"] })) {
  console.log(doc.name, doc.labelKind);
}
const doc = await memory.getDocument("…");   // doc.content is the saved Markdown
const hits = await memory.search("release checklist", { scopeId: "…" });
const link = await memory.resolveLink(doc.id, "docs/setup.md#install"); // { status: "found", id, fragment }

const folders = await memory.listFolders({ scopeId: "…", parentId: null }); // null = top level
const unfiled = await memory.listDocuments({ folderId: null });             // null = location root

const asset = await memory.getAsset("…");
const original = await memory.downloadAsset(asset.id);                 // application/octet-stream
const thumb = await memory.downloadAsset(asset.id, { width: 256 });     // resized WebP for images
```

### Locale: export catalogs

```ts
import { mkdir, writeFile } from "node:fs/promises";
import { dirname, join } from "node:path";

const { locale } = nulldull;
const { items: formats } = await locale.listFormats(); // json, world, world-cldr, xcstrings, apple-strings, android-xml

const exported = await locale.export(workspaceId, {
  format: "android-xml",
  languages: ["en", "tr"],
  status: ["approved"],
});
// exported.files: [{ path: "values/strings.xml", ... }, { path: "values-tr/strings.xml", ... }]
for (const file of exported.files) {
  const target = join("app/src/main/res", file.path);
  await mkdir(dirname(target), { recursive: true });
  await writeFile(target, file.content);
}
```

The export is always JSON with text `files` and is never an archive. Single-language formats give one file set per language. `xcstrings` gives one file holding every language. Exports are limited to 2,000 keys and 2 million characters.

## Pagination

Every `listX` method returns one page, `{ items, nextCursor, … }`. Pass `nextCursor` back as `after`:

```ts
let after: string | undefined;
do {
  const page = await memory.listDocuments({ after });
  // …
  after = page.nextCursor ?? undefined;
} while (after);
```

Every `iterateX` method returns an async iterator over the items of all pages, fetched lazily. An empty page with a cursor is not the end (Grid search scans in windows), and the iterators handle that for you.

## Errors

Every failure is a `NullDullError`:

```ts
import { NullDullError } from "@nulldull/sdk";

try {
  await nulldull.memory.getDocument("…");
} catch (error) {
  if (error instanceof NullDullError) {
    error.status;     // HTTP status, or 0 for client-side errors
    error.code;       // "FORBIDDEN", "NOT_FOUND", "RATE_LIMITED", "TIMEOUT", …
    error.detail;     // e.g. "LOCALE_EXPORT_TOO_LARGE"
    error.message;
    error.requestId;  // CF-Ray, for support
    error.retryAfter; // seconds, on 429
    error.body;       // the full JSON error body
    error.reason;     // e.g. "PUBLIC_REQUESTS_PAUSED"
    error.renewsAt;   // ISO 8601 time the paused allowance renews
  }
}
```

### Paused public requests

When a workspace on the Free plan has used its monthly public requests, Grid reads of its pools answer `429 RATE_LIMITED` with `reason` and `detail` `PUBLIC_REQUESTS_PAUSED`, a `renewsAt` time (the start of the next UTC month) and a `Retry-After` until then. The SDK never retries it. Show a calm notice instead of the content:

```ts
import { isPublicRequestsPaused } from "@nulldull/sdk";

try {
  return await nulldull.grid.getPage("my-blog", slug);
} catch (error) {
  if (isPublicRequestsPaused(error)) return { paused: true, until: error.renewsAt };
  throw error;
}
```

Delivery resumes at `renewsAt`, or within a few minutes after the workspace upgrades.

| Code | Meaning |
| --- | --- |
| `INVALID_INPUT` (400) | A bad parameter. Locale errors add `detail`. |
| `UNAUTHENTICATED`, `INVALID_KEY`, `KEY_REQUIRED` (401) | Missing, revoked or rotated key. |
| `FORBIDDEN` (403) | Missing scope or wrong `workspaceId`. Unreadable documents and folders also answer 403. |
| `NOT_FOUND` (404) | Missing or invisible resource, or a pool owned by another workspace. |
| `RATE_LIMITED` (429) | See `retryAfter`. With `reason` `PUBLIC_REQUESTS_PAUSED`, the workspace's monthly public requests are used up (see below). |
| `SERVICE_UNAVAILABLE`, `NOT_CONFIGURED` (503) | Temporary failure, or a feature not configured in this environment. |
| `INVALID_ARGUMENT`, `WORKSPACE_REQUIRED`, `PRIVATE_KEY_REQUIRED` (0) | Caught before any request was sent. |
| `NETWORK_ERROR`, `TIMEOUT`, `ABORTED`, `INVALID_RESPONSE` (0) | Transport problems. |

## Retries and timeouts

Requests are retried up to `maxRetries` times (default 2) on `429`, `502`, `503`, `504` and network errors:

- With `Retry-After` of 30 seconds or less, the SDK waits that long and retries.
- With a longer `Retry-After`, it raises the error at once with `retryAfter` set.
- A paused public request allowance (`PUBLIC_REQUESTS_PAUSED`) is never retried.
- Otherwise it backs off 500 ms and then 1 s.

Each attempt times out after `timeout` ms (default 30000). Every method accepts an `AbortSignal`:

```ts
await nulldull.grid.getPage("my-blog", "hello", { signal: AbortSignal.timeout(5000) });
```

## Options

| Option | Default | |
| --- | --- | --- |
| `apiKey` | required | `nd_pub_…` or `nd_sec_…` |
| `baseUrl` | `https://nulldull.com` | Point at another NullDull environment. |
| `workspaceId` | none | Required for `memory` and `locale`. |
| `timeout` | `30000` | Milliseconds per attempt; `0` disables it. |
| `maxRetries` | `2` | `0` disables retries. |
| `fetch` | `globalThis.fetch` | Inject a custom or mocked `fetch`. |
| `userAgent` | none | Appended to `nulldull-sdk-node/0.1.0` (server runtimes only). |
| `dangerouslyAllowPrivateKeyInBrowser` | `false` | The client refuses a private key in a browser unless you set this. |

## Browsers

Use a **public** key in browsers. The SDK sends no `User-Agent` or cookies there, and refuses a private key unless `dangerouslyAllowPrivateKeyInBrowser` is set. Grid delivery allows cross-origin requests. Memory and Locale are for servers.

## Testing

```sh
npm test            # typecheck and unit/conformance tests (shared fixtures, mocked fetch)
npm run test:live   # live tests; set NULLDULL_PUBLIC_KEY + NULLDULL_GRID_POOL and/or
                    # NULLDULL_PRIVATE_KEY + NULLDULL_WORKSPACE_ID
```

## License

[MIT](LICENSE) © 2026 NullDull
