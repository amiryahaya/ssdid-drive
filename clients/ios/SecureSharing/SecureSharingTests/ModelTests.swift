import XCTest
@testable import SecureSharing

/// Unit tests for domain model encoding/decoding
final class FileItemModelTests: XCTestCase {

    // MARK: - JSON Decoder Configuration

    var decoder: JSONDecoder!
    var encoder: JSONEncoder!

    override func setUp() {
        super.setUp()
        decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
    }

    // MARK: - FileItem Tests

    func testFileItemDecoding() throws {
        // Given
        let json = """
        {
            "id": "file-123",
            "name": "document.pdf",
            "mime_type": "application/pdf",
            "size": 1024000,
            "folder_id": "folder-456",
            "owner_id": "user-789",
            "encrypted_key": "c2VjcmV0a2V5",
            "created_at": "2024-01-15T10:30:00Z",
            "updated_at": "2024-01-15T11:00:00Z",
            "is_folder": false
        }
        """.data(using: .utf8)!

        // When
        let fileItem = try decoder.decode(FileItem.self, from: json)

        // Then
        XCTAssertEqual(fileItem.id, "file-123")
        XCTAssertEqual(fileItem.name, "document.pdf")
        XCTAssertEqual(fileItem.mimeType, "application/pdf")
        XCTAssertEqual(fileItem.size, 1024000)
        XCTAssertEqual(fileItem.folderId, "folder-456")
        XCTAssertEqual(fileItem.ownerId, "user-789")
        XCTAssertNotNil(fileItem.encryptedKey)
        XCTAssertFalse(fileItem.isFolder)
    }

    func testFileItemEncodingDecoding() throws {
        // Given
        let now = Date()
        let fileItem = FileItem(
            id: "test-id",
            name: "test.txt",
            mimeType: "text/plain",
            size: 500,
            folderId: nil,
            ownerId: "owner-1",
            encryptedKey: Data([0x01, 0x02, 0x03]),
            createdAt: now,
            updatedAt: now,
            isFolder: false
        )

        // When
        let encoded = try encoder.encode(fileItem)
        let decoded = try decoder.decode(FileItem.self, from: encoded)

        // Then
        XCTAssertEqual(decoded.id, fileItem.id)
        XCTAssertEqual(decoded.name, fileItem.name)
        XCTAssertEqual(decoded.mimeType, fileItem.mimeType)
        XCTAssertEqual(decoded.size, fileItem.size)
        XCTAssertEqual(decoded.folderId, fileItem.folderId)
        XCTAssertEqual(decoded.encryptedKey, fileItem.encryptedKey)
    }

    func testFileItemTypeDetection() {
        // Image
        let image = FileItem(id: "1", name: "photo.jpg", mimeType: "image/jpeg", size: 100, folderId: nil, ownerId: "o", encryptedKey: nil, createdAt: Date(), updatedAt: Date())
        XCTAssertTrue(image.isImage)
        XCTAssertFalse(image.isVideo)

        // Video
        let video = FileItem(id: "2", name: "video.mp4", mimeType: "video/mp4", size: 100, folderId: nil, ownerId: "o", encryptedKey: nil, createdAt: Date(), updatedAt: Date())
        XCTAssertTrue(video.isVideo)
        XCTAssertFalse(video.isImage)

        // PDF
        let pdf = FileItem(id: "3", name: "doc.pdf", mimeType: "application/pdf", size: 100, folderId: nil, ownerId: "o", encryptedKey: nil, createdAt: Date(), updatedAt: Date())
        XCTAssertTrue(pdf.isPDF)
        XCTAssertTrue(pdf.isPreviewable)

        // Code file
        let code = FileItem(id: "4", name: "app.swift", mimeType: "text/plain", size: 100, folderId: nil, ownerId: "o", encryptedKey: nil, createdAt: Date(), updatedAt: Date())
        XCTAssertTrue(code.isCode)
    }

    func testFileItemFormattedSize() {
        let file = FileItem(id: "1", name: "test.bin", mimeType: "application/octet-stream", size: 1048576, folderId: nil, ownerId: "o", encryptedKey: nil, createdAt: Date(), updatedAt: Date())
        XCTAssertFalse(file.formattedSize.isEmpty, "Formatted size should not be empty")
    }

    // MARK: - Folder Tests

