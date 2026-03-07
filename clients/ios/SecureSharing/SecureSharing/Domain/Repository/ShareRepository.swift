import Foundation

/// Repository for sharing operations
protocol ShareRepository {

    // MARK: - Create Shares

    /// Share a file with a user
    /// - Parameters:
    ///   - fileId: The file ID to share
    ///   - granteeId: User ID of the recipient
    ///   - granteePublicKeys: Recipient's public keys for key wrapping
    ///   - fileEncryptedKey: The file's DEK encrypted for the owner (required for key wrapping)
    ///   - permission: Share permission level
    ///   - expiresAt: Optional expiration date
    func shareFile(
        fileId: String,
        granteeId: String,
        granteePublicKeys: KeyManager.PublicKeys,
        fileEncryptedKey: Data,
        permission: Share.Permission,
        expiresAt: Date?
    ) async throws -> Share

    /// Share a folder with a user
    /// - Parameters:
    ///   - folderId: The folder ID to share
    ///   - granteeId: User ID of the recipient
    ///   - granteePublicKeys: Recipient's public keys for key wrapping
    ///   - folderEncryptedKek: The folder's KEK encrypted for the owner (required for key wrapping)
    ///   - permission: Share permission level
    ///   - recursive: Whether to include child files and subfolders
    ///   - expiresAt: Optional expiration date
    func shareFolder(
        folderId: String,
        granteeId: String,
        granteePublicKeys: KeyManager.PublicKeys,
        folderEncryptedKek: Data,
        permission: Share.Permission,
        recursive: Bool,
        expiresAt: Date?
    ) async throws -> Share

    // MARK: - List Shares

    /// Get shares created by current user
    func getCreatedShares() async throws -> [Share]

    /// Get shares received by current user
    func getReceivedShares() async throws -> [Share]

    /// Get share details
    func getShare(shareId: String) async throws -> Share

    // MARK: - Share Actions

    /// Revoke a share (as grantor)
    func revokeShare(shareId: String) async throws

    /// Update share permission
    func updateSharePermission(
        shareId: String,
        permission: Share.Permission
    ) async throws -> Share

    /// Set or remove share expiry
    func setShareExpiry(
        shareId: String,
        expiresAt: Date?
    ) async throws -> Share

    // MARK: - Invitations

    /// Get pending share invitations
    func getInvitations() async throws -> [ShareInvitation]

    /// Accept an invitation
    func acceptInvitation(invitationId: String) async throws

    /// Decline an invitation
    func declineInvitation(invitationId: String) async throws

    // MARK: - User Search

    /// Search for users to share with
    func searchUsers(query: String) async throws -> [User]
}
