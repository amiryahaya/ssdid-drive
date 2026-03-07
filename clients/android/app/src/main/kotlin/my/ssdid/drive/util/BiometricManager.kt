package my.ssdid.drive.util

import android.content.Context
import androidx.biometric.BiometricManager
import androidx.biometric.BiometricManager.Authenticators.BIOMETRIC_STRONG
import androidx.biometric.BiometricManager.Authenticators.BIOMETRIC_WEAK
import androidx.biometric.BiometricManager.Authenticators.DEVICE_CREDENTIAL
import androidx.biometric.BiometricPrompt
import androidx.core.content.ContextCompat
import androidx.fragment.app.FragmentActivity
import dagger.hilt.android.qualifiers.ApplicationContext
import kotlinx.coroutines.suspendCancellableCoroutine
import javax.inject.Inject
import javax.inject.Singleton
import kotlin.coroutines.resume

/**
 * Manager for biometric authentication operations.
 *
 * SECURITY: Provides biometric authentication for sensitive operations like
 * unlocking keys, viewing sensitive data, or authorizing transactions.
 */
@Singleton
class BiometricAuthManager @Inject constructor(
    @ApplicationContext private val context: Context
) {
    private val biometricManager = BiometricManager.from(context)

    /**
     * Check if biometric authentication is available.
     */
    fun isBiometricAvailable(): BiometricAvailability {
        return when (biometricManager.canAuthenticate(BIOMETRIC_STRONG or BIOMETRIC_WEAK)) {
            BiometricManager.BIOMETRIC_SUCCESS -> BiometricAvailability.AVAILABLE
            BiometricManager.BIOMETRIC_ERROR_NO_HARDWARE -> BiometricAvailability.NO_HARDWARE
            BiometricManager.BIOMETRIC_ERROR_HW_UNAVAILABLE -> BiometricAvailability.HARDWARE_UNAVAILABLE
            BiometricManager.BIOMETRIC_ERROR_NONE_ENROLLED -> BiometricAvailability.NOT_ENROLLED
            BiometricManager.BIOMETRIC_ERROR_SECURITY_UPDATE_REQUIRED -> BiometricAvailability.SECURITY_UPDATE_REQUIRED
            else -> BiometricAvailability.UNAVAILABLE
        }
    }

    /**
     * Check if device credential (PIN/pattern/password) is available as fallback.
     */
    fun isDeviceCredentialAvailable(): Boolean {
        return biometricManager.canAuthenticate(DEVICE_CREDENTIAL) == BiometricManager.BIOMETRIC_SUCCESS
    }

    /**
     * Check if any authentication method is available (biometric or device credential).
     */
    fun isAuthenticationAvailable(): Boolean {
        val biometricOrCredential = BIOMETRIC_STRONG or BIOMETRIC_WEAK or DEVICE_CREDENTIAL
        return biometricManager.canAuthenticate(biometricOrCredential) == BiometricManager.BIOMETRIC_SUCCESS
    }

    /**
     * Show biometric prompt and authenticate the user.
     *
     * @param activity The activity to show the prompt from
     * @param title Title for the biometric prompt
     * @param subtitle Optional subtitle
     * @param description Optional description
     * @param negativeButtonText Text for the negative button (only shown if not using device credential)
     * @param allowDeviceCredential Whether to allow PIN/pattern/password as fallback
     * @return BiometricResult indicating success or failure
     */
    suspend fun authenticate(
        activity: FragmentActivity,
        title: String,
        subtitle: String? = null,
        description: String? = null,
        negativeButtonText: String = "Cancel",
        allowDeviceCredential: Boolean = true
    ): BiometricResult = suspendCancellableCoroutine { continuation ->
        val executor = ContextCompat.getMainExecutor(activity)

        val callback = object : BiometricPrompt.AuthenticationCallback() {
            override fun onAuthenticationSucceeded(result: BiometricPrompt.AuthenticationResult) {
                if (continuation.isActive) {
                    continuation.resume(BiometricResult.Success(result.authenticationType))
                }
            }

            override fun onAuthenticationError(errorCode: Int, errString: CharSequence) {
                if (continuation.isActive) {
                    val result = when (errorCode) {
                        BiometricPrompt.ERROR_USER_CANCELED,
                        BiometricPrompt.ERROR_NEGATIVE_BUTTON -> BiometricResult.Cancelled
                        BiometricPrompt.ERROR_LOCKOUT -> BiometricResult.Lockout(temporary = true)
                        BiometricPrompt.ERROR_LOCKOUT_PERMANENT -> BiometricResult.Lockout(temporary = false)
                        else -> BiometricResult.Error(errorCode, errString.toString())
                    }
                    continuation.resume(result)
                }
            }

            override fun onAuthenticationFailed() {
                // Don't resume here - the prompt stays open for retry
                // Only called when a biometric is not recognized
            }
        }

        val prompt = BiometricPrompt(activity, executor, callback)

        val promptInfoBuilder = BiometricPrompt.PromptInfo.Builder()
            .setTitle(title)
            .apply {
                subtitle?.let { setSubtitle(it) }
                description?.let { setDescription(it) }
            }

        if (allowDeviceCredential && isDeviceCredentialAvailable()) {
            // Allow device credential as fallback
            promptInfoBuilder.setAllowedAuthenticators(
                BIOMETRIC_STRONG or BIOMETRIC_WEAK or DEVICE_CREDENTIAL
            )
        } else {
            // Biometric only
            promptInfoBuilder
                .setAllowedAuthenticators(BIOMETRIC_STRONG or BIOMETRIC_WEAK)
                .setNegativeButtonText(negativeButtonText)
        }

        val promptInfo = promptInfoBuilder.build()

        continuation.invokeOnCancellation {
            prompt.cancelAuthentication()
        }

        prompt.authenticate(promptInfo)
    }

    /**
     * Authenticate with crypto object for additional security.
     * Used when protecting cryptographic operations with biometrics.
     */
    suspend fun authenticateWithCrypto(
        activity: FragmentActivity,
        cryptoObject: BiometricPrompt.CryptoObject,
        title: String,
        subtitle: String? = null,
        description: String? = null,
        negativeButtonText: String = "Cancel"
    ): BiometricCryptoResult = suspendCancellableCoroutine { continuation ->
        val executor = ContextCompat.getMainExecutor(activity)

        val callback = object : BiometricPrompt.AuthenticationCallback() {
            override fun onAuthenticationSucceeded(result: BiometricPrompt.AuthenticationResult) {
                if (continuation.isActive) {
                    val crypto = result.cryptoObject
                    if (crypto != null) {
                        continuation.resume(BiometricCryptoResult.Success(crypto))
                    } else {
                        continuation.resume(
                            BiometricCryptoResult.Error(-1, "CryptoObject not returned")
                        )
                    }
                }
            }

            override fun onAuthenticationError(errorCode: Int, errString: CharSequence) {
                if (continuation.isActive) {
                    val result = when (errorCode) {
                        BiometricPrompt.ERROR_USER_CANCELED,
                        BiometricPrompt.ERROR_NEGATIVE_BUTTON -> BiometricCryptoResult.Cancelled
                        BiometricPrompt.ERROR_LOCKOUT -> BiometricCryptoResult.Lockout(temporary = true)
                        BiometricPrompt.ERROR_LOCKOUT_PERMANENT -> BiometricCryptoResult.Lockout(temporary = false)
                        else -> BiometricCryptoResult.Error(errorCode, errString.toString())
                    }
                    continuation.resume(result)
                }
            }

            override fun onAuthenticationFailed() {
                // Prompt stays open for retry
            }
        }

        val prompt = BiometricPrompt(activity, executor, callback)

        val promptInfo = BiometricPrompt.PromptInfo.Builder()
            .setTitle(title)
            .apply {
                subtitle?.let { setSubtitle(it) }
                description?.let { setDescription(it) }
            }
            .setAllowedAuthenticators(BIOMETRIC_STRONG)
            .setNegativeButtonText(negativeButtonText)
            .build()

        continuation.invokeOnCancellation {
            prompt.cancelAuthentication()
        }

        prompt.authenticate(promptInfo, cryptoObject)
    }
}

