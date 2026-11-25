package com.nulldull.grid.client

import com.nulldull.grid.GridDocument
import com.nulldull.grid.PublishedGridPageTarget
import kotlinx.serialization.Serializable

/** A pinned, published asset. Use [url] exactly as returned (the client resolves it to an absolute URL). */
@Serializable
public data class PublicGridAsset(
    val id: String,
    val version: Int,
    val url: String,
    val filename: String,
    val mediaType: String,
    val byteSize: Long,
    val checksum: String,
)

/** Optional publication cover: an asset plus alternative text (empty means decorative). */
@Serializable
public data class PublicGridCover(
    val id: String,
    val version: Int,
    val url: String,
    val filename: String,
    val mediaType: String,
    val byteSize: Long,
    val checksum: String,
    val alt: String,
)

@Serializable
public data class PublicGridPageSummary(
    val id: String,
    val pool: String,
    val slug: String,
    val locale: String,
    val title: String,
    val summary: String,
    val version: Int,
    val sourceVersion: Int,
    /** Milliseconds since the Unix epoch. */
    val publishedAt: Long,
    /** Direct parent folder captured at publication; null for the pool root or older snapshots. */
    val folderId: String? = null,
    val cover: PublicGridCover? = null,
)

/** A published page: its summary, the validated document, and the pinned asset manifest. */
@Serializable
public data class PublicGridPage(
    val id: String,
    val pool: String,
    val slug: String,
    val locale: String,
    val title: String,
    val summary: String,
    val version: Int,
    val sourceVersion: Int,
    val publishedAt: Long,
    val folderId: String? = null,
    val cover: PublicGridCover? = null,
    val document: GridDocument,
    val assets: List<PublicGridAsset>,
    val pageTargets: Map<String, PublishedGridPageTarget> = emptyMap(),
) {
    /** Asset URL lookup for the renderer; unknown ids resolve to null. */
    public fun assetUrl(id: String): String? = assets.firstOrNull { it.id == id }?.url
}

@Serializable
public data class PublicGridPool(val key: String, val name: String)

@Serializable
public data class PublicGridPageList(
    val pool: PublicGridPool,
    val items: List<PublicGridPageSummary>,
    /** Opaque cursor for the next page, or null at the end. Pass it back as `after`. */
    val nextCursor: String? = null,
)
