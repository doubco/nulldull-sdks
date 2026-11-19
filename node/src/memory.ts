import { clientError, invalidArgument } from "./errors";
import { paginate, segment, type Query, type Transport } from "./http";
import type { RequestOptions } from "./grid";
import type {
  Asset,
  AssetVersion,
  Document,
  DocumentSummary,
  Download,
  FileKind,
  FileLifecycle,
  Folder,
  FolderList,
  FolderSummary,
  LinkResolution,
  Page,
  Scope,
  SearchResult,
  TagCount,
} from "./types";

/** A folder ID, or `null` (or `"root"`) for the location root. Omit for no folder filter. */
export type FolderFilter = string | null;

export interface CursorParams extends RequestOptions {
  after?: string;
}
export interface ListFoldersParams extends CursorParams {
  scopeId?: string;
  /** Parent folder, or `null` for top-level folders. Omit for every readable folder. */
  parentId?: FolderFilter;
}
export interface LabelFilters {
  /** Every listed tag must be present (sent as repeated `tag`). */
  tags?: readonly string[];
  kind?: FileKind;
  lifecycle?: FileLifecycle;
}
export interface ListDocumentsParams extends CursorParams, LabelFilters {
  scopeId?: string;
  /** Folder, or `null` for unfiled documents. Omit for every folder. */
  folderId?: FolderFilter;
}
export interface SearchParams extends CursorParams, LabelFilters {
  /** Limits the search to this location and its descendants. */
  scopeId?: string;
}
export interface ListTagsParams extends CursorParams {
  scopeId?: string;
  /** Substring of the tag, up to 48 characters. */
  q?: string;
}
export interface ListAssetsParams extends CursorParams {
  scopeId?: string;
  /** Folder, or `null` for unfiled assets. Omit for every folder. */
  folderId?: FolderFilter;
  /** Substring of name, description or tags, up to 160 characters. */
  q?: string;
  tags?: readonly string[];
}
export interface GetAssetParams extends RequestOptions {
  /** A specific immutable version instead of the current one. */
  revisionId?: string;
}
export interface DownloadAssetParams extends RequestOptions {
  revisionId?: string;
  /** Serve images inline (`preview=true`). Implied by `width`. */
  preview?: boolean;
  /** Resized WebP width in pixels for PNG, JPEG, WebP and AVIF (snaps up to 64…2048). */
  width?: number;
}

const folder = (value: FolderFilter | undefined) => (value === undefined ? undefined : value === null ? "root" : value);
const tags = (value: readonly string[] | undefined) => (value && value.length ? value : undefined);

function id(value: unknown, name: string): string {
  if (typeof value !== "string" || !value) throw invalidArgument(`${name} must be a non-empty string.`);
  return segment(value);
}

/** Read-only Memory (`memory:read`). Needs a private key and `workspaceId`. */
export class MemoryApi {
  /** @internal */
  constructor(
    private readonly transport: Transport,
    private readonly root: () => string,
  ) {}

  private get<T>(path: string, query: Query, signal?: AbortSignal) {
    return this.transport.json<T>(this.root() + path, query, signal);
  }

  /** Locations the key's member can see (workspace root, products, projects). */
  async listScopes(params: CursorParams = {}): Promise<Page<Scope>> {
    return this.get("/scopes", { after: params.after }, params.signal);
  }
  iterateScopes(params: CursorParams = {}) {
    const { after, ...rest } = params;
    return paginate((cursor) => this.listScopes({ ...rest, after: cursor }), after);
  }

  /** Readable folders, optionally in one location or under one parent. */
  async listFolders(params: ListFoldersParams = {}): Promise<FolderList> {
    return this.get("/folders", { scopeId: params.scopeId, parentId: folder(params.parentId), after: params.after }, params.signal);
  }
  iterateFolders(params: ListFoldersParams = {}): AsyncGenerator<FolderSummary, void, undefined> {
    const { after, ...rest } = params;
    return paginate((cursor) => this.listFolders({ ...rest, after: cursor }), after);
  }

  /** A folder with its ancestors and effective placement. */
  async getFolder(folderId: string, options: RequestOptions = {}): Promise<Folder> {
    return this.get(`/folders/${id(folderId, "folderId")}`, {}, options.signal);
  }