/**
 * Biometric availability status.
 */
enum class BiometricAvailability {
    AVAILABLE,
    NO_HARDWARE,
    HARDWARE_UNAVAILABLE,
    NOT_ENROLLED,
    SECURITY_UPDATE_REQUIRED,
    UNAVAILABLE
}

/**
 * Result of biometric authentication.
 */
sealed class BiometricResult {
    data class Success(val authenticationType: Int) : BiometricResult() {
        val isBiometric: Boolean
            get() = authenticationType == BiometricPrompt.AUTHENTICATION_RESULT_TYPE_BIOMETRIC
        val isDeviceCredential: Boolean
            get() = authenticationType == BiometricPrompt.AUTHENTICATION_RESULT_TYPE_DEVICE_CREDENTIAL
    }
    object Cancelled : BiometricResult()
    data class Lockout(val temporary: Boolean) : BiometricResult()
    data class Error(val errorCode: Int, val message: String) : BiometricResult()
}

/**
 * Result of biometric authentication with crypto object.
 */
sealed class BiometricCryptoResult {
    data class Success(val cryptoObject: BiometricPrompt.CryptoObject) : BiometricCryptoResult()
    object Cancelled : BiometricCryptoResult()
    data class Lockout(val temporary: Boolean) : BiometricCryptoResult()
    data class Error(val errorCode: Int, val message: String) : BiometricCryptoResult()
}
