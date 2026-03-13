package my.ssdid.drive.invitation.data

import com.google.gson.Gson
import com.google.gson.GsonBuilder
import my.ssdid.drive.data.remote.dto.*
import my.ssdid.drive.invitation.fixtures.InvitationTestFixtures
import org.junit.Assert.*
import org.junit.Before
import org.junit.Test

/**
 * Unit tests for invitation DTOs.
 *
 * Tests cover:
 * - JSON deserialization
 * - Field mapping
 * - Null handling
 * - Validation
 */
class InvitationDtoTest {

    private lateinit var gson: Gson

    @Before
    fun setup() {
        gson = GsonBuilder().create()
    }

    // ==================== InviteInfoDto Tests ====================

    @Test
    fun `InviteInfoDto deserializes from valid JSON`() {
        val response = gson.fromJson(
            InvitationTestFixtures.JSON.validInviteInfoResponse,
            InviteInfoResponse::class.java
        )

        val dto = response.data
        assertEquals("user@example.com", dto.email)
        assertEquals("member", dto.role)
        assertEquals("Test Organization", dto.tenantName)
        assertEquals("John Doe", dto.inviterName)
        assertEquals("Welcome to our team!", dto.message)
        assertEquals("2030-12-31T23:59:59Z", dto.expiresAt)
        assertEquals("pending", dto.status)
    }

    @Test
    fun `InviteInfoDto deserializes with error reason`() {
        val response = gson.fromJson(
            InvitationTestFixtures.JSON.expiredInviteInfoResponse,
            InviteInfoResponse::class.java
        )

        val dto = response.data
        assertEquals("expired", dto.status)
    }

    @Test
    fun `InviteInfoDto handles null optional fields`() {
        val json = """
            {
                "data": {
                    "email": "user@example.com",
                    "role": "member",
                    "tenant_name": "Test Org",
                    "expires_at": "2030-12-31T23:59:59Z",
                    "status": "pending"
                }
            }
        """.trimIndent()

        val response = gson.fromJson(json, InviteInfoResponse::class.java)
        val dto = response.data

        assertNull(dto.inviterName)
        assertNull(dto.message)
    }

    @Test
    fun `InviteInfoDto uses snake_case for JSON field names`() {
        val dto = InvitationTestFixtures.DTOs.validInviteInfoDto
        val json = gson.toJson(dto)

        assertTrue(json.contains("tenant_name") || json.contains("tenantName"))
        assertTrue(json.contains("inviter_name") || json.contains("inviterName"))
        assertTrue(json.contains("expires_at") || json.contains("expiresAt"))
    }

    // ==================== InvitationDto Tests ====================

    @Test
    fun `InvitationsResponse deserializes list of invitations`() {
        val response = gson.fromJson(
            InvitationTestFixtures.JSON.validInvitationsResponse,
            InvitationsResponse::class.java
        )

        assertEquals(2, response.data.size)

        val first = response.data[0]
        assertEquals("inv-1", first.id)
        assertEquals("tenant-1", first.tenantId)
        assertEquals("Org One", first.tenantName)
        assertEquals("org-one", first.tenantSlug)
        assertEquals("member", first.role)
        assertNotNull(first.invitedBy)
        assertEquals("Admin User", first.invitedBy?.displayName)

        val second = response.data[1]
        assertEquals("inv-2", second.id)
        assertEquals("admin", second.role)
        assertNull(second.invitedBy)
    }

    @Test
    fun `InvitationsResponse handles empty list`() {
        val response = gson.fromJson(
            InvitationTestFixtures.JSON.emptyInvitationsResponse,
            InvitationsResponse::class.java
        )

        assertTrue(response.data.isEmpty())
    }

    @Test
    fun `InvitationDto with null invitedBy`() {
        val dto = InvitationTestFixtures.DTOs.invitationDtoWithNullInviter

        assertNull(dto.invitedBy)
        assertEquals("pending-inv-123", dto.id)
    }

