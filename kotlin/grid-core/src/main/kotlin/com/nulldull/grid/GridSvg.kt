package com.nulldull.grid

/**
 * Port of `isSafeGridSvg`: only static, paint-only SVG drawing markup is previewed.
 * Anything else (scripts, external references, `<style>`, entities, oversized input)
 * stays download-only.
 */
public object GridSvg {
    private val STYLE_PROPERTIES = (
        "fill fill-opacity fill-rule stroke stroke-width stroke-linecap stroke-linejoin stroke-dasharray " +
            "stroke-dashoffset stroke-opacity stroke-miterlimit stop-color stop-opacity opacity display visibility clip-rule color"
        ).split(" ").toSet()
    private val TAGS = setOf(
        "svg", "g", "path", "rect", "circle", "ellipse", "line", "polyline", "polygon", "defs", "clipPath", "mask",
        "linearGradient", "radialGradient", "stop", "title", "desc",
    )
    private val ATTRIBUTES = (
        "xmlns xmlns:xlink version xml:space enable-background overflow style viewBox width height x y x1 x2 y1 y2 cx cy r rx ry " +
            "d points fill fill-rule fill-opacity stroke stroke-width stroke-linecap stroke-linejoin stroke-dasharray " +
            "stroke-dashoffset stroke-opacity opacity transform id clip-path mask gradientUnits gradientTransform offset " +
            "stop-color stop-opacity spreadMethod fx fy preserveAspectRatio"
        ).split(" ").toSet()
    private val FRAGMENT_URL = Regex("^url\\(#[A-Za-z][\\w-]*\\)$")
    private val COLOR_FUNCTION = Regex("\\b(?:rgba?|hsla?|color)\\(\\s*[-\\w\\s.,%/]*\\)", RegexOption.IGNORE_CASE)
    private val PLAIN = Regex("^[-#\\w\\s.,%]*$")
    private val XML_DECLARATION = Regex(
        "^<\\?xml\\s+version=[\"']1\\.0[\"'](?:\\s+encoding=[\"']UTF-8[\"'])?(?:\\s+standalone=[\"'](?:yes|no)[\"'])?\\s*\\?>",
        RegexOption.IGNORE_CASE,
    )
    private val FORBIDDEN = Regex("<!|<\\?|&|[\\u0000-\\u0008]")
    private val TAG = Regex("<(/?)([A-Za-z]+)\\b([^<>]*)>")
    private val ATTRIBUTE = Regex("\\s+([\\w:-]+)\\s*=\\s*([\"'])(.*?)\\2")
    private val ACTIVE_VALUE = Regex("[<>\\\\]|(?:https?:|data:|javascript:)", RegexOption.IGNORE_CASE)
    private val URL_CALL = Regex("url\\s*\\(", RegexOption.IGNORE_CASE)
    private val JS_WHITESPACE = Regex("^[\\s\\u00A0\\uFEFF]+|[\\s\\u00A0\\uFEFF]+$")

    private fun String.jsTrim() = replace(JS_WHITESPACE, "")

    private fun isStaticStyle(value: String): Boolean {
        val declarations = value.split(";")
        if (declarations.size > 64) return false
        for (declaration in declarations) {
            if (declaration.jsTrim().isEmpty()) continue
            val colon = declaration.indexOf(':')
            if (colon < 0 || declaration.substring(0, colon).jsTrim() !in STYLE_PROPERTIES) return false
            var css = declaration.substring(colon + 1).jsTrim()
            if (css.lowercase().endsWith("!important")) css = css.dropLast(10).jsTrim()
            if (FRAGMENT_URL.matches(css)) continue
            if (!PLAIN.matches(COLOR_FUNCTION.replace(css, ""))) return false
        }
        return true
    }

    public fun isSafe(input: String): Boolean {
        if (input.length > GridLimits.SVG_MAX_BYTES) return false
        var source = XML_DECLARATION.replaceFirst(input.jsTrim(), "")
        val pieces = StringBuilder()
        var commentCursor = 0
        var commentCount = 0
        while (true) {
            val start = source.indexOf("<!--", commentCursor)
            if (start < 0) break
            if (++commentCount > 10000) return false
            val end = source.indexOf("-->", start + 4)
            if (end < 0) return false
            pieces.append(source, commentCursor, start)
            commentCursor = end + 3
        }
        pieces.append(source, commentCursor, source.length)
        source = pieces.toString()
        if (source.isEmpty() || source.length > 10 * 1024 * 1024 || FORBIDDEN.containsMatchIn(source)) return false
        val stack = ArrayList<String>()
        var cursor = 0
        var roots = 0
        var tagCount = 0
        for (match in TAG.findAll(source)) {
            if (++tagCount > 10000 || stack.size > 64) return false
            val between = source.substring(cursor, match.range.first)
            if (between.any { it == '<' || it == '>' } || (stack.isEmpty() && between.jsTrim().isNotEmpty())) return false
            val close = match.groupValues[1]
            val tag = match.groupValues[2]
            val trimmed = match.groupValues[3].replace(Regex("[\\s\\u00A0\\uFEFF]+$"), "")
            val selfClosing = trimmed.endsWith("/")
            val attrs = if (selfClosing) trimmed.dropLast(1) else trimmed
            if (tag !in TAGS) return false
            if (close.isNotEmpty()) {
                if (attrs.jsTrim().isNotEmpty() || selfClosing || stack.removeLastOrNull() != tag) return false
            } else {
                if (stack.isEmpty() && (tag != "svg" || ++roots != 1)) return false
                var attributeEnd = 0
                var attributeCount = 0
                val names = HashSet<String>()
                while (attributeEnd < attrs.length && attrs.substring(attributeEnd).jsTrim().isNotEmpty()) {
                    val attr = ATTRIBUTE.matchAt(attrs, attributeEnd) ?: return false
                    val name = attr.groupValues[1]
                    val value = attr.groupValues[3]
                    if (++attributeCount > 64 || !names.add(name)) return false
                    attributeEnd = attr.range.last + 1
                    val bad = name !in ATTRIBUTES ||
                        (name == "xmlns" && value != "http://www.w3.org/2000/svg") ||
                        (name == "xmlns:xlink" && value != "http://www.w3.org/1999/xlink") ||
                        (name == "xml:space" && value !in setOf("default", "preserve")) ||
                        (name == "version" && value !in setOf("1.0", "1.1", "2.0")) ||
                        (name == "overflow" && value !in setOf("visible", "hidden", "auto", "scroll")) ||
                        (name == "style" && !isStaticStyle(value)) ||
                        ACTIVE_VALUE.containsMatchIn(if (name == "xmlns" || name == "xmlns:xlink") "" else value)
                    if (bad) return false
                    if (name != "style" && URL_CALL.containsMatchIn(value) && !FRAGMENT_URL.matches(value)) return false
                }
                if (attrs.substring(attributeEnd).jsTrim().isNotEmpty()) return false
                if (!selfClosing) stack.add(tag)
            }
            cursor = match.range.last + 1
        }
        return roots == 1 && stack.isEmpty() && source.substring(cursor).jsTrim().isEmpty()
    }
}
