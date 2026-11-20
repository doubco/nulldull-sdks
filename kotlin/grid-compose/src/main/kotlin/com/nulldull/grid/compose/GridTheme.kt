package com.nulldull.grid.compose

import androidx.compose.runtime.Immutable
import androidx.compose.runtime.staticCompositionLocalOf
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.unit.Density
import androidx.compose.ui.unit.TextUnit
import androidx.compose.ui.unit.sp
import com.nulldull.grid.GridFontFamily
import com.nulldull.grid.client.GridHttpEngine
import com.nulldull.grid.client.UrlConnectionGridHttpEngine

/**
 * Host theme for colors a document leaves `transparent`, and the font families behind
 * Grid's named families. Authored colors never change with the theme.
 *
 * [foreground] defaults to black in light mode and white in dark mode (the web renderer
 * inherits the host text color); pass your design system's colors for an exact match.
 */
@Immutable
public data class GridTheme(
    val foreground: Color = Color.Unspecified,
    val background: Color = Color.Transparent,
    val sans: FontFamily = FontFamily.SansSerif,
    val serif: FontFamily = FontFamily.Serif,
    val mono: FontFamily = FontFamily.Monospace,
    val system: FontFamily = FontFamily.Default,
    /** Android has no system rounded face; supply one to match `ui-rounded` on Apple platforms. */
    val rounded: FontFamily = FontFamily.Default,
) {
    internal fun family(family: GridFontFamily?): FontFamily = when (family ?: GridFontFamily.Sans) {
        GridFontFamily.System -> system
        GridFontFamily.Rounded -> rounded
        GridFontFamily.Sans -> sans
        GridFontFamily.Serif -> serif
        GridFontFamily.Mono -> mono
    }
}

/** Visible fallback strings; localize them in the host application. */
@Immutable
public data class GridMessages(
    val unavailable: String = "Preview unavailable.",
    val download: String = "Download original",
    val chooseAsset: String = "No asset selected",
    val play: String = "Play",
    val pause: String = "Pause",
)

/** How the system font size setting applies to authored text. */
public enum class GridFontScaling {
    /**
     * Default. Content-flow text, which is sized by its content, follows the system font
     * scale; text in fixed-height frames keeps its authored size so layouts do not clip.
     */
    FlowOnly,
    /** Authored sizes everywhere, like the web renderer at 100% zoom. */
    Never,
    /** Scale all text; fixed frames may clip enlarged text. */
    Always,
}

/** Rendering options that are not part of the document. */
@Immutable
public data class GridRenderOptions(
    val fontScaling: GridFontScaling = GridFontScaling.FlowOnly,
    /** Transport for images, SVG, fonts and media metadata. Never follows redirects or sends cookies. */
    val engine: GridHttpEngine = DefaultEngine,
    /** Width used before the container is measured (the web renderer's `initialWidth`). */
    val initialWidthDp: Float = 768f,
) {
    internal companion object {
        val DefaultEngine: GridHttpEngine = UrlConnectionGridHttpEngine()
    }
}

internal val LocalGridOptions = staticCompositionLocalOf { GridRenderOptions() }

/** Parses validated `#rrggbb`; `transparent` and absent values fall back. */
internal fun themeColor(value: String?, fallback: Color): Color {
    if (value == null || value == "transparent" || value.length != 7) return fallback
    return Color(0xFF000000 or value.substring(1).toLong(16))
}

/** Independent per-color opacity, like `color-mix(in srgb, color p%, transparent)`. */
internal fun Color.withOpacity(opacity: Double?): Color =
    if (opacity == null || opacity == 1.0) this else copy(alpha = alpha * opacity.toFloat())

/** Converts authored CSS pixels to a text size, applying the system font scale only when [scaled]. */
internal fun Density.gridTextUnit(px: Double, scaled: Boolean): TextUnit =
    if (scaled) px.toFloat().sp else (px.toFloat() / fontScale).sp
