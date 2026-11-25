package com.nulldull.grid

import com.nulldull.grid.client.PublicGridPage
import java.lang.invoke.MethodType
import java.lang.reflect.Modifier
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue

class GridModelAbiTest {
    @Test fun releasedCopyOverloadsRetainPageLinkData() {
        val page = GridJson.format.decodeFromString<PublicGridPage>(Fixtures.text("../grid/page-links.json"))
        val tile = page.document.nodes[1] as GridBuiltinNode
        assertEquals(page.copy(title = "Edited"), page.copyV020(title = "Edited"))
        assertEquals(tile.copy(text = "Edited", padding = 22), tile.copyV020(text = "Edited", padding = 22))
    }

    /** Public JVM descriptors from javap -public -s on the Grid 0.2.0 release artifact. */
    @Test fun releasedModelEntryPointsStillLink() {
        val dump = checkNotNull(javaClass.getResource("/grid-models-0.2.0.api")).readText()
        for (block in dump.trim().split("\n\n")) {
            val lines = block.lines()
            val type = Class.forName(lines.first())
            fun prefix(modifiers: Int) = if (Modifier.isStatic(modifiers)) "static " else ""
            val members = buildSet {
                for (field in type.fields) add(prefix(field.modifiers) + field.name + " " + field.type.descriptorString())
                for (ctor in type.constructors) {
                    add("<init> " + MethodType.methodType(Void.TYPE, ctor.parameterTypes).toMethodDescriptorString())
                }
                for (method in type.methods) {
                    val signature = MethodType.methodType(method.returnType, method.parameterTypes).toMethodDescriptorString()
                    add(prefix(method.modifiers) + method.name + " " + signature)
                }
            }
            for (signature in lines.drop(1)) {
                assertTrue(signature in members, "Missing Grid 0.2.0 entry point on ${type.name}: $signature")
            }
        }
    }
}
