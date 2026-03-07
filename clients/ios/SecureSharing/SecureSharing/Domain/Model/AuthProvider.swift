import Foundation

/// Authentication provider (OIDC IdP or WebAuthn)
struct AuthProvider: Codable, Identifiable {
    let id: String
    let name: String
    let providerType: String
    let enabled: Bool

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case providerType = "provider_type"
        case enabled
    }
}

/// User credential for WebAuthn or OIDC
struct UserCredential: Codable, Identifiable {
    let id: String
    let credentialType: String
    let name: String?
    let providerName: String?
    let createdAt: String
    let lastUsedAt: String?

    enum CodingKeys: String, CodingKey {
        case id
        case credentialType = "credential_type"
        case name
        case providerName = "provider_name"
        case createdAt = "created_at"
        case lastUsedAt = "last_used_at"
    }
}
