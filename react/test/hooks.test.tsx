import { NullDullClient, NullDullError, isPublicRequestsPaused, type GridPage, type GridPageList } from "@nulldull/sdk";
import { act, cleanup, render, renderHook, screen, waitFor } from "@testing-library/react";
import { StrictMode } from "react";
import { afterEach, describe, expect, it } from "vitest";
import {
  NullDullProvider,
  stableKey,
  useGridPage,
  useGridPages,
  useLocaleFormats,
  useMemoryAsset,
  useMemoryAssets,
  useMemoryDocument,
  useMemoryDocuments,
  useMemorySearch,
  useNullDull,
  useNullDullQuery,
} from "../src";
import { config, deferred, fixture, fromFixture, json, makeClient, mockFetch, wrapperFor } from "./support";

afterEach(cleanup);

const PAGE_PATH = "/api/grid/v1/pools/nulldull-blog/pages/context-that-survives-the-chat";
const WS = `/api/platform/workspaces/${config.workspaceId}`;

describe("provider", () => {
  it("builds a memoised client from options", () => {
    const { fetch } = mockFetch();
    const seen: NullDullClient[] = [];
    function Probe() {
      seen.push(useNullDull());
      return null;
    }
    const tree = (n: number) => (
      <NullDullProvider apiKey={config.publicKey} baseUrl="https://example.com/" fetch={fetch}>
        <Probe key="probe" />
        <span>{n}</span>
      </NullDullProvider>
    );
    const { rerender } = render(tree(1));
    rerender(tree(2));
    expect(seen).toHaveLength(2);
    expect(seen[0]).toBe(seen[1]);
    expect(seen[0]!.baseUrl).toBe("https://example.com");
    expect(seen[0]!.keyKind).toBe("public");
  });

  it("uses a client passed in", () => {
    const client = makeClient("public", mockFetch().fetch);
    const { result } = renderHook(() => useNullDull(), { wrapper: wrapperFor(client) });
    expect(result.current).toBe(client);
  });

  it("refuses a private key in the browser, like the SDK", () => {
    const original = console.error;
    console.error = () => {};
    try {
      expect(() => render(<NullDullProvider apiKey={config.privateKey} fetch={mockFetch().fetch} />)).toThrow(/private/i);
    } finally {
      console.error = original;
    }
  });

  it("useNullDull throws outside a provider", () => {
    const original = console.error;
    console.error = () => {};
    try {
      expect(() => renderHook(() => useNullDull())).toThrow(NullDullError);
    } finally {
      console.error = original;
    }
  });
});

describe("stableKey", () => {
  it("ignores object key order, undefined values and signal", () => {
    const signal = new AbortController().signal;
    expect(stableKey(["a", { b: 1, a: [2, { y: 1, x: undefined }] }])).toBe(stableKey(["a", { a: [2, { y: 1 }], b: 1, signal }]));
    expect(stableKey([{ q: "a" }])).not.toBe(stableKey([{ q: "b" }]));
  });
});

