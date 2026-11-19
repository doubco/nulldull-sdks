import { afterEach, describe, expect, it, vi } from "vitest";
import pkg from "../package.json";
import { NullDullClient, NullDullError, VERSION } from "../src";
import { parseFilename, parseRetryAfter } from "../src/http";
import { clientFor, fixture, manifest, mockFetch } from "./support";

const { publicKey, privateKey, workspaceId } = manifest.config;
const json = (body: unknown, status = 200, headers: Record<string, string> = {}) =>
  new Response(JSON.stringify(body), { status, headers: { "content-type": "application/json", ...headers } });

async function failure(promise: Promise<unknown> | (() => unknown)): Promise<NullDullError> {
  try {
    await (typeof promise === "function" ? promise() : promise);
  } catch (error) {
    expect(error).toBeInstanceOf(NullDullError);
    return error as NullDullError;
  }
  throw new Error("Expected a NullDullError");
}

describe("1. construction", () => {
  const make = (options: Record<string, unknown>) => () => new NullDullClient({ apiKey: publicKey, fetch: async () => json({}), ...options } as any);

  it("rejects malformed keys", async () => {
    for (const apiKey of [undefined, "", "nd_pub_123", `nd_xyz_${"a".repeat(64)}`, `nd_pub_${"A".repeat(64)}`, `ndm_${"a".repeat(64)}`]) {
      const error = await failure(make({ apiKey }));
      expect(error.code).toBe("INVALID_ARGUMENT");
      expect(error.status).toBe(0);
    }
  });

  it("rejects bad base URLs", async () => {
    for (const baseUrl of ["ftp://nulldull.com", "nulldull.com", "https://user:pass@nulldull.com", "https://nulldull.com/?x=1", "https://nulldull.com/#top"])
      expect((await failure(make({ baseUrl }))).code).toBe("INVALID_ARGUMENT");
  });

  it("rejects malformed workspace IDs, timeouts and retries", async () => {
    expect((await failure(make({ workspaceId: "../etc" }))).code).toBe("INVALID_ARGUMENT");
    expect((await failure(make({ workspaceId: "a".repeat(129) }))).code).toBe("INVALID_ARGUMENT");
    expect((await failure(make({ timeout: -1 }))).code).toBe("INVALID_ARGUMENT");
    expect((await failure(make({ maxRetries: 1.5 }))).code).toBe("INVALID_ARGUMENT");
  });

  it("strips a trailing slash and keeps a path prefix", async () => {
    const { fetch, requests } = mockFetch([json(fixture("grid/page-list-last.json")), json(fixture("grid/page-list-last.json"))]);
    expect(new NullDullClient({ apiKey: publicKey, baseUrl: "https://staging.nulldull.com/", fetch }).baseUrl).toBe("https://staging.nulldull.com");
    await new NullDullClient({ apiKey: publicKey, baseUrl: "https://staging.nulldull.com/", fetch }).grid.listPages("nulldull-blog");
    await new NullDullClient({ apiKey: publicKey, baseUrl: "http://localhost:8787/proxy/", fetch }).grid.listPages("nulldull-blog");
    expect(requests[0]!.url.href).toBe("https://staging.nulldull.com/api/grid/v1/pools/nulldull-blog/pages?locale=en");
    expect(requests[1]!.url.href).toBe("http://localhost:8787/proxy/api/grid/v1/pools/nulldull-blog/pages?locale=en");
  });

  it("defaults to https://nulldull.com and exposes the key kind", () => {
    const client = new NullDullClient({ apiKey: privateKey, fetch: async () => json({}) });
    expect(client.baseUrl).toBe("https://nulldull.com");
    expect(client.keyKind).toBe("private");
  });

  describe("in a browser", () => {
    afterEach(() => {
      vi.unstubAllGlobals();
    });
    it("refuses a private key unless explicitly allowed, and sends no User-Agent", async () => {
      vi.stubGlobal("window", {});
      vi.stubGlobal("document", {});
      expect((await failure(make({ apiKey: privateKey }))).code).toBe("INVALID_ARGUMENT");
      const { fetch, requests } = mockFetch([json(fixture("grid/page-list-last.json"))]);
      new NullDullClient({ apiKey: privateKey, fetch, dangerouslyAllowPrivateKeyInBrowser: true });
      await new NullDullClient({ apiKey: publicKey, fetch }).grid.listPages("nulldull-blog");
      expect(requests[0]!.headers.has("user-agent")).toBe(false);
      expect(requests[0]!.init.credentials).toBe("omit");
    });
  });
});

