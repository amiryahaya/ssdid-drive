package my.ssdid.drive.data.repository

import android.util.Base64
import com.google.gson.Gson
import my.ssdid.drive.crypto.CryptoConfig
import my.ssdid.drive.crypto.FolderKeyManager
import my.ssdid.drive.crypto.PqcAlgorithm
import my.ssdid.drive.data.local.SecureStorage
import my.ssdid.drive.data.remote.ApiService
import my.ssdid.drive.data.remote.dto.CreateInvitationRequest
import my.ssdid.drive.data.remote.dto.CreateInvitationResponse
import my.ssdid.drive.data.remote.dto.CreatedInvitationDto
import my.ssdid.drive.data.remote.dto.InvitationAcceptedDto
import my.ssdid.drive.data.remote.dto.InvitationAcceptedResponse
import my.ssdid.drive.data.remote.dto.InvitationCreatedResponse
import my.ssdid.drive.data.remote.dto.InvitationCreatedDto
import my.ssdid.drive.data.remote.dto.InvitationDto
import my.ssdid.drive.data.remote.dto.InvitationsResponse
import my.ssdid.drive.data.remote.dto.InviteMemberRequest
import my.ssdid.drive.data.remote.dto.InviteCodeInfoDto
import my.ssdid.drive.data.remote.dto.InviteCodeInfoResponse
import my.ssdid.drive.data.remote.dto.InviterDto
import my.ssdid.drive.data.remote.dto.SentInvitationDto
import my.ssdid.drive.data.remote.dto.SentInvitationsResponse
import my.ssdid.drive.data.remote.dto.MemberDto
import my.ssdid.drive.data.remote.dto.MemberResponse
import my.ssdid.drive.data.remote.dto.MembersResponse
import my.ssdid.drive.data.remote.dto.TenantConfigDto
import my.ssdid.drive.data.remote.dto.TenantConfigResponse
import my.ssdid.drive.data.remote.dto.TenantDto
import my.ssdid.drive.data.remote.dto.TenantSwitchData
import my.ssdid.drive.data.remote.dto.TenantSwitchRequest
import my.ssdid.drive.data.remote.dto.TenantSwitchResponse
import my.ssdid.drive.data.remote.dto.TenantsResponse
import my.ssdid.drive.data.remote.dto.UpdateMemberRoleRequest
import my.ssdid.drive.data.remote.dto.UsersResponse
import my.ssdid.drive.data.remote.dto.UserDto
import my.ssdid.drive.data.remote.dto.PublicKeysDto
import my.ssdid.drive.domain.model.InvitationStatus
import my.ssdid.drive.domain.model.MemberStatus
import my.ssdid.drive.domain.model.UserRole
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
 * Unit tests for TenantRepositoryImpl.
 *
 * Tests cover:
 * - getUserTenants (success, 401, network error)
 * - switchTenant (success, 401, 403, 404, network error)
 * - leaveTenant (success, 401, 404, 409, network error)
 * - getTenantConfig (success, 401, 404, network error, updates crypto config)
 * - getTenantUsers (success, 401, 403, network error)
 * - getTenantMembers (success, 401, 403, 404, network error)
 * - inviteMember (success, 401, 403, 404, 409, network error)
 * - updateMemberRole (success, 401, 403, 404, network error)
 * - removeMember (success, 401, 403, 404, 409, network error)
 * - getPendingInvitations (success, 401, network error)
 * - acceptInvitation (success, 401, 404, 409, network error)
 * - declineInvitation (success, 401, 404, 409, network error)
 * - getPqcAlgorithm
 * - saveTenantContext
 * - clearTenantData
 */
@OptIn(ExperimentalCoroutinesApi::class)
class TenantRepositoryImplTest {

    private lateinit var apiService: ApiService
    private lateinit var secureStorage: SecureStorage
    private lateinit var cryptoConfig: CryptoConfig
    private lateinit var folderKeyManager: FolderKeyManager
    private lateinit var gson: Gson
    private lateinit var repository: TenantRepositoryImpl

    private val testTenantId = "tenant-123"
    private val testUserId = "user-456"
    private val testInvitationId = "invitation-789"

    @Before
    fun setup() {
        mockkStatic(Base64::class)
        every { Base64.decode(any<String>(), any()) } returns ByteArray(32)
        every { Base64.encodeToString(any(), any()) } returns "base64encoded"

        apiService = mockk()
        secureStorage = mockk(relaxed = true)
        cryptoConfig = mockk(relaxed = true)
        folderKeyManager = mockk(relaxed = true)
        gson = Gson()

        repository = TenantRepositoryImpl(
            apiService = apiService,
            secureStorage = secureStorage,
            cryptoConfig = cryptoConfig,
            folderKeyManager = folderKeyManager,
            gson = gson
        )
    }

    @After
    fun tearDown() {
        unmockkStatic(Base64::class)
    }

    // ==================== getUserTenants Tests ====================

    @Test
    fun `getUserTenants returns tenant list on success`() = runTest {
        val tenants = listOf(
            createTestTenantDto(),
            createTestTenantDto(id = "tenant-456", name = "Second Org", slug = "second-org")
        )
        coEvery { apiService.getUserTenants() } returns
            Response.success(TenantsResponse(data = tenants))

        val result = repository.getUserTenants()

        assertTrue(result is Result.Success)
        assertEquals(2, (result as Result.Success).data.size)
        assertEquals("Test Org", result.data[0].name)
        assertEquals(UserRole.ADMIN, result.data[0].role)
        coVerify { secureStorage.saveUserTenants(any()) }
    }

