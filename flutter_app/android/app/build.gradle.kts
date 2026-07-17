import java.io.FileInputStream
import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// --- Release signing (TASK-063) -------------------------------------------
//
// Signing material is never committed. It is sourced, in order of
// preference, from:
//   1. android/key.properties (gitignored) with keys:
//        storeFile, storePassword, keyAlias, keyPassword
//   2. Environment variables: KEYSTORE_PATH, KEYSTORE_PASSWORD, KEY_ALIAS,
//      KEY_PASSWORD (this is how CI supplies a decoded keystore — see
//      .github/workflows/flutter.yml).
// If neither source provides a complete set of values, the release build
// type falls back to the Flutter debug keystore and a build warning is
// printed, so `flutter build apk --release` / `flutter run --release` keep
// working for local development without any signing setup.
val keystorePropertiesFile = rootProject.file("key.properties")
val keystoreProperties = Properties()
val hasKeystorePropertiesFile = keystorePropertiesFile.exists()
if (hasKeystorePropertiesFile) {
    FileInputStream(keystorePropertiesFile).use { keystoreProperties.load(it) }
}

fun releaseSigningValue(propertiesKey: String, envVar: String): String? {
    if (hasKeystorePropertiesFile) {
        val value = keystoreProperties.getProperty(propertiesKey)
        if (!value.isNullOrBlank()) return value
    }
    return System.getenv(envVar)?.takeIf { it.isNotBlank() }
}

val releaseStoreFilePath = releaseSigningValue("storeFile", "KEYSTORE_PATH")
val releaseStorePassword = releaseSigningValue("storePassword", "KEYSTORE_PASSWORD")
val releaseKeyAlias = releaseSigningValue("keyAlias", "KEY_ALIAS")
val releaseKeyPassword = releaseSigningValue("keyPassword", "KEY_PASSWORD")

val hasReleaseSigningConfig = !releaseStoreFilePath.isNullOrBlank() &&
    !releaseStorePassword.isNullOrBlank() &&
    !releaseKeyAlias.isNullOrBlank() &&
    !releaseKeyPassword.isNullOrBlank()
// ----------------------------------------------------------------------------

android {
    namespace = "com.choreapp.chore_app"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "dev.ahzed11.choreapp"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (hasReleaseSigningConfig) {
            create("release") {
                storeFile = file(releaseStoreFilePath!!)
                storePassword = releaseStorePassword
                keyAlias = releaseKeyAlias
                keyPassword = releaseKeyPassword
            }
        }
    }

    buildTypes {
        release {
            signingConfig = if (hasReleaseSigningConfig) {
                signingConfigs.getByName("release")
            } else {
                logger.warn(
                    "WARNING: no release signing config found (android/key.properties or " +
                        "KEYSTORE_PATH/KEYSTORE_PASSWORD/KEY_ALIAS/KEY_PASSWORD env vars are " +
                        "missing or incomplete). Falling back to debug signing for the " +
                        "release build type — this APK is NOT suitable for distribution."
                )
                signingConfigs.getByName("debug")
            }
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