describe("2. request headers", () => {
  it("sends Authorization, Accept and User-Agent", async () => {
    const { fetch, requests } = mockFetch([json(fixture("memory/scopes.json")), new Response("x", { status: 200 })]);
    const { client } = clientFor("private", fetch, { userAgent: "my-app/2.0" });
    await client.memory.listScopes();
    await client.memory.downloadAsset("asset_1");
    expect(requests[0]!.headers.get("authorization")).toBe(`Bearer ${privateKey}`);
    expect(requests[0]!.headers.get("accept")).toBe("application/json");
    expect(requests[0]!.headers.get("user-agent")).toBe(`nulldull-sdk-node/${VERSION} my-app/2.0`);
    expect(requests[1]!.headers.get("accept")).toBe("*/*");
    expect(requests[0]!.init.redirect).toBe("manual");
    expect(requests[0]!.init.method).toBe("GET");
  });

  it("keeps VERSION in sync with package.json", () => {
    expect(VERSION).toBe(pkg.version);
  });
});

describe("3. Memory and Locale preconditions", () => {
  it("needs workspaceId, without sending a request", async () => {
    const { fetch, requests } = mockFetch();
    const client = new NullDullClient({ apiKey: privateKey, fetch });
    expect((await failure(client.memory.listDocuments())).code).toBe("WORKSPACE_REQUIRED");
    expect((await failure(client.locale.export(workspaceId))).code).toBe("WORKSPACE_REQUIRED");
    const iterator = client.memory.iterateDocuments();
    expect((await failure(iterator.next())).code).toBe("WORKSPACE_REQUIRED");
    expect(requests).toHaveLength(0);
  });

  it("needs a private key, without sending a request", async () => {
    const { fetch, requests } = mockFetch();
    const { client } = clientFor("public", fetch);
    expect((await failure(client.memory.getDocument("doc"))).code).toBe("PRIVATE_KEY_REQUIRED");
    expect((await failure(client.locale.listFormats())).code).toBe("PRIVATE_KEY_REQUIRED");
    expect(requests).toHaveLength(0);
  });

  it("percent-encodes path segments and rejects empty IDs", async () => {
    const { fetch, requests } = mockFetch([json({})]);
    const { client } = clientFor("private", fetch);
    await client.memory.getDocument("a/b c");
    expect(requests[0]!.url.pathname).toBe(`/api/platform/workspaces/${workspaceId}/documents/a%2Fb%20c`);
    expect((await failure(client.memory.getDocument(""))).code).toBe("INVALID_ARGUMENT");
  });
});

describe("4. Grid validation", () => {
  it("validates pool, slug, locale and limit before any request", async () => {
    const { fetch, requests } = mockFetch();
    const { client } = clientFor("public", fetch);
    for (const call of [
      () => client.grid.listPages("Bad_Pool"),
      () => client.grid.listPages("pool", { locale: "EN" }),
      () => client.grid.listPages("pool", { limit: 0 }),
      () => client.grid.listPages("pool", { limit: 51 }),
      () => client.grid.listPages("pool", { limit: 2.5 }),
      () => client.grid.getPage("pool", "a--b"),
      () => client.grid.getPage("pool", "x".repeat(97)),
    ])
      expect((await failure(call())).code).toBe("INVALID_ARGUMENT");
    expect(requests).toHaveLength(0);
  });

  it("always sends locale, defaulting to en, and omits an empty q", async () => {
    const { fetch, requests } = mockFetch([json(fixture("grid/page-list-last.json")), json(fixture("grid/page.json"))]);
    const { client } = clientFor("public", fetch);
    await client.grid.listPages("nulldull-blog", { q: "" });
    await client.grid.getPage("nulldull-blog", "hello", { locale: "pt-br" });
    expect(requests[0]!.url.search).toBe("?locale=en");
    expect(requests[1]!.url.search).toBe("?locale=pt-br");
  });
});