    @Test
    fun `getUserTenants returns unauthorized on 401`() = runTest {
        coEvery { apiService.getUserTenants() } returns
            Response.error(401, "Unauthorized".toResponseBody())

        val result = repository.getUserTenants()

        assertTrue(result is Result.Error)
        assertTrue((result as Result.Error).exception is AppException.Unauthorized)
    }

    @Test
    fun `getUserTenants returns network error on exception`() = runTest {
        coEvery { apiService.getUserTenants() } throws
            java.io.IOException("Connection refused")

        val result = repository.getUserTenants()

        assertTrue(result is Result.Error)
        assertTrue((result as Result.Error).exception is AppException.Network)
    }

    // ==================== switchTenant Tests ====================

    @Test
    fun `switchTenant returns new context on success`() = runTest {
        val switchData = TenantSwitchData(
            currentTenantId = testTenantId,
            role = "admin",
            accessToken = "new-access-token",
            refreshToken = "new-refresh-token",
            expiresIn = 3600,
            tokenType = "Bearer"
        )
        coEvery { apiService.switchTenant(TenantSwitchRequest(testTenantId)) } returns
            Response.success(TenantSwitchResponse(data = switchData))
        coEvery { apiService.getTenantConfig() } returns
            Response.success(TenantConfigResponse(data = createTestTenantConfigDto()))

        val result = repository.switchTenant(testTenantId)

        assertTrue(result is Result.Success)
        val context = (result as Result.Success).data
        assertEquals(testTenantId, context.currentTenantId)
        assertEquals(UserRole.ADMIN, context.currentRole)
        verify { folderKeyManager.clearCache() }
        coVerify {
            secureStorage.saveTokensWithTenantContext(
                accessToken = "new-access-token",
                refreshToken = "new-refresh-token",
                tenantId = testTenantId,
                role = "admin"
            )
        }
    }

    @Test
    fun `switchTenant returns unauthorized on 401`() = runTest {
        coEvery { apiService.switchTenant(any()) } returns
            Response.error(401, "Unauthorized".toResponseBody())

        val result = repository.switchTenant(testTenantId)

        assertTrue(result is Result.Error)
        assertTrue((result as Result.Error).exception is AppException.Unauthorized)
    }

    @Test
    fun `switchTenant returns forbidden on 403`() = runTest {
        coEvery { apiService.switchTenant(any()) } returns
            Response.error(403, "Forbidden".toResponseBody())

        val result = repository.switchTenant(testTenantId)

        assertTrue(result is Result.Error)
        assertTrue((result as Result.Error).exception is AppException.Forbidden)
    }

    @Test
    fun `switchTenant returns not found on 404`() = runTest {
        coEvery { apiService.switchTenant(any()) } returns
            Response.error(404, "Not Found".toResponseBody())

        val result = repository.switchTenant(testTenantId)

        assertTrue(result is Result.Error)
        assertTrue((result as Result.Error).exception is AppException.NotFound)
    }

    @Test
    fun `switchTenant returns network error on exception`() = runTest {
        coEvery { apiService.switchTenant(any()) } throws
            java.io.IOException("Network error")

        val result = repository.switchTenant(testTenantId)

        assertTrue(result is Result.Error)
        assertTrue((result as Result.Error).exception is AppException.Network)
    }

    // ==================== leaveTenant Tests ====================

    @Test
    fun `leaveTenant succeeds and refreshes tenants`() = runTest {
        coEvery { apiService.leaveTenant(testTenantId) } returns Response.success(Unit)
        coEvery { apiService.getUserTenants() } returns
            Response.success(TenantsResponse(data = emptyList()))

        val result = repository.leaveTenant(testTenantId)

        assertTrue(result is Result.Success)
        coVerify { apiService.getUserTenants() }
    }

    @Test
    fun `leaveTenant returns unauthorized on 401`() = runTest {
        coEvery { apiService.leaveTenant(testTenantId) } returns
            Response.error(401, "Unauthorized".toResponseBody())

        val result = repository.leaveTenant(testTenantId)

        assertTrue(result is Result.Error)
        assertTrue((result as Result.Error).exception is AppException.Unauthorized)
    }

    @Test
    fun `leaveTenant returns not found on 404`() = runTest {
        coEvery { apiService.leaveTenant(testTenantId) } returns
            Response.error(404, "Not Found".toResponseBody())

        val result = repository.leaveTenant(testTenantId)

        assertTrue(result is Result.Error)
        assertTrue((result as Result.Error).exception is AppException.NotFound)
    }

    @Test
    fun `leaveTenant returns conflict on 409 when user is only owner`() = runTest {
        coEvery { apiService.leaveTenant(testTenantId) } returns
            Response.error(409, "Conflict".toResponseBody())

        val result = repository.leaveTenant(testTenantId)

        assertTrue(result is Result.Error)
        assertTrue((result as Result.Error).exception is AppException.Conflict)
    }

    @Test
    fun `leaveTenant returns network error on exception`() = runTest {
        coEvery { apiService.leaveTenant(testTenantId) } throws
            java.io.IOException("Network error")

        val result = repository.leaveTenant(testTenantId)

        assertTrue(result is Result.Error)
        assertTrue((result as Result.Error).exception is AppException.Network)
    }

    // ==================== getTenantConfig Tests ====================

