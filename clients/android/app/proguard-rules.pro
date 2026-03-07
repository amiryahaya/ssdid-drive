# SSDID Drive ProGuard Rules

# Retrofit
-keepattributes Signature
-keepattributes *Annotation*
-keep class retrofit2.** { *; }
-keepclasseswithmembers class * {
    @retrofit2.http.* <methods>;
}

# OkHttp
-dontwarn okhttp3.**
-dontwarn okio.**
-dontwarn javax.annotation.**
-keepnames class okhttp3.internal.publicsuffix.PublicSuffixDatabase

# Gson
-keepattributes Signature
-keepattributes *Annotation*
-dontwarn sun.misc.**
-keep class com.google.gson.stream.** { *; }
-keep class * extends com.google.gson.TypeAdapter
-keep class * implements com.google.gson.TypeAdapterFactory
-keep class * implements com.google.gson.JsonSerializer
-keep class * implements com.google.gson.JsonDeserializer
-keepclassmembers,allowobfuscation class * {
  @com.google.gson.annotations.SerializedName <fields>;
}

# Keep data classes
-keep class my.ssdid.drive.data.remote.dto.** { *; }
-keep class my.ssdid.drive.domain.model.** { *; }

# Room
-keep class * extends androidx.room.RoomDatabase
-keep @androidx.room.Entity class *
-dontwarn androidx.room.paging.**

# Hilt
-dontwarn dagger.hilt.android.internal.**

# ====================================================================================
# PQC (Post-Quantum Cryptography) Libraries
# CRITICAL: These rules are essential for the app's security functionality
# ====================================================================================

# KAZ-KEM (Custom PQC Key Encapsulation Mechanism)
-keep class com.pqc.kazkem.** { *; }
-keepclassmembers class com.pqc.kazkem.** {
    native <methods>;
    public *;
}
-keepclasseswithmembers class com.pqc.kazkem.** {
    native <methods>;
}

# KAZ-SIGN (Custom PQC Digital Signatures)
-keep class com.pqc.kazsign.** { *; }
-keepclassmembers class com.pqc.kazsign.** {
    native <methods>;
    public *;
}
-keepclasseswithmembers class com.pqc.kazsign.** {
    native <methods>;
}

# Bouncy Castle - NIST PQC Algorithms (ML-KEM-768, ML-DSA-65)
-keep class org.bouncycastle.** { *; }
-keepclassmembers class org.bouncycastle.** { *; }
-dontwarn org.bouncycastle.**
-dontnote org.bouncycastle.**

# Specifically keep PQC-related Bouncy Castle classes
-keep class org.bouncycastle.pqc.** { *; }
-keep class org.bouncycastle.pqc.crypto.** { *; }
-keep class org.bouncycastle.pqc.crypto.mlkem.** { *; }
-keep class org.bouncycastle.pqc.crypto.mldsa.** { *; }
-keep class org.bouncycastle.pqc.jcajce.** { *; }

# Keep native methods (general rule for all JNI)
-keepclasseswithmembernames class * {
    native <methods>;
}

# ====================================================================================
# SSDID Drive Crypto Classes - DO NOT OBFUSCATE
# These handle sensitive cryptographic operations
# ====================================================================================
-keep class my.ssdid.drive.crypto.** { *; }
-keepclassmembers class my.ssdid.drive.crypto.** {
    public *;
    private *;
}

# Keep crypto providers specifically
-keep class my.ssdid.drive.crypto.providers.** { *; }
-keep class my.ssdid.drive.crypto.CryptoManager { *; }
-keep class my.ssdid.drive.crypto.KeyManager { *; }
-keep class my.ssdid.drive.crypto.KeyBundle { *; }
-keep class my.ssdid.drive.crypto.SecureMemory { *; }
-keep class my.ssdid.drive.crypto.ShamirSecretSharing { *; }
-keep class my.ssdid.drive.crypto.FileEncryptor { *; }
-keep class my.ssdid.drive.crypto.FileDecryptor { *; }
-keep class my.ssdid.drive.crypto.FolderKeyManager { *; }

# Kotlin Coroutines
-keepnames class kotlinx.coroutines.internal.MainDispatcherFactory {}
-keepnames class kotlinx.coroutines.CoroutineExceptionHandler {}
-keepclassmembers class kotlinx.coroutines.** {
    volatile <fields>;
}

# Kotlin Serialization
-keepattributes *Annotation*, InnerClasses
-dontnote kotlinx.serialization.AnnotationsKt
-keepclassmembers @kotlinx.serialization.Serializable class ** {
    *** Companion;
}
-if @kotlinx.serialization.Serializable class **
-keepclassmembers class <1>$Companion {
    kotlinx.serialization.KSerializer serializer(...);
}

# Security - Don't obfuscate security-related classes
-keep class androidx.security.crypto.** { *; }

# Compose
-keep class androidx.compose.** { *; }
-dontwarn androidx.compose.**

# Remove debug logs in release
-assumenosideeffects class android.util.Log {
    public static *** d(...);
    public static *** v(...);
}

# ====================================================================================
# Third-party library rules for R8 compatibility
# ====================================================================================

# PDFBox - JP2 decoder is optional (JPEG2000 support)
-dontwarn com.gemalto.jp2.**

# Google Tink - Error Prone annotations are compile-time only
-dontwarn com.google.errorprone.annotations.**

# Timber - Keep for Sentry integration
-keep class timber.log.Timber { *; }
-keep class timber.log.Timber$Tree { *; }
-dontwarn timber.log.**

# Sentry
-keep class io.sentry.** { *; }
-dontwarn io.sentry.**

# Google Play Services (optional dependency)
-dontwarn com.google.android.gms.**

# Amazon IAP (optional dependency)
-dontwarn com.amazon.device.iap.**

# JNDI (not available on Android)
-dontwarn javax.naming.**

# OneSignal
-keep class com.onesignal.** { *; }
-dontwarn com.onesignal.**
