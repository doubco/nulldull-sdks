package com.nulldull.grid.compose

import androidx.compose.foundation.clickable
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.layout.wrapContentHeight
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.key
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.layout.Layout
import androidx.compose.ui.layout.Placeable
import androidx.compose.ui.platform.LocalUriHandler
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.isTraversalGroup
import androidx.compose.ui.semantics.role
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.testTag
import androidx.compose.ui.semantics.traversalIndex
import androidx.compose.ui.unit.Constraints
import androidx.compose.ui.unit.dp
import com.nulldull.grid.GridBuiltinNode
import com.nulldull.grid.GridCustomNode
import com.nulldull.grid.GridDocument
import com.nulldull.grid.GridLayout
import com.nulldull.grid.GridLayoutEngine
import com.nulldull.grid.GridLimits
import com.nulldull.grid.GridNode
import com.nulldull.grid.GridNodeKind
import com.nulldull.grid.GridShape
import com.nulldull.grid.GridUrl
import com.nulldull.grid.client.PublicGridPage
import kotlin.math.roundToInt

/**
 * Renders a Grid document at the width of its container (or [width]), selecting the
 * breakpoint like the web renderer. The renderer reports the full canvas height; place it
 * in a vertically scrolling container for long pages. Canvases wider than the container
 * (horizontal grids) scroll horizontally.
 *
 * @param resolveAsset maps Grid asset ids to absolute http(s) URLs. Other values are ignored.
 *   Never put a private API key in these URLs.
 * @param customNodes trusted host components by `nodeKey`. Stored custom properties are inert data.
 * @param renderUnknownNode replaces the inert placeholder for unregistered keys.
 * @param renderEmbed replaces the built-in YouTube/Vimeo player, e.g. to gate it behind consent. It
 *   takes precedence over [embedLoading].
 * @param renderVideo replaces the built-in video player.
 * @param renderAudio replaces the built-in audio control.
 * @param layout with [breakpointId], forces a layout instead of width-based selection.
 * @param embedLoading when the built-in YouTube/Vimeo player loads. [GridEmbedLoading.Immediate]
 *   (default) loads it as soon as the embed is composed, which contacts the provider without a tap;
 *   [GridEmbedLoading.Tap] shows a local poster and loads the player only after the viewer taps it.
 * @param onOpenUrl opens safe http(s) links; defaults to the platform URI handler.
 */
