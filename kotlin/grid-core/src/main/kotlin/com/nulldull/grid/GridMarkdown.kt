package com.nulldull.grid

import org.intellij.markdown.IElementType
import org.intellij.markdown.MarkdownElementTypes as E
import org.intellij.markdown.MarkdownTokenTypes as T
import org.intellij.markdown.ast.ASTNode
import org.intellij.markdown.ast.getTextInNode
import org.intellij.markdown.flavours.gfm.GFMElementTypes
import org.intellij.markdown.flavours.gfm.GFMFlavourDescriptor
import org.intellij.markdown.flavours.gfm.GFMTokenTypes
import org.intellij.markdown.html.entities.EntityConverter
import org.intellij.markdown.parser.LinkMap
import org.intellij.markdown.parser.MarkdownParser

/** Block-level Markdown supported by Grid text nodes (CommonMark + GitHub Flavored Markdown). */
public sealed interface MdBlock {
    public data class Paragraph(val inlines: List<MdInline>) : MdBlock
    public data class Heading(val level: Int, val inlines: List<MdInline>) : MdBlock
    public data class ListBlock(val ordered: Boolean, val start: Int, val items: List<ListItem>) : MdBlock
    public data class ListItem(val blocks: List<MdBlock>, val checked: Boolean?)
    public data class Quote(val blocks: List<MdBlock>) : MdBlock
    public data class Code(val text: String, val language: String?) : MdBlock
    public data class Table(val header: List<List<MdInline>>, val rows: List<List<List<MdInline>>>, val alignments: List<GridAlign?>) : MdBlock
    public data object Rule : MdBlock
    /** Raw HTML is never interpreted; it is shown as literal text, as react-markdown escapes it. */
    public data class Html(val text: String) : MdBlock
}

/** Inline Markdown. Links carry only a safe http(s) href; unsafe links become plain text. */
public sealed interface MdInline {
    public data class Text(val text: String) : MdInline
    public data class Strong(val children: List<MdInline>) : MdInline
    public data class Emphasis(val children: List<MdInline>) : MdInline
    public data class Strike(val children: List<MdInline>) : MdInline
    public data class Code(val text: String) : MdInline
    public data class Link(val href: String, val children: List<MdInline>) : MdInline
    public data object LineBreak : MdInline
}

/** Parses Grid text into the inert block model. Images render as their alt text and are never fetched. */
public object GridMarkdown {
    private val flavour = GFMFlavourDescriptor()

    public fun parse(markdown: String): List<MdBlock> {
        val tree = MarkdownParser(flavour).buildMarkdownTreeFromString(markdown)
        val links = LinkMap.buildLinkMap(tree, markdown)
        return Converter(markdown, links).blocks(tree.children)
    }

    /** Plain text of inlines, for accessibility labels and measuring. */
    public fun plainText(inlines: List<MdInline>): String = buildString {
        inlines.forEach { inline ->
            when (inline) {
                is MdInline.Text -> append(inline.text)
                is MdInline.Code -> append(inline.text)
                is MdInline.LineBreak -> append('\n')
                is MdInline.Strong -> append(plainText(inline.children))
                is MdInline.Emphasis -> append(plainText(inline.children))
                is MdInline.Strike -> append(plainText(inline.children))
                is MdInline.Link -> append(plainText(inline.children))
            }
        }
    }

    private class Converter(val source: String, val links: LinkMap) {
        fun text(node: ASTNode) = node.getTextInNode(source).toString()
        fun unescape(value: String) = EntityConverter.replaceEntities(value, processEntities = true, processEscapes = true)

        fun blocks(nodes: List<ASTNode>): List<MdBlock> = nodes.mapNotNull(::block)

