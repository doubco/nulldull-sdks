package com.nulldull.grid

import java.util.ServiceLoader

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

    /** Customer routes accept single-slash paths or credential-free HTTP(S), without whitespace or backslashes. */
    public fun safePageHref(value: String?): String? {
        if (value.isNullOrEmpty() || value.any { it == '\\' || it.isWhitespace() || it == '\uFEFF' }) return null
        if (value.startsWith('/')) return value.takeUnless { it.startsWith("//") }
        val scheme = value.substringBefore(':').lowercase()
        if (scheme != "http" && scheme != "https" || ':' !in value) return null
        val rest = value.substringAfter(':').trimStart('/')
        val authority = rest.takeWhile { it !in "/?#" }
        val host = authority.substringAfterLast('@')
        if ('@' in authority && authority.substringBeforeLast('@') !in listOf("", ":")) return null
        val href = normalizeHttp("$scheme://$host" + rest.substring(authority.length), pageRoute = true) ?: return null
        if (host.startsWith('[')) return href
        val domain = href.substringAfter("://").takeWhile { it !in ":/?#" }
        val labels = domain.removeSuffix(".").split('.')
        val last = labels.last()
        if (!(last.isNotEmpty() && last.all { it in '0'..'9' }) && !hexNumber.matches(last)) return href
        val canonical = ipv4(labels) ?: return null
        return "$scheme://$canonical" + href.substringAfter("://").substring(domain.length)
    }

    private val hexNumber = Regex("0x[0-9a-f]*")

    /** WHATWG IPv4 permits one to four decimal, octal or hexadecimal parts. */
    private fun ipv4(labels: List<String>): String? {
        if (labels.size > 4) return null
        var address = 0L
        for ((index, label) in labels.withIndex()) {
            if (label.isEmpty()) return null
            val radix = when {
                label.startsWith("0x") -> 16
                label.length > 1 && label.startsWith('0') -> 8
                else -> 10
            }
            val digits = (if (radix == 16) label.drop(2) else label).trimStart('0')
            if (digits.any { it !in "0123456789abcdef".take(radix) }) return null
            val number = if (digits.isEmpty()) 0L else digits.toLongOrNull(radix) ?: return null
            val last = index == labels.lastIndex
            val bits = if (last) 8 * (4 - index) else 8
            if (number >= (1L shl bits)) return null
            address += if (last) number else number shl (8 * (3 - index))
        }
        return listOf(24, 16, 8, 0).joinToString(".") { ((address shr it) and 255L).toString() }
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
    public fun normalizeHttp(input: String): String? = normalizeHttp(input, pageRoute = false)

    /** A declined internationalized node link is empty so its document can still render. */
    internal fun documentLink(input: String): String? = normalizeHttp(input, pageRoute = false, inertIdn = true)

    private fun normalizeHttp(input: String, pageRoute: Boolean, inertIdn: Boolean = false): String? {
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
        val (rawHost, port) = splitPort(authority, pageRoute) ?: return null
        val host = normalizeHost(rawHost, inertIdn) ?: return null
        if (host.isEmpty()) return ""
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

    private fun splitPort(authority: String, pageRoute: Boolean): Pair<String, Int?>? {
        if (authority.startsWith("[")) {
            val end = authority.indexOf(']')
            if (end < 0) return null
            val after = authority.substring(end + 1)
            if (after.isEmpty() || after == ":") return authority.substring(0, end + 1) to null
            if (!after.startsWith(":")) return null
            return authority.substring(0, end + 1) to (parsePort(after.substring(1), pageRoute) ?: return null)
        }
        val colon = authority.lastIndexOf(':')
        if (colon < 0) return authority to null
        val portText = authority.substring(colon + 1)
        if (portText.isEmpty()) return authority.substring(0, colon) to null
        val port = parsePort(portText, pageRoute) ?: return null
        return authority.substring(0, colon) to port
    }

    private fun parsePort(text: String, pageRoute: Boolean): Int? {
        if (pageRoute && text.any { it !in '0'..'9' }) return null
        val digits = if (pageRoute) text.trimStart('0').ifEmpty { "0" } else text
        return digits.takeIf { it.length <= 5 && it.all(Char::isDigit) }?.toIntOrNull()?.takeIf { it <= 65535 }
    }

    // Resolve the renderer's provider before document decoding as well as before rendering.
    private val hostNormalizer: GridHostNormalizer by lazy {
        ServiceLoader.load(GridHostNormalizer::class.java, GridHostNormalizer::class.java.classLoader)
            .firstOrNull() ?: JdkGridHostNormalizer
    }

    private fun normalizeHost(raw: String, inertIdn: Boolean): String? {
        if (raw.startsWith("[")) {
            if ('%' in raw || runCatching { java.net.URI("http://$raw/").host }.getOrNull() == null) return null
            return raw.lowercase()
        }
        val host = try {
            java.net.URLDecoder.decode(raw.replace("+", "%2B"), "UTF-8")
        } catch (_: IllegalArgumentException) { return null }
        if (host.isEmpty() || host.any(::forbiddenHostChar)) return null
        val ace = host.split('.').filter { it.startsWith("xn--", ignoreCase = true) }
        if (ace.isEmpty() && host.all { it.code < 128 }) return host.lowercase()

        // A trailing Punycode delimiter encodes only basic characters, never an international label.
        if (ace.any { it.endsWith('-') }) return if (inertIdn) "" else null
        val ascii = hostNormalizer.toAscii(host) ?: return if (inertIdn) "" else null
        return ascii.takeIf { it.isNotEmpty() && it.all { c -> c.code < 128 && !forbiddenHostChar(c) } }
    }

    private fun forbiddenHostChar(c: Char): Boolean = c <= ' ' || c == '\u007F' || c in "#%/:<>?@[\\]^|"

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
