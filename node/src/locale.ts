import { invalidArgument } from "./errors";
import type { RequestOptions } from "./grid";
import type { Transport } from "./http";
import type { LocaleExport, LocaleFormatId, LocaleFormatList, LocaleKeyStatus } from "./types";

export interface LocaleExportParams extends RequestOptions {
  /** Default `json`. See `listFormats()` for the others. */
  format?: LocaleFormatId;
  /** Languages to export (comma-joined on the wire). Default: every configured language. */
  languages?: readonly string[] | string;
  /** Only keys with these statuses (comma-joined on the wire). Default: every status. */
  status?: readonly LocaleKeyStatus[] | LocaleKeyStatus;
  /** Base file name without extension, for example `Localizable`. */
  basename?: string;
}

const list = (value: readonly string[] | string | undefined, name: string) => {
  if (value === undefined) return undefined;
  const items = typeof value === "string" ? [value] : value;
  if (!Array.isArray(items) || items.some((item) => typeof item !== "string" || !item || item.includes(",")))
    throw invalidArgument(`${name} must be a list of non-empty strings without commas.`);
  return items.length ? items.join(",") : undefined;
};

/** Locale catalog export (`locale:read`). Needs a private key and `workspaceId`. */
export class LocaleApi {
  /** @internal */
  constructor(
    private readonly transport: Transport,
    private readonly root: () => string,
  ) {}

  /** Export formats with their capabilities and file roles. */
  async listFormats(options: RequestOptions = {}): Promise<LocaleFormatList> {
    return this.transport.json(this.root() + "/locale/formats", {}, options.signal);
  }

  /**
   * Exports a location's catalog as text files: one file set per language for single-language
   * formats (`en.json`, `values-tr/strings.xml`), one file for `xcstrings`. Never an archive.
   */
  async export(scopeId: string, params: LocaleExportParams = {}): Promise<LocaleExport> {
    if (typeof scopeId !== "string" || !scopeId) throw invalidArgument("scopeId must be a non-empty string.");
    const root = this.root();
    return this.transport.json(root + "/locale/export", {
      scopeId,
      format: params.format ?? "json",
      languages: list(params.languages, "languages"),
      status: list(params.status, "status"),
      basename: params.basename,
    }, params.signal);
  }
}
