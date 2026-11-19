package com.nulldull.sdk

import kotlinx.coroutines.flow.Flow
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import okhttp3.HttpUrl
import okhttp3.HttpUrl.Companion.toHttpUrlOrNull

private val KEY = Regex("^[a-z0-9]+(?:-[a-z0-9]+)*$")
private val LOCALE = Regex("^[a-z]{2,3}(?:-[a-z0-9]{2,8})*$")

/** The default Grid content language. */
public const val DEFAULT_LOCALE: String = "en"

/**
 * Published Grid content (`grid:published`). Works with public keys (safe in apps) and with private
 * keys that hold `grid:published`. No `workspaceId` is needed.
 *
 * Asset and cover URLs in results are already absolute; see [assetUrl].
 */
public class GridApi internal constructor(
    private val transport: Transport,
    private val origin: HttpUrl,
    private val publicKey: String?,
) {
    /**
     * One page of a pool's published pages, newest first.
     *
     * @param pool Pool key, for example `my-blog`.
     * @param locale Content language, lowercase (`en`, `pt-br`). Always sent; default `en`.
     * @param q Literal search over titles and summaries, up to 160 characters. Empty means no search.
     * @param folderId Only pages whose direct parent folder at publication time was this folder.
     * @param limit 1–50; the server defaults to 20.
     * @param after Cursor from a previous page's [Page.nextCursor].
     * @throws NullDullException `INVALID_ARGUMENT` for a malformed pool, locale or limit (no request is sent).
     */
    public suspend fun listPages(
        pool: String,
        locale: String = DEFAULT_LOCALE,
        q: String? = null,
        folderId: String? = null,
        limit: Int? = null,
        after: String? = null,
    ): GridPageList {
        val path = "/api/grid/v1/pools/${encodeUriComponent(key(pool, "pool"))}/pages"
        if (limit != null && limit !in 1..50) throw NullDullException.invalidArgument("limit must be a whole number from 1 to 50.")
        if (folderId != null && folderId.isEmpty()) throw NullDullException.invalidArgument("folderId must be a non-empty string.")
        val query = Query()
            .add("locale", locale(locale))
            .add("q", q?.ifEmpty { null })
            .add("folderId", folderId)
            .add("limit", limit)
            .add("after", after?.ifEmpty { null })
        return transport.json(path, query) { element ->
            val json = element.asObject("the page list")
            val items = json.pageItems { it }.map { summary(it) }
            val normalized = JsonObject(json + ("items" to JsonArray(items)))
            GridPageList(normalized, items.map(::GridPageSummary))
        }
    }

    /**
     * Every published page across all result pages, as a cold [Flow]. Requests are made lazily while
     * collecting; empty pages that still have a cursor are followed. Starts at [after] when given.
     */
    public fun iteratePages(
        pool: String,
        locale: String = DEFAULT_LOCALE,
        q: String? = null,
        folderId: String? = null,
        limit: Int? = null,
        after: String? = null,
    ): Flow<GridPageSummary> = paginate(after) { cursor -> listPages(pool, locale, q, folderId, limit, cursor) }

    /**
     * A published page with its document and version-pinned asset manifest.
     *
     * @throws NullDullException `404 NOT_FOUND` when the page is missing, unpublished or in another
     *   workspace's pool; `INVALID_ARGUMENT` for a malformed pool, slug or locale.
     */
    public suspend fun getPage(pool: String, slug: String, locale: String = DEFAULT_LOCALE): GridPage {
        val path = "/api/grid/v1/pools/${encodeUriComponent(key(pool, "pool"))}/pages/${encodeUriComponent(key(slug, "slug"))}"
        return transport.json(path, Query().add("locale", locale(locale))) { element ->
            val json = summary(element.asObject("the page"))
            val assets = (json["assets"] as? JsonArray ?: JsonArray(emptyList())).map { asset ->
                if (asset is JsonObject) withUrl(asset) else asset
            }
            GridPage(JsonObject(json + ("assets" to JsonArray(assets))))
        }
    }

    /**
     * Resolves an asset or cover URL against the API origin.
     *
     * For a **public** key and a URL on the API's own origin (same scheme, host and port) without a
     * `key` parameter, adds `key=<public key>` so image loaders, fonts and media players, which cannot
     * send headers, can authenticate. Never adds a private key, and never adds a key to another origin.
     *
     * @throws NullDullException `INVALID_ARGUMENT` when [url] cannot be resolved to an HTTP(S) URL.
     */
    public fun assetUrl(url: String): String {
        val resolved = origin.resolve(url) ?: throw NullDullException.invalidArgument("Provide a valid asset URL.")
        if (publicKey != null && sameOrigin(resolved) && resolved.queryParameter("key") == null) {
            return resolved.newBuilder().addQueryParameter("key", publicKey).build().toString()
        }
        return resolved.toString()
    }

    /**
     * Downloads an asset or cover by URL. The URL is resolved with [assetUrl]; `Authorization` is sent
     * only when it is on the API origin.
     */
    public suspend fun downloadAsset(url: String): Download {
        if (url.isEmpty()) throw NullDullException.invalidArgument("Provide an asset URL or an object with a url.")
        val resolved = assetUrl(url)
        return transport.download(resolved, authorize = sameOrigin(resolved.toHttpUrlOrNull()!!))
    }

    /** Downloads an asset or cover (anything with a `url`). See [downloadAsset]. */
    public suspend fun downloadAsset(asset: GridAssetRef): Download = downloadAsset(asset.url)

    private fun sameOrigin(url: HttpUrl) = url.scheme == origin.scheme && url.host == origin.host && url.port == origin.port

    private fun withUrl(ref: JsonObject): JsonObject {
        val url = (ref["url"] as? JsonPrimitive)?.takeIf { it.isString }?.content ?: return ref
        return JsonObject(ref + ("url" to JsonPrimitive(assetUrl(url))))
    }

    private fun summary(page: JsonObject): JsonObject {
        val cover = page["cover"] as? JsonObject ?: return page
        return JsonObject(page + ("cover" to withUrl(cover)))
    }

    private fun key(value: String, name: String): String {
        if (value.length > 96 || !KEY.matches(value)) {
            throw NullDullException.invalidArgument("$name must be 1–96 lowercase letters, numbers and single hyphens.")
        }
        return value
    }

    private fun locale(value: String): String {
        if (value.length > 35 || !LOCALE.matches(value)) {
            throw NullDullException.invalidArgument("locale must be a lowercase language tag, such as en or pt-br.")
        }
        return value
    }
}
