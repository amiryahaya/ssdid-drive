# iOS Invitation System - Comprehensive Unit Test Plan

## Overview

This test plan covers the invitation flow in the iOS SecureSharing app, including:
- **Model Layer**: `TokenInvitation`, `TokenInvitationError`, API request/response structs
- **View Layer**: `InviteAcceptViewController` (UIKit-based)
- **ViewModel Layer**: `InviteAcceptViewModel` with Combine
- **Repository Layer**: `AuthRepository` protocol and `AuthRepositoryImpl`
- **Navigation**: Deep link handling in coordinators

---

## 1. Model Tests (`InvitationTests.swift`)

### 1.1 TokenInvitation Model

| Test Case | Description | Expected Result |
|-----------|-------------|-----------------|
| `test_tokenInvitation_validInvitation_isValid` | Valid invitation with future expiry | `isValid` returns `true` |
| `test_tokenInvitation_expiredInvitation_isInvalid` | Invitation with `errorReason = .expired` | `isValid` returns `false` |
| `test_tokenInvitation_revokedInvitation_isInvalid` | Invitation with `errorReason = .revoked` | `isValid` returns `false` |
| `test_tokenInvitation_alreadyUsedInvitation_isInvalid` | Invitation with `errorReason = .alreadyUsed` | `isValid` returns `false` |
| `test_tokenInvitation_notFoundInvitation_isInvalid` | Invitation with `errorReason = .notFound` | `isValid` returns `false` |

### 1.2 TokenInvitationError Enum

| Test Case | Description | Expected Result |
|-----------|-------------|-----------------|
| `test_tokenInvitationError_fromString_expired` | Parse "expired" string | Returns `.expired` |
| `test_tokenInvitationError_fromString_revoked` | Parse "revoked" string | Returns `.revoked` |
| `test_tokenInvitationError_fromString_alreadyUsed` | Parse "already_used" string | Returns `.alreadyUsed` |
| `test_tokenInvitationError_fromString_notFound` | Parse "not_found" string | Returns `.notFound` |
| `test_tokenInvitationError_fromString_unknown` | Parse unknown string | Returns `.notFound` (default) |
| `test_tokenInvitationError_fromString_nil` | Parse nil value | Returns `nil` |

### 1.3 API Response Decoding

| Test Case | Description | Expected Result |
|-----------|-------------|-----------------|
| `test_invitationInfoResponse_decodesValidJSON` | Decode complete valid response | All fields populated correctly |
| `test_invitationInfoResponse_decodesWithNullMessage` | Response with null message | `message` is `nil` |
| `test_invitationInfoResponse_decodesInvalidInvitation` | Response with `valid: false` | `errorReason` is populated |
| `test_acceptInvitationResponse_decodesTokens` | Decode accept response | Access/refresh tokens present |

---

## 2. ViewModel Tests (`InviteAcceptViewModelTests.swift`)

### 2.1 State Management

| Test Case | Description | Expected Result |
|-----------|-------------|-----------------|
| `test_initialState_isLoading` | Initial state when created | `state` is `.loading` |
| `test_loadInvitation_success_updatesStateToLoaded` | Successful invitation load | `state` is `.loaded(invitation)` |
| `test_loadInvitation_notFound_updatesStateToError` | 404 response | `state` is `.error(.notFound)` |
| `test_loadInvitation_expired_updatesStateToInvalid` | Expired invitation | `state` is `.invalid(.expired)` |
| `test_loadInvitation_revoked_updatesStateToInvalid` | Revoked invitation | `state` is `.invalid(.revoked)` |
| `test_loadInvitation_alreadyUsed_updatesStateToInvalid` | Already used invitation | `state` is `.invalid(.alreadyUsed)` |
| `test_loadInvitation_networkError_updatesStateToError` | Network failure | `state` is `.error(.networkError)` |

### 2.2 Form Field Binding

| Test Case | Description | Expected Result |
|-----------|-------------|-----------------|
| `test_displayName_binding_updatesValue` | Set display name | `displayName` property updated |
| `test_password_binding_updatesValue` | Set password | `password` property updated |
| `test_confirmPassword_binding_updatesValue` | Set confirm password | `confirmPassword` property updated |

### 2.3 Password Validation

