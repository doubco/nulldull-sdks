package com.nulldull.grid.client

import com.nulldull.grid.GridJson
import com.nulldull.grid.GridUrl
import com.nulldull.grid.GridValidationException
import com.nulldull.grid.GridValidator
import kotlinx.coroutines.CancellationException
import kotlinx.serialization.SerializationException
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.decodeFromJsonElement
import java.io.IOException
import java.net.URI
import java.net.URLEncoder

/** Base class of every failure the client reports. Coroutine cancellation is never wrapped. */
public sealed class GridClientException(message: String, cause: Throwable? = null) : Exception(message, cause)

/** The API answered with a non-success status. [code] is the API error code, or `REQUEST_FAILED`. */
public class GridPublicException(public val status: Int, public val code: String) :
    GridClientException("Grid request failed ($status: $code).")

/** The request could not complete (connection, timeout, redirect, or oversized response). */
public class GridNetworkException(message: String, cause: Throwable? = null) : GridClientException(message, cause)

/** The API answered with JSON that is not a valid Grid response or document. */
public class GridResponseException(message: String, cause: Throwable? = null) : GridClientException(message, cause)

/**
 * Coroutine client for the public Grid delivery API (`/api/grid/v1`).
 *
 * Pass a workspace API key with the Published Grid content scope as [apiKey]. Only public
 * `nd_pub_` keys belong in app bundles: a private `nd_sec_` key is refused unless
 * [allowPrivateKey] is set for server-side use, and it is never placed in a URL. Omit the
 * key only where the API still allows anonymous reads.
 */
