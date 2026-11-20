package com.nulldull.grid

import kotlinx.serialization.Serializable

/** Zero-based cell rectangle as stored in a Grid document. */
@Serializable
public data class GridFrame(val x: Int, val y: Int, val width: Int, val height: Int)

/** A Grid enum value together with its exact JSON spelling. */
public interface GridWireValue {
    public val wire: String
}

internal inline fun <reified E> wireValueOf(value: String): E? where E : Enum<E>, E : GridWireValue =
    enumValues<E>().firstOrNull { it.wire == value }

public enum class GridDirection(override val wire: String) : GridWireValue { Vertical("vertical"), Horizontal("horizontal") }
public enum class GridFit(override val wire: String) : GridWireValue { Cover("cover"), Contain("contain"), Tile("tile") }
public enum class GridAlign(override val wire: String) : GridWireValue { Left("left"), Center("center"), Right("right"), Justify("justify") }
public enum class GridVerticalAlign(override val wire: String) : GridWireValue { Top("top"), Middle("middle"), Bottom("bottom") }
public enum class GridFontFamily(override val wire: String) : GridWireValue {
    System("system"), Rounded("rounded"), Sans("sans"), Serif("serif"), Mono("mono")
}
public enum class GridBorderStyle(override val wire: String) : GridWireValue {
    Solid("solid"), Dashed("dashed"), Dotted("dotted"), Double("double"), Groove("groove"), Ridge("ridge")
}
public enum class GridStrokeStyle(override val wire: String) : GridWireValue { Solid("solid"), Dashed("dashed"), Dotted("dotted") }
public enum class GridSeparatorStyle(override val wire: String) : GridWireValue { Empty("empty"), Full("full"), Centered("centered") }
public enum class GridNodeKind(override val wire: String) : GridWireValue {
    Text("text"), Image("image"), Video("video"), Audio("audio"), Shape("shape"), Embed("embed"), Separator("separator")
}
public enum class GridShape(override val wire: String) : GridWireValue {
    Rectangle("rectangle"), Ellipse("ellipse"), Circle("circle"), Triangle("triangle"), Pentagon("pentagon"),
    Hexagon("hexagon"), Heptagon("heptagon"), Octagon("octagon"), Polygon("polygon"), Star("star"),
    Line("line"), Arrow("arrow"), Icon("icon"), Svg("svg"),
}

/**
 * Optional background and foreground settings shared by layouts and built-in nodes.
 * Absent opacities mean 1. `transparent` colors follow the renderer theme.
 */
public interface GridAppearance {
    public val backgroundImageId: String?
    public val backgroundFit: GridFit?
    public val padding: Int?
    public val backgroundOpacity: Double?
    public val colorOpacity: Double?
}

/** Base layout or the layout half of a breakpoint. */
public data class GridLayout(
    val direction: GridDirection,
    val columns: Int,
    val rows: Int,
    val cellSize: Int,
    val gap: Int,
    val maxRows: Int? = null,
    val maxColumns: Int? = null,
    /** Content-flow spacing in pixels; only valid for vertical layouts. */
    val flowGap: Int? = null,
    val background: String? = null,
    val color: String? = null,
    val radius: Int? = null,
    /** Editor viewport metadata; never constrains rendering. */
    val previewWidth: Int? = null,
    val previewHeight: Int? = null,
    override val backgroundImageId: String? = null,
    /** True when the document stored an explicit `backgroundImageId: null`. */
    val backgroundImageCleared: Boolean = false,
    override val backgroundFit: GridFit? = null,
    override val padding: Int? = null,
    override val backgroundOpacity: Double? = null,
    override val colorOpacity: Double? = null,
) : GridAppearance

public data class GridBreakpoint(
    val id: String,
    val name: String,
    /** Activation threshold in pixels: the widest breakpoint whose minWidth fits the viewport wins. */
    val minWidth: Int,
    val layout: GridLayout,
)

/** Common placement data of every node kind. */
public sealed interface GridNode {
    public val id: String
    public val name: String
    public val frame: GridFrame
    /** Per-breakpoint frame overrides keyed by breakpoint id. */
    public val frames: Map<String, GridFrame>
    public val hidden: Boolean
    public val ignoreFlow: Boolean?
    public val opacity: Double?
}