    @Test
    fun `getTenantConfig returns config and updates crypto config on success`() = runTest {
        coEvery { apiService.getTenantConfig() } returns
            Response.success(TenantConfigResponse(data = createTestTenantConfigDto()))

        val result = repository.getTenantConfig()

        assertTrue(result is Result.Success)
        val config = (result as Result.Success).data
        assertEquals(testTenantId, config.id)
        assertEquals("Test Org", config.name)
        assertEquals("test-org", config.slug)
        assertEquals(PqcAlgorithm.KAZ, config.pqcAlgorithm)
        assertEquals("pro", config.plan)
        verify { cryptoConfig.setAlgorithm(PqcAlgorithm.KAZ) }
    }

    @Test
    fun `getTenantConfig returns unauthorized on 401`() = runTest {
        coEvery { apiService.getTenantConfig() } returns
            Response.error(401, "Unauthorized".toResponseBody())

        val result = repository.getTenantConfig()

        assertTrue(result is Result.Error)
        assertTrue((result as Result.Error).exception is AppException.Unauthorized)
    }

    @Test
    fun `getTenantConfig returns not found on 404`() = runTest {
        coEvery { apiService.getTenantConfig() } returns
            Response.error(404, "Not Found".toResponseBody())

        val result = repository.getTenantConfig()

        assertTrue(result is Result.Error)
        assertTrue((result as Result.Error).exception is AppException.NotFound)
    }

    @Test
    fun `getTenantConfig returns network error on exception`() = runTest {
        coEvery { apiService.getTenantConfig() } throws
            java.io.IOException("Network error")

        val result = repository.getTenantConfig()

        assertTrue(result is Result.Error)
        assertTrue((result as Result.Error).exception is AppException.Network)
    }

    // ==================== getTenantUsers Tests ====================

    @Test
    fun `getTenantUsers returns user list on success`() = runTest {
        val users = listOf(createTestUserDto(), createTestUserDto(id = "user-999", email = "other@test.com"))
        coEvery { apiService.getTenantUsers() } returns
            Response.success(UsersResponse(data = users))

        val result = repository.getTenantUsers()

        assertTrue(result is Result.Success)
        assertEquals(2, (result as Result.Success).data.size)
        assertEquals(testUserId, result.data[0].id)
    }

    @Test
    fun `getTenantUsers returns unauthorized on 401`() = runTest {
        coEvery { apiService.getTenantUsers() } returns
            Response.error(401, "Unauthorized".toResponseBody())

        val result = repository.getTenantUsers()

        assertTrue(result is Result.Error)
        assertTrue((result as Result.Error).exception is AppException.Unauthorized)
    }

    @Test
    fun `getTenantUsers returns forbidden on 403`() = runTest {
        coEvery { apiService.getTenantUsers() } returns
            Response.error(403, "Forbidden".toResponseBody())

        val result = repository.getTenantUsers()

        assertTrue(result is Result.Error)
        assertTrue((result as Result.Error).exception is AppException.Forbidden)
    }

    @Test
    fun `getTenantUsers returns network error on exception`() = runTest {
        coEvery { apiService.getTenantUsers() } throws
            java.io.IOException("Network error")

        val result = repository.getTenantUsers()

        assertTrue(result is Result.Error)
        assertTrue((result as Result.Error).exception is AppException.Network)
    }

    // ==================== getTenantMembers Tests ====================

    @Test
    fun `getTenantMembers returns member list on success`() = runTest {
        val members = listOf(createTestMemberDto(), createTestMemberDto(id = "member-2", userId = "user-2"))
        coEvery { apiService.getTenantMembers(testTenantId) } returns
            Response.success(MembersResponse(data = members))

        val result = repository.getTenantMembers(testTenantId)

        assertTrue(result is Result.Success)
        assertEquals(2, (result as Result.Success).data.size)
        assertEquals(UserRole.ADMIN, result.data[0].role)
        assertEquals(MemberStatus.ACTIVE, result.data[0].status)
    }

    @Test
    fun `getTenantMembers returns unauthorized on 401`() = runTest {
        coEvery { apiService.getTenantMembers(testTenantId) } returns
            Response.error(401, "Unauthorized".toResponseBody())

        val result = repository.getTenantMembers(testTenantId)

        assertTrue(result is Result.Error)
        assertTrue((result as Result.Error).exception is AppException.Unauthorized)
    }

    @Test
    fun `getTenantMembers returns forbidden on 403`() = runTest {
        coEvery { apiService.getTenantMembers(testTenantId) } returns
            Response.error(403, "Forbidden".toResponseBody())

        val result = repository.getTenantMembers(testTenantId)

        assertTrue(result is Result.Error)
        assertTrue((result as Result.Error).exception is AppException.Forbidden)
    }

    @Test
    fun `getTenantMembers returns not found on 404`() = runTest {
        coEvery { apiService.getTenantMembers(testTenantId) } returns
            Response.error(404, "Not Found".toResponseBody())

        val result = repository.getTenantMembers(testTenantId)

        assertTrue(result is Result.Error)
        assertTrue((result as Result.Error).exception is AppException.NotFound)
    }

    @Test
    fun `getTenantMembers returns network error on exception`() = runTest {
        coEvery { apiService.getTenantMembers(testTenantId) } throws
            java.io.IOException("Network error")

        val result = repository.getTenantMembers(testTenantId)

        assertTrue(result is Result.Error)
        assertTrue((result as Result.Error).exception is AppException.Network)
    }

    // ==================== inviteMember Tests ====================

