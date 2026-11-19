plugins {
    alias(libs.plugins.kotlin.jvm) apply false
    alias(libs.plugins.maven.publish) apply false
}

allprojects {
    group = "com.nulldull"
    version = providers.gradleProperty("sdkVersion").get()
}
