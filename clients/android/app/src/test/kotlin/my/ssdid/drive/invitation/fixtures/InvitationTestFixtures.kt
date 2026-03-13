package my.ssdid.drive.invitation.fixtures

import my.ssdid.drive.data.remote.dto.*
import my.ssdid.drive.domain.model.*

/**
 * Test fixtures for invitation system tests.
 * Provides consistent test data across all test classes.
 */
object InvitationTestFixtures {

    // ==================== Domain Models ====================

    object DomainModels {
        val validTokenInvitation = TokenInvitation(
            email = "user@example.com",
            role = UserRole.USER,
            tenantName = "Test Organization",
            inviterName = "John Doe",
            message = "Welcome to our team!",
            expiresAt = "2030-12-31T23:59:59Z",
            valid = true,
            errorReason = null
        )

        val expiredTokenInvitation = validTokenInvitation.copy(
            valid = false,
            errorReason = TokenInvitationError.EXPIRED
        )

        val revokedTokenInvitation = validTokenInvitation.copy(
            valid = false,
            errorReason = TokenInvitationError.REVOKED
        )

        val alreadyUsedTokenInvitation = validTokenInvitation.copy(
            valid = false,
            errorReason = TokenInvitationError.ALREADY_USED
        )

        val notFoundTokenInvitation = validTokenInvitation.copy(
            valid = false,
            errorReason = TokenInvitationError.NOT_FOUND
        )

        val invitationWithNullOptionals = validTokenInvitation.copy(
            inviterName = null,
            message = null
        )

        val validInviter = Inviter(
            id = "user-456",
            email = "inviter@example.com",
            displayName = "Jane Smith"
        )

        val inviterWithOnlyEmail = Inviter(
            id = "user-789",
            email = "noreply@example.com",
            displayName = null
        )

        val inviterWithNoData = Inviter(
            id = null,
            email = null,
            displayName = null
        )

        val validPendingInvitation = Invitation(
            id = "pending-inv-123",
            tenantId = "tenant-456",
            tenantName = "Another Organization",
            tenantSlug = "another-org",
            role = UserRole.USER,
            invitedBy = validInviter,
            invitedAt = "2025-01-15T10:00:00Z"
        )

        val pendingInvitationWithNullInviter = validPendingInvitation.copy(
            invitedBy = null
        )

        val pendingInvitationAsAdmin = validPendingInvitation.copy(
            role = UserRole.ADMIN
        )

        val validInvitationAccepted = InvitationAccepted(
            id = "inv-accepted-123",
            tenantId = "tenant-456",
            role = UserRole.USER,
            joinedAt = "2025-01-15T12:00:00Z"
        )

        val validTenantMember = TenantMember(
            id = "member-123",
            userId = "user-456",
            email = "member@example.com",
            displayName = "Team Member",
            role = UserRole.USER,
            status = MemberStatus.ACTIVE,
            joinedAt = "2025-01-01T00:00:00Z"
        )

        val pendingTenantMember = validTenantMember.copy(
            status = MemberStatus.PENDING
        )

        val suspendedTenantMember = validTenantMember.copy(
            status = MemberStatus.SUSPENDED
        )
    }

    // ==================== DTOs ====================

    object DTOs {
        val validInviteInfoDto = InviteInfoDto(
            email = "user@example.com",
            role = "member",
            tenantName = "Test Organization",
            inviterName = "John Doe",
            message = "Welcome to our team!",
            expiresAt = "2030-12-31T23:59:59Z",
            status = "pending"
        )

        val expiredInviteInfoDto = validInviteInfoDto.copy(
            status = "expired"
        )

        val revokedInviteInfoDto = validInviteInfoDto.copy(
            status = "revoked"
        )

        val alreadyUsedInviteInfoDto = validInviteInfoDto.copy(
            status = "accepted"
        )

        val inviteInfoDtoWithNullOptionals = validInviteInfoDto.copy(
            inviterName = null,
            message = null
        )

        val validInviterDto = InviterDto(
            id = "user-456",
            email = "inviter@example.com",
            displayName = "Jane Smith"
        )

        val validInvitationDto = InvitationDto(
            id = "pending-inv-123",
            tenantId = "tenant-456",
            tenantName = "Another Organization",
            tenantSlug = "another-org",
            role = "member",
            invitedBy = validInviterDto,
            invitedAt = "2025-01-15T10:00:00Z"
        )

        val invitationDtoWithNullInviter = validInvitationDto.copy(
            invitedBy = null
        )

        val validInvitationAcceptedDto = InvitationAcceptedDto(
            id = "inv-accepted-123",
            tenantId = "tenant-456",
            role = "member",
            status = "active",
            joinedAt = "2025-01-15T12:00:00Z"
        )

        val validPublicKeysDto = PublicKeysDto(
            kem = "YmFzZTY0a2VtcHVibGlja2V5",
            sign = "YmFzZTY0c2lnbnB1YmxpY2tleQ==",
            mlKem = "YmFzZTY0bWxrZW1wdWJsaWNrZXk=",
            mlDsa = "YmFzZTY0bWxkc2FwdWJsaWNrZXk="
        )

        val validAcceptInviteRequest = AcceptInviteRequest(
            displayName = "New User",
            password = "securePassword123",
            publicKeys = validPublicKeysDto,
            encryptedMasterKey = "ZW5jcnlwdGVkbWFzdGVya2V5",
            encryptedPrivateKeys = "ZW5jcnlwdGVkcHJpdmF0ZWtleXM=",
            keyDerivationSalt = "a2V5ZGVyaXZhdGlvbnNhbHQ="
        )

