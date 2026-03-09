import java.util.Locale
import java.util.Properties

plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
    id("com.google.dagger.hilt.android")
    id("com.google.devtools.ksp")
    id("io.sentry.android.gradle")
    id("com.onesignal.androidsdk.onesignal-gradle-plugin")
    kotlin("plugin.serialization") version "1.9.22"
}

// Load keystore properties from file (not in version control)
val keystorePropertiesFile = rootProject.file("keystore.properties")
val keystoreProperties = Properties()
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(keystorePropertiesFile.inputStream())
}

// Load local properties for API keys (not in version control)
val localPropertiesFile = rootProject.file("local.properties")
val localProperties = Properties()
if (localPropertiesFile.exists()) {
    localProperties.load(localPropertiesFile.inputStream())
}

fun localProp(key: String, default: String = ""): String =
    localProperties.getProperty(key, default)

android {
    namespace = "my.ssdid.drive"
    compileSdk = 34

    // ==================== Signing Configurations ====================
    signingConfigs {
        create("release") {
            if (keystorePropertiesFile.exists()) {
                storeFile = file(keystoreProperties["storeFile"] as String)
                storePassword = keystoreProperties["storePassword"] as String
                keyAlias = keystoreProperties["keyAlias"] as String
                keyPassword = keystoreProperties["keyPassword"] as String
            }
        }
    }

    defaultConfig {
        applicationId = "my.ssdid.drive"
        minSdk = 24
        targetSdk = 34
        versionCode = 1
        versionName = "1.0.0"

        testInstrumentationRunner = "dagger.hilt.android.testing.HiltTestRunner"
        val e2eEnabledArg =
            (project.findProperty("E2E_ENABLED") as? String)?.takeIf { it.isNotBlank() } ?: "false"
        val e2eTenantSlugArg =
            (project.findProperty("E2E_TENANT_SLUG") as? String)?.takeIf { it.isNotBlank() } ?: "e2e"

        testInstrumentationRunnerArguments["e2e"] = e2eEnabledArg.lowercase(Locale.ROOT)
        testInstrumentationRunnerArguments["tenant_slug"] = e2eTenantSlugArg

        vectorDrawables {
            useSupportLibrary = true
        }

        // Sentry DSN (shared across all variants)
        buildConfigField("String", "SENTRY_DSN", "\"${localProp("sentry.dsn")}\"")
        buildConfigField("String", "E2E_TENANT_SLUG", "\"e2e\"")
    }

    // ==================== Product Flavors ====================
    flavorDimensions += "environment"

    productFlavors {
        create("dev") {
            dimension = "environment"
            applicationIdSuffix = ".dev"
            versionNameSuffix = "-dev"
            resValue("string", "app_name", "SSDID Drive Dev")

            // Local development server (emulator)
            buildConfigField("String", "API_BASE_URL", "\"http://10.0.2.2:4000/api/\"")
            buildConfigField("String", "API_WS_URL", "\"ws://10.0.2.2:4000/socket/websocket\"")
            buildConfigField("Boolean", "ENABLE_LOGGING", "true")
            buildConfigField("Boolean", "ENABLE_CRASH_REPORTING", "false")
            buildConfigField("String", "CERT_PIN_PRIMARY", "\"\"")
            buildConfigField("String", "CERT_PIN_BACKUP", "\"\"")

            // Certificate pinning disabled for local development
            buildConfigField("String", "CERT_PIN_PRIMARY", "\"PLACEHOLDER_DEV\"")
            buildConfigField("String", "CERT_PIN_BACKUP", "\"PLACEHOLDER_DEV\"")

            // OneSignal App ID (use your dev/test app)
            manifestPlaceholders["onesignal_app_id"] = localProp("onesignal.app.id")
            manifestPlaceholders["onesignal_google_project_number"] = "REMOTE"
        }

        create("staging") {
            dimension = "environment"
            applicationIdSuffix = ".staging"
            versionNameSuffix = "-staging"
            resValue("string", "app_name", "SSDID Drive Staging")

            // Staging server
            buildConfigField("String", "API_BASE_URL", "\"https://staging-api.ssdiddrive.example/api/\"")
            buildConfigField("String", "API_WS_URL", "\"wss://staging-api.ssdiddrive.example/socket/websocket\"")
            buildConfigField("Boolean", "ENABLE_LOGGING", "true")
            buildConfigField("Boolean", "ENABLE_CRASH_REPORTING", "true")
            buildConfigField("String", "CERT_PIN_PRIMARY", "\"REPLACE_WITH_STAGING_PRIMARY_PIN\"")
            buildConfigField("String", "CERT_PIN_BACKUP", "\"REPLACE_WITH_STAGING_BACKUP_PIN\"")

            // Certificate pinning - IMPORTANT: Replace with actual staging server cert hashes
            // Generate using: openssl s_client -servername staging-api.ssdiddrive.example -connect staging-api.ssdiddrive.example:443 | openssl x509 -pubkey -noout | openssl pkey -pubin -outform der | openssl dgst -sha256 -binary | openssl enc -base64
            buildConfigField("String", "CERT_PIN_PRIMARY", "\"PLACEHOLDER_STAGING_PRIMARY\"")
            buildConfigField("String", "CERT_PIN_BACKUP", "\"PLACEHOLDER_STAGING_BACKUP\"")

            // OneSignal App ID (staging)
            manifestPlaceholders["onesignal_app_id"] = localProp("onesignal.app.id")
            manifestPlaceholders["onesignal_google_project_number"] = "REMOTE"
        }

        create("prod") {
            dimension = "environment"
            resValue("string", "app_name", "SSDID Drive")

            // Production server
            buildConfigField("String", "API_BASE_URL", "\"https://api.ssdiddrive.example/api/\"")
            buildConfigField("String", "API_WS_URL", "\"wss://api.ssdiddrive.example/socket/websocket\"")
            buildConfigField("Boolean", "ENABLE_LOGGING", "false")
            buildConfigField("Boolean", "ENABLE_CRASH_REPORTING", "true")
            buildConfigField("String", "CERT_PIN_PRIMARY", "\"REPLACE_WITH_PROD_PRIMARY_PIN\"")
            buildConfigField("String", "CERT_PIN_BACKUP", "\"REPLACE_WITH_PROD_BACKUP_PIN\"")

            // Certificate pinning - CRITICAL: Replace with actual production cert hashes before release!
            // Generate using: openssl s_client -servername api.ssdiddrive.example -connect api.ssdiddrive.example:443 | openssl x509 -pubkey -noout | openssl pkey -pubin -outform der | openssl dgst -sha256 -binary | openssl enc -base64
            // Include both primary (current cert) and backup (next cert for rotation)
            buildConfigField("String", "CERT_PIN_PRIMARY", "\"PLACEHOLDER_PROD_PRIMARY\"")
            buildConfigField("String", "CERT_PIN_BACKUP", "\"PLACEHOLDER_PROD_BACKUP\"")

            // OneSignal App ID (production)
            manifestPlaceholders["onesignal_app_id"] = localProp("onesignal.app.id")
            manifestPlaceholders["onesignal_google_project_number"] = "REMOTE"
        }
    }

    buildTypes {
        debug {
            isMinifyEnabled = false
            isDebuggable = true
        }
        release {
            isMinifyEnabled = true
            isShrinkResources = true
            isDebuggable = false
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )
            // Use release signing config if available
            if (keystorePropertiesFile.exists()) {
                signingConfig = signingConfigs.getByName("release")
            }
        }
    }

    compileOptions {
        // Enable core library desugaring for java.time API support on API < 26
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = "17"
    }

    buildFeatures {
        compose = true
        buildConfig = true
    }

    composeOptions {
        kotlinCompilerExtensionVersion = "1.5.9"
    }

    packaging {
        resources {
            excludes += "/META-INF/{AL2.0,LGPL2.1}"
            excludes += "META-INF/versions/9/OSGI-INF/MANIFEST.MF"
        }
    }

    // 64-bit only for PQC libraries
    ndkVersion = "25.2.9519653"

    splits {
        abi {
            isEnable = true
            reset()
            include("arm64-v8a", "x86_64")
            isUniversalApk = false
        }
    }
}

