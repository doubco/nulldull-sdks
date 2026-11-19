package com.nulldull.sdk

import kotlinx.serialization.json.JsonObject
import java.io.File

/** Known Locale export format IDs. Unknown IDs are sent anyway; the server answers `LOCALE_FORMAT_UNKNOWN`. */
public object LocaleFormatId {
    public const val JSON: String = "json"
    public const val WORLD: String = "world"
    public const val WORLD_CLDR: String = "world-cldr"
    public const val XCSTRINGS: String = "xcstrings"
    public const val APPLE_STRINGS: String = "apple-strings"
    public const val ANDROID_XML: String = "android-xml"
}

/** Locale key review statuses, for the `status` export filter. */
public object LocaleKeyStatus {
    public const val DRAFT: String = "draft"
    public const val NEEDS_REVIEW: String = "needs_review"
    public const val APPROVED: String = "approved"
}

/** What an export format can represent. */
public class LocaleFormatCapabilities(json: JsonObject) : JsonModel(json) {
    /** `single` (one file set per language) or `multi` (one file for every language). */
    public val layout: String get() = json.string("layout")

    /** `cldr`, `one-other` or `none`. */
    public val plurals: String get() = json.string("plurals")

    /** `named` or `positional`. */
    public val variables: String get() = json.string("variables")
    public val status: Boolean get() = json.boolean("status")
    public val description: Boolean get() = json.boolean("description")
    public val variableTypes: Boolean get() = json.boolean("variableTypes")
}

/** A file role an export format produces. */
public class LocaleFormatFile(json: JsonObject) : JsonModel(json) {
    public val role: String get() = json.string("role")
    public val extension: String get() = json.string("extension")
    public val contentType: String get() = json.string("contentType")
    public val required: Boolean get() = json.boolean("required")
}

/** A Locale export format. */
public class LocaleFormat(json: JsonObject) : JsonModel(json) {
    public val id: String get() = json.string("id")
    public val label: String get() = json.string("label")
    public val capabilities: LocaleFormatCapabilities?
        get() = json.model("capabilities", ::LocaleFormatCapabilities)
    public val files: List<LocaleFormatFile> get() = json.models("files", ::LocaleFormatFile)
}

/** Every export format. */
public class LocaleFormatList(json: JsonObject) : JsonModel(json) {
    public val items: List<LocaleFormat> get() = json.models("items", ::LocaleFormat)
}

/** One exported text file. */
public class LocaleFile(json: JsonObject) : JsonModel(json) {
    /** Relative path, may contain `/` (for example `values-tr/strings.xml`). */
    public val path: String get() = json.string("path")
    public val contentType: String get() = json.string("contentType")

    /** UTF-8 text. */
    public val content: String get() = json.string("content")
}

/** Something the format could not represent, for example `LOCALE_FORMAT_DESCRIPTION_OMITTED`. */
public class LocaleNote(json: JsonObject) : JsonModel(json) {
    public val code: String get() = json.string("code")
    public val key: String get() = json.string("key")
    public val language: String? get() = json.stringOrNull("language")
}

/**
 * A Locale export: always JSON holding text files, never an archive. Single-language formats give one
 * file set per language (`en.json`, `tr.json`); `xcstrings` gives one file.
 */
public class LocaleExport(json: JsonObject) : JsonModel(json) {
    public val format: String get() = json.string("format")
    public val files: List<LocaleFile> get() = json.models("files", ::LocaleFile)
    public val notes: List<LocaleNote> get() = json.models("notes", ::LocaleNote)
    public val contentVersion: Long get() = json.long("contentVersion")

    /**
     * Writes every file under [directory] (created when missing) as UTF-8 and returns the written files.
     * Every path is checked before anything is written.
     *
     * @throws NullDullException `INVALID_RESPONSE` for an empty or absolute path or one with a `..` segment.
     */
    public fun writeTo(directory: File): List<File> {
        val targets = files.map { file ->
            val path = file.path
            val segments = path.split('/', '\\')
            val absolute = path.startsWith("/") || path.startsWith("\\") || Regex("^[A-Za-z]:").containsMatchIn(path)
            if (path.isEmpty() || absolute || segments.any { it == ".." } || File(path).isAbsolute) {
                throw NullDullException.client(NullDullException.INVALID_RESPONSE, "Refusing to write unsafe export path: $path")
            }
            File(directory, segments.filter { it.isNotEmpty() && it != "." }.joinToString(File.separator)) to file.content
        }
        return targets.map { (target, content) ->
            target.parentFile?.mkdirs()
            target.writeText(content, Charsets.UTF_8)
            target
        }
    }
}
