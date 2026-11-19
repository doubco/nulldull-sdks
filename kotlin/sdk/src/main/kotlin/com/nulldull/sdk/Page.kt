package com.nulldull.sdk

import kotlinx.serialization.json.JsonObject

/**
 * One page of a list endpoint: `{items, nextCursor, ...}`.
 *
 * Pass [nextCursor] back as `after` to get the next page, or use the matching `iterate…` method to get
 * a [kotlinx.coroutines.flow.Flow] of items across pages. Cursors are opaque: never parse or build
 * them. An empty page with a non-null [nextCursor] is not the end (Grid search scans a bounded window).
 */
public open class Page<out T>(json: JsonObject, public val items: List<T>) : JsonModel(json) {
    /** Cursor for the next page, or null on the last page. */
    public val nextCursor: String? get() = json.stringOrNull("nextCursor")

    internal companion object {
        fun <T> decode(json: JsonObject, factory: (JsonObject) -> T): Page<T> = Page(json, json.pageItems(factory))
    }
}
