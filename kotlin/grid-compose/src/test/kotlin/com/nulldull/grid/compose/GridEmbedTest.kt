package com.nulldull.grid.compose

import android.net.Uri
import android.view.View
import android.view.ViewGroup
import android.webkit.WebResourceRequest
import android.webkit.WebView
import androidx.activity.ComponentActivity
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.ui.semantics.SemanticsProperties
import androidx.compose.ui.test.SemanticsMatcher
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.compose.ui.unit.dp
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.Shadows.shadowOf
import org.robolectric.annotation.Config
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue

/** URL, HTML and embedder identity of the built-in player (no Android needed). */
class GridEmbedPlayerTest {
    @Test
    fun resolvesProvidersLikeGridEmbedUrl() {
        val youtube = assertNotNull(GridEmbedPlayer.resolve("https://youtu.be/dQw4w9WgXcQ"))
        assertEquals(GridEmbedPlayer.Provider.YouTube, youtube.provider)
        assertEquals("https://www.youtube-nocookie.com/embed/dQw4w9WgXcQ", youtube.src)
        assertEquals("https://www.youtube-nocookie.com/embed/dQw4w9WgXcQ?autoplay=1", youtube.autoplaySrc)
        assertEquals(youtube.src, youtube.src(autoplay = false))
        assertEquals(youtube.autoplaySrc, youtube.src(autoplay = true))

        val vimeo = assertNotNull(GridEmbedPlayer.resolve("https://vimeo.com/76979871"))
        assertEquals(GridEmbedPlayer.Provider.Vimeo, vimeo.provider)
        assertEquals("https://player.vimeo.com/video/76979871?autoplay=1", vimeo.autoplaySrc)

        assertNull(GridEmbedPlayer.resolve("https://example.com/watch?v=dQw4w9WgXcQ"))
        assertNull(GridEmbedPlayer.resolve("javascript:alert(1)"))
        assertNull(GridEmbedPlayer.resolve(null))
    }

    @Test
    fun embedderIdentityIsTheApplicationId() {
        assertEquals("https://com.example.app/", GridEmbedPlayer.embedderOrigin("com.example.app"))
        assertEquals("https://com.example.my_app/", GridEmbedPlayer.embedderOrigin("com.Example.my_app"))
    }

    @Test
    fun framePageHoldsOnlyTheSandboxedPlayer() {
        val player = assertNotNull(GridEmbedPlayer.resolve("https://www.youtube.com/watch?v=dQw4w9WgXcQ"))
        val html = GridEmbedPlayer.html(player, "Say \"hi\" <script>alert(1)</script> & 'bye'", autoplay = true)
        assertTrue("src=\"https://www.youtube-nocookie.com/embed/dQw4w9WgXcQ?autoplay=1\"" in html, html)
        assertTrue("title=\"Say &quot;hi&quot; &lt;script&gt;alert(1)&lt;/script&gt; &amp; &#39;bye&#39;\"" in html, html)
        assertTrue("sandbox=\"allow-scripts allow-same-origin allow-presentation allow-popups allow-top-navigation-by-user-activation\"" in html, html)
        assertTrue("referrerpolicy=\"strict-origin-when-cross-origin\"" in html, html)
        assertFalse("<script" in html, html)
        // Nothing may be fetched from the identity origin (it is not a server the app controls).
        assertTrue("<link rel=\"icon\" href=\"data:,\">" in html, html)
        assertEquals(1, Regex("<iframe").findAll(html).count())
    }

    @Test
    fun framePageAutoplaysOnlyWhenAsked() {
        val player = assertNotNull(GridEmbedPlayer.resolve("https://vimeo.com/76979871"))
        val immediate = GridEmbedPlayer.html(player, "Clip", autoplay = false)
        assertTrue("src=\"https://player.vimeo.com/video/76979871\"" in immediate, immediate)
        assertFalse("autoplay=1" in immediate, immediate)
        assertTrue("src=\"https://player.vimeo.com/video/76979871?autoplay=1\"" in GridEmbedPlayer.html(player, "Clip", autoplay = true))
    }

    @Test
    fun embedLoadingHasTheSharedValues() {
        // The web and Swift renderers use the same two values ("immediate" and "tap").
        assertEquals(listOf("Immediate", "Tap"), GridEmbedLoading.entries.map { it.name })
    }
}

/**
 * Embed loading: by default the player loads without a tap and without autoplay; with
 * [GridEmbedLoading.Tap] no WebView (so no provider request) exists until the poster is tapped.
 */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [35], qualifiers = "w390dp-h2000dp-xhdpi")
class GridEmbedLoadingTest {
    @get:Rule val compose = createAndroidComposeRule<ComponentActivity>()

    @Test
    fun loadsThePlayerImmediatelyByDefault() {
        val opened = mutableListOf<String>()
        // Unchanged call site: no embedLoading argument.
        compose.setContent { GridRenderer(document = fixture("kitchen-sink"), width = 390.dp, onOpenUrl = { opened += it }) }
        compose.waitForIdle()
        compose.onNodeWithText("YouTube").assertDoesNotExist()
        compose.onNode(SemanticsMatcher.expectValue(SemanticsProperties.ContentDescription, listOf("Play Product video"))).assertDoesNotExist()
        val web = webViews().single()
        val loaded = assertNotNull(shadowOf(web).lastLoadDataWithBaseURL)
        assertEquals("https://${compose.activity.packageName.lowercase()}/", loaded.baseUrl)
        assertEquals("text/html", loaded.mimeType)
        assertTrue("src=\"https://www.youtube-nocookie.com/embed/dQw4w9WgXcQ\"" in loaded.data, loaded.data)
        assertFalse("autoplay=1" in loaded.data, loaded.data)
        assertNull(shadowOf(web).lastLoadedUrl, "the player is never the top-level page")
        assertTrue(web.settings.mediaPlaybackRequiresUserGesture, "the viewer starts playback with the player's button")
        assertHardened(web, opened)
    }

