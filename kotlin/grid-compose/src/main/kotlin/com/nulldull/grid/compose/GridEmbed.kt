package com.nulldull.grid.compose

import android.annotation.SuppressLint
import android.view.ViewGroup
import android.webkit.CookieManager
import android.webkit.WebResourceRequest
import android.webkit.WebSettings
import android.webkit.WebView
import android.webkit.WebViewClient
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.text.BasicText
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.key
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.role
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.viewinterop.AndroidView
import com.nulldull.grid.GridBuiltinNode
import com.nulldull.grid.GridUrl

/**
 * The built-in player for restricted embeds (YouTube on its privacy-enhanced host, and Vimeo),
 * as `gridEmbedUrl` resolves them.
 *
 * YouTube's embedded player requires the embedder to identify itself with an HTTP `Referer`
 * and blocks playback with "error 153" when it is missing. A WebView that loads the player URL
 * as its top-level page sends none, so the player is framed in a small local HTML page loaded
 * with `loadDataWithBaseURL`, whose base URL is the app's identity `https://<application id>/`
 * (the format YouTube documents for apps). Vimeo gets the same page and identity.
 */
internal object GridEmbedPlayer {
    internal enum class Provider(val label: String) { YouTube("YouTube"), Vimeo("Vimeo") }

    /** A resolved embed: the provider and the player URL the web renderer frames. */
    internal data class Player(val provider: Provider, val src: String) {
        /** The player URL with `autoplay=1`, used only when the viewer tapped the poster to load it. */
        val autoplaySrc: String get() = src + (if ('?' in src) "&" else "?") + "autoplay=1"

        fun src(autoplay: Boolean): String = if (autoplay) autoplaySrc else src
    }

    fun resolve(url: String?): Player? {
        val src = GridUrl.embed(url) ?: return null
        val provider = if (src.startsWith("https://player.vimeo.com/")) Provider.Vimeo else Provider.YouTube
        return Player(provider, src)
    }

    /**
     * The embedder identity sent as `Referer`: `https://` plus the Android application id
     * (`Context.packageName`, the id the app is published under), e.g. `https://com.example.app/`.
     */
    fun embedderOrigin(packageName: String): String = "https://${packageName.lowercase()}/"

    /**
     * The local page that frames the player. The iframe keeps the web renderer's sandbox, and adds
     * `allow-popups` and `allow-top-navigation-by-user-activation` so links the viewer taps in the
     * player (the title, the YouTube logo) reach the WebView client, which hands them to `openUrl`
     * instead of navigating. The referrer policy sends only the origin (the app identity).
     * [autoplay] adds `autoplay=1`, for a player the viewer loaded by tapping the poster.
     */
    fun html(player: Player, title: String, autoplay: Boolean): String = buildString {
        append("<!doctype html><html><head><meta charset=\"utf-8\">")
        // The frame page itself never runs script: if markup ever got into it, nothing would execute.
        // The policy does not reach the cross-origin player, which keeps its own.
        append("<meta http-equiv=\"Content-Security-Policy\" content=\"").append(CONTENT_SECURITY_POLICY).append("\">")
        append("<meta name=\"viewport\" content=\"width=device-width,initial-scale=1\">")
        append("<meta name=\"referrer\" content=\"strict-origin-when-cross-origin\">")
        // The base URL is an identity, not a server: an inline icon stops the WebView requesting /favicon.ico from it.
        append("<link rel=\"icon\" href=\"data:,\">")
        append("<style>html,body{margin:0;padding:0;width:100%;height:100%;overflow:hidden;background:#000}")
        append("iframe{display:block;border:0;width:100%;height:100%}</style></head><body>")
        append("<iframe src=\"").append(escape(player.src(autoplay))).append("\" title=\"").append(escape(title)).append("\"")
        append(" sandbox=\"allow-scripts allow-same-origin allow-presentation allow-popups allow-top-navigation-by-user-activation\"")
        append(" allow=\"autoplay; encrypted-media; fullscreen; picture-in-picture\"")
        append(" referrerpolicy=\"strict-origin-when-cross-origin\"></iframe>")
        append("</body></html>")
    }

    /** The frame page's policy: no script, plugins, `<base>` or form submissions of its own. */
    const val CONTENT_SECURITY_POLICY: String = "script-src 'none'; object-src 'none'; base-uri 'none'; form-action 'none'"

    private fun escape(value: String): String = buildString {
        for (c in value) when (c) {
            '&' -> append("&amp;")
            '<' -> append("&lt;")
            '>' -> append("&gt;")
            '"' -> append("&quot;")
            '\'' -> append("&#39;")
            else -> append(c)
        }
    }
}

/**
 * Restricted embed. With [GridEmbedLoading.Immediate] the player loads when the embed is composed
 * and waits for the viewer to press its play button. With [GridEmbedLoading.Tap] nothing is
 * requested from the provider until the viewer taps the local poster; the tap then loads the
 * player, which starts playing. Other URLs show a link or text. Hosts that need consent gating
 * replace this with `renderEmbed`.
 */