describe("useGridPage", () => {
  it("returns the current published targets by document alias", async () => {
    const mock = mockFetch([fromFixture("grid/page-links.json")]);
    const { result } = renderHook(() => useGridPage("manual", "source"), {
      wrapper: wrapperFor(makeClient("public", mock.fetch)),
    });
    await waitFor(() => expect(result.current.data?.pageTargets?.["~1"]).toEqual({
      entryId: "guide", published: true, pool: "manual", slug: "getting-started", locale: "en",
    }));
  });

  it("goes from loading to success with normalised asset URLs", async () => {
    const mock = mockFetch([fromFixture("grid/page.json")]);
    const { result } = renderHook(() => useGridPage("nulldull-blog", "context-that-survives-the-chat"), {
      wrapper: wrapperFor(makeClient("public", mock.fetch)),
    });
    expect(result.current.isLoading).toBe(true);
    expect(result.current.data).toBeUndefined();
    await waitFor(() => expect(result.current.isLoading).toBe(false));
    expect(result.current.error).toBeNull();
    expect(result.current.data?.slug).toBe("context-that-survives-the-chat");
    expect(result.current.data?.assets[0]?.url).toMatch(/^https:\/\/nulldull\.com\/.*key=nd_pub_/);
    expect(mock.requests).toHaveLength(1);
    expect(mock.requests[0]!.url.pathname).toBe(PAGE_PATH);
    expect(mock.requests[0]!.url.searchParams.get("locale")).toBe("en");
    expect(new Headers(mock.requests[0]!.init.headers).get("authorization")).toBe(`Bearer ${config.publicKey}`);
  });

  it("maps HTTP errors to NullDullError with every field", async () => {
    const mock = mockFetch([fromFixture("errors/not-found.json", 404, { "cf-ray": "ray-123" })]);
    const { result } = renderHook(() => useGridPage("nulldull-blog", "missing"), { wrapper: wrapperFor(makeClient("public", mock.fetch)) });
    await waitFor(() => expect(result.current.error).not.toBeNull());
    const error = result.current.error!;
    expect(error).toBeInstanceOf(NullDullError);
    expect(error.status).toBe(404);
    expect(error.code).toBe("NOT_FOUND");
    expect(error.message).toBe("Resource not found.");
    expect(error.requestId).toBe("ray-123");
    expect(result.current.isLoading).toBe(false);
    expect(result.current.data).toBeUndefined();
  });

  it("reports a paused public request allowance once, with its reason and renewal time", async () => {
    const mock = mockFetch([fromFixture("errors/public-requests-paused.json", 429, { "retry-after": "691200" })]);
    const { result } = renderHook(() => useGridPage("nulldull-blog", "missing"), { wrapper: wrapperFor(makeClient("public", mock.fetch)) });
    await waitFor(() => expect(result.current.error).not.toBeNull());
    const error = result.current.error!;
    expect(isPublicRequestsPaused(error)).toBe(true);
    expect(error.reason).toBe("PUBLIC_REQUESTS_PAUSED");
    expect(error.renewsAt).toBe("2026-12-01T00:00:00.000Z");
    expect(error.retryAfter).toBe(691200);
    expect(mock.requests).toHaveLength(1);
  });

  it("reports client-side validation errors without a request", async () => {
    const mock = mockFetch();
    const { result } = renderHook(() => useGridPage("Not A Pool", "x"), { wrapper: wrapperFor(makeClient("public", mock.fetch)) });
    await waitFor(() => expect(result.current.error?.code).toBe("INVALID_ARGUMENT"));
    expect(result.current.error?.status).toBe(0);
    expect(mock.requests).toHaveLength(0);
  });

  it("stays idle without a slug or when disabled", async () => {
    const mock = mockFetch();
    const wrapper = wrapperFor(makeClient("public", mock.fetch));
    const a = renderHook(() => useGridPage("nulldull-blog", undefined), { wrapper });
    const b = renderHook(() => useGridPage("nulldull-blog", "x", { enabled: false }), { wrapper });
    await act(async () => {});
    expect(a.result.current.isLoading).toBe(false);
    expect(b.result.current.isLoading).toBe(false);
    expect(mock.requests).toHaveLength(0);
  });

  it("refetches when params change and drops the stale result", async () => {
    const slow = deferred(() => fromFixture("grid/page.json"));
    const mock = mockFetch([slow.reply, json({ ...fixture<GridPage>("grid/page.json"), slug: "second", locale: "tr" })]);
    const { result, rerender } = renderHook(({ slug, locale }) => useGridPage("nulldull-blog", slug, { locale }), {
      wrapper: wrapperFor(makeClient("public", mock.fetch)),
      initialProps: { slug: "first", locale: "en" },
    });
    await waitFor(() => expect(mock.requests).toHaveLength(1));
    rerender({ slug: "second", locale: "tr" });
    expect(result.current.data).toBeUndefined();
    expect(result.current.isLoading).toBe(true);
    await waitFor(() => expect(result.current.data?.slug).toBe("second"));
    expect(mock.requests[0]!.init.signal?.aborted).toBe(true);
    expect(mock.requests[1]!.url.searchParams.get("locale")).toBe("tr");
    slow.release();
    await act(async () => {});
    expect(result.current.data?.slug).toBe("second");
    expect(result.current.error).toBeNull();
  });

  it("does not refetch when an equal options object is passed again", async () => {
    const mock = mockFetch([fromFixture("grid/page.json")]);
    const { result, rerender } = renderHook(() => useGridPage("nulldull-blog", "context-that-survives-the-chat", { locale: "en" }), {
      wrapper: wrapperFor(makeClient("public", mock.fetch)),
    });
    await waitFor(() => expect(result.current.data).toBeDefined());
    rerender();
    rerender();
    await act(async () => {});
    expect(mock.requests).toHaveLength(1);
  });

  it("aborts the request on unmount and never updates state afterwards", async () => {
    const slow = deferred(() => fromFixture("grid/page.json"));
    const mock = mockFetch([slow.reply]);
    const errors: unknown[] = [];
    const original = console.error;
    console.error = (...args: unknown[]) => errors.push(args);
    try {
      const { unmount } = renderHook(() => useGridPage("nulldull-blog", "context-that-survives-the-chat"), {
        wrapper: wrapperFor(makeClient("public", mock.fetch)),
      });
      await waitFor(() => expect(mock.requests).toHaveLength(1));
      unmount();
      expect(mock.requests[0]!.init.signal?.aborted).toBe(true);
      slow.release();
      await act(async () => {});
    } finally {
      console.error = original;
    }
    expect(errors).toEqual([]);
  });

  it("refetch reloads and keeps the old data while loading", async () => {
    const mock = mockFetch([fromFixture("grid/page.json"), json({ ...fixture<GridPage>("grid/page.json"), title: "Updated" })]);
    const { result } = renderHook(() => useGridPage("nulldull-blog", "context-that-survives-the-chat"), {
      wrapper: wrapperFor(makeClient("public", mock.fetch)),
    });
    await waitFor(() => expect(result.current.data).toBeDefined());
    let pending!: Promise<void>;
    act(() => {
      pending = result.current.refetch();
    });
    expect(result.current.isLoading).toBe(true);
    expect(result.current.data?.title).toBe("Context that survives the chat.");
    await act(() => pending);
    expect(result.current.data?.title).toBe("Updated");
    expect(result.current.isLoading).toBe(false);
  });

  it("uses initialData without fetching, then refetches on key change", async () => {
    const page = fixture<GridPage>("grid/page.json");
    const mock = mockFetch([json({ ...page, slug: "other" })]);
    const { result, rerender } = renderHook(({ slug }) => useGridPage("nulldull-blog", slug, { initialData: page }), {
      wrapper: wrapperFor(makeClient("public", mock.fetch)),
      initialProps: { slug: page.slug },
    });
    expect(result.current.isLoading).toBe(false);
    expect(result.current.data).toBe(page);
    await act(async () => {});
    expect(mock.requests).toHaveLength(0);
    rerender({ slug: "other" });
    await waitFor(() => expect(result.current.data?.slug).toBe("other"));
    expect(mock.requests).toHaveLength(1);
  });

  it("is StrictMode-safe: the double mount aborts the first request and settles once", async () => {
    const mock = mockFetch([
      (_url, init) => new Promise<Response>((_, reject) => init.signal?.addEventListener("abort", () => reject(new DOMException("Aborted", "AbortError")))),
      fromFixture("grid/page.json"),
    ]);
    const client = makeClient("public", mock.fetch);
    function Page() {
      const { data, error, isLoading } = useGridPage("nulldull-blog", "context-that-survives-the-chat");
      if (error) return <p>error {error.code}</p>;
      return <p>{isLoading ? "loading" : data?.title}</p>;
    }
    render(
      <StrictMode>
        <NullDullProvider client={client}>
          <Page />
        </NullDullProvider>
      </StrictMode>,
    );
    expect(screen.getByText("loading")).toBeTruthy();
    expect(await screen.findByText("Context that survives the chat.")).toBeTruthy();
    expect(mock.requests).toHaveLength(2);
    expect(mock.requests[0]!.init.signal?.aborted).toBe(true);
    expect(mock.requests[1]!.init.signal?.aborted).toBe(false);
  });

  it("StrictMode with initialData does not fetch at all", async () => {
    const page = fixture<GridPage>("grid/page.json");
    const mock = mockFetch();
    const client = makeClient("public", mock.fetch);
    function Page() {
      return <p>{useGridPage("nulldull-blog", page.slug, { initialData: page }).data?.title}</p>;
    }
    render(
      <StrictMode>
        <NullDullProvider client={client}>
          <Page />
        </NullDullProvider>
      </StrictMode>,
    );
    await act(async () => {});
    expect(screen.getByText(page.title)).toBeTruthy();
    expect(mock.requests).toHaveLength(0);
  });
});

