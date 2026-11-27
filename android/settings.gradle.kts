pluginManagement {
    repositories {
        google()
        maven("https://mirrors.tencent.com/nexus/repository/maven-public/")
        mavenCentral()
        gradlePluginPortal()
    }
    plugins {
        id("com.android.application") version "8.7.0"
        id("com.android.library") version "8.7.0"
        id("org.jetbrains.kotlin.android") version "2.1.10"
    }
}
dependencyResolutionManagement {
    repositoriesMode.set(RepositoriesMode.PREFER_SETTINGS)
    repositories {
        google()
        maven("https://mirrors.tencent.com/nexus/repository/maven-public/")
        maven("https://mirrors.tencent.com/repository/maven/liteavsdk")
        mavenCentral()
    }
}
rootProject.name = "Social-Dating"
include(":app", ":uikit", ":callkit", ":hostbase", ":homekit", ":minekit", ":atomic_x")
