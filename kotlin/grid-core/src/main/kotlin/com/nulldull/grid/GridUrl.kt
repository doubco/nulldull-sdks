package com.nulldull.grid

import java.net.IDN

/**
 * URL safety rules shared with `@nulldull/grid-react/rendering`. Only credential-free
 * http(s) URLs are ever opened, loaded or embedded.
 */
public object GridUrl {
    // Explicit ASCII classes, as in the TypeScript and Swift rules: the meaning of `\w` and `\d` depends on
    // the regex engine (Android's is ICU-based and may treat them as Unicode classes), and a
    // percent-decoded `v=` value can contain non-ASCII letters and digits.
    private val YOUTUBE_ID = Regex("^[A-Za-z0-9_-]{11}$")
    private val YOUTUBE_PATH = Regex("^/(?:embed|shorts)/([A-Za-z0-9_-]+)$")
    private val VIMEO_PATH = Regex("^/[0-9]+$")

    /** `safeGridUrl`: the normalized href of a credential-free http(s) URL, else null. */
    public fun safe(value: String?): String? = value?.let(::normalizeHttp)

    /**
     * `resolveAsset` guard: a public http(s) URL, or a same-host absolute path
     * (`/…`, not `//…`, without backslashes or line breaks).
     */
    public fun safeAsset(value: String?): String? {
        if (value == null) return null
        if (value.startsWith("/") && !value.startsWith("//") && value.none { it == '\\' || it == '\r' || it == '\n' }) return value
        return safe(value)
    }

    /** `gridEmbedUrl`: privacy-enhanced YouTube or Vimeo player URL for an allowed video page, else null. */
    public fun embed(value: String?): String? {
        val href = safe(value) ?: return null
        val url = Parsed.of(href) ?: return null
        val id = when (url.host) {
            "youtu.be" -> url.path.drop(1)
            "youtube.com", "www.youtube.com" ->
                url.queryParameter("v")?.takeIf { it.isNotEmpty() } ?: YOUTUBE_PATH.find(url.path)?.groupValues?.get(1)
            else -> null
        }
        if (id != null && YOUTUBE_ID.matches(id)) return "https://www.youtube-nocookie.com/embed/$id"
        if ((url.host == "vimeo.com" || url.host == "www.vimeo.com") && VIMEO_PATH.matches(url.path))
            return "https://player.vimeo.com/video${url.path}"
        return null
    }

    /**
     * Normalizes an absolute http(s) URL like the WHATWG `URL.href` for the inputs Grid
     * stores (lowercase scheme and host, punycode, default port removed, `/` path,
     * dot segments resolved, unsafe characters percent-encoded). Returns null for other
     * schemes, missing hosts, or user info.
     */
    public fun normalizeHttp(input: String): String? {
        val value = input.trim { it <= ' ' }.filterNot { it == '\t' || it == '\n' || it == '\r' }
        val colon = value.indexOf(':')
        if (colon <= 0) return null
        val scheme = value.substring(0, colon).lowercase()
        if (scheme != "http" && scheme != "https") return null
        var rest = value.substring(colon + 1).replace('\\', '/')
        if (!rest.startsWith("//")) return null
        rest = rest.trimStart('/')
        val authorityEnd = rest.indexOfFirst { it == '/' || it == '?' || it == '#' }.let { if (it < 0) rest.length else it }
        val authority = rest.substring(0, authorityEnd)
        var tail = rest.substring(authorityEnd)
        if ('@' in authority) return null
        val (rawHost, port) = splitPort(authority) ?: return null
        val host = normalizeHost(rawHost) ?: return null
        val portPart = when {
            port == null -> ""
            (scheme == "http" && port == 80) || (scheme == "https" && port == 443) -> ""
            else -> ":$port"
        }
        val hashIndex = tail.indexOf('#')
        val fragment = if (hashIndex >= 0) tail.substring(hashIndex + 1) else null
        if (hashIndex >= 0) tail = tail.substring(0, hashIndex)
        val queryIndex = tail.indexOf('?')
        val query = if (queryIndex >= 0) tail.substring(queryIndex + 1) else null
        val path = removeDotSegments(if (queryIndex >= 0) tail.substring(0, queryIndex) else tail).ifEmpty { "/" }
        return buildString {
            append(scheme).append("://").append(host).append(portPart)
            append(encode(path, PATH_SET))
            if (query != null) append('?').append(encode(query, QUERY_SET))
            if (fragment != null) append('#').append(encode(fragment, FRAGMENT_SET))
        }
    }

