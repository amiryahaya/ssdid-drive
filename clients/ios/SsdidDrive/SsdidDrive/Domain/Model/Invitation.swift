import Foundation

// MARK: - Token Invitation (Public - for new users)

/// Public invitation info retrieved by token.
/// Used for invitation-only registration flow.
struct TokenInvitation: Codable, Equatable {
    let id: String
    let email: String
    let role: UserRole
    let tenantName: String
    let inviterName: String?
    let message: String?
    let expiresAt: Date
    let valid: Bool
    let errorReason: TokenInvitationError?

    enum CodingKeys: String, CodingKey {
        case id
        case email
        case role
        case tenantName = "tenant_name"
        case inviterName = "inviter_name"
        case message
        case expiresAt = "expires_at"
        case valid
        case errorReason = "error_reason"
    }
}

/// Possible error reasons for invalid invitations.
enum TokenInvitationError: String, Codable, Equatable {
    case expired
    case revoked
    case alreadyUsed = "already_used"
    case notFound = "not_found"

    var displayMessage: String {
        switch self {
        case .expired:
            return "This invitation has expired"
        case .revoked:
            return "This invitation has been revoked"
        case .alreadyUsed:
            return "This invitation has already been used"
        case .notFound:
            return "Invitation not found"
        }
    }
}

/// User role in a tenant
enum UserRole: String, Codable, Equatable {
    case admin
    case member
    case viewer

    var displayName: String {
        switch self {
        case .admin:
            return "Admin"
        case .member:
            return "Member"
        case .viewer:
            return "Viewer"
        }
    }
}

// MARK: - API Response Types

/// Response from GET /invite/{token}
struct InviteInfoResponse: Codable {
    let data: TokenInvitation
}

/// Request to accept an invitation and register
struct AcceptInviteRequest: Codable {
    let displayName: String
    let password: String
    let publicKeys: AcceptInvitePublicKeys
    let encryptedMasterKey: String
    let encryptedPrivateKeys: String
    let keyDerivationSalt: String

    enum CodingKeys: String, CodingKey {
        case displayName = "display_name"
        case password
        case publicKeys = "public_keys"
        case encryptedMasterKey = "encrypted_master_key"
        case encryptedPrivateKeys = "encrypted_private_keys"
        case keyDerivationSalt = "key_derivation_salt"
    }
}

/// Public keys format for API registration
struct AcceptInvitePublicKeys: Codable {
    let kem: String          // Base64 KAZ-KEM public key
    let sign: String         // Base64 KAZ-SIGN public key
    let mlKem: String?       // Base64 ML-KEM public key
    let mlDsa: String?       // Base64 ML-DSA public key

    enum CodingKeys: String, CodingKey {
        case kem
        case sign
        case mlKem = "ml_kem"
        case mlDsa = "ml_dsa"
    }
}

/// Response from POST /invite/{token}/accept
struct AcceptInviteResponse: Codable {
    let data: AcceptInviteData
}

struct AcceptInviteData: Codable {
    let user: InviteUser
    let accessToken: String
    let refreshToken: String
    let expiresIn: Int?
    let tokenType: String?

    enum CodingKeys: String, CodingKey {
        case user
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case expiresIn = "expires_in"
        case tokenType = "token_type"
    }
}

/// User info returned from invitation acceptance
struct InviteUser: Codable, Identifiable, Equatable {
    let id: String
    let email: String
    let displayName: String?
    let tenantId: String?
    let createdAt: Date
    let updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case email
        case displayName = "display_name"
        case tenantId = "tenant_id"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

// MARK: - Authenticated Invitation (for existing users joining tenants)

/// Invitation for existing users to join additional tenants
struct TenantInvitation: Codable, Identifiable, Equatable {
    let id: String
    let tenantId: String
    let tenantName: String
    let role: UserRole
    let invitedBy: InvitedBy?
    let expiresAt: Date
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case tenantId = "tenant_id"
        case tenantName = "tenant_name"
        case role
        case invitedBy = "invited_by"
        case expiresAt = "expires_at"
        case createdAt = "created_at"
    }
}

struct InvitedBy: Codable, Equatable {
    let id: String
    let email: String?
    let displayName: String?

    enum CodingKeys: String, CodingKey {
        case id
        case email
        case displayName = "display_name"
    }

    var name: String {
        displayName ?? email ?? "Unknown"
    }
}