        fun block(node: ASTNode): MdBlock? = when (node.type) {
            E.PARAGRAPH -> MdBlock.Paragraph(inlines(node.children))
            E.ATX_1, E.ATX_2, E.ATX_3, E.ATX_4, E.ATX_5, E.ATX_6 -> MdBlock.Heading(
                level = node.type.name.last().digitToInt(),
                inlines = node.children.firstOrNull { it.type == T.ATX_CONTENT }?.let { inlines(it.children).trimText() } ?: emptyList(),
            )
            E.SETEXT_1, E.SETEXT_2 -> MdBlock.Heading(
                level = if (node.type == E.SETEXT_1) 1 else 2,
                inlines = node.children.firstOrNull { it.type == T.SETEXT_CONTENT }?.let { inlines(it.children).trimText() } ?: emptyList(),
            )
            E.UNORDERED_LIST, E.ORDERED_LIST -> list(node)
            E.BLOCK_QUOTE -> MdBlock.Quote(blocks(node.children.filter { it.type != T.BLOCK_QUOTE }))
            E.CODE_FENCE -> {
                val content = node.children.filter { it.type == T.CODE_FENCE_CONTENT || it.type == T.EOL }
                    .dropWhile { it.type == T.EOL }
                    .joinToString("") { if (it.type == T.EOL) "\n" else text(it) }
                    .removeSuffix("\n")
                MdBlock.Code(content, node.children.firstOrNull { it.type == T.FENCE_LANG }?.let(::text)?.trim())
            }
            E.CODE_BLOCK -> MdBlock.Code(
                node.children.joinToString("") { if (it.type == T.EOL) "\n" else text(it) }.trimEnd('\n'),
                null,
            )
            E.HTML_BLOCK -> MdBlock.Html(text(node).trimEnd('\n'))
            T.HORIZONTAL_RULE -> MdBlock.Rule
            GFMElementTypes.TABLE -> table(node)
            E.LINK_DEFINITION, T.EOL, T.WHITE_SPACE -> null
            else -> if (node.children.isEmpty()) null else MdBlock.Paragraph(inlines(node.children))
        }

        fun list(node: ASTNode): MdBlock.ListBlock {
            val ordered = node.type == E.ORDERED_LIST
            val items = node.children.filter { it.type == E.LIST_ITEM }
            val start = if (ordered) items.firstOrNull()?.children?.firstOrNull { it.type == T.LIST_NUMBER }
                ?.let { text(it).trim().dropLast(1).toIntOrNull() } ?: 1 else 1
            return MdBlock.ListBlock(ordered, start, items.map { item ->
                val box = item.children.firstOrNull { it.type == GFMTokenTypes.CHECK_BOX }?.let(::text)
                MdBlock.ListItem(
                    blocks = blocks(item.children.filter { it.type != T.LIST_BULLET && it.type != T.LIST_NUMBER && it.type != GFMTokenTypes.CHECK_BOX }),
                    checked = box?.let { it.contains('x', ignoreCase = true) },
                )
            })
        }

        fun table(node: ASTNode): MdBlock.Table {
            fun cells(row: ASTNode) = row.children.filter { it.type == GFMTokenTypes.CELL }.map { inlines(it.children).trimText() }
            val header = node.children.firstOrNull { it.type == GFMElementTypes.HEADER }?.let(::cells) ?: emptyList()
            val separator = node.children.firstOrNull { it.type == GFMTokenTypes.TABLE_SEPARATOR && text(it).contains('-') }
            val alignments = separator?.let { s ->
                text(s).trim().trim('|').split('|').map { spec ->
                    val t = spec.trim()
                    when {
                        t.startsWith(":") && t.endsWith(":") -> GridAlign.Center
                        t.endsWith(":") -> GridAlign.Right
                        t.startsWith(":") -> GridAlign.Left
                        else -> null
                    }
                }
            } ?: emptyList()
            val rows = node.children.filter { it.type == GFMElementTypes.ROW }.map(::cells)
            return MdBlock.Table(header, rows, alignments)
        }

        fun List<MdInline>.trimText(): List<MdInline> {
            if (isEmpty()) return this
            val out = toMutableList()
            (out.first() as? MdInline.Text)?.let { out[0] = MdInline.Text(it.text.trimStart()) }
            (out.last() as? MdInline.Text)?.let { out[out.lastIndex] = MdInline.Text(it.text.trimEnd()) }
            return out.filterNot { it is MdInline.Text && it.text.isEmpty() }
        }

