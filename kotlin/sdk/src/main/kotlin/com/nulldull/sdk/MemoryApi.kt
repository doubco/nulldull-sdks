package com.nulldull.sdk

import kotlinx.coroutines.flow.Flow
import kotlinx.serialization.json.JsonObject

/**
 * Read-only Memory (`memory:read`). Needs a private key and the client's `workspaceId`; otherwise
 * every call throws `PRIVATE_KEY_REQUIRED` or `WORKSPACE_REQUIRED` without sending a request.
 *
 * List methods return one [Page]; the matching `iterate…` methods return a cold [Flow] of items across
 * pages. The server fixes page sizes (50 items, or 20 for search and tags).
 */
public class MemoryApi internal constructor(
    private val transport: Transport,
    private val root: () -> String,
) {
    private suspend fun <T> get(path: String, query: Query, decode: (JsonObject) -> T): T {
        val prefix = root()
        return transport.json(prefix + path, query) { decode(it.asObject("the response")) }
    }

    /** Locations the key's member can see: the workspace root, customer products and projects. */
    public suspend fun listScopes(after: String? = null): Page<Scope> =
        get("/scopes", Query().add("after", after)) { Page.decode(it, ::Scope) }

    /** Every visible location. See [listScopes]. */
    public fun iterateScopes(after: String? = null): Flow<Scope> = paginate(after) { listScopes(it) }

    /**
     * Readable folders, optionally in one location or under one parent.
     *
     * @param parentId [FolderFilter.Root] for top-level folders, [FolderFilter.Id] for one parent, null for every folder.
     */
    public suspend fun listFolders(scopeId: String? = null, parentId: FolderFilter? = null, after: String? = null): FolderList =
        get("/folders", Query().add("scopeId", scopeId).add("parentId", parentId?.wireValue).add("after", after)) {
            FolderList(it, it.pageItems(::FolderSummary))
        }

    /** Every readable folder matching the filters. See [listFolders]. */
    public fun iterateFolders(scopeId: String? = null, parentId: FolderFilter? = null, after: String? = null): Flow<FolderSummary> =
        paginate(after) { listFolders(scopeId, parentId, it) }

    /** A folder with its ancestors and effective placement. A missing or unreadable folder gives `403 FORBIDDEN`. */
    public suspend fun getFolder(folderId: String): Folder =
        get("/folders/${id(folderId, "folderId")}", Query(), ::Folder)

    /**
     * Readable documents (Markdown files) without their content.
     *
     * @param folderId [FolderFilter.Root] for unfiled documents, [FolderFilter.Id] for one folder, null for all.
     * @param tags Every listed tag must be present (sent as repeated `tag`).
     * @param kind One of [FileKind].
     * @param lifecycle One of [FileLifecycle].
     */
    public suspend fun listDocuments(
        scopeId: String? = null,
        folderId: FolderFilter? = null,
        tags: List<String>? = null,
        kind: String? = null,
        lifecycle: String? = null,
        after: String? = null,
    ): Page<DocumentSummary> = get(
        "/documents",
        Query().add("scopeId", scopeId).add("folderId", folderId?.wireValue).addAll("tag", tags)
            .add("kind", kind).add("lifecycle", lifecycle).add("after", after),
    ) { Page.decode(it, ::DocumentSummary) }

    /** Every readable document matching the filters. See [listDocuments]. */
    public fun iterateDocuments(
        scopeId: String? = null,
        folderId: FolderFilter? = null,
        tags: List<String>? = null,
        kind: String? = null,
        lifecycle: String? = null,
        after: String? = null,
    ): Flow<DocumentSummary> = paginate(after) { listDocuments(scopeId, folderId, tags, kind, lifecycle, it) }

    /** A document with its saved Markdown content. A missing or unreadable document gives `403 FORBIDDEN`. */
    public suspend fun getDocument(documentId: String): Document =
        get("/documents/${id(documentId, "documentId")}", Query(), ::Document)

    /** Resolves a relative Markdown link inside a document to another readable document. */
    public suspend fun resolveLink(documentId: String, href: String): LinkResolution =
        get("/documents/${id(documentId, "documentId")}/resolve-link", Query().add("href", href), ::LinkResolution)

    /**
     * Literal, case-insensitive search over names, content and tags.
     *
     * @param q 2–160 characters. Shorter queries get `400 INVALID_INPUT` from the server.
     * @param scopeId Limits the search to this location and its descendants.
     */
    public suspend fun search(
        q: String,
        scopeId: String? = null,
        tags: List<String>? = null,
        kind: String? = null,
        lifecycle: String? = null,
        after: String? = null,
    ): Page<SearchResult> = get(
        "/search",
        Query().add("q", q).add("scopeId", scopeId).addAll("tag", tags)
            .add("kind", kind).add("lifecycle", lifecycle).add("after", after),
    ) { Page.decode(it, ::SearchResult) }

    /** Every search hit across pages. See [search]. */
    public fun iterateSearch(
        q: String,
        scopeId: String? = null,
        tags: List<String>? = null,
        kind: String? = null,
        lifecycle: String? = null,
        after: String? = null,
    ): Flow<SearchResult> = paginate(after) { search(q, scopeId, tags, kind, lifecycle, it) }

    /**
     * Tags on readable documents with their counts, most used first.
     *
     * @param q Substring of the tag, up to 48 characters.
     */
    public suspend fun listTags(scopeId: String? = null, q: String? = null, after: String? = null): Page<TagCount> =
        get("/tags", Query().add("scopeId", scopeId).add("q", q).add("after", after)) { Page.decode(it, ::TagCount) }

    /** Every tag across pages. See [listTags]. */
    public fun iterateTags(scopeId: String? = null, q: String? = null, after: String? = null): Flow<TagCount> =
        paginate(after) { listTags(scopeId, q, it) }

    /**
     * Readable Memory assets with metadata.
     *
     * @param folderId [FolderFilter.Root] for unfiled assets, [FolderFilter.Id] for one folder, null for all.
     * @param q Substring of name, description or tags, up to 160 characters.
     */
    public suspend fun listAssets(
        scopeId: String? = null,
        folderId: FolderFilter? = null,
        q: String? = null,
        tags: List<String>? = null,
        after: String? = null,
    ): Page<Asset> = get(
        "/assets",
        Query().add("scopeId", scopeId).add("folderId", folderId?.wireValue).add("q", q).addAll("tag", tags).add("after", after),
    ) { Page.decode(it, ::Asset) }

    /** Every readable asset matching the filters. See [listAssets]. */
    public fun iterateAssets(
        scopeId: String? = null,
        folderId: FolderFilter? = null,
        q: String? = null,
        tags: List<String>? = null,
        after: String? = null,
    ): Flow<Asset> = paginate(after) { listAssets(scopeId, folderId, q, tags, it) }

    /**
     * An asset's metadata and current stored object (file name, media type, SHA-256).
     *
     * @param revisionId A specific immutable version instead of the current one.
     */
    public suspend fun getAsset(assetId: String, revisionId: String? = null): Asset =
        get("/assets/${id(assetId, "assetId")}", Query().add("revisionId", revisionId), ::Asset)

    /** An asset's immutable versions, newest first. */
    public suspend fun listAssetVersions(assetId: String, after: String? = null): Page<AssetVersion> =
        get("/assets/${id(assetId, "assetId")}/versions", Query().add("after", after)) { Page.decode(it, ::AssetVersion) }

    /** Every version of an asset, newest first. See [listAssetVersions]. */
    public fun iterateAssetVersions(assetId: String, after: String? = null): Flow<AssetVersion> =
        paginate(after) { listAssetVersions(assetId, it) }

    /**
     * Downloads an asset's bytes, or a resized preview.
     *
     * Originals are served as `application/octet-stream`; the real media type is in [Asset.assetObject].
     *
     * @param revisionId A specific version instead of the current one.
     * @param preview Serve images inline (`preview=true`). Implied by [width].
     * @param width Resized WebP width in pixels for PNG, JPEG, WebP and AVIF; the server snaps it up to
     *   64, 128, 256, 512, 1024 or 2048. Other types and larger widths return the original.
     */
    public suspend fun downloadAsset(
        assetId: String,
        revisionId: String? = null,
        preview: Boolean = false,
        width: Int? = null,
    ): Download {
        if (width != null && width < 1) throw NullDullException.invalidArgument("width must be a positive whole number of pixels.")
        val path = root() + "/assets/${id(assetId, "assetId")}/download"
        val query = Query()
            .add("revisionId", revisionId)
            .add("preview", if (preview || width != null) "true" else null)
            .add("w", width)
        return transport.download(path, query)
    }

    private fun id(value: String, name: String): String {
        if (value.isEmpty()) throw NullDullException.invalidArgument("$name must be a non-empty string.")
        return encodeUriComponent(value)
    }
}

/** Builds the platform path prefix, or throws when the client cannot call the platform API. */
internal fun workspaceGuard(workspaceId: String?, publicKey: Boolean): () -> String = {
    if (publicKey) {
        throw NullDullException.client(
            NullDullException.PRIVATE_KEY_REQUIRED,
            "Memory and Locale need a private key (nd_sec_…) with the matching scope.",
        )
    }
    if (workspaceId == null) {
        throw NullDullException.client(
            NullDullException.WORKSPACE_REQUIRED,
            "Memory and Locale need workspaceId: a key cannot look up its own workspace.",
        )
    }
    "/api/platform/workspaces/${encodeUriComponent(workspaceId)}"
}
