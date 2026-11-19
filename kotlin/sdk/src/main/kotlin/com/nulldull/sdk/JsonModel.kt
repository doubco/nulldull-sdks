package com.nulldull.sdk

import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.booleanOrNull
import kotlinx.serialization.json.longOrNull

/**
 * Base class of every response model: a typed view over the API's JSON object.
 *
 * [json] is the object exactly as the API sent it (field names unchanged, unknown fields kept), except
 * that Grid asset URLs are already resolved by [GridApi.assetUrl]. Typed properties read from it, so
 * new API fields never break decoding: read them from [json] until the SDK adds a property.
 *
 * Enum-like values (kinds, statuses) are plain strings so unknown values pass through. Missing
 * required fields read as an empty string, `0`, `false` or an empty list instead of throwing.
 *
 * Two models are equal when they are the same type with equal [json].
 */
public abstract class JsonModel(public val json: JsonObject) {
    override fun equals(other: Any?): Boolean =
        other is JsonModel && other.javaClass == javaClass && other.json == json

    override fun hashCode(): Int = json.hashCode()

    override fun toString(): String = "${javaClass.simpleName}($json)"
}

internal fun JsonObject.stringOrNull(name: String): String? =
    (this[name] as? JsonPrimitive)?.takeIf { it.isString }?.content

internal fun JsonObject.string(name: String): String = stringOrNull(name) ?: ""

internal fun JsonObject.longOrNull(name: String): Long? =
    (this[name] as? JsonPrimitive)?.takeIf { !it.isString }?.let { it.longOrNull ?: it.content.toDoubleOrNull()?.toLong() }

internal fun JsonObject.long(name: String): Long = longOrNull(name) ?: 0L

internal fun JsonObject.intOrNull(name: String): Int? = longOrNull(name)?.toInt()

internal fun JsonObject.int(name: String): Int = intOrNull(name) ?: 0

internal fun JsonObject.boolean(name: String): Boolean =
    (this[name] as? JsonPrimitive)?.takeIf { !it.isString }?.booleanOrNull ?: false

internal fun JsonObject.objectOrNull(name: String): JsonObject? = this[name] as? JsonObject

internal fun <T> JsonObject.model(name: String, factory: (JsonObject) -> T): T? = objectOrNull(name)?.let(factory)

internal fun <T> JsonObject.models(name: String, factory: (JsonObject) -> T): List<T> =
    (this[name] as? JsonArray)?.mapNotNull { (it as? JsonObject)?.let(factory) } ?: emptyList()

internal fun JsonObject.strings(name: String): List<String> =
    (this[name] as? JsonArray)?.mapNotNull { (it as? JsonPrimitive)?.takeIf { p -> p.isString }?.content } ?: emptyList()

/** Thrown by response decoders; the transport turns it into `INVALID_RESPONSE`. */
internal class ShapeException(message: String) : RuntimeException(message)

internal fun JsonElement.asObject(what: String): JsonObject =
    this as? JsonObject ?: throw ShapeException("Expected $what to be a JSON object.")

/** Decodes `{items: [...], nextCursor}` strictly: items must be an array of objects. */
internal fun <T> JsonObject.pageItems(factory: (JsonObject) -> T): List<T> {
    val items = this["items"] as? JsonArray ?: throw ShapeException("Expected an items array.")
    return items.map { factory(it.asObject("each item")) }
}
