package com.securesharing.e2e

import android.content.Context
import androidx.test.platform.app.InstrumentationRegistry
import com.securesharing.BuildConfig
import java.io.File
import java.util.UUID

object E2eTestConfig {
    private const val ARG_E2E_ENABLED = "e2e"
    private const val ARG_TENANT_SLUG = "tenant_slug"

    fun isE2eEnabled(): Boolean {
        val args = InstrumentationRegistry.getArguments()
        return args.getString(ARG_E2E_ENABLED, "false").equals("true", ignoreCase = true)
    }

    fun tenantSlug(): String {
        val args = InstrumentationRegistry.getArguments()
        return args.getString(ARG_TENANT_SLUG, BuildConfig.E2E_TENANT_SLUG)
    }

    fun isLocalBackend(): Boolean {
        return BuildConfig.API_BASE_URL.contains("10.0.2.2") ||
            BuildConfig.API_BASE_URL.contains("localhost")
    }

    fun uniqueEmail(prefix: String): String {
        val nonce = UUID.randomUUID().toString().take(8)
        return "${prefix}_$nonce@example.com"
    }

    fun createTempFile(context: Context, name: String, content: ByteArray): File {
        val file = File(context.cacheDir, name)
        file.outputStream().use { it.write(content) }
        return file
    }
}