    func testFolderDecoding() throws {
        // Given
        let json = """
        {
            "id": "folder-123",
            "name": "My Folder",
            "parent_id": null,
            "owner_id": "user-456",
            "created_at": "2024-01-10T09:00:00Z",
            "updated_at": "2024-01-10T09:00:00Z"
        }
        """.data(using: .utf8)!

        // When
        let folder = try decoder.decode(Folder.self, from: json)

        // Then
        XCTAssertEqual(folder.id, "folder-123")
        XCTAssertEqual(folder.name, "My Folder")
        XCTAssertNil(folder.parentId)
        XCTAssertEqual(folder.ownerId, "user-456")
        XCTAssertEqual(folder.iconName, "folder.fill")
    }
}

// MARK: - Share Model Tests

final class ShareModelTests: XCTestCase {

    var decoder: JSONDecoder!
    var encoder: JSONEncoder!

    override func setUp() {
        super.setUp()
        decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
    }

    func testShareDecoding() throws {
        // Given - matches backend ShareJSON response format
        let json = """
        {
            "id": "share-123",
            "resource_type": "file",
            "resource_id": "file-456",
            "grantor_id": "user-1",
            "grantee_id": "user-2",
            "permission": "read",
            "recursive": false,
            "algorithm": "kaz",
            "wrapped_key": "d3JhcHBlZGtleQ==",
            "kem_ciphertext": "a2VtY2lwaGVydGV4dA==",
            "signature": "c2lnbmF0dXJl",
            "expires_at": null,
            "revoked_at": null,
            "revoked_by_id": null,
            "active": true,
            "created_at": "2024-01-15T10:00:00Z",
            "updated_at": "2024-01-15T10:00:00Z"
        }
        """.data(using: .utf8)!

        // When
        let share = try decoder.decode(Share.self, from: json)

        // Then
        XCTAssertEqual(share.id, "share-123")
        XCTAssertEqual(share.resourceType, .file)
        XCTAssertEqual(share.resourceId, "file-456")
        XCTAssertEqual(share.grantorId, "user-1")
        XCTAssertEqual(share.granteeId, "user-2")
        XCTAssertEqual(share.permission, .read)
        XCTAssertFalse(share.recursive)
        XCTAssertEqual(share.algorithm, "kaz")
        XCTAssertNotNil(share.wrappedKey)
        XCTAssertNotNil(share.kemCiphertext)
        XCTAssertNotNil(share.signature)
        XCTAssertTrue(share.isActive)
        XCTAssertTrue(share.active)
        XCTAssertFalse(share.isFolder)
    }

    func testSharePermissionTypes() {
        XCTAssertEqual(Share.Permission.read.displayName, "View only")
        XCTAssertEqual(Share.Permission.write.displayName, "Can edit")
        XCTAssertEqual(Share.Permission.admin.displayName, "Full access")
        XCTAssertEqual(Share.Permission.read.iconName, "eye")
        XCTAssertEqual(Share.Permission.write.iconName, "pencil")
        XCTAssertEqual(Share.Permission.admin.iconName, "person.badge.key")
    }

    func testShareDataResponseDecoding() throws {
        // Given - single share wrapped in data
        let json = """
        {
            "data": {
                "id": "share-123",
                "resource_type": "file",
                "resource_id": "file-456",
                "grantor_id": "user-1",
                "grantee_id": "user-2",
                "permission": "write",
                "recursive": false,
                "algorithm": "kaz",
                "wrapped_key": null,
                "kem_ciphertext": null,
                "signature": null,
                "expires_at": null,
                "revoked_at": null,
                "revoked_by_id": null,
                "active": true,
                "created_at": "2024-01-15T10:00:00Z",
                "updated_at": "2024-01-15T10:00:00Z"
            }
        }
        """.data(using: .utf8)!

        // When
        let response = try decoder.decode(ShareDataResponse.self, from: json)

        // Then
        XCTAssertEqual(response.data.id, "share-123")
        XCTAssertEqual(response.data.permission, .write)
    }

