package my.ssdid.drive.data.repository

import my.ssdid.drive.data.local.SecureStorage
import my.ssdid.drive.data.remote.ApiService
import my.ssdid.drive.data.remote.dto.DeviceDto
import my.ssdid.drive.data.remote.dto.DeviceEnrollmentDto
import my.ssdid.drive.data.remote.dto.DeviceEnrollmentResponse
import my.ssdid.drive.data.remote.dto.DeviceEnrollmentsResponse
import my.ssdid.drive.data.remote.dto.DeviceInfoDto
import my.ssdid.drive.data.remote.dto.UpdateDeviceRequest
import my.ssdid.drive.domain.model.DeviceEnrollmentStatus
import my.ssdid.drive.domain.model.DeviceKeyAlgorithm
import my.ssdid.drive.domain.model.DevicePlatform
import my.ssdid.drive.domain.model.DeviceStatus
import my.ssdid.drive.domain.model.DeviceTrustLevel
import my.ssdid.drive.util.AppException
import my.ssdid.drive.util.PushNotificationManager
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
 * Unit tests for DeviceRepositoryImpl.
 *
 * Tests cover:
 * - getCurrentEnrollment (success, not enrolled, 404 clears enrollment, 401, network error)
 * - listEnrollments (success, 401, network error)
 * - updateEnrollment (success, 401, 403, 404, network error)
 * - revokeEnrollment (success, revoke current clears local, revoke other keeps local, 401, 403, 404, network error)
 * - isDeviceEnrolled
 * - enrollDevice (delegated to wallet)
 * - signRequest (delegated to wallet)
 * - getEnrollmentId
 * - clearEnrollment
 * - push notification registration/unregistration
 */
@OptIn(ExperimentalCoroutinesApi::class)
class DeviceRepositoryImplTest {

    private lateinit var apiService: ApiService
    private lateinit var secureStorage: SecureStorage
    private lateinit var pushNotificationManager: PushNotificationManager
    private lateinit var repository: DeviceRepositoryImpl

    private val testEnrollmentId = "enrollment-123"
    private val testDeviceId = "device-456"
    private val testUserId = "user-789"

    @Before
    fun setup() {
        apiService = mockk()
        secureStorage = mockk(relaxed = true)
        pushNotificationManager = mockk(relaxed = true)

        repository = DeviceRepositoryImpl(
            apiService = apiService,
            secureStorage = secureStorage,
            pushNotificationManager = pushNotificationManager
        )
    }

    @After
    fun tearDown() {
        unmockkAll()
    }

    // ==================== getCurrentEnrollment Tests ====================

    @Test
    fun `getCurrentEnrollment returns null when no enrollment id stored`() = runTest {
        coEvery { secureStorage.getDeviceEnrollmentId() } returns null

        val result = repository.getCurrentEnrollment()

        assertTrue(result is Result.Success)
        assertNull((result as Result.Success).data)
    }

    @Test
    fun `getCurrentEnrollment returns enrollment on success`() = runTest {
        coEvery { secureStorage.getDeviceEnrollmentId() } returns testEnrollmentId
        coEvery { apiService.getDeviceEnrollment(testEnrollmentId) } returns
            Response.success(DeviceEnrollmentResponse(data = createTestEnrollmentDto()))

        val result = repository.getCurrentEnrollment()

        assertTrue(result is Result.Success)
        val enrollment = (result as Result.Success).data
        assertNotNull(enrollment)
        assertEquals(testEnrollmentId, enrollment!!.id)
        assertEquals(testDeviceId, enrollment.deviceId)
        assertEquals(DeviceEnrollmentStatus.ACTIVE, enrollment.status)
        assertEquals(DeviceKeyAlgorithm.KAZ_SIGN, enrollment.keyAlgorithm)
    }

    @Test
    fun `getCurrentEnrollment clears enrollment and returns null on 404`() = runTest {
        coEvery { secureStorage.getDeviceEnrollmentId() } returns testEnrollmentId
        coEvery { apiService.getDeviceEnrollment(testEnrollmentId) } returns
            Response.error(404, "Not Found".toResponseBody())

        val result = repository.getCurrentEnrollment()

        assertTrue(result is Result.Success)
        assertNull((result as Result.Success).data)
        coVerify { secureStorage.clearDeviceEnrollment() }
    }

