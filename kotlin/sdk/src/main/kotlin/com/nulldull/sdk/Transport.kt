package com.nulldull.sdk

import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.ensureActive
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.flow
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import okhttp3.Call
import okhttp3.Callback
import okhttp3.Headers
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.Response
import java.io.ByteArrayOutputStream
import java.io.IOException
import java.io.InterruptedIOException
import java.net.SocketTimeoutException
import java.nio.ByteBuffer
import java.nio.charset.CodingErrorAction
import java.util.concurrent.TimeUnit
import kotlin.coroutines.resume
import kotlin.coroutines.resumeWithException

/** Waits the given number of milliseconds before a retry. Replaceable in tests. */
internal typealias Sleeper = suspend (millis: Long) -> Unit

/** `Retry-After` values above this many seconds are thrown instead of waited for (SPEC.md section 6). */
internal const val MAX_RETRY_AFTER_SECONDS = 30L
private val RETRYABLE = setOf(429, 502, 503, 504)

private fun backoff(retry: Int): Long = 500L shl (retry - 1)

internal class RawResponse(val status: Int, val headers: Headers, val bytes: ByteArray)

/** Ordered query parameters. Absent values are left out; lists repeat the key. */
internal class Query {
    private val parts = mutableListOf<Pair<String, String>>()

    fun add(name: String, value: String?): Query = apply { if (value != null) parts += name to value }

    fun add(name: String, value: Int?): Query = add(name, value?.toString())

    fun addAll(name: String, values: List<String>?): Query = apply { values?.forEach { parts += name to it } }

    override fun toString(): String =
        if (parts.isEmpty()) "" else parts.joinToString("&", prefix = "?") { (k, v) -> "${encodeUriComponent(k)}=${encodeUriComponent(v)}" }
}

private const val HEX = "0123456789ABCDEF"

/** JavaScript `encodeURIComponent`: everything but `A-Z a-z 0-9 - _ . ! ~ * ' ( )` is percent-encoded. */
internal fun encodeUriComponent(value: String): String {
    val out = StringBuilder(value.length)
    for (byte in value.toByteArray(Charsets.UTF_8)) {
        val c = byte.toInt() and 0xff
        val ch = c.toChar()
        if (ch in 'A'..'Z' || ch in 'a'..'z' || ch in '0'..'9' || ch in "-_.!~*'()") {
            out.append(ch)
        } else {
            out.append('%').append(HEX[c shr 4]).append(HEX[c and 0x0f])
        }
    }
    return out.toString()
}

/** JavaScript `decodeURIComponent`: strict, throws on malformed escapes or UTF-8. `+` stays `+`. */
internal fun decodeUriComponent(value: String): String {
    val bytes = ByteArrayOutputStream(value.length)
    var i = 0
    while (i < value.length) {
        val ch = value[i]
        if (ch == '%') {
            require(i + 2 < value.length) { "Malformed escape" }
            val hi = Character.digit(value[i + 1], 16)
            val lo = Character.digit(value[i + 2], 16)
            require(hi >= 0 && lo >= 0) { "Malformed escape" }
            bytes.write(hi * 16 + lo)
            i += 3
        } else {
            bytes.write(ch.toString().toByteArray(Charsets.UTF_8))
            i++
        }
    }
    val decoder = Charsets.UTF_8.newDecoder()
        .onMalformedInput(CodingErrorAction.REPORT)
        .onUnmappableCharacter(CodingErrorAction.REPORT)
    return decoder.decode(ByteBuffer.wrap(bytes.toByteArray())).toString()
}

