package com.nulldull.grid.client

import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.awaitCancellation
import kotlinx.coroutines.launch
import kotlinx.coroutines.runInterruptible
import kotlinx.coroutines.withContext
import java.io.ByteArrayOutputStream
import java.io.IOException
import java.io.InputStream
import java.net.HttpURLConnection
import java.net.URI

/** A GET request issued by the Grid client. Headers never contain cookies. */
public data class GridHttpRequest(val url: String, val headers: Map<String, String>, val maxBytes: Int)

public class GridHttpResponse(public val status: Int, public val headers: Map<String, String>, public val body: ByteArray)

/**
 * Pluggable transport. Implementations must not follow redirects, must not send or
 * store cookies, must not cache, and must respect coroutine cancellation.
 */
public fun interface GridHttpEngine {
    public suspend fun get(request: GridHttpRequest): GridHttpResponse
}

/** Thrown by an engine when a response exceeds [GridHttpRequest.maxBytes]. */
public class GridResponseTooLargeException(limit: Int) : IOException("Response exceeds $limit bytes.")

/**
 * Default engine on `java.net.HttpURLConnection` (available on the JVM and Android, no
 * third-party dependency). Redirects are returned as responses so the client can
 * reject them; caches are disabled; cancellation disconnects the socket.
 */
public class UrlConnectionGridHttpEngine(
    private val connectTimeoutMillis: Int = 15_000,
    private val readTimeoutMillis: Int = 30_000,
) : GridHttpEngine {
    override suspend fun get(request: GridHttpRequest): GridHttpResponse = withContext(Dispatchers.IO) {
        val connection = URI(request.url).toURL().openConnection() as HttpURLConnection
        // Blocking socket reads ignore thread interrupts; a watcher disconnects on cancellation.
        val watcher = launch {
            try { awaitCancellation() } finally { connection.disconnect() }
        }
        try {
            runInterruptible {
                connection.instanceFollowRedirects = false
                connection.useCaches = false
                connection.connectTimeout = connectTimeoutMillis
                connection.readTimeout = readTimeoutMillis
                connection.requestMethod = "GET"
                request.headers.forEach { (k, v) -> connection.setRequestProperty(k, v) }
                val status = connection.responseCode
                val stream = if (status >= 400) connection.errorStream else connection.inputStream
                val body = stream?.use { readBounded(it, request.maxBytes) } ?: ByteArray(0)
                val headers = connection.headerFields.orEmpty()
                    .filterKeys { it != null }
                    .mapKeys { it.key.lowercase() }
                    .mapValues { it.value.joinToString(", ") }
                GridHttpResponse(status, headers, body)
            }
        } finally {
            watcher.cancel()
            connection.disconnect()
        }
    }

    private fun readBounded(input: InputStream, limit: Int): ByteArray {
        val out = ByteArrayOutputStream()
        val buffer = ByteArray(16 * 1024)
        while (true) {
            if (Thread.interrupted()) throw InterruptedException()
            val read = input.read(buffer)
            if (read < 0) break
            if (out.size() + read > limit) throw GridResponseTooLargeException(limit)
            out.write(buffer, 0, read)
        }
        return out.toByteArray()
    }
}
