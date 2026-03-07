package my.ssdid.drive

import android.app.Application
import androidx.hilt.work.HiltWorkerFactory
import androidx.work.Configuration
import coil.ImageLoader
import coil.ImageLoaderFactory
import coil.disk.DiskCache
import coil.memory.MemoryCache
import coil.request.CachePolicy
import my.ssdid.drive.util.PushNotificationManager
import my.ssdid.drive.util.SentryConfig
import dagger.hilt.android.HiltAndroidApp
import java.io.File
import javax.inject.Inject

/**
 * SsdidDrive Application class.
 *
 * This is the main application entry point, configured with Hilt for dependency injection,
 * WorkManager for background processing, Coil for optimized image loading, and Sentry for
 * crash reporting and performance monitoring.
 */
@HiltAndroidApp
class SsdidDriveApp : Application(), Configuration.Provider, ImageLoaderFactory {

    @Inject
    lateinit var workerFactory: HiltWorkerFactory

    @Inject
    lateinit var pushNotificationManager: PushNotificationManager

    override val workManagerConfiguration: Configuration
        get() = Configuration.Builder()
            .setWorkerFactory(workerFactory)
            .setMinimumLoggingLevel(android.util.Log.INFO)
            .build()

    /**
     * Create a custom Coil ImageLoader with disk and memory caching for thumbnails.
     *
     * Performance optimizations:
     * - Disk cache: 250MB for thumbnails
     * - Memory cache: 25% of available heap
     * - Crossfade animation for smooth transitions
     */
    override fun newImageLoader(): ImageLoader {
        return ImageLoader.Builder(this)
            .memoryCache {
                MemoryCache.Builder(this)
                    .maxSizePercent(0.25) // 25% of available memory
                    .build()
            }
            .diskCache {
                DiskCache.Builder()
                    .directory(File(cacheDir, "image_cache"))
                    .maxSizeBytes(250L * 1024 * 1024) // 250MB disk cache
                    .build()
            }
            .memoryCachePolicy(CachePolicy.ENABLED)
            .diskCachePolicy(CachePolicy.ENABLED)
            .crossfade(true)
            .respectCacheHeaders(false) // Don't respect server cache headers for local files
            .build()
    }

    override fun onCreate() {
        super.onCreate()

        // Initialize Sentry for crash reporting (before other initializations)
        initializeSentry()

        // Initialize OneSignal push notifications
        initializePushNotifications()

        // Initialize any global components here
        initializeSecurity()
    }

    /**
     * Initialize OneSignal push notifications.
     *
     * OneSignal handles cross-platform push notifications (Android, iOS, Windows).
     * The app ID is configured per build flavor via manifestPlaceholders.
     */
    private fun initializePushNotifications() {
        pushNotificationManager.initialize()

        if (BuildConfig.ENABLE_LOGGING) {
            android.util.Log.d(TAG, "OneSignal push notifications initialized")
        }
    }

    /**
     * Initialize Sentry crash reporting and performance monitoring.
     *
     * Security features:
     * - Sensitive data is automatically scrubbed from reports
     * - User data is anonymized (hashed user ID only)
     * - Screenshots are disabled
     * - Controlled by ENABLE_CRASH_REPORTING build config per flavor
     */
    private fun initializeSentry() {
        // Only initialize Sentry if crash reporting is enabled for this flavor
        if (!BuildConfig.ENABLE_CRASH_REPORTING) {
            if (BuildConfig.ENABLE_LOGGING) {
                android.util.Log.d(TAG, "Sentry disabled for this build flavor")
            }
            return
        }

        // Determine environment from flavor (based on application ID suffix)
        val environment = when {
            BuildConfig.APPLICATION_ID.endsWith(".dev") -> "development"
            BuildConfig.APPLICATION_ID.endsWith(".staging") -> "staging"
            else -> "production"
        }

        SentryConfig.initialize(
            context = this,
            dsn = BuildConfig.SENTRY_DSN,
            environment = environment,
            enableInDebug = BuildConfig.ENABLE_LOGGING // Enable in debug if logging is on
        )

        if (BuildConfig.ENABLE_LOGGING) {
            android.util.Log.d(TAG, "Sentry initialized for environment: $environment")
        }
    }

    /**
     * Initialize security-related components.
     * Uses background loading for non-critical initialization.
     */
    private fun initializeSecurity() {
        // Load native PQC libraries in background to avoid blocking app startup
        Thread {
            try {
                System.loadLibrary("kazkem")
                System.loadLibrary("kazsign")
                if (BuildConfig.ENABLE_LOGGING) {
                    android.util.Log.d(TAG, "PQC libraries loaded successfully")
                }
                if (BuildConfig.ENABLE_CRASH_REPORTING) {
                    SentryConfig.addCryptoBreadcrumb(
                        message = "PQC libraries loaded",
                        operation = "library_load",
                        success = true
                    )
                }
            } catch (e: UnsatisfiedLinkError) {
                // Libraries will be loaded when first used
                if (BuildConfig.ENABLE_LOGGING) {
                    android.util.Log.w(TAG, "PQC libraries not pre-loaded: ${e.message}")
                }
                if (BuildConfig.ENABLE_CRASH_REPORTING) {
                    SentryConfig.addCryptoBreadcrumb(
                        message = "PQC libraries deferred",
                        operation = "library_load",
                        success = false
                    )
                }
            }
        }.start()
    }

    override fun onTrimMemory(level: Int) {
        super.onTrimMemory(level)

        // Clear image cache on low memory
        if (level >= TRIM_MEMORY_MODERATE) {
            android.util.Log.d(TAG, "Trimming memory at level $level")
        }
    }

    companion object {
        private const val TAG = "SsdidDriveApp"
    }
}
