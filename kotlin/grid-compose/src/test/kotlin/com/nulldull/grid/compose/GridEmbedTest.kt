package com.nulldull.grid.compose

import android.net.Uri
import android.view.View
import android.view.ViewGroup
import android.webkit.WebResourceRequest
import android.webkit.WebView
import androidx.activity.ComponentActivity
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
        val html = GridEmbedPlayer.html(player, "Say \"hi\" <script>alert(1)</script> & 'bye'")
        assertTrue("src=\"https://www.youtube-nocookie.com/embed/dQw4w9WgXcQ?autoplay=1\"" in html, html)
        assertTrue("title=\"Say &quot;hi&quot; &lt;script&gt;alert(1)&lt;/script&gt; &amp; &#39;bye&#39;\"" in html, html)
        assertTrue("sandbox=\"allow-scripts allow-same-origin allow-presentation allow-popups allow-top-navigation-by-user-activation\"" in html, html)
        assertTrue("referrerpolicy=\"strict-origin-when-cross-origin\"" in html, html)
        assertFalse("<script" in html, html)
        // Nothing may be fetched from the identity origin (it is not a server the app controls).
        assertTrue("<link rel=\"icon\" href=\"data:,\">" in html, html)
        assertEquals(1, Regex("<iframe").findAll(html).count())
    }
}

/** The tap gate: no WebView (so no provider request) until the poster is tapped. */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [35], qualifiers = "w390dp-h2000dp-xhdpi")
class GridEmbedTapGateTest {
    @get:Rule val compose = createAndroidComposeRule<ComponentActivity>()

    @Test
    fun loadsThePlayerOnlyAfterTheTap() {
        val opened = mutableListOf<String>()
        compose.setContent { GridRenderer(document = fixture("kitchen-sink"), width = 390.dp, onOpenUrl = { opened += it }) }
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
        // WRAP_CONTENT would collapse the frame page's percentage height to 0 (an invisible player).
        assertEquals(ViewGroup.LayoutParams.MATCH_PARENT, web.layoutParams.height)
        assertFalse(web.settings.allowFileAccess)
        assertFalse(web.settings.allowContentAccess)

        // Links in the player leave through the host; the player's own frames load normally.
        val client = shadowOf(web).webViewClient
        assertTrue(client.shouldOverrideUrlLoading(web, request("https://www.youtube.com/watch?v=dQw4w9WgXcQ", mainFrame = true)))
        assertFalse(client.shouldOverrideUrlLoading(web, request("https://www.youtube-nocookie.com/embed/x", mainFrame = false)))
        assertTrue(client.shouldOverrideUrlLoading(web, request("intent://evil", mainFrame = true)))
        assertEquals(listOf("https://www.youtube.com/watch?v=dQw4w9WgXcQ"), opened)
    }

    @Test
    fun renderEmbedStillReplacesTheBuiltInPlayer() {
        compose.setContent {
            GridRenderer(document = fixture("kitchen-sink"), width = 390.dp, renderEmbed = { androidx.compose.foundation.text.BasicText("consent") })
        }
        compose.onNodeWithText("consent").assertExists()
        compose.onNodeWithText("YouTube").assertDoesNotExist()
        assertEquals(0, webViews().size)
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
