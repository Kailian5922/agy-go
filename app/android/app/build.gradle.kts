import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Optional PRoot Linux rootfs bundles built by runtime/build-rootfs.sh.
val runtimeOut = rootProject.file("../../runtime/out")

val keyProps = Properties().apply {
    val file = rootProject.file("key.properties")
    if (file.isFile) file.inputStream().use(::load)
}

val releaseStorePath: String? =
    System.getenv("AGY_KEYSTORE_PATH")?.takeIf { it.isNotBlank() }
        ?: keyProps.getProperty("storeFile")?.takeIf { it.isNotBlank() }
val releaseStorePassword: String? =
    System.getenv("AGY_KEYSTORE_PASSWORD")?.takeIf { it.isNotBlank() }
        ?: keyProps.getProperty("storePassword")?.takeIf { it.isNotBlank() }
val releaseKeyAlias: String? =
    System.getenv("AGY_KEY_ALIAS")?.takeIf { it.isNotBlank() }
        ?: keyProps.getProperty("keyAlias")?.takeIf { it.isNotBlank() }
val releaseKeyPassword: String? =
    System.getenv("AGY_KEY_PASSWORD")?.takeIf { it.isNotBlank() }
        ?: keyProps.getProperty("keyPassword")?.takeIf { it.isNotBlank() }
val hasReleaseSigning: Boolean =
    releaseStorePath != null &&
        File(releaseStorePath).isFile &&
        releaseStorePassword != null &&
        releaseKeyAlias != null &&
        releaseKeyPassword != null

android {
    namespace = "io.github.kailian5922.agy_go"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // Permanently fixed Android package ID so every build upgrades cleanly in-place.
        applicationId = "io.github.kailian5922.agy_go"
        // java.nio.file & modern Android crypto/network APIs require API 26+.
        minSdk = 26
        // Deliberately target API 28 (same strategy as Termux / dsh-Go) so Android 10+
        // W^X restrictions do not block exec() on binaries unpacked in app-private filesDir.
        targetSdk = 28
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    sourceSets {
        getByName("main") {
            val arm64Assets = File(runtimeOut, "arm64-v8a/assets")
            val arm64Jni = File(runtimeOut, "arm64-v8a/jniLibs")
            if (arm64Assets.exists()) assets.srcDir(arm64Assets)
            if (arm64Jni.exists()) jniLibs.srcDir(arm64Jni)
        }
    }

    packaging {
        jniLibs {
            // Required so optional libproot.so / libtalloc.so extract to nativeLibraryDir.
            useLegacyPackaging = true
        }
    }

    lint {
        // targetSdk 28 is deliberate for sideloaded on-device CLI execution.
        disable += "ExpiredTargetSdkVersion"
    }

    testOptions {
        unitTests.isReturnDefaultValues = true
    }

    signingConfigs {
        if (hasReleaseSigning) {
            create("release") {
                storeFile = File(releaseStorePath!!)
                storePassword = releaseStorePassword
                keyAlias = releaseKeyAlias
                keyPassword = releaseKeyPassword
            }
        }
    }

    buildTypes {
        release {
            // Use the stable release keystore when configured (CI secrets or local key.properties).
            signingConfig = if (hasReleaseSigning) {
                signingConfigs.getByName("release")
            } else {
                signingConfigs.getByName("debug")
            }
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro",
            )
        }
    }
}

dependencies {
    implementation("org.apache.commons:commons-compress:1.27.1")
    testImplementation("junit:junit:4.13.2")
    testImplementation("org.json:json:20240303")
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}
