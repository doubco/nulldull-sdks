/**
 * Optional live tests against a real NullDull API. Skipped unless the variables are set:
 *
 *   NULLDULL_PUBLIC_KEY + NULLDULL_GRID_POOL         Grid delivery
 *   NULLDULL_PRIVATE_KEY + NULLDULL_WORKSPACE_ID     Memory and Locale
 *   NULLDULL_LOCALE_SCOPE_ID (optional)              Locale export location (default: workspace root)
 *   NULLDULL_BASE_URL (optional)                     Default https://nulldull.com
 *
 * Never print key values.
 */
import { describe, expect, it } from "vitest";
import { NullDullClient, NullDullError } from "../src";

const env = process.env;
const baseUrl = env.NULLDULL_BASE_URL || undefined;
const grid = !!(env.NULLDULL_PUBLIC_KEY && env.NULLDULL_GRID_POOL);
const platform = !!(env.NULLDULL_PRIVATE_KEY && env.NULLDULL_WORKSPACE_ID);

describe.skipIf(!grid)("live Grid", () => {
  const client = () => new NullDullClient({ apiKey: env.NULLDULL_PUBLIC_KEY!, baseUrl });
  const pool = env.NULLDULL_GRID_POOL!;

  it("lists, iterates and reads published pages", async () => {
    const list = await client().grid.listPages(pool, { limit: 2 });
    expect(list.pool.key).toBe(pool);
    expect(Array.isArray(list.items)).toBe(true);
    let count = 0;
    for await (const summary of client().grid.iteratePages(pool, { limit: 2 })) {
      expect(typeof summary.slug).toBe("string");
      if (++count >= 5) break;
    }
    const first = list.items[0];
    if (!first) return;
    const page = await client().grid.getPage(pool, first.slug, { locale: first.locale });
    expect(page.id).toBe(first.id);
    expect(Array.isArray(page.document.nodes)).toBe(true);
    for (const asset of page.assets) expect(asset.url.startsWith("http")).toBe(true);
  });

  it("raises NOT_FOUND for a missing page", async () => {
    const error = await client().grid.getPage(pool, "nulldull-sdk-live-test-missing-page").catch((e: unknown) => e);
    expect(error).toBeInstanceOf(NullDullError);
    expect((error as NullDullError).status).toBe(404);
    expect((error as NullDullError).code).toBe("NOT_FOUND");
  });

  it("refuses the platform API for a public key", async () => {
    const error = await new NullDullClient({ apiKey: env.NULLDULL_PUBLIC_KEY!, baseUrl, workspaceId: "w" }).memory.listScopes().catch((e: unknown) => e);
    expect((error as NullDullError).code).toBe("PRIVATE_KEY_REQUIRED");
  });
});

describe.skipIf(!platform)("live Memory and Locale", () => {
  const client = () => new NullDullClient({ apiKey: env.NULLDULL_PRIVATE_KEY!, workspaceId: env.NULLDULL_WORKSPACE_ID!, baseUrl });

  const tolerateForbidden = async <T>(call: () => Promise<T>): Promise<T | null> => {
    try {
      return await call();
    } catch (error) {
      // A key without memory:read or locale:read gets 403; that is a configuration, not an SDK, failure.
      if (error instanceof NullDullError && error.code === "FORBIDDEN") return null;
      throw error;
    }
  };

  it("lists scopes, documents and tags", async () => {
    const scopes = await tolerateForbidden(() => client().memory.listScopes());
    if (!scopes) return;
    expect(scopes.items.some((scope) => scope.id === env.NULLDULL_WORKSPACE_ID)).toBe(true);
    const documents = await client().memory.listDocuments();
    expect(Array.isArray(documents.items)).toBe(true);
    const first = documents.items[0];
    if (first) expect((await client().memory.getDocument(first.id)).id).toBe(first.id);
    const tags = await client().memory.listTags();
    expect(Array.isArray(tags.items)).toBe(true);
  });

  it("lists Locale formats and exports", async () => {
    const formats = await tolerateForbidden(() => client().locale.listFormats());
    if (!formats) return;
    expect(formats.items.map((format) => format.id)).toContain("json");
    const exported = await tolerateForbidden(() => client().locale.export(env.NULLDULL_LOCALE_SCOPE_ID || env.NULLDULL_WORKSPACE_ID!));
    if (exported) expect(exported.format).toBe("json");
  });
});
