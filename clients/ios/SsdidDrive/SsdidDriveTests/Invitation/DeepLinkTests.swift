import XCTest
@testable import SsdidDrive

/// Unit tests for deep link parsing, particularly invitation deep links
@MainActor
final class DeepLinkTests: XCTestCase {

    // MARK: - Custom Scheme Tests (ssdid-drive://)

    func testCustomScheme_inviteLink_extractsToken() {
        // Given
        let url = URL(string: "ssdid-drive://invite/abc123xyz789")!

        // When
        let result = parseInviteToken(from: url)

        // Then
        XCTAssertEqual(result, "abc123xyz789")
    }

    func testCustomScheme_inviteLink_extractsComplexToken() {
        // Given
        let url = URL(string: "ssdid-drive://invite/Abc-123_XyZ.789")!

        // When
        let result = parseInviteToken(from: url)

        // Then
        XCTAssertEqual(result, "Abc-123_XyZ.789")
    }

    func testCustomScheme_inviteLink_handlesLongToken() {
        // Given
        let longToken = String(repeating: "a", count: 64)
        let url = URL(string: "ssdid-drive://invite/\(longToken)")!

        // When
        let result = parseInviteToken(from: url)

        // Then
        XCTAssertEqual(result, longToken)
    }

    func testCustomScheme_inviteLink_missingToken_returnsNil() {
        // Given
        let url = URL(string: "ssdid-drive://invite/")!

        // When
        let result = parseInviteToken(from: url)

        // Then
        XCTAssertNil(result)
    }

    func testCustomScheme_inviteLink_emptyToken_returnsNil() {
        // Given
        let url = URL(string: "ssdid-drive://invite")!

        // When
        let result = parseInviteToken(from: url)

        // Then
        XCTAssertNil(result)
    }

    func testCustomScheme_shareLink_returnsNil() {
        // Given
        let url = URL(string: "ssdid-drive://share/abc123")!

        // When
        let result = parseInviteToken(from: url)

        // Then
        XCTAssertNil(result) // Not an invite link
    }

    func testCustomScheme_fileLink_returnsNil() {
        // Given
        let url = URL(string: "ssdid-drive://file/abc123")!

        // When
        let result = parseInviteToken(from: url)

        // Then
        XCTAssertNil(result) // Not an invite link
    }

    // MARK: - Universal Link Tests (https://)

    func testUniversalLink_inviteLink_extractsToken() {
        // Given
        let url = URL(string: "https://app.ssdid-drive.com/invite/abc123xyz789")!

        // When
        let result = parseInviteToken(from: url)

        // Then
        XCTAssertEqual(result, "abc123xyz789")
    }

    func testUniversalLink_inviteLink_extractsComplexToken() {
        // Given
        let url = URL(string: "https://app.ssdid-drive.com/invite/Abc-123_XyZ.789")!

        // When
        let result = parseInviteToken(from: url)

        // Then
        XCTAssertEqual(result, "Abc-123_XyZ.789")
    }

    func testUniversalLink_inviteLink_missingToken_returnsNil() {
        // Given
        let url = URL(string: "https://app.ssdid-drive.com/invite/")!

        // When
        let result = parseInviteToken(from: url)

        // Then
        XCTAssertNil(result)
    }

    func testUniversalLink_shareLink_returnsNil() {
        // Given
        let url = URL(string: "https://app.ssdid-drive.com/share/abc123")!

        // When
        let result = parseInviteToken(from: url)

        // Then
        XCTAssertNil(result) // Not an invite link
    }

    func testUniversalLink_withQueryParams_extractsToken() {
        // Given
        let url = URL(string: "https://app.ssdid-drive.com/invite/abc123?source=email")!

        // When
        let result = parseInviteToken(from: url)

        // Then
        XCTAssertEqual(result, "abc123")
    }

    // MARK: - Invalid URL Tests

    func testInvalidURL_randomScheme_returnsNil() {
        // Given
        let url = URL(string: "http://example.com/invite/abc123")!

        // When
        let result = parseInviteToken(from: url)

        // Then
        XCTAssertNil(result) // Wrong scheme
    }

    func testInvalidURL_malformedURL_handlesGracefully() {
        // Given - This should be handled gracefully
        let url = URL(string: "ssdid-drive://")!

        // When
        let result = parseInviteToken(from: url)

        // Then
        XCTAssertNil(result)
    }

    // MARK: - URL Type Detection Tests

    func testURLType_customSchemeInvite_isInviteType() {
        // Given
        let url = URL(string: "ssdid-drive://invite/abc123")!

        // When
        let type = getDeepLinkType(from: url)

        // Then
        XCTAssertEqual(type, .invite)
    }