| Test Case | Description | Expected Result |
|-----------|-------------|-----------------|
| `test_passwordValidation_tooShort_showsError` | Password < 12 chars | `passwordError` is set |
| `test_passwordValidation_tooLong_showsError` | Password > 72 chars | `passwordError` is set |
| `test_passwordValidation_valid_noError` | Password 12-72 chars | `passwordError` is `nil` |
| `test_passwordValidation_mismatch_showsError` | password ≠ confirmPassword | `confirmPasswordError` is set |
| `test_passwordValidation_match_noError` | password == confirmPassword | `confirmPasswordError` is `nil` |
| `test_passwordValidation_emptyPassword_showsError` | Empty password string | `passwordError` is set |
| `test_passwordValidation_emptyConfirm_showsError` | Empty confirm password | `confirmPasswordError` is set |

### 2.4 Display Name Validation

| Test Case | Description | Expected Result |
|-----------|-------------|-----------------|
| `test_displayNameValidation_empty_showsError` | Empty display name | `displayNameError` is set |
| `test_displayNameValidation_tooLong_showsError` | Display name > 256 chars | `displayNameError` is set |
| `test_displayNameValidation_valid_noError` | Valid display name | `displayNameError` is `nil` |
| `test_displayNameValidation_whitespaceOnly_showsError` | Only spaces | `displayNameError` is set |

### 2.5 Form Validity

| Test Case | Description | Expected Result |
|-----------|-------------|-----------------|
| `test_isFormValid_allFieldsValid_returnsTrue` | All fields valid | `isFormValid` is `true` |
| `test_isFormValid_passwordTooShort_returnsFalse` | Invalid password | `isFormValid` is `false` |
| `test_isFormValid_passwordMismatch_returnsFalse` | Mismatched passwords | `isFormValid` is `false` |
| `test_isFormValid_emptyDisplayName_returnsFalse` | No display name | `isFormValid` is `false` |
| `test_isFormValid_invalidState_returnsFalse` | Not in loaded state | `isFormValid` is `false` |

### 2.6 Accept Invitation

| Test Case | Description | Expected Result |
|-----------|-------------|-----------------|
| `test_acceptInvitation_success_triggersOnSuccess` | Successful accept | `onAcceptSuccess` called with tokens |
| `test_acceptInvitation_setsIsAccepting` | During accept | `isAccepting` is `true` |
| `test_acceptInvitation_clearsIsAcceptingOnComplete` | After accept | `isAccepting` is `false` |
| `test_acceptInvitation_networkError_showsAlert` | Network failure | Alert displayed |
| `test_acceptInvitation_409Conflict_showsAlreadyUsedError` | 409 response | Shows "already used" error |
| `test_acceptInvitation_410Gone_showsExpiredError` | 410 response | Shows expired/revoked error |
| `test_acceptInvitation_422Validation_showsValidationError` | 422 response | Shows validation errors |
| `test_acceptInvitation_invalidForm_doesNotSubmit` | Form invalid | No API call made |

---

## 3. Repository Tests (`AuthRepositoryTests.swift`)

### 3.1 Get Invitation Info

| Test Case | Description | Expected Result |
|-----------|-------------|-----------------|
| `test_getInvitationInfo_validToken_returnsInvitation` | Valid token lookup | Returns `TokenInvitation` |
| `test_getInvitationInfo_invalidToken_returnsErrorInvitation` | Invalid token | Returns invitation with `errorReason` |
| `test_getInvitationInfo_networkError_throwsError` | Network failure | Throws network error |
| `test_getInvitationInfo_malformedResponse_throwsDecodingError` | Invalid JSON | Throws decoding error |

### 3.2 Accept Invitation - Key Generation

| Test Case | Description | Expected Result |
|-----------|-------------|-----------------|
| `test_acceptInvitation_generatesKazKemKeyPair` | Key generation | KAZ-KEM keys generated (236B pub, 86B priv) |
| `test_acceptInvitation_generatesKazSignKeyPair` | Key generation | KAZ-SIGN keys generated (2144B pub, 4512B priv) |
| `test_acceptInvitation_generatesMlKemKeyPair` | Key generation | ML-KEM-768 keys generated (1184B pub, 2400B priv) |
| `test_acceptInvitation_generatesMlDsaKeyPair` | Key generation | ML-DSA-65 keys generated (1952B pub, 4032B priv) |
| `test_acceptInvitation_generatesMasterKey` | Key generation | 32-byte master key generated |

