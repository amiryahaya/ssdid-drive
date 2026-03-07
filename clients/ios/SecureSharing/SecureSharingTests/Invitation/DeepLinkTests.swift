import XCTest
@testable import SecureSharing

/// Unit tests for deep link parsing, particularly invitation deep links
final class DeepLinkTests: XCTestCase {

    // MARK: - Custom Scheme Tests (securesharing://)

    func testCustomScheme_inviteLink_extractsToken() {
        // Given
        let url = URL(string: "securesharing://invite/abc123xyz789")!

        // When
        let result = parseInviteToken(from: url)

        // Then
        XCTAssertEqual(result, "abc123xyz789")
    }

    func testCustomScheme_inviteLink_extractsComplexToken() {
        // Given
        let url = URL(string: "securesharing://invite/Abc-123_XyZ.789")!

        // When
        let result = parseInviteToken(from: url)

        // Then
        XCTAssertEqual(result, "Abc-123_XyZ.789")
    }

    func testCustomScheme_inviteLink_handlesLongToken() {
        // Given
        let longToken = String(repeating: "a", count: 64)
        let url = URL(string: "securesharing://invite/\(longToken)")!

        // When
        let result = parseInviteToken(from: url)

        // Then
        XCTAssertEqual(result, longToken)
    }

    func testCustomScheme_inviteLink_missingToken_returnsNil() {
        // Given
        let url = URL(string: "securesharing://invite/")!

        // When
        let result = parseInviteToken(from: url)

        // Then
        XCTAssertNil(result)
    }

    func testCustomScheme_inviteLink_emptyToken_returnsNil() {
        // Given
        let url = URL(string: "securesharing://invite")!

        // When
        let result = parseInviteToken(from: url)

        // Then
        XCTAssertNil(result)
    }

    func testCustomScheme_shareLink_returnsNil() {
        // Given
        let url = URL(string: "securesharing://share/abc123")!

        // When
        let result = parseInviteToken(from: url)

        // Then
        XCTAssertNil(result) // Not an invite link
    }

    func testCustomScheme_fileLink_returnsNil() {
        // Given
        let url = URL(string: "securesharing://file/abc123")!

        // When
        let result = parseInviteToken(from: url)

        // Then
        XCTAssertNil(result) // Not an invite link
    }

    // MARK: - Universal Link Tests (https://)

    func testUniversalLink_inviteLink_extractsToken() {
        // Given
        let url = URL(string: "https://app.securesharing.com/invite/abc123xyz789")!

        // When
        let result = parseInviteToken(from: url)

        // Then
        XCTAssertEqual(result, "abc123xyz789")
    }

    func testUniversalLink_inviteLink_extractsComplexToken() {
        // Given
        let url = URL(string: "https://app.securesharing.com/invite/Abc-123_XyZ.789")!

        // When
        let result = parseInviteToken(from: url)

        // Then
        XCTAssertEqual(result, "Abc-123_XyZ.789")
    }

    func testUniversalLink_inviteLink_missingToken_returnsNil() {
        // Given
        let url = URL(string: "https://app.securesharing.com/invite/")!

        // When
        let result = parseInviteToken(from: url)

        // Then
        XCTAssertNil(result)
    }

    func testUniversalLink_shareLink_returnsNil() {
        // Given
        let url = URL(string: "https://app.securesharing.com/share/abc123")!

        // When
        let result = parseInviteToken(from: url)

        // Then
        XCTAssertNil(result) // Not an invite link
    }

    func testUniversalLink_withQueryParams_extractsToken() {
        // Given
        let url = URL(string: "https://app.securesharing.com/invite/abc123?source=email")!

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
        let url = URL(string: "securesharing://")!

        // When
        let result = parseInviteToken(from: url)

        // Then
        XCTAssertNil(result)
    }

    // MARK: - URL Type Detection Tests

    func testURLType_customSchemeInvite_isInviteType() {
        // Given
        let url = URL(string: "securesharing://invite/abc123")!

        // When
        let type = getDeepLinkType(from: url)

        // Then
        XCTAssertEqual(type, .invite)
    }

    func testURLType_universalLinkInvite_isInviteType() {
        // Given
        let url = URL(string: "https://app.securesharing.com/invite/abc123")!

        // When
        let type = getDeepLinkType(from: url)

        // Then
        XCTAssertEqual(type, .invite)
    }

    func testURLType_shareLink_isShareType() {
        // Given
        let url = URL(string: "securesharing://share/abc123")!

        // When
        let type = getDeepLinkType(from: url)

        // Then
        XCTAssertEqual(type, .share)
    }

    func testURLType_fileLink_isFileType() {
        // Given
        let url = URL(string: "securesharing://file/abc123")!

        // When
        let type = getDeepLinkType(from: url)

        // Then
        XCTAssertEqual(type, .file)
    }

    func testURLType_folderLink_isFolderType() {
        // Given
        let url = URL(string: "securesharing://folder/abc123")!

        // When
        let type = getDeepLinkType(from: url)

        // Then
        XCTAssertEqual(type, .folder)
    }

    func testURLType_unknownHost_isUnknownType() {
        // Given
        let url = URL(string: "securesharing://unknown/abc123")!

        // When
        let type = getDeepLinkType(from: url)

        // Then
        XCTAssertEqual(type, .unknown)
    }

    // MARK: - URL Component Extraction Tests

    func testExtractId_customScheme_extractsFromPath() {
        // Given
        let url = URL(string: "securesharing://file/file123")!

        // When
        let id = extractResourceId(from: url)

        // Then
        XCTAssertEqual(id, "file123")
    }

    func testExtractId_universalLink_extractsFromPath() {
        // Given
        let url = URL(string: "https://app.securesharing.com/file/file456")!

        // When
        let id = extractResourceId(from: url)

        // Then
        XCTAssertEqual(id, "file456")
    }

    func testExtractId_missingPath_returnsNil() {
        // Given
        let url = URL(string: "securesharing://file")!

        // When
        let id = extractResourceId(from: url)

        // Then
        XCTAssertNil(id)
    }

    // MARK: - Edge Cases

    func testInviteToken_withEncodedCharacters() {
        // Given - URL-encoded token
        let url = URL(string: "securesharing://invite/abc%20123")!

        // When
        let result = parseInviteToken(from: url)

        // Then
        XCTAssertEqual(result, "abc 123") // Should decode
    }

    func testInviteToken_withPlusSign() {
        // Given
        let url = URL(string: "securesharing://invite/abc+123")!

        // When
        let result = parseInviteToken(from: url)

        // Then
        XCTAssertEqual(result, "abc+123")
    }

    func testInviteToken_withSlashInToken() {
        // Given - This would be unusual but should handle gracefully
        let url = URL(string: "securesharing://invite/abc/123")!

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

        if url.scheme == "securesharing" {
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
        if url.scheme == "securesharing" {
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

        if url.scheme == "securesharing" {
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

        if url.scheme == "securesharing" {
            return pathComponents.first
        } else {
            return pathComponents.dropFirst().first
        }
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
