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
            // Confirmed real crash (2026-09-22): R8 was miscompiling a
            // class inside the Tap payment SDK (java.lang.VerifyError on
            // PaymentDataManager$PaymentProcessListener), only in release
            // builds. A `-keep` rule (proguard-rules.pro) did NOT fix
            // this — confirmed by the exact same crash reproducing after
            // adding it — because `-keep` only protects a class from
            // being REMOVED/RENAMED; it doesn't stop R8's separate code
            // OPTIMIZATION pass (register allocation, inlining) from
            // still rewriting the method bodies, which is exactly where
            // this bug lives (a register-type-inference error inside
            // didReceiveAuthorize/didReceiveSaveCard). Disabling
            // minification outright removes R8 from the picture
            // entirely, rather than trying to guess a more precise rule
            // for a bug already confirmed to survive one attempt.
            // Trade-off: a larger APK and no obfuscation — revisit
            // re-enabling R8 with a properly scoped `-dontoptimize` rule
            // for just this SDK's package once the payment flow is
            // confirmed working, rather than leaving it blocked on
            // getting R8's config exactly right.
            isMinifyEnabled = false
            isShrinkResources = false
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