### 3.3 Accept Invitation - Key Derivation

| Test Case | Description | Expected Result |
|-----------|-------------|-----------------|
| `test_acceptInvitation_derivesKeyFromPassword` | PBKDF2 derivation | Derives 32-byte key |
| `test_acceptInvitation_usesPBKDF2HmacSHA256` | Algorithm check | Uses correct algorithm |
| `test_acceptInvitation_uses100000Iterations` | Iteration count | Uses 100,000 iterations |
| `test_acceptInvitation_generates32ByteSalt` | Salt generation | Generates 32-byte random salt |

### 3.4 Accept Invitation - Encryption

| Test Case | Description | Expected Result |
|-----------|-------------|-----------------|
| `test_acceptInvitation_encryptsMasterKeyWithAESGCM` | MK encryption | Encrypts with AES-256-GCM |
| `test_acceptInvitation_encryptsPrivateKeysWithAESGCM` | PK encryption | Encrypts with AES-256-GCM |
| `test_acceptInvitation_generatesUniqueNonces` | Nonce generation | Each encryption uses unique nonce |

### 3.5 Accept Invitation - API Request

| Test Case | Description | Expected Result |
|-----------|-------------|-----------------|
| `test_acceptInvitation_sendsCorrectPayload` | Request body | Contains all required fields |
| `test_acceptInvitation_base64EncodesKeys` | Key encoding | All binary data Base64 encoded |
| `test_acceptInvitation_success_returnsTokens` | 201 response | Returns access/refresh tokens |
| `test_acceptInvitation_409_throwsConflictError` | 409 response | Throws already used error |
| `test_acceptInvitation_410_throwsGoneError` | 410 response | Throws expired/revoked error |
| `test_acceptInvitation_422_throwsValidationError` | 422 response | Throws validation error with details |

---

## 4. View Controller Tests (`InviteAcceptViewControllerTests.swift`)

### 4.1 UI State Rendering

| Test Case | Description | Expected Result |
|-----------|-------------|-----------------|
| `test_loadingState_showsLoadingIndicator` | Loading state | Activity indicator visible |
| `test_loadingState_hidesFormFields` | Loading state | Form fields hidden |
| `test_loadedState_showsInvitationInfo` | Loaded state | Shows tenant name, inviter, message |
| `test_loadedState_showsFormFields` | Loaded state | Form fields visible |
| `test_errorState_showsErrorMessage` | Error state | Error message displayed |
| `test_errorState_showsRetryButton` | Error state | Retry button visible |
| `test_invalidState_showsInvalidMessage` | Invalid state | Shows appropriate invalid message |
| `test_invalidState_hidesFormFields` | Invalid state | Form hidden |

### 4.2 Form UI Elements

| Test Case | Description | Expected Result |
|-----------|-------------|-----------------|
| `test_displayNameField_hasCorrectPlaceholder` | Field config | Shows "Display Name" placeholder |
| `test_passwordField_isSecureEntry` | Field config | Password is masked |
| `test_confirmPasswordField_isSecureEntry` | Field config | Confirm password is masked |
| `test_submitButton_disabledWhenFormInvalid` | Button state | Disabled when invalid |
| `test_submitButton_enabledWhenFormValid` | Button state | Enabled when valid |
| `test_submitButton_showsLoadingDuringAccept` | Button state | Shows spinner during submission |

### 4.3 Error Display

| Test Case | Description | Expected Result |
|-----------|-------------|-----------------|
| `test_passwordError_showsErrorLabel` | Validation error | Error label visible under field |
| `test_confirmPasswordError_showsErrorLabel` | Validation error | Error label visible under field |
| `test_displayNameError_showsErrorLabel` | Validation error | Error label visible under field |
| `test_clearingError_hidesErrorLabel` | Error cleared | Error label hidden |

### 4.4 Keyboard Handling

