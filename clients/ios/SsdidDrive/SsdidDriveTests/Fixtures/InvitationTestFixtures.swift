import Foundation
@testable import SsdidDrive

/// Test fixtures for invitation-related tests
struct InvitationTestFixtures {

    // MARK: - Valid Invitations

    static let validInvitation = TokenInvitation(
        id: "inv_123456789",
        email: "newuser@example.com",
        role: .member,
        tenantName: "Test Company",
        inviterName: "Admin User",
        message: "Welcome to the team!",
        expiresAt: Date().addingTimeInterval(86400 * 7), // 7 days from now
        valid: true,
        errorReason: nil
    )

    static let validInvitationNoMessage = TokenInvitation(
        id: "inv_987654321",
        email: "another@example.com",
        role: .admin,
        tenantName: "Another Company",
        inviterName: "Owner",
        message: nil,
        expiresAt: Date().addingTimeInterval(86400 * 7),
        valid: true,
        errorReason: nil
    )

    static let validInvitationViewer = TokenInvitation(
        id: "inv_viewer123",
        email: "viewer@example.com",
        role: .viewer,
        tenantName: "View Only Corp",
        inviterName: "Manager",
        message: "You have view-only access",
        expiresAt: Date().addingTimeInterval(86400 * 7),
        valid: true,
        errorReason: nil
    )

    // MARK: - Invalid Invitations

    static let expiredInvitation = TokenInvitation(
        id: "inv_expired123",
        email: "expired@example.com",
        role: .member,
        tenantName: "Test Company",
        inviterName: "Admin User",
        message: nil,
        expiresAt: Date().addingTimeInterval(-86400), // 1 day ago
        valid: false,
        errorReason: .expired
    )

    static let revokedInvitation = TokenInvitation(
        id: "inv_revoked456",
        email: "revoked@example.com",
        role: .member,
        tenantName: "Test Company",
        inviterName: "Admin User",
        message: nil,
        expiresAt: Date().addingTimeInterval(86400 * 7),
        valid: false,
        errorReason: .revoked
    )

    static let alreadyUsedInvitation = TokenInvitation(
        id: "inv_used789",
        email: "used@example.com",
        role: .member,
        tenantName: "Test Company",
        inviterName: "Admin User",
        message: nil,
        expiresAt: Date().addingTimeInterval(86400 * 7),
        valid: false,
        errorReason: .alreadyUsed
    )

    static let notFoundInvitation = TokenInvitation(
        id: "inv_notfound000",
        email: "notfound@example.com",
        role: .member,
        tenantName: "",
        inviterName: nil,
        message: nil,
        expiresAt: Date(),
        valid: false,
        errorReason: .notFound
    )

    // MARK: - Invite User (Result of accepting)

    static let acceptedUser = InviteUser(
        id: "usr_newuser123",
        email: "newuser@example.com",
        displayName: "John Doe",
        tenantId: "ten_456",
        createdAt: Date(),
        updatedAt: Date()
    )

    static let acceptedAdminUser = InviteUser(
        id: "usr_admin456",
        email: "newadmin@example.com",
        displayName: "Jane Admin",
        tenantId: "ten_789",
        createdAt: Date(),
        updatedAt: Date()
    )

    // MARK: - Form Input

    struct FormInput {
        static let validDisplayName = "John Doe"
        static let validPassword = "SecurePass123!"
        static let validConfirmPassword = "SecurePass123!"

        static let shortPassword = "short"
        static let longPassword = String(repeating: "a", count: 100)

        static let emptyDisplayName = ""
        static let longDisplayName = String(repeating: "a", count: 150)
        static let whitespaceOnlyDisplayName = "   "

        static let unicodeDisplayName = "Jean-Pierre Dubuisson"
        static let emojiDisplayName = "John Doe"
        static let specialCharsPassword = "P@ssw0rd!#$%^&*()"
        static let unicodePassword = "secret123"
    }

    // MARK: - Tokens

    static let validToken = "abc123xyz789"
    static let invalidToken = "invalid-token-here"
    static let expiredToken = "expired-token-456"
    static let revokedToken = "revoked-token-789"

    // MARK: - API JSON Responses

    struct JSON {
        static let validInvitationResponse = """
        {
            "data": {
                "id": "inv_123456789",
                "email": "newuser@example.com",
                "role": "member",
                "tenant_name": "Test Company",
                "inviter_name": "Admin User",
                "message": "Welcome to the team!",
                "expires_at": "\(iso8601String(for: Date().addingTimeInterval(86400 * 7)))",
                "valid": true,
                "error_reason": null
            }
        }
        """