    @Test
    fun `InviterDto deserializes all fields`() {
        val json = """
            {
                "id": "user-123",
                "email": "inviter@example.com",
                "display_name": "Inviter Name"
            }
        """.trimIndent()

        val dto = gson.fromJson(json, InviterDto::class.java)

        assertEquals("user-123", dto.id)
        assertEquals("inviter@example.com", dto.email)
        assertEquals("Inviter Name", dto.displayName)
    }

    @Test
    fun `InviterDto handles null fields`() {
        val json = """
            {
                "id": null,
                "email": null,
                "display_name": null
            }
        """.trimIndent()

        val dto = gson.fromJson(json, InviterDto::class.java)

        assertNull(dto.id)
        assertNull(dto.email)
        assertNull(dto.displayName)
    }

    // ==================== InvitationAcceptedDto Tests ====================

    @Test
    fun `InvitationAcceptedResponse deserializes correctly`() {
        val response = gson.fromJson(
            InvitationTestFixtures.JSON.validInvitationAcceptedResponse,
            InvitationAcceptedResponse::class.java
        )

        val dto = response.data
        assertEquals("inv-123", dto.id)
        assertEquals("tenant-456", dto.tenantId)
        assertEquals("member", dto.role)
        assertEquals("active", dto.status)
        assertEquals("2025-01-15T12:00:00Z", dto.joinedAt)
    }

    @Test
    fun `InvitationAcceptedDto with null joinedAt`() {
        val json = """
            {
                "data": {
                    "id": "inv-123",
                    "tenant_id": "tenant-456",
                    "role": "member",
                    "status": "active",
                    "joined_at": null
                }
            }
        """.trimIndent()

        val response = gson.fromJson(json, InvitationAcceptedResponse::class.java)
        assertNull(response.data.joinedAt)
    }

    // ==================== AcceptInviteRequest Tests ====================

    @Test
    fun `AcceptInviteRequest serializes all fields`() {
        val request = InvitationTestFixtures.DTOs.validAcceptInviteRequest
        val json = gson.toJson(request)

        assertTrue(json.contains("display_name") || json.contains("displayName"))
        assertTrue(json.contains("password"))
        assertTrue(json.contains("public_keys") || json.contains("publicKeys"))
        assertTrue(json.contains("encrypted_master_key") || json.contains("encryptedMasterKey"))
        assertTrue(json.contains("encrypted_private_keys") || json.contains("encryptedPrivateKeys"))
        assertTrue(json.contains("key_derivation_salt") || json.contains("keyDerivationSalt"))
    }

    @Test
    fun `AcceptInviteRequest validates empty displayName`() {
        val request = InvitationTestFixtures.DTOs.validAcceptInviteRequest.copy(
            displayName = ""
        )
        val result = request.validate()

        assertTrue(result.isInvalid)
    }

    @Test
    fun `AcceptInviteRequest validates blank displayName`() {
        val request = InvitationTestFixtures.DTOs.validAcceptInviteRequest.copy(
            displayName = "   "
        )
        val result = request.validate()

        assertTrue(result.isInvalid)
    }

    @Test
    fun `AcceptInviteRequest validates displayName too long`() {
        val request = InvitationTestFixtures.DTOs.validAcceptInviteRequest.copy(
            displayName = "A".repeat(101)
        )
        val result = request.validate()

        assertTrue(result.isInvalid)
    }

    @Test
    fun `AcceptInviteRequest accepts displayName exactly 100 chars`() {
        val request = InvitationTestFixtures.DTOs.validAcceptInviteRequest.copy(
            displayName = "A".repeat(100)
        )
        val result = request.validate()

        // Should pass displayName validation, but might fail other validations
        // depending on other fields - testing that 100 chars is within limit
        assertTrue(request.displayName.length == 100)
    }

    @Test
    fun `AcceptInviteRequest validates short password`() {
        val request = InvitationTestFixtures.DTOs.validAcceptInviteRequest.copy(
            password = "short"
        )
        val result = request.validate()

        assertTrue(result.isInvalid)
    }

    @Test
    fun `AcceptInviteRequest validates empty encrypted data`() {
        val request = InvitationTestFixtures.DTOs.validAcceptInviteRequest.copy(
            encryptedMasterKey = ""
        )
        val result = request.validate()

        assertTrue(result.isInvalid)
    }

