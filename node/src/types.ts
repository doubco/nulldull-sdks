/**
 * Response types. Every type is the API's JSON object, unchanged (see SPEC.md section 9).
 * New fields may appear at any time; enum-like unions also accept unknown strings.
 */

/** A string union that still accepts values added by the API later. */
export type OpenString<T extends string> = T | (string & {});

/** One page of a list: pass `nextCursor` back as `after` until it is `null`. */
export interface Page<T> {
  items: T[];
  nextCursor: string | null;
}

// ---------------------------------------------------------------- Grid

export interface GridAssetRef {
  id: string;
  /** Publication-pinned asset version. */
  version: number;
  /** Absolute URL (normalized by `grid.assetUrl`). */
  url: string;
  filename: string;
  mediaType: string;
  byteSize: number;
  /** SHA-256, hex. */
  checksum: string;
}

export interface GridCover extends GridAssetRef {
  /** Alternative text; empty means decorative. */
  alt: string;
}

export interface GridPageSummary {
  id: string;
  pool: string;
  slug: string;
  locale: string;
  title: string;
  summary: string;
  /** The publication's own version. */
  version: number;
  /** The saved editor version that was published. */
  sourceVersion: number;
  /** Unix epoch milliseconds. */
  publishedAt: number;
  /** Direct parent folder at publication; older snapshots may omit it. */
  folderId?: string | null;
  cover?: GridCover | null;
}

/** The published Grid document. Its full schema belongs to `@nulldull/grid-core`. */
export interface GridDocument {
  layout: Record<string, unknown>;
  breakpoints: Record<string, unknown>[];
  baseLayoutIndex?: number;
  baseLayoutName?: string;
  nodes: Record<string, unknown>[];
  [key: string]: unknown;
}

export interface GridPageTarget {
  entryId: string;
  published: true;
  pool: string;
  slug: string;
  locale: string;
}

export interface GridPage extends GridPageSummary {
  pageTargets?: Record<string, GridPageTarget>;
  document: GridDocument;
  assets: GridAssetRef[];
}

export interface GridPageList extends Page<GridPageSummary> {
  pool: { key: string; name: string };
}

// ---------------------------------------------------------------- Memory

export type LocationKind = OpenString<"workspace" | "customer-product" | "project">;
export type FileKind = OpenString<"rules" | "tasks" | "plan" | "reference" | "procedure" | "notes" | "unknown">;
export type FileLifecycle = OpenString<"maintained" | "one-time" | "unknown">;
export type FileRole = OpenString<"senior" | "junior">;

export interface LocationIcon {
  iconKind?: OpenString<"symbol" | "emoji" | "image"> | null;
  iconValue?: string | null;
  iconVersion?: number;
}

/** A location: the workspace root, a customer product or a project. */
export interface Scope extends LocationIcon {
  id: string;
  name: string;
  kind: LocationKind;
  parentId: string | null;
}

/** One level of a location path, root first. */
export type LocationPathItem = Scope;

export interface Placement {
  repository: string | null;
  path: string;
  /** Folder names joined with `/`; `""` at the location root. */
  folderPath: string;
}

export interface FileLabels {
  tags: string[];
  labelKind: FileKind | null;
  labelLifecycle: FileLifecycle | null;
  labelSource: OpenString<"ai" | "manual"> | null;
  labelStatus: OpenString<"ready" | "pending" | "failed" | "unclassified">;
}

export interface FolderBase {
  workspaceId: string;
  id: string;
  scopeId: string;
  parentId: string | null;
  name: string;
  createdBy: string;
  preferredRepository: string | null;
  preferredPath: string | null;
  metadataVersion: number;
}

export interface FolderSummary extends FolderBase {
  folderCount: number;
  documentCount: number;
  assetCount: number;
  secretCount: number;
  placement: Placement;
}

export interface FolderList extends Page<FolderSummary> {
  /** Only on the first page when both `scopeId` and `parentId` were given. */
  here?: { folders: number; documents: number; assets: number; secrets: number };
}