configurations.all {
    // Exclude older Bouncy Castle versions to avoid duplicate class conflicts
    exclude(group = "org.bouncycastle", module = "bcprov-jdk15to18")
    exclude(group = "org.bouncycastle", module = "bcpkix-jdk15to18")
    exclude(group = "org.bouncycastle", module = "bcutil-jdk15to18")
}

dependencies {
    // Core library desugaring for java.time API support on API < 26
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.0.4")

    // Core Android
    implementation("androidx.core:core-ktx:1.12.0")
    implementation("androidx.lifecycle:lifecycle-runtime-ktx:2.7.0")
    implementation("androidx.lifecycle:lifecycle-runtime-compose:2.7.0")
    implementation("androidx.lifecycle:lifecycle-viewmodel-compose:2.7.0")
    implementation("androidx.activity:activity-compose:1.8.2")

    // Compose BOM
    implementation(platform("androidx.compose:compose-bom:2024.02.00"))
    implementation("androidx.compose.ui:ui")
    implementation("androidx.compose.ui:ui-graphics")
    implementation("androidx.compose.ui:ui-tooling-preview")
    implementation("androidx.compose.material3:material3")
    implementation("androidx.compose.material:material-icons-extended")

    // Navigation
    implementation("androidx.navigation:navigation-compose:2.7.6")

    // Hilt - Dependency Injection
    implementation("com.google.dagger:hilt-android:2.50")
    ksp("com.google.dagger:hilt-compiler:2.50")
    androidTestImplementation("com.google.dagger:hilt-android-testing:2.50")
    kspAndroidTest("com.google.dagger:hilt-compiler:2.50")
    implementation("androidx.hilt:hilt-navigation-compose:1.1.0")
    implementation("androidx.hilt:hilt-work:1.1.0")
    ksp("androidx.hilt:hilt-compiler:1.1.0")

    // Networking - Retrofit + OkHttp
    implementation("com.squareup.retrofit2:retrofit:2.9.0")
    implementation("com.squareup.retrofit2:converter-gson:2.9.0")
    implementation("com.squareup.okhttp3:okhttp:4.12.0")
    implementation("com.squareup.okhttp3:logging-interceptor:4.12.0")

    // Serialization
    implementation("org.jetbrains.kotlinx:kotlinx-serialization-json:1.6.2")
    implementation("com.google.code.gson:gson:2.10.1")

    // Room - Local Database
    implementation("androidx.room:room-runtime:2.6.1")
    implementation("androidx.room:room-ktx:2.6.1")
    implementation("androidx.room:room-paging:2.6.1")
    ksp("androidx.room:room-compiler:2.6.1")

    // SQLCipher - Database Encryption
    implementation("net.zetetic:android-database-sqlcipher:4.5.4")
    implementation("androidx.sqlite:sqlite-ktx:2.4.0")

    // Paging 3
    implementation("androidx.paging:paging-runtime-ktx:3.2.1")
    implementation("androidx.paging:paging-compose:3.2.1")

    // DataStore - Preferences
    implementation("androidx.datastore:datastore-preferences:1.0.0")

    // Security - Encrypted Storage
    implementation("androidx.security:security-crypto:1.1.0-alpha06")

    // Biometric Authentication
    implementation("androidx.biometric:biometric:1.1.0")

    // Credential Manager (WebAuthn/Passkeys)
    implementation("androidx.credentials:credentials:1.3.0")
    implementation("androidx.credentials:credentials-play-services-auth:1.3.0")

    // Custom Tabs (OIDC browser flow)
    implementation("androidx.browser:browser:1.7.0")

    // Coroutines
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-android:1.7.3")
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-core:1.7.3")

    // WorkManager - Background Processing
    implementation("androidx.work:work-runtime-ktx:2.9.0")

    // Coil - Image Loading
    implementation("io.coil-kt:coil-compose:2.5.0")

    // Accompanist
    implementation("com.google.accompanist:accompanist-permissions:0.34.0")
    implementation("com.google.accompanist:accompanist-systemuicontroller:0.34.0")

    // PQC Libraries (local AAR) - KAZ algorithms
    implementation(files("libs/kazkem-release.aar"))
    implementation(files("libs/kazsign-release.aar"))

    // Bouncy Castle - NIST PQC algorithms (ML-KEM, ML-DSA)
    implementation("org.bouncycastle:bcprov-jdk18on:1.78.1")
    implementation("org.bouncycastle:bcpkix-jdk18on:1.78.1")

    // PDF Viewer
    implementation("io.github.grizzi91:bouquet:1.1.2")

    // Sentry - Crash Reporting & Performance Monitoring
    implementation("io.sentry:sentry-android:7.3.0")
    implementation("io.sentry:sentry-android-okhttp:7.3.0")
    implementation("io.sentry:sentry-android-timber:7.3.0")

    // OneSignal - Push Notifications (cross-platform)
    implementation("com.onesignal:OneSignal:5.1.6")

    // Testing
    testImplementation("junit:junit:4.13.2")
    testImplementation("org.jetbrains.kotlinx:kotlinx-coroutines-test:1.7.3")
    testImplementation("io.mockk:mockk:1.13.9")
    testImplementation("app.cash.turbine:turbine:1.0.0")

    androidTestImplementation("androidx.test.ext:junit:1.1.5")
    androidTestImplementation("androidx.test.espresso:espresso-core:3.5.1")
    androidTestImplementation(platform("androidx.compose:compose-bom:2024.02.00"))
    androidTestImplementation("androidx.compose.ui:ui-test-junit4")
    androidTestImplementation("com.google.dagger:hilt-android-testing:2.50")
    kspAndroidTest("com.google.dagger:hilt-compiler:2.50")

    debugImplementation("androidx.compose.ui:ui-tooling")
    debugImplementation("androidx.compose.ui:ui-test-manifest")
}

// Sentry configuration for automatic ProGuard mapping upload
sentry {
    // Enables source context, showing snippet of code affected by error
    includeSourceContext = false

    // Upload ProGuard/R8 mappings for release builds
    autoUploadProguardMapping = false

    // Upload native symbols for native crashes
    uploadNativeSymbols = false

    // Add source bundles for better stack traces
    includeNativeSources = false

    // Performance monitoring
    tracingInstrumentation {
        enabled = true
    }

    // Auto-install integrations
    autoInstallation {
        enabled = true
    }
}
