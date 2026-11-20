package com.nulldull.grid.compose

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.ColorFilter
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.PathEffect
import androidx.compose.ui.graphics.PathFillType
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.StrokeJoin
import androidx.compose.ui.graphics.drawscope.DrawScope
import androidx.compose.ui.graphics.drawscope.Fill
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.drawscope.withTransform
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.graphics.vector.PathParser
import androidx.compose.ui.graphics.vector.rememberVectorPainter
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.unit.dp
import com.nulldull.grid.GridBuiltinNode
import com.nulldull.grid.GridSeparatorStyle
import com.nulldull.grid.GridShape
import com.nulldull.grid.GridStrokeStyle
import kotlin.math.PI
import kotlin.math.cos
import kotlin.math.min
import kotlin.math.sin

internal class GridIconSpec(val width: Float, val height: Float, val paths: List<GridIconPath>)
internal class GridIconPath(
    val d: String, val fill: Boolean, val stroke: Boolean, val strokeWidth: Float,
    val cap: String, val join: String, val evenOdd: Boolean,
)

/** Icon names come from the shared catalog; unknown names use the generic `grid-shape` glyph. */
public object GridIcons {
    public val names: Set<String> get() = gridIconData.keys

    internal fun vector(name: String?): ImageVector {
        val spec = gridIconData[name] ?: gridIconData.getValue("grid-shape")
        return ImageVector.Builder(
            name = name ?: "grid-shape", defaultWidth = 24.dp, defaultHeight = 24.dp,
            viewportWidth = spec.width, viewportHeight = spec.height,
        ).apply {
            spec.paths.forEach { p ->
                addPath(
                    pathData = PathParser().parsePathString(p.d).toNodes(),
                    pathFillType = if (p.evenOdd) PathFillType.EvenOdd else PathFillType.NonZero,
                    fill = if (p.fill) SolidColor(Color.Black) else null,
                    stroke = if (p.stroke) SolidColor(Color.Black) else null,
                    strokeLineWidth = p.strokeWidth,
                    strokeLineCap = when (p.cap) { "round" -> StrokeCap.Round; "square" -> StrokeCap.Square; else -> StrokeCap.Butt },
                    strokeLineJoin = when (p.join) { "round" -> StrokeJoin.Round; "bevel" -> StrokeJoin.Bevel; else -> StrokeJoin.Miter },
                )
            }
        }.build()
    }
}

/** `polygonPoints`: regular polygon or five-point star in a 100×100 viewBox. */
internal fun polygonPoints(sides: Int, star: Boolean): List<Offset> {
    val count = if (star) sides * 2 else sides
    return (0 until count).map { index ->
        val angle = (index * PI * 2) / count - PI / 2
        val radius = if (star && index % 2 == 1) 21.0 else 48.0
        Offset((50 + cos(angle) * radius).toFloat(), (50 + sin(angle) * radius).toFloat())
    }
}

private fun dashEffect(style: GridStrokeStyle?): PathEffect? = when (style) {
    GridStrokeStyle.Dashed -> PathEffect.dashPathEffect(floatArrayOf(6f, 4f))
    GridStrokeStyle.Dotted -> PathEffect.dashPathEffect(floatArrayOf(1f, 3f))
    else -> null
}

/** Shapes, icons and rectangles; SVG shapes are handled by [GridSvgShape]. Purely decorative for accessibility. */
@Composable
internal fun GridShapeContent(node: GridBuiltinNode, foreground: Color) {
    val fill = themeColor(node.color, foreground)
    val stroke = themeColor(node.strokeColor, foreground).withOpacity(node.strokeOpacity)
    val padding = (node.padding ?: 0).dp
    val decorative = Modifier.clearAndSetSemantics { }
    when (node.shape) {
        GridShape.Icon -> {
            val vector = remember(node.iconName) { GridIcons.vector(node.iconName) }
            Image(
                painter = rememberVectorPainter(vector),
                contentDescription = null,
                colorFilter = ColorFilter.tint(fill),
                contentScale = ContentScale.Fit,
                modifier = decorative.fillMaxSize().padding(padding).alpha((node.colorOpacity ?: 1.0).toFloat()),
            )
        }
        GridShape.Rectangle -> {
            val shape = RoundedCornerShape(node.radius.dp)
            val strokeWidth = (node.strokeWidth ?: 0).toFloat()
            Box(decorative.fillMaxSize().padding(padding)) {
                Box(
                    Modifier.fillMaxSize().clip(shape).background(fill.withOpacity(node.colorOpacity), shape)
                        .gridBorder(strokeWidth.dp, stroke, node.strokeStyle.toBorderStyle(), node.radius.dp),
                )
            }
        }
        else -> Canvas(decorative.fillMaxSize().padding(padding)) {
            drawGridShape(node, fill.withOpacity(node.colorOpacity), stroke)
        }
    }
}

