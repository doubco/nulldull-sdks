package com.nulldull.grid.compose

import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.text.BasicText
import androidx.compose.runtime.Composable
import androidx.compose.runtime.mutableStateOf
import androidx.compose.ui.Modifier
import androidx.compose.ui.test.junit4.ComposeContentTestRule
import androidx.compose.ui.semantics.SemanticsProperties
import androidx.compose.ui.test.SemanticsMatcher
import androidx.compose.ui.test.assertCountEquals
import androidx.compose.ui.test.getUnclippedBoundsInRoot
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onAllNodesWithText
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performFirstLinkClick
import androidx.compose.ui.text.LinkAnnotation
import com.nulldull.grid.GridJson
import com.nulldull.grid.client.PublicGridPage
import androidx.compose.ui.test.performClick
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.height
import androidx.compose.ui.unit.width
import com.nulldull.grid.GridBuiltinNode
import com.nulldull.grid.GridDocument
import com.nulldull.grid.GridLayoutEngine
import com.nulldull.grid.GridNodeKind
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import java.io.File
import kotlin.math.abs
import kotlin.test.assertEquals
import kotlin.test.assertTrue

internal fun fixture(name: String): GridDocument =
    GridDocument.decode(File(System.getProperty("grid.fixtures"), "documents/$name.json").readText())

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [35], qualifiers = "w390dp-h2000dp-xhdpi")
class GridRendererTest {
    @get:Rule val compose = createComposeRule()

    @Test
    fun rendersBuiltInFamiliesAndKeepsCustomDataInert() {
        val opened = mutableListOf<String>()
        compose.setContent {
            GridRenderer(
                document = fixture("kitchen-sink"),
                width = 390.dp,
                customNodes = mapOf("callout" to { node -> BasicText(node.property("text") ?: "") }),
                onOpenUrl = { opened += it },
            )
        }
        compose.onNodeWithText("Registered host component").assertExists()
        // Unregistered keys show their key as an inert placeholder; stored markup is never rendered.
        compose.onNodeWithText("pricing-table").assertExists()
        compose.onAllNodesWithText("onerror", substring = true).assertCountEquals(0)
        compose.onAllNodesWithText("NOT VISIBLE", substring = true).assertCountEquals(0)
        compose.onNodeWithText("No asset selected").assertExists()
        compose.onNodeWithText("Grid on every screen").assertExists()
        // Unsafe Markdown links are plain text; HTML is literal text.
        compose.onNodeWithText("unsafe <b>escaped</b>", substring = true).assertExists()
        // Node links open through the host, with the node name as their accessible label.
        compose.onNode(SemanticsMatcher.expectValue(SemanticsProperties.ContentDescription, listOf("Open the docs"))).performClick()
        assertEquals(listOf("https://example.com/docs"), opened)
    }

