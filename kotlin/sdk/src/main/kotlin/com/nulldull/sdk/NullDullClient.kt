package com.nulldull.sdk

import kotlinx.coroutines.delay
import okhttp3.CookieJar
import okhttp3.HttpUrl
import okhttp3.HttpUrl.Companion.toHttpUrlOrNull
import okhttp3.OkHttpClient
import java.util.concurrent.TimeUnit
import kotlin.time.Duration
import kotlin.time.Duration.Companion.seconds

private val API_KEY = Regex("^nd_(pub|sec)_[a-f0-9]{64}$")
private val WORKSPACE_ID = Regex("^[a-zA-Z0-9_-]{1,128}$")

/** The default API origin. */
public const val DEFAULT_BASE_URL: String = "https://nulldull.com"

/** Which kind of workspace API key a client holds. */
public enum class KeyKind {
    /** `nd_pub_…`: Grid delivery only. Safe to ship in apps. */
    PUBLIC,

    /** `nd_sec_…`: Grid, Memory and Locale reads, limited by its scopes. Servers only. */
    PRIVATE,
}

/**
 * The NullDull client. It holds only configuration and is safe to share between coroutines; build one
 * per key and reuse it.
 *
 * ```kotlin
 * val nulldull = NullDullClient(apiKey = BuildConfig.NULLDULL_PUBLIC_KEY)
 * val page = nulldull.grid.getPage("my-blog", "hello-world")
 * ```
 *
 * Every call is a `suspend` function and throws [NullDullException] on failure. Requests for HTTP
 * `429`, `502`, `503` and `504` and network errors are retried up to [maxRetries] times (500 ms, then
 * 1000 ms, or the server's `Retry-After` when it is 30 seconds or less). Redirects are never followed.
 *
 * Coroutine cancellation propagates as [kotlinx.coroutines.CancellationException] and cancels the
 * in-flight HTTP call. A call cancelled outside the coroutine (for example with
 * `OkHttpClient.dispatcher.cancelAll()`) throws [NullDullException] with code `ABORTED`.
 *
 * @param apiKey A workspace API key: public `nd_pub_…` or private `nd_sec_…`.
 * @param workspaceId Needed for [memory] and [locale]; a key cannot look up its own workspace. Owners
 *   and admins find it in the app.
 * @param baseUrl API origin, default `https://nulldull.com`. HTTP(S) without credentials, query or
 *   fragment; one trailing `/` is removed.
 * @param timeout Per-attempt timeout covering connect, response and body. [Duration.ZERO] or
 *   [Duration.INFINITE] disables it. Default 30 seconds.
 * @param maxRetries Retries after the first attempt. `0` turns retries off. Default 2.
 * @param httpClient An [OkHttpClient] to share connection pools, add interceptors or proxies. The SDK
 *   derives its own client from it with redirects, cookies and caching turned off.
 * @param userAgent Optional suffix, sent as `nulldull-sdk-kotlin/0.4.0 <suffix>`.
 * @throws NullDullException `INVALID_ARGUMENT` for a malformed key, base URL, workspace ID, timeout
 *   or retry count.
 */
public class NullDullClient private constructor(config: Config) {

    public constructor(
        apiKey: String,
        workspaceId: String? = null,
        baseUrl: String = DEFAULT_BASE_URL,
        timeout: Duration = 30.seconds,
        maxRetries: Int = 2,
        httpClient: OkHttpClient? = null,
        userAgent: String? = null,
    ) : this(Config(apiKey, workspaceId, baseUrl, timeout, maxRetries, httpClient, userAgent, { delay(it) }))

    /** For tests: replaces the retry wait. */
    internal constructor(
        apiKey: String,
        workspaceId: String? = null,
        baseUrl: String = DEFAULT_BASE_URL,
        timeout: Duration = 30.seconds,
        maxRetries: Int = 2,
        httpClient: OkHttpClient? = null,
        userAgent: String? = null,
        sleep: Sleeper,
    ) : this(Config(apiKey, workspaceId, baseUrl, timeout, maxRetries, httpClient, userAgent, sleep))

