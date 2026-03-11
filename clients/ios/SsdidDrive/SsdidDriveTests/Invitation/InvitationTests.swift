import XCTest
@testable import SsdidDrive

/// Unit tests for Invitation model encoding/decoding and validation
final class InvitationTests: XCTestCase {

    // MARK: - Properties

    var decoder: JSONDecoder!
    var encoder: JSONEncoder!

    // MARK: - Setup

    override func setUp() {
        super.setUp()
        decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
    }

    override func tearDown() {
        decoder = nil
        encoder = nil
        super.tearDown()
    }

    // MARK: - TokenInvitation Decoding Tests

    func testTokenInvitation_decodesValidInvitation() throws {
        // Given
        let json = InvitationTestFixtures.JSON.validInvitationResponse

        // When
        let response = try decoder.decode(InviteInfoResponse.self, from: json.data(using: .utf8)!)

        // Then
        XCTAssertEqual(response.data.email, "newuser@example.com")
        XCTAssertEqual(response.data.role, .member)
        XCTAssertEqual(response.data.tenantName, "Test Company")
        XCTAssertEqual(response.data.inviterName, "Admin User")
        XCTAssertEqual(response.data.message, "Welcome to the team!")
        XCTAssertTrue(response.data.valid)
        XCTAssertNil(response.data.errorReason)
    }

    func testTokenInvitation_decodesInvitationWithNullMessage() throws {
        // Given
        let json = InvitationTestFixtures.JSON.validInvitationNoMessageResponse

        // When
        let response = try decoder.decode(InviteInfoResponse.self, from: json.data(using: .utf8)!)

        // Then
        XCTAssertEqual(response.data.email, "another@example.com")
        XCTAssertEqual(response.data.role, .admin)
        XCTAssertNil(response.data.message)
        XCTAssertTrue(response.data.valid)
    }

    func testTokenInvitation_decodesExpiredInvitation() throws {
        // Given
        let json = InvitationTestFixtures.JSON.expiredInvitationResponse

        // When
        let response = try decoder.decode(InviteInfoResponse.self, from: json.data(using: .utf8)!)

        // Then
        XCTAssertEqual(response.data.email, "expired@example.com")
        XCTAssertFalse(response.data.valid)
        XCTAssertEqual(response.data.errorReason, .expired)
    }

    func testTokenInvitation_decodesRevokedInvitation() throws {
        // Given
        let json = InvitationTestFixtures.JSON.revokedInvitationResponse

        // When
        let response = try decoder.decode(InviteInfoResponse.self, from: json.data(using: .utf8)!)

        // Then
        XCTAssertFalse(response.data.valid)
        XCTAssertEqual(response.data.errorReason, .revoked)
    }

    func testTokenInvitation_decodesAlreadyUsedInvitation() throws {
        // Given
        let json = InvitationTestFixtures.JSON.alreadyUsedInvitationResponse

        // When
        let response = try decoder.decode(InviteInfoResponse.self, from: json.data(using: .utf8)!)

        // Then
        XCTAssertFalse(response.data.valid)
        XCTAssertEqual(response.data.errorReason, .alreadyUsed)
    }

    func testTokenInvitation_decodesNotFoundInvitation() throws {
        // Given
        let json = InvitationTestFixtures.JSON.notFoundInvitationResponse

        // When
        let response = try decoder.decode(InviteInfoResponse.self, from: json.data(using: .utf8)!)

        // Then
        XCTAssertFalse(response.data.valid)
        XCTAssertEqual(response.data.errorReason, .notFound)
    }

    // MARK: - TokenInvitationError Tests

    func testTokenInvitationError_displayMessage_expired() {
        XCTAssertEqual(TokenInvitationError.expired.displayMessage, "This invitation has expired")
    }

    func testTokenInvitationError_displayMessage_revoked() {
        XCTAssertEqual(TokenInvitationError.revoked.displayMessage, "This invitation has been revoked")
    }

    func testTokenInvitationError_displayMessage_alreadyUsed() {
        XCTAssertEqual(TokenInvitationError.alreadyUsed.displayMessage, "This invitation has already been used")
    }

    func testTokenInvitationError_displayMessage_notFound() {
        XCTAssertEqual(TokenInvitationError.notFound.displayMessage, "Invitation not found")
    }

