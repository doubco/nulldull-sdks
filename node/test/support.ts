import { readFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { NullDullClient, type NullDullClientOptions } from "../src";

export const FIXTURES = join(dirname(fileURLToPath(import.meta.url)), "..", "..", "fixtures");

export const fixture = <T = any>(path: string): T => JSON.parse(readFileSync(join(FIXTURES, path), "utf8"));

export interface Exchange {
  request: { method: string; path: string; query: Record<string, string[]> };
  response: { status: number; headers?: Record<string, string>; bodyFile?: string; body?: string; bodyBase64?: string };
}
export interface Case {
  id: string;
  key: "public" | "private";
  call: { method: string; args: unknown[] };
  exchanges: Exchange[];
  expect: {
    resultFile?: string;
    except?: string[];
    checks?: { path: string; equals: unknown }[];
    itemCount?: number;
    download?: { contentType: string | null; filename: string | null; size: number; bytesBase64: string };
    error?: Record<string, unknown>;
    attempts?: number;
    sleeps?: number[];
  };
}
export interface Manifest {
  config: { baseUrl: string; publicKey: string; privateKey: string; workspaceId: string };
  cases: Case[];
}

export const manifest = fixture<Manifest>("manifest.json");

export interface Recorded {
  url: URL;
  init: RequestInit;
  headers: Headers;
}

export function responseFrom(spec: Exchange["response"]): Response {
  const body = spec.bodyFile !== undefined
    ? readFileSync(join(FIXTURES, spec.bodyFile))
    : spec.bodyBase64 !== undefined
      ? Buffer.from(spec.bodyBase64, "base64")
      : spec.body ?? "";
  return new Response(body, { status: spec.status, headers: spec.headers ?? {} });
}

/** A fetch that answers with queued responses (or a handler) and records every request. */
export function mockFetch(responses: (Response | Error | ((url: URL, init: RequestInit) => Response | Promise<Response>))[] = []) {
  const requests: Recorded[] = [];
  const queue = [...responses];
  const fetch = async (input: string, init: RequestInit = {}) => {
    const url = new URL(input);
    requests.push({ url, init, headers: new Headers(init.headers) });
    const next = queue.shift();
    if (next === undefined) throw new Error(`Unexpected request: GET ${url.href}`);
    if (next instanceof Error) throw next;
    if (typeof next === "function") return next(url, init);
    return next;
  };
  return { fetch, requests };
}

export function clientFor(kind: "public" | "private", fetch: NullDullClientOptions["fetch"], extra: Partial<NullDullClientOptions> = {}) {
  const sleeps: number[] = [];
  const client = new NullDullClient({
    apiKey: kind === "public" ? manifest.config.publicKey : manifest.config.privateKey,
    baseUrl: manifest.config.baseUrl,
    workspaceId: manifest.config.workspaceId,
    fetch,
    sleep: async (ms) => {
      sleeps.push(ms);
    },
    ...extra,
  });
  return { client, sleeps };
}

/** Query parameters as a multimap: name -> values in order. */
export function multimap(url: URL): Record<string, string[]> {
  const out: Record<string, string[]> = {};
  for (const [name, value] of url.searchParams) (out[name] ??= []).push(value);
  return out;
}

export function at(value: unknown, path: string): unknown {
  return path.split(".").reduce<any>((current, part) => (current == null ? undefined : current[/^\d+$/.test(part) ? Number(part) : part]), value);
}

export function without(value: unknown, paths: string[] = []): unknown {
  const copy = structuredClone(value) as any;
  for (const path of paths) {
    const parts = path.split(".");
    const last = parts.pop()!;
    const parent = parts.length ? at(copy, parts.join(".")) : copy;
    if (parent && typeof parent === "object") delete (parent as any)[/^\d+$/.test(last) ? Number(last) : last];
  }
  return copy;
}

/** Invokes a canonical method name such as `memory.listDocuments` and collects iterators. */
export async function invoke(client: NullDullClient, method: string, args: unknown[]): Promise<unknown> {
  const [namespace, name] = method.split(".") as [keyof NullDullClient, string];
  const target = client[namespace] as any;
  const result = target[name](...args);
  if (name.startsWith("iterate")) {
    const items: unknown[] = [];
    for await (const item of result) items.push(item);
    return items;
  }
  return result;
}