    func testShareInvitationDecoding() throws {
        // Given
        let json = """
        {
            "id": "inv-123",
            "share_id": "share-456",
            "resource_type": "folder",
            "resource_name": "Shared Folder",
            "permission": "write",
            "sender_email": "sender@example.com",
            "sender_name": "John Doe",
            "expires_at": "2024-02-15T00:00:00Z",
            "created_at": "2024-01-15T00:00:00Z"
        }
        """.data(using: .utf8)!

        // When
        let invitation = try decoder.decode(ShareInvitation.self, from: json)

        // Then
        XCTAssertEqual(invitation.id, "inv-123")
        XCTAssertEqual(invitation.shareId, "share-456")
        XCTAssertEqual(invitation.resourceType, .folder)
        XCTAssertEqual(invitation.resourceName, "Shared Folder")
        XCTAssertEqual(invitation.permission, .write)
        XCTAssertEqual(invitation.senderEmail, "sender@example.com")
        XCTAssertEqual(invitation.senderName, "John Doe")
    }

    // MARK: - Permission Enum Raw Values

    func testPermissionRawValues() {
        // Verify raw values match the backend string format exactly
        XCTAssertEqual(Share.Permission.read.rawValue, "read")
        XCTAssertEqual(Share.Permission.write.rawValue, "write")
        XCTAssertEqual(Share.Permission.admin.rawValue, "admin")
    }

    func testPermissionDecodingFromRawValues() throws {
        // Given - JSON with each permission level
        let readJson = """
        {"permission": "read"}
        """.data(using: .utf8)!
        let writeJson = """
        {"permission": "write"}
        """.data(using: .utf8)!
        let adminJson = """
        {"permission": "admin"}
        """.data(using: .utf8)!

        struct PermissionWrapper: Codable {
            let permission: Share.Permission
        }

        // When/Then
        let readWrapper = try decoder.decode(PermissionWrapper.self, from: readJson)
        XCTAssertEqual(readWrapper.permission, .read)

        let writeWrapper = try decoder.decode(PermissionWrapper.self, from: writeJson)
        XCTAssertEqual(writeWrapper.permission, .write)

        let adminWrapper = try decoder.decode(PermissionWrapper.self, from: adminJson)
        XCTAssertEqual(adminWrapper.permission, .admin)
    }

    func testPermissionCaseIterable() {
        // Verify all permission cases are present
        let allCases = Share.Permission.allCases
        XCTAssertEqual(allCases.count, 3)
        XCTAssertTrue(allCases.contains(.read))
        XCTAssertTrue(allCases.contains(.write))
        XCTAssertTrue(allCases.contains(.admin))
    }

    // MARK: - isFolder Computed Property

    func testIsFolder_fileShare_returnsFalse() throws {
        // Given
        let json = """
        {
            "id": "share-1",
            "resource_type": "file",
            "resource_id": "file-1",
            "grantor_id": "user-1",
            "grantee_id": "user-2",
            "permission": "read",
            "recursive": false,
            "active": true,
            "created_at": "2024-01-15T10:00:00Z",
            "updated_at": "2024-01-15T10:00:00Z"
        }
        """.data(using: .utf8)!

        // When
        let share = try decoder.decode(Share.self, from: json)

        // Then
        XCTAssertFalse(share.isFolder)
        XCTAssertEqual(share.resourceType, .file)
    }

    func testIsFolder_folderShare_returnsTrue() throws {
        // Given
        let json = """
        {
            "id": "share-2",
            "resource_type": "folder",
            "resource_id": "folder-1",
            "grantor_id": "user-1",
            "grantee_id": "user-2",
            "permission": "admin",
            "recursive": true,
            "active": true,
            "created_at": "2024-01-15T10:00:00Z",
            "updated_at": "2024-01-15T10:00:00Z"
        }
        """.data(using: .utf8)!

        // When
        let share = try decoder.decode(Share.self, from: json)

        // Then
        XCTAssertTrue(share.isFolder)
        XCTAssertEqual(share.resourceType, .folder)
    }

    // MARK: - isActive Computed Property

    func testIsActive_activeShare_returnsTrue() throws {
        // Given
        let json = """
        {
            "id": "share-active",
            "resource_type": "file",
            "resource_id": "file-1",
            "grantor_id": "user-1",
            "grantee_id": "user-2",
            "permission": "read",
            "recursive": false,
            "active": true,
            "created_at": "2024-01-15T10:00:00Z",
            "updated_at": "2024-01-15T10:00:00Z"
        }
        """.data(using: .utf8)!

        // When
        let share = try decoder.decode(Share.self, from: json)

        // Then
        XCTAssertTrue(share.isActive)
    }

