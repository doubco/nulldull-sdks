package com.nulldull.grid.compose

import androidx.compose.foundation.background
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.IntrinsicSize
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.wrapContentHeight
import androidx.compose.foundation.layout.wrapContentWidth
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.text.BasicText
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.layout.SubcomposeLayout
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.LinkAnnotation
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.TextLinkStyles
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.rememberTextMeasurer
import androidx.compose.ui.text.style.LineHeightStyle
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextDecoration
import androidx.compose.ui.text.withLink
import androidx.compose.ui.text.withStyle
import androidx.compose.ui.unit.Constraints
import androidx.compose.ui.unit.dp
import com.nulldull.grid.GridAlign
import com.nulldull.grid.GridBuiltinNode
import com.nulldull.grid.GridLimits
import com.nulldull.grid.GridMarkdown
import com.nulldull.grid.GridVerticalAlign
import com.nulldull.grid.MdBlock
import com.nulldull.grid.MdInline
import kotlin.math.ceil
import kotlin.math.max

/** Everything a Markdown block needs to style itself, in layout pixels (dp). */
private class TextEnv(
    val style: TextStyle,
    /** Effective font size in dp (after font scaling), the `em` for margins. */
    val em: Float,
    val mono: FontFamily,
    val color: Color,
    val openUrl: (String) -> Unit,
    val scaled: Boolean,
    val baseFontPx: Double,
    val lineHeight: Double,
)

/**
 * Text node: Markdown (CommonMark + GFM tables, lists, strikethrough, autolinks), drop
 * caps, fit-to-box sizing, uploaded fonts. HTML is shown as literal text and Markdown
 * images as their alt text, as the web renderer does.
 */
@Composable
internal fun GridTextContent(
    node: GridBuiltinNode,
    color: Color,
    contentSized: Boolean,
    fontFamily: FontFamily,
    mono: FontFamily,
    openUrl: (String) -> Unit,
) {
    val options = LocalGridOptions.current
    val scaled = when (options.fontScaling) {
        GridFontScaling.Always -> true
        GridFontScaling.Never -> false
        GridFontScaling.FlowOnly -> contentSized
    }
    val blocks = remember(node.text) { GridMarkdown.parse(node.text) }
    val lineHeight = node.lineHeight ?: GridLimits.DEFAULT_LINE_HEIGHT
    val alignment = when (node.verticalAlign) {
        GridVerticalAlign.Middle -> Alignment.CenterVertically
        GridVerticalAlign.Bottom -> Alignment.Bottom
        else -> Alignment.Top
    }
    val box = Modifier.fillMaxWidth()
        .then(if (contentSized) Modifier.wrapContentHeight() else Modifier.fillMaxHeight())
        .padding((node.padding ?: GridLimits.DEFAULT_TEXT_PADDING).dp)
        .alpha((node.colorOpacity ?: 1.0).toFloat())
    val density = LocalDensity.current
    fun env(fontPx: Double) = TextEnv(
        style = TextStyle(
            color = color,
            fontSize = density.gridTextUnit(fontPx, scaled),
            lineHeight = density.gridTextUnit(fontPx * lineHeight, scaled),
            fontFamily = fontFamily,
            textAlign = when (node.align) {
                GridAlign.Left -> TextAlign.Left
                GridAlign.Center -> TextAlign.Center
                GridAlign.Right -> TextAlign.Right
                GridAlign.Justify -> TextAlign.Justify
            },
            lineHeightStyle = LineHeightStyle(LineHeightStyle.Alignment.Center, LineHeightStyle.Trim.None),
        ),
        em = (fontPx * if (scaled) density.fontScale else 1f).toFloat(),
        mono = mono, color = color, openUrl = openUrl, scaled = scaled, baseFontPx = fontPx, lineHeight = lineHeight,
    )
    Box(box) {
        if (node.fitToBox == true && !contentSized) {
            FittedText(alignment) { size -> MarkdownBlocks(blocks, env(size.toDouble()), node.dropcap == true) }
        } else {
            Column(
                Modifier.fillMaxWidth().then(
                    if (contentSized) Modifier else Modifier.wrapContentHeight(alignment, unbounded = true),
                ),
            ) {
                MarkdownBlocks(blocks, env(node.fontSize.toDouble()), node.dropcap == true)
            }
        }
    }
}

/** Largest font size from 8 to 256 whose content fits the box height, as the web binary search. */
@Composable
private fun FittedText(alignment: Alignment.Vertical, content: @Composable (Int) -> Unit) {
    val tolerance = with(LocalDensity.current) { 1.dp.roundToPx() }
    SubcomposeLayout(Modifier.fillMaxSize()) { constraints ->
        val width = constraints.maxWidth
        val height = constraints.maxHeight
        val loose = Constraints(maxWidth = width)
        fun measure(size: Int, slot: String) =
            subcompose(slot) { Column(Modifier.fillMaxWidth()) { content(size) } }.map { it.measure(loose) }
        var low = 8
        var high = 256
        var best = 8
        while (low <= high) {
            val size = (low + high) / 2
            if (measure(size, "fit-$size").sumOf { it.height } <= height + tolerance) {
                best = size; low = size + 1
            } else high = size - 1
        }
        val placeables = measure(best, "final")
        val total = placeables.sumOf { it.height }
        layout(width, height) {
            var y = alignment.align(total, height)
            placeables.forEach { it.place(0, y); y += it.height }
        }
    }
}

