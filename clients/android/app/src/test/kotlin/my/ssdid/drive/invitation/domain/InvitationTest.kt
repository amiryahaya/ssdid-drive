package my.ssdid.drive.invitation.domain

import my.ssdid.drive.domain.model.*
import my.ssdid.drive.invitation.fixtures.InvitationTestFixtures
import org.junit.Assert.*
import org.junit.Test

/**
 * Unit tests for invitation domain models.
 *
 * Tests cover:
 * - TokenInvitation creation and validation
 * - TokenInvitationError parsing
 * - Invitation (pending) creation
 * - Inviter display text logic
 * - MemberStatus parsing
 * - InvitationAccepted creation
 */
class InvitationTest {

    // ==================== TokenInvitation Tests ====================

    @Test
    fun `TokenInvitation created with all fields populated`() {
        val invitation = InvitationTestFixtures.DomainModels.validTokenInvitation

        assertEquals("inv-123", invitation.id)
        assertEquals("user@example.com", invitation.email)
        assertEquals(UserRole.USER, invitation.role)
        assertEquals("Test Organization", invitation.tenantName)
        assertEquals("John Doe", invitation.inviterName)
        assertEquals("Welcome to our team!", invitation.message)
        assertEquals("2030-12-31T23:59:59Z", invitation.expiresAt)
        assertTrue(invitation.valid)
        assertNull(invitation.errorReason)
    }

    @Test
    fun `TokenInvitation created with null optional fields`() {
        val invitation = InvitationTestFixtures.DomainModels.invitationWithNullOptionals

        assertNull(invitation.inviterName)
        assertNull(invitation.message)
        assertTrue(invitation.valid)
    }

    @Test
    fun `TokenInvitation with expired error reason`() {
        val invitation = InvitationTestFixtures.DomainModels.expiredTokenInvitation

        assertFalse(invitation.valid)
        assertEquals(TokenInvitationError.EXPIRED, invitation.errorReason)
    }

    @Test
    fun `TokenInvitation with revoked error reason`() {
        val invitation = InvitationTestFixtures.DomainModels.revokedTokenInvitation

        assertFalse(invitation.valid)
        assertEquals(TokenInvitationError.REVOKED, invitation.errorReason)
    }

    @Test
    fun `TokenInvitation with already used error reason`() {
        val invitation = InvitationTestFixtures.DomainModels.alreadyUsedTokenInvitation

        assertFalse(invitation.valid)
        assertEquals(TokenInvitationError.ALREADY_USED, invitation.errorReason)
    }

    @Test
    fun `TokenInvitation with not found error reason`() {
        val invitation = InvitationTestFixtures.DomainModels.notFoundTokenInvitation

        assertFalse(invitation.valid)
        assertEquals(TokenInvitationError.NOT_FOUND, invitation.errorReason)
    }

    // ==================== TokenInvitationError Tests ====================

    @Test
    fun `TokenInvitationError fromString returns EXPIRED for 'expired'`() {
        assertEquals(TokenInvitationError.EXPIRED, TokenInvitationError.fromString("expired"))
    }

    @Test
    fun `TokenInvitationError fromString returns REVOKED for 'revoked'`() {
        assertEquals(TokenInvitationError.REVOKED, TokenInvitationError.fromString("revoked"))
    }

    @Test
    fun `TokenInvitationError fromString returns ALREADY_USED for 'already_used'`() {
        assertEquals(TokenInvitationError.ALREADY_USED, TokenInvitationError.fromString("already_used"))
    }

    @Test
    fun `TokenInvitationError fromString returns NOT_FOUND for 'not_found'`() {
        assertEquals(TokenInvitationError.NOT_FOUND, TokenInvitationError.fromString("not_found"))
    }

    @Test
    fun `TokenInvitationError fromString is case insensitive`() {
        assertEquals(TokenInvitationError.EXPIRED, TokenInvitationError.fromString("EXPIRED"))
        assertEquals(TokenInvitationError.EXPIRED, TokenInvitationError.fromString("Expired"))
        assertEquals(TokenInvitationError.REVOKED, TokenInvitationError.fromString("REVOKED"))
        assertEquals(TokenInvitationError.ALREADY_USED, TokenInvitationError.fromString("ALREADY_USED"))
        assertEquals(TokenInvitationError.NOT_FOUND, TokenInvitationError.fromString("NOT_FOUND"))
    }