describe("5. grid.assetUrl", () => {
  const pub = clientFor("public", mockFetch().fetch).client.grid;
  const sec = clientFor("private", mockFetch().fetch).client.grid;

  it("resolves relative URLs and adds a public key on the API origin", () => {
    expect(pub.assetUrl("/api/grid/v1/pools/p/pages/s/assets/a?locale=en&version=3")).toBe(
      `https://nulldull.com/api/grid/v1/pools/p/pages/s/assets/a?locale=en&version=3&key=${publicKey}`,
    );
    expect(pub.assetUrl("https://NULLDULL.com:443/x")).toBe(`https://nulldull.com/x?key=${publicKey}`);
  });

  it("keeps an existing key", () => {
    expect(pub.assetUrl("/x?key=nd_pub_existing")).toBe("https://nulldull.com/x?key=nd_pub_existing");
  });

  it("never adds a key to another origin", () => {
    for (const url of ["https://cdn.example.com/a.png", "//evil.example/a.png", "https://nulldull.com.evil.example/a.png", "http://nulldull.com/a.png", "https://nulldull.com:8443/a.png"])
      expect(pub.assetUrl(url)).not.toContain("key=");
  });

  it("never adds a private key", () => {
    expect(sec.assetUrl("/api/grid/v1/pools/p/pages/s/assets/a?version=1")).toBe("https://nulldull.com/api/grid/v1/pools/p/pages/s/assets/a?version=1");
  });
});

describe("6. grid.downloadAsset", () => {
  it("sends Authorization only to the API origin", async () => {
    const bytes = () => new Response(new Uint8Array([1, 2, 3]), { headers: { "content-type": "image/png", "content-disposition": "inline; filename*=UTF-8''cover.png" } });
    const { fetch, requests } = mockFetch([bytes(), bytes()]);
    const { client } = clientFor("private", fetch);
    const page = fixture("grid/page.json");
    const own = await client.grid.downloadAsset(page.assets[0]);
    await client.grid.downloadAsset("https://cdn.example.com/cover.png");
    expect(own).toMatchObject({ contentType: "image/png", filename: "cover.png", size: 3 });
    expect(requests[0]!.url.origin).toBe("https://nulldull.com");
    expect(requests[0]!.headers.get("authorization")).toBe(`Bearer ${privateKey}`);
    expect(requests[1]!.headers.has("authorization")).toBe(false);
  });
});

describe("7. URL normalization", () => {
  it("normalizes list covers and page covers and assets, leaving the rest untouched", async () => {
    const { fetch } = mockFetch([json(fixture("grid/page-list.json")), json(fixture("grid/page.json"))]);
    const { client } = clientFor("public", fetch);
    const list = await client.grid.listPages("nulldull-blog");
    const page = await client.grid.getPage("nulldull-blog", "context-that-survives-the-chat");
    expect(list.items[0]!.cover!.url.startsWith("https://nulldull.com/api/grid/v1/")).toBe(true);
    expect(page.assets.every((asset) => asset.url.startsWith("https://nulldull.com/"))).toBe(true);
    expect(page.document).toEqual(fixture("grid/page.json").document);
    expect(list.pool).toEqual({ key: "nulldull-blog", name: "The Void" });
  });
});