    private fun splitPort(authority: String): Pair<String, Int?>? {
        if (authority.startsWith("[")) {
            val end = authority.indexOf(']')
            if (end < 0) return null
            val after = authority.substring(end + 1)
            if (after.isEmpty()) return authority.substring(0, end + 1) to null
            if (!after.startsWith(":")) return null
            return authority.substring(0, end + 1) to (parsePort(after.substring(1)) ?: return null)
        }
        val colon = authority.lastIndexOf(':')
        if (colon < 0) return authority to null
        val portText = authority.substring(colon + 1)
        if (portText.isEmpty()) return authority.substring(0, colon) to null
        val port = parsePort(portText) ?: return null
        return authority.substring(0, colon) to port
    }

    private fun parsePort(text: String): Int? =
        if (text.all { it.isDigit() } && text.length <= 5) text.toInt().takeIf { it <= 65535 } else null

    private fun normalizeHost(host: String): String? {
        if (host.isEmpty()) return null
        if (host.startsWith("[")) return host.lowercase()
        val decoded = try { java.net.URLDecoder.decode(host.replace("+", "%2B"), "UTF-8") } catch (_: IllegalArgumentException) { return null }
        if (decoded.any { it <= ' ' || it in "#%/:<>?@[\\]^|" }) return null
        return try { IDN.toASCII(decoded, IDN.ALLOW_UNASSIGNED).lowercase() } catch (_: IllegalArgumentException) { null }
            ?.takeIf { it.isNotEmpty() }
    }

    private fun removeDotSegments(path: String): String {
        if (path.isEmpty()) return path
        val out = ArrayDeque<String>()
        val segments = path.removePrefix("/").split('/')
        segments.forEachIndexed { index, raw ->
            val segment = raw.lowercase().let { if (it == "%2e") "." else if (it == ".%2e" || it == "%2e." || it == "%2e%2e") ".." else raw }
            val last = index == segments.lastIndex
            when (segment) {
                "." -> if (last) out.addLast("")
                ".." -> { out.removeLastOrNull(); if (last) out.addLast("") }
                else -> out.addLast(raw)
            }
        }
        return "/" + out.joinToString("/")
    }

    private const val FRAGMENT_SET = " \"<>`"
    private const val QUERY_SET = " \"#<>'"
    private const val PATH_SET = " \"#<>?`{}"

    private fun encode(value: String, set: String): String = buildString {
        for (byte in value.toByteArray(Charsets.UTF_8)) {
            val c = byte.toInt() and 0xff
            if (c < 0x21 || c > 0x7e || c.toChar() in set) append('%').append("%02X".format(c)) else append(c.toChar())
        }
    }

    internal class Parsed(val host: String, val path: String, val query: String?) {
        fun queryParameter(name: String): String? = query?.split('&')?.firstNotNullOfOrNull { pair ->
            val key = pair.substringBefore('=')
            if (decode(key) == name) decode(pair.substringAfter('=', "")) else null
        }

        companion object {
            fun of(href: String): Parsed? {
                val afterScheme = href.substringAfter("://", "").ifEmpty { return null }
                val end = afterScheme.indexOfFirst { it == '/' || it == '?' || it == '#' }.let { if (it < 0) afterScheme.length else it }
                val host = afterScheme.substring(0, end).substringBefore(':')
                var rest = afterScheme.substring(end).substringBefore('#')
                val query = if ('?' in rest) rest.substringAfter('?') else null
                rest = rest.substringBefore('?')
                return Parsed(host, rest.ifEmpty { "/" }, query)
            }

            private fun decode(value: String): String = try {
                java.net.URLDecoder.decode(value, "UTF-8")
            } catch (_: IllegalArgumentException) { value }
        }
    }
}
