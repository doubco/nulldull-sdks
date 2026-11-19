package com.nulldull.sdk

/**
 * Locale catalog export (`locale:read`). Needs a private key and the client's `workspaceId`.
 */
public class LocaleApi internal constructor(
    private val transport: Transport,
    private val root: () -> String,
) {
    /** Export formats with their capabilities and file roles. */
    public suspend fun listFormats(): LocaleFormatList =
        transport.json(root() + "/locale/formats") { LocaleFormatList(it.asObject("the format list")) }

    /**
     * Exports a location's Locale catalog as text files.
     *
     * @param scopeId The location holding the Locale library. The workspace root's ID equals `workspaceId`.
     * @param format One of [LocaleFormatId]; always sent, default `json`.
     * @param languages Languages to export, comma-joined on the wire (at most 50). Null: every configured language.
     * @param status Only keys with these [LocaleKeyStatus] values, comma-joined. Null: every status.
     * @param basename Base file name without extension, for example `Localizable`.
     * @throws NullDullException `400 INVALID_INPUT` with `detail` such as `LOCALE_EXPORT_TOO_LARGE` or
     *   `LOCALE_FORMAT_UNREPRESENTABLE`; the error's `body` holds `key`, `language` and `issues`.
     */
    public suspend fun export(
        scopeId: String,
        format: String = LocaleFormatId.JSON,
        languages: List<String>? = null,
        status: List<String>? = null,
        basename: String? = null,
    ): LocaleExport {
        if (scopeId.isEmpty()) throw NullDullException.invalidArgument("scopeId must be a non-empty string.")
        val prefix = root()
        val query = Query()
            .add("scopeId", scopeId)
            .add("format", format)
            .add("languages", joined(languages, "languages"))
            .add("status", joined(status, "status"))
            .add("basename", basename)
        return transport.json(prefix + "/locale/export", query) { LocaleExport(it.asObject("the export")) }
    }

    private fun joined(values: List<String>?, name: String): String? {
        if (values == null) return null
        if (values.any { it.isEmpty() || it.contains(',') }) {
            throw NullDullException.invalidArgument("$name must be a list of non-empty strings without commas.")
        }
        return values.takeIf { it.isNotEmpty() }?.joinToString(",")
    }
}
