import { NullDullError, clientError } from "./errors";
import type { Download, Page } from "./types";

/** A `fetch`-compatible function. Defaults to `globalThis.fetch`. */
export type FetchLike = (input: string, init?: RequestInit) => Promise<Response>;
/** Waits `ms` milliseconds; must reject when `signal` aborts. Replaceable for tests. */
export type SleepLike = (ms: number, signal?: AbortSignal) => Promise<void>;

export type QueryValue = string | number | boolean | readonly string[] | null | undefined;
export type Query = Record<string, QueryValue>;

export interface TransportConfig {
  apiKey: string;
  baseUrl: string;
  timeout: number;
  maxRetries: number;
  fetch: FetchLike;
  userAgent: string | null;
  browser: boolean;
  sleep: SleepLike;
}

/** Retry-After values above this (seconds) are raised instead of waited for (SPEC.md section 6). */
export const MAX_RETRY_AFTER_SECONDS = 30;
const RETRYABLE = new Set([429, 502, 503, 504]);
const backoff = (retry: number) => 500 * 2 ** (retry - 1);

interface RawResponse {
  status: number;
  headers: Headers;
  bytes: Uint8Array;
}

export const isBrowser = () => typeof window !== "undefined" && typeof document !== "undefined";

export const defaultSleep: SleepLike = (ms, signal) =>
  new Promise((resolve, reject) => {
    if (signal?.aborted) return reject(aborted(signal.reason));
    const timer = setTimeout(() => {
      signal?.removeEventListener("abort", onAbort);
      resolve();
    }, ms);
    const onAbort = () => {
      clearTimeout(timer);
      reject(aborted(signal?.reason));
    };
    signal?.addEventListener("abort", onAbort, { once: true });
  });

const aborted = (cause?: unknown) => clientError("ABORTED", "The request was cancelled.", cause);

/** Percent-encodes a query string. Absent values are omitted and lists repeat the key. */
export function queryString(query: Query = {}): string {
  const parts: string[] = [];
  for (const [name, value] of Object.entries(query)) {
    if (value === undefined || value === null) continue;
    const values = Array.isArray(value) ? value : [String(value)];
    for (const item of values) parts.push(`${encodeURIComponent(name)}=${encodeURIComponent(item)}`);
  }
  return parts.length ? `?${parts.join("&")}` : "";
}

export const segment = (value: string) => encodeURIComponent(value);

function header(headers: Headers, name: string) {
  const value = headers.get(name);
  return value === null || value === "" ? null : value;
}

/** Seconds from a `Retry-After` header (delta-seconds or HTTP date), or null. */
export function parseRetryAfter(value: string | null, now = Date.now()): number | null {
  if (value === null) return null;
  const trimmed = value.trim();
  if (/^\d+$/.test(trimmed)) return Number(trimmed);
  const date = Date.parse(trimmed);
  if (Number.isNaN(date)) return null;
  return Math.max(0, Math.ceil((date - now) / 1000));
}

/** File name from `Content-Disposition`: RFC 5987 `filename*` first, then `filename`. */
export function parseFilename(value: string | null): string | null {
  if (!value) return null;
  const extended = /filename\*\s*=\s*([^']*)'[^']*'([^;]+)/i.exec(value);
  if (extended?.[2]) {
    try {
      return decodeURIComponent(extended[2].trim());
    } catch {
      /* fall through to the plain parameter */
    }
  }
  const quoted = /(?:^|;)\s*filename\s*=\s*"((?:[^"\\]|\\.)*)"/i.exec(value);
  if (quoted?.[1] !== undefined) return quoted[1].replace(/\\(.)/g, "$1");
  const plain = /(?:^|;)\s*filename\s*=\s*([^;]+)/i.exec(value);
  return plain?.[1] ? plain[1].trim() : null;
}

function errorFrom(response: RawResponse): NullDullError {
  let body: Record<string, unknown> | null = null;
  try {
    const parsed: unknown = JSON.parse(new TextDecoder().decode(response.bytes));
    if (parsed && typeof parsed === "object" && !Array.isArray(parsed)) body = parsed as Record<string, unknown>;
  } catch {
    /* Not JSON: a router page, a gateway error or an empty body. */
  }
  const code = typeof body?.code === "string" ? body.code : "REQUEST_FAILED";
  return new NullDullError({
    status: response.status,
    code,
    message: typeof body?.message === "string" ? body.message : undefined,
    detail: typeof body?.detail === "string" ? body.detail : null,
    requestId: header(response.headers, "x-request-id") ?? header(response.headers, "cf-ray"),
    retryAfter: parseRetryAfter(response.headers.get("retry-after")),
    body,
  });
}

export class Transport {
  constructor(readonly config: TransportConfig) {}

