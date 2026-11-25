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
    // Bridge the constructor, copy and their Kotlin default-argument entry points from Grid 0.2.0.
    internal constructor(
        id: String, pool: String, slug: String, locale: String, title: String, summary: String, version: Int,
        sourceVersion: Int, publishedAt: Long, folderId: String? = null, cover: PublicGridCover? = null,
        document: GridDocument, assets: List<PublicGridAsset>,
    ) : this(
        id, pool, slug, locale, title, summary, version, sourceVersion, publishedAt, folderId, cover, document,
        assets, pageTargets = emptyMap(),
    )

    // The serializer plugin also emitted a JVM constructor that takes the decoded-field mask.
    // Its 0.2.0 descriptor had 13 fields, with only folderId (bit 9) and cover (bit 10) optional.
    @Suppress("DEPRECATION_ERROR", "UNUSED_PARAMETER")
    @OptIn(kotlinx.serialization.InternalSerializationApi::class)
    @Deprecated("For the Grid 0.2.0 serializer", level = DeprecationLevel.HIDDEN)
    public constructor(
        seen: Int, id: String?, pool: String?, slug: String?, locale: String?, title: String?, summary: String?,
        version: Int, sourceVersion: Int, publishedAt: Long, folderId: String?, cover: PublicGridCover?,
        document: GridDocument?, assets: List<PublicGridAsset>?,
        marker: kotlinx.serialization.internal.SerializationConstructorMarker?,
    ) : this(
        id = requireNotNull(id.also {
            val required = 0b1100111111111
            if (seen and required != required) {
                kotlinx.serialization.internal.throwMissingFieldException(seen, required, serializer().descriptor)
            }
        }),
        pool = requireNotNull(pool), slug = requireNotNull(slug), locale = requireNotNull(locale),
        title = requireNotNull(title), summary = requireNotNull(summary), version = version, sourceVersion = sourceVersion,
        publishedAt = publishedAt, folderId = folderId.takeIf { seen and (1 shl 9) != 0 },
        cover = cover.takeIf { seen and (1 shl 10) != 0 }, document = requireNotNull(document),
        assets = requireNotNull(assets), pageTargets = emptyMap(),
    )

    @JvmName("copy")
    internal fun copyV020(
        id: String = this.id, pool: String = this.pool, slug: String = this.slug, locale: String = this.locale,
        title: String = this.title, summary: String = this.summary, version: Int = this.version,
        sourceVersion: Int = this.sourceVersion, publishedAt: Long = this.publishedAt,
        folderId: String? = this.folderId, cover: PublicGridCover? = this.cover,
        document: GridDocument = this.document, assets: List<PublicGridAsset> = this.assets,
    ): PublicGridPage = copy(
        id, pool, slug, locale, title, summary, version, sourceVersion, publishedAt, folderId, cover, document,
        assets, pageTargets = this.pageTargets,
    )

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
