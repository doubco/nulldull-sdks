import { NullDullError, type NullDullClient } from "@nulldull/sdk";
import { useCallback, useEffect, useRef, useState } from "react";
import { useNullDull } from "./context";

/** Options every hook accepts. */
export interface QueryOptions<T> {
  /** `false` skips fetching until it becomes `true`. Default `true`. */
  enabled?: boolean;
  /**
   * Data you already have, for example from a server render. While the query key is unchanged
   * the hook shows it and does not fetch on mount; `refetch()` or a key change loads fresh data.
   */
  initialData?: T;
}

export interface QueryResult<T> {
  data: T | undefined;
  /** Always a `NullDullError` (see `code` and `status`), or null. Cancellations are never reported. */
  error: NullDullError | null;
  /** A request for the first page (or the only resource) is in flight, or about to start. */
  isLoading: boolean;
  /** Loads again, cancelling any request in flight. Resolves when done; never rejects. */
  refetch: () => Promise<void>;
}

/** Any SDK list response: `{ items, nextCursor }` plus extra fields such as Grid's `pool`. */
export interface PageLike {
  items: readonly unknown[];
  nextCursor: string | null;
}

export interface InfiniteData<P extends PageLike> {
  /** Every loaded page, exactly as the SDK returned it. */
  pages: P[];
  /** The items of every loaded page, in order. */
  items: P["items"][number][];
}

export interface InfiniteQueryOptions<P extends PageLike> extends QueryOptions<P> {
  /** For paginated hooks, `initialData` is the first page (for example from a server render). */
  initialData?: P;
}

export interface InfiniteQueryResult<P extends PageLike> extends QueryResult<InfiniteData<P>> {
  /** Loads the page after the last one. Does nothing without a next page or while one is loading. */
  fetchNextPage: () => Promise<void>;
  /** The last loaded page has a `nextCursor`. An empty page with a cursor is not the end. */
  hasNextPage: boolean;
  isFetchingNextPage: boolean;
}

export type QueryKey = readonly unknown[];
export type Loader<T> = (client: NullDullClient, signal: AbortSignal) => Promise<T>;
export type PageLoader<P> = (client: NullDullClient, after: string | undefined, signal: AbortSignal) => Promise<P>;

/** A deterministic string for a query key: object keys are sorted, `undefined` and `signal` dropped. */
export function stableKey(value: unknown): string {
  return JSON.stringify(value, (name, item: unknown) => {
    if (item && typeof item === "object" && !Array.isArray(item)) {
      const record = item as Record<string, unknown>;
      const sorted: Record<string, unknown> = {};
      for (const key of Object.keys(record).sort())
        if (record[key] !== undefined && key !== "signal") sorted[key] = record[key];
      return sorted;
    }
    return name === "signal" ? undefined : item;
  });
}

function toNullDullError(error: unknown): NullDullError {
  if (error instanceof NullDullError) return error;
  return new NullDullError({
    status: 0,
    code: "REQUEST_FAILED",
    message: error instanceof Error ? error.message : "NullDull request failed.",
    cause: error,
  });
}

interface Snapshot<T> {
  key: string;
  data: T | undefined;
  error: NullDullError | null;
  loading: boolean;
}

/**
 * The building block of every resource hook: runs `load` for `key` after mount and whenever the
 * key or client changes, cancels the previous request, and never updates state after unmount.
 * Use it for SDK calls without a dedicated hook, such as `memory.getFolder` or `memory.resolveLink`.
 *
 * ```ts
 * const folder = useNullDullQuery(["memory.getFolder", id], (client, signal) => client.memory.getFolder(id, { signal }));
 * ```
 */
export function useNullDullQuery<T>(key: QueryKey, load: Loader<T>, options: QueryOptions<T> = {}): QueryResult<T> {
  const client = useNullDull();
  const enabled = options.enabled ?? true;
  const hash = stableKey(key);
  const [snapshot, setSnapshot] = useState<Snapshot<T>>(() => ({ key: hash, data: options.initialData, error: null, loading: false }));
  const loadRef = useRef(load);
  loadRef.current = load;
  const initialKey = useRef<string | null>(options.initialData !== undefined ? hash : null);
  const controller = useRef<AbortController | null>(null);
  const mounted = useRef(false);

  const run = useCallback(async () => {
    initialKey.current = null;
    controller.current?.abort();
    const current = new AbortController();
    controller.current = current;
    setSnapshot((s) => ({ key: hash, data: s.key === hash ? s.data : undefined, error: null, loading: true }));
    try {
      const data = await loadRef.current(client, current.signal);
      if (!current.signal.aborted) setSnapshot({ key: hash, data, error: null, loading: false });
    } catch (error) {
      if (!current.signal.aborted)
        setSnapshot((s) => ({ key: hash, data: s.key === hash ? s.data : undefined, error: toNullDullError(error), loading: false }));
    } finally {
      if (controller.current === current) controller.current = null;
    }
  }, [client, hash]);

  useEffect(() => {
    mounted.current = true;
    if (!enabled) setSnapshot((s) => (s.loading ? { ...s, loading: false } : s));
    else if (initialKey.current !== hash) void run();
    return () => {
      mounted.current = false;
      controller.current?.abort();
      controller.current = null;
    };
  }, [run, enabled, hash]);

  const refetch = useCallback(() => (mounted.current ? run() : Promise.resolve()), [run]);
  const view = snapshot.key === hash ? snapshot : { data: undefined, error: null, loading: false };
  return {
    data: view.data,
    error: view.error,
    isLoading: view.loading || (enabled && view.data === undefined && view.error === null),
    refetch,
  };
}

