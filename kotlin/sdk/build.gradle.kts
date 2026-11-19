import com.vanniktech.maven.publish.JavadocJar
import com.vanniktech.maven.publish.KotlinJvm
import org.jetbrains.kotlin.gradle.dsl.JvmTarget

plugins {
    alias(libs.plugins.kotlin.jvm)
    alias(libs.plugins.dokka)
    alias(libs.plugins.maven.publish)
}

kotlin {
    explicitApi()
    // Builds with any JDK 17+ and emits Java 11 bytecode against the Java 11 API (-Xjdk-release), so
    // Android apps (minSdk 24) and any JVM 11+ can consume the library.
    compilerOptions {
        jvmTarget.set(JvmTarget.JVM_11)
        freeCompilerArgs.add("-Xjdk-release=11")
    }
}

tasks.withType<JavaCompile>().configureEach {
    options.release.set(11)
}

dependencies {
    api(libs.okhttp)
    api(libs.kotlinx.serialization.json)
    api(libs.kotlinx.coroutines.core)

    testImplementation(platform(libs.junit.bom))
    testImplementation(libs.junit.jupiter)
    testImplementation(libs.okhttp.mockwebserver)
    testImplementation(libs.kotlinx.coroutines.test)
    testRuntimeOnly(libs.junit.platform.launcher)
}

tasks.test {
    useJUnitPlatform()
    // Shared conformance fixtures live next to the other SDKs and are read in place.
    systemProperty("nulldull.version", project.version.toString())
    systemProperty("nulldull.fixtures", rootProject.layout.projectDirectory.dir("../fixtures").asFile.absolutePath)
    inputs.dir(rootProject.layout.projectDirectory.dir("../fixtures")).withPathSensitivity(PathSensitivity.RELATIVE)
    // Live tests read these; declare whether each is set (never its value) so setting them re-runs the tests.
    listOf(
        "NULLDULL_PUBLIC_KEY", "NULLDULL_GRID_POOL", "NULLDULL_PRIVATE_KEY", "NULLDULL_WORKSPACE_ID",
        "NULLDULL_LOCALE_SCOPE_ID", "NULLDULL_BASE_URL",
    ).forEach { name -> inputs.property(name, providers.environmentVariable(name).map { "set" }.orElse("unset")) }
    testLogging {
        events("skipped", "failed")
        exceptionFormat = org.gradle.api.tasks.testing.logging.TestExceptionFormat.FULL
    }
}

dokka {
    moduleName.set("NullDull Kotlin SDK")
    dokkaSourceSets.configureEach {
        includes.from("Module.md")
        sourceLink {
            localDirectory.set(file("src/main/kotlin"))
            remoteUrl("https://github.com/doubco/nulldull-sdks/tree/main/kotlin/sdk/src/main/kotlin")
            remoteLineSuffix.set("#L")
        }
    }
}

val hasSigningKey = providers.gradleProperty("signingInMemoryKey").isPresent ||
    providers.gradleProperty("signing.keyId").isPresent

mavenPublishing {
    publishToMavenCentral()
    // Local builds and publishToMavenLocal work without keys; CI provides them for releases.
    if (hasSigningKey) signAllPublications()
    coordinates("com.nulldull", "nulldull-sdk", project.version.toString())
    configure(KotlinJvm(javadocJar = JavadocJar.Dokka("dokkaGeneratePublicationHtml"), sourcesJar = true))
    pom {
        name.set("NullDull SDK")
        description.set(
            "Official NullDull SDK for Kotlin and Android: Grid published content, read-only Memory " +
                "and Locale export with workspace API keys.",
        )
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