    func testIsActive_revokedShare_returnsFalse() throws {
        // Given - share that has been revoked
        let json = """
        {
            "id": "share-revoked",
            "resource_type": "file",
            "resource_id": "file-1",
            "grantor_id": "user-1",
            "grantee_id": "user-2",
            "permission": "write",
            "recursive": false,
            "revoked_at": "2024-01-20T00:00:00Z",
            "revoked_by_id": "user-1",
            "active": false,
            "created_at": "2024-01-15T10:00:00Z",
            "updated_at": "2024-01-20T00:00:00Z"
        }
        """.data(using: .utf8)!

        // When
        let share = try decoder.decode(Share.self, from: json)

        // Then
        XCTAssertFalse(share.isActive)
        XCTAssertFalse(share.active)
        XCTAssertNotNil(share.revokedAt)
        XCTAssertEqual(share.revokedById, "user-1")
    }

    // MARK: - ShareFileRequest Encoding

    func testShareFileRequestEncoding() throws {
        // Given
        let request = ShareFileRequest(
            fileId: "file-abc",
            granteeId: "user-xyz",
            wrappedKey: "d3JhcHBlZGtleQ==",
            kemCiphertext: "a2VtY2lwaGVydGV4dA==",
            signature: "c2lnbmF0dXJl",
            permission: .write,
            expiresAt: nil
        )

        // When
        let data = try encoder.encode(request)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]

        // Then - verify snake_case keys in encoded output
        XCTAssertEqual(json["file_id"] as? String, "file-abc")
        XCTAssertEqual(json["grantee_id"] as? String, "user-xyz")
        XCTAssertEqual(json["wrapped_key"] as? String, "d3JhcHBlZGtleQ==")
        XCTAssertEqual(json["kem_ciphertext"] as? String, "a2VtY2lwaGVydGV4dA==")
        XCTAssertEqual(json["signature"] as? String, "c2lnbmF0dXJl")
        XCTAssertEqual(json["permission"] as? String, "write")

