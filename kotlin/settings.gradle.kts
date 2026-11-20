pluginManagement {
    repositories {
        google()
        mavenCentral()
        gradlePluginPortal()
    }
}

dependencyResolutionManagement {
    repositoriesMode.set(RepositoriesMode.FAIL_ON_PROJECT_REPOS)
    repositories {
        google()
        mavenCentral()
    }
}

rootProject.name = "nulldull-kotlin"

// The SDK.
include(":sdk")
// Grid renderers: the document model and layout engine (JVM) and the Jetpack Compose renderer (Android).
include(":grid-core")
include(":grid-compose")
