pluginManagement {
    val flutterSdkPath = run {
        val properties = java.util.Properties()
        file("local.properties").inputStream().use { properties.load(it) }
        val flutterSdkPath = properties.getProperty("flutter.sdk")
        require(flutterSdkPath != null) { "flutter.sdk not set in local.properties" }
        flutterSdkPath
    }

    includeBuild("$flutterSdkPath/packages/flutter_tools/gradle")

    repositories {
        google()
        mavenCentral()
        gradlePluginPortal()
    }
}

plugins {
    id("dev.flutter.flutter-plugin-loader") version "1.0.0"
    id("com.android.application") version "8.13.1" apply false
    id("org.jetbrains.kotlin.android") version "1.8.22" apply false
}

include(":app")

// Dev-only composite: build against the checked-out sibling libs when present;
// otherwise the declared com.eclypses:* artifacts resolve from Maven Central.
if (file("../../../../Packages/mte-relay-client-android").exists()) {
    includeBuild("../../../../Packages/mte-relay-client-android") {
        dependencySubstitution {
            substitute(module("com.eclypses:mte-relay-client-android")).using(project(":relay"))
        }
    }
}
if (file("../../../../Packages/mte-client-android").exists()) {
    includeBuild("../../../../Packages/mte-client-android") {
        dependencySubstitution {
            substitute(module("com.eclypses:mte-client-android")).using(project(":mte"))
        }
    }
}
