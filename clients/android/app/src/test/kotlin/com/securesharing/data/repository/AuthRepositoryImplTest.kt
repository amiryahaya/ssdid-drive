package com.securesharing.data.repository

import android.content.Context
import android.util.Base64
import com.securesharing.crypto.CryptoConfig
import com.securesharing.crypto.KdfProfile
import com.securesharing.crypto.CryptoManager
import com.securesharing.crypto.FolderKeyManager
import com.securesharing.crypto.KeyBundle
import com.securesharing.crypto.KeyManager
import com.securesharing.data.local.SecureStorage
import com.securesharing.crypto.DeviceManager
import com.securesharing.util.CacheManager
import com.securesharing.util.Logger
import com.securesharing.util.PushNotificationManager
import com.securesharing.data.remote.ApiService
import com.securesharing.data.remote.dto.AuthResponse
import com.securesharing.data.remote.dto.AuthResponseData
import com.securesharing.data.remote.dto.PublicKeysDto
import com.securesharing.data.remote.dto.UserDto
import com.securesharing.data.remote.dto.UserResponse
import com.securesharing.data.remote.dto.UpdateKeyMaterialRequest
import com.securesharing.data.remote.dto.UserResponse
import com.securesharing.util.AppException
import com.securesharing.util.Result
import io.mockk.*
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.test.runTest
import okhttp3.ResponseBody.Companion.toResponseBody
import org.junit.After
import org.junit.Assert.*
import org.junit.Before
import org.junit.Test
import retrofit2.Response

/**
 * Unit tests for AuthRepositoryImpl.
 *
 * Tests cover:
 * - Login success and failure scenarios
 * - Registration with key generation
 * - Token refresh
 * - Logout and cleanup
 * - Error handling
 */
@OptIn(ExperimentalCoroutinesApi::class)
class AuthRepositoryImplTest {

    private lateinit var context: Context
    private lateinit var apiService: ApiService
    private lateinit var secureStorage: SecureStorage
    private lateinit var cryptoManager: CryptoManager
    private lateinit var keyManager: KeyManager
    private lateinit var cryptoConfig: CryptoConfig
    private lateinit var folderKeyManager: FolderKeyManager
    private lateinit var deviceManager: DeviceManager
    private lateinit var cacheManager: CacheManager
    private lateinit var pushNotificationManager: PushNotificationManager
    private lateinit var authRepository: AuthRepositoryImpl

    private val testEmail = "test@example.com"
    private val testPassword = "password123".toCharArray()
    private val testTenant = "test-tenant"
    private val testUserId = "user-123"
    private val testAccessToken = "access-token-123"
    private val testRefreshToken = "refresh-token-456"

    @Before
    fun setup() {
        // Mock static Base64 methods
        mockkStatic(Base64::class)
        every { Base64.decode(any<String>(), any()) } returns ByteArray(32)
        every { Base64.encodeToString(any(), any()) } returns "base64encoded"

        // Mock Logger to avoid android.util.Log calls in unit tests
        mockkObject(Logger)
        every { Logger.d(any(), any(), any()) } just Runs
        every { Logger.i(any(), any(), any()) } just Runs
        every { Logger.w(any(), any(), any()) } just Runs
        every { Logger.e(any(), any(), any()) } just Runs

        // Mock KdfProfile static methods (uses Android ActivityManager in real code)
        mockkObject(KdfProfile.Companion)
        every { KdfProfile.selectForDevice(any()) } returns KdfProfile.ARGON2ID_STANDARD
        every { KdfProfile.createSaltWithProfile(any()) } returns ByteArray(17).also { it[0] = 0x01 }

        context = mockk(relaxed = true)
        apiService = mockk()
        secureStorage = mockk(relaxed = true)
        cryptoManager = mockk()
        keyManager = mockk(relaxed = true)
        cryptoConfig = mockk(relaxed = true)
        folderKeyManager = mockk(relaxed = true)
        deviceManager = mockk(relaxed = true)
        cacheManager = mockk(relaxed = true)
        pushNotificationManager = mockk(relaxed = true)

        authRepository = AuthRepositoryImpl(
            context = context,
            apiService = apiService,
            secureStorage = secureStorage,
            cryptoManager = cryptoManager,
            keyManager = keyManager,
            cryptoConfig = cryptoConfig,
            folderKeyManager = folderKeyManager,
            deviceManager = deviceManager,
            cacheManager = cacheManager,
            pushNotificationManager = pushNotificationManager
        )
    }

    @After
    fun tearDown() {
        unmockkStatic(Base64::class)
        unmockkObject(Logger)
        unmockkObject(KdfProfile.Companion)
    }