    @Test
    fun `inviteMember succeeds`() = runTest {
        coEvery { apiService.inviteMember(testTenantId, any()) } returns
            Response.success(InvitationCreatedResponse(
                data = InvitationCreatedDto(
                    id = "inv-1", userId = testUserId, email = "new@test.com",
                    displayName = null, role = "member", status = "pending", invitedAt = "2024-01-01T00:00:00Z"
                )
            ))

        val result = repository.inviteMember(testTenantId, "new@test.com", UserRole.USER)

        assertTrue(result is Result.Success)
        coVerify { apiService.inviteMember(testTenantId, InviteMemberRequest("new@test.com", "member")) }
    }

    @Test
    fun `inviteMember sends admin role correctly`() = runTest {
        coEvery { apiService.inviteMember(testTenantId, any()) } returns
            Response.success(InvitationCreatedResponse(
                data = InvitationCreatedDto(
                    id = "inv-1", userId = testUserId, email = "admin@test.com",
                    displayName = null, role = "admin", status = "pending", invitedAt = "2024-01-01T00:00:00Z"
                )
            ))

        val result = repository.inviteMember(testTenantId, "admin@test.com", UserRole.ADMIN)

        assertTrue(result is Result.Success)
        coVerify { apiService.inviteMember(testTenantId, InviteMemberRequest("admin@test.com", "admin")) }
    }

    @Test
    fun `inviteMember returns unauthorized on 401`() = runTest {
        coEvery { apiService.inviteMember(testTenantId, any()) } returns
            Response.error(401, "Unauthorized".toResponseBody())

        val result = repository.inviteMember(testTenantId, "new@test.com")

        assertTrue(result is Result.Error)
        assertTrue((result as Result.Error).exception is AppException.Unauthorized)
    }

    @Test
    fun `inviteMember returns forbidden on 403`() = runTest {
        coEvery { apiService.inviteMember(testTenantId, any()) } returns
            Response.error(403, "Forbidden".toResponseBody())

        val result = repository.inviteMember(testTenantId, "new@test.com")

        assertTrue(result is Result.Error)
        assertTrue((result as Result.Error).exception is AppException.Forbidden)
    }

    @Test
    fun `inviteMember returns not found on 404`() = runTest {
        coEvery { apiService.inviteMember(testTenantId, any()) } returns
            Response.error(404, "Not Found".toResponseBody())

        val result = repository.inviteMember(testTenantId, "new@test.com")

        assertTrue(result is Result.Error)
        assertTrue((result as Result.Error).exception is AppException.NotFound)
    }

    @Test
    fun `inviteMember returns conflict on 409 when user already member`() = runTest {
        coEvery { apiService.inviteMember(testTenantId, any()) } returns
            Response.error(409, "Conflict".toResponseBody())

        val result = repository.inviteMember(testTenantId, "existing@test.com")

        assertTrue(result is Result.Error)
        assertTrue((result as Result.Error).exception is AppException.Conflict)
    }

    @Test
    fun `inviteMember returns network error on exception`() = runTest {
        coEvery { apiService.inviteMember(testTenantId, any()) } throws
            java.io.IOException("Network error")

        val result = repository.inviteMember(testTenantId, "new@test.com")

        assertTrue(result is Result.Error)
        assertTrue((result as Result.Error).exception is AppException.Network)
    }

    // ==================== updateMemberRole Tests ====================

    @Test
    fun `updateMemberRole returns updated member on success`() = runTest {
        val memberDto = createTestMemberDto(role = "owner")
        coEvery { apiService.updateMemberRole(testTenantId, testUserId, any()) } returns
            Response.success(MemberResponse(data = memberDto))

        val result = repository.updateMemberRole(testTenantId, testUserId, UserRole.OWNER)

        assertTrue(result is Result.Success)
        assertEquals(UserRole.OWNER, (result as Result.Success).data.role)
        coVerify { apiService.updateMemberRole(testTenantId, testUserId, UpdateMemberRoleRequest("owner")) }
    }

    @Test
    fun `updateMemberRole returns unauthorized on 401`() = runTest {
        coEvery { apiService.updateMemberRole(testTenantId, testUserId, any()) } returns
            Response.error(401, "Unauthorized".toResponseBody())

        val result = repository.updateMemberRole(testTenantId, testUserId, UserRole.ADMIN)

        assertTrue(result is Result.Error)
        assertTrue((result as Result.Error).exception is AppException.Unauthorized)
    }

    @Test
    fun `updateMemberRole returns forbidden on 403`() = runTest {
        coEvery { apiService.updateMemberRole(testTenantId, testUserId, any()) } returns
            Response.error(403, "Forbidden".toResponseBody())

        val result = repository.updateMemberRole(testTenantId, testUserId, UserRole.ADMIN)

        assertTrue(result is Result.Error)
        assertTrue((result as Result.Error).exception is AppException.Forbidden)
    }

    @Test
    fun `updateMemberRole returns not found on 404`() = runTest {
        coEvery { apiService.updateMemberRole(testTenantId, testUserId, any()) } returns
            Response.error(404, "Not Found".toResponseBody())

        val result = repository.updateMemberRole(testTenantId, testUserId, UserRole.ADMIN)

        assertTrue(result is Result.Error)
        assertTrue((result as Result.Error).exception is AppException.NotFound)
    }

    @Test
    fun `updateMemberRole returns network error on exception`() = runTest {
        coEvery { apiService.updateMemberRole(testTenantId, testUserId, any()) } throws
            java.io.IOException("Network error")

        val result = repository.updateMemberRole(testTenantId, testUserId, UserRole.ADMIN)

        assertTrue(result is Result.Error)
        assertTrue((result as Result.Error).exception is AppException.Network)
    }

    // ==================== removeMember Tests ====================

