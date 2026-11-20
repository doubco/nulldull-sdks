package com.nulldull.grid.compose

import android.content.Context
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.produceState
import androidx.compose.runtime.remember
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontFamily
import coil3.ImageLoader
import coil3.Uri
import coil3.decode.DataSource
import coil3.decode.ImageSource
import coil3.fetch.FetchResult
import coil3.fetch.Fetcher
import coil3.fetch.SourceFetchResult
import coil3.request.Options
import coil3.svg.SvgDecoder
import com.nulldull.grid.GridLimits
import com.nulldull.grid.GridSvg
import com.nulldull.grid.GridUrl
import com.nulldull.grid.client.GridHttpEngine
import com.nulldull.grid.client.GridHttpRequest
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.sync.Semaphore
import kotlinx.coroutines.sync.withPermit
import kotlinx.coroutines.withContext
import okio.Buffer
import java.io.File
import java.io.IOException
import java.security.MessageDigest
import java.util.concurrent.ConcurrentHashMap
import android.graphics.Typeface as AndroidTypeface
import androidx.compose.ui.text.font.Typeface as ComposeTypeface

/** Raster and SVG assets are bounded to the Grid upload limit. */
private const val ASSET_MAX_BYTES = 10 * 1024 * 1024

/** An asset could not be previewed (unsafe SVG, wrong scheme, HTTP error, too large). */
public class GridAssetException(message: String) : IOException(message)

internal suspend fun fetchAsset(engine: GridHttpEngine, url: String, maxBytes: Int): Pair<ByteArray, String?> {
    if (GridUrl.safe(url) == null) throw GridAssetException("Only http(s) assets are loaded.")
    val response = engine.get(GridHttpRequest(url, emptyMap(), maxBytes))
    if (response.status !in 200..299) throw GridAssetException("Asset request failed (${response.status}).")
    return response.body to response.headers["content-type"]?.substringBefore(';')?.trim()?.lowercase()
}

private fun looksLikeSvg(bytes: ByteArray, mimeType: String?): Boolean {
    if (mimeType == "image/svg+xml") return true
    val head = bytes.copyOfRange(0, minOf(bytes.size, 512)).decodeToString().trimStart('\uFEFF', ' ', '\n', '\r', '\t')
    return head.startsWith("<svg") || (head.startsWith("<?xml") && head.contains("<svg"))
}

/**
 * Coil fetcher bound to the Grid transport: http(s) only, no redirects, no cookies, bounded
 * bytes. SVG is decoded only after [GridSvg.isSafe] accepts it, like the web preview rules.
 */
internal class GridAssetFetcher(private val url: String, private val options: Options, private val engine: GridHttpEngine) : Fetcher {
    override suspend fun fetch(): FetchResult {
        val (bytes, mimeType) = fetchAsset(engine, url, ASSET_MAX_BYTES)
        val svg = looksLikeSvg(bytes, mimeType)
        if (svg && (bytes.size > GridLimits.SVG_MAX_BYTES || !GridSvg.isSafe(bytes.decodeToString())))
            throw GridAssetException("SVG is not a static drawing; it stays download-only.")
        return SourceFetchResult(
            source = ImageSource(source = Buffer().write(bytes), fileSystem = options.fileSystem),
            mimeType = if (svg) "image/svg+xml" else mimeType,
            dataSource = DataSource.NETWORK,
        )
    }

    class Factory(private val engine: GridHttpEngine) : Fetcher.Factory<Uri> {
        override fun create(data: Uri, options: Options, imageLoader: ImageLoader): Fetcher? =
            if (data.scheme == "http" || data.scheme == "https") GridAssetFetcher(data.toString(), options, engine) else null
    }
}

private val loaders = ConcurrentHashMap<GridHttpEngine, ImageLoader>()

/** One image loader per transport, so memory caches are shared across renderers. */
internal fun gridImageLoader(context: Context, engine: GridHttpEngine): ImageLoader =
    loaders.getOrPut(engine) {
        ImageLoader.Builder(context.applicationContext)
            .components {
                add(GridAssetFetcher.Factory(engine))
                add(SvgDecoder.Factory())
            }
            .build()
    }

@Composable
internal fun rememberGridImageLoader(): ImageLoader {
    val context = LocalContext.current
    val engine = LocalGridOptions.current.engine
    return remember(context, engine) { gridImageLoader(context, engine) }
}

/**
 * Uploaded fonts: one shared load per URL, at most two concurrent downloads, 2 MiB each,
 * a bounded cache, and failed loads evicted so a later composition can retry. Android
 * renders TrueType/OpenType; WOFF and WOFF2 are rejected and the fallback family is used.
 */
internal object GridFontCache {
    private val permits = Semaphore(2)
    private val entries = object : LinkedHashMap<String, FontFamily>(16, 0.75f, true) {
        override fun removeEldestEntry(eldest: MutableMap.MutableEntry<String, FontFamily>?) = size > 32
    }

    fun cached(url: String): FontFamily? = synchronized(entries) { entries[url] }

    suspend fun load(context: Context, engine: GridHttpEngine, url: String): FontFamily? {
        cached(url)?.let { return it }
        return try {
            permits.withPermit {
                cached(url) ?: run {
                    val (bytes, _) = fetchAsset(engine, url, GridLimits.FONT_MAX_BYTES)
                    if (!isSupportedFont(bytes)) return@run null
                    val family = withContext(Dispatchers.IO) {
                        val dir = File(context.cacheDir, "nulldull-grid-fonts").apply { mkdirs() }
                        val file = File(dir, sha256(url) + ".font")
                        file.writeBytes(bytes)
                        FontFamily(ComposeTypeface(AndroidTypeface.createFromFile(file)))
                    }
                    synchronized(entries) { entries[url] = family }
                    family
                }
            }
        } catch (e: kotlinx.coroutines.CancellationException) {
            throw e
        } catch (e: IOException) {
            null
        } catch (e: RuntimeException) {
            null
        }
    }

    /** TrueType (0x00010000, `true`), OpenType (`OTTO`) or collections (`ttcf`). */
    private fun isSupportedFont(bytes: ByteArray): Boolean {
        if (bytes.size < 12) return false
        val tag = bytes.copyOfRange(0, 4)
        return tag.contentEquals(byteArrayOf(0, 1, 0, 0)) || listOf("true", "OTTO", "ttcf").any { tag.contentEquals(it.toByteArray()) }
    }

    private fun sha256(value: String): String =
        MessageDigest.getInstance("SHA-256").digest(value.toByteArray()).joinToString("") { "%02x".format(it) }
}

/** Resolves an uploaded font; null while loading or when it cannot be used. */
@Composable
internal fun rememberGridFont(url: String?): FontFamily? {
    val context = LocalContext.current
    val engine = LocalGridOptions.current.engine
    val family by produceState(initialValue = url?.let(GridFontCache::cached), url, engine) {
        value = url?.let { GridFontCache.load(context, engine, it) }
    }
    return family
}
