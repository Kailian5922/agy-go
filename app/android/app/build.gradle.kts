plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Optional PRoot Linux rootfs bundles built by runtime/build-rootfs.sh.
val runtimeOut = rootProject.file("../../runtime/out")

android {
    namespace = "io.github.kailian5922.agy_go"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
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

    buildTypes {
        release {
            // Local release builds fall back to debug signing until key.properties is configured.
            signingConfig = signingConfigs.getByName("debug")
        }
    }
}

dependencies {
    implementation("org.apache.commons:commons-compress:1.27.1")
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}