    func testTokenInvitationError_rawValue_expired() {
        XCTAssertEqual(TokenInvitationError.expired.rawValue, "expired")
    }

    func testTokenInvitationError_rawValue_revoked() {
        XCTAssertEqual(TokenInvitationError.revoked.rawValue, "revoked")
    }

    func testTokenInvitationError_rawValue_alreadyUsed() {
        XCTAssertEqual(TokenInvitationError.alreadyUsed.rawValue, "already_used")
    }

    func testTokenInvitationError_rawValue_notFound() {
        XCTAssertEqual(TokenInvitationError.notFound.rawValue, "not_found")
    }

    // MARK: - UserRole Tests

    func testUserRole_displayName_admin() {
        XCTAssertEqual(UserRole.admin.displayName, "Admin")
    }

    func testUserRole_displayName_member() {
        XCTAssertEqual(UserRole.member.displayName, "Member")
    }

    func testUserRole_displayName_viewer() {
        XCTAssertEqual(UserRole.viewer.displayName, "Viewer")
    }

    func testUserRole_rawValue_admin() {
        XCTAssertEqual(UserRole.admin.rawValue, "admin")
    }

    func testUserRole_rawValue_member() {
        XCTAssertEqual(UserRole.member.rawValue, "member")
    }

    func testUserRole_rawValue_viewer() {
        XCTAssertEqual(UserRole.viewer.rawValue, "viewer")
    }

    // MARK: - AcceptInviteResponse Tests

    func testAcceptInviteResponse_decodesSuccessfully() throws {
        // Given
        let json = InvitationTestFixtures.JSON.acceptSuccessResponse

        // When
        let response = try decoder.decode(AcceptInviteResponse.self, from: json.data(using: .utf8)!)

        // Then
        XCTAssertEqual(response.data.user.id, "usr_newuser123")
        XCTAssertEqual(response.data.user.email, "newuser@example.com")
        XCTAssertEqual(response.data.user.displayName, "John Doe")
        XCTAssertEqual(response.data.user.tenantId, "ten_456")
        XCTAssertFalse(response.data.accessToken.isEmpty)
        XCTAssertFalse(response.data.refreshToken.isEmpty)
        XCTAssertEqual(response.data.tokenType, "Bearer")
        XCTAssertEqual(response.data.expiresIn, 3600)
    }

    // MARK: - AcceptInviteRequest Encoding Tests

    func testAcceptInviteRequest_encodesCorrectly() throws {
        // Given
        let publicKeys = AcceptInvitePublicKeys(
            kem: "base64kemkey==",
            sign: "base64signkey==",
            mlKem: "base64mlkemkey==",
            mlDsa: "base64mldsaKey=="
        )

        let request = AcceptInviteRequest(
            displayName: "John Doe",
            password: "SecurePass123!",
            publicKeys: publicKeys,
            encryptedMasterKey: "encryptedMK==",
            encryptedPrivateKeys: "encryptedPKs==",
            keyDerivationSalt: "salt123=="
        )

        // When
        let encoded = try encoder.encode(request)
        let jsonObject = try JSONSerialization.jsonObject(with: encoded) as! [String: Any]

        // Then
        XCTAssertEqual(jsonObject["display_name"] as? String, "John Doe")
        XCTAssertEqual(jsonObject["password"] as? String, "SecurePass123!")
        XCTAssertEqual(jsonObject["encrypted_master_key"] as? String, "encryptedMK==")
        XCTAssertEqual(jsonObject["encrypted_private_keys"] as? String, "encryptedPKs==")
        XCTAssertEqual(jsonObject["key_derivation_salt"] as? String, "salt123==")

        let publicKeysDict = jsonObject["public_keys"] as! [String: Any]
        XCTAssertEqual(publicKeysDict["kem"] as? String, "base64kemkey==")
        XCTAssertEqual(publicKeysDict["sign"] as? String, "base64signkey==")
        XCTAssertEqual(publicKeysDict["ml_kem"] as? String, "base64mlkemkey==")
        XCTAssertEqual(publicKeysDict["ml_dsa"] as? String, "base64mldsaKey==")
    }

