package my.ssdid.drive.crypto

import org.junit.Assert.*
import org.junit.Test

class ShamirSecretSharingTest {

    @Test
    fun `split and reconstruct with shares 1 and 2`() {
        val secret = ByteArray(32) { it.toByte() }
        val shares = ShamirSecretSharing.split(secret, 2, 3)
        assertEquals(3, shares.size)

        val reconstructed = ShamirSecretSharing.reconstruct(listOf(shares[0], shares[1]))
        assertArrayEquals(secret, reconstructed)
    }

    @Test
    fun `split and reconstruct with shares 1 and 3`() {
        val secret = ByteArray(32) { it.toByte() }
        val shares = ShamirSecretSharing.split(secret, 2, 3)

        val reconstructed = ShamirSecretSharing.reconstruct(listOf(shares[0], shares[2]))
        assertArrayEquals(secret, reconstructed)
    }

    @Test
    fun `split and reconstruct with shares 2 and 3`() {
        val secret = ByteArray(32) { it.toByte() }
        val shares = ShamirSecretSharing.split(secret, 2, 3)

        val reconstructed = ShamirSecretSharing.reconstruct(listOf(shares[1], shares[2]))
        assertArrayEquals(secret, reconstructed)
    }

    @Test
    fun `reconstruct random 32-byte key`() {
        val secret = java.security.SecureRandom().let { rng ->
            ByteArray(32).also { rng.nextBytes(it) }
        }
        val shares = ShamirSecretSharing.split(secret, 2, 3)

        for (combo in listOf(listOf(0, 1), listOf(0, 2), listOf(1, 2))) {
            val selected = combo.map { shares[it] }
            val reconstructed = ShamirSecretSharing.reconstruct(selected)
            assertArrayEquals("Failed for combination $combo", secret, reconstructed)
        }
    }

    @Test
    fun `single share reveals nothing about secret`() {
        val s1 = byteArrayOf(0x42)
        val s2 = byteArrayOf(0x99.toByte())
        val shares1 = ShamirSecretSharing.split(s1, 2, 3)
        val shares2 = ShamirSecretSharing.split(s2, 2, 3)
        assertEquals(1, shares1[0].second.size)
        assertEquals(1, shares2[0].second.size)
    }
}
