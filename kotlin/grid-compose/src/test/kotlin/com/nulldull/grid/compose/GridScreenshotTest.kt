package com.nulldull.grid.compose

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.text.BasicText
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onRoot
import androidx.compose.ui.unit.dp
import com.github.takahirom.roborazzi.captureRoboImage
import org.junit.Assume.assumeTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.ParameterizedRobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode
import java.io.File

/**
 * JVM rendering of fixture pages for visual comparison with the React renderer.
 * Run `./gradlew :grid-compose:recordRoborazziDebug -PgridShots=<dir>`; skipped otherwise.
 */
@RunWith(ParameterizedRobolectricTestRunner::class)
@GraphicsMode(GraphicsMode.Mode.NATIVE)
@Config(sdk = [35], qualifiers = "xhdpi")
class GridScreenshotTest(private val fixture: String, private val width: Int) {
    @get:Rule val compose = createComposeRule()

    @Test
    fun capture() {
        val out = System.getProperty("grid.shots").orEmpty()
        assumeTrue("Pass -PgridShots=<dir> to record screenshots.", out.isNotEmpty())
        RuntimeEnvironment.setQualifiers("w${width}dp-h3200dp")
        val document = fixture(fixture)
        compose.setContent {
            Box(Modifier.background(Color.White)) {
                GridRenderer(
                    document = document,
                    width = width.dp,
                    theme = GridTheme(foreground = Color(0xFF111111)),
                    customNodes = mapOf(
                        "callout" to { node ->
                            BasicText(node.property("text") ?: "", Modifier.background(Color(0xFFFFF3C4)).padding(8.dp))
                        },
                    ),
                )
            }
        }
        compose.onRoot().captureRoboImage(File(out, "kotlin-$fixture-$width.png").path)
    }

    companion object {
        @JvmStatic
        @ParameterizedRobolectricTestRunner.Parameters(name = "{0}@{1}")
        fun cases(): List<Array<Any>> = listOf(
            "kitchen-sink", "markdown-rich", "void-welcome-to-the-void", "all-shapes", "flow-padded", "horizontal", "showcase-fixed",
        ).flatMap { name -> listOf(390, 834).map { arrayOf<Any>(name, it) } }
    }
}
