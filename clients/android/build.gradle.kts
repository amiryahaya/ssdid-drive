// Top-level build file for SSDID Drive Android Client
plugins {
    id("com.android.application") version "8.2.2" apply false
    id("org.jetbrains.kotlin.android") version "1.9.22" apply false
    id("com.google.dagger.hilt.android") version "2.50" apply false
    id("com.google.devtools.ksp") version "1.9.22-1.0.17" apply false
    id("io.sentry.android.gradle") version "4.3.1" apply false
    // OneSignal push notifications
    id("com.onesignal.androidsdk.onesignal-gradle-plugin") version "0.14.0" apply false
}

tasks.register("clean", Delete::class) {
    delete(rootProject.layout.buildDirectory)
}