    @Test
    fun `removeMember succeeds`() = runTest {
        coEvery { apiService.removeMember(testTenantId, testUserId) } returns
            Response.success(Unit)

        val result = repository.removeMember(testTenantId, testUserId)

        assertTrue(result is Result.Success)
    }

    @Test
    fun `removeMember returns unauthorized on 401`() = runTest {
        coEvery { apiService.removeMember(testTenantId, testUserId) } returns
            Response.error(401, "Unauthorized".toResponseBody())

        val result = repository.removeMember(testTenantId, testUserId)

        assertTrue(result is Result.Error)
        assertTrue((result as Result.Error).exception is AppException.Unauthorized)
    }

    @Test
    fun `removeMember returns forbidden on 403`() = runTest {
        coEvery { apiService.removeMember(testTenantId, testUserId) } returns
            Response.error(403, "Forbidden".toResponseBody())

        val result = repository.removeMember(testTenantId, testUserId)

        assertTrue(result is Result.Error)
        assertTrue((result as Result.Error).exception is AppException.Forbidden)
    }

    @Test
    fun `removeMember returns not found on 404`() = runTest {
        coEvery { apiService.removeMember(testTenantId, testUserId) } returns
            Response.error(404, "Not Found".toResponseBody())

        val result = repository.removeMember(testTenantId, testUserId)

        assertTrue(result is Result.Error)
        assertTrue((result as Result.Error).exception is AppException.NotFound)
    }

    @Test
    fun `removeMember returns conflict on 409 when removing owner`() = runTest {
        coEvery { apiService.removeMember(testTenantId, testUserId) } returns
            Response.error(409, "Conflict".toResponseBody())

        val result = repository.removeMember(testTenantId, testUserId)

        assertTrue(result is Result.Error)
        assertTrue((result as Result.Error).exception is AppException.Conflict)
    }

    @Test
    fun `removeMember returns network error on exception`() = runTest {
        coEvery { apiService.removeMember(testTenantId, testUserId) } throws
            java.io.IOException("Network error")

        val result = repository.removeMember(testTenantId, testUserId)

        assertTrue(result is Result.Error)
        assertTrue((result as Result.Error).exception is AppException.Network)
    }

    // ==================== getPendingInvitations Tests ====================

    @Test
    fun `getPendingInvitations returns invitation list on success`() = runTest {
        val invitations = listOf(
            createTestInvitationDto(),
            createTestInvitationDto(id = "inv-2", tenantName = "Other Org")
        )
        coEvery { apiService.getPendingInvitations() } returns
            Response.success(InvitationsResponse(data = invitations))

        val result = repository.getPendingInvitations()

        assertTrue(result is Result.Success)
        assertEquals(2, (result as Result.Success).data.size)
        assertEquals("Test Org", result.data[0].tenantName)
        assertNotNull(result.data[0].invitedBy)
        assertEquals("inviter@test.com", result.data[0].invitedBy?.email)
    }

    @Test
    fun `getPendingInvitations returns empty list when none`() = runTest {
        coEvery { apiService.getPendingInvitations() } returns
            Response.success(InvitationsResponse(data = emptyList()))

        val result = repository.getPendingInvitations()

        assertTrue(result is Result.Success)
        assertTrue((result as Result.Success).data.isEmpty())
    }

    @Test
    fun `getPendingInvitations returns unauthorized on 401`() = runTest {
        coEvery { apiService.getPendingInvitations() } returns
            Response.error(401, "Unauthorized".toResponseBody())

        val result = repository.getPendingInvitations()

        assertTrue(result is Result.Error)
        assertTrue((result as Result.Error).exception is AppException.Unauthorized)
    }

    @Test
    fun `getPendingInvitations returns network error on exception`() = runTest {
        coEvery { apiService.getPendingInvitations() } throws
            java.io.IOException("Network error")

        val result = repository.getPendingInvitations()

        assertTrue(result is Result.Error)
        assertTrue((result as Result.Error).exception is AppException.Network)
    }

    // ==================== acceptInvitation Tests ====================

    @Test
    fun `acceptInvitation returns accepted details and refreshes tenants on success`() = runTest {
        val acceptedDto = InvitationAcceptedDto(
            id = testInvitationId,
            tenantId = testTenantId,
            role = "member",
            status = "accepted",
            joinedAt = "2024-06-01T00:00:00Z"
        )
        coEvery { apiService.acceptInvitation(testInvitationId) } returns
            Response.success(InvitationAcceptedResponse(data = acceptedDto))
        coEvery { apiService.getUserTenants() } returns
            Response.success(TenantsResponse(data = listOf(createTestTenantDto())))

        val result = repository.acceptInvitation(testInvitationId)

        assertTrue(result is Result.Success)
        val accepted = (result as Result.Success).data
        assertEquals(testInvitationId, accepted.id)
        assertEquals(testTenantId, accepted.tenantId)
        assertEquals(UserRole.USER, accepted.role)
        // Verify it refreshes tenants after accepting
        coVerify { apiService.getUserTenants() }
    }

    @Test
    fun `acceptInvitation returns unauthorized on 401`() = runTest {
        coEvery { apiService.acceptInvitation(testInvitationId) } returns
            Response.error(401, "Unauthorized".toResponseBody())

        val result = repository.acceptInvitation(testInvitationId)

        assertTrue(result is Result.Error)
        assertTrue((result as Result.Error).exception is AppException.Unauthorized)
    }

    @Test
    fun `acceptInvitation returns not found on 404`() = runTest {
        coEvery { apiService.acceptInvitation(testInvitationId) } returns
            Response.error(404, "Not Found".toResponseBody())

        val result = repository.acceptInvitation(testInvitationId)

        assertTrue(result is Result.Error)
        assertTrue((result as Result.Error).exception is AppException.NotFound)
    }