@Composable
public fun GridRenderer(
    document: GridDocument,
    modifier: Modifier = Modifier,
    resolveAsset: (String) -> String? = { null },
    customNodes: Map<String, @Composable (GridCustomNode) -> Unit> = emptyMap(),
    renderUnknownNode: (@Composable (GridCustomNode) -> Unit)? = null,
    renderEmbed: (@Composable (GridBuiltinNode) -> Unit)? = null,
    renderVideo: (@Composable (GridBuiltinNode, String) -> Unit)? = null,
    renderAudio: (@Composable (GridBuiltinNode, String) -> Unit)? = null,
    width: androidx.compose.ui.unit.Dp? = null,
    layout: GridLayout? = null,
    breakpointId: String? = null,
    theme: GridTheme = GridTheme(),
    messages: GridMessages = GridMessages(),
    options: GridRenderOptions = GridRenderOptions(),
    label: String? = null,
    embedLoading: GridEmbedLoading = GridEmbedLoading.Immediate,
    onOpenUrl: ((String) -> Unit)? = null,
) {
    val uriHandler = LocalUriHandler.current
    val openUrl: (String) -> Unit = { url -> GridUrl.safe(url)?.let { safe -> onOpenUrl?.invoke(safe) ?: runCatching { uriHandler.openUri(safe) } } }
    val asset: (String?) -> String? = { id -> id?.let(resolveAsset)?.let(GridUrl::safe) }
    val dark = isSystemInDarkTheme()
    CompositionLocalProvider(LocalGridOptions provides options) {
        BoxWithConstraints(
            modifier.fillMaxWidth().then(if (label != null) Modifier.semantics { contentDescription = label } else Modifier),
        ) {
            val viewport = width?.value ?: if (constraints.hasBoundedWidth) maxWidth.value else options.initialWidthDp
            val active = if (layout != null) com.nulldull.grid.GridActiveLayout(layout, breakpointId)
            else GridLayoutEngine.layoutAt(document, viewport.toDouble())
            val activeLayout = active.layout
            val hostForeground = if (theme.foreground != Color.Unspecified) theme.foreground else if (dark) Color.White else Color.Black
            val foreground = themeColor(activeLayout.color, hostForeground).withOpacity(activeLayout.colorOpacity)
            val canvasBackground = themeColor(activeLayout.background, theme.background)
            val flow = activeLayout.flowGap != null
            val visible = remember(document) { document.nodes.filter { !it.hidden } }
            val fontUrls = remember(document, resolveAsset) {
                document.nodes.asSequence().filterIsInstance<GridBuiltinNode>()
                    .filter { it.kind == GridNodeKind.Text && !it.hidden && it.fontAssetId != null }
                    .mapNotNull { asset(it.fontAssetId) }.distinct().take(GridLimits.MAX_FONTS).toSet()
            }
            val scroll = rememberScrollState()
            Box(Modifier.fillMaxWidth().horizontalScroll(scroll)) {
              // Narrower canvases are centered, like the web renderer's `margin-inline: auto`.
              Box(Modifier.widthIn(min = viewport.dp), contentAlignment = Alignment.TopCenter) {
                Layout(
                    modifier = Modifier.semantics { isTraversalGroup = true },
                    content = {
                        // Canvas background: color, image and radius; nodes are not clipped by it.
                        Box(Modifier.clip(RoundedCornerShape((activeLayout.radius ?: 0).dp))) {
                            GridBackground(
                                canvasBackground, asset(activeLayout.backgroundImageId), activeLayout.backgroundFit,
                                activeLayout.backgroundOpacity,
                            )
                        }
                        visible.forEachIndexed { index, node ->
                            key(node.id) {
                                val contentSized = flow && node.ignoreFlow != true && node is GridBuiltinNode && node.kind == GridNodeKind.Text
                                GridNodeView(
                                    node = node, index = index, contentSized = contentSized, foreground = foreground, theme = theme,
                                    messages = messages, asset = asset, fontUrls = fontUrls, openUrl = openUrl, customNodes = customNodes,
                                    renderUnknownNode = renderUnknownNode, renderEmbed = renderEmbed, renderVideo = renderVideo,
                                    renderAudio = renderAudio, embedLoading = embedLoading,
                                )
                            }
                        }
                    },
                ) { measurables, _ ->
                    val density = this
                    val placeables = arrayOfNulls<Placeable>(measurables.size)
                    val nodeIndex = visible.withIndex().associate { (i, n) -> n.id to i + 1 }
                    fun px(dp: Double) = (dp * density.density).roundToInt()
                    val geometry = GridLayoutEngine.layout(document, viewport.toDouble(), layout, breakpointId) { node, nodeWidth ->
                        val i = nodeIndex.getValue(node.id)
                        val w = px(nodeWidth).coerceAtLeast(0)
                        val placeable = measurables[i].measure(Constraints(minWidth = w, maxWidth = w))
                        placeables[i] = placeable
                        placeable.height / density.density.toDouble()
                    }
                    val canvasW = px(geometry.canvasWidth).coerceAtLeast(0)
                    val canvasH = px(geometry.canvasHeight).coerceAtLeast(0)
                    placeables[0] = measurables[0].measure(Constraints.fixed(canvasW, canvasH))
                    val positions = geometry.nodes.map { placed ->
                        val i = nodeIndex.getValue(placed.node.id)
                        val x = px(placed.rect.x)
                        val y = px(placed.rect.y)
                        val w = (px(placed.rect.x + placed.rect.width) - x).coerceAtLeast(0)
                        val h = (px(placed.rect.y + placed.rect.height) - y).coerceAtLeast(0)
                        if (placeables[i] == null) placeables[i] = measurables[i].measure(Constraints.fixed(w, h))
                        Triple(i, x, y)
                    }
                    layout(canvasW, canvasH) {
                        placeables[0]!!.place(0, 0)
                        // Grid geometry is authored in physical coordinates; it does not mirror in RTL.
                        positions.forEach { (i, x, y) -> placeables[i]!!.place(x, y) }
                    }
                }
              }
            }
        }
    }
}

/**
 * Renders a page from [com.nulldull.grid.client.GridClient.getPage], resolving assets from its pinned manifest.
 * The parameters behave as in [GridRenderer].
 */
@Composable
public fun PublishedGridPage(
    page: PublicGridPage,
    modifier: Modifier = Modifier,
    customNodes: Map<String, @Composable (GridCustomNode) -> Unit> = emptyMap(),
    renderUnknownNode: (@Composable (GridCustomNode) -> Unit)? = null,
    renderEmbed: (@Composable (GridBuiltinNode) -> Unit)? = null,
    theme: GridTheme = GridTheme(),
    messages: GridMessages = GridMessages(),
    options: GridRenderOptions = GridRenderOptions(),
    label: String? = page.title,
    embedLoading: GridEmbedLoading = GridEmbedLoading.Immediate,
    onOpenUrl: ((String) -> Unit)? = null,
) {
    val assets = remember(page) { page.assets.associate { it.id to it.url } }
    GridRenderer(
        document = page.document, modifier = modifier, resolveAsset = { assets[it] }, customNodes = customNodes,
        renderUnknownNode = renderUnknownNode, renderEmbed = renderEmbed, theme = theme, messages = messages,
        options = options, label = label, embedLoading = embedLoading, onOpenUrl = onOpenUrl,
    )
}