    @Test
    fun `getCurrentEnrollment returns unauthorized on 401`() = runTest {
        coEvery { secureStorage.getDeviceEnrollmentId() } returns testEnrollmentId
        coEvery { apiService.getDeviceEnrollment(testEnrollmentId) } returns
            Response.error(401, "Unauthorized".toResponseBody())

        val result = repository.getCurrentEnrollment()

        assertTrue(result is Result.Error)
        assertTrue((result as Result.Error).exception is AppException.Unauthorized)
    }

    @Test
    fun `getCurrentEnrollment returns network error on exception`() = runTest {
        coEvery { secureStorage.getDeviceEnrollmentId() } returns testEnrollmentId
        coEvery { apiService.getDeviceEnrollment(testEnrollmentId) } throws
            java.io.IOException("Connection refused")

        val result = repository.getCurrentEnrollment()

        assertTrue(result is Result.Error)
        assertTrue((result as Result.Error).exception is AppException.Network)
    }

    @Test
    fun `getCurrentEnrollment maps device info correctly`() = runTest {
        coEvery { secureStorage.getDeviceEnrollmentId() } returns testEnrollmentId
        coEvery { apiService.getDeviceEnrollment(testEnrollmentId) } returns
            Response.success(DeviceEnrollmentResponse(data = createTestEnrollmentDtoWithDevice()))

        val result = repository.getCurrentEnrollment()

        assertTrue(result is Result.Success)
        val enrollment = (result as Result.Success).data!!
        assertNotNull(enrollment.device)
        assertEquals(DevicePlatform.ANDROID, enrollment.device!!.platform)
        assertEquals(DeviceStatus.ACTIVE, enrollment.device!!.status)
        assertEquals(DeviceTrustLevel.HIGH, enrollment.device!!.trustLevel)
        assertNotNull(enrollment.device!!.deviceInfo)
        assertEquals("Pixel 8", enrollment.device!!.deviceInfo!!.model)
    }

    // ==================== listEnrollments Tests ====================

    @Test
    fun `listEnrollments returns list on success`() = runTest {
        val enrollments = listOf(createTestEnrollmentDto(), createTestEnrollmentDto(id = "enrollment-456"))
        coEvery { apiService.listDeviceEnrollments() } returns
            Response.success(DeviceEnrollmentsResponse(data = enrollments))

        val result = repository.listEnrollments()

        assertTrue(result is Result.Success)
        assertEquals(2, (result as Result.Success).data.size)
    }

    @Test
    fun `listEnrollments returns empty list on success with no enrollments`() = runTest {
        coEvery { apiService.listDeviceEnrollments() } returns
            Response.success(DeviceEnrollmentsResponse(data = emptyList()))

        val result = repository.listEnrollments()

        assertTrue(result is Result.Success)
        assertTrue((result as Result.Success).data.isEmpty())
    }

    @Test
    fun `listEnrollments returns unauthorized on 401`() = runTest {
        coEvery { apiService.listDeviceEnrollments() } returns
            Response.error(401, "Unauthorized".toResponseBody())

        val result = repository.listEnrollments()

        assertTrue(result is Result.Error)
        assertTrue((result as Result.Error).exception is AppException.Unauthorized)
    }

    @Test
    fun `listEnrollments returns network error on exception`() = runTest {
        coEvery { apiService.listDeviceEnrollments() } throws
            java.io.IOException("Timeout")

        val result = repository.listEnrollments()

        assertTrue(result is Result.Error)
        assertTrue((result as Result.Error).exception is AppException.Network)
    }

    // ==================== updateEnrollment Tests ====================

    @Test
    fun `updateEnrollment returns updated enrollment on success`() = runTest {
        val updatedDto = createTestEnrollmentDto(deviceName = "My Pixel")
        coEvery { apiService.updateDeviceEnrollment(testEnrollmentId, any()) } returns
            Response.success(DeviceEnrollmentResponse(data = updatedDto))

        val result = repository.updateEnrollment(testEnrollmentId, "My Pixel")

        assertTrue(result is Result.Success)
        assertEquals("My Pixel", (result as Result.Success).data.deviceName)
        coVerify { apiService.updateDeviceEnrollment(testEnrollmentId, UpdateDeviceRequest("My Pixel")) }
    }

