plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
}

android {
    namespace = "com.jsm.core"
    compileSdk = 34

    signingConfigs {
        create("release") {
            storeFile = file("../elysium-release.keystore")
            storePassword = "ElysiumVanguard2026"
            keyAlias = "elysium"
            keyPassword = "ElysiumVanguard2026"
        }
    }

    defaultConfig {
        applicationId = "com.jsm.core"
        minSdk = 31
        targetSdk = 34
        versionCode = 2
        versionName = "1.1"
    }

    buildTypes {
        release {
            isMinifyEnabled = false
            signingConfig = signingConfigs.getByName("release")
        }
    }

    buildFeatures {
        compose = true
    }
    composeOptions {
        kotlinCompilerExtensionVersion = "1.5.8"
    }
    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_1_8
        targetCompatibility = JavaVersion.VERSION_1_8
    }
    kotlinOptions {
        jvmTarget = "1.8"
    }
}

dependencies {
    implementation("androidx.core:core-ktx:1.12.0")
    implementation("androidx.lifecycle:lifecycle-runtime-ktx:2.7.0")

    // Jetpack Compose & Foldable APIs
    implementation("androidx.activity:activity-compose:1.8.2")
    implementation(platform("androidx.compose:compose-bom:2024.02.00"))
    implementation("androidx.compose.ui:ui")
    implementation("androidx.compose.material3:material3")
    implementation("androidx.window:window:1.2.0")

    // WebRTC Native (Community-maintained SDK - actively updated)
    implementation("io.github.webrtc-sdk:android:125.6422.07")

    // Protobuf Lite (runtime only, schemas pre-compiled)
    implementation("com.google.protobuf:protobuf-javalite:3.25.1")
}