        fun inlines(nodes: List<ASTNode>): List<MdInline> {
            val out = ArrayList<MdInline>()
            var afterEol = false
            fun appendText(value: String) {
                if (value.isEmpty()) return
                val last = out.lastOrNull()
                if (last is MdInline.Text) out[out.lastIndex] = MdInline.Text(last.text + value) else out.add(MdInline.Text(value))
            }
            for (node in nodes) {
                val type = node.type
                if (afterEol && type == T.WHITE_SPACE) continue
                afterEol = false
                when (type) {
                    T.EOL -> { appendText("\n"); afterEol = true }
                    T.HARD_LINE_BREAK -> { out.add(MdInline.LineBreak); afterEol = true }
                    E.STRONG -> out.add(MdInline.Strong(inlines(stripDelimiters(node.children, T.EMPH, 2))))
                    E.EMPH -> out.add(MdInline.Emphasis(inlines(stripDelimiters(node.children, T.EMPH, 1))))
                    GFMElementTypes.STRIKETHROUGH -> out.add(MdInline.Strike(inlines(node.children.filter { it.type != GFMTokenTypes.TILDE })))
                    E.CODE_SPAN -> out.add(MdInline.Code(codeSpan(node)))
                    E.INLINE_LINK -> link(node, node.children.firstOrNull { it.type == E.LINK_DESTINATION }?.let(::text), out)
                    E.FULL_REFERENCE_LINK, E.SHORT_REFERENCE_LINK -> {
                        val label = node.children.firstOrNull { it.type == E.LINK_LABEL }
                        val destination = label?.let { links.getLinkInfo(text(it))?.destination?.toString() }
                        if (destination == null) appendText(unescape(text(node))) else link(node, destination, out)
                    }
                    E.AUTOLINK -> {
                        val raw = text(node).removePrefix("<").removeSuffix(">")
                        GridUrl.safe(raw)?.let { out.add(MdInline.Link(it, listOf(MdInline.Text(raw)))) } ?: appendText(raw)
                    }
                    GFMTokenTypes.GFM_AUTOLINK -> {
                        val raw = text(node)
                        val href = GridUrl.safe(if (raw.startsWith("www.", ignoreCase = true)) "http://$raw" else raw)
                        if (href != null) out.add(MdInline.Link(href, listOf(MdInline.Text(raw)))) else appendText(raw)
                    }
                    E.IMAGE -> {
                        // Alt text only: Markdown images are never fetched.
                        val linkNode = node.children.firstOrNull { it.type != T.EXCLAMATION_MARK }
                        val label = linkNode?.children?.firstOrNull { it.type == E.LINK_TEXT || it.type == E.LINK_LABEL }
                        label?.let { inlines(it.children.filter { c -> c.type != T.LBRACKET && c.type != T.RBRACKET }) }
                            ?.let { GridMarkdown.plainText(it) }?.let(::appendText)
                    }
                    T.TEXT -> appendText(unescape(text(node)))
                    T.HTML_TAG -> appendText(text(node))
                    T.ESCAPED_BACKTICKS -> appendText(text(node).replace("\\", ""))
                    else -> if (node.children.isEmpty()) appendText(unescape(text(node))) else inlines(node.children).forEach { inline ->
                        if (inline is MdInline.Text) appendText(inline.text) else out.add(inline)
                    }
                }
            }
            return out
        }

        fun stripDelimiters(children: List<ASTNode>, type: IElementType, count: Int): List<ASTNode> {
            var list = children
            repeat(count) {
                if (list.firstOrNull()?.type == type) list = list.drop(1)
                if (list.lastOrNull()?.type == type) list = list.dropLast(1)
            }
            return list
        }

        fun codeSpan(node: ASTNode): String {
            val inner = node.children.dropWhile { it.type == T.BACKTICK }.dropLastWhile { it.type == T.BACKTICK }
            val raw = inner.joinToString("") { if (it.type == T.EOL) " " else text(it) }
            return if (raw.length >= 2 && raw.startsWith(" ") && raw.endsWith(" ") && raw.isNotBlank()) raw.substring(1, raw.length - 1) else raw
        }

        fun link(node: ASTNode, destination: String?, out: MutableList<MdInline>) {
            val label = node.children.firstOrNull { it.type == E.LINK_TEXT } ?: node.children.firstOrNull { it.type == E.LINK_LABEL }
            val children = label?.let { inlines(it.children.filter { c -> c.type != T.LBRACKET && c.type != T.RBRACKET }) } ?: emptyList()
            val href = destination?.trim()?.removePrefix("<")?.removeSuffix(">")?.let { unescape(it) }?.let(GridUrl::safe)
            if (href != null) out.add(MdInline.Link(href, children))
            else children.forEach { inline ->
                val last = out.lastOrNull()
                if (inline is MdInline.Text && last is MdInline.Text) out[out.lastIndex] = MdInline.Text(last.text + inline.text) else out.add(inline)
            }
        }
    }
}