    func testAcceptInvitePublicKeys_encodesWithNilOptionals() throws {
        // Given
        let publicKeys = AcceptInvitePublicKeys(
            kem: "base64kemkey==",
            sign: "base64signkey==",
            mlKem: nil,
            mlDsa: nil
        )

        // When
        let encoded = try encoder.encode(publicKeys)
        let jsonObject = try JSONSerialization.jsonObject(with: encoded) as! [String: Any]

        // Then
        XCTAssertEqual(jsonObject["kem"] as? String, "base64kemkey==")
        XCTAssertEqual(jsonObject["sign"] as? String, "base64signkey==")
        // Nil optionals should not appear in JSON or be null
        XCTAssertTrue(jsonObject["ml_kem"] == nil || jsonObject["ml_kem"] is NSNull)
        XCTAssertTrue(jsonObject["ml_dsa"] == nil || jsonObject["ml_dsa"] is NSNull)
    }

    // MARK: - InviteUser Tests

    func testInviteUser_decodesCorrectly() throws {
        // Given
        let json = """
        {
            "id": "usr_test123",
            "email": "test@example.com",
            "display_name": "Test User",
            "tenant_id": "ten_test",
            "created_at": "2024-01-15T10:30:00Z",
            "updated_at": "2024-01-15T11:00:00Z"
        }
        """.data(using: .utf8)!

        // When
        let user = try decoder.decode(InviteUser.self, from: json)

        // Then
        XCTAssertEqual(user.id, "usr_test123")
        XCTAssertEqual(user.email, "test@example.com")
        XCTAssertEqual(user.displayName, "Test User")
        XCTAssertEqual(user.tenantId, "ten_test")
    }

    func testInviteUser_decodesWithNullDisplayName() throws {
        // Given
        let json = """
        {
            "id": "usr_test456",
            "email": "noname@example.com",
            "display_name": null,
            "tenant_id": "ten_test",
            "created_at": "2024-01-15T10:30:00Z",
            "updated_at": "2024-01-15T11:00:00Z"
        }
        """.data(using: .utf8)!

        // When
        let user = try decoder.decode(InviteUser.self, from: json)

        // Then
        XCTAssertEqual(user.id, "usr_test456")
        XCTAssertNil(user.displayName)
    }

    // MARK: - TenantInvitation Tests

    func testTenantInvitation_decodesCorrectly() throws {
        // Given
        let json = """
        {
            "id": "tinv_123",
            "tenant_id": "ten_abc",
            "tenant_name": "Test Tenant",
            "role": "member",
            "invited_by": {
                "id": "usr_inviter",
                "email": "inviter@example.com",
                "display_name": "Inviter Name"
            },
            "expires_at": "2024-02-15T00:00:00Z",
            "created_at": "2024-01-15T00:00:00Z"
        }
        """.data(using: .utf8)!

        // When
        let invitation = try decoder.decode(TenantInvitation.self, from: json)

        // Then
        XCTAssertEqual(invitation.id, "tinv_123")
        XCTAssertEqual(invitation.tenantId, "ten_abc")
        XCTAssertEqual(invitation.tenantName, "Test Tenant")
        XCTAssertEqual(invitation.role, .member)
        XCTAssertNotNil(invitation.invitedBy)
        XCTAssertEqual(invitation.invitedBy?.id, "usr_inviter")
        XCTAssertEqual(invitation.invitedBy?.name, "Inviter Name")
    }

    func testTenantInvitation_decodesWithNullInvitedBy() throws {
        // Given
        let json = """
        {
            "id": "tinv_456",
            "tenant_id": "ten_def",
            "tenant_name": "Another Tenant",
            "role": "admin",
            "invited_by": null,
            "expires_at": "2024-02-15T00:00:00Z",
            "created_at": "2024-01-15T00:00:00Z"
        }
        """.data(using: .utf8)!

        // When
        let invitation = try decoder.decode(TenantInvitation.self, from: json)

        // Then
        XCTAssertEqual(invitation.id, "tinv_456")
        XCTAssertNil(invitation.invitedBy)
    }

    // MARK: - InvitedBy Tests

    func testInvitedBy_name_usesDisplayName() throws {
        // Given
        let json = """
        {
            "id": "usr_123",
            "email": "test@example.com",
            "display_name": "John Doe"
        }
        """.data(using: .utf8)!

        // When
        let invitedBy = try decoder.decode(InvitedBy.self, from: json)

        // Then
        XCTAssertEqual(invitedBy.name, "John Doe")
    }

