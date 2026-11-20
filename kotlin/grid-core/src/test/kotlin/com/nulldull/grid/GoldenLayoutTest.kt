package com.nulldull.grid

import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.boolean
import kotlinx.serialization.json.double
import kotlinx.serialization.json.int
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import kotlin.math.abs
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue
import kotlin.test.fail

/** The Kotlin engine must reproduce the TypeScript geometry (golden/layout.json) for every document and width. */
class GoldenLayoutTest {
    private fun close(a: Double, b: Double) = abs(a - b) <= 1e-9 * maxOf(1.0, abs(a), abs(b))

    @Test
    fun everyFixtureMatchesTypeScriptGeometry() {
        val golden = Fixtures.json("golden/layout.json").jsonObject
        assertEquals("stubTextHeight", golden["measure"]!!.jsonPrimitive.content)
        val documents = golden["documents"]!!.jsonObject
        assertEquals(Fixtures.documents().keys, documents.keys.toSortedSet(), "every document has goldens")
        var compared = 0
        val problems = mutableListOf<String>()
        for ((name, widths) in documents) {
            val document = GridDocument.decode(Fixtures.text("documents/$name.json"))
            for ((width, value) in widths.jsonObject) {
                val expected = value.jsonObject
                val viewport = width.toDouble()
                val actual = GridLayoutEngine.layout(document, viewport, measureText = Fixtures::stubTextHeight)
                val where = "$name@$width"
                fun check(label: String, a: Double, e: Double) { if (!close(a, e)) problems += "$where $label: $a != $e" }
                if (actual.breakpointId != expected.str("breakpointId")) problems += "$where breakpoint ${actual.breakpointId}"
                if (actual.flow != expected["flow"]!!.jsonPrimitive.boolean) problems += "$where flow"
                if (actual.columns != expected["columns"]!!.jsonPrimitive.int) problems += "$where columns ${actual.columns}"
                if (actual.rows != expected["rows"]!!.jsonPrimitive.int) problems += "$where rows ${actual.rows}"
                if (actual.layout.gap != expected["gap"]!!.jsonPrimitive.int) problems += "$where gap"
                if ((actual.layout.padding ?: 0) != expected["padding"]!!.jsonPrimitive.int) problems += "$where padding"
                check("cellSize", actual.cellSize, expected.num("cellSize"))
                val canvas = expected["canvas"]!!.jsonObject
                // The renderer centers narrower canvases (`margin-inline: auto`).
                check("canvas.x", maxOf(0.0, (viewport - actual.canvasWidth) / 2), canvas.num("x"))
                check("canvas.width", actual.canvasWidth, canvas.num("width"))
                check("canvas.height", actual.canvasHeight, canvas.num("height"))
                val nodes = expected["nodes"]!!.jsonArray.map { it.jsonObject }
                assertEquals(nodes.map { it.str("id") }, actual.nodes.map { it.node.id }, "$where paint order")
                actual.nodes.zip(nodes).forEach { (placed, e) ->
                    val id = placed.node.id
                    if (placed.flowing != e["flowing"]!!.jsonPrimitive.boolean) problems += "$where $id flowing"
                    check("$id.x", placed.rect.x, e.num("x"))
                    check("$id.y", placed.rect.y, e.num("y"))
                    check("$id.width", placed.rect.width, e.num("width"))
                    check("$id.height", placed.rect.height, e.num("height"))
                }
                compared++
            }
        }
        if (problems.isNotEmpty()) fail(problems.take(40).joinToString("\n"))
        assertTrue(compared >= 200, "compared $compared document/width pairs")
    }

    @Test
    fun breakpointSelectionUsesWidestMatchingMinimum() {
        val document = GridDocument.decode(Fixtures.text("documents/kitchen-sink.json"))
        assertEquals(null, GridLayoutEngine.layoutAt(document, 599.0).breakpointId)
        assertEquals("tablet", GridLayoutEngine.layoutAt(document, 600.0).breakpointId)
        assertEquals("tablet", GridLayoutEngine.layoutAt(document, 1023.5).breakpointId)
        assertEquals("desktop", GridLayoutEngine.layoutAt(document, 4000.0).breakpointId)
    }

    @Test
    fun layoutOverrideForcesAGivenLayout() {
        val document = GridDocument.decode(Fixtures.text("documents/kitchen-sink.json"))
        val tablet = document.breakpoints.first { it.id == "tablet" }
        val forced = GridLayoutEngine.layout(document, 320.0, tablet.layout, "tablet", Fixtures::stubTextHeight)
        assertEquals("tablet", forced.breakpointId)
        assertEquals(16, forced.columns)
    }

    private fun JsonObject.str(key: String) = this[key]!!.jsonPrimitive.content
    private fun JsonObject.num(key: String) = this[key]!!.jsonPrimitive.double
}
