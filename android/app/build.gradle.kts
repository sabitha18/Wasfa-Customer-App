plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
    // Reads android/app/google-services.json — see README for how to get that file.
    id("com.google.gms.google-services")
}

android {
    namespace = "kw.wasfa.customer"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
        // Required by flutter_local_notifications.
        isCoreLibraryDesugaringEnabled = true
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        applicationId = "kw.wasfa.customer"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        // firebase_messaging (recent versions) requires 23+ — hardcoded
        // rather than left to flutter.minSdkVersion, since that default
        // isn't guaranteed to stay >=23 across Flutter SDK updates, and a
        // silent drop back to a lower default would only surface as a
        // manifest-merger build failure, not a clear "why" message.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")
        }
    }
}

flutter {
    source = "../.."
}

dependencies {
    // Pulled in by isCoreLibraryDesugaringEnabled above — without this
    // dependency present, that flag alone isn't enough and the same build
    // error comes back.
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}
