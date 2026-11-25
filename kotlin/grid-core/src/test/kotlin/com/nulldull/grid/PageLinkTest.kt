package com.nulldull.grid

import com.nulldull.grid.client.PublicGridPage
import kotlinx.serialization.json.*
import kotlin.test.*

class PageLinkTest {
    private val page = GridJson.format.decodeFromString<PublicGridPage>(Fixtures.text("../grid/page-links.json"))
    private val route: GridPageLinkResolver = { target, anchor ->
        assertEquals("guide", target.entryId)
        "/${target.pool}/${target.locale}/${target.slug}" + (anchor?.let { "#$it" } ?: "")
    }

    @Test fun sharedPublishedCorpusRoundTrips() {
        val corpus = Fixtures.json("page-links/published.json").jsonArray
        assertEquals(17, corpus.size)
        for (raw in corpus) assertEquals(raw, GridJson.encode(GridValidator.validate(raw)))
        assertEquals(180000, GridJson.encodeToString(GridValidator.validate(corpus.last())).toByteArray().size)
    }

    @Test fun structuredDestinationsFollowTheCurrentDetail() {
        val link = assertNotNull((page.document.nodes[1] as GridBuiltinNode).pageLink)
        assertEquals("/manual/en/getting-started#chapter", link.resolve(page.pageTargets, route))
        val moved = page.pageTargets.getValue("~1").copy(pool = "handbook", slug = "new-name", locale = "tr")
        assertEquals("/handbook/tr/new-name#chapter", link.resolve(mapOf("~1" to moved), route))
        assertNull(link.resolve(emptyMap()) { _, _ -> fail("withdrawn target reached the host") })
        assertNull(link.resolve(page.pageTargets, null))
        assertNull(link.resolve(page.pageTargets) { _, _ -> null })
        val legacy = GridJson.format.decodeFromString<PublicGridPage>(Fixtures.text("page-links/legacy.json"))
        assertTrue(legacy.pageTargets.isEmpty())
        val old = legacy.document.nodes[1] as GridBuiltinNode
        assertNull(old.pageLink)
        assertEquals("https://example.org/legacy", old.link)
    }

    @Test fun formattedDestinationsResolveInParagraphsReferencesListsAndTables() {
        val node = page.document.nodes[0] as GridBuiltinNode
        assertEquals(1, node.pageLinkVersion)
        val blocks = GridMarkdown.parse(node.text, page.pageTargets, route)
        val first = (blocks[0] as MdBlock.Paragraph).inlines
        assertEquals("Inline and Missing.", GridMarkdown.plainText(first))
        assertEquals("/manual/en/getting-started#intro", first.filterIsInstance<MdInline.Link>().single().href)
        val list = (blocks[1] as MdBlock.ListBlock).items.single().blocks.single() as MdBlock.Paragraph
        assertEquals("/manual/en/getting-started#list", (list.inlines.single() as MdInline.Link).href)
        val cell = (blocks[2] as MdBlock.Table).rows.single().single()
        assertEquals("/manual/en/getting-started", (cell.single() as MdInline.Link).href)
        assertTrue((GridMarkdown.parse(node.text)[0] as MdBlock.Paragraph).inlines.none { it is MdInline.Link })
        val sample = "<grid-page:v1:~1> and `[code](grid-page:v1:~1)` and [web](https://example.org)"
        val runs = (GridMarkdown.parse(sample, page.pageTargets, route).single() as MdBlock.Paragraph).inlines
        assertEquals(listOf("/manual/en/getting-started", "https://example.org/"), runs.filterIsInstance<MdInline.Link>().map { it.href })
    }

    @Test fun fullCollapsedAndShortcutReferencesUseTheFirstDefinition() {
        val markdown = "[Full][ref], [ref][] and [ref].\n\n[ref]: <grid-page:v1:~1#intro>\n[ref]: grid-page:v1:~2"
        val paragraph = GridMarkdown.parse(markdown, page.pageTargets, route).single() as MdBlock.Paragraph
        val links = paragraph.inlines.filterIsInstance<MdInline.Link>()
        assertEquals(listOf("Full", "ref", "ref"), links.map { GridMarkdown.plainText(it.children) })
        assertTrue(links.all { it.href == "/manual/en/getting-started#intro" })
    }

    @Test fun aliasGrammarAndSafeOutput() {
        for (invalid in listOf("~0", "~01", "~65", "guide", "~1#", "~1#a#b", "~1#no/space", "~1#" + "a".repeat(129))) {
            assertNull(GridPageLink.parse("grid-page:v1:$invalid"))
        }
        val link = assertNotNull(GridPageLink.parse("grid-page:v1:~64#A-._~9"))
        val targets = mapOf("~64" to page.pageTargets.getValue("~1"))
        for (raw in Fixtures.json("page-links/routes.json").jsonArray) {
            val input = raw.jsonObject.getValue("input").jsonPrimitive.content
            assertEquals(raw.jsonObject["href"]?.jsonPrimitive?.contentOrNull, link.resolve(targets) { _, _ -> input }, input)
        }
    }
}
