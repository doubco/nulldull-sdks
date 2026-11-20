package com.nulldull.grid

import kotlinx.serialization.KSerializer
import kotlinx.serialization.descriptors.SerialDescriptor
import kotlinx.serialization.encoding.Decoder
import kotlinx.serialization.encoding.Encoder
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonDecoder
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonEncoder
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonObjectBuilder
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.buildJsonArray
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put

/** JSON helpers. Encoding writes the same fields, in the same order, as `validateGrid` output. */
public object GridJson {
    /** Lenient reader for API responses: unknown future fields are ignored. */
    public val format: Json = Json {
        ignoreUnknownKeys = true
        explicitNulls = false
        isLenient = false
    }

    public fun parse(text: String): JsonElement = format.parseToJsonElement(text)

    public fun encode(document: GridDocument): JsonObject = buildJsonObject {
        put("layout", layout(document.layout))
        put("breakpoints", buildJsonArray {
            document.breakpoints.forEach { b ->
                add(JsonObject(layout(b.layout) + mapOf(
                    "id" to JsonPrimitive(b.id), "name" to JsonPrimitive(b.name), "minWidth" to JsonPrimitive(b.minWidth),
                )))
            }
        })
        put("nodes", buildJsonArray { document.nodes.forEach { add(node(it)) } })
        document.baseLayoutName?.let { put("baseLayoutName", it) }
        document.baseLayoutIndex?.let { put("baseLayoutIndex", it) }
    }

    public fun encodeToString(document: GridDocument): String = encode(document).toString()

    /** JavaScript prints whole doubles without a fraction; keep byte sizes comparable. */
    private fun num(value: Double): JsonPrimitive =
        if (value == Math.floor(value) && Math.abs(value) < 1e15) JsonPrimitive(value.toLong()) else JsonPrimitive(value)

    private fun frame(f: GridFrame) = buildJsonObject {
        put("x", f.x); put("y", f.y); put("width", f.width); put("height", f.height)
    }

    private fun JsonObjectBuilder.appearance(
        imageId: String?, cleared: Boolean, fit: GridFit?, padding: Int?, colorOpacity: Double?, backgroundOpacity: Double?,
    ) {
        if (imageId != null) put("backgroundImageId", imageId) else if (cleared) put("backgroundImageId", JsonNull)
        fit?.let { put("backgroundFit", it.wire) }
        padding?.let { put("padding", it) }
        colorOpacity?.let { put("colorOpacity", num(it)) }
        backgroundOpacity?.let { put("backgroundOpacity", num(it)) }
    }

    private fun layout(l: GridLayout) = buildJsonObject {
        l.flowGap?.let { put("flowGap", it) }
        appearance(l.backgroundImageId, l.backgroundImageCleared, l.backgroundFit, l.padding, l.colorOpacity, l.backgroundOpacity)
        l.previewWidth?.let { put("previewWidth", it) }
        l.previewHeight?.let { put("previewHeight", it) }
        l.background?.let { put("background", it) }
        l.color?.let { put("color", it) }
        l.radius?.let { put("radius", it) }
        put("direction", l.direction.wire)
        put("columns", l.columns); put("rows", l.rows); put("cellSize", l.cellSize); put("gap", l.gap)
        l.maxRows?.let { put("maxRows", it) }
        l.maxColumns?.let { put("maxColumns", it) }
    }

    private fun node(n: GridNode): JsonObject = when (n) {
        is GridCustomNode -> buildJsonObject {
            n.ignoreFlow?.let { put("ignoreFlow", it) }
            put("id", n.id); put("kind", "custom"); put("name", n.name)
            put("frame", frame(n.frame))
            put("frames", JsonObject(n.frames.mapValues { frame(it.value) }))
            put("hidden", n.hidden); put("opacity", num(n.opacity)); put("nodeKey", n.nodeKey)
            put("properties", JsonArray(n.properties.map { buildJsonObject { put("key", it.key); put("value", it.value) } }))
        }
        is GridBuiltinNode -> buildJsonObject {
            appearance(n.backgroundImageId, n.backgroundImageCleared, n.backgroundFit, n.padding, n.colorOpacity, n.backgroundOpacity)
            n.dropcap?.let { put("dropcap", it) }
            n.fitToBox?.let { put("fitToBox", it) }
            n.ignoreFlow?.let { put("ignoreFlow", it) }
            n.opacity?.let { put("opacity", num(it)) }
            n.borderOpacity?.let { put("borderOpacity", num(it)) }
            n.strokeOpacity?.let { put("strokeOpacity", num(it)) }
            n.borderColor?.let { put("borderColor", it) }
            n.strokeColor?.let { put("strokeColor", it) }
            n.borderWidth?.let { put("borderWidth", it) }
            n.strokeWidth?.let { put("strokeWidth", it) }
            n.borderStyle?.let { put("borderStyle", it.wire) }
            n.strokeStyle?.let { put("strokeStyle", it.wire) }
            n.link?.let { put("link", it) }
            n.url?.let { put("url", it) }
            n.rotation?.let { put("rotation", num(it)) }
            n.lineHeight?.let { put("lineHeight", num(it)) }
            if (n.fontAssetId != null) put("fontAssetId", n.fontAssetId) else if (n.fontAssetCleared) put("fontAssetId", JsonNull)
            n.fontFamily?.let { put("fontFamily", it.wire) }
            n.verticalAlign?.let { put("verticalAlign", it.wire) }
            n.iconName?.let { put("iconName", it) }
            n.polygonSides?.let { put("polygonSides", it) }
            n.separatorStyle?.let { put("separatorStyle", it.wire) }
            put("id", n.id); put("kind", n.kind.wire); put("name", n.name); put("text", n.text)
            put("assetId", n.assetId?.let(::JsonPrimitive) ?: JsonNull)
            put("frame", frame(n.frame))
            put("frames", JsonObject(n.frames.mapValues { frame(it.value) }))
            put("color", n.color); put("background", n.background); put("fontSize", n.fontSize); put("radius", n.radius)
            put("align", n.align.wire); put("fit", n.fit.wire); put("shape", n.shape.wire); put("hidden", n.hidden)
        }
    }
}

/** kotlinx.serialization bridge: decoding always runs the full validator. */
public object GridDocumentSerializer : KSerializer<GridDocument> {
    override val descriptor: SerialDescriptor = JsonElement.serializer().descriptor

    override fun deserialize(decoder: Decoder): GridDocument {
        val input = decoder as? JsonDecoder ?: error("GridDocument can only be decoded from JSON.")
        return GridValidator.validate(input.decodeJsonElement())
    }

    override fun serialize(encoder: Encoder, value: GridDocument) {
        val output = encoder as? JsonEncoder ?: error("GridDocument can only be encoded to JSON.")
        output.encodeJsonElement(GridJson.encode(value))
    }
}