        static let validInvitationNoMessageResponse = """
        {
            "data": {
                "id": "inv_987654321",
                "email": "another@example.com",
                "role": "admin",
                "tenant_name": "Another Company",
                "inviter_name": "Owner",
                "message": null,
                "expires_at": "\(iso8601String(for: Date().addingTimeInterval(86400 * 7)))",
                "valid": true,
                "error_reason": null
            }
        }
        """

        static let expiredInvitationResponse = """
        {
            "data": {
                "id": "inv_expired123",
                "email": "expired@example.com",
                "role": "member",
                "tenant_name": "Test Company",
                "inviter_name": "Admin User",
                "message": null,
                "expires_at": "\(iso8601String(for: Date().addingTimeInterval(-86400)))",
                "valid": false,
                "error_reason": "expired"
            }
        }
        """

        static let revokedInvitationResponse = """
        {
            "data": {
                "id": "inv_revoked456",
                "email": "revoked@example.com",
                "role": "member",
                "tenant_name": "Test Company",
                "inviter_name": "Admin User",
                "message": null,
                "expires_at": "\(iso8601String(for: Date().addingTimeInterval(86400 * 7)))",
                "valid": false,
                "error_reason": "revoked"
            }
        }
        """

        static let alreadyUsedInvitationResponse = """
        {
            "data": {
                "id": "inv_used789",
                "email": "used@example.com",
                "role": "member",
                "tenant_name": "Test Company",
                "inviter_name": "Admin User",
                "message": null,
                "expires_at": "\(iso8601String(for: Date().addingTimeInterval(86400 * 7)))",
                "valid": false,
                "error_reason": "already_used"
            }
        }
        """

        static let notFoundInvitationResponse = """
        {
            "data": {
                "id": "",
                "email": "",
                "role": "member",
                "tenant_name": "",
                "inviter_name": null,
                "message": null,
                "expires_at": "\(iso8601String(for: Date()))",
                "valid": false,
                "error_reason": "not_found"
            }
        }
        """

        static let acceptSuccessResponse = """
        {
            "data": {
                "user": {
                    "id": "usr_newuser123",
                    "email": "newuser@example.com",
                    "display_name": "John Doe",
                    "tenant_id": "ten_456",
                    "created_at": "\(iso8601String(for: Date()))",
                    "updated_at": "\(iso8601String(for: Date()))"
                },
                "access_token": "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiIxMjM0NTY3ODkwIiwibmFtZSI6IlRlc3QgVXNlciIsImlhdCI6MTUxNjIzOTAyMn0.test",
                "refresh_token": "refresh_token_abc123",
                "token_type": "Bearer",
                "expires_in": 3600
            }
        }
        """

        // MARK: - Error Responses

        static let error404NotFound = """
        {
            "error": {
                "code": "not_found",
                "message": "Invitation not found"
            }
        }
        """

        static let error409Conflict = """
        {
            "error": {
                "code": "conflict",
                "message": "This invitation has already been used."
            }
        }
        """

        static let error410Gone = """
        {
            "error": {
                "code": "gone",
                "message": "This invitation has expired."
            }
        }
        """

        static let error422Validation = """
        {
            "error": {
                "code": "validation_error",
                "message": "Validation failed",
                "details": {
                    "password": ["must be at least 8 characters"]
                }
            }
        }
        """

        static let error500Server = """
        {
            "error": {
                "code": "internal_error",
                "message": "An unexpected error occurred"
            }
        }
        """

        // MARK: - Helper

        private static func iso8601String(for date: Date) -> String {
            let formatter = ISO8601DateFormatter()
            return formatter.string(from: date)
        }
    }

    // MARK: - Helper Methods

    /// Creates a TokenInvitation with custom parameters
    static func createInvitation(
        id: String = "inv_custom",
        email: String = "custom@example.com",
        role: UserRole = .member,
        tenantName: String = "Custom Company",
        inviterName: String? = "Custom Inviter",
        message: String? = nil,
        expiresAt: Date = Date().addingTimeInterval(86400 * 7),
        valid: Bool = true,
        errorReason: TokenInvitationError? = nil
    ) -> TokenInvitation {
        TokenInvitation(
            id: id,
            email: email,
            role: role,
            tenantName: tenantName,
            inviterName: inviterName,
            message: message,
            expiresAt: expiresAt,
            valid: valid,
            errorReason: errorReason
        )
    }

    /// Creates an InviteUser with custom parameters
    static func createInviteUser(
        id: String = "usr_custom",
        email: String = "custom@example.com",
        displayName: String? = "Custom User",
        tenantId: String? = "ten_custom",
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) -> InviteUser {
        InviteUser(
            id: id,
            email: email,
            displayName: displayName,
            tenantId: tenantId,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }
}
