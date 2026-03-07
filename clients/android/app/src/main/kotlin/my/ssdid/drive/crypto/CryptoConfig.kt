package my.ssdid.drive.crypto

import javax.inject.Inject
import javax.inject.Singleton

/**
 * Post-quantum cryptography algorithm options.
 *
 * - KAZ: KAZ-KEM + KAZ-SIGN (Malaysian algorithms)
 * - NIST: ML-KEM-768 + ML-DSA-65 (NIST FIPS 203/204)
 * - HYBRID: Both KAZ and NIST combined for defense in depth
 */
enum class PqcAlgorithm {
    KAZ,
    NIST,
    HYBRID;

    companion object {
        /**
         * Parse algorithm from server response string.
         */
        fun fromString(value: String?): PqcAlgorithm {
            return when (value?.lowercase()) {
                "kaz" -> KAZ
                "nist" -> NIST
                "hybrid" -> HYBRID
                else -> KAZ // Default to KAZ
            }
        }
    }
}

/**
 * Configuration for cryptographic algorithm selection.
 *
 * This class manages the tenant's PQC algorithm preference and provides
 * helper methods to determine which algorithms should be used for
 * encryption, key encapsulation, and signatures.
 *
 * ## Algorithm Selection
 *
 * - **KAZ**: Use only KAZ-KEM and KAZ-SIGN
 * - **NIST**: Use only ML-KEM-768 and ML-DSA-65
 * - **HYBRID**: Use both algorithm families combined for defense in depth
 *
 * ## Usage
 *
 * ```kotlin
 * val config = cryptoConfig
 * config.setAlgorithm(PqcAlgorithm.HYBRID)
 *
 * if (config.useKazKem()) {
 *     // Perform KAZ-KEM operations
 * }
 * if (config.useMlKem()) {
 *     // Perform ML-KEM operations
 * }
 * ```
 */
@Singleton
class CryptoConfig @Inject constructor() {

    /**
     * Current PQC algorithm selection.
     * Defaults to KAZ for backward compatibility.
     */
    @Volatile
    private var algorithm: PqcAlgorithm = PqcAlgorithm.KAZ

    /**
     * Get the current algorithm setting.
     */
    fun getAlgorithm(): PqcAlgorithm = algorithm

    /**
     * Set the algorithm from tenant configuration.
     */
    fun setAlgorithm(algo: PqcAlgorithm) {
        algorithm = algo
    }

    /**
     * Set the algorithm from a string value (from server response).
     */
    fun setAlgorithmFromString(value: String?) {
        algorithm = PqcAlgorithm.fromString(value)
    }

    // ==================== KEM Algorithm Selection ====================

    /**
     * Whether to use KAZ-KEM for key encapsulation.
     * True for KAZ and HYBRID modes.
     */
    fun useKazKem(): Boolean = algorithm == PqcAlgorithm.KAZ || algorithm == PqcAlgorithm.HYBRID

    /**
     * Whether to use ML-KEM for key encapsulation.
     * True for NIST and HYBRID modes.
     */
    fun useMlKem(): Boolean = algorithm == PqcAlgorithm.NIST || algorithm == PqcAlgorithm.HYBRID

    /**
     * Whether to use combined KEM (both algorithms).
     * True only for HYBRID mode.
     */
    fun useCombinedKem(): Boolean = algorithm == PqcAlgorithm.HYBRID

    // ==================== Signature Algorithm Selection ====================

    /**
     * Whether to use KAZ-SIGN for signatures.
     * True for KAZ and HYBRID modes.
     */
    fun useKazSign(): Boolean = algorithm == PqcAlgorithm.KAZ || algorithm == PqcAlgorithm.HYBRID

    /**
     * Whether to use ML-DSA for signatures.
     * True for NIST and HYBRID modes.
     */
    fun useMlDsa(): Boolean = algorithm == PqcAlgorithm.NIST || algorithm == PqcAlgorithm.HYBRID

    /**
     * Whether to use combined signatures (both algorithms).
     * True only for HYBRID mode.
     */
    fun useCombinedSignature(): Boolean = algorithm == PqcAlgorithm.HYBRID

    // ==================== Key Generation ====================

    /**
     * Whether to generate KAZ key pairs during registration/key rotation.
     * True for KAZ and HYBRID modes.
     */
    fun generateKazKeys(): Boolean = algorithm == PqcAlgorithm.KAZ || algorithm == PqcAlgorithm.HYBRID

    /**
     * Whether to generate NIST key pairs during registration/key rotation.
     * True for NIST and HYBRID modes.
     */
    fun generateNistKeys(): Boolean = algorithm == PqcAlgorithm.NIST || algorithm == PqcAlgorithm.HYBRID

    /**
     * Check if the current configuration requires all four key pairs.
     */
    fun requiresAllKeyPairs(): Boolean = algorithm == PqcAlgorithm.HYBRID

    override fun toString(): String = "CryptoConfig(algorithm=$algorithm)"
}
