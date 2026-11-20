package com.nulldull.grid.compose

import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.drawWithContent
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.PathEffect
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.drawscope.DrawScope
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.unit.Dp
import com.nulldull.grid.GridBorderStyle

/**
 * CSS-like border drawn inside the bounds, above the content. Solid, dashed, dotted and
 * double match the web closely; groove and ridge use solid lines (documented fallback).
 */
internal fun Modifier.gridBorder(width: Dp, color: Color, style: GridBorderStyle?, radius: Dp): Modifier =
    if (width.value <= 0f || color.alpha == 0f) this else drawWithContent {
        drawContent()
        val w = width.toPx()
        val r = radius.toPx()
        when (style ?: GridBorderStyle.Solid) {
            GridBorderStyle.Double -> {
                val line = w / 3f
                strokeRect(line, 0f, color, r, null, StrokeCap.Butt)
                strokeRect(line, w - line, color, r, null, StrokeCap.Butt)
            }
            GridBorderStyle.Dashed -> strokeRect(w, 0f, color, r, PathEffect.dashPathEffect(floatArrayOf(w * 3f, w * 3f)), StrokeCap.Butt)
            GridBorderStyle.Dotted -> strokeRect(w, 0f, color, r, PathEffect.dashPathEffect(floatArrayOf(0.01f, w * 2f)), StrokeCap.Round)
            else -> strokeRect(w, 0f, color, r, null, StrokeCap.Butt)
        }
    }

/** Strokes a rounded rectangle whose outer edge is inset by [inset]. */
private fun DrawScope.strokeRect(width: Float, inset: Float, color: Color, radius: Float, effect: PathEffect?, cap: StrokeCap) {
    val half = width / 2f + inset
    if (size.width <= half * 2 || size.height <= half * 2) return
    val corner = (radius - half).coerceAtLeast(0f)
    drawRoundRect(
        color = color,
        topLeft = Offset(half, half),
        size = Size(size.width - half * 2, size.height - half * 2),
        cornerRadius = CornerRadius(corner, corner),
        style = Stroke(width = width, pathEffect = effect, cap = cap),
    )
}