private class Margins(val top: Float, val bottom: Float)

private fun margins(block: MdBlock, inListItem: Boolean): Margins = when {
    inListItem && (block is MdBlock.Paragraph || block is MdBlock.ListBlock) -> Margins(0f, 0f)
    block is MdBlock.Paragraph -> Margins(0f, 0.5f)
    block is MdBlock.Heading -> Margins(0.5f, 0.5f)
    block is MdBlock.ListBlock || block is MdBlock.Quote || block is MdBlock.Code -> Margins(1f, 1f)
    block is MdBlock.Rule -> Margins(0.5f, 0.5f)
    else -> Margins(0f, 0f)
}

/** Blocks with collapsed vertical margins; the first top and last bottom margins are zero. */
@Composable
private fun MarkdownBlocks(blocks: List<MdBlock>, env: TextEnv, dropcap: Boolean, inListItem: Boolean = false, depth: Int = 0) {
    blocks.forEachIndexed { index, block ->
        if (index > 0) {
            val gap = max(margins(blocks[index - 1], inListItem).bottom, margins(block, inListItem).top) * env.em
            if (gap > 0f) Spacer(Modifier.height(gap.dp))
        }
        MarkdownBlock(block, env, dropcap && index == 0, inListItem, depth)
    }
}

@Composable
private fun MarkdownBlock(block: MdBlock, env: TextEnv, dropcap: Boolean, inListItem: Boolean, depth: Int) {
    when (block) {
        is MdBlock.Paragraph -> {
            val text = remember(block, env.mono) { inlineText(block.inlines, env) }
            if (dropcap && text.isNotEmpty()) DropCapParagraph(text, env) else BasicText(text, Modifier.fillMaxWidth(), style = env.style)
        }
        is MdBlock.Heading -> BasicText(
            remember(block, env.mono) { inlineText(block.inlines, env) },
            Modifier.fillMaxWidth(), style = env.style.copy(fontWeight = FontWeight.Bold),
        )
        is MdBlock.Html -> BasicText(block.text, Modifier.fillMaxWidth(), style = env.style)
        is MdBlock.Code -> Box(Modifier.fillMaxWidth().horizontalScroll(rememberScrollState())) {
            BasicText(block.text, style = env.style.copy(fontFamily = env.mono, textAlign = TextAlign.Left), softWrap = false)
        }
        is MdBlock.Rule -> Column(Modifier.fillMaxWidth()) {
            Box(Modifier.fillMaxWidth().height(1.dp).background(Color(0xFF9A9A9A)))
            Box(Modifier.fillMaxWidth().height(1.dp).background(Color(0xFFEEEEEE)))
        }
        is MdBlock.Quote -> Column(Modifier.fillMaxWidth().padding(horizontal = 40.dp)) {
            MarkdownBlocks(block.blocks, env, dropcap = false)
        }
        is MdBlock.ListBlock -> Column(Modifier.fillMaxWidth()) {
            block.items.forEachIndexed { i, item ->
                val marker = when {
                    item.checked != null -> if (item.checked == true) "☑ " else "☐ "
                    block.ordered -> "${block.start + i}. "
                    // The web stylesheet sets `list-style-type: disc` on every unordered list.
                    else -> "• "
                }
                Row(Modifier.fillMaxWidth()) {
                    Box(Modifier.width((1.3f * env.em).dp)) {
                        BasicText(
                            marker, Modifier.align(Alignment.TopEnd).wrapContentWidth(Alignment.End, unbounded = true),
                            style = env.style.copy(textAlign = TextAlign.Right), maxLines = 1,
                        )
                    }
                    Column(Modifier.weight(1f)) {
                        MarkdownBlocks(item.blocks, env, dropcap = false, inListItem = true, depth = depth + 1)
                    }
                }
            }
        }
        is MdBlock.Table -> MarkdownTable(block, env)
    }
}

