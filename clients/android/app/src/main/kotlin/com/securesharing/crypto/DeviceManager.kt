package com.securesharing.crypto

import android.content.Context
import android.os.Build
import android.provider.Settings
import android.util.Base64
import dagger.hilt.android.qualifiers.ApplicationContext
import com.securesharing.data.local.SecureStorage
import com.securesharing.domain.model.DeviceKeyAlgorithm
import java.security.MessageDigest
import javax.inject.Inject
import javax.inject.Singleton

/**
 * Manages device-specific cryptographic operations.
 *
 * Handles device fingerprinting, signing key generation, and request signing
 * for the device enrollment feature.
 */
@Singleton
class DeviceManager @Inject constructor(
    @ApplicationContext private val context: Context,
    private val cryptoManager: CryptoManager,
    private val keyManager: KeyManager,
    private val secureStorage: SecureStorage
) {
    // In-memory cache of decrypted device signing private key
    @Volatile
    private var deviceSigningPrivateKey: ByteArray? = null

    // ==================== Device Fingerprinting ====================

    /**
     * Generate a stable device fingerprint.
     * Uses a combination of device properties hashed with SHA-256.
     */
    fun generateDeviceFingerprint(): String {
        val fingerprintData = buildString {
            // Android ID (unique per device/user combination)
            append(getAndroidId())
            append("|")
            // Device model
            append(Build.MODEL)
            append("|")
            // Manufacturer
            append(Build.MANUFACTURER)
            append("|")
            // Board
            append(Build.BOARD)
            append("|")
            // Hardware
            append(Build.HARDWARE)
            append("|")
            // Device
            append(Build.DEVICE)
        }

        val digest = MessageDigest.getInstance("SHA-256")
        val hash = digest.digest(fingerprintData.toByteArray(Charsets.UTF_8))
        return "sha256:" + hash.joinToString("") { "%02x".format(it) }
    }

    @Suppress("HardwareIds")
    private fun getAndroidId(): String {
        return Settings.Secure.getString(
            context.contentResolver,
            Settings.Secure.ANDROID_ID
        ) ?: "unknown"
    }

    /**
     * Get device info for enrollment.
     */
    fun getDeviceInfo(): DeviceInfo {
        val packageInfo = try {
            context.packageManager.getPackageInfo(context.packageName, 0)
        } catch (e: Exception) {
            null
        }

        return DeviceInfo(
            model = Build.MODEL,
            manufacturer = Build.MANUFACTURER,
            osVersion = "Android ${Build.VERSION.RELEASE}",
            appVersion = packageInfo?.versionName ?: "unknown",
            sdkVersion = Build.VERSION.SDK_INT
        )
    }

    // ==================== Key Generation ====================

    /**
     * Generate a device signing key pair based on the configured algorithm.
     *
     * @param algorithm The signing algorithm to use
     * @return Pair of (publicKey, privateKey)
     */
    fun generateDeviceKeyPair(algorithm: DeviceKeyAlgorithm): Pair<ByteArray, ByteArray> {
        return when (algorithm) {
            DeviceKeyAlgorithm.KAZ_SIGN -> cryptoManager.generateKazSignKeyPair()
            DeviceKeyAlgorithm.ML_DSA -> cryptoManager.generateMlDsaKeyPair()
        }
    }

    /**
     * Get the preferred signing algorithm based on tenant config.
     */
    fun getPreferredAlgorithm(): DeviceKeyAlgorithm {
        return when (cryptoManager.cryptoConfig.getAlgorithm()) {
            PqcAlgorithm.KAZ -> DeviceKeyAlgorithm.KAZ_SIGN
            PqcAlgorithm.NIST -> DeviceKeyAlgorithm.ML_DSA
            PqcAlgorithm.HYBRID -> DeviceKeyAlgorithm.KAZ_SIGN // Default to KAZ for hybrid
        }
    }

    // ==================== Key Storage ====================

    /**
     * Store device signing keys securely.
     * The private key is encrypted with the user's master key.
     */
    suspend fun storeDeviceKeys(
        publicKey: ByteArray,
        privateKey: ByteArray,
        algorithm: DeviceKeyAlgorithm
    ) {
        // Get master key from unlocked keys
        val masterKey = keyManager.getUnlockedKeys().masterKey

        // Encrypt private key with master key
        val encryptedPrivateKey = cryptoManager.encryptAesGcm(privateKey, masterKey)

        // Store encrypted private key and public key
        secureStorage.saveEncryptedDeviceSigningKey(encryptedPrivateKey)
        secureStorage.saveDeviceSigningPublicKey(publicKey)
        secureStorage.saveDeviceKeyAlgorithm(algorithm.toApiString())

        // Cache the private key in memory
        deviceSigningPrivateKey = privateKey.copyOf()
    }

    /**
     * Load device signing private key from storage.
     * Decrypts using the user's master key.
     */
    suspend fun loadDeviceSigningKey(): ByteArray? {
        // Return cached key if available
        deviceSigningPrivateKey?.let { return it }

        // Load and decrypt from storage
        val encryptedKey = secureStorage.getEncryptedDeviceSigningKey() ?: return null

        return try {
            val masterKey = keyManager.getUnlockedKeys().masterKey
            val privateKey = cryptoManager.decryptAesGcm(encryptedKey, masterKey)
            deviceSigningPrivateKey = privateKey
            privateKey
        } catch (e: Exception) {
            null
        }
    }

    /**
     * Get the stored device signing algorithm.
     */
    suspend fun getDeviceKeyAlgorithm(): DeviceKeyAlgorithm? {
        val algorithmStr = secureStorage.getDeviceKeyAlgorithm() ?: return null
        return DeviceKeyAlgorithm.fromString(algorithmStr)
    }

    /**
     * Get the device signing public key.
     */
    suspend fun getDevicePublicKey(): ByteArray? {
        return secureStorage.getDeviceSigningPublicKey()
    }

    // ==================== Request Signing ====================

    /**
     * Sign a request payload using the device's signing key.
     *
     * @param payload The payload to sign (method|path|timestamp|body_hash)
     * @return Base64-encoded signature
     */
    suspend fun signRequest(payload: String): String? {
        val privateKey = loadDeviceSigningKey() ?: return null
        val algorithm = getDeviceKeyAlgorithm() ?: return null

        val payloadBytes = payload.toByteArray(Charsets.UTF_8)

        val signature = when (algorithm) {
            DeviceKeyAlgorithm.KAZ_SIGN -> cryptoManager.kazSign(payloadBytes, privateKey)
            DeviceKeyAlgorithm.ML_DSA -> cryptoManager.mlDsaSign(payloadBytes, privateKey)
        }

        return Base64.encodeToString(signature, Base64.NO_WRAP)
    }

    /**
     * Build the signature payload from request components.
     *
     * Format: {method}|{path_with_query}|{timestamp}|{body_hash}
     * Where body_hash is SHA-256 of the raw request body bytes (empty string for GET/no body).
     *
     * SECURITY: Path should include query string to prevent query parameter tampering.
     * Body is passed as raw bytes to preserve binary content integrity.
     */
    fun buildSignaturePayload(method: String, path: String, timestamp: Long, bodyBytes: ByteArray?): String {
        val bodyHash = if (bodyBytes == null || bodyBytes.isEmpty()) {
            ""
        } else {
            // SECURITY: Hash raw bytes directly, not UTF-8 string
            // This preserves integrity of binary payloads
            val digest = MessageDigest.getInstance("SHA-256")
            val hash = digest.digest(bodyBytes)
            hash.joinToString("") { "%02x".format(it) }
        }

        return "${method.uppercase()}|$path|$timestamp|$bodyHash"
    }

    // ==================== Cleanup ====================

    /**
     * Clear device signing key from memory.
     */
    fun clearDeviceKey() {
        deviceSigningPrivateKey?.let { key ->
            SecureMemory.zeroize(key)
        }
        deviceSigningPrivateKey = null
    }

    /**
     * Clear all device enrollment data.
     */
    suspend fun clearEnrollment() {
        clearDeviceKey()
        secureStorage.clearDeviceEnrollment()
    }

    /**
     * Check if device keys are loaded in memory.
     */
    fun hasDeviceKey(): Boolean = deviceSigningPrivateKey != null
}

/**
 * Device info data class for enrollment.
 */
data class DeviceInfo(
    val model: String,
    val manufacturer: String,
    val osVersion: String,
    val appVersion: String,
    val sdkVersion: Int
)
