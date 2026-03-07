package my.ssdid.drive.crypto

import android.app.ActivityManager
import android.content.Context
import java.security.SecureRandom

/**
 * Tiered KDF profile for password-based key derivation.
 *
 * Wire format: [profile_byte] || [salt_bytes (16 bytes)]
 * Profile is selected based on device RAM to balance security and usability.
 */
enum class KdfProfile(val profileByte: Byte) {
    /** argon2id-standard: 64 MiB, t=3, p=4 — Desktop and modern mobile (4+ GB RAM) */
    ARGON2ID_STANDARD(0x01),

    /** argon2id-low: 19 MiB, t=4, p=4 — Older mobile (2-4 GB RAM) */
    ARGON2ID_LOW(0x02),

    /** bcrypt-hkdf: bcrypt cost=13 + HKDF-SHA-384 — Extremely constrained (< 2 GB RAM) */
    BCRYPT_HKDF(0x03);

    companion object {
        /** Salt size (random bytes, excluding profile byte) */
        const val SALT_SIZE = 16

        /** Total wire salt size: 1 profile byte + 16 salt bytes */
        const val WIRE_SALT_SIZE = 17

        /** Parse profile from wire byte */
        fun fromByte(byte: Byte): KdfProfile =
            entries.firstOrNull { it.profileByte == byte }
                ?: throw KeyDerivationException("Unknown KDF profile byte: 0x${byte.toUByte().toString(16)}")

        /** Select optimal KDF profile based on device available RAM */
        fun selectForDevice(context: Context): KdfProfile {
            val activityManager = context.getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager
            val memInfo = ActivityManager.MemoryInfo()
            activityManager.getMemoryInfo(memInfo)
            val totalRamGB = memInfo.totalMem / (1024.0 * 1024.0 * 1024.0)

            return when {
                totalRamGB >= 4.0 -> ARGON2ID_STANDARD
                totalRamGB >= 2.0 -> ARGON2ID_LOW
                else -> BCRYPT_HKDF
            }
        }

        /** Create a salt with profile byte prepended: [profile_byte] || [16 random bytes] */
        fun createSaltWithProfile(profile: KdfProfile): ByteArray {
            val salt = ByteArray(WIRE_SALT_SIZE)
            salt[0] = profile.profileByte
            val randomBytes = ByteArray(SALT_SIZE)
            SecureRandom().nextBytes(randomBytes)
            System.arraycopy(randomBytes, 0, salt, 1, SALT_SIZE)
            return salt
        }

        /** Check if a salt uses the tiered format (17 bytes with valid profile byte) */
        fun isTieredSalt(salt: ByteArray): Boolean {
            if (salt.size != WIRE_SALT_SIZE) return false
            return salt[0] in 0x01..0x03
        }
    }
}
