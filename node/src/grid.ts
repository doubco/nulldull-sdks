import { invalidArgument } from "./errors";
import { paginate, segment, type Transport } from "./http";
import type { Download, GridAssetRef, GridCover, GridPage, GridPageList, GridPageSummary } from "./types";

const KEY = /^[a-z0-9]+(?:-[a-z0-9]+)*$/;
const LOCALE = /^[a-z]{2,3}(?:-[a-z0-9]{2,8})*$/;

export interface RequestOptions {
  /** Cancels the request (raises `ABORTED`). */
  signal?: AbortSignal;
}

export interface ListPagesParams extends RequestOptions {
  /** Content language, lowercase (`en`, `pt-br`). Default `en`. */
  locale?: string;
  /** Literal search over titles and summaries, up to 160 characters. */
  q?: string;
  /** Only pages whose direct parent folder at publication was this folder. */
  folderId?: string;
  /** 1–50, default 20 (server side). */
  limit?: number;
  /** Cursor from `nextCursor`. */
  after?: string;
}

export interface GetPageParams extends RequestOptions {
  locale?: string;
}

function key(value: unknown, name: string): string {
  if (typeof value !== "string" || value.length > 96 || !KEY.test(value))
    throw invalidArgument(`${name} must be 1–96 lowercase letters, numbers and single hyphens.`);
  return value;
}

function locale(value: unknown = "en"): string {
  if (typeof value !== "string" || value.length > 35 || !LOCALE.test(value))
    throw invalidArgument("locale must be a lowercase language tag, such as en or pt-br.");
  return value;
}

/** Published Grid content (`grid:published`). Works with public and private keys. */
export class GridApi {
  /** @internal */
  constructor(
    private readonly transport: Transport,
    private readonly origin: string,
    private readonly publicKey: string | undefined,
  ) {}

  /** One page of a pool's published pages, newest first. */
  async listPages(pool: string, params: ListPagesParams = {}): Promise<GridPageList> {
    const path = `/api/grid/v1/pools/${segment(key(pool, "pool"))}/pages`;
    const { limit } = params;
    if (limit !== undefined && (!Number.isInteger(limit) || limit < 1 || limit > 50))
      throw invalidArgument("limit must be a whole number from 1 to 50.");
    if (params.folderId !== undefined && (typeof params.folderId !== "string" || !params.folderId))
      throw invalidArgument("folderId must be a non-empty string.");
    const list = await this.transport.json<GridPageList>(path, {
      locale: locale(params.locale),
      q: params.q ? params.q : undefined,
      folderId: params.folderId,
      limit,
      after: params.after ? params.after : undefined,
    }, params.signal);
    return { ...list, items: list.items.map((item) => this.summary(item)) };
  }

  /** Every published page across all pages of results. Empty pages with a cursor are followed. */
  iteratePages(pool: string, params: ListPagesParams = {}): AsyncGenerator<GridPageSummary, void, undefined> {
    const { after, ...rest } = params;
    return paginate((cursor) => this.listPages(pool, { ...rest, after: cursor }), after);
  }

  /** A published page with its document and version-pinned asset manifest. */
  async getPage(pool: string, slug: string, params: GetPageParams = {}): Promise<GridPage> {
    const path = `/api/grid/v1/pools/${segment(key(pool, "pool"))}/pages/${segment(key(slug, "slug"))}`;
    const page = await this.transport.json<GridPage>(path, { locale: locale(params.locale) }, params.signal);
    return {
      ...this.summary(page),
      document: page.document,
      assets: (page.assets ?? []).map((asset) => ({ ...asset, url: this.assetUrl(asset.url) })),
    };
  }

  /**
   * Resolves an asset or cover URL against the API origin. For a public key and a URL on the API's
   * own origin, adds `key` so images, fonts and media can load without headers. Never adds a private
   * key, and never adds a key to another origin.
   */
  assetUrl(url: string): string {
    let resolved: URL;
    try {
      resolved = new URL(url, this.origin);
    } catch {
      throw invalidArgument("Provide a valid asset URL.");
    }
    if (this.publicKey && resolved.origin === this.origin && !resolved.searchParams.has("key"))
      resolved.searchParams.set("key", this.publicKey);
    return resolved.href;
  }

  /** Downloads an asset or cover. Sends the key only to the API's own origin. */
  async downloadAsset(target: string | { url: string }, options: RequestOptions = {}): Promise<Download> {
    const raw = typeof target === "string" ? target : target?.url;
    if (typeof raw !== "string" || !raw) throw invalidArgument("Provide an asset URL or an object with a url.");
    const url = this.assetUrl(raw);
    return this.transport.download({ url, authorize: new URL(url).origin === this.origin }, options.signal);
  }

  private summary<T extends GridPageSummary>(page: T): T {
    if (!page.cover) return page;
    return { ...page, cover: { ...page.cover, url: this.assetUrl(page.cover.url) } as GridCover };
  }
}

export type { GridAssetRef };