describe("useGridPages", () => {
  it("paginates through an empty page with a cursor until nextCursor is null", async () => {
    const first = fixture<GridPageList>("grid/page-list.json");
    const empty = fixture<GridPageList>("grid/page-list-empty-with-cursor.json");
    const mock = mockFetch([fromFixture("grid/page-list.json"), fromFixture("grid/page-list-empty-with-cursor.json"), fromFixture("grid/page-list-last.json")]);
    const { result } = renderHook(() => useGridPages("nulldull-blog", { limit: 2 }), { wrapper: wrapperFor(makeClient("public", mock.fetch)) });
    expect(result.current.isLoading).toBe(true);
    expect(result.current.hasNextPage).toBe(false);
    await waitFor(() => expect(result.current.data?.items).toHaveLength(2));
    expect(result.current.hasNextPage).toBe(true);
    expect(result.current.data?.pages[0]?.pool.key).toBe(first.pool.key);
    expect(result.current.data?.items[0]?.cover?.url).toContain("key=nd_pub_");

    let pending!: Promise<void>;
    act(() => {
      pending = result.current.fetchNextPage();
    });
    expect(result.current.isFetchingNextPage).toBe(true);
    expect(result.current.isLoading).toBe(false);
    await act(() => pending);
    expect(result.current.isFetchingNextPage).toBe(false);
    expect(result.current.data?.pages).toHaveLength(2);
    expect(result.current.data?.items).toHaveLength(2);
    expect(result.current.hasNextPage).toBe(true);

    await act(() => result.current.fetchNextPage());
    expect(result.current.data?.items).toHaveLength(3);
    expect(result.current.hasNextPage).toBe(false);

    await act(() => result.current.fetchNextPage());
    expect(mock.requests).toHaveLength(3);
    expect(mock.requests[0]!.url.searchParams.get("after")).toBeNull();
    expect(mock.requests[1]!.url.searchParams.get("after")).toBe(first.nextCursor);
    expect(mock.requests[2]!.url.searchParams.get("after")).toBe(empty.nextCursor);
    for (const request of mock.requests) expect(request.url.searchParams.get("limit")).toBe("2");
  });

  it("raises INVALID_RESPONSE when a cursor repeats and keeps loaded pages", async () => {
    const first = fixture<GridPageList>("grid/page-list.json");
    const mock = mockFetch([fromFixture("grid/page-list.json"), json({ ...first, items: [] })]);
    const { result } = renderHook(() => useGridPages("nulldull-blog"), { wrapper: wrapperFor(makeClient("public", mock.fetch)) });
    await waitFor(() => expect(result.current.data).toBeDefined());
    await act(() => result.current.fetchNextPage());
    expect(result.current.error?.code).toBe("INVALID_RESPONSE");
    expect(result.current.data?.pages).toHaveLength(1);
  });

  it("keeps loaded pages when a next page fails", async () => {
    const mock = mockFetch([fromFixture("grid/page-list.json"), fromFixture("errors/rate-limited.json", 429, { "retry-after": "60" })]);
    const { result } = renderHook(() => useGridPages("nulldull-blog"), { wrapper: wrapperFor(makeClient("public", mock.fetch)) });
    await waitFor(() => expect(result.current.data).toBeDefined());
    await act(() => result.current.fetchNextPage());
    expect(result.current.error?.code).toBe("RATE_LIMITED");
    expect(result.current.error?.retryAfter).toBe(60);
    expect(result.current.data?.items).toHaveLength(2);
    expect(result.current.hasNextPage).toBe(true);
  });

  it("resets to the first page when filters change, aborting a pending next page", async () => {
    const slow = deferred(() => fromFixture("grid/page-list-last.json"));
    const mock = mockFetch([fromFixture("grid/page-list.json"), slow.reply, fromFixture("grid/page-list-last.json")]);
    const { result, rerender } = renderHook(({ q }) => useGridPages("nulldull-blog", { q }), {
      wrapper: wrapperFor(makeClient("public", mock.fetch)),
      initialProps: { q: "a" },
    });
    await waitFor(() => expect(result.current.data).toBeDefined());
    act(() => void result.current.fetchNextPage());
    await waitFor(() => expect(mock.requests).toHaveLength(2));
    rerender({ q: "agents" });
    await waitFor(() => expect(mock.requests).toHaveLength(3));
    expect(mock.requests[1]!.init.signal?.aborted).toBe(true);
    await waitFor(() => expect(result.current.data?.pages).toHaveLength(1));
    expect(mock.requests[2]!.url.searchParams.get("q")).toBe("agents");
    expect(mock.requests[2]!.url.searchParams.get("after")).toBeNull();
    slow.release();
    await act(async () => {});
    expect(result.current.data?.pages).toHaveLength(1);
    expect(result.current.isFetchingNextPage).toBe(false);
  });

  it("accepts a server-rendered first page as initialData", async () => {
    const first = fixture<GridPageList>("grid/page-list.json");
    const mock = mockFetch([fromFixture("grid/page-list-last.json")]);
    const { result } = renderHook(() => useGridPages("nulldull-blog", { initialData: first }), {
      wrapper: wrapperFor(makeClient("public", mock.fetch)),
    });
    expect(result.current.isLoading).toBe(false);
    expect(result.current.data?.items).toHaveLength(2);
    await act(() => result.current.fetchNextPage());
    expect(result.current.data?.items).toHaveLength(3);
    expect(mock.requests).toHaveLength(1);
    expect(mock.requests[0]!.url.searchParams.get("after")).toBe(first.nextCursor);
  });

  it("keeps data referentially stable across renders", async () => {
    const mock = mockFetch([fromFixture("grid/page-list.json")]);
    const { result, rerender } = renderHook(() => useGridPages("nulldull-blog"), { wrapper: wrapperFor(makeClient("public", mock.fetch)) });
    await waitFor(() => expect(result.current.data).toBeDefined());
    const data = result.current.data;
    rerender();
    expect(result.current.data).toBe(data);
  });
});

