package com.securesharing.crypto

import org.bouncycastle.crypto.generators.Argon2BytesGenerator
import org.bouncycastle.crypto.generators.BCrypt
import org.bouncycastle.crypto.params.Argon2Parameters
import org.bouncycastle.crypto.digests.SHA384Digest
import org.bouncycastle.crypto.generators.HKDFBytesGenerator
import org.bouncycastle.crypto.params.HKDFParameters
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class KdfProfileTest {

    // ==================== Profile Byte Tests ====================

    @Test
    fun `profile bytes match spec`() {
        assertEquals(0x01.toByte(), KdfProfile.ARGON2ID_STANDARD.profileByte)
        assertEquals(0x02.toByte(), KdfProfile.ARGON2ID_LOW.profileByte)
        assertEquals(0x03.toByte(), KdfProfile.BCRYPT_HKDF.profileByte)
    }

    @Test
    fun `fromByte roundtrip for all profiles`() {
        for (profile in KdfProfile.entries) {
            val parsed = KdfProfile.fromByte(profile.profileByte)
            assertEquals(profile, parsed)
        }
    }

    @Test(expected = CryptoException::class)
    fun `fromByte throws for invalid byte 0x00`() {
        KdfProfile.fromByte(0x00)
    }

    @Test(expected = CryptoException::class)
    fun `fromByte throws for invalid byte 0x04`() {
        KdfProfile.fromByte(0x04)
    }

    // ==================== Salt Creation Tests ====================

    @Test
    fun `createSaltWithProfile produces correct size`() {
        for (profile in KdfProfile.entries) {
            val salt = KdfProfile.createSaltWithProfile(profile)
            assertEquals(KdfProfile.WIRE_SALT_SIZE, salt.size)
        }
    }

    @Test
    fun `createSaltWithProfile prepends correct profile byte`() {
        for (profile in KdfProfile.entries) {
            val salt = KdfProfile.createSaltWithProfile(profile)
            assertEquals(profile.profileByte, salt[0])
        }
    }

    @Test
    fun `createSaltWithProfile produces unique salts`() {
        val salt1 = KdfProfile.createSaltWithProfile(KdfProfile.ARGON2ID_STANDARD)
        val salt2 = KdfProfile.createSaltWithProfile(KdfProfile.ARGON2ID_STANDARD)
        // Random salts should differ (extremely unlikely to collide)
        assertFalse(salt1.contentEquals(salt2))
    }

    // ==================== Tiered Salt Detection Tests ====================

    @Test
    fun `isTieredSalt returns true for valid tiered salts`() {
        for (profile in KdfProfile.entries) {
            val salt = KdfProfile.createSaltWithProfile(profile)
            assertTrue(KdfProfile.isTieredSalt(salt))
        }
    }

    @Test
    fun `isTieredSalt returns false for legacy 32-byte salt`() {
        val legacySalt = ByteArray(32) { it.toByte() }
        assertFalse(KdfProfile.isTieredSalt(legacySalt))
    }

    @Test
    fun `isTieredSalt returns false for legacy 16-byte salt`() {
        val legacySalt = ByteArray(16) { it.toByte() }
        assertFalse(KdfProfile.isTieredSalt(legacySalt))
    }

    @Test
    fun `isTieredSalt returns false for 17-byte salt with invalid profile byte`() {
        val invalidSalt = ByteArray(17) { 0x00 }
        assertFalse(KdfProfile.isTieredSalt(invalidSalt))
    }

    // ==================== Cross-Platform Test Vector Assertions ====================
    // These test vectors are from docs/crypto/07-test-vectors.md sections 5.2-5.4.
    // All platforms MUST produce identical output for the same inputs.

    private val testPassword = "correct horse battery staple".toByteArray()
    private val testSalt = byteArrayOf(
        0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08,
        0x09, 0x0a, 0x0b, 0x0c, 0x0d, 0x0e, 0x0f, 0x10
    )

    private fun ByteArray.toHex(): String = joinToString("") { "%02x".format(it) }

    @Suppress("SameParameterValue")
    private fun hexToBytes(hex: String): ByteArray {
        val len = hex.length
        val data = ByteArray(len / 2)
        for (i in 0 until len step 2) {
            data[i / 2] = ((Character.digit(hex[i], 16) shl 4) +
                    Character.digit(hex[i + 1], 16)).toByte()
        }
        return data
    }

    @Test
    fun `test vector 5_2 argon2id-standard matches reference`() {
        val params = Argon2Parameters.Builder(Argon2Parameters.ARGON2_id)
            .withSalt(testSalt)
            .withMemoryAsKB(65536)
            .withIterations(3)
            .withParallelism(4)
            .build()

        val generator = Argon2BytesGenerator()
        generator.init(params)

        val output = ByteArray(32)
        generator.generateBytes(testPassword, output)

        assertEquals(
            "6ec690471257037ee9c75b275e6161c1c2f4335ab541400534dba6769a444397",
            output.toHex()
        )
    }

    @Test
    fun `test vector 5_3 argon2id-low matches reference`() {
        val params = Argon2Parameters.Builder(Argon2Parameters.ARGON2_id)
            .withSalt(testSalt)
            .withMemoryAsKB(19456)
            .withIterations(4)
            .withParallelism(4)
            .build()

        val generator = Argon2BytesGenerator()
        generator.init(params)

        val output = ByteArray(32)
        generator.generateBytes(testPassword, output)

        assertEquals(
            "1025994eae82eff51c942eed6294d085a1d43526998ed20e22c1f63e1c592a88",
            output.toHex()
        )
    }

    @Test
    fun `test vector 5_4 bcrypt-hkdf matches reference`() {
        // Step 1: Bcrypt (cost=13)
        val bcryptOutput = BCrypt.generate(testPassword, testSalt, 13)
        assertEquals(
            "b0bd8f45c23e9c8e41705c842a997336cd987356fbf235e2",
            bcryptOutput.toHex()
        )

        // Step 2: HKDF-SHA-384 stretch to 32 bytes
        val hkdfSalt = "SecureSharing-Bcrypt-KDF-v1".toByteArray()
        val hkdfInfo = "bcrypt-derived-key".toByteArray()
        val hkdf = HKDFBytesGenerator(SHA384Digest())
        hkdf.init(HKDFParameters(bcryptOutput, hkdfSalt, hkdfInfo))
        val derivedKey = ByteArray(32)
        hkdf.generateBytes(derivedKey, 0, 32)

        assertEquals(
            "eb9ffe4aa76d3cd79851cd1de39dbfa8ced4ad88b0eec1596c214bb733618279",
            derivedKey.toHex()
        )
    }
}