describe("8. pagination", () => {
  it("starts from after and stops at a null cursor", async () => {
    const { fetch, requests } = mockFetch([json(fixture("memory/documents-page-2.json"))]);
    const { client } = clientFor("private", fetch);
    const items = [];
    for await (const doc of client.memory.iterateDocuments({ after: "cursor-1", scopeId: "s" })) items.push(doc);
    expect(items).toHaveLength(1);
    expect(requests[0]!.url.searchParams.get("after")).toBe("cursor-1");
    expect(requests[0]!.url.searchParams.get("scopeId")).toBe("s");
  });

  it("raises INVALID_RESPONSE when a cursor repeats", async () => {
    const page = { items: [{ id: "a" }], nextCursor: "same" };
    const { fetch } = mockFetch([json(page), json(page)]);
    const { client } = clientFor("private", fetch);
    const seen: unknown[] = [];
    const error = await failure((async () => {
      for await (const item of client.memory.iterateScopes()) seen.push(item);
    })());
    expect(error.code).toBe("INVALID_RESPONSE");
    expect(seen).toHaveLength(2);
  });

  it("is lazy: no request until iterated, and stops early on break", async () => {
    const { fetch, requests } = mockFetch([json(fixture("memory/tags-page-1.json"))]);
    const { client } = clientFor("private", fetch);
    const iterator = client.memory.iterateTags();
    expect(requests).toHaveLength(0);
    for await (const tag of iterator) {
      expect(tag.tag).toBe("maintained");
      break;
    }
    expect(requests).toHaveLength(1);
  });
});

describe("9. errors", () => {
  it("fills every field from body and headers", async () => {
    const { fetch } = mockFetch([json(fixture("errors/locale-format-unrepresentable.json"), 400, { "cf-ray": "abc-AMS" })]);
    const { client } = clientFor("private", fetch);
    const error = await failure(client.locale.export(workspaceId, { format: "world" }));
    expect(error).toMatchObject({
      name: "NullDullError",
      status: 400,
      code: "INVALID_INPUT",
      detail: "LOCALE_FORMAT_UNREPRESENTABLE",
      message: "Plural values cannot be written to this format.",
      requestId: "abc-AMS",
      retryAfter: null,
    });
    expect(error.body).toMatchObject({ key: "cart.items", language: "tr" });
    expect(error).toBeInstanceOf(Error);
  });

  it("prefers X-Request-Id and builds a default message", async () => {
    const { fetch } = mockFetch([json({ code: "FORBIDDEN" }, 403, { "x-request-id": "req_1", "cf-ray": "ray" })]);
    const { client } = clientFor("private", fetch);
    const error = await failure(client.memory.listScopes());
    expect(error.requestId).toBe("req_1");
    expect(error.message).toBe("NullDull request failed (403 FORBIDDEN).");
  });

  it("reports invalid JSON on success as INVALID_RESPONSE", async () => {
    const { fetch } = mockFetch([new Response("<html>", { status: 200 })]);
    const { client } = clientFor("private", fetch);
    const error = await failure(client.memory.listScopes());
    expect(error).toMatchObject({ code: "INVALID_RESPONSE", status: 200 });
  });

  it("treats a redirect as an error instead of following it", async () => {
    const { fetch, requests } = mockFetch([new Response(null, { status: 302, headers: { location: "https://evil.example/" } })]);
    const { client } = clientFor("public", fetch);
    const error = await failure(client.grid.listPages("nulldull-blog"));
    expect(error).toMatchObject({ status: 302, code: "REQUEST_FAILED" });
    expect(requests).toHaveLength(1);
  });
});

