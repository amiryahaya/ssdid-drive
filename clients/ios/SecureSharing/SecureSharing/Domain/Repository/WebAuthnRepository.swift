import Foundation

/// WebAuthn login begin result
struct WebAuthnBeginResult {
    let optionsJson: String
    let challengeId: String
}

/// Repository for WebAuthn/Passkey authentication operations
protocol WebAuthnRepository: AnyObject {
    /// Begin WebAuthn login (passkey assertion)
    func loginBegin(email: String?) async throws -> WebAuthnBeginResult

    /// Complete WebAuthn login with assertion
    func loginComplete(challengeId: String, assertionData: [String: Any]) async throws -> User

    /// Get user's credentials
    func getCredentials() async throws -> [UserCredential]

    /// Rename a credential
    func renameCredential(credentialId: String, name: String) async throws -> UserCredential

    /// Delete a credential
    func deleteCredential(credentialId: String) async throws
}
