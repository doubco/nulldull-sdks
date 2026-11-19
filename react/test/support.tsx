import { readFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { NullDullClient, type NullDullClientOptions } from "@nulldull/sdk";
import type { ReactNode } from "react";
import { NullDullProvider } from "../src";

export const FIXTURES = join(dirname(fileURLToPath(import.meta.url)), "..", "..", "fixtures");
export const fixture = <T = any>(path: string): T => JSON.parse(readFileSync(join(FIXTURES, path), "utf8"));
export const config = fixture<{ config: { baseUrl: string; publicKey: string; privateKey: string; workspaceId: string } }>("manifest.json").config;

export const json = (body: unknown, status = 200, headers: Record<string, string> = {}) =>
  new Response(typeof body === "string" ? body : JSON.stringify(body), {
    status,
    headers: { "content-type": "application/json", ...headers },
  });
export const fromFixture = (path: string, status = 200, headers: Record<string, string> = {}) =>
  new Response(readFileSync(join(FIXTURES, path)), { status, headers: { "content-type": "application/json", ...headers } });

export interface Recorded {
  url: URL;
  init: RequestInit;
}

type Reply = Response | ((url: URL, init: RequestInit) => Response | Promise<Response>);

/** A fetch that answers in order from `replies` and records every request. */
export function mockFetch(replies: Reply[] = []) {
  const requests: Recorded[] = [];
  const queue = [...replies];
  const fetch = async (input: string, init: RequestInit = {}) => {
    const url = new URL(input);
    requests.push({ url, init });
    const next = queue.shift();
    if (next === undefined) throw new Error(`Unexpected request: GET ${url.href}`);
    return typeof next === "function" ? next(url, init) : next;
  };
  return { fetch, requests, push: (...more: Reply[]) => queue.push(...more) };
}

/** A reply that waits until `release()` is called or the request is aborted. */
export function deferred(response: () => Response) {
  let release!: () => void;
  const gate = new Promise<void>((resolve) => (release = resolve));
  const reply = (_url: URL, init: RequestInit) =>
    new Promise<Response>((resolve, reject) => {
      init.signal?.addEventListener("abort", () => reject(new DOMException("Aborted", "AbortError")), { once: true });
      void gate.then(() => resolve(response()));
    });
  return { reply, release: () => release() };
}

export function makeClient(kind: "public" | "private", fetch: NullDullClientOptions["fetch"], extra: Partial<NullDullClientOptions> = {}) {
  return new NullDullClient({
    apiKey: kind === "public" ? config.publicKey : config.privateKey,
    baseUrl: config.baseUrl,
    workspaceId: config.workspaceId,
    fetch,
    maxRetries: 0,
    // jsdom has window and document; memory tests use a private key on purpose.
    dangerouslyAllowPrivateKeyInBrowser: kind === "private",
    ...extra,
  });
}

export function wrapperFor(client: NullDullClient) {
  return ({ children }: { children: ReactNode }) => <NullDullProvider client={client}>{children}</NullDullProvider>;
}
