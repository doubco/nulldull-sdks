import com.vanniktech.maven.publish.JavadocJar
import com.vanniktech.maven.publish.KotlinJvm
import org.jetbrains.kotlin.gradle.dsl.JvmTarget

plugins {
    alias(libs.plugins.kotlin.jvm)
    alias(libs.plugins.kotlin.serialization)
    alias(libs.plugins.dokka)
    alias(libs.plugins.maven.publish)
}

// The Grid renderer artifacts have their own version (gradle.properties `gridVersion`).
version = providers.gradleProperty("gridVersion").get()

java {
    sourceCompatibility = JavaVersion.VERSION_17
    targetCompatibility = JavaVersion.VERSION_17
}

kotlin {
    explicitApi()
    compilerOptions { jvmTarget.set(JvmTarget.JVM_17) }
}

dependencies {
    api(libs.kotlinx.serialization.json)
    api(libs.kotlinx.coroutines.core)
    implementation(libs.icu4j)
    implementation(libs.jetbrains.markdown)
    testImplementation(libs.kotlin.test.junit)
    testImplementation(libs.junit4)
    testImplementation(libs.kotlinx.coroutines.test)
}

// Shared Grid renderer fixtures (also read by the Swift renderer's tests), read in place.
val fixtures = rootProject.layout.projectDirectory.dir("../fixtures/grid-renderer")
tasks.test {
    systemProperty("grid.fixtures", fixtures.asFile.absolutePath)
    inputs.dir(fixtures).withPropertyName("gridFixtures").withPathSensitivity(PathSensitivity.RELATIVE)
    testLogging { events("failed"); exceptionFormat = org.gradle.api.tasks.testing.logging.TestExceptionFormat.FULL }
}

dokka {
    moduleName.set("NullDull Grid core")
    dokkaSourceSets.configureEach {
        sourceLink {
            localDirectory.set(file("src/main/kotlin"))
            remoteUrl("https://github.com/doubco/nulldull-sdks/tree/main/kotlin/grid-core/src/main/kotlin")
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
    coordinates("com.nulldull", "nulldull-grid-core", project.version.toString())
    configure(KotlinJvm(javadocJar = JavadocJar.Dokka("dokkaGeneratePublicationHtml"), sourcesJar = true))
    pom {
        name.set("NullDull Grid core")
        description.set(
            "NullDull Grid document model, validation, layout engine and public content client " +
                "for the JVM and Android.",
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
