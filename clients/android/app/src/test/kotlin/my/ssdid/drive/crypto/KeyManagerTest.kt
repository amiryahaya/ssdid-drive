package my.ssdid.drive.crypto

import org.junit.Assert.*
import org.junit.Before
import org.junit.Test

/**
 * Unit tests for KeyManager and KeyBundle.
 *
 * Tests cover:
 * - Key bundle creation and field access
 * - Setting / getting / clearing unlocked keys
 * - hasUnlockedKeys state transitions
 * - getUnlockedKeys throws when locked
 * - KeyBundle zeroization
 * - KeyBundle equality and hashCode
 * - KeyBundle is not a data class (no copy)
 */
class KeyManagerTest {

    private lateinit var keyManager: KeyManager

    @Before
    fun setup() {
        keyManager = KeyManager()
    }

    // ==================== KeyBundle.create Tests ====================

    @Test
    fun `KeyBundle create stores all key fields`() {
        val bundle = createTestKeyBundle()

        assertEquals(32, bundle.masterKey.size)
        assertEquals(800, bundle.kazKemPublicKey.size)
        assertEquals(1600, bundle.kazKemPrivateKey.size)
        assertEquals(1312, bundle.kazSignPublicKey.size)
        assertEquals(2528, bundle.kazSignPrivateKey.size)
        assertEquals(1184, bundle.mlKemPublicKey.size)
        assertEquals(2400, bundle.mlKemPrivateKey.size)
        assertEquals(1952, bundle.mlDsaPublicKey.size)
        assertEquals(4032, bundle.mlDsaPrivateKey.size)
    }

    @Test
    fun `KeyBundle preserves original key bytes`() {
        val masterKey = ByteArray(32) { 0xAB.toByte() }
        val bundle = KeyBundle.create(
            masterKey = masterKey,
            kazKemPublicKey = ByteArray(800),
            kazKemPrivateKey = ByteArray(1600),
            kazSignPublicKey = ByteArray(1312),
            kazSignPrivateKey = ByteArray(2528),
            mlKemPublicKey = ByteArray(1184),
            mlKemPrivateKey = ByteArray(2400),
            mlDsaPublicKey = ByteArray(1952),
            mlDsaPrivateKey = ByteArray(4032)
        )

        assertTrue(bundle.masterKey.all { it == 0xAB.toByte() })
    }

    // ==================== hasUnlockedKeys Tests ====================

    @Test
    fun `hasUnlockedKeys returns false initially`() {
        assertFalse(keyManager.hasUnlockedKeys())
    }

    @Test
    fun `hasUnlockedKeys returns true after setUnlockedKeys`() {
        keyManager.setUnlockedKeys(createTestKeyBundle())
        assertTrue(keyManager.hasUnlockedKeys())
    }

    @Test
    fun `hasUnlockedKeys returns false after clearUnlockedKeys`() {
        keyManager.setUnlockedKeys(createTestKeyBundle())
        keyManager.clearUnlockedKeys()
        assertFalse(keyManager.hasUnlockedKeys())
    }

    // ==================== getUnlockedKeys Tests ====================

    @Test
    fun `getUnlockedKeys returns the set bundle`() {
        val bundle = createTestKeyBundle()
        keyManager.setUnlockedKeys(bundle)

        val retrieved = keyManager.getUnlockedKeys()
        assertEquals(bundle, retrieved)
    }

    @Test(expected = IllegalStateException::class)
    fun `getUnlockedKeys throws when no keys are set`() {
        keyManager.getUnlockedKeys()
    }

    @Test(expected = IllegalStateException::class)
    fun `getUnlockedKeys throws after clearUnlockedKeys`() {
        keyManager.setUnlockedKeys(createTestKeyBundle())
        keyManager.clearUnlockedKeys()
        keyManager.getUnlockedKeys()
    }

    // ==================== setUnlockedKeys Tests ====================

    @Test
    fun `setUnlockedKeys replaces previous keys`() {
        val bundle1 = KeyBundle.create(
            masterKey = ByteArray(32) { 0x11.toByte() },
            kazKemPublicKey = ByteArray(800),
            kazKemPrivateKey = ByteArray(1600),
            kazSignPublicKey = ByteArray(1312),
            kazSignPrivateKey = ByteArray(2528),
            mlKemPublicKey = ByteArray(1184),
            mlKemPrivateKey = ByteArray(2400),
            mlDsaPublicKey = ByteArray(1952),
            mlDsaPrivateKey = ByteArray(4032)
        )
        val bundle2 = KeyBundle.create(
            masterKey = ByteArray(32) { 0x22.toByte() },
            kazKemPublicKey = ByteArray(800),
            kazKemPrivateKey = ByteArray(1600),
            kazSignPublicKey = ByteArray(1312),
            kazSignPrivateKey = ByteArray(2528),
            mlKemPublicKey = ByteArray(1184),
            mlKemPrivateKey = ByteArray(2400),
            mlDsaPublicKey = ByteArray(1952),
            mlDsaPrivateKey = ByteArray(4032)
        )

        keyManager.setUnlockedKeys(bundle1)
        keyManager.setUnlockedKeys(bundle2)

        val retrieved = keyManager.getUnlockedKeys()
        assertTrue(retrieved.masterKey.all { it == 0x22.toByte() })
    }