    private class Config(
        val apiKey: String,
        val workspaceId: String?,
        val baseUrl: String,
        val timeout: Duration,
        val maxRetries: Int,
        val httpClient: OkHttpClient?,
        val userAgent: String?,
        val sleep: Sleeper,
    )

    /** The normalized base URL, without a trailing slash. */
    public val baseUrl: String

    /** The workspace ID used for [memory] and [locale], if any. */
    public val workspaceId: String?

    /** Whether the key is public or private. */
    public val keyKind: KeyKind

    /** Retries after the first attempt. */
    public val maxRetries: Int

    /** Published Grid content. */
    public val grid: GridApi

    /** Read-only Memory (private key and [workspaceId] required). */
    public val memory: MemoryApi

    /** Locale export (private key and [workspaceId] required). */
    public val locale: LocaleApi

    init {
        if (!API_KEY.matches(config.apiKey)) {
            throw NullDullException.invalidArgument("apiKey must be a NullDull workspace API key (nd_pub_… or nd_sec_…).")
        }
        if (config.workspaceId != null && !WORKSPACE_ID.matches(config.workspaceId)) {
            throw NullDullException.invalidArgument("workspaceId must be 1–128 letters, numbers, hyphens or underscores.")
        }
        if (config.timeout.isNegative()) {
            throw NullDullException.invalidArgument("timeout must be zero or positive.")
        }
        if (config.maxRetries < 0) {
            throw NullDullException.invalidArgument("maxRetries must be a whole number, zero or more.")
        }
        val (base, origin) = normalizeBaseUrl(config.baseUrl)
        baseUrl = base
        workspaceId = config.workspaceId
        maxRetries = config.maxRetries
        keyKind = if (config.apiKey.startsWith("nd_pub_")) KeyKind.PUBLIC else KeyKind.PRIVATE

        val http = (config.httpClient?.newBuilder() ?: OkHttpClient.Builder().readTimeout(0, TimeUnit.MILLISECONDS).writeTimeout(0, TimeUnit.MILLISECONDS))
            .followRedirects(false)
            .followSslRedirects(false)
            .cookieJar(CookieJar.NO_COOKIES)
            .cache(null)
            .build()
        val timeoutMillis = if (config.timeout.isInfinite()) 0L else config.timeout.inWholeMilliseconds
        val transport = Transport(
            apiKey = config.apiKey,
            baseUrl = base,
            timeoutMillis = timeoutMillis,
            maxRetries = config.maxRetries,
            http = http,
            userAgent = "nulldull-sdk-kotlin/$SDK_VERSION" + (config.userAgent?.takeIf { it.isNotEmpty() }?.let { " $it" } ?: ""),
            sleep = config.sleep,
        )
        val root = workspaceGuard(config.workspaceId, keyKind == KeyKind.PUBLIC)
        grid = GridApi(transport, origin, if (keyKind == KeyKind.PUBLIC) config.apiKey else null)
        memory = MemoryApi(transport, root)
        locale = LocaleApi(transport, root)
    }

    override fun toString(): String = "NullDullClient(baseUrl=$baseUrl, keyKind=$keyKind, workspaceId=$workspaceId)"

    private companion object {
        fun normalizeBaseUrl(value: String): Pair<String, HttpUrl> {
            val url = value.toHttpUrlOrNull()
                ?: throw NullDullException.invalidArgument("baseUrl must be an absolute HTTP(S) URL.")
            if (url.username.isNotEmpty() || url.password.isNotEmpty() || url.encodedQuery != null ||
                url.encodedFragment != null || value.contains('?') || value.contains('#')
            ) {
                throw NullDullException.invalidArgument("baseUrl must be an HTTP(S) URL without credentials, query or fragment.")
            }
            val origin = HttpUrl.Builder().scheme(url.scheme).host(url.host).port(url.port).build()
            return url.toString().removeSuffix("/") to origin
        }
    }
}