        // Verify no camelCase keys leaked
        XCTAssertNil(json["fileId"])
        XCTAssertNil(json["granteeId"])
        XCTAssertNil(json["wrappedKey"])
        XCTAssertNil(json["kemCiphertext"])
        XCTAssertNil(json["expiresAt"])
    }

    func testShareFileRequestEncodingWithExpiry() throws {
        // Given
        let expiryDate = ISO8601DateFormatter().date(from: "2024-06-01T00:00:00Z")!
        let request = ShareFileRequest(
            fileId: "file-123",
            granteeId: "user-456",
            wrappedKey: "a2V5",
            kemCiphertext: "Y2lwaGVy",
            signature: "c2ln",
            permission: .read,
            expiresAt: expiryDate
        )

        // When
        let data = try encoder.encode(request)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]

        // Then
        XCTAssertNotNil(json["expires_at"])
        XCTAssertEqual(json["permission"] as? String, "read")
    }

    // MARK: - ShareFolderRequest Encoding

    func testShareFolderRequestEncoding() throws {
        // Given
        let request = ShareFolderRequest(
            folderId: "folder-abc",
            granteeId: "user-xyz",
            wrappedKey: "d3JhcHBlZGtleQ==",
            kemCiphertext: "a2VtY2lwaGVydGV4dA==",
            signature: "c2lnbmF0dXJl",
            permission: .admin,
            recursive: true,
            expiresAt: nil
        )

        // When
        let data = try encoder.encode(request)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]

        // Then - verify snake_case keys in encoded output
        XCTAssertEqual(json["folder_id"] as? String, "folder-abc")
        XCTAssertEqual(json["grantee_id"] as? String, "user-xyz")
        XCTAssertEqual(json["wrapped_key"] as? String, "d3JhcHBlZGtleQ==")
        XCTAssertEqual(json["kem_ciphertext"] as? String, "a2VtY2lwaGVydGV4dA==")
        XCTAssertEqual(json["signature"] as? String, "c2lnbmF0dXJl")
        XCTAssertEqual(json["permission"] as? String, "admin")
        XCTAssertEqual(json["recursive"] as? Bool, true)

        // Verify no camelCase keys leaked
        XCTAssertNil(json["folderId"])
        XCTAssertNil(json["granteeId"])
        XCTAssertNil(json["wrappedKey"])
        XCTAssertNil(json["kemCiphertext"])
    }

    func testShareFolderRequestEncodingNonRecursive() throws {
        // Given
        let request = ShareFolderRequest(
            folderId: "folder-123",
            granteeId: "user-456",
            wrappedKey: "a2V5",
            kemCiphertext: "Y2lwaGVy",
            signature: "c2ln",
            permission: .read,
            recursive: false,
            expiresAt: nil
        )

        // When
        let data = try encoder.encode(request)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]

        // Then
        XCTAssertEqual(json["recursive"] as? Bool, false)
        XCTAssertEqual(json["permission"] as? String, "read")
    }

    // MARK: - ShareListDataResponse Decoding

    func testShareListDataResponseDecoding() throws {
        // Given - list of shares wrapped in data
        let json = """
        {
            "data": [
                {
                    "id": "share-1",
                    "resource_type": "file",
                    "resource_id": "file-1",
                    "grantor_id": "user-1",
                    "grantee_id": "user-2",
                    "permission": "read",
                    "recursive": false,
                    "active": true,
                    "created_at": "2024-01-15T10:00:00Z",
                    "updated_at": "2024-01-15T10:00:00Z"
                },
                {
                    "id": "share-2",
                    "resource_type": "folder",
                    "resource_id": "folder-1",
                    "grantor_id": "user-1",
                    "grantee_id": "user-3",
                    "permission": "admin",
                    "recursive": true,
                    "active": true,
                    "created_at": "2024-01-16T10:00:00Z",
                    "updated_at": "2024-01-16T10:00:00Z"
                }
            ]
        }
        """.data(using: .utf8)!

        // When
        let response = try decoder.decode(ShareListDataResponse.self, from: json)

        // Then
        XCTAssertEqual(response.data.count, 2)
        XCTAssertEqual(response.data[0].id, "share-1")
        XCTAssertFalse(response.data[0].isFolder)
        XCTAssertEqual(response.data[1].id, "share-2")
        XCTAssertTrue(response.data[1].isFolder)
        XCTAssertTrue(response.data[1].recursive)
    }

    // MARK: - ResourceType Enum

    func testResourceTypeRawValues() {
        XCTAssertEqual(Share.ResourceType.file.rawValue, "file")
        XCTAssertEqual(Share.ResourceType.folder.rawValue, "folder")
    }
}

// MARK: - User Model Tests

final class UserModelTests: XCTestCase {

    var decoder: JSONDecoder!

    override func setUp() {
        super.setUp()
        decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
    }

    func testUserDecoding() throws {
        // Given
        let json = """
        {
            "id": "user-123",
            "email": "test@example.com",
            "display_name": "Test User",
            "tenant_id": "tenant-456",
            "created_at": "2024-01-01T00:00:00Z",
            "updated_at": "2024-01-15T00:00:00Z"
        }
        """.data(using: .utf8)!

        // When
        let user = try decoder.decode(User.self, from: json)

        // Then
        XCTAssertEqual(user.id, "user-123")
        XCTAssertEqual(user.email, "test@example.com")
        XCTAssertEqual(user.displayName, "Test User")
        XCTAssertEqual(user.tenantId, "tenant-456")
    }

    func testUserInitials() throws {
        // Given
        let json1 = """
        {"id": "1", "email": "test@example.com", "display_name": "John Doe", "created_at": "2024-01-01T00:00:00Z", "updated_at": "2024-01-01T00:00:00Z"}
        """.data(using: .utf8)!

        let json2 = """
        {"id": "2", "email": "test@example.com", "display_name": "Alice", "created_at": "2024-01-01T00:00:00Z", "updated_at": "2024-01-01T00:00:00Z"}
        """.data(using: .utf8)!

        let json3 = """
        {"id": "3", "email": "bob@example.com", "display_name": null, "created_at": "2024-01-01T00:00:00Z", "updated_at": "2024-01-01T00:00:00Z"}
        """.data(using: .utf8)!

        // When
        let user1 = try decoder.decode(User.self, from: json1)
        let user2 = try decoder.decode(User.self, from: json2)
        let user3 = try decoder.decode(User.self, from: json3)

        // Then
        XCTAssertEqual(user1.initials, "JD", "Should use first letters of first and last name")
        XCTAssertEqual(user2.initials, "AL", "Should use first two letters of single name")
        XCTAssertEqual(user3.initials, "BO", "Should use first two letters of email when no display name")
    }

