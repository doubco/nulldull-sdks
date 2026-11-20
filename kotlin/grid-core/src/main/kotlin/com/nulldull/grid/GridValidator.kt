package com.nulldull.grid

import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive

/** A document or value that `validateGrid` would reject; [message] matches the TypeScript message. */
public class GridValidationException(message: String) : IllegalArgumentException(message)

/**
 * Port of `validateGrid` from `@nulldull/grid-core`. Checks run in the same order and
 * fail with the same messages. Unknown fields are ignored (dropped), exactly as the
 * TypeScript validator rebuilds documents from known fields only.
 */
public object GridValidator {
    private val ID = Regex("^[a-zA-Z0-9_-]{1,128}$")
    private val COLOR = Regex("^(transparent|#[a-fA-F0-9]{6})$")
    private const val MAX_SAFE_INTEGER = 9007199254740991.0

    public fun validate(value: JsonElement): GridDocument {
        val o = obj(value)
        val base = layout(o["layout"])
        val rawBreakpoints = o["breakpoints"]
        val rawNodes = o["nodes"]
        if (rawBreakpoints !is JsonArray || rawBreakpoints.size > 12 || rawNodes !is JsonArray || rawNodes.size > 200)
            fail("Use up to 12 breakpoints and 200 nodes.")
        val breakpoints = rawBreakpoints.map { v ->
            val b = obj(v)
            val l = layout(b)
            GridBreakpoint(
                layout = l,
                id = gridId(b["id"]),
                name = text(b["name"], 80, "Breakpoint name"),
                minWidth = integer(b["minWidth"], 1, 7680, "Breakpoint width"),
            )
        }
        if (breakpoints.map { it.id }.toSet().size != breakpoints.size ||
            breakpoints.map { it.minWidth }.toSet().size != breakpoints.size
        ) fail("Breakpoint IDs and widths must be unique.")
        val ids = breakpoints.map { it.id }.toSet()
        val nodes = rawNodes.map { node(it, ids) }
        if (nodes.map { it.id }.toSet().size != nodes.size) fail("Node IDs must be unique.")
        if ((listOf(base) + breakpoints.map { it.layout }).any { it.flowGap != null } &&
            nodes.any { it is GridBuiltinNode && it.kind == GridNodeKind.Text && it.ignoreFlow != true && it.fitToBox == true }
        ) fail("Content-sized text cannot also fit a fixed-height box.")
        var baseLayoutName: String? = null
        if (o.containsKey("baseLayoutName")) {
            val name = text(o["baseLayoutName"], 80, "Base layout name")
            if (name.isNotBlankJs()) baseLayoutName = name
        }
        var baseLayoutIndex: Int? = null
        if (o.containsKey("baseLayoutIndex"))
            baseLayoutIndex = minOf(integer(o["baseLayoutIndex"], 0, 12, "Base layout position"), breakpoints.size)
        val result = GridDocument(base, breakpoints, nodes, baseLayoutIndex, baseLayoutName)
        if (GridJson.encode(result).toString().toByteArray(Charsets.UTF_8).size > GridLimits.DOCUMENT_MAX_BYTES)
            fail("Grid content exceeds 180 KB.")
        return result
    }

    /** `gridLink`: empty string, or a credential-free http(s) URL normalized like `URL.href`. */
    public fun link(value: JsonElement?): String {
        if (value is JsonPrimitive && value.isString && value.content.isEmpty()) return ""
        val v = text(value, 2048, "URL")
        return GridUrl.normalizeHttp(v) ?: fail("Use an http or https URL.")
    }

    /** `gridId`: 1–128 letters, digits, `_` or `-`. */
    public fun gridId(value: JsonElement?): String {
        val s = (value as? JsonPrimitive)?.takeIf { it.isString }?.content
        return if (s != null && ID.matches(s)) s else fail("Invalid identifier.")
    }

    private fun fail(message: String): Nothing = throw GridValidationException(message)