interface PagesSnapshot<P> {
  key: string;
  pages: P[] | undefined;
  error: NullDullError | null;
  loading: boolean;
  fetchingNext: boolean;
}

/**
 * The paginated building block: loads the first page for `key`, then appends pages with
 * `fetchNextPage()` by sending the last `nextCursor` as `after` (SPEC.md section 7).
 *
 * ```ts
 * const tags = useNullDullInfiniteQuery(["memory.listTags", scopeId], (client, after, signal) =>
 *   client.memory.listTags({ scopeId, after, signal }));
 * ```
 */
export function useNullDullInfiniteQuery<P extends PageLike>(
  key: QueryKey,
  load: PageLoader<P>,
  options: InfiniteQueryOptions<P> = {},
): InfiniteQueryResult<P> {
  const client = useNullDull();
  const enabled = options.enabled ?? true;
  const hash = stableKey(key);
  const [snapshot, setSnapshot] = useState<PagesSnapshot<P>>(() => ({
    key: hash,
    pages: options.initialData !== undefined ? [options.initialData] : undefined,
    error: null,
    loading: false,
    fetchingNext: false,
  }));
  const loadRef = useRef(load);
  loadRef.current = load;
  const snapshotRef = useRef(snapshot);
  snapshotRef.current = snapshot;
  const initialKey = useRef<string | null>(options.initialData !== undefined ? hash : null);
  const first = useRef<AbortController | null>(null);
  const next = useRef<AbortController | null>(null);
  const mounted = useRef(false);

  const abortAll = () => {
    first.current?.abort();
    next.current?.abort();
    first.current = null;
    next.current = null;
  };

  const run = useCallback(async () => {
    initialKey.current = null;
    abortAll();
    const current = new AbortController();
    first.current = current;
    setSnapshot((s) => ({
      key: hash,
      pages: s.key === hash ? s.pages : undefined,
      error: null,
      loading: true,
      fetchingNext: false,
    }));
    try {
      const page = await loadRef.current(client, undefined, current.signal);
      if (!current.signal.aborted) setSnapshot({ key: hash, pages: [page], error: null, loading: false, fetchingNext: false });
    } catch (error) {
      if (!current.signal.aborted)
        setSnapshot((s) => ({
          key: hash,
          pages: s.key === hash ? s.pages : undefined,
          error: toNullDullError(error),
          loading: false,
          fetchingNext: false,
        }));
    } finally {
      if (first.current === current) first.current = null;
    }
  }, [client, hash]);

  const fetchNextPage = useCallback(async () => {
    const s = snapshotRef.current;
    const last = s.key === hash ? s.pages?.[s.pages.length - 1] : undefined;
    if (!mounted.current || !last || last.nextCursor === null || s.loading || next.current) return;
    const cursor = last.nextCursor;
    const current = new AbortController();
    next.current = current;
    setSnapshot((prev) => ({ ...prev, error: null, fetchingNext: true }));
    try {
      const page = await loadRef.current(client, cursor, current.signal);
      if (current.signal.aborted) return;
      if (page.nextCursor === cursor)
        throw new NullDullError({ status: 0, code: "INVALID_RESPONSE", message: "Pagination did not advance: the API returned the same cursor again." });
      setSnapshot((prev) => ({ ...prev, pages: [...(prev.pages ?? []), page], fetchingNext: false }));
    } catch (error) {
      if (!current.signal.aborted) setSnapshot((prev) => ({ ...prev, error: toNullDullError(error), fetchingNext: false }));
    } finally {
      if (next.current === current) next.current = null;
    }
  }, [client, hash]);

  useEffect(() => {
    mounted.current = true;
    if (!enabled) setSnapshot((s) => (s.loading || s.fetchingNext ? { ...s, loading: false, fetchingNext: false } : s));
    else if (initialKey.current !== hash) void run();
    return () => {
      mounted.current = false;
      abortAll();
    };
  }, [run, enabled, hash]);

  const refetch = useCallback(() => (mounted.current ? run() : Promise.resolve()), [run]);
  const view = snapshot.key === hash ? snapshot : { pages: undefined, error: null, loading: false, fetchingNext: false };
  const pages = view.pages;
  const data = useStableData(pages);
  const last = pages?.[pages.length - 1];
  return {
    data,
    error: view.error,
    isLoading: view.loading || (enabled && pages === undefined && view.error === null),
    refetch,
    fetchNextPage,
    hasNextPage: last !== undefined && last.nextCursor !== null && last.nextCursor !== undefined,
    isFetchingNextPage: view.fetchingNext,
  };
}

/** Keeps `data` referentially stable while the page list is unchanged. */
function useStableData<P extends PageLike>(pages: P[] | undefined): InfiniteData<P> | undefined {
  const cache = useRef<{ pages: P[]; data: InfiniteData<P> } | null>(null);
  if (!pages) return undefined;
  if (cache.current?.pages !== pages)
    cache.current = { pages, data: { pages, items: pages.flatMap((page) => page.items as P["items"][number][]) } };
  return cache.current.data;
}