    @Test
    fun `acceptInvitation returns conflict on 409 when already processed`() = runTest {
        coEvery { apiService.acceptInvitation(testInvitationId) } returns
            Response.error(409, "Conflict".toResponseBody())

        val result = repository.acceptInvitation(testInvitationId)

        assertTrue(result is Result.Error)
        assertTrue((result as Result.Error).exception is AppException.Conflict)
    }

    @Test
    fun `acceptInvitation returns network error on exception`() = runTest {
        coEvery { apiService.acceptInvitation(testInvitationId) } throws
            java.io.IOException("Network error")

        val result = repository.acceptInvitation(testInvitationId)

        assertTrue(result is Result.Error)
        assertTrue((result as Result.Error).exception is AppException.Network)
    }

    // ==================== declineInvitation Tests ====================

    @Test
    fun `declineInvitation succeeds`() = runTest {
        coEvery { apiService.declineInvitation(testInvitationId) } returns
            Response.success(Unit)

        val result = repository.declineInvitation(testInvitationId)

        assertTrue(result is Result.Success)
    }

    @Test
    fun `declineInvitation returns unauthorized on 401`() = runTest {
        coEvery { apiService.declineInvitation(testInvitationId) } returns
            Response.error(401, "Unauthorized".toResponseBody())

        val result = repository.declineInvitation(testInvitationId)

        assertTrue(result is Result.Error)
        assertTrue((result as Result.Error).exception is AppException.Unauthorized)
    }

    @Test
    fun `declineInvitation returns not found on 404`() = runTest {
        coEvery { apiService.declineInvitation(testInvitationId) } returns
            Response.error(404, "Not Found".toResponseBody())

        val result = repository.declineInvitation(testInvitationId)

        assertTrue(result is Result.Error)
        assertTrue((result as Result.Error).exception is AppException.NotFound)
    }

    @Test
    fun `declineInvitation returns conflict on 409 when already processed`() = runTest {
        coEvery { apiService.declineInvitation(testInvitationId) } returns
            Response.error(409, "Conflict".toResponseBody())

        val result = repository.declineInvitation(testInvitationId)

        assertTrue(result is Result.Error)
        assertTrue((result as Result.Error).exception is AppException.Conflict)
    }

    @Test
    fun `declineInvitation returns network error on exception`() = runTest {
        coEvery { apiService.declineInvitation(testInvitationId) } throws
            java.io.IOException("Network error")

        val result = repository.declineInvitation(testInvitationId)

        assertTrue(result is Result.Error)
        assertTrue((result as Result.Error).exception is AppException.Network)
    }

    // ==================== createInvitation Tests ====================

    @Test
    fun `createInvitation returns created invitation on success`() = runTest {
        val dto = CreatedInvitationDto(
            id = "inv-new",
            shortCode = "ACME-1234",
            email = "new@test.com",
            role = "member",
            status = "pending",
            message = "Welcome!",
            createdAt = "2024-06-01T00:00:00Z",
            expiresAt = "2024-07-01T00:00:00Z"
        )
        coEvery { apiService.createInvitation(any()) } returns
            Response.success(CreateInvitationResponse(data = dto))

        val result = repository.createInvitation(
            email = "new@test.com",
            role = UserRole.USER,
            message = "Welcome!"
        )

        assertTrue(result is Result.Success)
        val created = (result as Result.Success).data
        assertEquals("inv-new", created.id)
        assertEquals("ACME-1234", created.shortCode)
        assertEquals("new@test.com", created.email)
        assertEquals(UserRole.USER, created.role)
        assertEquals(InvitationStatus.PENDING, created.status)
        assertEquals("Welcome!", created.message)
    }

    @Test
    fun `createInvitation returns unauthorized on 401`() = runTest {
        coEvery { apiService.createInvitation(any()) } returns
            Response.error(401, "Unauthorized".toResponseBody())

        val result = repository.createInvitation(email = "test@test.com")

        assertTrue(result is Result.Error)
        assertTrue((result as Result.Error).exception is AppException.Unauthorized)
    }

    @Test
    fun `createInvitation returns forbidden on 403`() = runTest {
        coEvery { apiService.createInvitation(any()) } returns
            Response.error(403, "Forbidden".toResponseBody())

        val result = repository.createInvitation(email = "test@test.com")

        assertTrue(result is Result.Error)
        assertTrue((result as Result.Error).exception is AppException.Forbidden)
    }

    @Test
    fun `createInvitation returns conflict on 409`() = runTest {
        coEvery { apiService.createInvitation(any()) } returns
            Response.error(409, "Conflict".toResponseBody())

        val result = repository.createInvitation(email = "existing@test.com")

        assertTrue(result is Result.Error)
        assertTrue((result as Result.Error).exception is AppException.Conflict)
    }

    @Test
    fun `createInvitation returns network error on exception`() = runTest {
        coEvery { apiService.createInvitation(any()) } throws
            java.io.IOException("Network error")

        val result = repository.createInvitation(email = "test@test.com")

        assertTrue(result is Result.Error)
        assertTrue((result as Result.Error).exception is AppException.Network)
    }

    // ==================== getSentInvitations Tests ====================

