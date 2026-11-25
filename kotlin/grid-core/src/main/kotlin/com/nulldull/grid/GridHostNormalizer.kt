package com.nulldull.grid

import java.lang.Character.*
import java.net.IDN
import java.text.Normalizer

/**
 * Converts a percent-decoded domain to canonical ASCII, or returns null to decline the link.
 * Platform renderer modules can supply a provider via [java.util.ServiceLoader]. The core-only
 * JVM default accepts Unicode only when IDNA 2003 preserves its lowercase, NFC spelling.
 */
public fun interface GridHostNormalizer {
    public fun toAscii(host: String): String?
}

internal object JdkGridHostNormalizer : GridHostNormalizer {
    override fun toAscii(host: String): String? {
        if (host.any { it == 'ß' || it == 'ς' || it == '\u200c' || it == '\u200d' || ignoredByUts46(it) }) return null
        // Without ALLOW_UNASSIGNED the JDK rejects code points outside its IDNA 2003 tables.
        val ascii = try {
            if (host.all { it.code < 128 }) host else IDN.toASCII(host, IDN.USE_STD3_ASCII_RULES)
        } catch (_: IllegalArgumentException) { return null }
        val labels = host.split('.')
        val encoded = ascii.split('.')
        if (labels.size != encoded.size) return null
        val unicode = labels.mapIndexed { index, label ->
            when {
                label.startsWith("xn--", ignoreCase = true) -> decodeAceLabel(label.lowercase()) ?: return null
                label.all { it.code < 128 } -> label
                else -> {
                    val decoded = IDN.toUnicode(encoded[index], IDN.USE_STD3_ASCII_RULES)
                    if (decoded != Normalizer.normalize(label.lowercase(), Normalizer.Form.NFC) || startsWithMark(decoded)) return null
                    decoded
                }
            }
        }
        if (unicode.any { label -> label.codePoints().anyMatch { getDirectionality(it) in bidiTriggers } } &&
            !unicode.all(::validBidiLabel)) return null
        return ascii.lowercase()
    }

    // These Hangul fillers and Khmer signs survive IDNA 2003 round trips, but UTS 46 drops them.
    private fun ignoredByUts46(c: Char): Boolean = c in '\u115f'..'\u1160' || c in '\u17b4'..'\u17b5'

    private fun startsWithMark(text: String): Boolean = text.isNotEmpty() &&
        getType(text.codePointAt(0)) in setOf(NON_SPACING_MARK.toInt(), COMBINING_SPACING_MARK.toInt(), ENCLOSING_MARK.toInt())

    private val bidiTriggers = setOf(DIRECTIONALITY_RIGHT_TO_LEFT, DIRECTIONALITY_RIGHT_TO_LEFT_ARABIC, DIRECTIONALITY_ARABIC_NUMBER)
    private val bidiNeutral = setOf(DIRECTIONALITY_EUROPEAN_NUMBER_SEPARATOR, DIRECTIONALITY_EUROPEAN_NUMBER_TERMINATOR,
        DIRECTIONALITY_COMMON_NUMBER_SEPARATOR, DIRECTIONALITY_OTHER_NEUTRALS, DIRECTIONALITY_BOUNDARY_NEUTRAL, DIRECTIONALITY_NONSPACING_MARK)
    private val rtlEnds = bidiTriggers + DIRECTIONALITY_EUROPEAN_NUMBER
    private val ltrEnds = setOf(DIRECTIONALITY_LEFT_TO_RIGHT, DIRECTIONALITY_EUROPEAN_NUMBER)

    // RFC 5893 applies to every label of a domain containing R, AL or AN.
    private fun validBidiLabel(label: String): Boolean {
        if (label.isEmpty()) return true
        val directions = label.codePoints().toArray().map { getDirectionality(it) }
        val ends = when (directions.first()) {
            DIRECTIONALITY_LEFT_TO_RIGHT -> ltrEnds
            DIRECTIONALITY_RIGHT_TO_LEFT, DIRECTIONALITY_RIGHT_TO_LEFT_ARABIC -> rtlEnds
            else -> return false
        }
        return directions.last { it != DIRECTIONALITY_NONSPACING_MARK } in ends &&
            directions.all { it in ends || it in bidiNeutral } &&
            !(DIRECTIONALITY_EUROPEAN_NUMBER in directions && DIRECTIONALITY_ARABIC_NUMBER in directions)
    }

    // IDN.toUnicode silently returns its input for both broken ACE and valid nontransitional ACE
    // (including xn--fa-hia). Check RFC 3492 syntax directly; never use the decoded label as a URL.
    private fun decodeAceLabel(label: String): String? {
        val payload = label.substring(4)
        val delimiter = payload.lastIndexOf('-')
        if (payload.isEmpty() || delimiter == 0 || delimiter == payload.lastIndex || payload.any { it.code >= 128 }) return null
        val points = payload.take(delimiter.coerceAtLeast(0)).map { it.code }.toMutableList()
        var cursor = delimiter + 1
        var n = 128L
        var index = 0L
        var bias = 72L
        while (cursor < payload.length) {
            val previous = index
            var weight = 1L
            var k = 36L
            while (true) {
                if (cursor == payload.length) return null
                val c = payload[cursor++]
                val digit = when (c) {
                    in 'a'..'z' -> c - 'a'
                    in '0'..'9' -> c - '0' + 26
                    else -> return null
                }
                index += digit * weight
                if (index > Int.MAX_VALUE) return null
                val threshold = (k - bias).coerceIn(1, 26)
                if (digit < threshold) break
                weight *= 36 - threshold
                if (weight > Int.MAX_VALUE) return null
                k += 36
            }
            val size = points.size + 1
            var delta = (index - previous) / (if (previous == 0L) 700 else 2)
            delta += delta / size
            bias = 0
            while (delta > 455) {
                delta /= 35
                bias += 36
            }
            bias += 36 * delta / (delta + 38)
            n += index / size
            if (n > MAX_CODE_POINT || n in 0xd800..0xdfff || n == 0xfffdL) return null
            when (getType(n.toInt())) {
                CONTROL.toInt(), PRIVATE_USE.toInt() -> return null
                FORMAT.toInt() -> if (n != 0x200cL && n != 0x200dL) return null
            }
            index %= size
            points.add(index.toInt(), n.toInt())
            index++
        }
        val decoded = String(points.toIntArray(), 0, points.size)
        return decoded.takeIf {
            !startsWithMark(it) && it.none(::ignoredByUts46) && Normalizer.isNormalized(it, Normalizer.Form.NFC)
        }
    }
}
