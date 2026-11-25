package com.nulldull.grid

import com.nulldull.grid.client.PublicGridPage
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNull

class GridHostNormalizerTest {
    @Test fun asciiAndLosslessUnicodeKeepTheirDestination() {
        for ((source, host) in mapOf(
            "Ex_ample.COM." to "ex_ample.com.", "-a..b-" to "-a..b-",
            "BÜCHER.example" to "xn--bcher-kva.example", "bu\u0308cher.example" to "xn--bcher-kva.example",
            "xn--fa-hia.BÜCHER" to "xn--fa-hia.xn--bcher-kva",
            "XN--FA-HIA.de" to "xn--fa-hia.de", "xn--vi8h.example" to "xn--vi8h.example",
            "xn--11b2ezcw70k.test" to "xn--11b2ezcw70k.test",
        )) assertEquals("https://$host/", GridUrl.safe("https://$source"), source)
    }

    @Test fun unsupportedOrMalformedHostsAreInertInBothLinkPaths() {
        for (host in listOf(
            "sub.faß.de", "ς.example", "a\u200Cb.test", "a\u200Db.test", "ＦＯＯ.example",
            "soft\u00adhyphen.test", "a\u3002b", "🍕.example", "🫠.example", "\u0301a.example",
            "xn--", "xn--bad-.test", "xn--a", "xn--0", "xn---a", "xn--9999999999999",
            "xn--0y0c", "xn--zn7c", "xn--kba", "[faß.de]", "xn--bad-.bücher", "bü_cher.test", "a\u115fb.test", "a\u1160b.test", "a\u17b4b.test", "a\u17b5b.test",
            "a١b.test", "123.مثال.test",
        )) {
            assertNull(GridUrl.safe("https://$host/"), host)
            assertNull(GridUrl.safePageHref("https://$host/"), host)
        }
    }

    @Test fun declinedExternalNodeAndMarkdownKeepTheDocumentReadable() {
        val json = Fixtures.text("page-links/legacy.json").replace("https://example.org/legacy", "https://faß.de/legacy")
        val page = GridJson.format.decodeFromString<PublicGridPage>(json)
        assertEquals("", (page.document.nodes[1] as GridBuiltinNode).link)
        val para = GridMarkdown.parse("[Guide](https://faß.de)").single() as MdBlock.Paragraph
        assertEquals(listOf(MdInline.Text("Guide")), para.inlines)
    }
}