    func testURLType_universalLinkInvite_isInviteType() {
        // Given
        let url = URL(string: "https://app.ssdid-drive.com/invite/abc123")!

        // When
        let type = getDeepLinkType(from: url)

        // Then
        XCTAssertEqual(type, .invite)
    }

    func testURLType_shareLink_isShareType() {
        // Given
        let url = URL(string: "ssdid-drive://share/abc123")!

        // When
        let type = getDeepLinkType(from: url)

        // Then
        XCTAssertEqual(type, .share)
    }

    func testURLType_fileLink_isFileType() {
        // Given
        let url = URL(string: "ssdid-drive://file/abc123")!

        // When
        let type = getDeepLinkType(from: url)

        // Then
        XCTAssertEqual(type, .file)
    }

    func testURLType_folderLink_isFolderType() {
        // Given
        let url = URL(string: "ssdid-drive://folder/abc123")!

        // When
        let type = getDeepLinkType(from: url)

        // Then
        XCTAssertEqual(type, .folder)
    }

    func testURLType_unknownHost_isUnknownType() {
        // Given
        let url = URL(string: "ssdid-drive://unknown/abc123")!

        // When
        let type = getDeepLinkType(from: url)

        // Then
        XCTAssertEqual(type, .unknown)
    }

    // MARK: - URL Component Extraction Tests

    func testExtractId_customScheme_extractsFromPath() {
        // Given
        let url = URL(string: "ssdid-drive://file/file123")!

        // When
        let id = extractResourceId(from: url)

        // Then
        XCTAssertEqual(id, "file123")
    }

    func testExtractId_universalLink_extractsFromPath() {
        // Given
        let url = URL(string: "https://app.ssdid-drive.com/file/file456")!

        // When
        let id = extractResourceId(from: url)

        // Then
        XCTAssertEqual(id, "file456")
    }

    func testExtractId_missingPath_returnsNil() {
        // Given
        let url = URL(string: "ssdid-drive://file")!

        // When
        let id = extractResourceId(from: url)

        // Then
        XCTAssertNil(id)
    }

    // MARK: - Edge Cases

    func testInviteToken_withEncodedCharacters() {
        // Given - URL-encoded token
        let url = URL(string: "ssdid-drive://invite/abc%20123")!

        // When
        let result = parseInviteToken(from: url)

        // Then
        XCTAssertEqual(result, "abc 123") // Should decode
    }

    func testInviteToken_withPlusSign() {
        // Given
        let url = URL(string: "ssdid-drive://invite/abc+123")!

        // When
        let result = parseInviteToken(from: url)

        // Then
        XCTAssertEqual(result, "abc+123")
    }

    func testInviteToken_withSlashInToken() {
        // Given - This would be unusual but should handle gracefully
        let url = URL(string: "ssdid-drive://invite/abc/123")!

        // When
        let result = parseInviteToken(from: url)

        // Then - Should get first path component only
        XCTAssertEqual(result, "abc")
    }

    // MARK: - Helper Methods

    /// Parse invite token from URL (mirrors AppCoordinator logic)
    private func parseInviteToken(from url: URL) -> String? {
        let host: String?
        let pathComponents: [String]

        if url.scheme == "ssdid-drive" {
            host = url.host
            pathComponents = url.pathComponents.filter { $0 != "/" }
        } else if url.scheme == "https" {
            pathComponents = url.pathComponents.filter { $0 != "/" }
            host = pathComponents.first
        } else {
            return nil
        }

        guard host == "invite" else {
            return nil
        }

        let token: String?
        if url.scheme == "ssdid-drive" {
            token = pathComponents.first
        } else {
            token = pathComponents.dropFirst().first
        }

        // Return nil for empty strings
        guard let token = token, !token.isEmpty else {
            return nil
        }

        return token.removingPercentEncoding ?? token
    }

    /// Get deep link type from URL
    private func getDeepLinkType(from url: URL) -> DeepLinkType {
        let host: String?

        if url.scheme == "ssdid-drive" {
            host = url.host
        } else if url.scheme == "https" {
            let pathComponents = url.pathComponents.filter { $0 != "/" }
            host = pathComponents.first
        } else {
            return .unknown
        }

        switch host {
        case "invite": return .invite
        case "share": return .share
        case "file": return .file
        case "folder": return .folder
        default: return .unknown
        }
    }

    /// Extract resource ID from URL
    private func extractResourceId(from url: URL) -> String? {
        let pathComponents = url.pathComponents.filter { $0 != "/" }

        if url.scheme == "ssdid-drive" {
            return pathComponents.first
        } else {
            return pathComponents.dropFirst().first
        }
    }