    private fun obj(v: JsonElement?): JsonObject = v as? JsonObject ?: fail("Expected an object.")

    private fun numberOf(v: JsonElement?): Double? {
        if (v !is JsonPrimitive || v.isString || v is JsonNull) return null
        val d = v.content.toDoubleOrNull() ?: return null
        return if (d.isFinite()) d else null
    }

    private fun integer(v: JsonElement?, min: Int, max: Int, field: String): Int {
        val d = numberOf(v)
        if (d != null && d == Math.floor(d) && Math.abs(d) <= MAX_SAFE_INTEGER && d >= min && d <= max) return d.toInt()
        fail("$field must be between $min and $max.")
    }

    private fun number(v: JsonElement?, min: Double, max: Double): Double {
        val d = numberOf(v)
        if (d != null && d >= min && d <= max) return d
        fail("Invalid numeric option.")
    }

    private fun text(v: JsonElement?, max: Int, field: String): String {
        if (v is JsonPrimitive && v.isString && v.content.length <= max) return v.content
        fail("$field is too long or missing.")
    }

    private inline fun <reified E> choice(v: JsonElement?): E where E : Enum<E>, E : GridWireValue {
        val s = (v as? JsonPrimitive)?.takeIf { it.isString }?.content
        return s?.let { wireValueOf<E>(it) } ?: fail("Invalid option.")
    }

    private fun color(v: JsonElement?): String {
        val s = (v as? JsonPrimitive)?.takeIf { it.isString }?.content
        return if (s != null && COLOR.matches(s)) s else fail("Use a six-digit color or transparent.")
    }

    private fun boolean(v: JsonElement?): Boolean? =
        (v as? JsonPrimitive)?.takeIf { !it.isString && it !is JsonNull }?.content?.let {
            when (it) { "true" -> true; "false" -> false; else -> null }
        }

    private class Appearance(
        val backgroundImageId: String?, val backgroundImageCleared: Boolean, val backgroundFit: GridFit?,
        val padding: Int?, val colorOpacity: Double?, val backgroundOpacity: Double?,
    )

    private fun appearance(o: JsonObject): Appearance {
        var imageId: String? = null
        var cleared = false
        if (o.containsKey("backgroundImageId")) {
            if (o["backgroundImageId"] is JsonNull) cleared = true else imageId = gridId(o["backgroundImageId"])
        }
        val fit = if (o.containsKey("backgroundFit")) choice<GridFit>(o["backgroundFit"]) else null
        val padding = if (o.containsKey("padding")) integer(o["padding"], 0, 128, "Padding") else null
        val colorOpacity = if (o.containsKey("colorOpacity")) number(o["colorOpacity"], 0.0, 1.0) else null
        val backgroundOpacity = if (o.containsKey("backgroundOpacity")) number(o["backgroundOpacity"], 0.0, 1.0) else null
        return Appearance(imageId, cleared, fit, padding, colorOpacity, backgroundOpacity)
    }

    private fun layout(v: JsonElement?): GridLayout {
        val o = obj(v)
        if (o.containsKey("flowGap") && !(o["direction"].let { it is JsonPrimitive && it.isString && it.content == "vertical" }))
            fail("Content flow requires a vertical layout.")
        val flowGap = if (o.containsKey("flowGap")) integer(o["flowGap"], 0, 128, "Flow spacing") else null
        val a = appearance(o)
        val previewWidth = if (o.containsKey("previewWidth")) integer(o["previewWidth"], 240, 7680, "Preview width") else null
        val previewHeight = if (o.containsKey("previewHeight")) integer(o["previewHeight"], 240, 7680, "Preview height") else null
        val background = if (o.containsKey("background")) color(o["background"]) else null
        val color = if (o.containsKey("color")) color(o["color"]) else null
        val radius = if (o.containsKey("radius")) integer(o["radius"], 0, 256, "Radius") else null
        val direction = choice<GridDirection>(o["direction"])
        val columns = integer(o["columns"], 1, 64, "Columns")
        val rows = integer(o["rows"], 1, 64, "Rows")
        val cellSize = integer(o["cellSize"], 8, 256, "Cell size")
        val gap = integer(o["gap"], 0, 64, "Gap")
        val maxRows = if (o.containsKey("maxRows")) integer(o["maxRows"], 1, 512, "Row limit") else null
        val maxColumns = if (o.containsKey("maxColumns")) integer(o["maxColumns"], 1, 512, "Column limit") else null
        return GridLayout(
            direction, columns, rows, cellSize, gap, maxRows, maxColumns, flowGap, background, color, radius,
            previewWidth, previewHeight, a.backgroundImageId, a.backgroundImageCleared, a.backgroundFit, a.padding,
            a.backgroundOpacity, a.colorOpacity,
        )
    }