  /** GETs a JSON resource under `baseUrl`. */
  async json<T>(path: string, query: Query = {}, signal?: AbortSignal): Promise<T> {
    const response = await this.send(this.config.baseUrl + path + queryString(query), "application/json", true, signal);
    try {
      return JSON.parse(new TextDecoder().decode(response.bytes)) as T;
    } catch (cause) {
      throw new NullDullError({
        status: response.status,
        code: "INVALID_RESPONSE",
        message: "NullDull returned a response that is not valid JSON.",
        requestId: header(response.headers, "x-request-id") ?? header(response.headers, "cf-ray"),
        cause,
      });
    }
  }

  /** GETs bytes from a path under `baseUrl`, or from an absolute URL. */
  async download(target: { path: string; query?: Query } | { url: string; authorize: boolean }, signal?: AbortSignal): Promise<Download> {
    const url = "url" in target ? target.url : this.config.baseUrl + target.path + queryString(target.query);
    const authorize = "url" in target ? target.authorize : true;
    const response = await this.send(url, "*/*", authorize, signal);
    return {
      bytes: response.bytes,
      contentType: header(response.headers, "content-type"),
      filename: parseFilename(response.headers.get("content-disposition")),
      size: response.bytes.byteLength,
    };
  }

  private async send(url: string, accept: string, authorize: boolean, signal?: AbortSignal): Promise<RawResponse> {
    const headers: Record<string, string> = { Accept: accept };
    if (authorize) headers.Authorization = `Bearer ${this.config.apiKey}`;
    if (this.config.userAgent && !this.config.browser) headers["User-Agent"] = this.config.userAgent;
    for (let retry = 0; ; retry++) {
      let response: RawResponse;
      try {
        response = await this.attempt(url, headers, signal);
      } catch (error) {
        if (error instanceof NullDullError && error.code === "NETWORK_ERROR" && retry < this.config.maxRetries) {
          await this.config.sleep(backoff(retry + 1), signal);
          continue;
        }
        throw error;
      }
      if (response.status >= 200 && response.status < 300) return response;
      const error = errorFrom(response);
      if (!RETRYABLE.has(response.status) || retry >= this.config.maxRetries) throw error;
      if (error.retryAfter !== null && error.retryAfter > MAX_RETRY_AFTER_SECONDS) throw error;
      await this.config.sleep(error.retryAfter !== null ? error.retryAfter * 1000 : backoff(retry + 1), signal);
    }
  }

  /** One attempt: fetch and read the whole body within the timeout. */
  private async attempt(url: string, headers: Record<string, string>, signal?: AbortSignal): Promise<RawResponse> {
    if (signal?.aborted) throw aborted(signal.reason);
    const controller = new AbortController();
    let timedOut = false;
    const onAbort = () => controller.abort(signal?.reason);
    signal?.addEventListener("abort", onAbort, { once: true });
    const timer = this.config.timeout > 0
      ? setTimeout(() => {
          timedOut = true;
          controller.abort();
        }, this.config.timeout)
      : undefined;
    try {
      const init: RequestInit = { method: "GET", headers, redirect: "manual", signal: controller.signal };
      // Browsers only: some server runtimes (Cloudflare Workers) reject the `credentials` field.
      if (this.config.browser) init.credentials = "omit";
      // Race both steps against the abort signal: a custom fetch may not cancel its body stream.
      const stopped = new Promise<never>((_, reject) => {
        const stop = () => reject(controller.signal.reason ?? new Error("aborted"));
        if (controller.signal.aborted) stop();
        else controller.signal.addEventListener("abort", stop, { once: true });
      });
      stopped.catch(() => {});
      const response = await Promise.race([this.config.fetch(url, init), stopped]);
      const bytes = new Uint8Array(await Promise.race([response.arrayBuffer(), stopped]));
      return { status: response.status, headers: response.headers, bytes };
    } catch (error) {
      if (error instanceof NullDullError) throw error;
      if (timedOut) throw clientError("TIMEOUT", `The request timed out after ${this.config.timeout} ms.`, error);
      if (signal?.aborted) throw aborted(signal.reason ?? error);
      throw clientError("NETWORK_ERROR", "The request could not reach NullDull.", error);
    } finally {
      if (timer !== undefined) clearTimeout(timer);
      signal?.removeEventListener("abort", onAbort);
    }
  }
}

/** Yields items across pages, following `nextCursor` until it is null (SPEC.md section 7). */
export async function* paginate<T>(load: (after: string | undefined) => Promise<Page<T>>, start?: string): AsyncGenerator<T, void, undefined> {
  let after = start;
  for (;;) {
    const page = await load(after);
    for (const item of page.items) yield item;
    if (page.nextCursor === null || page.nextCursor === undefined) return;
    if (page.nextCursor === after)
      throw clientError("INVALID_RESPONSE", "Pagination did not advance: the API returned the same cursor again.");
    after = page.nextCursor;
  }
}
