import Foundation

// MARK: - Removed: WebAuthn/Passkey authentication replaced by SSDID wallet authentication

/// Stub: WebAuthn authentication has been replaced by SSDID wallet QR-based authentication.
/// Protocol and types are kept to satisfy existing DI container references.
final class WebAuthnRepositoryImpl: WebAuthnRepository {

    init(apiClient: APIClient, keychainManager: KeychainManager, keyManager: KeyManager) {}

    func loginBegin(email: String?) async throws -> WebAuthnBeginResult {
        throw AuthError.notAuthenticated
    }

    func loginComplete(challengeId: String, assertionData: [String: Any]) async throws -> User {
        throw AuthError.notAuthenticated
    }

    func getCredentials() async throws -> [UserCredential] {
        return []
    }

    func renameCredential(credentialId: String, name: String) async throws -> UserCredential {
        throw AuthError.notAuthenticated
    }

    func deleteCredential(credentialId: String) async throws {
        throw AuthError.notAuthenticated
    }
}

/// Type-erased Codable wrapper for dynamic JSON (kept for potential future use)
struct AnyCodable: Codable {
    let value: Any

    init(_ value: Any) {
        self.value = value
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let dict = try? container.decode([String: AnyCodable].self) {
            value = dict.mapValues { $0.value }
        } else if let array = try? container.decode([AnyCodable].self) {
            value = array.map { $0.value }
        } else if let string = try? container.decode(String.self) {
            value = string
        } else if let int = try? container.decode(Int.self) {
            value = int
        } else if let double = try? container.decode(Double.self) {
            value = double
        } else if let bool = try? container.decode(Bool.self) {
            value = bool
        } else {
            value = NSNull()
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        if let dict = value as? [String: Any] {
            try container.encode(dict.mapValues { AnyCodable($0) })
        } else if let array = value as? [Any] {
            try container.encode(array.map { AnyCodable($0) })
        } else if let string = value as? String {
            try container.encode(string)
        } else if let int = value as? Int {
            try container.encode(int)
        } else if let double = value as? Double {
            try container.encode(double)
        } else if let bool = value as? Bool {
            try container.encode(bool)
        } else {
            try container.encodeNil()
        }
    }
}