    private fun frame(v: JsonElement?): GridFrame {
        val o = obj(v)
        return GridFrame(
            x = integer(o["x"], 0, 511, "X"),
            y = integer(o["y"], 0, 511, "Y"),
            width = integer(o["width"], 1, 512, "Width"),
            height = integer(o["height"], 1, 512, "Height"),
        )
    }

    private fun node(v: JsonElement, breakpointIds: Set<String>): GridNode {
        val n = obj(v)
        val frames = obj(n["frames"])
        if (frames.keys.any { it !in breakpointIds }) fail("Unknown breakpoint frame.")
        val hidden = boolean(n["hidden"]) ?: fail("Invalid visibility.")
        if (n.containsKey("ignoreFlow") && boolean(n["ignoreFlow"]) == null) fail("Invalid stacking option.")
        val kind = n["kind"]
        if (kind is JsonPrimitive && kind.isString && kind.content == "custom") {
            val nodeKey = text(n["nodeKey"], 128, "Node key").trimJs()
            if (nodeKey.isEmpty()) fail("Enter a node key.")
            val rawProperties = n["properties"]
            if (rawProperties !is JsonArray || rawProperties.size > 64) fail("Use up to 64 custom properties.")
            val properties = rawProperties.map { value ->
                val pair = obj(value)
                val key = text(pair["key"], 128, "Property key").trimJs()
                if (key.isEmpty()) fail("Enter a property key.")
                GridProperty(key, text(pair["value"], 4000, "Property value"))
            }
            if (properties.map { it.key }.toSet().size != properties.size) fail("Property keys must be unique.")
            val ignoreFlow = if (n.containsKey("ignoreFlow")) boolean(n["ignoreFlow"]) else null
            val id = gridId(n["id"])
            val name = text(n["name"], GridLimits.NODE_NAME_LIMIT, "Node name")
            val frame = frame(n["frame"])
            val overrides = frames.mapValues { frame(it.value) }
            val opacity = n["opacity"].let { if (it == null || it is JsonNull) 0.5 else number(it, 0.0, 1.0) }
            return GridCustomNode(id, name, frame, overrides, hidden, opacity, nodeKey, properties, ignoreFlow)
        }
        // nodeOptions(n), in the TypeScript evaluation order.
        val a = appearance(n)
        val flags = listOf("dropcap", "fitToBox", "ignoreFlow").associateWith { key ->
            if (n.containsKey(key)) boolean(n[key]) ?: fail("Invalid text option.") else null
        }
        val opacities = listOf("opacity", "borderOpacity", "strokeOpacity").associateWith { key ->
            if (n.containsKey(key)) number(n[key], 0.0, 1.0) else null
        }
        val colors = listOf("borderColor", "strokeColor").associateWith { key -> if (n.containsKey(key)) color(n[key]) else null }
        val widths = listOf("borderWidth", "strokeWidth").associateWith { key ->
            if (n.containsKey(key)) integer(n[key], 0, 64, key) else null
        }
        val borderStyle = if (n.containsKey("borderStyle")) choice<GridBorderStyle>(n["borderStyle"]) else null
        val strokeStyle = if (n.containsKey("strokeStyle")) choice<GridStrokeStyle>(n["strokeStyle"]) else null
        val link = if (n.containsKey("link")) link(n["link"]) else null
        val url = if (n.containsKey("url")) link(n["url"]) else null
        val rotation = if (n.containsKey("rotation")) number(n["rotation"], -360.0, 360.0) else null
        val lineHeight = if (n.containsKey("lineHeight")) number(n["lineHeight"], 0.5, 4.0) else null
        var fontAssetId: String? = null
        var fontCleared = false
        if (n.containsKey("fontAssetId")) {
            if (n["fontAssetId"] is JsonNull) fontCleared = true else fontAssetId = gridId(n["fontAssetId"])
        }
        val fontFamily = if (n.containsKey("fontFamily")) choice<GridFontFamily>(n["fontFamily"]) else null
        val verticalAlign = if (n.containsKey("verticalAlign")) choice<GridVerticalAlign>(n["verticalAlign"]) else null
        val iconName = if (n.containsKey("iconName")) gridId(n["iconName"]) else null
        val polygonSides = if (n.containsKey("polygonSides")) integer(n["polygonSides"], 3, 12, "Polygon sides") else null
        val separatorStyle = if (kind is JsonPrimitive && kind.isString && kind.content == "separator") {
            val raw = n["separatorStyle"]
            if (raw == null || raw is JsonNull) GridSeparatorStyle.Empty else choice<GridSeparatorStyle>(raw)
        } else null
        val id = gridId(n["id"])
        val nodeKind = choice<GridNodeKind>(kind)
        val name = text(n["name"], GridLimits.NODE_NAME_LIMIT, "Node name")
        val body = text(n["text"], 16000, "Text")
        val assetId = if (n["assetId"] is JsonNull) null else gridId(n["assetId"])
        val frame = frame(n["frame"])
        val overrides = frames.mapValues { frame(it.value) }
        return GridBuiltinNode(
            id = id, kind = nodeKind, name = name, text = body, assetId = assetId, frame = frame, frames = overrides,
            color = color(n["color"]), background = color(n["background"]),
            fontSize = integer(n["fontSize"], 8, 256, "Font size"), radius = integer(n["radius"], 0, 256, "Radius"),
            align = choice(n["align"]), fit = choice(n["fit"]), shape = choice(n["shape"]), hidden = hidden,
            ignoreFlow = flags["ignoreFlow"], rotation = rotation, opacity = opacities["opacity"],
            borderOpacity = opacities["borderOpacity"], strokeOpacity = opacities["strokeOpacity"],
            borderColor = colors["borderColor"], borderWidth = widths["borderWidth"], borderStyle = borderStyle,
            lineHeight = lineHeight, fontAssetId = fontAssetId, fontAssetCleared = fontCleared, fontFamily = fontFamily,
            verticalAlign = verticalAlign, dropcap = flags["dropcap"], fitToBox = flags["fitToBox"], link = link, url = url,
            iconName = iconName, polygonSides = polygonSides, strokeColor = colors["strokeColor"],
            strokeWidth = widths["strokeWidth"], strokeStyle = strokeStyle, separatorStyle = separatorStyle,
            backgroundImageId = a.backgroundImageId, backgroundImageCleared = a.backgroundImageCleared,
            backgroundFit = a.backgroundFit, padding = a.padding, backgroundOpacity = a.backgroundOpacity,
            colorOpacity = a.colorOpacity,
        )
    }
}

/** JavaScript `String.prototype.trim` whitespace (includes NBSP, BOM and Unicode spaces). */
internal fun String.trimJs(): String = trim { it.isWhitespace() || it == '\u00A0' || it == '\uFEFF' }
internal fun String.isNotBlankJs(): Boolean = trimJs().isNotEmpty()
