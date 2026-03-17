import Foundation

// MARK: - Token Invitation (Public - for new users)

/// Public invitation info retrieved by token.
/// Used for invitation-only registration flow.
struct TokenInvitation: Codable, Equatable {
    let email: String
    let role: UserRole
    let tenantName: String
    let inviterName: String?
    let message: String?
    let status: String
    let shortCode: String
    let expiresAt: Date
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case email, role, message, status
        case tenantName = "tenant_name"
        case inviterName = "inviter_name"
        case shortCode = "short_code"
        case expiresAt = "expires_at"
        case createdAt = "created_at"
    }

    var valid: Bool { status.lowercased() == "pending" }

    var errorReason: TokenInvitationError? {
        switch status.lowercased() {
        case "pending": return nil
        case "expired": return .expired
        case "revoked": return .revoked
        case "accepted": return .alreadyUsed
        default: return .notFound
        }
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
    case owner
    case admin
    case member
    case viewer

    var displayName: String {
        switch self {
        case .owner:
            return "Owner"
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

/// Response from GET /api/invitations/token/{token}
/// The backend returns the invitation fields directly without a `data` wrapper.
typealias InviteInfoResponse = TokenInvitation

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

// MARK: - Short Code Invitation (for joining tenants by code)

/// Invitation info retrieved by short code.
/// Used for both authenticated and unauthenticated users.
struct CodeInvitation: Codable, Equatable {
    let id: String?
    let tenantName: String
    let role: UserRole
    let shortCode: String
    let expiresAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case tenantName = "tenant_name"
        case role
        case shortCode = "short_code"
        case expiresAt = "expires_at"
    }

    /// Whether the invitation has expired
    var isExpired: Bool {
        expiresAt < Date()
    }
}

/// Response from GET /api/invitations/code/{code}
struct CodeInvitationResponse: Codable {
    let data: CodeInvitation
}

/// Response from POST /api/invitations/{id}/accept (for authenticated users)
struct AcceptCodeInvitationResponse: Codable {
    let data: AcceptCodeInvitationData
}

struct AcceptCodeInvitationData: Codable {
    let tenantId: String
    let role: String

    enum CodingKeys: String, CodingKey {
        case tenantId = "tenant_id"
        case role
    }
}

// MARK: - Create Invitation (Admin/Owner)

/// Request to create a new tenant invitation
struct CreateInvitationRequest: Codable {
    let email: String?
    let role: String?
    let message: String?
}

/// Response from POST /api/invitations
struct CreateInvitationResponse: Codable {
    let data: SentInvitation
}

/// An invitation sent by the current user (admin/owner)
struct SentInvitation: Codable, Identifiable, Equatable, Hashable {
    let id: String
    let email: String?
    let role: UserRole
    let shortCode: String
    let status: InvitationStatus
    let message: String?
    let tenantId: String
    let tenantName: String?
    let emailSent: Bool?
    let emailError: String?
    let createdAt: Date
    let expiresAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case email
        case role
        case shortCode = "short_code"
        case status
        case message
        case tenantId = "tenant_id"
        case tenantName = "tenant_name"
        case emailSent = "email_sent"
        case emailError = "email_error"
        case createdAt = "created_at"
        case expiresAt = "expires_at"
    }

    var isExpired: Bool {
        expiresAt < Date()
    }

    var displayEmail: String {
        email ?? "Open invite"
    }
}

/// Invitation status
enum InvitationStatus: String, Codable, Equatable, Hashable {
    case pending
    case accepted
    case declined
    case revoked
    case expired

    var displayName: String {
        switch self {
        case .pending: return "Pending"
        case .accepted: return "Accepted"
        case .declined: return "Declined"
        case .revoked: return "Revoked"
        case .expired: return "Expired"
        }
    }
}

/// Response from GET /api/invitations (received)
struct ReceivedInvitationsResponse: Codable {
    let data: [TenantInvitation]
}

/// Response from GET /api/invitations/sent
struct SentInvitationsResponse: Codable {
    let data: [SentInvitation]
}

// MARK: - Tenant Member

/// A member of a tenant (organization)
struct TenantMember: Codable, Identifiable, Equatable, Hashable {
    let id: String
    let email: String
    let displayName: String?
    let role: UserRole
    let joinedAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case email
        case displayName = "display_name"
        case role
        case joinedAt = "joined_at"
    }

    var name: String {
        displayName ?? email.components(separatedBy: "@").first?.capitalized ?? email
    }

    var initials: String {
        if let displayName = displayName, !displayName.isEmpty {
            let words = displayName.split(separator: " ")
            if words.count >= 2 {
                return String(words[0].prefix(1) + words[1].prefix(1)).uppercased()
            }
            return String(displayName.prefix(2)).uppercased()
        }
        return String(email.prefix(2)).uppercased()
    }
}

/// Response from GET /api/tenants/{id}/members
struct TenantMembersResponse: Codable {
    let data: [TenantMember]
}

/// Request to update a member's role
struct UpdateMemberRoleRequest: Codable {
    let role: String
}
