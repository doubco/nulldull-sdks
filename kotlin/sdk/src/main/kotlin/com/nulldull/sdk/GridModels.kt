package com.nulldull.sdk

import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject

/** A version-pinned file referenced by a published Grid page. [url] is absolute (see [GridApi.assetUrl]). */
public open class GridAssetRef(json: JsonObject) : JsonModel(json) {
    public val id: String get() = json.string("id")
    public val version: Int get() = json.int("version")

    /** Absolute URL. For a public key on the API origin it carries `key=` so images and fonts can load. */
    public val url: String get() = json.string("url")
    public val filename: String get() = json.string("filename")
    public val mediaType: String get() = json.string("mediaType")
    public val byteSize: Long get() = json.long("byteSize")

    /** SHA-256, hex. */
    public val checksum: String get() = json.string("checksum")
}

/** A page's cover image. */
public class GridCover(json: JsonObject) : GridAssetRef(json) {
    /** Alternative text; `""` means decorative. */
    public val alt: String get() = json.string("alt")
}

/** A published page without its document, as listed by [GridApi.listPages]. */
public open class GridPageSummary(json: JsonObject) : JsonModel(json) {
    public val id: String get() = json.string("id")
    public val pool: String get() = json.string("pool")
    public val slug: String get() = json.string("slug")
    public val locale: String get() = json.string("locale")
    public val title: String get() = json.string("title")
    public val summary: String get() = json.string("summary")

    /** Publication version. */
    public val version: Int get() = json.int("version")

    /** Editor version that was published. */
    public val sourceVersion: Int get() = json.int("sourceVersion")

    /** Unix epoch milliseconds. */
    public val publishedAt: Long get() = json.long("publishedAt")

    /** The page's direct parent folder at publication time, if any. */
    public val folderId: String? get() = json.stringOrNull("folderId")
    public val cover: GridCover? get() = json.model("cover", ::GridCover)
}

/** A published page with its document and version-pinned asset manifest. */
public class GridPage(json: JsonObject) : GridPageSummary(json) {
    /**
     * The Grid document, untouched. Its schema belongs to the Grid renderer; the SDK treats it as opaque
     * JSON (`{layout, breakpoints, nodes, ...}`).
     */
    public val document: JsonElement get() = json["document"] ?: JsonNull
    public val assets: List<GridAssetRef> get() = json.models("assets", ::GridAssetRef)
}

/** The pool a page list came from. */
public class GridPool(json: JsonObject) : JsonModel(json) {
    public val key: String get() = json.string("key")
    public val name: String get() = json.string("name")
}

/** One page of a pool's published pages, newest first. */
public class GridPageList(json: JsonObject, items: List<GridPageSummary>) : Page<GridPageSummary>(json, items) {
    public val pool: GridPool get() = json.model("pool", ::GridPool) ?: GridPool(JsonObject(emptyMap()))
}