  /** Readable documents (Markdown files) without their content. */
  async listDocuments(params: ListDocumentsParams = {}): Promise<Page<DocumentSummary>> {
    return this.get("/documents", {
      scopeId: params.scopeId,
      folderId: folder(params.folderId),
      tag: tags(params.tags),
      kind: params.kind,
      lifecycle: params.lifecycle,
      after: params.after,
    }, params.signal);
  }
  iterateDocuments(params: ListDocumentsParams = {}) {
    const { after, ...rest } = params;
    return paginate((cursor) => this.listDocuments({ ...rest, after: cursor }), after);
  }

  /** A document with its saved Markdown `content`. */
  async getDocument(documentId: string, options: RequestOptions = {}): Promise<Document> {
    return this.get(`/documents/${id(documentId, "documentId")}`, {}, options.signal);
  }

  /** Resolves a relative Markdown link inside a document to another readable document. */
  async resolveLink(documentId: string, href: string, options: RequestOptions = {}): Promise<LinkResolution> {
    if (typeof href !== "string") throw invalidArgument("href must be a string.");
    return this.get(`/documents/${id(documentId, "documentId")}/resolve-link`, { href }, options.signal);
  }

  /** Literal, case-insensitive search (2–160 characters) over names, content and tags. */
  async search(q: string, params: SearchParams = {}): Promise<Page<SearchResult>> {
    if (typeof q !== "string") throw invalidArgument("q must be a string.");
    return this.get("/search", {
      q,
      scopeId: params.scopeId,
      tag: tags(params.tags),
      kind: params.kind,
      lifecycle: params.lifecycle,
      after: params.after,
    }, params.signal);
  }
  iterateSearch(q: string, params: SearchParams = {}) {
    const { after, ...rest } = params;
    return paginate((cursor) => this.search(q, { ...rest, after: cursor }), after);
  }

  /** Tags on readable documents with their counts, most used first. */
  async listTags(params: ListTagsParams = {}): Promise<Page<TagCount>> {
    return this.get("/tags", { scopeId: params.scopeId, q: params.q, after: params.after }, params.signal);
  }
  iterateTags(params: ListTagsParams = {}) {
    const { after, ...rest } = params;
    return paginate((cursor) => this.listTags({ ...rest, after: cursor }), after);
  }

  /** Readable Memory assets with metadata. */
  async listAssets(params: ListAssetsParams = {}): Promise<Page<Asset>> {
    return this.get("/assets", {
      scopeId: params.scopeId,
      folderId: folder(params.folderId),
      q: params.q,
      tag: tags(params.tags),
      after: params.after,
    }, params.signal);
  }
  iterateAssets(params: ListAssetsParams = {}) {
    const { after, ...rest } = params;
    return paginate((cursor) => this.listAssets({ ...rest, after: cursor }), after);
  }

  /** An asset's metadata, current object (filename, media type, SHA-256) and usage guidance. */
  async getAsset(assetId: string, params: GetAssetParams = {}): Promise<Asset> {
    return this.get(`/assets/${id(assetId, "assetId")}`, { revisionId: params.revisionId }, params.signal);
  }

  /** An asset's immutable versions, newest first. */
  async listAssetVersions(assetId: string, params: CursorParams = {}): Promise<Page<AssetVersion>> {
    return this.get(`/assets/${id(assetId, "assetId")}/versions`, { after: params.after }, params.signal);
  }
  iterateAssetVersions(assetId: string, params: CursorParams = {}) {
    const { after, ...rest } = params;
    return paginate((cursor) => this.listAssetVersions(assetId, { ...rest, after: cursor }), after);
  }

  /** Downloads an asset's bytes, or a resized preview with `width`. */
  async downloadAsset(assetId: string, params: DownloadAssetParams = {}): Promise<Download> {
    const { width } = params;
    if (width !== undefined && (!Number.isInteger(width) || width < 1))
      throw invalidArgument("width must be a positive whole number of pixels.");
    const path = this.root() + `/assets/${id(assetId, "assetId")}/download`;
    return this.transport.download({
      path,
      query: { revisionId: params.revisionId, preview: params.preview || width !== undefined ? "true" : undefined, w: width },
    }, params.signal);
  }
}

export const workspaceGuard = (workspaceId: string | undefined, publicKey: boolean) => () => {
  if (publicKey)
    throw clientError("PRIVATE_KEY_REQUIRED", "Memory and Locale need a private key (nd_sec_…) with the matching scope.");
  if (!workspaceId)
    throw clientError("WORKSPACE_REQUIRED", "Memory and Locale need workspaceId: a key cannot look up its own workspace.");
  return `/api/platform/workspaces/${segment(workspaceId)}`;
};
