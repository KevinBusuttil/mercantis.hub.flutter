import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Release signing. Nothing secret lives in this repository: the upload key is
// read from android/key.properties (git-ignored, for a maintainer's machine)
// or from ATLAS_ANDROID_* environment variables (the protected `release`
// environment in CI). See docs/release/RELEASE_SIGNING_AND_SECRETS.md.
//
// Without a key a release build is left UNSIGNED: it compiles (CI proves the
// release build on every change) but cannot be installed or uploaded. The
// debug key is never used for a release unless a developer opts in for a
// local device test with ATLAS_ANDROID_DEBUG_SIGN_RELEASE=true.
val keystoreProperties = Properties().apply {
    val file = rootProject.file("key.properties")
    if (file.exists()) file.inputStream().use { load(it) }
}

fun signingValue(property: String, environment: String): String? =
    (System.getenv(environment) ?: keystoreProperties.getProperty(property))
        ?.takeIf { it.isNotBlank() }

val releaseStoreFile = signingValue("storeFile", "ATLAS_ANDROID_KEYSTORE_PATH")
val releaseStorePassword =
    signingValue("storePassword", "ATLAS_ANDROID_KEYSTORE_PASSWORD")
val releaseKeyAlias = signingValue("keyAlias", "ATLAS_ANDROID_KEY_ALIAS")
val releaseKeyPassword = signingValue("keyPassword", "ATLAS_ANDROID_KEY_PASSWORD")
val hasReleaseSigning = listOf(
    releaseStoreFile, releaseStorePassword, releaseKeyAlias, releaseKeyPassword,
).all { it != null }
// Set by the signed release job: a missing key must fail the build, never
// fall back to an unsigned or debug-signed artifact.
val requireReleaseSigning = System.getenv("ATLAS_REQUIRE_RELEASE_SIGNING") == "true"
val debugSignRelease = System.getenv("ATLAS_ANDROID_DEBUG_SIGN_RELEASE") == "true"

if (requireReleaseSigning && !hasReleaseSigning) {
    throw GradleException(
        "ATLAS_REQUIRE_RELEASE_SIGNING is set but the upload key is incomplete. " +
            "Set ATLAS_ANDROID_KEYSTORE_PATH, ATLAS_ANDROID_KEYSTORE_PASSWORD, " +
            "ATLAS_ANDROID_KEY_ALIAS and ATLAS_ANDROID_KEY_PASSWORD.",
    )
}
if (requireReleaseSigning && debugSignRelease) {
    throw GradleException("A required-signing build cannot be debug-signed.")
}

android {
    // The permanent Android application id (product-owner decision,
    // October 2026). It must never change once a build is published.
    namespace = "com.neuradix.atlas"
    // Pinned to 36: file_picker pulls in flutter_plugin_android_lifecycle,
    // which requires consumers to compile against API 36+.
    compileSdk = 36
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "com.neuradix.atlas"
        // Flutter 3.44's floor, API 24 (Android 7.0). The supported minimum
        // is recorded in docs/release/PLATFORM_MATRIX.md.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (hasReleaseSigning) {
            create("release") {
                storeFile = file(releaseStoreFile!!)
                storePassword = releaseStorePassword
                keyAlias = releaseKeyAlias
                keyPassword = releaseKeyPassword
            }
        }
    }

    buildTypes {
        release {
            signingConfig = when {
                hasReleaseSigning -> signingConfigs.getByName("release")
                debugSignRelease -> signingConfigs.getByName("debug")
                else -> null
            }
            // R8 (release minify) needs keep rules for ML Kit's optional script
            // recognizers we don't bundle — see proguard-rules.pro.
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro",
            )
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}