    @Test
    fun publishedPageLoadsImmediatelyByDefaultAndHonorsTap() {
        val page = com.nulldull.grid.client.PublicGridPage(
            id = "page", pool = "pool", slug = "page", locale = "en", title = "Page", summary = "", version = 1, sourceVersion = 1,
            publishedAt = 0, document = fixture("kitchen-sink"), assets = emptyList(),
        )
        var loading by mutableStateOf<GridEmbedLoading?>(null)
        compose.setContent {
            val mode = loading
            if (mode == null) PublishedGridPage(page = page) else PublishedGridPage(page = page, embedLoading = mode)
        }
        compose.waitForIdle()
        assertEquals(1, webViews().size)
        loading = GridEmbedLoading.Tap
        compose.waitForIdle()
        assertEquals(0, webViews().size)
        compose.onNodeWithText("YouTube").assertExists()
    }

    @Test
    fun tapLoadsThePlayerOnlyAfterTheTap() {
        val opened = mutableListOf<String>()
        compose.setContent {
            GridRenderer(document = fixture("kitchen-sink"), width = 390.dp, embedLoading = GridEmbedLoading.Tap, onOpenUrl = { opened += it })
        }
        compose.onNodeWithText("Product video").assertExists()
        compose.onNodeWithText("YouTube").assertExists()
        assertEquals(0, webViews().size, "no WebView before the tap")

        compose.onNode(SemanticsMatcher.expectValue(SemanticsProperties.ContentDescription, listOf("Play Product video"))).performClick()
        compose.waitForIdle()
        val web = webViews().single()
        val loaded = assertNotNull(shadowOf(web).lastLoadDataWithBaseURL)
        assertEquals("https://${compose.activity.packageName.lowercase()}/", loaded.baseUrl)
        assertEquals("text/html", loaded.mimeType)
        assertTrue("https://www.youtube-nocookie.com/embed/dQw4w9WgXcQ?autoplay=1" in loaded.data)
        assertNull(shadowOf(web).lastLoadedUrl, "the player is never the top-level page")
        assertFalse(web.settings.mediaPlaybackRequiresUserGesture, "the tap starts playback")
        assertHardened(web, opened)
    }

    @Test
    fun renderEmbedStillReplacesTheBuiltInPlayerInBothModes() {
        var loading by mutableStateOf(GridEmbedLoading.Immediate)
        compose.setContent {
            GridRenderer(
                document = fixture("kitchen-sink"), width = 390.dp, embedLoading = loading,
                renderEmbed = { androidx.compose.foundation.text.BasicText("consent") },
            )
        }
        for (mode in GridEmbedLoading.entries) {
            loading = mode
            compose.waitForIdle()
            compose.onNodeWithText("consent").assertExists()
            compose.onNodeWithText("YouTube").assertDoesNotExist()
            assertEquals(0, webViews().size, "\$mode")
        }
    }

    /** Layout, settings and navigation shared by both modes. */
    private fun assertHardened(web: WebView, opened: MutableList<String>) {
        // WRAP_CONTENT would collapse the frame page's percentage height to 0 (an invisible player).
        assertEquals(ViewGroup.LayoutParams.MATCH_PARENT, web.layoutParams.height)
        assertTrue(web.settings.javaScriptEnabled)
        assertFalse(web.settings.allowFileAccess)
        assertFalse(web.settings.allowContentAccess)
        assertFalse(web.settings.javaScriptCanOpenWindowsAutomatically)

        // Links in the player leave through the host; the player's own frames load normally.
        val client = shadowOf(web).webViewClient
        assertTrue(client.shouldOverrideUrlLoading(web, request("https://www.youtube.com/watch?v=dQw4w9WgXcQ", mainFrame = true)))
        assertFalse(client.shouldOverrideUrlLoading(web, request("https://www.youtube-nocookie.com/embed/x", mainFrame = false)))
        assertTrue(client.shouldOverrideUrlLoading(web, request("intent://evil", mainFrame = true)))
        assertEquals(listOf("https://www.youtube.com/watch?v=dQw4w9WgXcQ"), opened)
    }

    private fun webViews(): List<WebView> {
        val found = mutableListOf<WebView>()
        fun walk(view: View) {
            if (view is WebView) found += view
            if (view is ViewGroup) for (i in 0 until view.childCount) walk(view.getChildAt(i))
        }
        walk(compose.activity.window.decorView)
        return found
    }

    private fun request(url: String, mainFrame: Boolean) = object : WebResourceRequest {
        override fun getUrl(): Uri = Uri.parse(url)
        override fun isForMainFrame() = mainFrame
        override fun isRedirect() = false
        override fun hasGesture() = true
        override fun getMethod() = "GET"
        override fun getRequestHeaders(): Map<String, String> = emptyMap()
    }
}
