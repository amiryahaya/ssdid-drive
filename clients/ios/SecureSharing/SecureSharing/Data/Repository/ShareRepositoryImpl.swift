import Foundation

/// Implementation of ShareRepository
final class ShareRepositoryImpl: ShareRepository {

    private let apiClient: APIClient
    private let cryptoManager: CryptoManager

    init(apiClient: APIClient, cryptoManager: CryptoManager) {
        self.apiClient = apiClient
        self.cryptoManager = cryptoManager
    }

    // MARK: - Errors

    enum ShareError: Error, LocalizedError {
        case missingGranteePublicKeys
        case missingEncryptedKey
        case keyWrappingFailed

        var errorDescription: String? {
            switch self {
            case .missingGranteePublicKeys:
                return "Recipient's public keys are required for secure sharing"
            case .missingEncryptedKey:
                return "Encryption key is required for sharing"
            case .keyWrappingFailed:
                return "Failed to wrap key for recipient"
            }
        }
    }

    // MARK: - Create Shares

    func shareFile(
        fileId: String,
        granteeId: String,
        granteePublicKeys: KeyManager.PublicKeys,
        fileEncryptedKey: Data,
        permission: Share.Permission,
        expiresAt: Date?
    ) async throws -> Share {
        // Wrap the file DEK for the recipient
        let wrapping: CryptoManager.KeyWrappingResult
        do {
            wrapping = try cryptoManager.wrapKeyForRecipient(
                encryptedKey: fileEncryptedKey,
                recipientPublicKeys: granteePublicKeys
            )
        } catch {
            throw ShareError.keyWrappingFailed
        }

        let body = ShareFileRequest(
            fileId: fileId,
            granteeId: granteeId,
            wrappedKey: wrapping.wrappedKey.base64EncodedString(),
            kemCiphertext: wrapping.kemCiphertext.base64EncodedString(),
            signature: wrapping.signature.base64EncodedString(),
            permission: permission,
            expiresAt: expiresAt
        )

        let response: ShareDataResponse = try await apiClient.request(
            "/shares/file",
            method: .post,
            body: body
        )
        return response.data
    }

    func shareFolder(
        folderId: String,
        granteeId: String,
        granteePublicKeys: KeyManager.PublicKeys,
        folderEncryptedKek: Data,
        permission: Share.Permission,
        recursive: Bool,
        expiresAt: Date?
    ) async throws -> Share {
        // Wrap the folder KEK for the recipient
        let wrapping: CryptoManager.KeyWrappingResult
        do {
            wrapping = try cryptoManager.wrapKeyForRecipient(
                encryptedKey: folderEncryptedKek,
                recipientPublicKeys: granteePublicKeys
            )
        } catch {
            throw ShareError.keyWrappingFailed
        }

        let body = ShareFolderRequest(
            folderId: folderId,
            granteeId: granteeId,
            wrappedKey: wrapping.wrappedKey.base64EncodedString(),
            kemCiphertext: wrapping.kemCiphertext.base64EncodedString(),
            signature: wrapping.signature.base64EncodedString(),
            permission: permission,
            recursive: recursive,
            expiresAt: expiresAt
        )

        let response: ShareDataResponse = try await apiClient.request(
            "/shares/folder",
            method: .post,
            body: body
        )
        return response.data
    }

    // MARK: - List Shares

    func getCreatedShares() async throws -> [Share] {
        let response: ShareListDataResponse = try await apiClient.request("/shares/created")
        return response.data
    }

    func getReceivedShares() async throws -> [Share] {
        let response: ShareListDataResponse = try await apiClient.request("/shares/received")
        return response.data
    }

    func getShare(shareId: String) async throws -> Share {
        let response: ShareDataResponse = try await apiClient.request("/shares/\(shareId)")
        return response.data
    }

    // MARK: - Share Actions

    func revokeShare(shareId: String) async throws {
        try await apiClient.requestNoContent("/shares/\(shareId)", method: .delete)
    }

    func updateSharePermission(
        shareId: String,
        permission: Share.Permission
    ) async throws -> Share {
        let body = UpdatePermissionRequest(permission: permission)
        let response: ShareDataResponse = try await apiClient.request(
            "/shares/\(shareId)/permission",
            method: .put,
            body: body
        )
        return response.data
    }

    func setShareExpiry(
        shareId: String,
        expiresAt: Date?
    ) async throws -> Share {
        let body = UpdateExpiryRequest(expiresAt: expiresAt)
        let response: ShareDataResponse = try await apiClient.request(
            "/shares/\(shareId)/expiry",
            method: .put,
            body: body
        )
        return response.data
    }

    // MARK: - Invitations

    func getInvitations() async throws -> [ShareInvitation] {
        let response: InvitationsListResponse = try await apiClient.request("/shares/invitations")
        return response.invitations
    }

    func acceptInvitation(invitationId: String) async throws {
        try await apiClient.requestNoContent("/shares/invitations/\(invitationId)/accept", method: .post)
    }

    func declineInvitation(invitationId: String) async throws {
        try await apiClient.requestNoContent("/shares/invitations/\(invitationId)/decline", method: .post)
    }

    // MARK: - User Search

    func searchUsers(query: String) async throws -> [User] {
        let encodedQuery = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query
        let response: UsersListResponse = try await apiClient.request("/users/search?q=\(encodedQuery)")
        return response.users
    }
}

// MARK: - Request Types

private struct UpdatePermissionRequest: Codable {
    let permission: Share.Permission
}

private struct UpdateExpiryRequest: Codable {
    let expiresAt: Date?

    enum CodingKeys: String, CodingKey {
        case expiresAt = "expires_at"
    }
}

// MARK: - Response Types

private struct InvitationsListResponse: Codable {
    let invitations: [ShareInvitation]
}

private struct UsersListResponse: Codable {
    let users: [User]
}
