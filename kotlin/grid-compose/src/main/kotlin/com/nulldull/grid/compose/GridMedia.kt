package com.nulldull.grid.compose

import android.media.AudioAttributes
import android.media.MediaPlayer
import android.net.Uri
import android.widget.MediaController
import android.widget.VideoView
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.text.BasicText
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.drawscope.translate
import androidx.compose.ui.graphics.painter.Painter
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.role
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextDecoration
import androidx.compose.ui.unit.dp
import androidx.compose.ui.viewinterop.AndroidView
import coil3.compose.AsyncImage
import coil3.compose.AsyncImagePainter
import coil3.compose.rememberAsyncImagePainter
import coil3.request.ImageRequest
import com.nulldull.grid.GridBuiltinNode
import com.nulldull.grid.GridFit
import com.nulldull.grid.GridUrl

/** Centered placeholder text, like the web renderer's `.placeholder` (12px, medium weight). */
@Composable
internal fun GridPlaceholder(text: String, color: Color, modifier: Modifier = Modifier, link: (() -> Unit)? = null, linkText: String? = null) {
    val style = TextStyle(color = color, fontSize = with(androidx.compose.ui.platform.LocalDensity.current) { gridTextUnit(12.0, false) },
        fontWeight = FontWeight.Medium, textAlign = TextAlign.Center)
    Column(
        modifier.fillMaxSize().padding(4.dp),
        verticalArrangement = Arrangement.spacedBy(8.dp, Alignment.CenterVertically),
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        BasicText(text, style = style)
        if (link != null && linkText != null) BasicText(
            linkText,
            Modifier.clickable(role = Role.Button, onClick = link),
            style = style.copy(textDecoration = TextDecoration.Underline),
        )
    }
}

/** Layer or node background: color plus optional cover/contain/tile image, at its own opacity. */
@Composable
internal fun GridBackground(color: Color, imageUrl: String?, fit: GridFit?, opacity: Double?, modifier: Modifier = Modifier) {
    if (color.alpha == 0f && imageUrl == null) return
    Box(modifier.fillMaxSize().clearAndSetSemantics { }.alpha((opacity ?: 1.0).toFloat()).background(color)) {
        if (imageUrl != null) {
            if (fit == GridFit.Tile) TiledImage(imageUrl, centered = true, modifier = Modifier.fillMaxSize())
            else AsyncImage(
                model = imageUrl, contentDescription = null, imageLoader = rememberGridImageLoader(),
                contentScale = if (fit == GridFit.Contain) ContentScale.Fit else ContentScale.Crop,
                modifier = Modifier.fillMaxSize(),
            )
        }
    }
}

/** Repeats the image at its natural size (1 image pixel = 1 dp), like CSS `background-repeat`. */
@Composable
internal fun TiledImage(url: String, centered: Boolean, modifier: Modifier) {
    val painter = rememberAsyncImagePainter(model = url, imageLoader = rememberGridImageLoader())
    Box(modifier.drawBehind { drawTiles(painter, centered) })
}

private fun androidx.compose.ui.graphics.drawscope.DrawScope.drawTiles(painter: Painter, centered: Boolean) {
    val intrinsic = painter.intrinsicSize
    if (intrinsic == Size.Unspecified || intrinsic.width.isNaN() || intrinsic.width <= 0f || intrinsic.height <= 0f) return
    val tile = Size(intrinsic.width * density, intrinsic.height * density)
    val startX = if (centered) ((size.width - tile.width) / 2f).let { it - kotlin.math.ceil(it / tile.width) * tile.width } else 0f
    val startY = if (centered) ((size.height - tile.height) / 2f).let { it - kotlin.math.ceil(it / tile.height) * tile.height } else 0f
    var y = startY
    while (y < size.height) {
        var x = startX
        while (x < size.width) {
            translate(x, y) { with(painter) { draw(tile) } }
            x += tile.width
        }
        y += tile.height
    }
}