describe("10. retries", () => {
  it("honours an HTTP-date Retry-After", () => {
    const now = Date.parse("2026-11-20T10:00:00Z");
    expect(parseRetryAfter("Fri, 20 Nov 2026 10:00:05 GMT", now)).toBe(5);
    expect(parseRetryAfter("7")).toBe(7);
    expect(parseRetryAfter("soon")).toBeNull();
  });

  it("retries 504 and 429 without Retry-After with backoff", async () => {
    const { fetch } = mockFetch([json({ code: "X" }, 504), json({ code: "RATE_LIMITED" }, 429), json(fixture("memory/scopes.json"))]);
    const { client, sleeps } = clientFor("private", fetch);
    await client.memory.listScopes();
    expect(sleeps).toEqual([500, 1000]);
  });

  it("accepts Retry-After of exactly 30 seconds", async () => {
    const { fetch } = mockFetch([json({ code: "RATE_LIMITED" }, 429, { "retry-after": "30" }), json(fixture("memory/scopes.json"))]);
    const { client, sleeps } = clientFor("private", fetch);
    await client.memory.listScopes();
    expect(sleeps).toEqual([30000]);
  });

  it("disables retries with maxRetries: 0", async () => {
    const { fetch, requests } = mockFetch([json({ code: "SERVICE_UNAVAILABLE" }, 503)]);
    const { client } = clientFor("private", fetch, { maxRetries: 0 });
    expect((await failure(client.memory.listScopes())).code).toBe("SERVICE_UNAVAILABLE");
    expect(requests).toHaveLength(1);
  });

  it("never retries 400, 401, 403, 404 or 500", async () => {
    for (const status of [400, 401, 403, 404, 500]) {
      const { fetch, requests } = mockFetch([json({ code: "X" }, status)]);
      const { client } = clientFor("private", fetch);
      await failure(client.memory.listScopes());
      expect(requests).toHaveLength(1);
    }
  });

  it("retries network errors and reports NETWORK_ERROR when they persist", async () => {
    const { fetch, requests } = mockFetch([new TypeError("fetch failed"), new TypeError("fetch failed"), new TypeError("fetch failed")]);
    const { client, sleeps } = clientFor("private", fetch);
    const error = await failure(client.memory.listScopes());
    expect(error).toMatchObject({ code: "NETWORK_ERROR", status: 0 });
    expect(error.cause).toBeInstanceOf(TypeError);
    expect(requests).toHaveLength(3);
    expect(sleeps).toEqual([500, 1000]);
  });

  it("recovers after one network error", async () => {
    const { fetch } = mockFetch([new TypeError("fetch failed"), json(fixture("memory/scopes.json"))]);
    const { client } = clientFor("private", fetch);
    expect((await client.memory.listScopes()).items).toHaveLength(3);
  });
});

describe("11. timeouts and cancellation", () => {
  const hanging = (_url: URL, init: RequestInit) =>
    new Promise<Response>((_, reject) => init.signal!.addEventListener("abort", () => reject(new DOMException("aborted", "AbortError"))));

  it("raises TIMEOUT and does not retry it", async () => {
    const { fetch, requests } = mockFetch([hanging, hanging]);
    const { client } = clientFor("private", fetch, { timeout: 20 });
    const error = await failure(client.memory.listScopes());
    expect(error).toMatchObject({ code: "TIMEOUT", status: 0 });
    expect(requests).toHaveLength(1);
  });

  it("raises ABORTED when the caller cancels", async () => {
    const { fetch } = mockFetch([hanging]);
    const { client } = clientFor("private", fetch);
    const controller = new AbortController();
    const pending = client.memory.listScopes({ signal: controller.signal });
    setTimeout(() => controller.abort(), 5);
    expect((await failure(pending)).code).toBe("ABORTED");
  });

  it("raises ABORTED for an already-aborted signal without a request", async () => {
    const { fetch, requests } = mockFetch();
    const { client } = clientFor("public", fetch);
    expect((await failure(client.grid.getPage("p", "s", { signal: AbortSignal.abort() }))).code).toBe("ABORTED");
    expect(requests).toHaveLength(0);
  });

  it("raises ABORTED while waiting to retry", async () => {
    const { fetch } = mockFetch([json({ code: "SERVICE_UNAVAILABLE" }, 503)]);
    const controller = new AbortController();
    const client = new NullDullClient({ apiKey: privateKey, workspaceId, fetch });
    const pending = client.memory.listScopes({ signal: controller.signal });
    setTimeout(() => controller.abort(), 20);
    expect((await failure(pending)).code).toBe("ABORTED");
  });

  it("covers reading the body within the timeout", async () => {
    const slowBody = () =>
      new Response(new ReadableStream({ start() { /* never enqueues */ } }), { status: 200 });
    const { fetch } = mockFetch([slowBody]);
    const { client } = clientFor("private", fetch, { timeout: 20 });
    expect((await failure(client.memory.listScopes())).code).toBe("TIMEOUT");
  });
});