    // ==================== isAuthenticated Tests ====================

    @Test
    fun `isAuthenticated returns true when tokens exist`() = runTest {
        coEvery { secureStorage.hasValidTokens() } returns true

        val result = authRepository.isAuthenticated()

        assertTrue(result)
        coVerify { secureStorage.hasValidTokens() }
    }

    @Test
    fun `isAuthenticated returns false when no tokens`() = runTest {
        coEvery { secureStorage.hasValidTokens() } returns false

        val result = authRepository.isAuthenticated()

        assertFalse(result)
    }

    // ==================== Login Tests ====================

    @Test
    fun `login success saves tokens and returns user`() = runTest {
        val userDto = createTestUserDto()
        val authResponse = AuthResponse(
            data = AuthResponseData(
                accessToken = testAccessToken,
                refreshToken = testRefreshToken,
                expiresIn = 3600,
                tokenType = "Bearer",
                user = userDto
            )
        )

        coEvery { apiService.login(any()) } returns Response.success(authResponse)
        coEvery { apiService.getTenantConfig() } returns Response.success(mockk(relaxed = true))
        coEvery { secureStorage.getEncryptedMasterKey() } returns ByteArray(32)
        coEvery { secureStorage.getEncryptedPrivateKeys() } returns ByteArray(100)
        coEvery { secureStorage.getKeyDerivationSalt() } returns ByteArray(16)
        every { cryptoManager.deriveKeyWithProfile(any(), any()) } returns ByteArray(32)
        every { cryptoManager.decryptAesGcm(any(), any()) } returns ByteArray(32)
        every { keyManager.deserializePrivateKeys(any(), any()) } returns mockk<KeyBundle>()

        val result = authRepository.login(testEmail, testPassword, testTenant)

        assertTrue(result is Result.Success)
        coVerify { secureStorage.saveTokens(testAccessToken, testRefreshToken) }
        coVerify { secureStorage.saveUserId(testUserId) }
    }

    @Test
    fun `login with invalid credentials returns error`() = runTest {
        coEvery { apiService.login(any()) } returns Response.error(
            401,
            "Unauthorized".toResponseBody()
        )

        val result = authRepository.login(testEmail, testPassword, testTenant)

        assertTrue(result is Result.Error)
        val error = (result as Result.Error).exception
        assertTrue(error is AppException.Unauthorized)
    }

    @Test
    fun `login with network error returns network exception`() = runTest {
        coEvery { apiService.login(any()) } throws java.io.IOException("Network error")

        val result = authRepository.login(testEmail, testPassword, testTenant)

        assertTrue(result is Result.Error)
        val error = (result as Result.Error).exception
        assertTrue(error is AppException.Network)
    }

    @Test
    fun `login zeroizes password after use`() = runTest {
        val password = "testpass".toCharArray()
        coEvery { apiService.login(any()) } returns Response.error(401, "".toResponseBody())

        authRepository.login(testEmail, password, testTenant)

        // Verify password was zeroized (all chars should be null)
        assertTrue(password.all { it == '\u0000' })
    }

    // ==================== Registration Tests ====================

