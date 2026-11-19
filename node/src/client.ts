import { invalidArgument } from "./errors";
import { GridApi } from "./grid";
import { Transport, defaultSleep, isBrowser, type FetchLike, type SleepLike } from "./http";
import { LocaleApi } from "./locale";
import { MemoryApi, workspaceGuard } from "./memory";
import { VERSION } from "./version";

const API_KEY = /^nd_(pub|sec)_[a-f0-9]{64}$/;
const WORKSPACE_ID = /^[a-zA-Z0-9_-]{1,128}$/;
export const DEFAULT_BASE_URL = "https://nulldull.com";

export interface NullDullClientOptions {
  /** A workspace API key: public `nd_pub_…` or private `nd_sec_…`. */
  apiKey: string;
  /** Default `https://nulldull.com`. */
  baseUrl?: string;
  /** Needed for `memory` and `locale`; a key cannot look up its own workspace. */
  workspaceId?: string;
  /** Per-attempt timeout in milliseconds. Default 30000; 0 disables it. */
  timeout?: number;
  /** Retries for 429/502/503/504 and network errors. Default 2; 0 disables them. */
  maxRetries?: number;
  /** A `fetch`-compatible function. Default `globalThis.fetch`. */
  fetch?: FetchLike;
  /** Appended to the `User-Agent` (server runtimes only). */
  userAgent?: string;
  /** Allow a private key in a browser. Never do this in a public bundle. */
  dangerouslyAllowPrivateKeyInBrowser?: boolean;
  /** Replaces the retry wait, for tests. */
  sleep?: SleepLike;
}

function normalizeBaseUrl(value: string): { baseUrl: string; origin: string } {
  let url: URL;
  try {
    url = new URL(value);
  } catch {
    throw invalidArgument("baseUrl must be an absolute HTTP(S) URL.");
  }
  if (!["https:", "http:"].includes(url.protocol) || url.username || url.password || url.search || url.hash || value.includes("?") || value.includes("#"))
    throw invalidArgument("baseUrl must be an HTTP(S) URL without credentials, query or fragment.");
  return { baseUrl: url.href.replace(/\/$/, ""), origin: url.origin };
}

/**
 * The NullDull client. Holds only configuration and is safe to share.
 *
 * ```ts
 * const nulldull = new NullDullClient({ apiKey: process.env.NULLDULL_PRIVATE_KEY!, workspaceId: "…" });
 * const page = await nulldull.grid.getPage("my-blog", "hello-world");
 * ```
 */
export class NullDullClient {
  /** Published Grid content. */
  readonly grid: GridApi;
  /** Read-only Memory. */
  readonly memory: MemoryApi;
  /** Locale export. */
  readonly locale: LocaleApi;
  readonly baseUrl: string;
  readonly workspaceId: string | undefined;
  readonly keyKind: "public" | "private";

  constructor(options: NullDullClientOptions) {
    if (!options || typeof options !== "object") throw invalidArgument("Pass client options with an apiKey.");
    const { apiKey, workspaceId } = options;
    if (typeof apiKey !== "string" || !API_KEY.test(apiKey))
      throw invalidArgument("apiKey must be a NullDull workspace API key (nd_pub_… or nd_sec_…).");
    if (workspaceId !== undefined && (typeof workspaceId !== "string" || !WORKSPACE_ID.test(workspaceId)))
      throw invalidArgument("workspaceId must be 1–128 letters, numbers, hyphens or underscores.");
    const timeout = options.timeout ?? 30_000;
    if (!Number.isFinite(timeout) || timeout < 0) throw invalidArgument("timeout must be zero or a positive number of milliseconds.");
    const maxRetries = options.maxRetries ?? 2;
    if (!Number.isInteger(maxRetries) || maxRetries < 0) throw invalidArgument("maxRetries must be a whole number, zero or more.");
    const fetcher = options.fetch ?? (typeof globalThis.fetch === "function" ? globalThis.fetch.bind(globalThis) : undefined);
    if (typeof fetcher !== "function") throw invalidArgument("No fetch implementation found. Pass options.fetch (Node 18+ has one built in).");
    const browser = isBrowser();
    this.keyKind = apiKey.startsWith("nd_pub_") ? "public" : "private";
    if (browser && this.keyKind === "private" && !options.dangerouslyAllowPrivateKeyInBrowser)
      throw invalidArgument("Never use a private NullDull API key in a browser. Use a public key (nd_pub_…).");
    const { baseUrl, origin } = normalizeBaseUrl(options.baseUrl ?? DEFAULT_BASE_URL);
    this.baseUrl = baseUrl;
    this.workspaceId = workspaceId;
    const transport = new Transport({
      apiKey,
      baseUrl,
      timeout,
      maxRetries,
      fetch: fetcher,
      userAgent: `nulldull-sdk-node/${VERSION}${options.userAgent ? ` ${options.userAgent}` : ""}`,
      browser,
      sleep: options.sleep ?? defaultSleep,
    });
    const root = workspaceGuard(workspaceId, this.keyKind === "public");
    this.grid = new GridApi(transport, origin, this.keyKind === "public" ? apiKey : undefined);
    this.memory = new MemoryApi(transport, root);
    this.locale = new LocaleApi(transport, root);
  }
}
