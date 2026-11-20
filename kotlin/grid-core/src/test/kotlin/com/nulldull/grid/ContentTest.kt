package com.nulldull.grid

import kotlinx.serialization.json.boolean
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertIs
import kotlin.test.assertTrue

class ContentTest {
    @Test
    fun parsesTheGfmSubsetIntoInertBlocks() {
        val blocks = GridMarkdown.parse(
            "# Heading\n\nA **bold** [reference][one] and ~~old~~ `code`.\nNext line\n\n- First\n  - Nested\n- [x] Done\n\n" +
                "3. Three\n4. Four\n\n> Quoted text\n\n---\n\n```js\nconst x = 1;\n```\n\n| A | B |\n| :- | -: |\n| One | Two |\n\n" +
                "[unsafe](javascript:alert(1)) <script>alert(1)</script> ![alt text](https://example.com/i.png) https://example.org\n\n" +
                "[one]: https://example.com",
        )
        val kinds = blocks.map { it::class.simpleName }
        assertEquals(listOf("Heading", "Paragraph", "ListBlock", "ListBlock", "Quote", "Rule", "Code", "Table", "Paragraph"), kinds)
        val heading = blocks[0] as MdBlock.Heading
        assertEquals(1, heading.level)
        assertEquals(listOf(MdInline.Text("Heading")), heading.inlines)
        val paragraph = (blocks[1] as MdBlock.Paragraph).inlines
        assertTrue(paragraph.any { it is MdInline.Strong })
        assertTrue(paragraph.any { it is MdInline.Strike })
        assertTrue(paragraph.any { it is MdInline.Code && it.text == "code" })
        assertEquals("https://example.com/", paragraph.filterIsInstance<MdInline.Link>().single().href)
        assertTrue(GridMarkdown.plainText(paragraph).contains("code.\nNext line"))
        val list = blocks[2] as MdBlock.ListBlock
        assertFalse(list.ordered)
        assertEquals(true, list.items[1].checked)
        assertIs<MdBlock.ListBlock>(list.items[0].blocks.last())
        assertEquals(3, (blocks[3] as MdBlock.ListBlock).start)
        assertEquals(MdBlock.Code("const x = 1;", "js"), blocks[6])
        val table = blocks[7] as MdBlock.Table
        assertEquals(listOf(GridAlign.Left, GridAlign.Right), table.alignments)
        assertEquals("Two", GridMarkdown.plainText(table.rows.single()[1]))
        val last = (blocks[8] as MdBlock.Paragraph).inlines
        val text = GridMarkdown.plainText(last)
        assertTrue(text.startsWith("unsafe <script>alert(1)</script> alt text"), text)
        assertEquals(listOf("https://example.org/"), last.filterIsInstance<MdInline.Link>().map { it.href })
    }

    @Test
    fun svgValidationMatchesTypeScript() {
        for (case in Fixtures.json("validation/svg.json").jsonArray) {
            val o = case.jsonObject
            val source = o["source"]!!.jsonPrimitive.content
            assertEquals(o["safe"]!!.jsonPrimitive.boolean, GridSvg.isSafe(source), source)
        }
    }
}
