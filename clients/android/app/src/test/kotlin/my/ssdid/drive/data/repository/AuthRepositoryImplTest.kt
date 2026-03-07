package my.ssdid.drive.data.repository

import android.content.Context
import android.util.Base64
import my.ssdid.drive.crypto.CryptoConfig
import my.ssdid.drive.crypto.CryptoManager
import my.ssdid.drive.crypto.FolderKeyManager
import my.ssdid.drive.crypto.KeyBundle
import my.ssdid.drive.crypto.KeyManager
import my.ssdid.drive.data.local.SecureStorage
import my.ssdid.drive.util.AnalyticsManager
import my.ssdid.drive.util.CacheManager
import my.ssdid.drive.util.Logger
import my.ssdid.drive.util.PushNotificationManager
import my.ssdid.drive.data.remote.ApiService
import my.ssdid.drive.data.remote.dto.PublicKeysDto
import my.ssdid.drive.data.remote.dto.UserDto
import my.ssdid.drive.data.remote.dto.UserResponse
import my.ssdid.drive.util.AppException
import my.ssdid.drive.util.Result
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
 * - Authentication state checks
 * - Logout and cleanup
 * - getCurrentUser
 * - Error handling
 *
 * Note: Login/register flows now use SSDID Wallet deep links
 * and are tested via integration tests.
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
    private lateinit var cacheManager: CacheManager
    private lateinit var pushNotificationManager: PushNotificationManager
    private lateinit var analyticsManager: AnalyticsManager
    private lateinit var authRepository: AuthRepositoryImpl

    private val testEmail = "test@example.com"
    private val testUserId = "user-123"
    private val testTenant = "test-tenant"

    @Before
    fun setup() {
        mockkStatic(Base64::class)
        every { Base64.decode(any<String>(), any()) } returns ByteArray(32)
        every { Base64.encodeToString(any(), any()) } returns "base64encoded"

        mockkObject(Logger)
        every { Logger.d(any(), any(), any()) } just Runs
        every { Logger.i(any(), any(), any()) } just Runs
        every { Logger.w(any(), any(), any()) } just Runs
        every { Logger.e(any(), any(), any()) } just Runs

        context = mockk(relaxed = true)
        apiService = mockk()
        secureStorage = mockk(relaxed = true)
        cryptoManager = mockk()
        keyManager = mockk(relaxed = true)
        cryptoConfig = mockk(relaxed = true)
        folderKeyManager = mockk(relaxed = true)
        cacheManager = mockk(relaxed = true)
        pushNotificationManager = mockk(relaxed = true)
        analyticsManager = mockk(relaxed = true)

        authRepository = AuthRepositoryImpl(
            context = context,
            apiService = apiService,
            secureStorage = secureStorage,
            cryptoManager = cryptoManager,
            keyManager = keyManager,
            cryptoConfig = cryptoConfig,
            folderKeyManager = folderKeyManager,
            cacheManager = cacheManager,
            pushNotificationManager = pushNotificationManager,
            analyticsManager = analyticsManager
        )
    }

    @After
    fun tearDown() {
        unmockkStatic(Base64::class)
        unmockkObject(Logger)
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

    // ==================== areKeysUnlocked Tests ====================

    @Test
    fun `areKeysUnlocked returns true when keys unlocked`() = runTest {
        every { keyManager.hasUnlockedKeys() } returns true

        val result = authRepository.areKeysUnlocked()

        assertTrue(result)
    }

    @Test
    fun `areKeysUnlocked returns false when keys locked`() = runTest {
        every { keyManager.hasUnlockedKeys() } returns false

        val result = authRepository.areKeysUnlocked()

        assertFalse(result)
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
