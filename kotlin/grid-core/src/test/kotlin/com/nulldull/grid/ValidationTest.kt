package com.nulldull.grid

import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertIs
import kotlin.test.assertNull
import kotlin.test.assertTrue
import kotlin.test.fail

class ValidationTest {
    @Test
    fun everyValidationCaseMatchesTypeScript() {
        val cases = Fixtures.json("validation/cases.json").jsonArray
        assertTrue(cases.size >= 100)
        val problems = cases.mapNotNull { case ->
            val o = case.jsonObject
            val name = o["name"]!!.jsonPrimitive.content
            val input = o["inputJSON"]?.let { GridJson.parse(it.jsonPrimitive.content) } ?: o["input"]!!
            val valid = o["valid"]!!.jsonPrimitive.content == "true"
            try {
                val document = GridValidator.validate(input)
                when {
                    !valid -> "$name: accepted, expected '${o["error"]!!.jsonPrimitive.content}'"
                    o["output"] != null && o["output"] != GridJson.encode(document) -> "$name: normalized output differs"
                    else -> null
                }
            } catch (e: GridValidationException) {
                val expected = o["error"]?.jsonPrimitive?.content
                if (valid) "$name: rejected with '${e.message}'" else if (e.message == expected) null else "$name: '${e.message}' != '$expected'"
            }
        }
        if (problems.isNotEmpty()) fail(problems.joinToString("\n"))
    }

    @Test
    fun fixtureDocumentsRoundTripUnchanged() {
        for ((name, file) in Fixtures.documents()) {
            val json = GridJson.parse(file.readText()) as JsonObject
            assertEquals(json, GridJson.encode(GridDocument.decode(file.readText())), name)
        }
    }

    @Test
    fun keepsTypedOptionalFieldsAndDefaults() {
        val document = GridDocument.decode(Fixtures.text("documents/kitchen-sink.json"))
        assertEquals(listOf("base", "tablet", "desktop"), document.layoutOrder())
        val custom = document.nodes.first { it.id == "custom-unknown" }
        assertIs<GridCustomNode>(custom)
        assertEquals("pricing-table", custom.nodeKey)
        assertEquals(0.5, custom.opacity)
        assertEquals("<img src=x onerror=alert(1)>", custom.property("html"))
        val rule = document.nodes.first { it.id == "spacer" } as GridBuiltinNode
        assertEquals(GridSeparatorStyle.Empty, rule.separatorStyle)
        val body = document.nodes.first { it.id == "body" } as GridBuiltinNode
        assertEquals(0.5, body.borderOpacity)
        assertNull(body.rotation)
    }

    @Test
    fun integersMayBeWrittenWithAFraction() {
        val json = Fixtures.text("documents/starter-story.json").replace("\"cellSize\": 32", "\"cellSize\": 32.0")
        assertEquals(32, GridDocument.decode(json).layout.cellSize)
        assertFailsWith<GridValidationException> { GridDocument.decode(json.replace("32.0", "1e400")) }
    }

    @Test
    fun urlsAndEmbedsMatchTypeScript() {
        for (case in Fixtures.json("validation/urls.json").jsonArray) {
            val o = case.jsonObject
            val input = o["input"]!!.jsonPrimitive.content
            assertEquals(o["safe"]!!.jsonPrimitive.contentOrNull, GridUrl.safe(input), "safe($input)")
            assertEquals(o["embed"]!!.jsonPrimitive.contentOrNull, GridUrl.embed(input), "embed($input)")
        }
    }

    @Test
    fun assetReferencesMustBeHttpOrSameHostPaths() {
        assertEquals("/api/grid/v1/a.png", GridUrl.safeAsset("/api/grid/v1/a.png"))
        assertNull(GridUrl.safeAsset("//evil.example/a.png"))
        assertNull(GridUrl.safeAsset("/a\\b"))
        assertNull(GridUrl.safeAsset("file:///etc/passwd"))
        assertNull(GridUrl.safeAsset("content://com.example/a"))
    }
}
