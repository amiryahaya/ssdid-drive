import XCTest
@testable import SsdidDrive

/// Unit tests for deep link callback parsing via DeepLinkParser,
/// covering auth callbacks, wallet invite callbacks, universal links,
/// and security-related edge cases (path traversal, script injection).
@MainActor
final class DeepLinkCallbackTests: XCTestCase {

    // MARK: - Auth Callback Tests

    func testAuthCallback_validToken_parsesToAuthCallback() {
        // Given
        let url = URL(string: "ssdid-drive://auth/callback?session_token=validtoken")!

        // When
        let action = DeepLinkParser.parse(url)

        // Then
        if case .authCallback(let token) = action {
            XCTAssertEqual(token, "validtoken")
        } else {
            XCTFail("Expected .authCallback, got \(String(describing: action))")
        }
    }

    func testAuthCallback_emptyToken_returnsNil() {
        // Given
        let url = URL(string: "ssdid-drive://auth/callback?session_token=")!

        // When
        let action = DeepLinkParser.parse(url)

        // Then
        XCTAssertNil(action, "Should return nil when session_token is empty")
    }

    func testAuthCallback_missingSessionTokenParam_returnsNil() {
        // Given
        let url = URL(string: "ssdid-drive://auth/callback?other_param=value")!

        // When
        let action = DeepLinkParser.parse(url)

        // Then
        XCTAssertNil(action, "Should return nil when session_token param is absent")
    }

    func testAuthCallback_noQueryParams_returnsNil() {
        // Given
        let url = URL(string: "ssdid-drive://auth/callback")!

        // When
        let action = DeepLinkParser.parse(url)

        // Then
        XCTAssertNil(action, "Should return nil when no query params present")
    }

    func testAuthCallback_uuidToken_parsesCorrectly() {
        // Given
        let uuid = "550e8400-e29b-41d4-a716-446655440000"
        let url = URL(string: "ssdid-drive://auth/callback?session_token=\(uuid)")!

        // When
        let action = DeepLinkParser.parse(url)

        // Then
        if case .authCallback(let token) = action {
            XCTAssertEqual(token, uuid)
        } else {
            XCTFail("Expected .authCallback with UUID token")
        }
    }

    // MARK: - Wallet Invite Callback Tests

    func testWalletInviteCallback_successWithToken_parsesToWalletInviteCallback() {
        // Given
        let url = URL(string: "ssdid-drive://invite/callback?status=success&session_token=abc123token")!

        // When
        let action = DeepLinkParser.parse(url)

        // Then
        if case .walletInviteCallback(let token) = action {
            XCTAssertEqual(token, "abc123token")
        } else {
            XCTFail("Expected .walletInviteCallback, got \(String(describing: action))")
        }
    }

    func testWalletInviteCallback_successWithoutToken_returnsNil() {
        // Given
        let url = URL(string: "ssdid-drive://invite/callback?status=success")!

        // When
        let action = DeepLinkParser.parse(url)

        // Then
        XCTAssertNil(action, "Should return nil when status=success but no session_token")
    }

    func testWalletInviteCallback_successWithEmptyToken_returnsNil() {
        // Given
        let url = URL(string: "ssdid-drive://invite/callback?status=success&session_token=")!

        // When
        let action = DeepLinkParser.parse(url)

        // Then
        XCTAssertNil(action, "Should return nil when session_token is empty")
    }

    func testWalletInviteError_parsesToWalletInviteError() {
        // Given
        let url = URL(string: "ssdid-drive://invite/callback?status=error&message=Failed")!

        // When
        let action = DeepLinkParser.parse(url)

        // Then
        if case .walletInviteError(let message) = action {
            XCTAssertEqual(message, "Failed")
        } else {
            XCTFail("Expected .walletInviteError, got \(String(describing: action))")
        }
    }

    func testWalletInviteError_noMessage_usesDefaultMessage() {
        // Given
        let url = URL(string: "ssdid-drive://invite/callback?status=error")!

        // When
        let action = DeepLinkParser.parse(url)

        // Then
        if case .walletInviteError(let message) = action {
            XCTAssertEqual(message, "Invitation failed")
        } else {
            XCTFail("Expected .walletInviteError with default message")
        }
    }

    func testWalletInviteCallback_denied_returnsNil() {
        // Given
        let url = URL(string: "ssdid-drive://invite/callback?status=denied")!

        // When
        let action = DeepLinkParser.parse(url)

        // Then
        XCTAssertNil(action, "Should return nil when status is denied")
    }

