package my.ssdid.drive.domain.model

/**
 * Domain model representing a device enrollment.
 *
 * Each enrollment represents a user's cryptographic binding to a physical device.
 * Multiple users can have separate enrollments on the same physical device.
 */
data class DeviceEnrollment(
    val id: String,
    val deviceId: String,
    val deviceName: String?,
    val status: DeviceEnrollmentStatus,
    val keyAlgorithm: DeviceKeyAlgorithm,
    val enrolledAt: String,
    val lastUsedAt: String?,
    val device: Device?
) {
    /**
     * Check if this enrollment is active and can be used.
     */
    val isActive: Boolean
        get() = status == DeviceEnrollmentStatus.ACTIVE && device?.status == DeviceStatus.ACTIVE
}

/**
 * Domain model representing a physical device.
 */
data class Device(
    val id: String,
    val deviceFingerprint: String,
    val platform: DevicePlatform,
    val deviceInfo: DeviceInfo?,
    val status: DeviceStatus,
    val trustLevel: DeviceTrustLevel,
    val createdAt: String
)

/**
 * Device information metadata.
 */
data class DeviceInfo(
    val model: String,
    val manufacturer: String,
    val osVersion: String,
    val appVersion: String,
    val sdkVersion: Int
)

/**
 * Device enrollment status.
 */
enum class DeviceEnrollmentStatus {
    ACTIVE,
    REVOKED;

    companion object {
        fun fromString(value: String): DeviceEnrollmentStatus {
            return when (value.lowercase()) {
                "active" -> ACTIVE
                "revoked" -> REVOKED
                else -> REVOKED
            }
        }
    }
}

/**
 * Physical device status.
 */
enum class DeviceStatus {
    ACTIVE,
    SUSPENDED;

    companion object {
        fun fromString(value: String): DeviceStatus {
            return when (value.lowercase()) {
                "active" -> ACTIVE
                "suspended" -> SUSPENDED
                else -> SUSPENDED
            }
        }
    }
}

/**
 * Device platform type.
 */
enum class DevicePlatform {
    ANDROID,
    IOS,
    WINDOWS,
    MACOS,
    LINUX,
    OTHER;

    companion object {
        fun fromString(value: String): DevicePlatform {
            return when (value.lowercase()) {
                "android" -> ANDROID
                "ios" -> IOS
                "windows" -> WINDOWS
                "macos" -> MACOS
                "linux" -> LINUX
                else -> OTHER
            }
        }
    }
}

/**
 * Device trust level (determined by attestation).
 */
enum class DeviceTrustLevel {
    HIGH,
    MEDIUM,
    LOW;

    companion object {
        fun fromString(value: String): DeviceTrustLevel {
            return when (value.lowercase()) {
                "high" -> HIGH
                "medium" -> MEDIUM
                "low" -> LOW
                else -> LOW
            }
        }
    }
}

/**
 * Key algorithm used for device signing.
 */
enum class DeviceKeyAlgorithm {
    KAZ_SIGN,
    ML_DSA;

    companion object {
        fun fromString(value: String): DeviceKeyAlgorithm {
            return when (value.lowercase()) {
                "kaz_sign" -> KAZ_SIGN
                "ml_dsa" -> ML_DSA
                else -> KAZ_SIGN
            }
        }
    }

    fun toApiString(): String {
        return when (this) {
            KAZ_SIGN -> "kaz_sign"
            ML_DSA -> "ml_dsa"
        }
    }
}