public class GridClient(
    baseUrl: String,
    private val apiKey: String? = null,
    private val engine: GridHttpEngine = UrlConnectionGridHttpEngine(),
    allowPrivateKey: Boolean = false,
    /** Upper bound for one JSON response body. */
    private val maxResponseBytes: Int = 4 * 1024 * 1024,
) {
    private val root: String
    private val origin: URI
    private val publicKey: String?

    init {
        if (apiKey != null) {
            require(API_KEY.matches(apiKey)) { "Use a NullDull workspace API key (nd_pub_… or nd_sec_…)." }
            require(apiKey.startsWith("nd_pub_") || allowPrivateKey) {
                "Never ship a private NullDull API key in an app. Use a public nd_pub_ key, or pass allowPrivateKey = true on a server."
            }
        }
        publicKey = apiKey?.takeIf { it.startsWith("nd_pub_") }
        val href = GridUrl.normalizeHttp(baseUrl)
        val uri = href?.let(URI::create)
        require(uri != null && uri.rawQuery == null && uri.rawFragment == null && !baseUrl.contains('?') && !baseUrl.contains('#')) {
            "Use an HTTP(S) Grid API base URL."
        }
        root = href.removeSuffix("/")
        origin = URI(uri.scheme, null, uri.host, uri.port, null, null, null)
    }

    /** Reads one published page. The document is validated with [GridValidator]; asset and cover URLs are made absolute. */
    public suspend fun getPage(pool: String, slug: String, locale: String = "en"): PublicGridPage {
        val json = read("/pools/${publicKey(pool)}/pages/${publicKey(slug)}?locale=${publicLocale(locale)}")
        val page = decode<PublicGridPage>(json)
        return page.copy(
            cover = page.cover?.let { it.copy(url = assetUrl(it.url)) },
            assets = page.assets.map { it.copy(url = assetUrl(it.url)) },
        )
    }

    /** Lists published pages of a pool. Pass [PublicGridPageList.nextCursor] as [after] to continue. */
    public suspend fun listPages(
        pool: String,
        locale: String = "en",
        after: String? = null,
        q: String? = null,
        folderId: String? = null,
        limit: Int? = null,
    ): PublicGridPageList {
        val query = mutableListOf("locale" to publicLocale(locale))
        if (!after.isNullOrEmpty()) query += "after" to after
        if (!q.isNullOrEmpty()) query += "q" to q
        if (folderId != null) query += "folderId" to GridValidator.gridId(JsonPrimitive(folderId))
        if (limit != null) {
            require(limit in 1..50) { "Use a limit between 1 and 50." }
            query += "limit" to limit.toString()
        }
        val search = query.joinToString("&") { (k, v) -> "${form(k)}=${form(v)}" }
        val list = decode<PublicGridPageList>(read("/pools/${publicKey(pool)}/pages?$search"))
        return list.copy(items = list.items.map { item -> item.copy(cover = item.cover?.let { it.copy(url = assetUrl(it.url)) }) })
    }

    /**
     * Resolves an asset URL from the API against the API origin. Images, fonts and media
     * load without headers, so a public key is appended as `key` for same-origin assets.
     * Private keys and foreign origins never receive a key.
     */
    public fun assetUrl(value: String): String {
        val resolved = origin.resolve(URI.create(value.replace(" ", "%20")))
        val href = resolved.toString()
        val sameOrigin = resolved.scheme.equals(origin.scheme, true) && resolved.host.equals(origin.host, true) &&
            effectivePort(resolved) == effectivePort(origin)
        if (publicKey == null || !sameOrigin) return href
        val query = resolved.rawQuery
        if (query != null && query.split('&').any { it.substringBefore('=') == "key" }) return href
        val fragment = resolved.rawFragment?.let { "#$it" } ?: ""
        val base = href.substringBefore('#')
        return base + (if (query == null) "?" else "&") + "key=" + form(publicKey) + fragment
    }

    private fun effectivePort(uri: URI) = if (uri.port >= 0) uri.port else if (uri.scheme.equals("https", true)) 443 else 80

    private suspend fun read(path: String): JsonObject {
        val headers = buildMap {
            put("Accept", "application/json")
            apiKey?.let { put("Authorization", "Bearer $it") }
        }
        val response = try {
            engine.get(GridHttpRequest(root + path, headers, maxResponseBytes))
        } catch (e: CancellationException) {
            throw e
        } catch (e: GridClientException) {
            throw e
        } catch (e: IOException) {
            throw GridNetworkException("Grid request failed: ${e.message ?: e::class.simpleName}", e)
        }
        if (response.status in 300..399) throw GridNetworkException("Grid request was redirected; redirects are not followed.")
        if (response.status !in 200..299) {
            val code = runCatching {
                ((GridJson.parse(response.body.decodeToString()) as? JsonObject)?.get("code") as? JsonPrimitive)
                    ?.takeIf { it.isString }?.content
            }.getOrNull()
            throw GridPublicException(response.status, code ?: "REQUEST_FAILED")
        }
        return try {
            GridJson.parse(response.body.decodeToString()) as? JsonObject
                ?: throw GridResponseException("Expected a JSON object from the Grid API.")
        } catch (e: SerializationException) {
            throw GridResponseException("The Grid API returned invalid JSON.", e)
        }
    }

    private inline fun <reified T> decode(json: JsonObject): T = try {
        GridJson.format.decodeFromJsonElement<T>(json)
    } catch (e: GridValidationException) {
        throw GridResponseException("The published document is invalid: ${e.message}", e)
    } catch (e: SerializationException) {
        throw GridResponseException("Unexpected Grid API response: ${e.message}", e)
    } catch (e: IllegalArgumentException) {
        throw GridResponseException("Unexpected Grid API response: ${e.message}", e)
    }

    public companion object {
        private val API_KEY = Regex("^nd_(pub|sec)_[a-f0-9]{64}$")
        private val PUBLIC_KEY = Regex("^[a-z0-9]+(?:-[a-z0-9]+)*$")
        private val LOCALE = Regex("^[a-z]{2,3}(?:-[a-z0-9]{2,8})*$")

        /** `gridPublicKey`: pool keys and slugs are 1–96 lowercase letters, digits and single hyphens. */
        public fun publicKey(value: String): String {
            require(PUBLIC_KEY.matches(value) && value.length <= 96) { "Use 1–96 lowercase letters, numbers and single hyphens." }
            return value
        }

        /** `gridPublicLocale`: a lowercase language tag such as `en` or `pt-br`. */
        public fun publicLocale(value: String): String {
            require(LOCALE.matches(value) && value.length <= 35) { "Use a lowercase language tag, such as en or pt-br." }
            return value
        }

        /** application/x-www-form-urlencoded, as URLSearchParams serializes. */
        private fun form(value: String): String = URLEncoder.encode(value, "UTF-8")
    }
}
