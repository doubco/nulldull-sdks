# Shared fixtures

Conformance data reused by every SDK's test suite. See [SPEC.md, section 11](../SPEC.md#11-conformance) for the format.

- `manifest.json`: the cases. Each case gives the client config, the canonical call, the exact HTTP requests expected with canned responses, and the expected result or error.
- `grid/`, `memory/`, `locale/`: response bodies, shaped exactly like the API handlers' output. Locale exports were produced by the real codecs.
- `errors/`: error bodies (`{code, message?, detail?, ...}`).
- `grid-renderer/`: fixtures for the native Grid renderers (Swift `NullDullGrid`/`NullDullGridUI`, Kotlin `nulldull-grid-core`/`nulldull-grid-compose`), not for the SDK conformance cases. They are generated from the canonical TypeScript Grid packages in the NullDull app repository and copied here unchanged; do not edit them by hand.
  - `documents/*.json`: 68 documents, each normalized by `validateGrid`.
  - `golden/layout.json`: layout geometry for every document at 280, 320, 390, 600, 640, 768, 1024 and 1440 points. Flowing text uses a deterministic stub instead of font measurement (`stubTextHeight`, in IEEE-754 doubles: `pad = padding ?? 8`, `inner = max(1, width - 2*pad)`, `perLine = max(1, floor(inner / (fontSize*0.5)))`, `lines = max(1, ceil(utf16Length(text) / perLine))`, `height = 2*pad + lines * fontSize * (lineHeight ?? 1.2)`, where `width` is the node's outer width).
  - `validation/cases.json`: `validateGrid` inputs with the normalized output or the exact error message. `validation/urls.json` and `validation/svg.json`: URL and SVG safety rules.
  - `delivery/*.json`: public Grid delivery API samples for the renderers' content clients.
  - `icons/grid-icons.json`: the shared icon catalog as path data (the Kotlin renderer generates its icons from it).

The page-link corpus in `grid-renderer/page-links/published.json` contains the 17 published documents produced by `snapshotGridPageLinks` from `packages/domain/test/grid-page-link-corpus.ts` in the app repository. Its final case reaches the 180,000-byte document limit and the 16,000-character text limit. `page-links/routes.json` records the React resolver’s output for URL safety cases. Swift and Android use the exact `href`. With `jvmDefaultDeclines: true`, the core-only JVM must decline the link, never rewrite it. All other JVM results must match `href` exactly. Cases marked `external` also exercise direct HTTP(S) links. `grid/page-links.json` and `grid-renderer/page-links/legacy.json` exercise delivery with and without the extension.

The keys and IDs are fake. Never put real keys here.