/** Raster image node: cover, contain or tile. The node name is the accessibility label. */
@Composable
internal fun GridImageContent(node: GridBuiltinNode, url: String, messages: GridMessages, color: Color) {
    val label = node.name
    if (node.fit == GridFit.Tile) {
        TiledImage(url, centered = false, modifier = Modifier.fillMaxSize().semantics { contentDescription = label; role = Role.Image })
        return
    }
    var failed by remember(url) { mutableStateOf(false) }
    if (failed) { GridPlaceholder(messages.unavailable, color); return }
    AsyncImage(
        model = url, contentDescription = label, imageLoader = rememberGridImageLoader(),
        contentScale = if (node.fit == GridFit.Contain) ContentScale.Fit else ContentScale.Crop,
        onState = { if (it is AsyncImagePainter.State.Error) failed = true },
        modifier = Modifier.fillMaxSize(),
    )
}

/** SVG shape: validated static SVG drawn with `contain`; anything else offers the original download. */
@Composable
internal fun GridSvgShape(node: GridBuiltinNode, url: String?, messages: GridMessages, color: Color, openUrl: (String) -> Unit) {
    if (url == null) { GridPlaceholder(messages.chooseAsset, color); return }
    var failed by remember(url) { mutableStateOf(false) }
    if (failed) {
        val href = GridUrl.safe(url)
        GridPlaceholder(messages.unavailable, color, link = href?.let { { openUrl(it) } }, linkText = messages.download)
        return
    }
    val context = LocalContext.current
    AsyncImage(
        model = remember(url) { ImageRequest.Builder(context).data(url).build() },
        contentDescription = node.name, imageLoader = rememberGridImageLoader(), contentScale = ContentScale.Fit,
        onState = { if (it is AsyncImagePainter.State.Error) failed = true },
        modifier = Modifier.fillMaxSize().padding((node.padding ?: 0).dp),
    )
}

/** Video with platform controls (`VideoView` + `MediaController`); loads metadata only, never autoplays. */
@Composable
internal fun GridVideoContent(node: GridBuiltinNode, url: String) {
    AndroidView(
        factory = { context ->
            VideoView(context).apply {
                contentDescription = node.name
                val controller = MediaController(context)
                controller.setAnchorView(this)
                setMediaController(controller)
                setVideoURI(Uri.parse(url))
                setOnPreparedListener { player -> player.isLooping = false; seekTo(1) }
            }
        },
        onRelease = { it.stopPlayback() },
        modifier = Modifier.fillMaxSize(),
    )
}

/** Audio: a play/pause control. Nothing is downloaded before the first play (`preload="none"`). */
@Composable
internal fun GridAudioContent(node: GridBuiltinNode, url: String, messages: GridMessages, color: Color) {
    var player by remember(url) { mutableStateOf<MediaPlayer?>(null) }
    var playing by remember(url) { mutableStateOf(false) }
    var prepared by remember(url) { mutableStateOf(false) }
    DisposableEffect(url) { onDispose { player?.release(); player = null } }
    val label = (if (playing) messages.pause else messages.play) + " " + node.name
    Row(
        Modifier.fillMaxSize()
            .clickable(role = Role.Button, onClickLabel = label) {
                val current = player
                when {
                    current == null -> player = MediaPlayer().also { created ->
                        created.setAudioAttributes(AudioAttributes.Builder().setContentType(AudioAttributes.CONTENT_TYPE_MUSIC).build())
                        created.setOnPreparedListener { prepared = true; it.start(); playing = true }
                        created.setOnCompletionListener { playing = false }
                        created.setOnErrorListener { _, _, _ -> playing = false; true }
                        runCatching { created.setDataSource(url); created.prepareAsync() }
                    }
                    !prepared -> Unit
                    playing -> { current.pause(); playing = false }
                    else -> { current.start(); playing = true }
                }
            }
            .semantics { contentDescription = label },
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.Center,
    ) {
        Canvas(Modifier.size(24.dp)) {
            if (playing) {
                drawRect(color, Offset(size.width * 0.2f, size.height * 0.15f), Size(size.width * 0.2f, size.height * 0.7f))
                drawRect(color, Offset(size.width * 0.6f, size.height * 0.15f), Size(size.width * 0.2f, size.height * 0.7f))
            } else {
                drawPath(Path().apply {
                    moveTo(size.width * 0.25f, size.height * 0.15f); lineTo(size.width * 0.85f, size.height * 0.5f)
                    lineTo(size.width * 0.25f, size.height * 0.85f); close()
                }, color)
            }
        }
    }
}