describe("12. Memory filters", () => {
  it("sends root for null, the literal root, and nothing when omitted", async () => {
    const { fetch, requests } = mockFetch([json({ items: [], nextCursor: null }), json({ items: [], nextCursor: null }), json({ items: [], nextCursor: null }), json({ items: [], nextCursor: null })]);
    const { client } = clientFor("private", fetch);
    await client.memory.listAssets({ folderId: null });
    await client.memory.listFolders({ parentId: "root" });
    await client.memory.listDocuments({});
    await client.memory.listDocuments({ tags: [] });
    expect(requests[0]!.url.search).toBe("?folderId=root");
    expect(requests[1]!.url.search).toBe("?parentId=root");
    expect(requests[2]!.url.search).toBe("");
    expect(requests[3]!.url.search).toBe("");
  });

  it("downloads previews with preview=true and w, and rejects bad widths", async () => {
    const { fetch, requests } = mockFetch([new Response("a"), new Response("b")]);
    const { client } = clientFor("private", fetch);
    await client.memory.downloadAsset("a1", { width: 256 });
    await client.memory.downloadAsset("a1", { preview: true });
    expect(requests[0]!.url.search).toBe("?preview=true&w=256");
    expect(requests[1]!.url.search).toBe("?preview=true");
    expect((await failure(client.memory.downloadAsset("a1", { width: 0 }))).code).toBe("INVALID_ARGUMENT");
  });
});

describe("13. Locale export", () => {
  it("always sends format, comma-joins lists and never sends language", async () => {
    const { fetch, requests } = mockFetch([json(fixture("locale/export-json.json")), json(fixture("locale/export-json.json"))]);
    const { client } = clientFor("private", fetch);
    await client.locale.export("scope_1", { languages: "tr" });
    await client.locale.export("scope_1", { languages: ["en", "pt-br"], status: "approved" });
    expect(requests[0]!.url.search).toBe("?scopeId=scope_1&format=json&languages=tr");
    expect(requests[1]!.url.search).toBe("?scopeId=scope_1&format=json&languages=en%2Cpt-br&status=approved");
    expect(requests.some((request) => request.url.searchParams.has("language"))).toBe(false);
  });

  it("rejects a missing scope and comma-containing languages", async () => {
    const { fetch } = mockFetch();
    const { client } = clientFor("private", fetch);
    expect((await failure(client.locale.export(""))).code).toBe("INVALID_ARGUMENT");
    expect((await failure(client.locale.export("s", { languages: ["en,tr"] }))).code).toBe("INVALID_ARGUMENT");
  });
});

describe("14. Content-Disposition", () => {
  it("decodes filename* and falls back to filename", () => {
    expect(parseFilename("attachment; filename*=UTF-8''%C3%B6deme%20plan.pdf")).toBe("ödeme plan.pdf");
    expect(parseFilename('attachment; filename="report \\"q3\\".csv"')).toBe('report "q3".csv');
    expect(parseFilename("inline; filename=logo.png")).toBe("logo.png");
    expect(parseFilename('attachment; filename="fallback.txt"; filename*=UTF-8\'\'real.txt')).toBe("real.txt");
    expect(parseFilename("attachment")).toBeNull();
    expect(parseFilename(null)).toBeNull();
  });
});
