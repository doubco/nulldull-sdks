# @nulldull/react

React hooks for [NullDull](https://nulldull.com), on top of [`@nulldull/sdk`](../node). Read published Grid pages in your site or app, and read Memory and Locale formats in internal tools, with workspace API keys.

> **Early access.** Version 0.4.0 is in preparation. The hooks only read data.

- One provider, one hook per read call, each returning `{ data, error, isLoading, refetch }`.
- Paginated hooks add `fetchNextPage`, `hasNextPage` and `isFetchingNextPage`.
- In-flight requests are cancelled on unmount and when parameters change. No state updates after unmount.
- StrictMode-safe. SSR-safe: nothing is fetched during a server render, and every hook accepts `initialData`.
- No data-fetching library. React 18 and 19.

Documentation: <https://nulldull.com/docs>

## Install

```sh
npm install @nulldull/react @nulldull/sdk
```

The peer dependencies are `@nulldull/sdk` (`^0.1.0` or `^0.4.0`) and `react` (>=18). The SDK 0.4.0 types include `pageTargets`.

## Security: which key goes where

| Key | Where | What the hooks can read |
| --- | --- | --- |
| Public `nd_pub_…` | Browser and mobile bundles | Grid: `useGridPages`, `useGridPage` |
| Private `nd_sec_…` | Servers, CI and build scripts only | Memory and Locale (and Grid) |

**Only public keys belong in browser bundles.** Anything you put in client-side code, including `NEXT_PUBLIC_*` / `VITE_*` variables, is readable by every visitor. A private key acts as the member who created it.

Like the SDK, the provider refuses a private key when it runs in a browser (`INVALID_ARGUMENT`). The Memory and Locale hooks therefore only run in a browser in trusted, non-public environments where you opt in with `dangerouslyAllowPrivateKeyInBrowser` (a local-only internal tool, or a desktop app whose users already hold the key). For public websites, read Memory on the server with `@nulldull/sdk` and send the browser only what it needs.

## Provider

```tsx
import { NullDullProvider } from "@nulldull/react";

export function App() {
  return (
    <NullDullProvider apiKey={import.meta.env.VITE_NULLDULL_PUBLIC_KEY}>
      <Blog />
    </NullDullProvider>
  );
}
```

The provider takes every `NullDullClient` option (`apiKey`, `workspaceId`, `baseUrl`, `timeout`, `maxRetries`, `fetch`, …) and builds one client, rebuilt only when an option value changes. Pass a stable `fetch` (not an inline arrow) if you pass one. Or build the client yourself:

```tsx
import { NullDullClient } from "@nulldull/sdk";

const client = new NullDullClient({ apiKey: "nd_pub_…" });
<NullDullProvider client={client}>…</NullDullProvider>;
```

`useNullDull()` returns the client for direct SDK calls, such as `client.grid.assetUrl(url)` or `client.grid.downloadAsset(asset)`.

## Hooks

Every hook takes the SDK method's parameters plus two hook options:

- `enabled` (default `true`): `false` keeps the hook idle.
- `initialData`: shown without fetching on mount while the parameters stay the same (for paginated hooks: the first page).

IDs may be `null`, `undefined` or `""` while they are not known yet; the hook then stays idle. Parameters are compared by value, so passing a fresh `{ locale: "en" }` object each render does not refetch.

`error` is always a `NullDullError` from the SDK (`status`, `code`, `message`, `detail`, `reason`, `renewsAt`, `requestId`, `retryAfter`, `body`), or `null`. `isPublicRequestsPaused(error)` (from `@nulldull/sdk`) is true when the workspace has used its monthly public requests; show a calm notice then, since the content returns at `error.renewsAt` or after an upgrade. Hooks never refetch on their own, so a paused workspace is not asked again until `refetch()` or a parameter change. Cancellations are never reported as errors. `refetch()` cancels any request in flight and resolves when the new one settles; it never rejects.

`isLoading` is `true` while the first page (or the only resource) is loading, including the first render before the request starts. During a `refetch()` the previous `data` stays visible. When parameters change, `data` resets to `undefined` so you never show the previous page under a new slug.

### `useGridPages(pool, options?)` (public key)

Published pages, newest first. Options: `locale` (default `en`), `q`, `folderId`, `limit` (1–50), `enabled`, `initialData`.

```tsx
function Blog() {
  const { data, error, isLoading, fetchNextPage, hasNextPage, isFetchingNextPage } = useGridPages("my-blog", { limit: 10 });
  if (isLoading) return <p>Loading…</p>;
  if (error) return <p>Could not load posts ({error.code}).</p>;
  return (
    <>
      <ul>
        {data!.items.map((page) => (
          <li key={page.id}>
            {page.cover && <img src={page.cover.url} alt={page.cover.alt} />}
            <a href={`/blog/${page.slug}`}>{page.title}</a>
          </li>
        ))}
      </ul>
      {hasNextPage && (
        <button onClick={() => fetchNextPage()} disabled={isFetchingNextPage}>
          More
        </button>
      )}
    </>
  );
}
```

`data.items` is every summary loaded so far; `data.pages` is each `GridPageList` as returned (with `pool`). A page can be empty and still have a next cursor (Grid search scans a bounded window), so rely on `hasNextPage`, not on an empty page. Cover and asset URLs already carry the public key where needed, so they work in `<img>`.

### `useGridPage(pool, slug, options?)` (public key)

One published page with its `document`, version-pinned `assets` and optional `pageTargets` keyed by document-local alias. Options: `locale`, `enabled`, `initialData`.

```tsx
const { data: page, error, isLoading } = useGridPage("my-blog", slug, { locale: "en" });
```

### `useMemoryDocuments(options?)` (private key, `workspaceId`)

Documents without content, 50 per page. Options: `scopeId`, `folderId` (`null` for unfiled), `tags`, `kind`, `lifecycle`.

### `useMemoryDocument(documentId, options?)` (private key, `workspaceId`)

A document with its Markdown `content`. A missing or unreadable document is `403 FORBIDDEN`.

### `useMemorySearch(q, options?)` (private key, `workspaceId`)

Literal search, 20 per page. Options: `scopeId`, `tags`, `kind`, `lifecycle`. Stays idle until `q` has at least 2 characters (the server rejects shorter queries); pass `enabled` to override. Debounce `q` yourself for search-as-you-type: each change cancels the previous request.

### `useMemoryAssets(options?)` and `useMemoryAsset(assetId, options?)` (private key, `workspaceId`)

Assets with metadata (50 per page; options `scopeId`, `folderId`, `q`, `tags`), and one asset (option `revisionId`). Download bytes with `useNullDull().memory.downloadAsset(id, { width })` in an event handler.

### `useLocaleFormats(options?)` (private key, `workspaceId`)

Export formats and their capabilities.

**Locale export is a build-time server task.** There is deliberately no `useLocaleExport`: `locale.export` needs a private key, so run it in a build script, CI job or server with `@nulldull/sdk`, write the files into your app, and ship those. Never run it in a browser with a private key.

### Anything else: `useNullDullQuery` and `useNullDullInfiniteQuery`

The building blocks behind every hook, for SDK calls without a dedicated hook (`memory.getFolder`, `memory.listTags`, `memory.resolveLink`, …). Pass a key that identifies the request and a loader that forwards the `signal`:

```tsx
const folder = useNullDullQuery(["memory.getFolder", folderId], (client, signal) => client.memory.getFolder(folderId, { signal }), {
  enabled: !!folderId,
});

const tags = useNullDullInfiniteQuery(["memory.listTags", scopeId], (client, after, signal) =>
  client.memory.listTags({ scopeId, after, signal }),
);
```

The key is compared by value (object keys sorted, `undefined` dropped).

## Rendering Grid pages with `@nulldull/grid-react`

`@nulldull/grid-react` renders Grid documents; this package fetches them. They are independent: install both to use them together.

```tsx
import { useGridPage } from "@nulldull/react";
import { PublishedGridPage, type PublicGridPage } from "@nulldull/grid-react";
import "@nulldull/grid-react/style.css";

function Article({ slug }: { slug: string }) {
  const { data: page, error, isLoading } = useGridPage("my-blog", slug);
  if (isLoading) return <p>Loading…</p>;
  if (error) return <p>Not found.</p>;
  return <PublishedGridPage page={page as unknown as PublicGridPage} initialWidth={1024} />;
}
```

`PublishedGridPage` takes the delivered page (`page.document` plus `page.assets`) and maps each asset ID to its `url`. The SDK has already resolved those URLs against the API origin and added the public `key` for same-origin assets, exactly as grid-react's `createGridClient` does, so images, fonts and media load. For a document you got elsewhere, use `<GridRenderer document={page.document} resolveAsset={(id) => urls.get(id)} />`.

The cast is needed because the SDK types `document` as opaque JSON (its schema belongs to `@nulldull/grid-core`) while grid-react uses the full document type. Unlike `createGridClient`, the SDK does not validate the document; the renderer treats it as data and never executes custom-node content.

## SSR and Next.js

Hooks never fetch during a server render; they render the loading state (or `initialData`) and fetch after hydration. The package's build carries `"use client"`, so you can import the hooks from client components in the Next.js App Router.

The best pattern is to fetch on the server and pass the result as `initialData`, so the first HTML already has the content and the browser does not fetch again:

```tsx
// app/blog/[slug]/page.tsx (server component)
import { NullDullClient } from "@nulldull/sdk";
import { Article } from "./article";

const nulldull = new NullDullClient({ apiKey: process.env.NULLDULL_PUBLIC_KEY! });

export default async function Page({ params }: { params: Promise<{ slug: string }> }) {
  const { slug } = await params;
  const page = await nulldull.grid.getPage("my-blog", slug);
  return <Article slug={slug} initialPage={page} />;
}
```

```tsx
// app/blog/[slug]/article.tsx
"use client";
import { useGridPage, type UseGridPageOptions } from "@nulldull/react";

export function Article({ slug, initialPage }: { slug: string; initialPage: UseGridPageOptions["initialData"] }) {
  const { data: page } = useGridPage("my-blog", slug, { initialData: initialPage });
  return <h1>{page?.title}</h1>;
}
```

Wrap the client part of your tree in `<NullDullProvider apiKey={process.env.NEXT_PUBLIC_NULLDULL_PUBLIC_KEY}>` inside a client component (for example `app/providers.tsx`). If you only ever render server-fetched data, you do not need the hooks at all: use `@nulldull/sdk` in server components.

The same applies to Remix/React Router loaders, Astro islands and any SSR setup: load in the server data layer, pass `initialData`.

Notes:

- Do not put a private key in a provider that also renders in the browser. On the server the SDK allows it (there is no `window`), but the same props would then be serialised into the client bundle.
- Responses are `Cache-Control: no-store`; caching is up to your framework (for example Next.js `revalidate` on the server side).
- In development, StrictMode mounts effects twice. The first request is cancelled and the second wins; with `initialData` nothing is fetched.

## License

MIT