    @Test
    fun `register generates keys and saves user data`() = runTest {
        val userDto = createTestUserDto()
        val authResponse = AuthResponse(
            data = AuthResponseData(
                accessToken = testAccessToken,
                refreshToken = testRefreshToken,
                expiresIn = 3600,
                tokenType = "Bearer",
                user = userDto
            )
        )

        // Mock key generation
        val mockKeyBundle = KeyBundle.create(
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
        every { keyManager.generateKeyBundle() } returns mockKeyBundle
        every { cryptoManager.generateRandom(any()) } returns ByteArray(32)
        every { cryptoManager.deriveKeyWithProfile(any(), any()) } returns ByteArray(32)
        every { cryptoManager.encryptAesGcm(any(), any()) } returns ByteArray(64)
        every { keyManager.serializePrivateKeys(any()) } returns ByteArray(100)
        coEvery { apiService.register(any()) } returns Response.success(authResponse)
        coEvery { apiService.getTenantConfig() } returns Response.success(mockk(relaxed = true))

        val result = authRepository.register(testEmail, testPassword, testTenant)

        assertTrue(result is Result.Success)
        coVerify { secureStorage.saveTokens(testAccessToken, testRefreshToken) }
        coVerify { secureStorage.saveEncryptedMasterKey(any()) }
        coVerify { secureStorage.saveEncryptedPrivateKeys(any()) }
        coVerify { secureStorage.saveKeyDerivationSalt(any()) }
    }

    @Test
    fun `register with duplicate email returns validation error`() = runTest {
        // Mock key generation
        val mockKeyBundle = KeyBundle.create(
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
        every { keyManager.generateKeyBundle() } returns mockKeyBundle
        every { cryptoManager.generateRandom(any()) } returns ByteArray(32)
        every { cryptoManager.deriveKeyWithProfile(any(), any()) } returns ByteArray(32)
        every { cryptoManager.encryptAesGcm(any(), any()) } returns ByteArray(64)
        every { keyManager.serializePrivateKeys(any()) } returns ByteArray(100)
        coEvery { apiService.register(any()) } returns Response.error(
            409,
            "Email already registered".toResponseBody()
        )

        val result = authRepository.register(testEmail, testPassword, testTenant)

        assertTrue(result is Result.Error)
        val error = (result as Result.Error).exception
        assertTrue(error is AppException.ValidationError)
    }

    // ==================== Logout Tests ====================

    @Test
    fun `logout clears all local data`() = runTest {
        coEvery { apiService.logout() } returns Response.success(Unit)

        val result = authRepository.logout()

        assertTrue(result is Result.Success)
        coVerify { secureStorage.clearAll() }
        verify { keyManager.clearUnlockedKeys() }
        verify { folderKeyManager.clearCache() }
    }

    @Test
    fun `logout succeeds even when API fails`() = runTest {
        coEvery { apiService.logout() } throws java.io.IOException("Network error")

        val result = authRepository.logout()

        // Logout should still succeed - local cleanup is more important
        assertTrue(result is Result.Success)
        coVerify { secureStorage.clearAll() }
    }

    // ==================== getCurrentUser Tests ====================

    @Test
    fun `getCurrentUser returns user on success`() = runTest {
        val userDto = createTestUserDto()
        val userResponse = UserResponse(data = userDto)
        coEvery { apiService.getCurrentUser() } returns Response.success(userResponse)

        val result = authRepository.getCurrentUser()

        assertTrue(result is Result.Success)
        val user = (result as Result.Success).data
        assertEquals(testUserId, user.id)
        assertEquals(testEmail, user.email)
    }

    @Test
    fun `getCurrentUser returns unauthorized on 401`() = runTest {
        coEvery { apiService.getCurrentUser() } returns Response.error(
            401,
            "Unauthorized".toResponseBody()
        )

        val result = authRepository.getCurrentUser()

        assertTrue(result is Result.Error)
        val error = (result as Result.Error).exception
        assertTrue(error is AppException.Unauthorized)
    }

    // ==================== Key Unlock Tests ====================

    @Test
    fun `unlockKeys decrypts and sets keys`() = runTest {
        val password = "testpass".toCharArray()
        val encryptedMasterKey = ByteArray(64)
        val encryptedPrivateKeys = ByteArray(100)
        val salt = ByteArray(16)
        val decryptedMasterKey = ByteArray(32)
        val keyBundle = mockk<KeyBundle>()

        coEvery { secureStorage.getEncryptedMasterKey() } returns encryptedMasterKey
        coEvery { secureStorage.getEncryptedPrivateKeys() } returns encryptedPrivateKeys
        coEvery { secureStorage.getKeyDerivationSalt() } returns salt
        every { cryptoManager.deriveKeyWithProfile(any(), salt) } returns ByteArray(32)
        every { cryptoManager.decryptAesGcm(encryptedMasterKey, any()) } returns decryptedMasterKey
        every { cryptoManager.decryptAesGcm(encryptedPrivateKeys, decryptedMasterKey) } returns ByteArray(50)
        every { keyManager.deserializePrivateKeys(any(), any()) } returns keyBundle

        val result = authRepository.unlockKeys(password)

        assertTrue(result is Result.Success)
        verify { keyManager.setUnlockedKeys(keyBundle) }
    }

    @Test
    fun `unlockKeys fails when keys not found`() = runTest {
        val password = "testpass".toCharArray()
        coEvery { secureStorage.getEncryptedMasterKey() } returns null

        val result = authRepository.unlockKeys(password)

        assertTrue(result is Result.Error)
    }

    // ==================== KDF Upgrade Tests ====================

    @Test
    fun `unlockKeys should trigger KDF upgrade when salt has weaker profile`() = runTest {
        // Arrange: device supports ARGON2ID_STANDARD (0x01)
        every { KdfProfile.selectForDevice(any()) } returns KdfProfile.ARGON2ID_STANDARD
        every { KdfProfile.createSaltWithProfile(KdfProfile.ARGON2ID_STANDARD) } returns
            ByteArray(17).also { it[0] = 0x01 }

        // Server salt uses BCRYPT_HKDF (0x03) — weaker, needs upgrade
        val weakSalt = ByteArray(17).also { it[0] = 0x03 }
        val encryptedMasterKey = ByteArray(64)
        val encryptedPrivateKeys = ByteArray(100)
        val decryptedMasterKey = ByteArray(32)
        val newEncryptedMasterKey = ByteArray(64)
        val keyBundle = mockk<KeyBundle>()

        coEvery { secureStorage.getEncryptedMasterKey() } returns encryptedMasterKey
        coEvery { secureStorage.getEncryptedPrivateKeys() } returns encryptedPrivateKeys
        coEvery { secureStorage.getKeyDerivationSalt() } returns weakSalt
        every { cryptoManager.deriveKeyWithProfile(any(), any()) } returns ByteArray(32)
        every { cryptoManager.decryptAesGcm(encryptedMasterKey, any()) } returns decryptedMasterKey
        every { cryptoManager.decryptAesGcm(encryptedPrivateKeys, decryptedMasterKey) } returns ByteArray(50)
        every { cryptoManager.encryptAesGcm(decryptedMasterKey, any()) } returns newEncryptedMasterKey
        every { keyManager.deserializePrivateKeys(any(), any()) } returns keyBundle

        // Mock the server update call
        val userResponse = mockk<UserResponse>(relaxed = true)
        coEvery { apiService.updateKeyMaterial(any()) } returns Response.success(userResponse)

        // Act
        val result = authRepository.unlockKeys("testpass".toCharArray())

        // Assert
        assertTrue(result is Result.Success)

        // Verify updateKeyMaterial was called (KDF upgrade happened)
        coVerify { apiService.updateKeyMaterial(match { request ->
            // The new salt should have profile byte 0x01 (ARGON2ID_STANDARD)
            val saltBytes = Base64.decode(request.keyDerivationSalt, Base64.NO_WRAP)
            saltBytes[0] == 0x01.toByte()
        }) }

        // Verify local storage was updated with new salt
        coVerify { secureStorage.saveEncryptedMasterKey(newEncryptedMasterKey) }
        coVerify { secureStorage.saveKeyDerivationSalt(match { salt -> salt[0] == 0x01.toByte() }) }
    }

    @Test
    fun `unlockKeys should NOT trigger KDF upgrade when profile is already strongest`() = runTest {
        // Arrange: device supports ARGON2ID_STANDARD (0x01)
        every { KdfProfile.selectForDevice(any()) } returns KdfProfile.ARGON2ID_STANDARD

        // Server salt already uses ARGON2ID_STANDARD (0x01) — no upgrade needed
        val strongSalt = ByteArray(17).also { it[0] = 0x01 }
        val encryptedMasterKey = ByteArray(64)
        val encryptedPrivateKeys = ByteArray(100)
        val decryptedMasterKey = ByteArray(32)
        val keyBundle = mockk<KeyBundle>()

        coEvery { secureStorage.getEncryptedMasterKey() } returns encryptedMasterKey
        coEvery { secureStorage.getEncryptedPrivateKeys() } returns encryptedPrivateKeys
        coEvery { secureStorage.getKeyDerivationSalt() } returns strongSalt
        every { cryptoManager.deriveKeyWithProfile(any(), any()) } returns ByteArray(32)
        every { cryptoManager.decryptAesGcm(encryptedMasterKey, any()) } returns decryptedMasterKey
        every { cryptoManager.decryptAesGcm(encryptedPrivateKeys, decryptedMasterKey) } returns ByteArray(50)
        every { keyManager.deserializePrivateKeys(any(), any()) } returns keyBundle

        // Act
        val result = authRepository.unlockKeys("testpass".toCharArray())

        // Assert
        assertTrue(result is Result.Success)

        // Verify updateKeyMaterial was NOT called (no upgrade needed)
        coVerify(exactly = 0) { apiService.updateKeyMaterial(any()) }
    }

    // ==================== Helper Functions ====================

    private fun createTestUserDto() = UserDto(
        id = testUserId,
        email = testEmail,
        tenantId = testTenant,
        role = "user",
        publicKeys = PublicKeysDto(
            kem = "base64encodedkey",
            sign = "base64encodedkey",
            mlKem = "base64encodedkey",
            mlDsa = "base64encodedkey"
        ),
        encryptedMasterKey = "encrypted",
        encryptedPrivateKeys = "encrypted",
        keyDerivationSalt = "salt",
        storageQuota = 1073741824,
        storageUsed = 0,
        insertedAt = "2024-01-01T00:00:00Z",
        updatedAt = "2024-01-01T00:00:00Z"
    )
}
