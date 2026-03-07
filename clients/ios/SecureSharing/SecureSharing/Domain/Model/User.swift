import Foundation

/// Represents a user in the system
struct User: Codable, Identifiable, Equatable, Hashable {
    let id: String
    let email: String
    let displayName: String?
    let tenantId: String?
    let createdAt: Date
    let updatedAt: Date

    // Public keys for encryption/signing
    var publicKeys: KeyManager.PublicKeys?

    // Server-side key material (returned during login for key unlock/upgrade)
    let encryptedMasterKey: String?
    let keyDerivationSalt: String?

    enum CodingKeys: String, CodingKey {
        case id
        case email
        case displayName = "display_name"
        case tenantId = "tenant_id"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case publicKeys = "public_keys"
        case encryptedMasterKey = "encrypted_master_key"
        case keyDerivationSalt = "key_derivation_salt"
    }

    var initials: String {
        if let name = displayName, !name.isEmpty {
            let components = name.split(separator: " ")
            if components.count >= 2 {
                return String(components[0].prefix(1) + components[1].prefix(1)).uppercased()
            }
            return String(name.prefix(2)).uppercased()
        }
        return String(email.prefix(2)).uppercased()
    }
}

/// Authentication tokens
struct AuthTokens: Codable {
    let accessToken: String
    let refreshToken: String
    let expiresIn: Int

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case expiresIn = "expires_in"
    }
}

/// Login response from server
struct LoginResponse: Codable {
    let user: User
    let tokens: AuthTokens
    let device: Device?
}

/// Registration response from server
struct RegisterResponse: Codable {
    let user: User
    let tokens: AuthTokens
    let device: Device
}

/// Current user info response
struct MeResponse: Codable {
    let user: User
}