    func testAuthTokensDecoding() throws {
        // Given
        let json = """
        {
            "access_token": "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9",
            "refresh_token": "refresh-token-value",
            "expires_in": 3600
        }
        """.data(using: .utf8)!

        // When
        let tokens = try decoder.decode(AuthTokens.self, from: json)

        // Then
        XCTAssertEqual(tokens.accessToken, "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9")
        XCTAssertEqual(tokens.refreshToken, "refresh-token-value")
        XCTAssertEqual(tokens.expiresIn, 3600)
    }
}

// MARK: - Device Model Tests

final class DeviceModelTests: XCTestCase {

    var decoder: JSONDecoder!

    override func setUp() {
        super.setUp()
        decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
    }

    func testDeviceDecoding() throws {
        // Given
        let json = """
        {
            "id": "device-123",
            "name": "iPhone 15 Pro",
            "platform": "ios",
            "public_key": "cHVibGlja2V5ZGF0YQ==",
            "user_id": "user-456",
            "is_revoked": false,
            "last_active_at": "2024-01-15T12:00:00Z",
            "created_at": "2024-01-01T00:00:00Z"
        }
        """.data(using: .utf8)!

        // When
        let device = try decoder.decode(Device.self, from: json)

        // Then
        XCTAssertEqual(device.id, "device-123")
        XCTAssertEqual(device.name, "iPhone 15 Pro")
        XCTAssertEqual(device.platform, "ios")
        XCTAssertEqual(device.userId, "user-456")
        XCTAssertFalse(device.isRevoked)
        XCTAssertNotNil(device.lastActiveAt)
    }

    func testDevicePlatformIcons() throws {
        // Create devices with different platforms
        let platforms = ["ios", "android", "web", "macos", "windows", "linux"]
        let expectedIcons = ["iphone", "flipphone", "globe", "laptopcomputer", "pc", "desktopcomputer"]

        for (index, platform) in platforms.enumerated() {
            let json = """
            {
                "id": "device-\(index)",
                "name": "Test Device",
                "platform": "\(platform)",
                "public_key": "cHVibGlja2V5",
                "user_id": "user-1",
                "is_revoked": false,
                "created_at": "2024-01-01T00:00:00Z"
            }
            """.data(using: .utf8)!

            let device = try decoder.decode(Device.self, from: json)
            XCTAssertEqual(device.platformIcon, expectedIcons[index], "Platform \(platform) should have icon \(expectedIcons[index])")
        }
    }

    func testDeviceIsCurrent() throws {
        // Given
        let json = """
        {
            "id": "device-123",
            "name": "Test Device",
            "platform": "ios",
            "public_key": "cHVibGlja2V5",
            "user_id": "user-1",
            "is_revoked": false,
            "created_at": "2024-01-01T00:00:00Z"
        }
        """.data(using: .utf8)!

        let device = try decoder.decode(Device.self, from: json)

        // Then
        XCTAssertTrue(device.isCurrent(deviceId: "device-123"))
        XCTAssertFalse(device.isCurrent(deviceId: "device-456"))
        XCTAssertFalse(device.isCurrent(deviceId: nil))
    }
}

// MARK: - Recovery Model Tests

final class RecoveryModelTests: XCTestCase {

    var decoder: JSONDecoder!

    override func setUp() {
        super.setUp()
        decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
    }

    func testRecoveryConfigDecoding() throws {
        // Given
        let json = """
        {
            "is_configured": true,
            "threshold": 3,
            "total_shares": 5,
            "trustees": [
                {
                    "id": "trustee-1",
                    "user_id": "user-1",
                    "email": "trustee1@example.com",
                    "display_name": "Trustee One",
                    "has_accepted": true,
                    "accepted_at": "2024-01-10T00:00:00Z"
                }
            ],
            "created_at": "2024-01-01T00:00:00Z"
        }
        """.data(using: .utf8)!

        // When
        let config = try decoder.decode(RecoveryConfig.self, from: json)

        // Then
        XCTAssertTrue(config.isConfigured)
        XCTAssertEqual(config.threshold, 3)
        XCTAssertEqual(config.totalShares, 5)
        XCTAssertEqual(config.trustees.count, 1)
        XCTAssertEqual(config.trustees[0].email, "trustee1@example.com")
        XCTAssertTrue(config.trustees[0].hasAccepted)
    }