export interface Folder extends FolderBase {
  canManage: boolean;
  canDelete: boolean;
  placement: Placement;
  ancestors: { id: string; name: string }[];
  contents: OpenString<"empty" | "visible" | "hidden">;
}

export interface DocumentSummary extends FileLabels {
  id: string;
  name: string;
  scopeId: string;
  folderId: string | null;
  headRevisionId: string | null;
  preferredRepository: string | null;
  preferredPath: string | null;
  metadataVersion: number;
  role: FileRole;
}

export interface Document extends DocumentSummary {
  headAuthorMemberId: string | null;
  /** Saved Markdown (up to 128 KiB), or null before the first save. */
  content: string | null;
  contentHash: string | null;
  placement: Placement;
  locationPath: LocationPathItem[];
}

export interface SearchResult extends FileLabels {
  id: string;
  name: string;
  scopeId: string;
  folderId: string | null;
  headRevisionId: string | null;
  metadataVersion: number;
  role: FileRole;
  /** Up to 240 characters around the match. */
  excerpt: string;
  locationPath: LocationPathItem[];
  folderPath: string;
}

export interface TagCount {
  tag: string;
  count: number;
}

export type LinkResolution =
  | { status: "found"; id: string; fragment: string }
  | { status: "unavailable" }
  | { status: "ambiguous" };

export interface AssetObject {
  id: string;
  filename: string;
  mediaType: string;
  byteSize: number;
  checksum: string;
  authorMemberId: string;
  createdAt: number;
}

export interface Asset {
  id: string;
  name: string;
  scopeId: string;
  kind: "asset";
  folderId: string | null;
  folderPath: { id: string; name: string }[];
  headRevisionId: string | null;
  revisionId: string | null;
  metadataVersion: number;
  role: FileRole;
  /** Usage guidance written by people. */
  description: string;
  tags: string[];
  tagSource: OpenString<"manual" | "ai">;
  summary: string | null;
  insightStatus: OpenString<"ready" | "pending" | "failed" | "unavailable">;
  /** Null until a first version is uploaded. */
  object: AssetObject | null;
  locationPath: LocationPathItem[];
}

export interface AssetVersion {
  id: string;
  createdAt: number;
  authorMemberId: string;
}

// ---------------------------------------------------------------- Locale

export type LocaleFormatId = OpenString<"json" | "world" | "world-cldr" | "xcstrings" | "apple-strings" | "android-xml">;
export type LocaleKeyStatus = OpenString<"draft" | "needs_review" | "approved">;

export interface LocaleFormat {
  id: LocaleFormatId;
  label: string;
  capabilities: {
    /** `single`: one file set per language. `multi`: one file holds every language. */
    layout: OpenString<"single" | "multi">;
    plurals: OpenString<"cldr" | "one-other" | "none">;
    variables: OpenString<"named" | "positional">;
    status: boolean;
    description: boolean;
    variableTypes: boolean;
  };
  files: { role: string; extension: string; contentType: string; required: boolean }[];
}

export interface LocaleFormatList {
  items: LocaleFormat[];
}

export interface LocaleFile {
  /** Relative path such as `en.json` or `values-tr/strings.xml`. */
  path: string;
  contentType: string;
  /** UTF-8 text. */
  content: string;
}

export interface LocaleExportNote {
  code: string;
  key: string;
  language?: string;
}

export interface LocaleExport {
  format: LocaleFormatId;
  files: LocaleFile[];
  notes: LocaleExportNote[];
  contentVersion: number;
}

// ---------------------------------------------------------------- Downloads

export interface Download {
  bytes: Uint8Array;
  /** The `Content-Type` header. Non-preview Memory downloads are `application/octet-stream`. */
  contentType: string | null;
  /** From `Content-Disposition`; null when absent (for example resized previews). */
  filename: string | null;
  size: number;
}