/** Every built-in node kind shares one record, as in the TypeScript contract. */
public data class GridBuiltinNode(
    override val id: String,
    val kind: GridNodeKind,
    override val name: String,
    val text: String,
    val assetId: String?,
    override val frame: GridFrame,
    override val frames: Map<String, GridFrame>,
    val color: String,
    val background: String,
    val fontSize: Int,
    val radius: Int,
    val align: GridAlign,
    val fit: GridFit,
    val shape: GridShape,
    override val hidden: Boolean,
    override val ignoreFlow: Boolean? = null,
    val rotation: Double? = null,
    override val opacity: Double? = null,
    val borderOpacity: Double? = null,
    val strokeOpacity: Double? = null,
    val borderColor: String? = null,
    val borderWidth: Int? = null,
    val borderStyle: GridBorderStyle? = null,
    val lineHeight: Double? = null,
    val fontAssetId: String? = null,
    val fontAssetCleared: Boolean = false,
    val fontFamily: GridFontFamily? = null,
    val verticalAlign: GridVerticalAlign? = null,
    val dropcap: Boolean? = null,
    val fitToBox: Boolean? = null,
    val link: String? = null,
    val url: String? = null,
    val iconName: String? = null,
    val polygonSides: Int? = null,
    val strokeColor: String? = null,
    val strokeWidth: Int? = null,
    val strokeStyle: GridStrokeStyle? = null,
    val separatorStyle: GridSeparatorStyle? = null,
    override val backgroundImageId: String? = null,
    val backgroundImageCleared: Boolean = false,
    override val backgroundFit: GridFit? = null,
    override val padding: Int? = null,
    override val backgroundOpacity: Double? = null,
    override val colorOpacity: Double? = null,
) : GridNode, GridAppearance

/** One inert string pair of a custom node. Values are data, never markup or code. */
@Serializable
public data class GridProperty(val key: String, val value: String)

/** Host-rendered node. Only components the application registers for [nodeKey] run. */
public data class GridCustomNode(
    override val id: String,
    override val name: String,
    override val frame: GridFrame,
    override val frames: Map<String, GridFrame>,
    override val hidden: Boolean,
    override val opacity: Double,
    val nodeKey: String,
    val properties: List<GridProperty>,
    override val ignoreFlow: Boolean? = null,
) : GridNode {
    /** Value of the first property with [key], or null. */
    public fun property(key: String): String? = properties.firstOrNull { it.key == key }?.value
}

/** A validated Grid document. Obtain one through [GridDocument.decode] or [GridValidator.validate]. */
@Serializable(with = GridDocumentSerializer::class)
public data class GridDocument(
    val layout: GridLayout,
    val breakpoints: List<GridBreakpoint>,
    val nodes: List<GridNode>,
    /** Display position of Base among breakpoints; presentation only. */
    val baseLayoutIndex: Int? = null,
    val baseLayoutName: String? = null,
) {
    public companion object {
        /** Decode and validate JSON text with the same rules as `validateGrid`. */
        public fun decode(json: String): GridDocument = GridValidator.validate(GridJson.parse(json))
    }

    /** Layout ids in display order, with "base" inserted at [baseLayoutIndex]. */
    public fun layoutOrder(): List<String> {
        val ids = breakpoints.map { it.id }.toMutableList()
        ids.add(minOf(baseLayoutIndex ?: 0, ids.size), "base")
        return ids
    }

    /** Asset ids this document references, as `gridAssetReferences` reports them. */
    public fun assetReferences(): List<GridAssetReference> = buildList {
        (listOf(layout) + breakpoints.map { it.layout }).forEach { l ->
            l.backgroundImageId?.let { add(GridAssetReference(it, GridAssetUse.Image)) }
        }
        nodes.filterIsInstance<GridBuiltinNode>().forEach { n ->
            n.fontAssetId?.let { add(GridAssetReference(it, GridAssetUse.Font)) }
            n.backgroundImageId?.let { add(GridAssetReference(it, GridAssetUse.Image)) }
            n.assetId?.let {
                val use = when (n.kind) {
                    GridNodeKind.Audio -> GridAssetUse.Audio
                    GridNodeKind.Video -> GridAssetUse.Video
                    else -> GridAssetUse.Image
                }
                add(GridAssetReference(it, use))
            }
        }
    }
}

public enum class GridAssetUse { Image, Video, Audio, Font }
public data class GridAssetReference(val id: String, val use: GridAssetUse)

/** Limits shared with the TypeScript contract. */
public object GridLimits {
    public const val MAX_FONTS: Int = 8
    public const val FONT_MAX_BYTES: Int = 2 * 1024 * 1024
    public const val SVG_MAX_BYTES: Int = 1024 * 1024
    public const val NODE_NAME_LIMIT: Int = 160
    public const val DOCUMENT_MAX_BYTES: Int = 180_000
    /** Default text line height when a node omits `lineHeight`. */
    public const val DEFAULT_LINE_HEIGHT: Double = 1.2
    /** Default text padding in pixels when a text node omits `padding`. */
    public const val DEFAULT_TEXT_PADDING: Int = 8
}