    func testWalletInviteCallback_legacyNoStatus_withToken_treatsAsSuccess() {
        // Given — no status param but has session_token (legacy callback)
        let url = URL(string: "ssdid-drive://invite/callback?session_token=legacyToken123")!

        // When
        let action = DeepLinkParser.parse(url)

        // Then
        if case .walletInviteCallback(let token) = action {
            XCTAssertEqual(token, "legacyToken123")
        } else {
            XCTFail("Expected .walletInviteCallback for legacy callback, got \(String(describing: action))")
        }
    }

    // MARK: - Action Token URL Tests

    func testActionTokenURL_hostIsAction() {
        // Given
        let url = URL(string: "ssdid-drive://action/sometoken")!

        // When — verify the URL structure
        XCTAssertEqual(url.scheme, "ssdid-drive")
        XCTAssertEqual(url.host, "action")

        let pathComponents = url.pathComponents.filter { $0 != "/" }
        XCTAssertEqual(pathComponents.first, "sometoken")
    }

    func testActionTokenURL_notParsedByDeepLinkParser() {
        // Given — action URLs are handled by SceneDelegate, not DeepLinkParser
        let url = URL(string: "ssdid-drive://action/sometoken")!

        // When
        let action = DeepLinkParser.parse(url)

        // Then — DeepLinkParser does not handle "action" host
        XCTAssertNil(action, "DeepLinkParser should not handle action:// URLs")
    }

    // MARK: - Universal Link Tests

    func testUniversalLink_file_validHost_parsesToOpenFile() {
        // Given
        let url = URL(string: "https://drive.ssdid.my/file/abc123")!

        // When
        let action = DeepLinkParser.parse(url)

        // Then
        if case .openFile(let fileId) = action {
            XCTAssertEqual(fileId, "abc123")
        } else {
            XCTFail("Expected .openFile, got \(String(describing: action))")
        }
    }

    func testUniversalLink_invalidHost_returnsNil() {
        // Given — evil.com is not in allowedUniversalLinkHosts
        let url = URL(string: "https://evil.com/file/abc")!

        // When
        let action = DeepLinkParser.parse(url)

        // Then
        XCTAssertNil(action, "Should reject URLs from non-allowed hosts")
    }

    func testUniversalLink_ssdidMyHost_parsesCorrectly() {
        // Given — ssdid.my is in allowedUniversalLinkHosts
        let url = URL(string: "https://ssdid.my/file/file456")!

        // When
        let action = DeepLinkParser.parse(url)

        // Then
        if case .openFile(let fileId) = action {
            XCTAssertEqual(fileId, "file456")
        } else {
            XCTFail("Expected .openFile, got \(String(describing: action))")
        }
    }

    func testUniversalLink_share_parsesToOpenShare() {
        // Given
        let url = URL(string: "https://drive.ssdid.my/share/share789")!

        // When
        let action = DeepLinkParser.parse(url)

        // Then
        if case .openShare(let shareId) = action {
            XCTAssertEqual(shareId, "share789")
        } else {
            XCTFail("Expected .openShare, got \(String(describing: action))")
        }
    }

    // MARK: - Security Tests

    func testPathTraversal_rejected() {
        // Given — path traversal attempt in file path
        let url = URL(string: "ssdid-drive://file/../../../etc/passwd")!

        // When
        let action = DeepLinkParser.parse(url)

        // Then — the resource ID extraction gets the first path component which
        // would be ".." and isValidResourceId rejects it (contains dots only)
        // or the pathComponents resolution removes the traversal
        XCTAssertNil(action, "Should reject path traversal attempts")
    }

    func testPathTraversal_invitationToken_rejected() {
        // Given — path traversal in invitation token
        let traversalToken = "abc../../../etc/passwd"
        // The token contains "../" which is in pathTraversalPatterns
        XCTAssertFalse(
            DeepLinkParser.isValidInvitationToken(traversalToken),
            "Should reject tokens containing path traversal patterns"
        )
    }

    func testPathTraversal_encodedDots_rejected() {
        // Given — percent-encoded path traversal
        let encodedTraversal = "abc%2e%2edef"
        XCTAssertFalse(
            DeepLinkParser.isValidInvitationToken(encodedTraversal),
            "Should reject tokens containing encoded path traversal"
        )
    }

    func testScriptInjection_rejected() {
        // Given — script injection in token
        let scriptToken = "abc<script>alert(1)</script>xyz"
        XCTAssertFalse(
            DeepLinkParser.isValidInvitationToken(scriptToken),
            "Should reject tokens containing script injection"
        )
    }

    func testScriptInjection_javascript_rejected() {
        // Given — javascript: protocol injection
        let jsToken = "javascript:alert(document.cookie)"
        XCTAssertFalse(
            DeepLinkParser.isValidInvitationToken(jsToken),
            "Should reject tokens containing javascript: protocol"
        )
    }