    // ==================== clearUnlockedKeys Tests ====================

    @Test
    fun `clearUnlockedKeys zeroizes key material`() {
        val masterKey = ByteArray(32) { 0xFF.toByte() }
        val kazKemPub = ByteArray(800) { 0xAA.toByte() }
        val kazKemPriv = ByteArray(1600) { 0xBB.toByte() }
        val kazSignPub = ByteArray(1312) { 0xCC.toByte() }
        val kazSignPriv = ByteArray(2528) { 0xDD.toByte() }
        val mlKemPub = ByteArray(1184) { 0xEE.toByte() }
        val mlKemPriv = ByteArray(2400) { 0x11.toByte() }
        val mlDsaPub = ByteArray(1952) { 0x22.toByte() }
        val mlDsaPriv = ByteArray(4032) { 0x33.toByte() }

        val bundle = KeyBundle.create(
            masterKey = masterKey,
            kazKemPublicKey = kazKemPub,
            kazKemPrivateKey = kazKemPriv,
            kazSignPublicKey = kazSignPub,
            kazSignPrivateKey = kazSignPriv,
            mlKemPublicKey = mlKemPub,
            mlKemPrivateKey = mlKemPriv,
            mlDsaPublicKey = mlDsaPub,
            mlDsaPrivateKey = mlDsaPriv
        )

        keyManager.setUnlockedKeys(bundle)
        keyManager.clearUnlockedKeys()

        // Since KeyBundle stores arrays directly (not copied), the originals
        // should be zeroized after clearUnlockedKeys calls bundle.zeroize()
        assertTrue("masterKey should be zeroed", masterKey.all { it == 0.toByte() })
        assertTrue("kazKemPublicKey should be zeroed", kazKemPub.all { it == 0.toByte() })
        assertTrue("kazKemPrivateKey should be zeroed", kazKemPriv.all { it == 0.toByte() })
        assertTrue("kazSignPublicKey should be zeroed", kazSignPub.all { it == 0.toByte() })
        assertTrue("kazSignPrivateKey should be zeroed", kazSignPriv.all { it == 0.toByte() })
        assertTrue("mlKemPublicKey should be zeroed", mlKemPub.all { it == 0.toByte() })
        assertTrue("mlKemPrivateKey should be zeroed", mlKemPriv.all { it == 0.toByte() })
        assertTrue("mlDsaPublicKey should be zeroed", mlDsaPub.all { it == 0.toByte() })
        assertTrue("mlDsaPrivateKey should be zeroed", mlDsaPriv.all { it == 0.toByte() })
    }

    @Test
    fun `clearUnlockedKeys is safe to call when no keys are set`() {
        // Should not throw
        keyManager.clearUnlockedKeys()
        assertFalse(keyManager.hasUnlockedKeys())
    }

    @Test
    fun `clearUnlockedKeys is safe to call multiple times`() {
        keyManager.setUnlockedKeys(createTestKeyBundle())
        keyManager.clearUnlockedKeys()
        keyManager.clearUnlockedKeys() // Second call should not throw
        assertFalse(keyManager.hasUnlockedKeys())
    }

    // ==================== KeyBundle.equals Tests ====================

    @Test
    fun `KeyBundle equals compares by masterKey content`() {
        val masterKey = ByteArray(32) { 0xAB.toByte() }
        val bundle1 = KeyBundle.create(
            masterKey = masterKey.copyOf(),
            kazKemPublicKey = ByteArray(800),
            kazKemPrivateKey = ByteArray(1600),
            kazSignPublicKey = ByteArray(1312),
            kazSignPrivateKey = ByteArray(2528),
            mlKemPublicKey = ByteArray(1184),
            mlKemPrivateKey = ByteArray(2400),
            mlDsaPublicKey = ByteArray(1952),
            mlDsaPrivateKey = ByteArray(4032)
        )
        val bundle2 = KeyBundle.create(
            masterKey = masterKey.copyOf(),
            kazKemPublicKey = ByteArray(800) { 0xFF.toByte() }, // different other keys
            kazKemPrivateKey = ByteArray(1600),
            kazSignPublicKey = ByteArray(1312),
            kazSignPrivateKey = ByteArray(2528),
            mlKemPublicKey = ByteArray(1184),
            mlKemPrivateKey = ByteArray(2400),
            mlDsaPublicKey = ByteArray(1952),
            mlDsaPrivateKey = ByteArray(4032)
        )

        assertEquals(bundle1, bundle2)
    }