        val validUserDto = UserDto(
            id = "user-new-123",
            email = "user@example.com",
            displayName = "New User",
            status = "active",
            tenants = listOf(
                TenantDto(
                    id = "tenant-456",
                    name = "Test Organization",
                    slug = "test-org",
                    role = "member",
                    joinedAt = "2025-01-15T12:00:00Z"
                )
            ),
            currentTenantId = "tenant-456",
            publicKeys = validPublicKeysDto,
            storageQuota = 1073741824L,
            storageUsed = 0L
        )

        val validAcceptInviteResponseData = AcceptInviteResponseData(
            user = validUserDto,
            accessToken = "test-access-token",
            refreshToken = "test-refresh-token",
            expiresIn = 3600,
            tokenType = "Bearer"
        )
    }

    // ==================== JSON Strings ====================

    object JSON {
        val validInviteInfoResponse = """
            {
                "data": {
                    "email": "user@example.com",
                    "role": "member",
                    "tenant_name": "Test Organization",
                    "inviter_name": "John Doe",
                    "message": "Welcome to our team!",
                    "expires_at": "2030-12-31T23:59:59Z",
                    "status": "pending"
                }
            }
        """.trimIndent()

        val expiredInviteInfoResponse = """
            {
                "data": {
                    "email": "user@example.com",
                    "role": "member",
                    "tenant_name": "Test Organization",
                    "expires_at": "2020-01-01T00:00:00Z",
                    "status": "expired"
                }
            }
        """.trimIndent()

        val validInvitationsResponse = """
            {
                "data": [
                    {
                        "id": "inv-1",
                        "tenant_id": "tenant-1",
                        "tenant_name": "Org One",
                        "tenant_slug": "org-one",
                        "role": "member",
                        "invited_by": {
                            "id": "user-1",
                            "email": "admin@org-one.com",
                            "display_name": "Admin User"
                        },
                        "invited_at": "2025-01-15T10:00:00Z"
                    },
                    {
                        "id": "inv-2",
                        "tenant_id": "tenant-2",
                        "tenant_name": "Org Two",
                        "tenant_slug": "org-two",
                        "role": "admin",
                        "invited_by": null,
                        "invited_at": "2025-01-14T09:00:00Z"
                    }
                ]
            }
        """.trimIndent()

        val emptyInvitationsResponse = """
            {
                "data": []
            }
        """.trimIndent()

        val validInvitationAcceptedResponse = """
            {
                "data": {
                    "id": "inv-123",
                    "tenant_id": "tenant-456",
                    "role": "member",
                    "status": "active",
                    "joined_at": "2025-01-15T12:00:00Z"
                }
            }
        """.trimIndent()

        val validAcceptInviteResponse = """
            {
                "data": {
                    "user": {
                        "id": "user-new-123",
                        "email": "user@example.com",
                        "display_name": "New User",
                        "status": "active",
                        "tenants": [{
                            "id": "tenant-456",
                            "name": "Test Organization",
                            "slug": "test-org",
                            "role": "member",
                            "joined_at": "2025-01-15T12:00:00Z"
                        }],
                        "current_tenant_id": "tenant-456",
                        "storage_quota": 1073741824,
                        "storage_used": 0
                    },
                    "access_token": "test-access-token",
                    "refresh_token": "test-refresh-token",
                    "expires_in": 3600,
                    "token_type": "Bearer"
                }
            }
        """.trimIndent()
    }

    // ==================== Form Inputs ====================

    object FormInputs {
        val validDisplayName = "John Doe"
        val displayNameWithSpaces = "  John Doe  "
        val emptyDisplayName = ""
        val blankDisplayName = "   "
        val displayNameTooLong = "A".repeat(101)
        val displayNameExactly100 = "A".repeat(100)
        val displayNameWithUnicode = "Jöhn Dœ"
        val displayNameWithEmoji = "John 👋 Doe"

        val validPassword = "securePassword123"
        val emptyPassword = ""
        val shortPassword = "short"
        val passwordExactly8 = "12345678"
        val passwordWithSpaces = "pass word"
        val passwordAllNumbers = "12345678"
        val passwordAllSymbols = "!@#$%^&*"

        val validConfirmPassword = validPassword
        val mismatchedConfirmPassword = "differentPassword"

        val validToken = "abc123-def456-ghi789"
        val emptyToken = ""
        val blankToken = "   "
        val tokenWithSpecialChars = "abc%20123+def"
        val longToken = "a".repeat(256)
    }

    // ==================== Deep Link URIs ====================

    object DeepLinks {
        // Custom scheme
        const val customSchemeInvite = "ssdiddrive://invite/abc123"
        const val customSchemeInviteWithDashes = "ssdiddrive://invite/abc-123-def"
        const val customSchemeInviteWithUnderscores = "ssdiddrive://invite/abc_123"
        const val customSchemeShare = "ssdiddrive://share/share123"
        const val customSchemeFile = "ssdiddrive://file/file123"
        const val customSchemeFolder = "ssdiddrive://folder/folder123"

        // HTTP scheme
        const val httpSchemeInvite = "https://app.ssdiddrive.example/invite/abc123"
        const val httpSchemeInviteWithQuery = "https://app.ssdiddrive.example/invite/abc123?ref=email"
        const val httpSchemeInviteWithPort = "https://app.ssdiddrive.example:8443/invite/abc123"
        const val httpSchemeShare = "https://app.ssdiddrive.example/share/share123"

        // Invalid
        const val unsupportedScheme = "ftp://ssdiddrive.example/invite/abc123"
        const val missingToken = "ssdiddrive://invite/"
        const val emptyPath = "ssdiddrive://invite"
        const val unknownHost = "ssdiddrive://unknown/abc123"
        const val malformedUri = "not a valid uri"
    }
}
