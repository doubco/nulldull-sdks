import type {
  Asset,
  Document,
  DocumentSummary,
  GetAssetParams,
  GetPageParams,
  GridPage,
  GridPageList,
  ListAssetsParams,
  ListDocumentsParams,
  ListPagesParams,
  LocaleFormatList,
  Page,
  SearchParams,
  SearchResult,
} from "@nulldull/sdk";
import {
  useNullDullInfiniteQuery,
  useNullDullQuery,
  type InfiniteQueryOptions,
  type InfiniteQueryResult,
  type QueryOptions,
  type QueryResult,
} from "./query";

/** SDK params without the parts the hooks manage (`after`, `signal`). */
type Params<T> = Omit<T, "after" | "signal">;

/** An ID that may not be known yet: `null`, `undefined` or `""` keeps the hook idle. */
export type MaybeId = string | null | undefined;

export type UseGridPagesOptions = Params<ListPagesParams> & InfiniteQueryOptions<GridPageList>;
export type UseGridPageOptions = Params<GetPageParams> & QueryOptions<GridPage>;
export type UseMemoryDocumentsOptions = Params<ListDocumentsParams> & InfiniteQueryOptions<Page<DocumentSummary>>;
export type UseMemoryDocumentOptions = QueryOptions<Document>;
export type UseMemorySearchOptions = Params<SearchParams> & InfiniteQueryOptions<Page<SearchResult>>;
export type UseMemoryAssetsOptions = Params<ListAssetsParams> & InfiniteQueryOptions<Page<Asset>>;
export type UseMemoryAssetOptions = Params<GetAssetParams> & QueryOptions<Asset>;
export type UseLocaleFormatsOptions = QueryOptions<LocaleFormatList>;

/**
 * A pool's published pages, newest first, with `fetchNextPage()` for more.
 * `data.pages` holds each `GridPageList` (with `pool`); `data.items` all summaries so far.
 */
export function useGridPages(pool: MaybeId, options: UseGridPagesOptions = {}): InfiniteQueryResult<GridPageList> {
  const { enabled = true, initialData, ...params } = options;
  return useNullDullInfiniteQuery(
    ["grid.listPages", pool, params],
    (client, after, signal) => client.grid.listPages(pool as string, { ...params, after, signal }),
    { enabled: enabled && !!pool, initialData },
  );
}

/** One published page with its `document` and version-pinned `assets`, ready for `@nulldull/grid-react`. */
export function useGridPage(pool: MaybeId, slug: MaybeId, options: UseGridPageOptions = {}): QueryResult<GridPage> {
  const { enabled = true, initialData, ...params } = options;
  return useNullDullQuery(
    ["grid.getPage", pool, slug, params],
    (client, signal) => client.grid.getPage(pool as string, slug as string, { ...params, signal }),
    { enabled: enabled && !!pool && !!slug, initialData },
  );
}

/** Readable Memory documents (without content), 50 per page. Private key and `workspaceId` required. */
export function useMemoryDocuments(options: UseMemoryDocumentsOptions = {}): InfiniteQueryResult<Page<DocumentSummary>> {
  const { enabled = true, initialData, ...params } = options;
  return useNullDullInfiniteQuery(
    ["memory.listDocuments", params],
    (client, after, signal) => client.memory.listDocuments({ ...params, after, signal }),
    { enabled, initialData },
  );
}

/** A Memory document with its Markdown `content`. Private key and `workspaceId` required. */
export function useMemoryDocument(documentId: MaybeId, options: UseMemoryDocumentOptions = {}): QueryResult<Document> {
  const { enabled = true, initialData } = options;
  return useNullDullQuery(
    ["memory.getDocument", documentId],
    (client, signal) => client.memory.getDocument(documentId as string, { signal }),
    { enabled: enabled && !!documentId, initialData },
  );
}

/**
 * Literal Memory search, 20 results per page. Stays idle until `q` has at least 2 characters
 * (the server rejects shorter queries); debounce `q` yourself for search-as-you-type.
 */
export function useMemorySearch(q: string | null | undefined, options: UseMemorySearchOptions = {}): InfiniteQueryResult<Page<SearchResult>> {
  const { enabled, initialData, ...params } = options;
  const query = q ?? "";
  return useNullDullInfiniteQuery(
    ["memory.search", query, params],
    (client, after, signal) => client.memory.search(query, { ...params, after, signal }),
    { enabled: enabled ?? query.trim().length >= 2, initialData },
  );
}

/** Readable Memory assets with metadata, 50 per page. Private key and `workspaceId` required. */
export function useMemoryAssets(options: UseMemoryAssetsOptions = {}): InfiniteQueryResult<Page<Asset>> {
  const { enabled = true, initialData, ...params } = options;
  return useNullDullInfiniteQuery(
    ["memory.listAssets", params],
    (client, after, signal) => client.memory.listAssets({ ...params, after, signal }),
    { enabled, initialData },
  );
}

/** A Memory asset's metadata, optionally at `revisionId`. Private key and `workspaceId` required. */
export function useMemoryAsset(assetId: MaybeId, options: UseMemoryAssetOptions = {}): QueryResult<Asset> {
  const { enabled = true, initialData, ...params } = options;
  return useNullDullQuery(
    ["memory.getAsset", assetId, params],
    (client, signal) => client.memory.getAsset(assetId as string, { ...params, signal }),
    { enabled: enabled && !!assetId, initialData },
  );
}

/**
 * Locale export formats and their capabilities. Needs a private key with `locale:read`.
 * Run `locale.export` itself in a build script or server, not in a browser.
 */
export function useLocaleFormats(options: UseLocaleFormatsOptions = {}): QueryResult<LocaleFormatList> {
  const { enabled = true, initialData } = options;
  return useNullDullQuery(["locale.listFormats"], (client, signal) => client.locale.listFormats({ signal }), { enabled, initialData });
}