| Test Case | Description | Expected Result |
|-----------|-------------|-----------------|
| `test_keyboardAppears_scrollsToActiveField` | Keyboard up | Scroll view adjusts |
| `test_keyboardDismisses_resetsScrollPosition` | Keyboard down | Scroll view resets |
| `test_returnKey_movesToNextField` | Tab navigation | Focus moves correctly |
| `test_returnOnLastField_dismissesKeyboard` | Done key | Keyboard dismissed |

### 4.5 Accessibility

| Test Case | Description | Expected Result |
|-----------|-------------|-----------------|
| `test_formFields_haveAccessibilityLabels` | A11y labels | All fields labeled |
| `test_errorLabels_announcedToVoiceOver` | A11y announce | Errors announced |
| `test_loadingState_announcedToVoiceOver` | A11y announce | Loading state announced |

---

## 5. Deep Link Tests (`DeepLinkTests.swift`)

### 5.1 URL Parsing

| Test Case | Description | Expected Result |
|-----------|-------------|-----------------|
| `test_customScheme_parsesInviteToken` | `securesharing://invite/{token}` | Extracts token correctly |
| `test_universalLink_parsesInviteToken` | `https://app.securesharing.com/invite/{token}` | Extracts token correctly |
| `test_malformedURL_returnsNil` | Invalid URL format | Returns nil/fails gracefully |
| `test_missingToken_returnsNil` | URL without token | Returns nil |
| `test_emptyToken_returnsNil` | Empty token string | Returns nil |

### 5.2 Navigation Handling

| Test Case | Description | Expected Result |
|-----------|-------------|-----------------|
| `test_inviteDeepLink_navigatesToInviteAccept` | Valid invite link | Shows InviteAcceptViewController |
| `test_inviteDeepLink_whileLoggedIn_promptsLogout` | User authenticated | Shows logout confirmation |
| `test_inviteDeepLink_passesTokenToViewModel` | Navigation | ViewModel receives token |

---

## 6. Edge Cases & Error Scenarios

### 6.1 Network Edge Cases

| Test Case | Description | Expected Result |
|-----------|-------------|-----------------|
| `test_networkTimeout_showsTimeoutError` | Request times out | Shows timeout message |
| `test_noInternetConnection_showsOfflineError` | No connectivity | Shows offline message |
| `test_serverError500_showsGenericError` | 500 response | Shows generic server error |
| `test_malformedJSON_handlesGracefully` | Invalid response | Shows parsing error |

### 6.2 Cryptographic Edge Cases

| Test Case | Description | Expected Result |
|-----------|-------------|-----------------|
| `test_keyGeneration_failure_showsError` | Key gen fails | Shows crypto error |
| `test_encryption_failure_showsError` | Encryption fails | Shows crypto error |
| `test_randomGeneration_failure_showsError` | RNG fails | Shows crypto error |

### 6.3 Concurrency Edge Cases

| Test Case | Description | Expected Result |
|-----------|-------------|-----------------|
| `test_doubleSubmit_preventsSecondRequest` | Rapid double tap | Only one request sent |
| `test_navigationDuringLoad_cancelsRequest` | Back during load | Request cancelled |
| `test_viewDeallocDuringRequest_noRetain` | VC dealloc | No retain cycle/crash |

### 6.4 Input Edge Cases

| Test Case | Description | Expected Result |
|-----------|-------------|-----------------|
| `test_unicodeDisplayName_accepted` | Unicode chars | Accepted and encoded correctly |
| `test_emojiInDisplayName_accepted` | Emoji chars | Accepted and encoded correctly |
| `test_passwordWithSpecialChars_accepted` | Special chars | Accepted and handled |
| `test_passwordWithUnicode_accepted` | Unicode password | Accepted and handled |
| `test_extremelyLongInput_truncatedOrRejected` | Very long strings | Handled gracefully |
| `test_sqlInjectionAttempt_escaped` | Malicious input | Properly escaped/rejected |
| `test_htmlInjectionAttempt_escaped` | XSS attempt | Properly escaped |

### 6.5 State Transition Edge Cases

| Test Case | Description | Expected Result |
|-----------|-------------|-----------------|
| `test_invitationExpiresWhileFillingForm` | Expiry during form | Shows expired on submit |
| `test_invitationRevokedWhileFillingForm` | Revoked during form | Shows revoked on submit |
| `test_invitationAcceptedByOtherDevice` | Race condition | Shows already used |
| `test_appBackgroundedDuringSubmit` | App backgrounds | Completes in background |
| `test_appKilledDuringSubmit_noPartialState` | Force kill | No partial registration |

