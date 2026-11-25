package com.nulldull.grid

import kotlinx.serialization.Serializable

/** A document-local alias and optional anchor in a published Grid document. */
@Serializable
public data class GridPageLink(val version: Int, val entryId: String, val anchor: String? = null) {
    init {
        require(version == 1 && alias.matches(entryId) && (anchor == null || fragment.matches(anchor))) {
            "Invalid Grid page reference."
        }
    }

    public fun resolve(targets: Map<String, PublishedGridPageTarget>, resolver: GridPageLinkResolver?): String? {
        val target = targets[entryId]?.takeIf { it.published } ?: return null
        return GridUrl.safePageHref(resolver?.invoke(target, anchor))
    }

    public companion object {
        private val alias = Regex("~(?:[1-9]|[1-5][0-9]|6[0-4])")
        private val fragment = Regex("[a-zA-Z0-9._~-]{1,128}")
        private const val PREFIX = "grid-page:v1:"

        public fun parse(destination: String): GridPageLink? {
            if (!destination.startsWith(PREFIX)) return null
            val value = destination.substring(PREFIX.length)
            val id = value.substringBefore('#')
            val anchor = if ('#' in value) value.substringAfter('#') else null
            return if (alias.matches(id) && (anchor == null || fragment.matches(anchor))) GridPageLink(1, id, anchor) else null
        }
    }
}

/** Current readable publication from the page detail response. */
@Serializable
public data class PublishedGridPageTarget(
    val entryId: String,
    val published: Boolean,
    val pool: String,
    val slug: String,
    val locale: String,
)

public typealias GridPageLinkResolver = (target: PublishedGridPageTarget, anchor: String?) -> String?