    // MARK: - Auth Callback Deep Link Tests (ssdid-drive://auth/callback)

    func testAuthCallback_validToken_parsesCorrectly() {
        // Given
        let url = URL(string: "ssdid-drive://auth/callback?session_token=abc123-valid-token-xyz")!

        // When
        let action = DeepLinkParser.parse(url)

        // Then
        if case .authCallback(let token) = action {
            XCTAssertEqual(token, "abc123-valid-token-xyz")
        } else {
            XCTFail("Expected .authCallback, got \(String(describing: action))")
        }
    }

    func testAuthCallback_missingToken_returnsNil() {
        // Given
        let url = URL(string: "ssdid-drive://auth/callback")!

        // When
        let action = DeepLinkParser.parse(url)

        // Then
        XCTAssertNil(action, "Should return nil when session_token is missing")
    }

    func testAuthCallback_emptyToken_returnsNil() {
        // Given
        let url = URL(string: "ssdid-drive://auth/callback?session_token=")!

        // When
        let action = DeepLinkParser.parse(url)

        // Then
        XCTAssertNil(action, "Should return nil when session_token is empty")
    }

    func testAuthCallback_wrongPath_returnsNil() {
        // Given — extra path segment after "callback"
        let url = URL(string: "ssdid-drive://auth/callback/extra?session_token=valid-token")!

        // When
        let action = DeepLinkParser.parse(url)

        // Then
        XCTAssertNil(action, "Should reject auth callback with extra path segments")
    }

    func testAuthCallback_wrongHost_returnsNil() {
        // Given — not "auth" host
        let url = URL(string: "ssdid-drive://login/callback?session_token=valid-token")!

        // When
        let action = DeepLinkParser.parse(url)

        // Then
        XCTAssertNil(action, "Should reject non-auth host")
    }

    // MARK: - Session Token Validation Tests

    func testSessionToken_valid_uuid() {
        XCTAssertTrue(LoginViewModel.isValidSessionToken("550e8400-e29b-41d4-a716-446655440000"))
    }

    func testSessionToken_valid_alphanumericWithDots() {
        XCTAssertTrue(LoginViewModel.isValidSessionToken("eyJhbGciOiJSUzI1NiJ9.payload.signature"))
    }

    func testSessionToken_tooShort_rejected() {
        XCTAssertFalse(LoginViewModel.isValidSessionToken("abc"))
    }

    func testSessionToken_empty_rejected() {
        XCTAssertFalse(LoginViewModel.isValidSessionToken(""))
    }

    func testSessionToken_tooLong_rejected() {
        let longToken = String(repeating: "a", count: 513)
        XCTAssertFalse(LoginViewModel.isValidSessionToken(longToken))
    }

    func testSessionToken_specialChars_rejected() {
        XCTAssertFalse(LoginViewModel.isValidSessionToken("token<script>alert(1)</script>"))
    }

    func testSessionToken_spaces_rejected() {
        XCTAssertFalse(LoginViewModel.isValidSessionToken("token with spaces here"))
    }

    func testSessionToken_maxLength_accepted() {
        let token = String(repeating: "a", count: 512)
        XCTAssertTrue(LoginViewModel.isValidSessionToken(token))
    }

    func testSessionToken_minLength_accepted() {
        let token = String(repeating: "a", count: 16)
        XCTAssertTrue(LoginViewModel.isValidSessionToken(token))
    }

    // MARK: - QR Payload Format Tests

    func testQrPayload_ssdidScheme() {
        // Verify the expected format: ssdid://login?server_url=...&callback_url=ssdid-drive://auth/callback
        let payload = "ssdid://login?server_url=https://drive.ssdid.my&service_name=ssdid-drive&challenge_id=abc123&callback_url=ssdid-drive://auth/callback"
        guard let url = URL(string: payload) else {
            XCTFail("QR payload should be a valid URL")
            return
        }

        XCTAssertEqual(url.scheme, "ssdid")
        XCTAssertEqual(url.host, "login")

        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        let queryItems = components?.queryItems ?? []

        XCTAssertEqual(queryItems.first(where: { $0.name == "server_url" })?.value, "https://drive.ssdid.my")
        XCTAssertEqual(queryItems.first(where: { $0.name == "service_name" })?.value, "ssdid-drive")
        XCTAssertEqual(queryItems.first(where: { $0.name == "challenge_id" })?.value, "abc123")
        XCTAssertEqual(queryItems.first(where: { $0.name == "callback_url" })?.value, "ssdid-drive://auth/callback")
    }
}

// MARK: - Deep Link Type

enum DeepLinkType: Equatable {
    case invite
    case share
    case file
    case folder
    case unknown
}