    @Test
    fun `getSentInvitations returns invitation list on success`() = runTest {
        val invitations = listOf(
            SentInvitationDto(
                id = "inv-1", shortCode = "CODE-1", email = "a@test.com",
                role = "member", status = "pending", message = null,
                createdAt = "2024-06-01T00:00:00Z", expiresAt = "2024-07-01T00:00:00Z"
            ),
            SentInvitationDto(
                id = "inv-2", shortCode = "CODE-2", email = null,
                role = "admin", status = "accepted", message = "Hi",
                createdAt = "2024-06-02T00:00:00Z", expiresAt = "2024-07-02T00:00:00Z"
            )
        )
        coEvery { apiService.getSentInvitations(any(), any()) } returns
            Response.success(SentInvitationsResponse(data = invitations))

        val result = repository.getSentInvitations()

        assertTrue(result is Result.Success)
        assertEquals(2, (result as Result.Success).data.size)
        assertEquals("inv-1", result.data[0].id)
        assertEquals(UserRole.USER, result.data[0].role)
        assertEquals(InvitationStatus.PENDING, result.data[0].status)
        assertEquals(UserRole.ADMIN, result.data[1].role)
        assertEquals(InvitationStatus.ACCEPTED, result.data[1].status)
    }

    @Test
    fun `getSentInvitations returns unauthorized on 401`() = runTest {
        coEvery { apiService.getSentInvitations(any(), any()) } returns
            Response.error(401, "Unauthorized".toResponseBody())

        val result = repository.getSentInvitations()

        assertTrue(result is Result.Error)
        assertTrue((result as Result.Error).exception is AppException.Unauthorized)
    }

    @Test
    fun `getSentInvitations returns forbidden on 403`() = runTest {
        coEvery { apiService.getSentInvitations(any(), any()) } returns
            Response.error(403, "Forbidden".toResponseBody())

        val result = repository.getSentInvitations()

        assertTrue(result is Result.Error)
        assertTrue((result as Result.Error).exception is AppException.Forbidden)
    }

    @Test
    fun `getSentInvitations returns network error on exception`() = runTest {
        coEvery { apiService.getSentInvitations(any(), any()) } throws
            java.io.IOException("Network error")

        val result = repository.getSentInvitations()

        assertTrue(result is Result.Error)
        assertTrue((result as Result.Error).exception is AppException.Network)
    }

    // ==================== revokeInvitation Tests ====================

    @Test
    fun `revokeInvitation succeeds`() = runTest {
        coEvery { apiService.revokeInvitation(testInvitationId) } returns
            Response.success(Unit)

        val result = repository.revokeInvitation(testInvitationId)

        assertTrue(result is Result.Success)
    }

    @Test
    fun `revokeInvitation returns unauthorized on 401`() = runTest {
        coEvery { apiService.revokeInvitation(testInvitationId) } returns
            Response.error(401, "Unauthorized".toResponseBody())

        val result = repository.revokeInvitation(testInvitationId)

        assertTrue(result is Result.Error)
        assertTrue((result as Result.Error).exception is AppException.Unauthorized)
    }

    @Test
    fun `revokeInvitation returns forbidden on 403`() = runTest {
        coEvery { apiService.revokeInvitation(testInvitationId) } returns
            Response.error(403, "Forbidden".toResponseBody())

        val result = repository.revokeInvitation(testInvitationId)

        assertTrue(result is Result.Error)
        assertTrue((result as Result.Error).exception is AppException.Forbidden)
    }

    @Test
    fun `revokeInvitation returns not found on 404`() = runTest {
        coEvery { apiService.revokeInvitation(testInvitationId) } returns
            Response.error(404, "Not Found".toResponseBody())

        val result = repository.revokeInvitation(testInvitationId)

        assertTrue(result is Result.Error)
        assertTrue((result as Result.Error).exception is AppException.NotFound)
    }

    @Test
    fun `revokeInvitation returns conflict on 409`() = runTest {
        coEvery { apiService.revokeInvitation(testInvitationId) } returns
            Response.error(409, "Conflict".toResponseBody())

        val result = repository.revokeInvitation(testInvitationId)

        assertTrue(result is Result.Error)
        assertTrue((result as Result.Error).exception is AppException.Conflict)
    }

    @Test
    fun `revokeInvitation returns network error on exception`() = runTest {
        coEvery { apiService.revokeInvitation(testInvitationId) } throws
            java.io.IOException("Network error")

        val result = repository.revokeInvitation(testInvitationId)

        assertTrue(result is Result.Error)
        assertTrue((result as Result.Error).exception is AppException.Network)
    }

    // ==================== lookupInviteCode Tests ====================

    @Test
    fun `lookupInviteCode returns invite info on success`() = runTest {
        val dto = InviteCodeInfoDto(
            id = "inv-123",
            tenantName = "Acme Corp",
            role = "member",
            shortCode = "ACME-7K9X",
            expiresAt = "2024-07-01T00:00:00Z"
        )
        coEvery { apiService.getInviteByCode("ACME-7K9X") } returns
            Response.success(InviteCodeInfoResponse(data = dto))

        val result = repository.lookupInviteCode("ACME-7K9X")

        assertTrue(result is Result.Success)
        val info = (result as Result.Success).data
        assertEquals("inv-123", info.id)
        assertEquals("Acme Corp", info.tenantName)
        assertEquals(UserRole.USER, info.role)
        assertEquals("ACME-7K9X", info.shortCode)
    }

    @Test
    fun `lookupInviteCode returns not found on 404`() = runTest {
        coEvery { apiService.getInviteByCode("BAD-CODE") } returns
            Response.error(404, "Not Found".toResponseBody())

        val result = repository.lookupInviteCode("BAD-CODE")

        assertTrue(result is Result.Error)
        assertTrue((result as Result.Error).exception is AppException.NotFound)
    }