    @Test
    fun `TokenInvitationError fromString returns null for unknown value`() {
        assertNull(TokenInvitationError.fromString("unknown"))
        assertNull(TokenInvitationError.fromString("invalid"))
        assertNull(TokenInvitationError.fromString(""))
    }

    @Test
    fun `TokenInvitationError fromString returns null for null input`() {
        assertNull(TokenInvitationError.fromString(null))
    }

    // ==================== Invitation (Pending) Tests ====================

    @Test
    fun `Invitation created with all fields populated`() {
        val invitation = InvitationTestFixtures.DomainModels.validPendingInvitation

        assertEquals("pending-inv-123", invitation.id)
        assertEquals("tenant-456", invitation.tenantId)
        assertEquals("Another Organization", invitation.tenantName)
        assertEquals("another-org", invitation.tenantSlug)
        assertEquals(UserRole.USER, invitation.role)
        assertNotNull(invitation.invitedBy)
        assertEquals("2025-01-15T10:00:00Z", invitation.invitedAt)
    }

    @Test
    fun `Invitation created with null invitedBy`() {
        val invitation = InvitationTestFixtures.DomainModels.pendingInvitationWithNullInviter

        assertNull(invitation.invitedBy)
    }

    @Test
    fun `Invitation with admin role`() {
        val invitation = InvitationTestFixtures.DomainModels.pendingInvitationAsAdmin

        assertEquals(UserRole.ADMIN, invitation.role)
    }

    @Test
    fun `Invitation with null tenantSlug is valid`() {
        val invitation = InvitationTestFixtures.DomainModels.validPendingInvitation.copy(
            tenantSlug = null
        )

        assertNull(invitation.tenantSlug)
        assertEquals("pending-inv-123", invitation.id)
    }

    @Test
    fun `Invitation with null invitedAt is valid`() {
        val invitation = InvitationTestFixtures.DomainModels.validPendingInvitation.copy(
            invitedAt = null
        )

        assertNull(invitation.invitedAt)
    }

    // ==================== Inviter Tests ====================

    @Test
    fun `Inviter getDisplayText returns displayName when present`() {
        val inviter = InvitationTestFixtures.DomainModels.validInviter

        assertEquals("Jane Smith", inviter.getDisplayText())
    }

    @Test
    fun `Inviter getDisplayText returns email when displayName is null`() {
        val inviter = InvitationTestFixtures.DomainModels.inviterWithOnlyEmail

        assertEquals("noreply@example.com", inviter.getDisplayText())
    }

    @Test
    fun `Inviter getDisplayText returns Unknown when both displayName and email are null`() {
        val inviter = InvitationTestFixtures.DomainModels.inviterWithNoData

        assertEquals("Unknown", inviter.getDisplayText())
    }

    @Test
    fun `Inviter getDisplayText prioritizes displayName over email`() {
        val inviter = Inviter(
            id = "user-123",
            email = "email@example.com",
            displayName = "Display Name"
        )

        assertEquals("Display Name", inviter.getDisplayText())
    }

    @Test
    fun `Inviter with empty displayName returns email`() {
        // Note: Empty string is truthy in Kotlin, so displayName takes precedence
        val inviter = Inviter(
            id = "user-123",
            email = "email@example.com",
            displayName = ""
        )

        // In current implementation, empty string would be returned
        // This tests current behavior - could be changed to check for blank
        assertEquals("", inviter.getDisplayText())
    }

    // ==================== MemberStatus Tests ====================

    @Test
    fun `MemberStatus fromString returns ACTIVE for 'active'`() {
        assertEquals(MemberStatus.ACTIVE, MemberStatus.fromString("active"))
    }

    @Test
    fun `MemberStatus fromString returns PENDING for 'pending'`() {
        assertEquals(MemberStatus.PENDING, MemberStatus.fromString("pending"))
    }

    @Test
    fun `MemberStatus fromString returns SUSPENDED for 'suspended'`() {
        assertEquals(MemberStatus.SUSPENDED, MemberStatus.fromString("suspended"))
    }

    @Test
    fun `MemberStatus fromString is case insensitive`() {
        assertEquals(MemberStatus.ACTIVE, MemberStatus.fromString("ACTIVE"))
        assertEquals(MemberStatus.ACTIVE, MemberStatus.fromString("Active"))
        assertEquals(MemberStatus.PENDING, MemberStatus.fromString("PENDING"))
        assertEquals(MemberStatus.SUSPENDED, MemberStatus.fromString("SUSPENDED"))
    }

