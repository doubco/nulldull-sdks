# NullDull SDKs

Official client libraries for reading NullDull with **workspace API keys**:

- **Grid**: published pages, covers and assets for your website or app.
- **Memory**: read-only access to documents, folders, search, tags and assets.
- **Locale**: export translation catalogs (JSON, World, Xcode String Catalog, `.strings`/`.stringsdict`, Android `strings.xml`) at build time.

> **Early access.** NullDull and these SDKs are in early access. Version `0.1.0` may still change before `1.0`. The SDKs only read data; they never write.

Documentation: <https://nulldull.com/docs>

## Keys

Owners and admins create keys in the NullDull app under **Workspace settings → API keys**.

| Key | Use it | Scopes |
| --- | --- | --- |
| Public `nd_pub_…` | In browser and mobile bundles | `grid:published` |
| Private `nd_sec_…` | On servers and in CI only | `grid:published`, `memory:read`, `locale:read` |

Memory and Locale calls also need your **workspace ID**, because a key cannot look up its own workspace.

## Languages

| Language | Directory | Package | Install |
| --- | --- | --- | --- |
| Node.js / TypeScript | [`node/`](node) | `@nulldull/sdk` | `npm install @nulldull/sdk` |
| React | [`react/`](react) | `@nulldull/react` | `npm install @nulldull/react @nulldull/sdk` |
| Python | [`python/`](python) | `nulldull` | `pip install nulldull` |
| Go | [`go/`](go) | `github.com/doubco/nulldull-sdks/go` | `go get github.com/doubco/nulldull-sdks/go@latest` |
| Swift | [`swift/`](swift) | `NullDull` (Swift Package Manager) | `.package(url: "https://github.com/doubco/nulldull-sdks", from: "0.1.0")` |
| Kotlin / Android | [`kotlin/`](kotlin) | `com.nulldull:nulldull-sdk` | `implementation("com.nulldull:nulldull-sdk:0.1.0")` |

### Grid renderers (alpha)

Native renderers for Grid documents, for apps that show published pages without a web view. They are in early access, separate from the SDK packages above and not yet released.

| Platform | Package | Install |
| --- | --- | --- |
| SwiftUI (iOS 16, macOS 13, tvOS 16, visionOS 1) | `NullDullGrid`, `NullDullGridUI` (Swift Package Manager) | `.package(url: "https://github.com/doubco/nulldull-sdks", from: "0.2.0")` |
| Jetpack Compose (Android minSdk 24) | `com.nulldull:nulldull-grid-compose` (with `com.nulldull:nulldull-grid-core`) | `implementation("com.nulldull:nulldull-grid-compose:0.1.0")` |

See the Grid renderer sections of [`swift/README.md`](swift/README.md#grid-renderer-alpha) and [`kotlin/README.md`](kotlin/README.md#grid-renderer-alpha).

Each directory has its own README with a quick start for Grid, Memory and Locale, errors and pagination. All six implement [`SPEC.md`](SPEC.md) and pass the same conformance fixtures.

### Quick look (Node)

```ts
import { NullDullClient } from "@nulldull/sdk";

const nulldull = new NullDullClient({ apiKey: process.env.NULLDULL_PUBLIC_KEY! });
const { items } = await nulldull.grid.listPages("my-blog", { limit: 10 });
```

See [`node/README.md`](node/README.md) for the full guide.

## Repository layout

- [`SPEC.md`](SPEC.md): the one contract every SDK implements. It covers methods, types, errors, retries, pagination and conformance.
- [`fixtures/`](fixtures): shared conformance cases and API responses that every SDK's tests reuse, and the Grid renderer fixtures in `fixtures/grid-renderer/` that the Swift and Kotlin renderers' tests reuse.
- `node/`, `react/`, `python/`, `go/`, `swift/`, `kotlin/`: one directory per language.

## Contributing a port

1. Read [`SPEC.md`](SPEC.md) completely.
2. Implement every method in its naming table, using your language's conventions.
3. Run every case in [`fixtures/manifest.json`](fixtures/manifest.json) against a mocked HTTP layer, and cover the Conformance list.
4. Add an optional live suite gated on `NULLDULL_PUBLIC_KEY`, `NULLDULL_PRIVATE_KEY`, `NULLDULL_WORKSPACE_ID` and `NULLDULL_GRID_POOL`.

Never commit API keys. Tests must not print key values.

## License

[MIT](LICENSE) © 2026 NullDull
