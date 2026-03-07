import Foundation

/// Represents a tenant (organization) the user belongs to
struct Tenant: Codable, Identifiable, Equatable, Hashable {
    let id: String
    let name: String
    let slug: String
    let role: UserRole
    let joinedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case slug
        case role
        case joinedAt = "joined_at"
    }

    /// Get display initials (first 2 letters of name)
    var initials: String {
        let words = name.split(separator: " ")
        if words.count >= 2 {
            return String(words[0].prefix(1) + words[1].prefix(1)).uppercased()
        }
        return String(name.prefix(2)).uppercased()
    }
}

/// Context for the current user's tenant state
struct TenantContext: Codable, Equatable {
    let currentTenantId: String
    let currentRole: UserRole
    let availableTenants: [Tenant]

    /// Get the current tenant from available tenants
    var currentTenant: Tenant? {
        availableTenants.first { $0.id == currentTenantId }
    }

    /// Check if user has access to a specific tenant
    func hasAccessTo(tenantId: String) -> Bool {
        availableTenants.contains { $0.id == tenantId }
    }

    /// Check if user is admin or owner in current tenant
    var isAdminOrOwner: Bool {
        currentRole == .admin
    }

    /// Check if user can manage other users
    var canManageUsers: Bool {
        currentRole == .admin
    }

    /// Check if user has multiple tenants
    var hasMultipleTenants: Bool {
        availableTenants.count > 1
    }
}

/// Response from switching tenants
struct TenantSwitchResponse: Codable {
    let data: TenantSwitchData
}

struct TenantSwitchData: Codable {
    let currentTenantId: String
    let role: String
    let accessToken: String
    let refreshToken: String
    let expiresIn: Int
    let tokenType: String

    enum CodingKeys: String, CodingKey {
        case currentTenantId = "current_tenant_id"
        case role
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case expiresIn = "expires_in"
        case tokenType = "token_type"
    }

    var userRole: UserRole {
        UserRole(rawValue: role) ?? .member
    }
}

/// Request to switch tenants
struct TenantSwitchRequest: Codable {
    let tenantId: String

    enum CodingKeys: String, CodingKey {
        case tenantId = "tenant_id"
    }
}

/// Response containing list of tenants
struct TenantsResponse: Codable {
    let data: [Tenant]
}

/// Tenant configuration response
struct TenantConfigResponse: Codable {
    let data: TenantConfig
}

/// Tenant configuration
struct TenantConfig: Codable, Equatable {
    let id: String
    let name: String
    let slug: String
    let pqcAlgorithm: String?
    let plan: String?

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case slug
        case pqcAlgorithm = "pqc_algorithm"
        case plan
    }
}