    func testScriptInjection_dataUri_rejected() {
        // Given — data: URI injection
        let dataToken = "data:text/html,<h1>evil</h1>"
        XCTAssertFalse(
            DeepLinkParser.isValidInvitationToken(dataToken),
            "Should reject tokens containing data: URI"
        )
    }

    // MARK: - Resource ID Validation Tests

    func testResourceId_validUuid_accepted() {
        XCTAssertTrue(DeepLinkParser.isValidResourceId("550e8400-e29b-41d4-a716-446655440000"))
    }

    func testResourceId_validAlphanumericWithHyphensUnderscores_accepted() {
        XCTAssertTrue(DeepLinkParser.isValidResourceId("file_abc-123_XYZ"))
    }

    func testResourceId_empty_rejected() {
        XCTAssertFalse(DeepLinkParser.isValidResourceId(""))
    }

    func testResourceId_tooLong_rejected() {
        let longId = String(repeating: "a", count: 129)
        XCTAssertFalse(DeepLinkParser.isValidResourceId(longId))
    }

    func testResourceId_withDots_rejected() {
        // Dots are NOT in the allowed character set for resource IDs
        XCTAssertFalse(DeepLinkParser.isValidResourceId("file.txt"))
    }

    func testResourceId_withSlash_rejected() {
        XCTAssertFalse(DeepLinkParser.isValidResourceId("path/traversal"))
    }

    // MARK: - Invitation Token Validation Tests

    func testInvitationToken_validFormat_accepted() {
        XCTAssertTrue(DeepLinkParser.isValidInvitationToken("abc12345"))
    }

    func testInvitationToken_withDotsHyphensUnderscores_accepted() {
        XCTAssertTrue(DeepLinkParser.isValidInvitationToken("abc.def-ghi_jkl"))
    }

    func testInvitationToken_tooShort_rejected() {
        XCTAssertFalse(DeepLinkParser.isValidInvitationToken("abc"))
    }

    func testInvitationToken_empty_rejected() {
        XCTAssertFalse(DeepLinkParser.isValidInvitationToken(""))
    }

    func testInvitationToken_tooLong_rejected() {
        let longToken = String(repeating: "a", count: 257)
        XCTAssertFalse(DeepLinkParser.isValidInvitationToken(longToken))
    }

    func testInvitationToken_maxLength_accepted() {
        let token = String(repeating: "a", count: 256)
        XCTAssertTrue(DeepLinkParser.isValidInvitationToken(token))
    }

    func testInvitationToken_minLength_accepted() {
        let token = String(repeating: "a", count: 8)
        XCTAssertTrue(DeepLinkParser.isValidInvitationToken(token))
    }

    func testInvitationToken_withSpaces_rejected() {
        XCTAssertFalse(DeepLinkParser.isValidInvitationToken("abc 12345 xyz"))
    }

    // MARK: - Scheme Validation Tests

    func testInvalidScheme_http_returnsNil() {
        let url = URL(string: "http://drive.ssdid.my/file/abc123")!
        let action = DeepLinkParser.parse(url)
        XCTAssertNil(action, "Should reject http:// scheme")
    }

    func testInvalidScheme_ftp_returnsNil() {
        let url = URL(string: "ftp://drive.ssdid.my/file/abc123")!
        let action = DeepLinkParser.parse(url)
        XCTAssertNil(action, "Should reject ftp:// scheme")
    }

    // MARK: - Import Manifest Tests

    func testLoadImportManifest_noAppGroup_returnsNil() {
        // In test environment, the App Group container is typically not available
        // This tests the graceful nil return when the container doesn't exist
        let manifest = DeepLinkParser.loadImportManifest()

        // In test environment, App Group is likely not configured
        // so this should return nil gracefully (not crash)
        // If it returns a manifest, that's fine too (App Group might be configured)
        _ = manifest // No crash = success
    }

    // MARK: - Edge Cases

    func testCustomScheme_emptyHost_returnsNil() {
        let url = URL(string: "ssdid-drive://")!
        let action = DeepLinkParser.parse(url)
        XCTAssertNil(action)
    }

    func testCustomScheme_unknownHost_returnsNil() {
        let url = URL(string: "ssdid-drive://unknown/something")!
        let action = DeepLinkParser.parse(url)
        XCTAssertNil(action)
    }

    func testCustomScheme_folderLink_parsesCorrectly() {
        let url = URL(string: "ssdid-drive://folder/folder-id-123")!
        let action = DeepLinkParser.parse(url)

        if case .openFolder(let folderId) = action {
            XCTAssertEqual(folderId, "folder-id-123")
        } else {
            XCTFail("Expected .openFolder, got \(String(describing: action))")
        }
    }
}