    @Test
    fun pageLinkSemanticsAndTapHandlersFollowRefreshedTargets() {
        val original = GridJson.format.decodeFromString<PublicGridPage>(
            File(System.getProperty("grid.fixtures"), "../grid/page-links.json").readText(),
        )
        val page = mutableStateOf(original)
        val opened = mutableListOf<String>()
        compose.setContent {
            PublishedGridPage(
                page.value, resolvePageLink = { target, anchor ->
                    "/${target.pool}/${target.locale}/${target.slug}" + (anchor?.let { "#$it" } ?: "")
                }, onOpenUrl = { opened += it },
            )
        }
        fun link(label: String, url: String) = SemanticsMatcher("link '$label' to '$url'") { node ->
            node.config.getOrElse(SemanticsProperties.Text) { emptyList() }.any { text ->
                text.getLinkAnnotations(0, text.length).any {
                    it.item is LinkAnnotation.Url && (it.item as LinkAnnotation.Url).url == url &&
                        text.text.substring(it.start, it.end) == label
                }
            }
        }
        val base = "/manual/en/getting-started"
        compose.onNode(link("Inline", "$base#intro")).performFirstLinkClick()
        compose.onNode(link("Read", "$base#list")).performFirstLinkClick()
        compose.onNode(link("Cell", base)).performFirstLinkClick()
        compose.onNode(link("Read the guide", "$base#chapter")).performFirstLinkClick()
        assertEquals(listOf("$base#intro", "$base#list", base, "$base#chapter"), opened)
        compose.runOnIdle {
            val moved = original.pageTargets.getValue("~1").copy(pool = "handbook", slug = "new", locale = "tr")
            page.value = original.copy(pageTargets = mapOf("~1" to moved))
        }
        val moved = "/handbook/tr/new#intro"
        compose.onNode(link("Inline", moved)).performFirstLinkClick()
        assertEquals(moved, opened.last())
        compose.runOnIdle { page.value = original.copy(pageTargets = emptyMap()) }
        compose.onAllNodes(link("Inline", moved)).assertCountEquals(0)
        compose.onAllNodes(link("Read the guide", "/handbook/tr/new#chapter")).assertCountEquals(0)
        compose.onNodeWithText("Inline and Missing.").assertExists()
        compose.onNodeWithText("grid-page:v1:~1 and grid-page:v1:~2").assertExists()
        compose.onAllNodes(link("grid-page:v1:~1", "/handbook/tr/new")).assertCountEquals(0)
        compose.onNodeWithText("Read the guide").assertExists()
    }

    @Test
    fun fixedCanvasMatchesTheLayoutEngine() {
        for ((name, width) in listOf("kitchen-sink" to 390, "kitchen-sink" to 834, "horizontal" to 390, "react-responsive-custom" to 1000, "breakpoints-padding" to 768, "showcase-fixed" to 390)) {
            val document = fixture(name)
            compose.show { GridRenderer(document = document, width = width.dp) }
            val geometry = GridLayoutEngine.layout(document, width.toDouble()) { _, _ -> error("fixed layouts do not measure text") }
            val canvasLeft = maxOf(0.0, (width - geometry.canvasWidth) / 2)
            for (placed in geometry.nodes) {
                val bounds = compose.onNodeWithTag("grid:${placed.node.id}", useUnmergedTree = true).getUnclippedBoundsInRoot()
                val where = "$name@$width ${placed.node.id}"
                assertClose(canvasLeft + placed.rect.x, bounds.left.value.toDouble(), where)
                assertClose(placed.rect.y, bounds.top.value.toDouble(), where)
                assertClose(placed.rect.width, bounds.width.value.toDouble(), where)
                assertClose(placed.rect.height, bounds.height.value.toDouble(), where)
            }
        }
    }

    @Test
    fun contentFlowStacksMeasuredTextWithFlowGap() {
        val document = fixture("markdown-rich")
        compose.setContent { GridRenderer(document = document, width = 390.dp) }
        val nodes = document.nodes.filter { !it.hidden }
        val bounds = nodes.map { compose.onNodeWithTag("grid:${it.id}", useUnmergedTree = true).getUnclippedBoundsInRoot() }
        val gap = document.layout.flowGap!!.toDouble()
        for (i in 1 until bounds.size) {
            assertClose(bounds[i - 1].bottom.value + gap, bounds[i].top.value.toDouble(), "flow gap before ${nodes[i].id}")
        }
        // Text heights are intrinsic: a multi-line block is taller than a heading.
        assertTrue(bounds[0].height.value > 10f)
        assertTrue(nodes.all { (it as? GridBuiltinNode)?.kind == GridNodeKind.Text })
    }

    private fun assertClose(expected: Double, actual: Double, message: String) {
        // Layout rounds to whole device pixels (density 2 => 0.5dp).
        assertTrue(abs(expected - actual) <= 0.51, "$message: expected $expected, got $actual")
    }

    /** setContent may run once per test; later content swaps through state. */
    private var composed = false
    private val holder = mutableStateOf<(@Composable () -> Unit)?>(null)
    private fun ComposeContentTestRule.show(content: @Composable () -> Unit) {
        holder.value = content
        if (!composed) { composed = true; setContent { Box(Modifier) { holder.value?.invoke() } } }
        waitForIdle()
    }
}