@Composable
internal fun GridEmbedContent(
    node: GridBuiltinNode,
    color: Color,
    messages: GridMessages,
    loading: GridEmbedLoading,
    openUrl: (String) -> Unit,
) {
    val player = remember(node.url) { GridEmbedPlayer.resolve(node.url) }
    if (player == null) {
        val href = GridUrl.safe(node.url)
        if (href != null) GridPlaceholder(node.name, color, link = { openUrl(href) }, linkText = href)
        else GridPlaceholder(node.url?.takeIf { it.isNotEmpty() } ?: node.name, color)
        return
    }
    var tapped by remember(player, loading) { mutableStateOf(false) }
    when {
        loading == GridEmbedLoading.Immediate -> key(player, false) { GridEmbedWebView(node, player, autoplay = false, openUrl) }
        tapped -> key(player, true) { GridEmbedWebView(node, player, autoplay = true, openUrl) }
        else -> GridEmbedPoster(node, player, color, messages) { tapped = true }
    }
}

/** Local poster with a play affordance; makes no network request. */
@Composable
private fun GridEmbedPoster(node: GridBuiltinNode, player: GridEmbedPlayer.Player, color: Color, messages: GridMessages, onPlay: () -> Unit) {
    val density = LocalDensity.current
    val title = TextStyle(color = color, fontSize = with(density) { gridTextUnit(13.0, false) }, fontWeight = FontWeight.SemiBold,
        textAlign = TextAlign.Center)
    val caption = title.copy(color = color.copy(alpha = color.alpha * 0.7f), fontSize = with(density) { gridTextUnit(12.0, false) },
        fontWeight = FontWeight.Medium)
    val label = messages.play + " " + node.name
    Column(
        Modifier.fillMaxSize()
            .background(color.copy(alpha = color.alpha * 0.06f))
            .clickable(role = Role.Button, onClickLabel = label, onClick = onPlay)
            .semantics { contentDescription = label; role = Role.Button }
            .padding(8.dp),
        verticalArrangement = Arrangement.spacedBy(8.dp, Alignment.CenterVertically),
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        Canvas(Modifier.size(44.dp)) {
            drawCircle(color, alpha = 0.85f)
            drawPath(Path().apply {
                moveTo(size.width * 0.40f, size.height * 0.30f); lineTo(size.width * 0.72f, size.height * 0.5f)
                lineTo(size.width * 0.40f, size.height * 0.70f); close()
            }, if (color.luminance() > 0.5f) Color.Black else Color.White)
        }
        BasicText(node.name, style = title, maxLines = 2, overflow = TextOverflow.Ellipsis)
        BasicText(player.provider.label, style = caption, maxLines = 1)
    }
}

private fun Color.luminance(): Float = 0.2126f * red + 0.7152f * green + 0.0722f * blue

/**
 * The player in a WebView: JavaScript on (the players need it), no JavaScript bridge, no file or
 * content access, no third-party cookies, no extra windows, and every top-level navigation (a
 * link in the player) handed to `openUrl` instead of replacing the player. [autoplay] is true only
 * when the viewer's tap on the poster created this WebView.
 */
@SuppressLint("SetJavaScriptEnabled")
@Composable
private fun GridEmbedWebView(node: GridBuiltinNode, player: GridEmbedPlayer.Player, autoplay: Boolean, openUrl: (String) -> Unit) {
    AndroidView(
        factory = { context ->
            WebView(context).apply {
                // AndroidView's default WRAP_CONTENT height makes WebView size the page to its content, so the
                // frame page's `height: 100%` resolves to 0 and the player is invisible. Fill the node instead.
                layoutParams = ViewGroup.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.MATCH_PARENT)
                contentDescription = node.name
                settings.javaScriptEnabled = true
                settings.allowFileAccess = false
                settings.allowContentAccess = false
                @Suppress("DEPRECATION")
                settings.allowFileAccessFromFileURLs = false
                @Suppress("DEPRECATION")
                settings.allowUniversalAccessFromFileURLs = false
                settings.setGeolocationEnabled(false)
                settings.domStorageEnabled = true
                settings.setSupportMultipleWindows(false)
                settings.javaScriptCanOpenWindowsAutomatically = false
                // After a tap on the poster playback may start at once; otherwise media waits for the
                // viewer's press on the player's own play button.
                settings.mediaPlaybackRequiresUserGesture = !autoplay
                settings.mixedContentMode = WebSettings.MIXED_CONTENT_NEVER_ALLOW
                CookieManager.getInstance().setAcceptThirdPartyCookies(this, false)
                webViewClient = object : WebViewClient() {
                    override fun shouldOverrideUrlLoading(view: WebView, request: WebResourceRequest): Boolean {
                        // The top-level page is the local frame page; navigating it means leaving the player.
                        if (!request.isForMainFrame) return false
                        GridUrl.safe(request.url.toString())?.let(openUrl)
                        return true
                    }
                }
                loadDataWithBaseURL(
                    GridEmbedPlayer.embedderOrigin(context.packageName),
                    GridEmbedPlayer.html(player, node.name, autoplay),
                    "text/html", "utf-8", null,
                )
            }
        },
        onRelease = { it.destroy() },
        modifier = Modifier.fillMaxSize(),
    )
}