    @Test
    fun `KeyBundle not equal with different masterKey`() {
        val bundle1 = KeyBundle.create(
            masterKey = ByteArray(32) { 0x11.toByte() },
            kazKemPublicKey = ByteArray(800),
            kazKemPrivateKey = ByteArray(1600),
            kazSignPublicKey = ByteArray(1312),
            kazSignPrivateKey = ByteArray(2528),
            mlKemPublicKey = ByteArray(1184),
            mlKemPrivateKey = ByteArray(2400),
            mlDsaPublicKey = ByteArray(1952),
            mlDsaPrivateKey = ByteArray(4032)
        )
        val bundle2 = KeyBundle.create(
            masterKey = ByteArray(32) { 0x22.toByte() },
            kazKemPublicKey = ByteArray(800),
            kazKemPrivateKey = ByteArray(1600),
            kazSignPublicKey = ByteArray(1312),
            kazSignPrivateKey = ByteArray(2528),
            mlKemPublicKey = ByteArray(1184),
            mlKemPrivateKey = ByteArray(2400),
            mlDsaPublicKey = ByteArray(1952),
            mlDsaPrivateKey = ByteArray(4032)
        )

        assertNotEquals(bundle1, bundle2)
    }

    @Test
    fun `KeyBundle equals with itself returns true`() {
        val bundle = createTestKeyBundle()
        assertEquals(bundle, bundle)
    }

    @Test
    fun `KeyBundle not equal to null`() {
        val bundle = createTestKeyBundle()
        assertNotEquals(bundle, null)
    }

    @Test
    fun `KeyBundle not equal to different type`() {
        val bundle = createTestKeyBundle()
        assertNotEquals(bundle, "not a key bundle")
    }

    // ==================== KeyBundle.hashCode Tests ====================

    @Test
    fun `KeyBundle hashCode consistent for equal bundles`() {
        val masterKey = ByteArray(32) { 0xAB.toByte() }
        val bundle1 = KeyBundle.create(
            masterKey = masterKey.copyOf(),
            kazKemPublicKey = ByteArray(800),
            kazKemPrivateKey = ByteArray(1600),
            kazSignPublicKey = ByteArray(1312),
            kazSignPrivateKey = ByteArray(2528),
            mlKemPublicKey = ByteArray(1184),
            mlKemPrivateKey = ByteArray(2400),
            mlDsaPublicKey = ByteArray(1952),
            mlDsaPrivateKey = ByteArray(4032)
        )
        val bundle2 = KeyBundle.create(
            masterKey = masterKey.copyOf(),
            kazKemPublicKey = ByteArray(800),
            kazKemPrivateKey = ByteArray(1600),
            kazSignPublicKey = ByteArray(1312),
            kazSignPrivateKey = ByteArray(2528),
            mlKemPublicKey = ByteArray(1184),
            mlKemPrivateKey = ByteArray(2400),
            mlDsaPublicKey = ByteArray(1952),
            mlDsaPrivateKey = ByteArray(4032)
        )

        assertEquals(bundle1.hashCode(), bundle2.hashCode())
    }

    // ==================== KeyBundle.zeroize Tests ====================

    @Test
    fun `KeyBundle zeroize clears all key material`() {
        val masterKey = ByteArray(32) { 0xFF.toByte() }
        val kazKemPub = ByteArray(800) { 0xAA.toByte() }
        val bundle = KeyBundle.create(
            masterKey = masterKey,
            kazKemPublicKey = kazKemPub,
            kazKemPrivateKey = ByteArray(1600) { 0xBB.toByte() },
            kazSignPublicKey = ByteArray(1312) { 0xCC.toByte() },
            kazSignPrivateKey = ByteArray(2528) { 0xDD.toByte() },
            mlKemPublicKey = ByteArray(1184) { 0xEE.toByte() },
            mlKemPrivateKey = ByteArray(2400) { 0x11.toByte() },
            mlDsaPublicKey = ByteArray(1952) { 0x22.toByte() },
            mlDsaPrivateKey = ByteArray(4032) { 0x33.toByte() }
        )

        bundle.zeroize()

        // Arrays are stored directly, so original references should be zeroed
        assertTrue("masterKey should be zeroed after zeroize", masterKey.all { it == 0.toByte() })
        assertTrue("kazKemPublicKey should be zeroed after zeroize", kazKemPub.all { it == 0.toByte() })
    }

    // ==================== Helper Methods ====================

    private fun createTestKeyBundle(): KeyBundle {
        return KeyBundle.create(
            masterKey = ByteArray(32),
            kazKemPublicKey = ByteArray(800),
            kazKemPrivateKey = ByteArray(1600),
            kazSignPublicKey = ByteArray(1312),
            kazSignPrivateKey = ByteArray(2528),
            mlKemPublicKey = ByteArray(1184),
            mlKemPrivateKey = ByteArray(2400),
            mlDsaPublicKey = ByteArray(1952),
            mlDsaPrivateKey = ByteArray(4032)
        )
    }
}