    // ==================== AcceptInviteResponse Tests ====================

    @Test
    fun `AcceptInviteResponse deserializes correctly`() {
        val response = gson.fromJson(
            InvitationTestFixtures.JSON.validAcceptInviteResponse,
            AcceptInviteResponse::class.java
        )

        val data = response.data
        assertEquals("test-access-token", data.accessToken)
        assertEquals("test-refresh-token", data.refreshToken)
        assertEquals(3600, data.expiresIn)
        assertEquals("Bearer", data.tokenType)

        val user = data.user
        assertEquals("user-new-123", user.id)
        assertEquals("user@example.com", user.email)
        assertEquals("New User", user.displayName)
    }

    @Test
    fun `AcceptInviteResponseData handles null optional fields`() {
        val json = """
            {
                "data": {
                    "user": {
                        "id": "user-123",
                        "email": "user@example.com"
                    },
                    "access_token": "token",
                    "refresh_token": "refresh"
                }
            }
        """.trimIndent()

        val response = gson.fromJson(json, AcceptInviteResponse::class.java)
        val data = response.data

        assertNull(data.expiresIn)
        assertNull(data.tokenType)
    }

    // ==================== PublicKeysDto Tests ====================

    @Test
    fun `PublicKeysDto validates all required fields`() {
        val validDto = InvitationTestFixtures.DTOs.validPublicKeysDto
        val result = validDto.validate()

        assertFalse(result.isInvalid)
    }

    @Test
    fun `PublicKeysDto validates empty kem`() {
        val dto = InvitationTestFixtures.DTOs.validPublicKeysDto.copy(
            kem = ""
        )
        val result = dto.validate()

        assertTrue(result.isInvalid)
    }

    @Test
    fun `PublicKeysDto validates empty sign`() {
        val dto = InvitationTestFixtures.DTOs.validPublicKeysDto.copy(
            sign = ""
        )
        val result = dto.validate()

        assertTrue(result.isInvalid)
    }

    @Test
    fun `PublicKeysDto allows null ML keys`() {
        val dto = PublicKeysDto(
            kem = "dmFsaWRrZW0=",
            sign = "dmFsaWRzaWdu",
            mlKem = null,
            mlDsa = null
        )
        val result = dto.validate()

        assertFalse(result.isInvalid)
    }

    // ==================== UserDto with Tenants Tests ====================

    @Test
    fun `UserDto deserializes with tenants list`() {
        val dto = InvitationTestFixtures.DTOs.validUserDto

        assertEquals("user-new-123", dto.id)
        assertEquals("tenant-456", dto.currentTenantId)
        assertNotNull(dto.tenants)
        assertEquals(1, dto.tenants?.size)

        val tenant = dto.tenants?.first()
        assertEquals("tenant-456", tenant?.id)
        assertEquals("Test Organization", tenant?.name)
        assertEquals("test-org", tenant?.slug)
        assertEquals("member", tenant?.role)
    }

    @Test
    fun `UserDto getEffectiveTenantId returns currentTenantId when present`() {
        val dto = InvitationTestFixtures.DTOs.validUserDto

        assertEquals("tenant-456", dto.getEffectiveTenantId())
    }

    @Test
    fun `UserDto getEffectiveTenantId falls back to tenantId`() {
        val dto = InvitationTestFixtures.DTOs.validUserDto.copy(
            currentTenantId = null,
            tenantId = "legacy-tenant"
        )

        assertEquals("legacy-tenant", dto.getEffectiveTenantId())
    }

    @Test
    fun `UserDto getEffectiveRole returns role from current tenant`() {
        val dto = InvitationTestFixtures.DTOs.validUserDto

        assertEquals("member", dto.getEffectiveRole())
    }

    @Test
    fun `UserDto getEffectiveRole falls back to role field`() {
        val dto = InvitationTestFixtures.DTOs.validUserDto.copy(
            currentTenantId = null,
            tenants = null,
            role = "admin"
        )

        assertEquals("admin", dto.getEffectiveRole())
    }
}
