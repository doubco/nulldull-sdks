import com.vanniktech.maven.publish.AndroidSingleVariantLibrary
import org.jetbrains.kotlin.gradle.dsl.JvmTarget

plugins {
    alias(libs.plugins.android.library)
    alias(libs.plugins.kotlin.android)
    alias(libs.plugins.kotlin.compose)
    alias(libs.plugins.roborazzi)
    alias(libs.plugins.maven.publish)
}

// The Grid renderer artifacts have their own version (gradle.properties `gridVersion`).
version = providers.gradleProperty("gridVersion").get()

// Shared Grid renderer fixtures (also read by the Swift renderer's tests), read in place.
val fixtures = rootProject.layout.projectDirectory.dir("../fixtures/grid-renderer")

android {
    namespace = "com.nulldull.grid.compose"
    compileSdk = 36
    defaultConfig {
        minSdk = 24
        consumerProguardFiles("consumer-rules.pro")
    }
    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
    buildFeatures { compose = true }
    testOptions {
        unitTests {
            isIncludeAndroidResources = true
            all {
                it.systemProperty("grid.fixtures", fixtures.asFile.absolutePath)
                it.inputs.dir(fixtures).withPropertyName("gridFixtures").withPathSensitivity(PathSensitivity.RELATIVE)
                it.systemProperty("grid.shots", providers.gradleProperty("gridShots").orNull ?: "")
                it.maxHeapSize = "3g"
            }
        }
    }
    lint {
        abortOnError = true
        // KTX suggestions would add androidx.core only for String.toUri().
        disable += "UseKtx"
    }
}

kotlin {
    explicitApi()
    compilerOptions { jvmTarget.set(JvmTarget.JVM_17) }
}

/** Generates Kotlin icon data from the shared catalog rendered out of the canonical React icons. */
abstract class GenerateGridIcons : DefaultTask() {
    @get:InputFile
    @get:PathSensitive(PathSensitivity.RELATIVE)
    abstract val catalog: RegularFileProperty

    @get:OutputDirectory
    abstract val outputDir: DirectoryProperty

    @TaskAction
    fun generate() {
        @Suppress("UNCHECKED_CAST")
        val root = groovy.json.JsonSlurper().parse(catalog.get().asFile) as Map<String, Any?>
        @Suppress("UNCHECKED_CAST")
        val icons = root["icons"] as Map<String, Map<String, Any?>>
        fun q(s: String) = "\"" + s.replace("\\", "\\\\").replace("\"", "\\\"").replace("$", "\\$") + "\""
        val body = StringBuilder()
        body.append("// Generated from fixtures/grid-renderer/icons/grid-icons.json. Do not edit.\n")
        body.append("package com.nulldull.grid.compose\n\n")
        body.append("internal val gridIconData: Map<String, GridIconSpec> = mapOf(\n")
        for ((name, icon) in icons.toSortedMap()) {
            @Suppress("UNCHECKED_CAST")
            val box = icon["viewBox"] as Map<String, Number>
            @Suppress("UNCHECKED_CAST")
            val paths = icon["paths"] as List<Map<String, Any?>>
            body.append("    ${q(name)} to GridIconSpec(${box["width"]}f, ${box["height"]}f, listOf(\n")
            for (p in paths) {
                body.append("        GridIconPath(${q(p["d"] as String)}, fill = ${p["fill"] != "none"}, stroke = ${p["stroke"] != "none"}, ")
                body.append("strokeWidth = ${(p["strokeWidth"] as Number).toFloat()}f, cap = ${q(p["strokeLinecap"] as String)}, ")
                body.append("join = ${q(p["strokeLinejoin"] as String)}, evenOdd = ${p["fillRule"] == "evenodd"}),\n")
            }
            body.append("    )),\n")
        }
        body.append(")\n")
        val out = outputDir.get().asFile.resolve("com/nulldull/grid/compose/GridIconData.kt")
        out.parentFile.mkdirs()
        out.writeText(body.toString())
    }
}

val generateGridIcons = tasks.register<GenerateGridIcons>("generateGridIcons") {
    catalog.set(fixtures.file("icons/grid-icons.json"))
    outputDir.set(layout.buildDirectory.dir("generated/gridIcons"))
}

androidComponents {
    onVariants { variant ->
        // Kotlin compilation reads generated Kotlin from the java source set under AGP 8.
        variant.sources.java?.addGeneratedSourceDirectory(generateGridIcons, GenerateGridIcons::outputDir)
    }
}

dependencies {
    api(project(":grid-core"))
    api(platform(libs.compose.bom))
    api(libs.compose.ui)
    api(libs.compose.foundation)
    implementation(libs.coil.compose)
    implementation(libs.coil.svg)

    testImplementation(libs.junit4)
    testImplementation(libs.kotlin.test.junit)
    testImplementation(libs.robolectric)
    testImplementation(libs.roborazzi)
    testImplementation(libs.roborazzi.compose)
    testImplementation(libs.androidx.test.core)
    testImplementation(platform(libs.compose.bom))
    testImplementation(libs.compose.ui.test.junit4)
    testImplementation(libs.compose.ui.test.manifest)
}

// AGP's bundled Dokka cannot read the core module's sealed interfaces (ASM9), so the javadoc jar
// Maven Central requires is a placeholder carrying the README; the KDoc lives in the sources jar.
val emptyJavadocJar = tasks.register<Jar>("emptyJavadocJar") {
    archiveClassifier.set("javadoc")
    from(rootProject.layout.projectDirectory.file("README.md"))
}

val hasSigningKey = providers.gradleProperty("signingInMemoryKey").isPresent ||
    providers.gradleProperty("signing.keyId").isPresent

mavenPublishing {
    publishToMavenCentral()
    // Local builds and publishToMavenLocal work without keys; CI provides them for releases.
    if (hasSigningKey) signAllPublications()
    coordinates("com.nulldull", "nulldull-grid-compose", project.version.toString())
    configure(AndroidSingleVariantLibrary(variant = "release", sourcesJar = true, publishJavadocJar = false))
    pom {
        name.set("NullDull Grid for Jetpack Compose")
        description.set("Jetpack Compose renderer for published NullDull Grid pages.")
        inceptionYear.set("2026")
        url.set("https://github.com/doubco/nulldull-sdks")
        licenses {
            license {
                name.set("MIT License")
                url.set("https://opensource.org/licenses/MIT")
                distribution.set("repo")
            }
        }
        developers {
            developer {
                id.set("nulldull")
                name.set("NullDull")
                url.set("https://nulldull.com")
            }
        }
        scm {
            url.set("https://github.com/doubco/nulldull-sdks")
            connection.set("scm:git:https://github.com/doubco/nulldull-sdks.git")
            developerConnection.set("scm:git:ssh://git@github.com/doubco/nulldull-sdks.git")
        }
        issueManagement {
            system.set("GitHub")
            url.set("https://github.com/doubco/nulldull-sdks/issues")
        }
    }
}

publishing {
    publications.withType<MavenPublication>().configureEach { artifact(emptyJavadocJar) }
}