    @Test
    fun `updateEnrollment returns unauthorized on 401`() = runTest {
        coEvery { apiService.updateDeviceEnrollment(testEnrollmentId, any()) } returns
            Response.error(401, "Unauthorized".toResponseBody())

        val result = repository.updateEnrollment(testEnrollmentId, "New Name")

        assertTrue(result is Result.Error)
        assertTrue((result as Result.Error).exception is AppException.Unauthorized)
    }

    @Test
    fun `updateEnrollment returns forbidden on 403`() = runTest {
        coEvery { apiService.updateDeviceEnrollment(testEnrollmentId, any()) } returns
            Response.error(403, "Forbidden".toResponseBody())

        val result = repository.updateEnrollment(testEnrollmentId, "New Name")

        assertTrue(result is Result.Error)
        assertTrue((result as Result.Error).exception is AppException.Forbidden)
    }

    @Test
    fun `updateEnrollment returns not found on 404`() = runTest {
        coEvery { apiService.updateDeviceEnrollment(testEnrollmentId, any()) } returns
            Response.error(404, "Not Found".toResponseBody())

        val result = repository.updateEnrollment(testEnrollmentId, "New Name")

        assertTrue(result is Result.Error)
        assertTrue((result as Result.Error).exception is AppException.NotFound)
    }

    @Test
    fun `updateEnrollment returns network error on exception`() = runTest {
        coEvery { apiService.updateDeviceEnrollment(testEnrollmentId, any()) } throws
            java.io.IOException("Network error")

        val result = repository.updateEnrollment(testEnrollmentId, "New Name")

        assertTrue(result is Result.Error)
        assertTrue((result as Result.Error).exception is AppException.Network)
    }

    // ==================== revokeEnrollment Tests ====================

    @Test
    fun `revokeEnrollment succeeds and clears local enrollment when revoking current device`() = runTest {
        coEvery { apiService.revokeDeviceEnrollment(testEnrollmentId) } returns
            Response.success(Unit)
        coEvery { secureStorage.getDeviceEnrollmentId() } returns testEnrollmentId

        val result = repository.revokeEnrollment(testEnrollmentId)

        assertTrue(result is Result.Success)
        coVerify { secureStorage.clearDeviceEnrollment() }
    }

    @Test
    fun `revokeEnrollment succeeds and does not clear local enrollment when revoking other device`() = runTest {
        coEvery { apiService.revokeDeviceEnrollment("other-enrollment") } returns
            Response.success(Unit)
        coEvery { secureStorage.getDeviceEnrollmentId() } returns testEnrollmentId

        val result = repository.revokeEnrollment("other-enrollment")

        assertTrue(result is Result.Success)
        coVerify(exactly = 0) { secureStorage.clearDeviceEnrollment() }
    }

    @Test
    fun `revokeEnrollment returns unauthorized on 401`() = runTest {
        coEvery { apiService.revokeDeviceEnrollment(testEnrollmentId) } returns
            Response.error(401, "Unauthorized".toResponseBody())

        val result = repository.revokeEnrollment(testEnrollmentId)

        assertTrue(result is Result.Error)
        assertTrue((result as Result.Error).exception is AppException.Unauthorized)
    }

    @Test
    fun `revokeEnrollment returns forbidden on 403`() = runTest {
        coEvery { apiService.revokeDeviceEnrollment(testEnrollmentId) } returns
            Response.error(403, "Forbidden".toResponseBody())

        val result = repository.revokeEnrollment(testEnrollmentId)

        assertTrue(result is Result.Error)
        assertTrue((result as Result.Error).exception is AppException.Forbidden)
    }

    @Test
    fun `revokeEnrollment returns not found on 404`() = runTest {
        coEvery { apiService.revokeDeviceEnrollment(testEnrollmentId) } returns
            Response.error(404, "Not Found".toResponseBody())

        val result = repository.revokeEnrollment(testEnrollmentId)

        assertTrue(result is Result.Error)
        assertTrue((result as Result.Error).exception is AppException.NotFound)
    }

    @Test
    fun `revokeEnrollment returns network error on exception`() = runTest {
        coEvery { apiService.revokeDeviceEnrollment(testEnrollmentId) } throws
            java.io.IOException("Network error")

        val result = repository.revokeEnrollment(testEnrollmentId)

        assertTrue(result is Result.Error)
        assertTrue((result as Result.Error).exception is AppException.Network)
    }