/** Seconds from a `Retry-After` header (delta-seconds or an HTTP date), or null. */
internal fun parseRetryAfter(value: String?, nowMillis: Long = System.currentTimeMillis()): Long? {
    if (value == null) return null
    val trimmed = value.trim()
    if (trimmed.isNotEmpty() && trimmed.all { it in '0'..'9' }) return trimmed.toLongOrNull() ?: Long.MAX_VALUE
    val date = try {
        Headers.Builder().add("Retry-After", trimmed).build().getDate("Retry-After")
    } catch (_: IllegalArgumentException) {
        null
    } ?: return null
    val millis = date.time - nowMillis
    return if (millis <= 0) 0L else (millis + 999) / 1000
}

private val FILENAME_EXTENDED = Regex("""filename\*\s*=\s*([^']*)'[^']*'([^;]+)""", RegexOption.IGNORE_CASE)
private val FILENAME_QUOTED = Regex("""(?:^|;)\s*filename\s*=\s*"((?:[^"\\]|\\.)*)"""", RegexOption.IGNORE_CASE)
private val FILENAME_PLAIN = Regex("""(?:^|;)\s*filename\s*=\s*([^;]+)""", RegexOption.IGNORE_CASE)
private val BACKSLASH_ESCAPE = Regex("""\\(.)""")

/** File name from `Content-Disposition`: RFC 5987 `filename*` first, then `filename`. */
internal fun parseFilename(value: String?): String? {
    if (value.isNullOrEmpty()) return null
    FILENAME_EXTENDED.find(value)?.groupValues?.get(2)?.takeIf { it.isNotEmpty() }?.let { encoded ->
        try {
            return decodeUriComponent(encoded.trim())
        } catch (_: Exception) {
            // Fall through to the plain parameter.
        }
    }
    FILENAME_QUOTED.find(value)?.let { return BACKSLASH_ESCAPE.replace(it.groupValues[1], "$1") }
    return FILENAME_PLAIN.find(value)?.groupValues?.get(1)?.trim()?.takeIf { it.isNotEmpty() }
}

private fun Headers.nonEmpty(name: String): String? = get(name)?.takeIf { it.isNotEmpty() }

private fun requestIdOf(headers: Headers): String? = headers.nonEmpty("X-Request-Id") ?: headers.nonEmpty("CF-Ray")

private fun errorFrom(response: RawResponse): NullDullException {
    val body = try {
        Json.parseToJsonElement(response.bytes.toString(Charsets.UTF_8)) as? JsonObject
    } catch (_: Exception) {
        null // Not JSON: a router page, a gateway error or an empty body.
    }
    fun field(name: String) = (body?.get(name) as? JsonPrimitive)?.takeIf { it.isString }?.content
    return NullDullException(
        status = response.status,
        code = field("code") ?: NullDullException.REQUEST_FAILED,
        message = field("message"),
        detail = field("detail"),
        requestId = requestIdOf(response.headers),
        retryAfter = parseRetryAfter(response.headers["Retry-After"]),
        body = body,
    )
}

internal class Transport(
    private val apiKey: String,
    val baseUrl: String,
    private val timeoutMillis: Long,
    private val maxRetries: Int,
    private val http: OkHttpClient,
    private val userAgent: String,
    private val sleep: Sleeper,
) {
    /** GETs a JSON resource under `baseUrl` and decodes it; shape errors become `INVALID_RESPONSE`. */
    suspend fun <T> json(path: String, query: Query = Query(), decode: (JsonElement) -> T): T {
        val response = send(baseUrl + path + query, "application/json", authorize = true)
        val element = try {
            Json.parseToJsonElement(response.bytes.toString(Charsets.UTF_8))
        } catch (e: Exception) {
            throw invalidResponse(response, "NullDull returned a response that is not valid JSON.", e)
        }
        return try {
            decode(element)
        } catch (e: ShapeException) {
            throw invalidResponse(response, "NullDull returned JSON of an unexpected shape: ${e.message}", e)
        }
    }

    /** GETs bytes from a path under `baseUrl`. */
    suspend fun download(path: String, query: Query): Download = download(baseUrl + path + query, authorize = true)

    /** GETs bytes from an absolute URL, sending the key only when [authorize] is true. */
    suspend fun download(url: String, authorize: Boolean): Download {
        val response = send(url, "*/*", authorize)
        return Download(
            bytes = response.bytes,
            contentType = response.headers.nonEmpty("Content-Type"),
            filename = parseFilename(response.headers["Content-Disposition"]),
        )
    }

    private fun invalidResponse(response: RawResponse, message: String, cause: Throwable) = NullDullException(
        status = response.status,
        code = NullDullException.INVALID_RESPONSE,
        message = message,
        requestId = requestIdOf(response.headers),
        cause = cause,
    )

    private suspend fun send(url: String, accept: String, authorize: Boolean): RawResponse {
        val request = try {
            Request.Builder().url(url).get().header("Accept", accept).header("User-Agent", userAgent).apply {
                if (authorize) header("Authorization", "Bearer $apiKey")
            }.build()
        } catch (e: IllegalArgumentException) {
            throw NullDullException.client(NullDullException.INVALID_ARGUMENT, "The request URL is not valid.", e)
        }
        var retry = 0
        while (true) {
            val response = try {
                attempt(request)
            } catch (e: NullDullException) {
                if (e.code == NullDullException.NETWORK_ERROR && retry < maxRetries) {
                    retry++
                    sleep(backoff(retry))
                    continue
                }
                throw e
            }
            if (response.status in 200..299) return response
            val error = errorFrom(response)
            if (response.status !in RETRYABLE || retry >= maxRetries) throw error
            // A paused public request allowance lasts until the month renews: never retry it.
            if (error.isPublicRequestsPaused) throw error
            val retryAfter = error.retryAfter
            if (retryAfter != null && retryAfter > MAX_RETRY_AFTER_SECONDS) throw error
            retry++
            sleep(if (retryAfter != null) retryAfter * 1000 else backoff(retry))
        }
    }

    /** One attempt: execute the call and read the whole body within the per-attempt timeout. */
    private suspend fun attempt(request: Request): RawResponse {
        currentCoroutineContext().ensureActive()
        return suspendCancellableCoroutine { continuation ->
            val call = http.newCall(request)
            if (timeoutMillis > 0) call.timeout().timeout(timeoutMillis, TimeUnit.MILLISECONDS)
            continuation.invokeOnCancellation { call.cancel() }
            call.enqueue(object : Callback {
                override fun onFailure(call: Call, e: IOException) {
                    continuation.resumeWithException(failure(call, e))
                }

                override fun onResponse(call: Call, response: Response) {
                    val raw = try {
                        response.use { RawResponse(it.code, it.headers, it.body?.bytes() ?: ByteArray(0)) }
                    } catch (e: IOException) {
                        continuation.resumeWithException(failure(call, e))
                        return
                    }
                    continuation.resume(raw)
                }
            })
        }
    }

    private fun failure(call: Call, e: IOException): NullDullException = when {
        e is SocketTimeoutException || (e is InterruptedIOException && e.message == "timeout") ->
            NullDullException.client(NullDullException.TIMEOUT, "The request timed out after $timeoutMillis ms.", e)
        call.isCanceled() -> NullDullException.client(NullDullException.ABORTED, "The request was cancelled.", e)
        else -> NullDullException.client(NullDullException.NETWORK_ERROR, "The request could not reach NullDull.", e)
    }
}

/** Emits items across pages, following `nextCursor` until it is null (SPEC.md section 7). */
internal fun <T> paginate(start: String?, load: suspend (after: String?) -> Page<T>): Flow<T> = flow {
    var after = start
    while (true) {
        val page = load(after)
        for (item in page.items) emit(item)
        val next = page.nextCursor ?: return@flow
        if (next == after) {
            throw NullDullException.client(
                NullDullException.INVALID_RESPONSE,
                "Pagination did not advance: the API returned the same cursor again.",
            )
        }
        after = next
    }
}