/** Fixed-weight table approximating the browser's auto layout: column widths follow their longest text. */
@Composable
private fun MarkdownTable(table: MdBlock.Table, env: TextEnv) {
    val columns = maxOf(table.header.size, table.rows.maxOfOrNull { it.size } ?: 0)
    if (columns == 0) return
    val all = listOf(table.header) + table.rows
    val weights = (0 until columns).map { c ->
        all.maxOf { row -> row.getOrNull(c)?.let { GridMarkdown.plainText(it).length } ?: 0 }.coerceIn(3, 40).toFloat()
    }
    val border = env.color
    val pad = (0.25f * env.em).dp
    Column(Modifier.fillMaxWidth().cellBorder(border, top = true, left = true)) {
        all.forEachIndexed { r, row ->
            if (r == 0 && table.header.isEmpty()) return@forEachIndexed
            Row(Modifier.fillMaxWidth().height(IntrinsicSize.Min)) {
                for (c in 0 until columns) {
                    val inlines = row.getOrNull(c) ?: emptyList()
                    val align = table.alignments.getOrNull(c)
                    val style = env.style.copy(
                        fontWeight = if (r == 0) FontWeight.Bold else env.style.fontWeight,
                        textAlign = when (align) {
                            GridAlign.Center -> TextAlign.Center
                            GridAlign.Right -> TextAlign.Right
                            GridAlign.Left -> TextAlign.Left
                            // Header cells inherit the node alignment, as `th` does under an explicit `text-align`.
                            else -> env.style.textAlign
                        },
                    )
                    Box(Modifier.weight(weights[c]).fillMaxHeight().cellBorder(border, top = false, left = false).padding(pad)) {
                        BasicText(remember(inlines, env.mono) { inlineText(inlines, env) }, Modifier.fillMaxWidth(), style = style)
                    }
                }
            }
        }
    }
}

/** Collapsed 1px table borders: the table draws top/left edges, each cell its right/bottom edges. */
private fun Modifier.cellBorder(color: Color, top: Boolean, left: Boolean): Modifier = drawBehind {
    val w = 1.dp.toPx()
    if (top) drawRect(color, size = Size(size.width, w))
    if (left) drawRect(color, size = Size(w, size.height))
    if (!top && !left) {
        drawRect(color, topLeft = Offset(size.width - w, 0f), size = Size(w, size.height))
        drawRect(color, topLeft = Offset(0f, size.height - w), size = Size(size.width, w))
    }
}

/** Floated first letter: 3.2em, line-height 0.85, wrapping the following lines beside it. */
@Composable
private fun DropCapParagraph(text: AnnotatedString, env: TextEnv) {
    BoxWithConstraints(Modifier.fillMaxWidth()) {
        val measurer = rememberTextMeasurer()
        val density = LocalDensity.current
        val end = text.text.offsetByCodePoints(0, 1)
        val letter = text.subSequence(0, end)
        val rest = text.subSequence(end, text.length)
        val letterStyle = env.style.copy(
            fontSize = env.style.fontSize * 3.2f,
            lineHeight = env.style.fontSize * 3.2f * 0.85f,
            lineHeightStyle = LineHeightStyle(LineHeightStyle.Alignment.Center, LineHeightStyle.Trim.Both),
        )
        val padTop = 0.08f * 3.2f * env.em
        val padEnd = 0.1f * 3.2f * env.em
        val widthPx = constraints.maxWidth
        val split = remember(text, env.style, widthPx) {
            with(density) {
                val letterLayout = measurer.measure(letter, letterStyle)
                val floatWidth = letterLayout.size.width + padEnd.dp.roundToPx()
                val floatHeight = letterLayout.size.height + padTop.dp.toPx()
                val line = env.style.lineHeight.toPx()
                val lines = max(1, ceil(floatHeight / line).toInt())
                val beside = measurer.measure(rest, env.style, constraints = Constraints(maxWidth = (widthPx - floatWidth).coerceAtLeast(1)))
                if (beside.lineCount > lines) beside.getLineEnd(lines - 1) else rest.length
            }
        }
        Column(Modifier.fillMaxWidth()) {
            Row(Modifier.fillMaxWidth()) {
                BasicText(letter, Modifier.padding(top = padTop.dp, end = padEnd.dp), style = letterStyle.copy(textAlign = TextAlign.Left))
                BasicText(rest.subSequence(0, split), Modifier.weight(1f), style = env.style)
            }
            if (split < rest.length) BasicText(rest.subSequence(split, rest.length).trimLeadingNewline(), Modifier.fillMaxWidth(), style = env.style)
        }
    }
}

private fun AnnotatedString.trimLeadingNewline(): AnnotatedString =
    if (text.startsWith("\n")) subSequence(1, length) else this

private fun inlineText(inlines: List<MdInline>, env: TextEnv): AnnotatedString = buildAnnotatedString {
    fun add(list: List<MdInline>) {
        list.forEach { inline ->
            when (inline) {
                is MdInline.Text -> append(inline.text)
                is MdInline.LineBreak -> append('\n')
                is MdInline.Strong -> withStyle(SpanStyle(fontWeight = FontWeight.Bold)) { add(inline.children) }
                is MdInline.Emphasis -> withStyle(SpanStyle(fontStyle = FontStyle.Italic)) { add(inline.children) }
                is MdInline.Strike -> withStyle(SpanStyle(textDecoration = TextDecoration.LineThrough)) { add(inline.children) }
                is MdInline.Code -> withStyle(SpanStyle(fontFamily = env.mono)) { append(inline.text) }
                is MdInline.Link -> withLink(
                    LinkAnnotation.Url(
                        inline.href,
                        TextLinkStyles(SpanStyle(textDecoration = TextDecoration.Underline)),
                    ) { env.openUrl(inline.href) },
                ) { add(inline.children) }
            }
        }
    }
    add(inlines)
}
