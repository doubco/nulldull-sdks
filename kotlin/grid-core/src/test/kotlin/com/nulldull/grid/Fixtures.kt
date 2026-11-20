package com.nulldull.grid

import kotlinx.serialization.json.JsonElement
import java.io.File

/** Shared Grid renderer fixtures generated from the TypeScript packages (fixtures/grid-renderer). */
object Fixtures {
    val root: File = File(
        System.getProperty("grid.fixtures") ?: error("Run through Gradle so grid.fixtures is set."),
    )

    fun text(path: String): String = File(root, path).readText()
    fun json(path: String): JsonElement = GridJson.parse(text(path))
    fun documents(): Map<String, File> =
        File(root, "documents").listFiles()!!.filter { it.extension == "json" }.associateBy { it.nameWithoutExtension }.toSortedMap()

    /** `stubTextHeight` from src/reference-layout.mjs, in the same IEEE-754 order. */
    fun stubTextHeight(node: GridBuiltinNode, width: Double): Double {
        val pad = (node.padding ?: 8).toDouble()
        val inner = maxOf(1.0, width - 2 * pad)
        val perLine = maxOf(1.0, Math.floor(inner / (node.fontSize * 0.5)))
        val lines = maxOf(1.0, Math.ceil(node.text.length / perLine))
        return 2 * pad + lines * (node.fontSize * (node.lineHeight ?: 1.2))
    }
}