---

## 7. Integration Tests

### 7.1 End-to-End Flow

| Test Case | Description | Expected Result |
|-----------|-------------|-----------------|
| `test_fullAcceptFlow_fromDeepLink` | Complete flow | User registered, logged in |
| `test_fullAcceptFlow_navigatesToHome` | After accept | Shows home screen |
| `test_fullAcceptFlow_savesKeysToKeychain` | Key storage | Keys persisted securely |
| `test_fullAcceptFlow_savesTokensToKeychain` | Token storage | Tokens persisted |

---

## 8. Mock/Stub Requirements

### 8.1 Repository Mocks

```swift
class MockAuthRepository: AuthRepository {
    var getInvitationInfoResult: Result<TokenInvitation, Error>?
    var acceptInvitationResult: Result<AuthTokens, Error>?

    var getInvitationInfoCallCount = 0
    var acceptInvitationCallCount = 0
    var lastAcceptParams: AcceptInvitationParams?

    func getInvitationInfo(token: String) async throws -> TokenInvitation {
        getInvitationInfoCallCount += 1
        switch getInvitationInfoResult {
        case .success(let invitation):
            return invitation
        case .failure(let error):
            throw error
        case .none:
            fatalError("getInvitationInfoResult not set")
        }
    }

    func acceptInvitation(token: String, params: AcceptInvitationParams) async throws -> AuthTokens {
        acceptInvitationCallCount += 1
        lastAcceptParams = params
        switch acceptInvitationResult {
        case .success(let tokens):
            return tokens
        case .failure(let error):
            throw error
        case .none:
            fatalError("acceptInvitationResult not set")
        }
    }
}
```

### 8.2 Crypto Mocks

```swift
class MockCryptoManager: CryptoManagerProtocol {
    var shouldFailKeyGeneration = false
    var shouldFailEncryption = false
    var generatedKeys: [String: Data] = [:]

    func generateKeyPair(algorithm: KeyAlgorithm) throws -> KeyPair {
        if shouldFailKeyGeneration {
            throw CryptoError.keyGenerationFailed
        }
        return KeyPair(
            publicKey: Data(repeating: 0x01, count: 32),
            privateKey: Data(repeating: 0x02, count: 64)
        )
    }

    func encrypt(data: Data, key: Data) throws -> EncryptedData {
        if shouldFailEncryption {
            throw CryptoError.encryptionFailed
        }
        return EncryptedData(
            ciphertext: Data(repeating: 0x03, count: data.count + 16),
            nonce: Data(repeating: 0x04, count: 12)
        )
    }
}
```

### 8.3 Keychain Mocks

```swift
class MockKeychainManager: KeychainManagerProtocol {
    var storage: [String: Data] = [:]
    var shouldFailOnSave = false
    var shouldFailOnLoad = false

    func save(key: String, data: Data) throws {
        if shouldFailOnSave {
            throw KeychainError.saveFailed
        }
        storage[key] = data
    }

    func load(key: String) throws -> Data? {
        if shouldFailOnLoad {
            throw KeychainError.loadFailed
        }
        return storage[key]
    }

    func delete(key: String) throws {
        storage.removeValue(forKey: key)
    }
}
```

### 8.4 API Client Mocks

```swift
class MockAPIClient: APIClientProtocol {
    var responses: [String: Result<Data, Error>] = [:]
    var requestHistory: [(endpoint: String, body: Data?)] = []

    func request<T: Decodable>(
        endpoint: String,
        method: HTTPMethod,
        body: Encodable?
    ) async throws -> T {
        let bodyData = try? JSONEncoder().encode(body)
        requestHistory.append((endpoint, bodyData))

        guard let result = responses[endpoint] else {
            fatalError("No mock response for \(endpoint)")
        }

        switch result {
        case .success(let data):
            return try JSONDecoder().decode(T.self, from: data)
        case .failure(let error):
            throw error
        }
    }
}
```

---

## 9. Test Data Fixtures