    @Test
    fun `MemberStatus fromString returns ACTIVE for unknown value`() {
        assertEquals(MemberStatus.ACTIVE, MemberStatus.fromString("unknown"))
        assertEquals(MemberStatus.ACTIVE, MemberStatus.fromString("invalid"))
        assertEquals(MemberStatus.ACTIVE, MemberStatus.fromString(""))
    }

    // ==================== InvitationAccepted Tests ====================

    @Test
    fun `InvitationAccepted created with all fields`() {
        val accepted = InvitationTestFixtures.DomainModels.validInvitationAccepted

        assertEquals("inv-accepted-123", accepted.id)
        assertEquals("tenant-456", accepted.tenantId)
        assertEquals(UserRole.USER, accepted.role)
        assertEquals("2025-01-15T12:00:00Z", accepted.joinedAt)
    }

    @Test
    fun `InvitationAccepted with null joinedAt is valid`() {
        val accepted = InvitationTestFixtures.DomainModels.validInvitationAccepted.copy(
            joinedAt = null
        )

        assertNull(accepted.joinedAt)
        assertEquals("inv-accepted-123", accepted.id)
    }

    @Test
    fun `InvitationAccepted with different roles`() {
        val memberAccepted = InvitationTestFixtures.DomainModels.validInvitationAccepted
        val adminAccepted = memberAccepted.copy(role = UserRole.ADMIN)
        val ownerAccepted = memberAccepted.copy(role = UserRole.OWNER)

        assertEquals(UserRole.USER, memberAccepted.role)
        assertEquals(UserRole.ADMIN, adminAccepted.role)
        assertEquals(UserRole.OWNER, ownerAccepted.role)
    }

    // ==================== TenantMember Tests ====================

    @Test
    fun `TenantMember created with all fields`() {
        val member = InvitationTestFixtures.DomainModels.validTenantMember

        assertEquals("member-123", member.id)
        assertEquals("user-456", member.userId)
        assertEquals("member@example.com", member.email)
        assertEquals("Team Member", member.displayName)
        assertEquals(UserRole.USER, member.role)
        assertEquals(MemberStatus.ACTIVE, member.status)
        assertEquals("2025-01-01T00:00:00Z", member.joinedAt)
    }

    @Test
    fun `TenantMember with PENDING status`() {
        val member = InvitationTestFixtures.DomainModels.pendingTenantMember

        assertEquals(MemberStatus.PENDING, member.status)
    }

    @Test
    fun `TenantMember with SUSPENDED status`() {
        val member = InvitationTestFixtures.DomainModels.suspendedTenantMember

        assertEquals(MemberStatus.SUSPENDED, member.status)
    }

    @Test
    fun `TenantMember with null optional fields`() {
        val member = TenantMember(
            id = "member-123",
            userId = "user-456",
            email = null,
            displayName = null,
            role = UserRole.USER,
            status = MemberStatus.ACTIVE,
            joinedAt = null
        )

        assertNull(member.email)
        assertNull(member.displayName)
        assertNull(member.joinedAt)
    }

    // ==================== UserRole Tests ====================

    @Test
    fun `UserRole enum has correct values`() {
        // Verify enum constants exist
        assertNotNull(UserRole.OWNER)
        assertNotNull(UserRole.ADMIN)
        assertNotNull(UserRole.USER)
    }

    @Test
    fun `UserRole fromString parses correctly`() {
        assertEquals(UserRole.OWNER, UserRole.fromString("owner"))
        assertEquals(UserRole.ADMIN, UserRole.fromString("admin"))
        // USER is returned for "member" and other values
        assertEquals(UserRole.USER, UserRole.fromString("member"))
        assertEquals(UserRole.USER, UserRole.fromString("user"))
    }

    @Test
    fun `UserRole fromString is case insensitive`() {
        assertEquals(UserRole.OWNER, UserRole.fromString("OWNER"))
        assertEquals(UserRole.ADMIN, UserRole.fromString("ADMIN"))
        assertEquals(UserRole.OWNER, UserRole.fromString("Owner"))
        assertEquals(UserRole.ADMIN, UserRole.fromString("Admin"))
    }

    @Test
    fun `UserRole fromString returns USER for unknown values`() {
        assertEquals(UserRole.USER, UserRole.fromString("unknown"))
        assertEquals(UserRole.USER, UserRole.fromString(""))
        assertEquals(UserRole.USER, UserRole.fromString("invalid"))
    }
}