    @Test
    fun `lookupInviteCode returns error on 410 expired`() = runTest {
        coEvery { apiService.getInviteByCode("OLD-CODE") } returns
            Response.error(410, "Gone".toResponseBody())

        val result = repository.lookupInviteCode("OLD-CODE")

        assertTrue(result is Result.Error)
        assertTrue((result as Result.Error).exception.message!!.contains("expired"))
    }

    @Test
    fun `lookupInviteCode returns network error on exception`() = runTest {
        coEvery { apiService.getInviteByCode(any()) } throws
            java.io.IOException("Network error")

        val result = repository.lookupInviteCode("ANY-CODE")

        assertTrue(result is Result.Error)
        assertTrue((result as Result.Error).exception is AppException.Network)
    }

    // ==================== acceptInvitationById Tests ====================

    @Test
    fun `acceptInvitationById delegates to acceptInvitation`() = runTest {
        val acceptedDto = InvitationAcceptedDto(
            id = testInvitationId,
            tenantId = testTenantId,
            role = "member",
            status = "accepted",
            joinedAt = "2024-06-01T00:00:00Z"
        )
        coEvery { apiService.acceptInvitation(testInvitationId) } returns
            Response.success(InvitationAcceptedResponse(data = acceptedDto))
        coEvery { apiService.getUserTenants() } returns
            Response.success(TenantsResponse(data = listOf(createTestTenantDto())))

        val result = repository.acceptInvitationById(testInvitationId)

        assertTrue(result is Result.Success)
        val accepted = (result as Result.Success).data
        assertEquals(testInvitationId, accepted.id)
        assertEquals(testTenantId, accepted.tenantId)
        assertEquals(UserRole.USER, accepted.role)
    }

    @Test
    fun `acceptInvitationById returns error on failure`() = runTest {
        coEvery { apiService.acceptInvitation(testInvitationId) } returns
            Response.error(404, "Not Found".toResponseBody())

        val result = repository.acceptInvitationById(testInvitationId)

        assertTrue(result is Result.Error)
        assertTrue((result as Result.Error).exception is AppException.NotFound)
    }

    // ==================== getPqcAlgorithm Tests ====================

    @Test
    fun `getPqcAlgorithm delegates to crypto config`() {
        every { cryptoConfig.getAlgorithm() } returns PqcAlgorithm.KAZ

        val result = repository.getPqcAlgorithm()

        assertEquals(PqcAlgorithm.KAZ, result)
        verify { cryptoConfig.getAlgorithm() }
    }

    // ==================== saveTenantContext Tests ====================

    @Test
    fun `saveTenantContext persists to secure storage and updates flow`() = runTest {
        val context = my.ssdid.drive.domain.model.TenantContext(
            currentTenantId = testTenantId,
            currentRole = UserRole.ADMIN,
            availableTenants = emptyList()
        )

        repository.saveTenantContext(context)

        coVerify { secureStorage.saveTenantId(testTenantId) }
        coVerify { secureStorage.saveCurrentRole("admin") }
        coVerify { secureStorage.saveUserTenants(any()) }
    }

    // ==================== clearTenantData Tests ====================

    @Test
    fun `clearTenantData resets tenant context flow`() = runTest {
        repository.clearTenantData()

        // After clearing, the in-memory flow is null.
        // Set up secureStorage to also return null so getCurrentTenantContext falls through.
        coEvery { secureStorage.getTenantId() } returns null

        val context = repository.getCurrentTenantContext()
        assertNull(context)
    }

    // ==================== Helper Functions ====================

    private fun createTestTenantDto(
        id: String = testTenantId,
        name: String = "Test Org",
        slug: String = "test-org",
        role: String = "admin"
    ) = TenantDto(
        id = id,
        name = name,
        slug = slug,
        role = role,
        joinedAt = "2024-01-01T00:00:00Z"
    )

    private fun createTestTenantConfigDto() = TenantConfigDto(
        id = testTenantId,
        name = "Test Org",
        slug = "test-org",
        pqcAlgorithm = "kaz",
        plan = "pro",
        settings = mapOf("max_file_size" to 104857600.0)
    )

    private fun createTestUserDto(
        id: String = testUserId,
        email: String = "test@test.com"
    ) = UserDto(
        id = id,
        email = email,
        tenantId = testTenantId,
        role = "user",
        publicKeys = PublicKeysDto(
            kem = "base64key",
            sign = "base64key",
            mlKem = null,
            mlDsa = null
        ),
        encryptedMasterKey = "encrypted",
        encryptedPrivateKeys = "encrypted",
        keyDerivationSalt = "salt",
        storageQuota = 1073741824,
        storageUsed = 0,
        insertedAt = "2024-01-01T00:00:00Z",
        updatedAt = "2024-01-01T00:00:00Z"
    )

    private fun createTestMemberDto(
        id: String = "member-1",
        userId: String = testUserId,
        role: String = "admin"
    ) = MemberDto(
        id = id,
        userId = userId,
        email = "member@test.com",
        displayName = "Test Member",
        role = role,
        status = "active",
        joinedAt = "2024-01-01T00:00:00Z"
    )

    private fun createTestInvitationDto(
        id: String = testInvitationId,
        tenantName: String = "Test Org"
    ) = InvitationDto(
        id = id,
        tenantId = testTenantId,
        tenantName = tenantName,
        tenantSlug = "test-org",
        role = "member",
        invitedBy = InviterDto(
            id = "inviter-1",
            email = "inviter@test.com",
            displayName = "Inviter"
        ),
        invitedAt = "2024-06-01T00:00:00Z"
    )
}