    func testRecoveryConfigNotConfigured() {
        let config = RecoveryConfig.notConfigured
        XCTAssertFalse(config.isConfigured)
        XCTAssertEqual(config.threshold, 0)
        XCTAssertEqual(config.totalShares, 0)
        XCTAssertTrue(config.trustees.isEmpty)
        XCTAssertNil(config.createdAt)
    }

    func testRecoveryRequestDecoding() throws {
        // Given
        let json = """
        {
            "id": "request-123",
            "requester_id": "user-456",
            "requester_email": "requester@example.com",
            "requester_name": "John Requester",
            "status": "pending",
            "approved_shares": 2,
            "required_shares": 3,
            "expires_at": "2024-01-20T00:00:00Z",
            "created_at": "2024-01-15T00:00:00Z"
        }
        """.data(using: .utf8)!

        // When
        let request = try decoder.decode(RecoveryRequest.self, from: json)

        // Then
        XCTAssertEqual(request.id, "request-123")
        XCTAssertEqual(request.requesterEmail, "requester@example.com")
        XCTAssertEqual(request.status, .pending)
        XCTAssertEqual(request.approvedShares, 2)
        XCTAssertEqual(request.requiredShares, 3)
        XCTAssertFalse(request.hasThresholdMet)
        XCTAssertEqual(request.progress, 2.0 / 3.0, accuracy: 0.001)
    }

    func testRecoveryRequestThresholdMet() throws {
        // Given
        let json = """
        {
            "id": "request-123",
            "requester_id": "user-456",
            "requester_email": "requester@example.com",
            "status": "approved",
            "approved_shares": 3,
            "required_shares": 3,
            "expires_at": "2024-01-20T00:00:00Z",
            "created_at": "2024-01-15T00:00:00Z"
        }
        """.data(using: .utf8)!

        // When
        let request = try decoder.decode(RecoveryRequest.self, from: json)

        // Then
        XCTAssertTrue(request.hasThresholdMet)
        XCTAssertEqual(request.progress, 1.0, accuracy: 0.001)
    }

    func testRecoveryShareDecoding() throws {
        // Given
        let json = """
        {
            "id": "share-123",
            "trustee_id": "trustee-456",
            "encrypted_share": "ZW5jcnlwdGVkc2hhcmU=",
            "share_index": 2,
            "created_at": "2024-01-15T00:00:00Z"
        }
        """.data(using: .utf8)!

        // When
        let share = try decoder.decode(RecoveryShare.self, from: json)

        // Then
        XCTAssertEqual(share.id, "share-123")
        XCTAssertEqual(share.trusteeId, "trustee-456")
        XCTAssertEqual(share.shareIndex, 2)
        XCTAssertNotNil(share.encryptedShare)
    }

    func testRecoveryRequestStatusTypes() {
        XCTAssertEqual(RecoveryRequest.Status.pending.displayName, "Pending")
        XCTAssertEqual(RecoveryRequest.Status.approved.displayName, "Approved")
        XCTAssertEqual(RecoveryRequest.Status.rejected.displayName, "Rejected")
        XCTAssertEqual(RecoveryRequest.Status.expired.displayName, "Expired")
        XCTAssertEqual(RecoveryRequest.Status.completed.displayName, "Completed")
    }
}

// MARK: - Sort Option Tests

final class SortOptionTests: XCTestCase {

    func testSortOptionDisplayNames() {
        XCTAssertEqual(SortOption.name.displayName, "Name")
        XCTAssertEqual(SortOption.date.displayName, "Date")
        XCTAssertEqual(SortOption.size.displayName, "Size")
        XCTAssertEqual(SortOption.type.displayName, "Type")
    }

    func testSortOptionIconNames() {
        XCTAssertEqual(SortOption.name.iconName, "textformat.abc")
        XCTAssertEqual(SortOption.date.iconName, "calendar")
        XCTAssertEqual(SortOption.size.iconName, "arrow.up.arrow.down")
        XCTAssertEqual(SortOption.type.iconName, "doc")
    }

    func testAllSortOptionsCovered() {
        XCTAssertEqual(SortOption.allCases.count, 4)
    }
}
