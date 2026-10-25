import java.io.FileInputStream
import java.util.Properties

plugins {
    id("com.android.application")
    // Flutter Gradle 插件必须在 Android / Kotlin 插件之后应用
    id("dev.flutter.flutter-gradle-plugin")
}

// 正式签名（key.properties 不入库，见 安卓开发指南.md）
val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
if (keystorePropertiesFile.exists()) {
    keystorePropertiesFile.inputStream().use { keystoreProperties.load(it) }
}

android {
    namespace = "com.bobomusic"
    compileSdk = flutter.compileSdkVersion
    // 全部插件要求 NDK 28.2（Flutter 提示向后兼容、取最高版）；sdkmanager 首次会下载 ~2GB
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "com.bobomusic"
        // 保持旧版 21（支持 Android 5.x）；SDK 模板默认 24（最低 Android 7），
        // 若决定放弃 API 21~23 设备，可改回 flutter.minSdkVersion（重构计划 D13 备注）
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        // versionCode 取 pubspec 版本号 +N（D5：发布时必须延续递增）
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        multiDexEnabled = true
    }

    signingConfigs {
        create("release") {
            val storeFileValue = keystoreProperties["storeFile"]?.let { file(it) }
            if (storeFileValue == null) {
                throw GradleException("storeFile is null. Check key.properties file.")
            }
            storeFile = storeFileValue
            storePassword = keystoreProperties["storePassword"] as String?
            keyAlias = keystoreProperties["keyAlias"] as String?
            keyPassword = keystoreProperties["keyPassword"] as String?
        }
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("release")
        }
        debug {
            // 沿用旧版：debug 包独立身份（.debug 后缀），也用正式签名便于真机覆盖安装测试
            applicationIdSuffix = ".debug"
            versionNameSuffix = "-debug"
            signingConfig = signingConfigs.getByName("release")
        }
    }

    splits {
        abi {
            isEnable = true
            reset()
            include("armeabi-v7a", "arm64-v8a", "x86", "x86_64")
            isUniversalApk = true
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
