import org.jetbrains.kotlin.gradle.dsl.JvmTarget
plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
}

android {
    namespace = "io.trtc.tuikit.chat.demo"
    compileSdk = 35
    defaultConfig {
        applicationId = "io.trtc.tuikit.chat.demo"
        minSdk = 23
        targetSdk = 35
        versionCode = (findProperty("VERSION_CODE") as String?)?.toIntOrNull() ?: 1
        versionName = (findProperty("VERSION_NAME") as String?) ?: "0.1-baseline"
    }
    packaging {
        jniLibs {
            useLegacyPackaging = true
        }
    }
    buildTypes {
        // Debug: no obfuscation, arm64 devices plus x86_64 emulators.
        debug {
            isMinifyEnabled = false
            ndk {
                abiFilters += listOf("arm64-v8a", "x86_64")
            }
        }
        // Release: R8 minify + obfuscation, arm64 only.
        release {
            isMinifyEnabled = true
            proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-rules.pro")
            ndk {
                abiFilters += listOf("arm64-v8a")
            }
        }
    }
    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
}
kotlin { compilerOptions { jvmTarget.set(JvmTarget.JVM_17) } }
dependencies {
    implementation(project(":uikit"))
    implementation(project(":callkit"))
    implementation(project(":hostbase"))
    implementation(project(":homekit"))
    implementation(project(":minekit"))
    implementation(project(":atomic_x"))
    implementation("com.tencent.imsdk:imsdk-plus:9.1.7822")
    implementation("com.tencent:mmkv:2.4.0")
    implementation("com.google.code.gson:gson:2.10.1")
    implementation("androidx.appcompat:appcompat:1.6.1")
    implementation("androidx.core:core-ktx:1.12.0")
    implementation("androidx.core:core-splashscreen:1.0.1")
    implementation("androidx.lifecycle:lifecycle-runtime-ktx:2.6.2")
}