```swift
struct InvitationTestFixtures {

    // MARK: - Valid Invitations

    static let validInvitation = TokenInvitation(
        id: "inv_123456789",
        email: "newuser@example.com",
        role: "member",
        tenantName: "Test Company",
        inviterName: "Admin User",
        message: "Welcome to the team!",
        expiresAt: Date().addingTimeInterval(86400 * 7), // 7 days
        valid: true,
        errorReason: nil
    )

    static let validInvitationNoMessage = TokenInvitation(
        id: "inv_987654321",
        email: "another@example.com",
        role: "admin",
        tenantName: "Another Company",
        inviterName: "Owner",
        message: nil,
        expiresAt: Date().addingTimeInterval(86400 * 7),
        valid: true,
        errorReason: nil
    )

    // MARK: - Invalid Invitations

    static let expiredInvitation = TokenInvitation(
        id: "inv_expired123",
        email: "expired@example.com",
        role: "member",
        tenantName: "Test Company",
        inviterName: "Admin User",
        message: nil,
        expiresAt: Date().addingTimeInterval(-86400), // 1 day ago
        valid: false,
        errorReason: .expired
    )

    static let revokedInvitation = TokenInvitation(
        id: "inv_revoked456",
        email: "revoked@example.com",
        role: "member",
        tenantName: "Test Company",
        inviterName: "Admin User",
        message: nil,
        expiresAt: Date().addingTimeInterval(86400 * 7),
        valid: false,
        errorReason: .revoked
    )

    static let alreadyUsedInvitation = TokenInvitation(
        id: "inv_used789",
        email: "used@example.com",
        role: "member",
        tenantName: "Test Company",
        inviterName: "Admin User",
        message: nil,
        expiresAt: Date().addingTimeInterval(86400 * 7),
        valid: false,
        errorReason: .alreadyUsed
    )

    static let notFoundInvitation = TokenInvitation(
        id: nil,
        email: nil,
        role: nil,
        tenantName: nil,
        inviterName: nil,
        message: nil,
        expiresAt: nil,
        valid: false,
        errorReason: .notFound
    )

    // MARK: - Auth Tokens

    static let validAuthTokens = AuthTokens(
        accessToken: "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiIxMjM0NTY3ODkwIiwibmFtZSI6IlRlc3QgVXNlciIsImlhdCI6MTUxNjIzOTAyMn0.SflKxwRJSMeKKF2QT4fwpMeJf36POk6yJV_adQssw5c",
        refreshToken: "refresh_token_abc123",
        tokenType: "Bearer",
        expiresIn: 3600
    )

    // MARK: - Form Input

    static let validFormInput = (
        displayName: "John Doe",
        password: "SecurePass123!",
        confirmPassword: "SecurePass123!"
    )

    static let shortPassword = "short"
    static let longPassword = String(repeating: "a", count: 100)
    static let mismatchedPasswords = ("Password123!", "Password456!")
    static let emptyDisplayName = ""
    static let longDisplayName = String(repeating: "a", count: 300)

    // MARK: - API Responses (JSON)

    static let validInvitationJSON = """
    {
        "data": {
            "id": "inv_123456789",
            "email": "newuser@example.com",
            "role": "member",
            "tenant_name": "Test Company",
            "inviter_name": "Admin User",
            "message": "Welcome to the team!",
            "expires_at": "\(ISO8601DateFormatter().string(from: Date().addingTimeInterval(86400 * 7)))",
            "valid": true,
            "error_reason": null
        }
    }
    """.data(using: .utf8)!

    static let expiredInvitationJSON = """
    {
        "data": {
            "id": "inv_expired123",
            "email": "expired@example.com",
            "role": "member",
            "tenant_name": "Test Company",
            "inviter_name": "Admin User",
            "message": null,
            "expires_at": "\(ISO8601DateFormatter().string(from: Date().addingTimeInterval(-86400)))",
            "valid": false,
            "error_reason": "expired"
        }
    }
    """.data(using: .utf8)!

    static let acceptSuccessJSON = """
    {
        "data": {
            "user": {
                "id": "usr_123",
                "email": "newuser@example.com",
                "display_name": "John Doe",
                "tenant_id": "ten_456",
                "role": "member"
            },
            "access_token": "eyJhbGciOiJIUzI1NiIs...",
            "refresh_token": "refresh_abc123",
            "token_type": "Bearer",
            "expires_in": 3600
        }
    }
    """.data(using: .utf8)!

    // MARK: - Error Responses

    static let error409ConflictJSON = """
    {
        "error": {
            "code": "conflict",
            "message": "This invitation has already been used."
        }
    }
    """.data(using: .utf8)!

    static let error410GoneJSON = """
    {
        "error": {
            "code": "gone",
            "message": "This invitation has expired."
        }
    }
    """.data(using: .utf8)!

    static let error422ValidationJSON = """
    {
        "error": {
            "code": "validation_error",
            "message": "Validation failed",
            "details": {
                "password": ["must be at least 12 characters"]
            }
        }
    }
    """.data(using: .utf8)!
}
```