    func testInvitedBy_name_fallsBackToEmail() throws {
        // Given
        let json = """
        {
            "id": "usr_123",
            "email": "test@example.com",
            "display_name": null
        }
        """.data(using: .utf8)!

        // When
        let invitedBy = try decoder.decode(InvitedBy.self, from: json)

        // Then
        XCTAssertEqual(invitedBy.name, "test@example.com")
    }

    func testInvitedBy_name_fallsBackToUnknown() throws {
        // Given
        let json = """
        {
            "id": "usr_123",
            "email": null,
            "display_name": null
        }
        """.data(using: .utf8)!

        // When
        let invitedBy = try decoder.decode(InvitedBy.self, from: json)

        // Then
        XCTAssertEqual(invitedBy.name, "Unknown")
    }

    // MARK: - Equatable Tests

    func testTokenInvitation_equatable() {
        let invitation1 = InvitationTestFixtures.validInvitation
        let invitation2 = InvitationTestFixtures.validInvitation

        XCTAssertEqual(invitation1, invitation2)
    }

    func testTokenInvitation_notEquatable_differentId() {
        let invitation1 = InvitationTestFixtures.createInvitation(id: "inv_1")
        let invitation2 = InvitationTestFixtures.createInvitation(id: "inv_2")

        XCTAssertNotEqual(invitation1, invitation2)
    }

    func testUserRole_equatable() {
        XCTAssertEqual(UserRole.admin, UserRole.admin)
        XCTAssertEqual(UserRole.member, UserRole.member)
        XCTAssertEqual(UserRole.viewer, UserRole.viewer)
        XCTAssertNotEqual(UserRole.admin, UserRole.member)
    }

    func testTokenInvitationError_equatable() {
        XCTAssertEqual(TokenInvitationError.expired, TokenInvitationError.expired)
        XCTAssertNotEqual(TokenInvitationError.expired, TokenInvitationError.revoked)
    }

    // MARK: - Edge Cases

    func testTokenInvitation_decodesWithMissingOptionalFields() throws {
        // Given - JSON with minimal required fields
        let json = """
        {
            "id": "inv_minimal",
            "email": "minimal@example.com",
            "role": "member",
            "tenant_name": "Minimal Co",
            "inviter_name": null,
            "message": null,
            "expires_at": "2024-02-15T00:00:00Z",
            "valid": true,
            "error_reason": null
        }
        """.data(using: .utf8)!

        // When
        let invitation = try decoder.decode(TokenInvitation.self, from: json)

        // Then
        XCTAssertEqual(invitation.id, "inv_minimal")
        XCTAssertNil(invitation.inviterName)
        XCTAssertNil(invitation.message)
        XCTAssertTrue(invitation.valid)
    }

    func testAcceptInviteData_decodesWithNilOptionals() throws {
        // Given
        let json = """
        {
            "user": {
                "id": "usr_123",
                "email": "test@example.com",
                "display_name": null,
                "tenant_id": null,
                "created_at": "2024-01-15T10:30:00Z",
                "updated_at": "2024-01-15T10:30:00Z"
            },
            "access_token": "access123",
            "refresh_token": "refresh123",
            "expires_in": null,
            "token_type": null
        }
        """.data(using: .utf8)!

        // When
        let data = try decoder.decode(AcceptInviteData.self, from: json)

        // Then
        XCTAssertEqual(data.accessToken, "access123")
        XCTAssertEqual(data.refreshToken, "refresh123")
        XCTAssertNil(data.expiresIn)
        XCTAssertNil(data.tokenType)
        XCTAssertNil(data.user.displayName)
        XCTAssertNil(data.user.tenantId)
    }

    // MARK: - UserRole Owner Tests

    func testUserRole_displayName_owner() {
        XCTAssertEqual(UserRole.owner.displayName, "Owner")
    }

    func testUserRole_rawValue_owner() {
        XCTAssertEqual(UserRole.owner.rawValue, "owner")
    }

    // MARK: - TenantMember Tests

    func testTenantMember_initials_twoWordName() throws {
        let json = """
        {
            "id": "usr_123",
            "email": "john@example.com",
            "display_name": "John Doe",
            "role": "member",
            "joined_at": "2024-01-15T10:30:00Z"
        }
        """.data(using: .utf8)!

        let member = try decoder.decode(TenantMember.self, from: json)
        XCTAssertEqual(member.initials, "JD")
    }