    // ==================== isDeviceEnrolled Tests ====================

    @Test
    fun `isDeviceEnrolled returns true when enrolled`() = runTest {
        coEvery { secureStorage.isDeviceEnrolled() } returns true

        val result = repository.isDeviceEnrolled()

        assertTrue(result)
    }

    @Test
    fun `isDeviceEnrolled returns false when not enrolled`() = runTest {
        coEvery { secureStorage.isDeviceEnrolled() } returns false

        val result = repository.isDeviceEnrolled()

        assertFalse(result)
    }

    // ==================== enrollDevice Tests ====================

    @Test
    fun `enrollDevice returns error because it is delegated to SSDID Wallet`() = runTest {
        val result = repository.enrollDevice("My Device")

        assertTrue(result is Result.Error)
        assertTrue((result as Result.Error).exception is AppException.Unknown)
    }

    // ==================== signRequest Tests ====================

    @Test
    fun `signRequest returns error because it is delegated to SSDID Wallet`() = runTest {
        val result = repository.signRequest("test-payload")

        assertTrue(result is Result.Error)
        assertTrue((result as Result.Error).exception is AppException.CryptoError)
    }

    // ==================== getEnrollmentId Tests ====================

    @Test
    fun `getEnrollmentId returns id when enrolled`() = runTest {
        coEvery { secureStorage.getDeviceEnrollmentId() } returns testEnrollmentId

        val result = repository.getEnrollmentId()

        assertEquals(testEnrollmentId, result)
    }

    @Test
    fun `getEnrollmentId returns null when not enrolled`() = runTest {
        coEvery { secureStorage.getDeviceEnrollmentId() } returns null

        val result = repository.getEnrollmentId()

        assertNull(result)
    }

    // ==================== clearEnrollment Tests ====================

    @Test
    fun `clearEnrollment clears secure storage`() = runTest {
        repository.clearEnrollment()

        coVerify { secureStorage.clearDeviceEnrollment() }
    }

    // ==================== Push Notification Tests ====================

    @Test
    fun `registerPushNotifications calls push manager when enrolled`() {
        every { secureStorage.getDeviceEnrollmentIdSync() } returns testEnrollmentId

        repository.registerPushNotifications(testUserId)

        verify { pushNotificationManager.login(testUserId, testEnrollmentId) }
    }

    @Test
    fun `registerPushNotifications does nothing when not enrolled`() {
        every { secureStorage.getDeviceEnrollmentIdSync() } returns null

        repository.registerPushNotifications(testUserId)

        verify(exactly = 0) { pushNotificationManager.login(any(), any()) }
    }

    @Test
    fun `unregisterPushNotifications calls push manager`() {
        every { secureStorage.getDeviceEnrollmentIdSync() } returns testEnrollmentId

        repository.unregisterPushNotifications()

        verify { pushNotificationManager.logout(testEnrollmentId) }
    }

    // ==================== Helper Functions ====================

    private fun createTestEnrollmentDto(
        id: String = testEnrollmentId,
        deviceName: String? = "Test Device"
    ) = DeviceEnrollmentDto(
        id = id,
        deviceId = testDeviceId,
        deviceName = deviceName,
        status = "active",
        keyAlgorithm = "kaz_sign",
        enrolledAt = "2024-01-01T00:00:00Z",
        lastUsedAt = "2024-06-01T00:00:00Z",
        pushPlayerId = null,
        device = null
    )

    private fun createTestEnrollmentDtoWithDevice() = DeviceEnrollmentDto(
        id = testEnrollmentId,
        deviceId = testDeviceId,
        deviceName = "Pixel 8",
        status = "active",
        keyAlgorithm = "kaz_sign",
        enrolledAt = "2024-01-01T00:00:00Z",
        lastUsedAt = "2024-06-01T00:00:00Z",
        pushPlayerId = "player-123",
        device = DeviceDto(
            id = testDeviceId,
            deviceFingerprint = "fp-abc-123",
            platform = "android",
            deviceInfo = DeviceInfoDto(
                model = "Pixel 8",
                manufacturer = "Google",
                osVersion = "14",
                appVersion = "1.0.0",
                sdkVersion = 34
            ),
            status = "active",
            trustLevel = "high",
            createdAt = "2024-01-01T00:00:00Z"
        )
    )
}