---

## 10. Test Execution Plan

### Priority Order

| Priority | Category | Test Count | Description |
|----------|----------|------------|-------------|
| **P0** | Critical Path | ~15 | Model decoding, password validation, accept flow success |
| **P1** | High | ~25 | Error states, form validation, key generation |
| **P2** | Medium | ~20 | UI states, keyboard handling, deep links |
| **P3** | Low | ~15 | Edge cases, accessibility, integration tests |

### Coverage Targets

| Layer | Target Coverage | Notes |
|-------|-----------------|-------|
| Model Layer | 100% | All structs, enums, and decoding |
| ViewModel Layer | 95% | State machine, validation, bindings |
| Repository Layer | 90% | API calls, crypto operations |
| View Controller | 80% | UI state rendering, user interactions |

### Test Environment Setup

```swift
class InvitationTestCase: XCTestCase {
    var mockAuthRepository: MockAuthRepository!
    var mockCryptoManager: MockCryptoManager!
    var mockKeychainManager: MockKeychainManager!
    var mockAPIClient: MockAPIClient!

    override func setUp() {
        super.setUp()
        mockAuthRepository = MockAuthRepository()
        mockCryptoManager = MockCryptoManager()
        mockKeychainManager = MockKeychainManager()
        mockAPIClient = MockAPIClient()
    }

    override func tearDown() {
        mockAuthRepository = nil
        mockCryptoManager = nil
        mockKeychainManager = nil
        mockAPIClient = nil
        super.tearDown()
    }
}
```

### CI/CD Integration

```yaml
# .github/workflows/ios-tests.yml
test-invitation-system:
  runs-on: macos-latest
  steps:
    - uses: actions/checkout@v4
    - name: Run Invitation Tests
      run: |
        xcodebuild test \
          -scheme SecureSharing \
          -destination 'platform=iOS Simulator,name=iPhone 15' \
          -only-testing:SecureSharingTests/InvitationTests \
          -only-testing:SecureSharingTests/InviteAcceptViewModelTests \
          -only-testing:SecureSharingTests/AuthRepositoryTests \
          -resultBundlePath TestResults.xcresult
    - name: Upload Coverage
      uses: codecov/codecov-action@v3
```

---

## 11. Test File Structure

```
SecureSharingTests/
├── InvitationSystemTestPlan.md          # This document
├── Invitation/
│   ├── InvitationTests.swift            # Model tests
│   ├── InviteAcceptViewModelTests.swift # ViewModel tests
│   ├── InviteAcceptViewControllerTests.swift # UI tests
│   └── DeepLinkTests.swift              # Navigation tests
├── Repository/
│   └── AuthRepositoryInvitationTests.swift # Repository tests
├── Mocks/
│   ├── MockAuthRepository.swift
│   ├── MockCryptoManager.swift
│   ├── MockKeychainManager.swift
│   └── MockAPIClient.swift
└── Fixtures/
    └── InvitationTestFixtures.swift
```

---

## 12. Definition of Done

A test is considered complete when:

1. **Written**: Test code is implemented following the test case specification
2. **Passing**: Test passes consistently (no flakiness)
3. **Reviewed**: Code reviewed by another team member
4. **Documented**: Test purpose is clear from name and/or comments
5. **Isolated**: Test does not depend on external state or other tests
6. **Fast**: Unit tests complete in < 100ms each
7. **Maintainable**: Uses shared fixtures and mocks appropriately
