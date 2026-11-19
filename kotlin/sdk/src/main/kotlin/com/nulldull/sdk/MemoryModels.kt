package com.nulldull.sdk

import kotlinx.serialization.json.JsonObject

/** File kinds used by Memory labels and filters. Unknown values from the API pass through as strings. */
public object FileKind {
    public const val RULES: String = "rules"
    public const val TASKS: String = "tasks"
    public const val PLAN: String = "plan"
    public const val REFERENCE: String = "reference"
    public const val PROCEDURE: String = "procedure"
    public const val NOTES: String = "notes"
    public const val UNKNOWN: String = "unknown"
}

/** File lifecycles used by Memory labels and filters. */
public object FileLifecycle {
    public const val MAINTAINED: String = "maintained"
    public const val ONE_TIME: String = "one-time"
    public const val UNKNOWN: String = "unknown"
}

/**
 * A folder filter for [MemoryApi.listFolders], [MemoryApi.listDocuments] and [MemoryApi.listAssets].
 * Pass `null` (the default) for no folder filter, [Root] for the location root (sent as `root`), or
 * [Id] for one folder.
 */
public sealed class FolderFilter {
    /** The location root: top-level folders, or unfiled documents and assets. */
    public object Root : FolderFilter() {
        override fun toString(): String = "FolderFilter.Root"
    }

    /** One folder by ID. */
    public data class Id(public val id: String) : FolderFilter()

    internal val wireValue: String
        get() = when (this) {
            Root -> "root"
            is Id -> id
        }

    public companion object {
        /** Shorthand for [Id]. */
        public fun id(id: String): FolderFilter = Id(id)
    }
}

/** A location: the workspace root, a customer product or a project. */
public class Scope(json: JsonObject) : JsonModel(json) {
    public val id: String get() = json.string("id")
    public val name: String get() = json.string("name")

    /** `workspace`, `customer-product` or `project`. */
    public val kind: String get() = json.string("kind")
    public val parentId: String? get() = json.stringOrNull("parentId")

    /** `symbol`, `emoji` or `image`. */
    public val iconKind: String? get() = json.stringOrNull("iconKind")
    public val iconValue: String? get() = json.stringOrNull("iconValue")
    public val iconVersion: Int? get() = json.intOrNull("iconVersion")
}

/** Where a folder or file is placed in a repository. */
public class Placement(json: JsonObject) : JsonModel(json) {
    public val repository: String? get() = json.stringOrNull("repository")
    public val path: String get() = json.string("path")

    /** `a/b`, or `""` at the root. */
    public val folderPath: String get() = json.string("folderPath")
}

/** A `{id, name}` reference to a folder. */
public class FolderRef(json: JsonObject) : JsonModel(json) {
    public val id: String get() = json.string("id")
    public val name: String get() = json.string("name")
}

/** Item counts directly inside a location or folder. */
public class FolderCounts(json: JsonObject) : JsonModel(json) {
    public val folders: Int get() = json.int("folders")
    public val documents: Int get() = json.int("documents")
    public val assets: Int get() = json.int("assets")
    public val secrets: Int get() = json.int("secrets")
}

/** A folder as listed by [MemoryApi.listFolders]. */
public class FolderSummary(json: JsonObject) : JsonModel(json) {
    public val workspaceId: String get() = json.string("workspaceId")
    public val id: String get() = json.string("id")
    public val scopeId: String get() = json.string("scopeId")
    public val parentId: String? get() = json.stringOrNull("parentId")
    public val name: String get() = json.string("name")
    public val createdBy: String get() = json.string("createdBy")
    public val preferredRepository: String? get() = json.stringOrNull("preferredRepository")
    public val preferredPath: String? get() = json.stringOrNull("preferredPath")
    public val metadataVersion: Int get() = json.int("metadataVersion")
    public val folderCount: Int get() = json.int("folderCount")
    public val documentCount: Int get() = json.int("documentCount")
    public val assetCount: Int get() = json.int("assetCount")
    public val secretCount: Int get() = json.int("secretCount")
    public val placement: Placement? get() = json.model("placement", ::Placement)
}

/** A page of folders. */
public class FolderList(json: JsonObject, items: List<FolderSummary>) : Page<FolderSummary>(json, items) {
    /** Counts at the requested level; only on the first page when both `scopeId` and `parentId` were given. */
    public val here: FolderCounts? get() = json.model("here", ::FolderCounts)
}

/** A folder with its ancestors and effective placement. */
public class Folder(json: JsonObject) : JsonModel(json) {
    public val workspaceId: String get() = json.string("workspaceId")
    public val id: String get() = json.string("id")
    public val scopeId: String get() = json.string("scopeId")
    public val parentId: String? get() = json.stringOrNull("parentId")
    public val name: String get() = json.string("name")
    public val createdBy: String get() = json.string("createdBy")
    public val preferredRepository: String? get() = json.stringOrNull("preferredRepository")
    public val preferredPath: String? get() = json.stringOrNull("preferredPath")
    public val metadataVersion: Int get() = json.int("metadataVersion")
    public val canManage: Boolean get() = json.boolean("canManage")
    public val canDelete: Boolean get() = json.boolean("canDelete")
    public val placement: Placement? get() = json.model("placement", ::Placement)
    public val ancestors: List<FolderRef> get() = json.models("ancestors", ::FolderRef)

    /** `empty`, `visible` or `hidden`. */
    public val contents: String get() = json.string("contents")
}