describe("memory and locale hooks", () => {
  const privateWrapper = (fetch: ReturnType<typeof mockFetch>["fetch"]) => wrapperFor(makeClient("private", fetch));

  it("useMemoryDocuments paginates with repeated tags and root folder", async () => {
    const mock = mockFetch([fromFixture("memory/documents-page-1.json"), fromFixture("memory/documents-page-2.json")]);
    const { result } = renderHook(() => useMemoryDocuments({ folderId: null, tags: ["agents", "rules"], kind: "rules" }), {
      wrapper: privateWrapper(mock.fetch),
    });
    await waitFor(() => expect(result.current.data?.items).toHaveLength(2));
    await act(() => result.current.fetchNextPage());
    expect(result.current.data?.items).toHaveLength(3);
    expect(result.current.hasNextPage).toBe(false);
    const url = mock.requests[0]!.url;
    expect(url.pathname).toBe(`${WS}/documents`);
    expect(url.searchParams.get("folderId")).toBe("root");
    expect(url.searchParams.getAll("tag")).toEqual(["agents", "rules"]);
    expect(mock.requests[1]!.url.searchParams.get("after")).toBe("3a7b9c1d-2e4f-4a6b-8c0d-1e2f3a4b5c6d");
  });

  it("useMemoryDocument loads one document", async () => {
    const mock = mockFetch([fromFixture("memory/document.json")]);
    const { result } = renderHook(() => useMemoryDocument("1f4e5c2a-8b3d-4a6e-9f7c-2d1b0a9e8c7f"), { wrapper: privateWrapper(mock.fetch) });
    await waitFor(() => expect(result.current.data?.name).toBe("AGENTS.md"));
    expect(mock.requests[0]!.url.pathname).toBe(`${WS}/documents/1f4e5c2a-8b3d-4a6e-9f7c-2d1b0a9e8c7f`);
  });

  it("useMemoryDocument surfaces 403 FORBIDDEN", async () => {
    const mock = mockFetch([fromFixture("errors/forbidden.json", 403)]);
    const { result } = renderHook(() => useMemoryDocument("nope"), { wrapper: privateWrapper(mock.fetch) });
    await waitFor(() => expect(result.current.error?.code).toBe("FORBIDDEN"));
    expect(result.current.error?.status).toBe(403);
  });

  it("useMemorySearch stays idle below 2 characters, then searches", async () => {
    const mock = mockFetch([fromFixture("memory/search.json")]);
    const { result, rerender } = renderHook(({ q }) => useMemorySearch(q, { scopeId: "s1" }), {
      wrapper: privateWrapper(mock.fetch),
      initialProps: { q: "a" },
    });
    await act(async () => {});
    expect(result.current.isLoading).toBe(false);
    expect(mock.requests).toHaveLength(0);
    rerender({ q: "agents" });
    await waitFor(() => expect(result.current.data?.items).toHaveLength(1));
    expect(mock.requests[0]!.url.searchParams.get("q")).toBe("agents");
    expect(mock.requests[0]!.url.searchParams.get("scopeId")).toBe("s1");
  });

  it("useMemoryAssets and useMemoryAsset", async () => {
    const mock = mockFetch([fromFixture("memory/assets.json"), fromFixture("memory/asset.json")]);
    const wrapper = privateWrapper(mock.fetch);
    const list = renderHook(() => useMemoryAssets({ q: "logo" }), { wrapper });
    await waitFor(() => expect(list.result.current.data?.items).toHaveLength(1));
    const one = renderHook(() => useMemoryAsset("c4ca4238-a0b9-4382-8dcc-509a6f75849b", { revisionId: "r1" }), { wrapper });
    await waitFor(() => expect(one.result.current.data?.name).toBe("logo.png"));
    expect(mock.requests[1]!.url.searchParams.get("revisionId")).toBe("r1");
  });

  it("useLocaleFormats loads formats", async () => {
    const mock = mockFetch([fromFixture("locale/formats.json")]);
    const { result } = renderHook(() => useLocaleFormats(), { wrapper: privateWrapper(mock.fetch) });
    await waitFor(() => expect(result.current.data?.items).toHaveLength(6));
    expect(mock.requests[0]!.url.pathname).toBe(`${WS}/locale/formats`);
  });

  it("memory hooks with a public key report PRIVATE_KEY_REQUIRED without a request", async () => {
    const mock = mockFetch();
    const { result } = renderHook(() => useMemoryDocuments(), { wrapper: wrapperFor(makeClient("public", mock.fetch)) });
    await waitFor(() => expect(result.current.error?.code).toBe("PRIVATE_KEY_REQUIRED"));
    expect(mock.requests).toHaveLength(0);
  });

  it("memory hooks without workspaceId report WORKSPACE_REQUIRED", async () => {
    const mock = mockFetch();
    const client = makeClient("private", mock.fetch, { workspaceId: undefined });
    const { result } = renderHook(() => useLocaleFormats(), { wrapper: wrapperFor(client) });
    await waitFor(() => expect(result.current.error?.code).toBe("WORKSPACE_REQUIRED"));
  });
});

describe("useNullDullQuery", () => {
  it("runs any SDK call with the hook's signal", async () => {
    const mock = mockFetch([fromFixture("memory/folder.json")]);
    const { result } = renderHook(
      () => useNullDullQuery(["memory.getFolder", "f1"], (client, signal) => client.memory.getFolder("f1", { signal })),
      { wrapper: wrapperFor(makeClient("private", mock.fetch)) },
    );
    await waitFor(() => expect(result.current.data).toBeDefined());
    expect(mock.requests[0]!.url.pathname).toBe(`${WS}/folders/f1`);
  });

  it("wraps a non-SDK failure in NullDullError", async () => {
    const { result } = renderHook(
      () => useNullDullQuery(["custom"], async () => {
        throw new TypeError("boom");
      }),
      { wrapper: wrapperFor(makeClient("public", mockFetch().fetch)) },
    );
    await waitFor(() => expect(result.current.error).not.toBeNull());
    expect(result.current.error).toBeInstanceOf(NullDullError);
    expect(result.current.error?.message).toBe("boom");
  });
});