    func testTenantMember_initials_singleWordName() throws {
        let json = """
        {
            "id": "usr_123",
            "email": "prince@example.com",
            "display_name": "Prince",
            "role": "member",
            "joined_at": "2024-01-15T10:30:00Z"
        }
        """.data(using: .utf8)!

        let member = try decoder.decode(TenantMember.self, from: json)
        XCTAssertEqual(member.initials, "PR")
    }

    func testTenantMember_initials_emailFallback() throws {
        let json = """
        {
            "id": "usr_123",
            "email": "hello@example.com",
            "display_name": null,
            "role": "member",
            "joined_at": "2024-01-15T10:30:00Z"
        }
        """.data(using: .utf8)!

        let member = try decoder.decode(TenantMember.self, from: json)
        XCTAssertEqual(member.initials, "HE")
    }

    func testTenantMember_name_usesDisplayName() throws {
        let json = """
        {
            "id": "usr_123",
            "email": "john@example.com",
            "display_name": "John Doe",
            "role": "member",
            "joined_at": "2024-01-15T10:30:00Z"
        }
        """.data(using: .utf8)!

        let member = try decoder.decode(TenantMember.self, from: json)
        XCTAssertEqual(member.name, "John Doe")
    }

    func testTenantMember_name_fallsBackToEmailPrefix() throws {
        let json = """
        {
            "id": "usr_123",
            "email": "johndoe@example.com",
            "display_name": null,
            "role": "member",
            "joined_at": "2024-01-15T10:30:00Z"
        }
        """.data(using: .utf8)!

        let member = try decoder.decode(TenantMember.self, from: json)
        XCTAssertEqual(member.name, "Johndoe")
    }

    // MARK: - CodeInvitation Tests

    func testCodeInvitation_isExpired_futureDate_returnsFalse() throws {
        let expiresAt = ISO8601DateFormatter().string(from: Date().addingTimeInterval(86400))
        let json = """
        {
            "id": "inv_123",
            "tenant_name": "Test Corp",
            "role": "member",
            "short_code": "ABCD1234",
            "expires_at": "\(expiresAt)"
        }
        """.data(using: .utf8)!

        let invitation = try decoder.decode(CodeInvitation.self, from: json)
        XCTAssertFalse(invitation.isExpired)
    }

    func testCodeInvitation_isExpired_pastDate_returnsTrue() throws {
        let expiresAt = ISO8601DateFormatter().string(from: Date().addingTimeInterval(-86400))
        let json = """
        {
            "id": "inv_expired",
            "tenant_name": "Test Corp",
            "role": "member",
            "short_code": "EXPR1234",
            "expires_at": "\(expiresAt)"
        }
        """.data(using: .utf8)!

        let invitation = try decoder.decode(CodeInvitation.self, from: json)
        XCTAssertTrue(invitation.isExpired)
    }

    // MARK: - SentInvitation Tests

    func testSentInvitation_displayEmail_withEmail() throws {
        let createdAt = ISO8601DateFormatter().string(from: Date())
        let expiresAt = ISO8601DateFormatter().string(from: Date().addingTimeInterval(86400))
        let json = """
        {
            "id": "sinv_001",
            "email": "user@example.com",
            "role": "member",
            "short_code": "CODE1234",
            "status": "pending",
            "message": null,
            "tenant_id": "ten_abc",
            "tenant_name": "Test Corp",
            "created_at": "\(createdAt)",
            "expires_at": "\(expiresAt)"
        }
        """.data(using: .utf8)!

        let invitation = try decoder.decode(SentInvitation.self, from: json)
        XCTAssertEqual(invitation.displayEmail, "user@example.com")
    }

    func testSentInvitation_displayEmail_withoutEmail() throws {
        let createdAt = ISO8601DateFormatter().string(from: Date())
        let expiresAt = ISO8601DateFormatter().string(from: Date().addingTimeInterval(86400))
        let json = """
        {
            "id": "sinv_002",
            "email": null,
            "role": "member",
            "short_code": "OPEN1234",
            "status": "pending",
            "message": null,
            "tenant_id": "ten_abc",
            "tenant_name": "Test Corp",
            "created_at": "\(createdAt)",
            "expires_at": "\(expiresAt)"
        }
        """.data(using: .utf8)!

        let invitation = try decoder.decode(SentInvitation.self, from: json)
        XCTAssertEqual(invitation.displayEmail, "Open invite")
    }
}