/** A document (Markdown file) without its content. */
public open class DocumentSummary(json: JsonObject) : JsonModel(json) {
    public val id: String get() = json.string("id")
    public val name: String get() = json.string("name")
    public val scopeId: String get() = json.string("scopeId")
    public val folderId: String? get() = json.stringOrNull("folderId")
    public val headRevisionId: String? get() = json.stringOrNull("headRevisionId")
    public val preferredRepository: String? get() = json.stringOrNull("preferredRepository")
    public val preferredPath: String? get() = json.stringOrNull("preferredPath")
    public val metadataVersion: Int get() = json.int("metadataVersion")

    /** `senior` or `junior`. */
    public val role: String get() = json.string("role")
    public val tags: List<String> get() = json.strings("tags")

    /** One of [FileKind], or null when unlabelled. */
    public val labelKind: String? get() = json.stringOrNull("labelKind")

    /** One of [FileLifecycle], or null when unlabelled. */
    public val labelLifecycle: String? get() = json.stringOrNull("labelLifecycle")

    /** `ai` or `manual`. */
    public val labelSource: String? get() = json.stringOrNull("labelSource")

    /** `ready`, `pending`, `failed` or `unclassified`. */
    public val labelStatus: String get() = json.string("labelStatus")
}

/** A document with its saved Markdown [content]. */
public class Document(json: JsonObject) : DocumentSummary(json) {
    public val headAuthorMemberId: String? get() = json.stringOrNull("headAuthorMemberId")

    /** Markdown, at most 128 KiB. */
    public val content: String? get() = json.stringOrNull("content")
    public val contentHash: String? get() = json.stringOrNull("contentHash")
    public val placement: Placement? get() = json.model("placement", ::Placement)

    /** Root first, up to three levels. */
    public val locationPath: List<Scope> get() = json.models("locationPath", ::Scope)
}

/** A Memory search hit. */
public class SearchResult(json: JsonObject) : JsonModel(json) {
    public val id: String get() = json.string("id")
    public val name: String get() = json.string("name")
    public val scopeId: String get() = json.string("scopeId")
    public val folderId: String? get() = json.stringOrNull("folderId")
    public val headRevisionId: String? get() = json.stringOrNull("headRevisionId")
    public val metadataVersion: Int get() = json.int("metadataVersion")
    public val role: String get() = json.string("role")
    public val tags: List<String> get() = json.strings("tags")
    public val labelKind: String? get() = json.stringOrNull("labelKind")
    public val labelLifecycle: String? get() = json.stringOrNull("labelLifecycle")
    public val labelSource: String? get() = json.stringOrNull("labelSource")
    public val labelStatus: String get() = json.string("labelStatus")

    /** Up to 240 characters around the match. */
    public val excerpt: String get() = json.string("excerpt")
    public val locationPath: List<Scope> get() = json.models("locationPath", ::Scope)
    public val folderPath: String get() = json.string("folderPath")
}

/** A tag and how many readable documents carry it. */
public class TagCount(json: JsonObject) : JsonModel(json) {
    public val tag: String get() = json.string("tag")
    public val count: Int get() = json.int("count")
}

/** The result of [MemoryApi.resolveLink]. */
public class LinkResolution(json: JsonObject) : JsonModel(json) {
    /** `found`, `unavailable` or `ambiguous`. */
    public val status: String get() = json.string("status")

    /** The target document when [status] is `found`. */
    public val id: String? get() = json.stringOrNull("id")

    /** The link's `#fragment` (without `#`) when [status] is `found`. */
    public val fragment: String? get() = json.stringOrNull("fragment")
}

/** The stored file behind an asset version. */
public class AssetObject(json: JsonObject) : JsonModel(json) {
    public val id: String get() = json.string("id")
    public val filename: String get() = json.string("filename")
    public val mediaType: String get() = json.string("mediaType")
    public val byteSize: Long get() = json.long("byteSize")

    /** SHA-256, hex. */
    public val checksum: String get() = json.string("checksum")
    public val authorMemberId: String get() = json.string("authorMemberId")

    /** Unix epoch milliseconds. */
    public val createdAt: Long get() = json.long("createdAt")
}

/** A Memory asset with metadata. */
public class Asset(json: JsonObject) : JsonModel(json) {
    public val id: String get() = json.string("id")
    public val name: String get() = json.string("name")
    public val scopeId: String get() = json.string("scopeId")

    /** Always `asset`. */
    public val kind: String get() = json.string("kind")
    public val folderId: String? get() = json.stringOrNull("folderId")
    public val folderPath: List<FolderRef> get() = json.models("folderPath", ::FolderRef)
    public val headRevisionId: String? get() = json.stringOrNull("headRevisionId")
    public val revisionId: String? get() = json.stringOrNull("revisionId")
    public val metadataVersion: Int get() = json.int("metadataVersion")
    public val role: String get() = json.string("role")
    public val description: String get() = json.string("description")
    public val tags: List<String> get() = json.strings("tags")

    /** `manual` or `ai`. */
    public val tagSource: String get() = json.string("tagSource")
    public val summary: String? get() = json.stringOrNull("summary")

    /** `ready`, `pending`, `failed`, `unavailable`, … */
    public val insightStatus: String get() = json.string("insightStatus")

    /** The JSON `object` field: the stored file, or null before the first upload. */
    public val assetObject: AssetObject? get() = json.model("object", ::AssetObject)
    public val locationPath: List<Scope> get() = json.models("locationPath", ::Scope)
}

/** An immutable asset version. */
public class AssetVersion(json: JsonObject) : JsonModel(json) {
    public val id: String get() = json.string("id")

    /** Unix epoch milliseconds. */
    public val createdAt: Long get() = json.long("createdAt")
    public val authorMemberId: String get() = json.string("authorMemberId")
}