/** Draws the SVG-viewBox shapes exactly like the web: 100×100 units, non-uniform scale except circles. */
private fun DrawScope.drawGridShape(node: GridBuiltinNode, fill: Color, stroke: Color) {
    val uniform = node.shape == GridShape.Circle
    val sx = size.width / 100f
    val sy = size.height / 100f
    val s = min(sx, sy)
    val strokeWidth = (node.strokeWidth ?: if (node.shape == GridShape.Line || node.shape == GridShape.Arrow) 2 else 0).toFloat()
    // Stroke widths are in viewBox units, so they scale with the shape like SVG strokes do.
    val path = Path()
    var filled = true
    when (node.shape) {
        GridShape.Ellipse, GridShape.Circle -> path.addOval(androidx.compose.ui.geometry.Rect(Offset(2f, 2f), Size(96f, 96f)))
        GridShape.Line -> { path.moveTo(2f, 50f); path.lineTo(98f, 50f) }
        GridShape.Arrow -> {
            path.moveTo(2f, 50f); path.lineTo(96f, 50f)
            path.moveTo(70f, 24f); path.lineTo(96f, 50f); path.lineTo(70f, 76f)
            filled = false
        }
        else -> {
            val sides = when (node.shape) {
                GridShape.Triangle -> 3
                GridShape.Pentagon -> 5
                GridShape.Hexagon -> 6
                GridShape.Heptagon -> 7
                GridShape.Octagon -> 8
                else -> node.polygonSides ?: 6
            }
            val star = node.shape == GridShape.Star
            val points = polygonPoints(if (star) 5 else sides, star)
            points.forEachIndexed { i, p -> if (i == 0) path.moveTo(p.x, p.y) else path.lineTo(p.x, p.y) }
            path.close()
        }
    }
    withTransform({
        if (uniform) {
            translate((size.width - 100f * s) / 2f, (size.height - 100f * s) / 2f)
            scale(s, s, Offset.Zero)
        } else scale(sx, sy, Offset.Zero)
    }) {
        if (filled && fill.alpha > 0f) drawPath(path, fill, style = Fill)
        if (strokeWidth > 0f && stroke.alpha > 0f) drawPath(
            path, stroke,
            style = Stroke(width = strokeWidth, cap = StrokeCap.Round, join = StrokeJoin.Round, pathEffect = dashEffect(node.strokeStyle)),
        )
    }
}

/** Spacer or a centered horizontal line spanning the frame or its middle 50%. */
@Composable
internal fun GridSeparatorContent(node: GridBuiltinNode, foreground: Color) {
    val style = node.separatorStyle ?: GridSeparatorStyle.Empty
    if (style == GridSeparatorStyle.Empty) return
    val color = themeColor(node.strokeColor, foreground).withOpacity(node.strokeOpacity)
    Box(Modifier.fillMaxSize().clearAndSetSemantics { }, contentAlignment = Alignment.Center) {
        Box(
            Modifier.fillMaxWidth(if (style == GridSeparatorStyle.Centered) 0.5f else 1f)
                .height((node.strokeWidth ?: 1).dp)
                .background(color),
        )
    }
}

internal fun GridStrokeStyle?.toBorderStyle(): com.nulldull.grid.GridBorderStyle = when (this) {
    GridStrokeStyle.Dashed -> com.nulldull.grid.GridBorderStyle.Dashed
    GridStrokeStyle.Dotted -> com.nulldull.grid.GridBorderStyle.Dotted
    else -> com.nulldull.grid.GridBorderStyle.Solid
}