@Composable
private fun GridNodeView(
    node: GridNode,
    index: Int,
    contentSized: Boolean,
    foreground: Color,
    theme: GridTheme,
    messages: GridMessages,
    asset: (String?) -> String?,
    fontUrls: Set<String>,
    openUrl: (String) -> Unit,
    customNodes: Map<String, @Composable (GridCustomNode) -> Unit>,
    renderUnknownNode: (@Composable (GridCustomNode) -> Unit)?,
    renderEmbed: (@Composable (GridBuiltinNode) -> Unit)?,
    renderVideo: (@Composable (GridBuiltinNode, String) -> Unit)?,
    renderAudio: (@Composable (GridBuiltinNode, String) -> Unit)?,
    embedLoading: GridEmbedLoading,
) {
    val builtin = node as? GridBuiltinNode
    val radius = (builtin?.radius ?: 0).dp
    val shape = RoundedCornerShape(radius)
    val color = themeColor(builtin?.color, foreground)
    val borderWidth = (builtin?.borderWidth ?: 0).dp
    val size = if (contentSized) Modifier.fillMaxWidth().wrapContentHeight() else Modifier.fillMaxSize()
    Box(
        size
            // `grid:<node id>` lets host UI tests find nodes; traversal follows document order like the DOM.
            .semantics { traversalIndex = index.toFloat(); testTag = "grid:${node.id}" }
            .graphicsLayer {
                alpha = (node.opacity ?: 1.0).toFloat().coerceIn(0f, 1f)
                rotationZ = (builtin?.rotation ?: 0.0).toFloat()
            }
            .clip(shape)
            .then(
                if (builtin != null) Modifier.gridBorder(
                    borderWidth, themeColor(builtin.borderColor, foreground).withOpacity(builtin.borderOpacity),
                    builtin.borderStyle, radius,
                ) else Modifier,
            ),
    ) {
        Box((if (contentSized) Modifier.fillMaxWidth().wrapContentHeight() else Modifier.fillMaxSize()).padding(borderWidth)) {
            if (builtin != null) {
                GridBackground(
                    themeColor(builtin.background, Color.Transparent), asset(builtin.backgroundImageId), builtin.backgroundFit,
                    builtin.backgroundOpacity, Modifier.matchParentSize(),
                )
            }
            when {
                node is GridCustomNode -> {
                    val registered = customNodes[node.nodeKey]
                    when {
                        registered != null -> registered(node)
                        renderUnknownNode != null -> renderUnknownNode(node)
                        else -> GridPlaceholder(node.nodeKey, foreground)
                    }
                }
                builtin == null -> Unit
                builtin.kind == GridNodeKind.Text -> {
                    val uploaded = builtin.fontAssetId?.let(asset)?.takeIf { it in fontUrls }
                    val loaded = rememberGridFont(uploaded)
                    GridTextContent(
                        builtin, color, contentSized, loaded ?: theme.family(builtin.fontFamily), theme.mono, openUrl,
                    )
                }
                builtin.kind == GridNodeKind.Separator -> GridSeparatorContent(builtin, foreground)
                builtin.kind == GridNodeKind.Shape && builtin.shape == GridShape.Svg ->
                    GridSvgShape(builtin, asset(builtin.assetId), messages, color, openUrl)
                builtin.kind == GridNodeKind.Shape -> GridShapeContent(builtin, foreground)
                builtin.kind == GridNodeKind.Embed ->
                    if (renderEmbed != null) renderEmbed(builtin) else GridEmbedContent(builtin, color, messages, embedLoading, openUrl)
                else -> {
                    val url = asset(builtin.assetId)
                    when {
                        url == null -> GridPlaceholder(messages.chooseAsset, color)
                        builtin.kind == GridNodeKind.Image -> GridImageContent(builtin, url, messages, color)
                        builtin.kind == GridNodeKind.Video ->
                            if (renderVideo != null) renderVideo(builtin, url) else GridVideoContent(builtin, url)
                        else -> if (renderAudio != null) renderAudio(builtin, url) else GridAudioContent(builtin, url, messages, color)
                    }
                }
            }
            val link = GridUrl.safe(builtin?.link)
            if (link != null) Box(
                Modifier.matchParentSize()
                    .clickable(role = Role.Button, onClickLabel = node.name) { openUrl(link) }
                    .semantics { contentDescription = node.name; role = Role.Button },
            )
        }
    }
}
