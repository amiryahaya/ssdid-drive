# Android Invitation System - Comprehensive Unit Test Plan

## Overview

This document outlines a comprehensive unit test plan for the SSDID Drive Android app's invitation system. The plan covers UI, data validation, and edge cases across all layers of the architecture.

## System Architecture

### Two Invitation Flows

1. **Token Invitation Flow** (for new users)
   - User receives invitation link via email/message
   - Deep link opens `InviteAcceptScreen`
   - User provides display name and password
   - Account created and invitation accepted in one operation

2. **Pending Invitation Flow** (for existing authenticated users)
   - Authenticated users receive invitations to join additional tenants
   - User views pending invitations in `InvitationsScreen`
   - Can accept or decline invitations
   - Upon acceptance, user is added to the new tenant

---

## Test Suites

### Suite 1: Domain Model Tests

**File:** `InvitationTest.kt`

#### 1.1 TokenInvitation Tests

| Test Case | Description | Expected Result |
|-----------|-------------|-----------------|
| `testTokenInvitationValidWithAllFields` | Create TokenInvitation with all fields populated | All fields accessible and correct |
| `testTokenInvitationValidWithNullOptionalFields` | inviterName and message are null | Object created successfully |
| `testTokenInvitationIsExpired` | Check expiresAt in the past | `isExpired()` returns true |
| `testTokenInvitationIsNotExpired` | Check expiresAt in the future | `isExpired()` returns false |
| `testTokenInvitationInvalidWithError` | valid=false with errorReason | Error reason accessible |

#### 1.2 TokenInvitationError Tests

| Test Case | Description | Expected Result |
|-----------|-------------|-----------------|
| `testTokenInvitationErrorFromStringExpired` | Parse "expired" | Returns `EXPIRED` |
| `testTokenInvitationErrorFromStringRevoked` | Parse "revoked" | Returns `REVOKED` |
| `testTokenInvitationErrorFromStringAlreadyUsed` | Parse "already_used" | Returns `ALREADY_USED` |
| `testTokenInvitationErrorFromStringNotFound` | Parse "not_found" | Returns `NOT_FOUND` |
| `testTokenInvitationErrorFromStringCaseInsensitive` | Parse "EXPIRED" | Returns `EXPIRED` |
| `testTokenInvitationErrorFromStringInvalid` | Parse "unknown" | Returns null |
| `testTokenInvitationErrorFromStringNull` | Parse null | Returns null |

#### 1.3 Invitation Tests (Pending Invitations)

| Test Case | Description | Expected Result |
|-----------|-------------|-----------------|
| `testInvitationCreatedWithAllFields` | Create Invitation with all fields | All fields correct |
| `testInvitationWithNullInviter` | invitedBy is null | Object created, invitedBy null |
| `testInvitationWithNullInvitedAt` | invitedAt is null | Object created, invitedAt null |
| `testInvitationWithNullTenantSlug` | tenantSlug is null | Object created successfully |

#### 1.4 Inviter Tests

| Test Case | Description | Expected Result |
|-----------|-------------|-----------------|
| `testInviterDisplayTextReturnsDisplayName` | displayName is "John Doe" | Returns "John Doe" |
| `testInviterDisplayTextReturnsEmailWhenNoName` | displayName null, email present | Returns email |
| `testInviterDisplayTextReturnsUnknownWhenNoData` | Both null | Returns "Unknown" |
| `testInviterDisplayTextWithEmptyDisplayName` | displayName is empty string | Returns email or "Unknown" |

#### 1.5 MemberStatus Tests

| Test Case | Description | Expected Result |
|-----------|-------------|-----------------|
| `testMemberStatusFromStringActive` | Parse "active" | Returns `ACTIVE` |
| `testMemberStatusFromStringPending` | Parse "pending" | Returns `PENDING` |
| `testMemberStatusFromStringSuspended` | Parse "suspended" | Returns `SUSPENDED` |
| `testMemberStatusFromStringCaseInsensitive` | Parse "ACTIVE" | Returns `ACTIVE` |
| `testMemberStatusFromStringInvalidDefaultsToActive` | Parse "unknown" | Returns `ACTIVE` |

#### 1.6 InvitationAccepted Tests

| Test Case | Description | Expected Result |
|-----------|-------------|-----------------|
| `testInvitationAcceptedCreation` | Create with all fields | All fields correct |
| `testInvitationAcceptedWithNullJoinedAt` | joinedAt is null | Object created |

---

### Suite 2: DTO Tests

**File:** `InvitationDtoTest.kt`

#### 2.1 InviteInfoDto Tests

| Test Case | Description | Expected Result |
|-----------|-------------|-----------------|
| `testInviteInfoDtoDeserialization` | Parse valid JSON | All fields mapped correctly |
| `testInviteInfoDtoWithNullOptionals` | JSON missing inviterName, message | Nulls handled |
| `testInviteInfoDtoWithErrorReason` | JSON includes errorReason | Error reason parsed |
| `testInviteInfoDtoDateParsing` | expiresAt ISO8601 string | Parsed correctly |

#### 2.2 InvitationDto Tests

| Test Case | Description | Expected Result |
|-----------|-------------|-----------------|
| `testInvitationDtoDeserialization` | Parse valid JSON | All fields mapped |
| `testInvitationDtoWithNullInvitedBy` | invitedBy missing | Null handled |
| `testInvitationDtoInviterMapping` | InviterDto present | Nested object mapped |

#### 2.3 AcceptInviteRequest Tests

| Test Case | Description | Expected Result |
|-----------|-------------|-----------------|
| `testAcceptInviteRequestSerialization` | Serialize request | Correct JSON output |
| `testAcceptInviteRequestPublicKeysSerialization` | PublicKeysDto nested | Nested object serialized |
| `testAcceptInviteRequestPasswordNotInJson` | Password field | Password in plain text (secured in transit) |

#### 2.4 InvitationAcceptedDto Tests

| Test Case | Description | Expected Result |
|-----------|-------------|-----------------|
| `testInvitationAcceptedDtoDeserialization` | Parse valid JSON | All fields mapped |
| `testInvitationAcceptedDtoToDomain` | Map to domain model | Correct mapping |

---

### Suite 3: AuthRepository Tests

**File:** `AuthRepositoryImplInvitationTest.kt`

#### 3.1 getInvitationInfo() Tests

| Test Case | Description | Expected Result |
|-----------|-------------|-----------------|
| `testGetInvitationInfoSuccess` | API returns valid invitation | Result.Success with TokenInvitation |
| `testGetInvitationInfoMapsAllFields` | Verify field mapping | All fields transferred correctly |
| `testGetInvitationInfoWithErrorReason` | valid=false, errorReason present | Error reason in domain model |
| `testGetInvitationInfoNotFound` | API returns 404 | Result.Failure with NotFound |
| `testGetInvitationInfoExpired` | API returns 410 | Result.Failure with ValidationError |
| `testGetInvitationInfoServerError` | API returns 500 | Result.Failure with Unknown |
| `testGetInvitationInfoNetworkError` | Network exception | Result.Failure with Network |
| `testGetInvitationInfoNullBody` | Successful but null body | Result.Failure with Unknown |
| `testGetInvitationInfoSpecialCharacters` | Special chars in tenant name | Handled correctly |

#### 3.2 acceptInvitation() Tests - Validation

| Test Case | Description | Expected Result |
|-----------|-------------|-----------------|
| `testAcceptInvitationEmptyDisplayName` | displayName is blank | Result.Failure with ValidationError |
| `testAcceptInvitationDisplayNameTrimmed` | displayName with whitespace | Trimmed before validation |
| `testAcceptInvitationDisplayNameTooLong` | displayName > 100 chars | Result.Failure with ValidationError |
| `testAcceptInvitationDisplayNameExactly100Chars` | displayName = 100 chars | Success (within limit) |
| `testAcceptInvitationEmptyPassword` | password is empty CharArray | Result.Failure with ValidationError |
| `testAcceptInvitationShortPassword` | password < 8 chars | Result.Failure with ValidationError |
| `testAcceptInvitationPasswordExactly8Chars` | password = 8 chars | Success (minimum met) |
| `testAcceptInvitationDisplayNameWithUnicode` | Unicode characters | Accepted |
| `testAcceptInvitationDisplayNameWithEmoji` | Emoji in name | Accepted |

#### 3.3 acceptInvitation() Tests - Crypto Operations

| Test Case | Description | Expected Result |
|-----------|-------------|-----------------|
| `testAcceptInvitationGeneratesKeyBundle` | Key generation flow | keyManager.generateKeyBundle() called |
| `testAcceptInvitationDerivesMasterKey` | Key derivation | cryptoManager.deriveKey() called with password |
| `testAcceptInvitationEncryptsMasterKey` | Master key encryption | Encrypted with derived key |
| `testAcceptInvitationEncryptsPrivateKeys` | Private keys encryption | Encrypted with master key |
| `testAcceptInvitationKeyGenerationFailure` | Key gen throws exception | Result.Failure, passwords zeroized |
| `testAcceptInvitationKeyDerivationFailure` | Key derivation fails | Result.Failure, cleanup performed |
| `testAcceptInvitationEncryptionFailure` | Encryption fails | Result.Failure, cleanup performed |

#### 3.4 acceptInvitation() Tests - API Calls

| Test Case | Description | Expected Result |
|-----------|-------------|-----------------|
| `testAcceptInvitationSuccess` | API returns success | User saved, tokens stored, keys unlocked |
| `testAcceptInvitationBadRequest` | API returns 400 | Result.Failure with ValidationError |
| `testAcceptInvitationNotFound` | API returns 404 | Result.Failure with NotFound |
| `testAcceptInvitationAlreadyUsed` | API returns 409 | Result.Failure with ValidationError |
| `testAcceptInvitationExpired` | API returns 410 | Result.Failure with ValidationError |
| `testAcceptInvitationInvalidData` | API returns 422 | Result.Failure with ValidationError |
| `testAcceptInvitationNetworkError` | Network exception | Result.Failure with Network |

#### 3.5 acceptInvitation() Tests - Security

| Test Case | Description | Expected Result |
|-----------|-------------|-----------------|
| `testAcceptInvitationPasswordZeroized` | After success | Password CharArray zeroed |
| `testAcceptInvitationPasswordZeroizedOnFailure` | After failure | Password CharArray zeroed |
| `testAcceptInvitationMasterKeyZeroized` | After save | Master key bytes zeroed |
| `testAcceptInvitationDerivedKeyZeroized` | After encryption | Derived key bytes zeroed |
| `testAcceptInvitationPasswordNotInLogs` | Exception thrown | Password not in error message |

#### 3.6 acceptInvitation() Tests - Storage

| Test Case | Description | Expected Result |
|-----------|-------------|-----------------|
| `testAcceptInvitationSavesTokens` | After success | Tokens saved to SecureStorage |
| `testAcceptInvitationSavesUser` | After success | User info saved |
| `testAcceptInvitationSavesEncryptedKeys` | After success | Encrypted key material saved |
| `testAcceptInvitationSavesTenantContext` | After success | Tenant context saved |
| `testAcceptInvitationFetchesTenantConfig` | After success | fetchAndApplyTenantConfig called |
| `testAcceptInvitationStorageFailure` | Storage throws | Result.Failure, proper cleanup |

---

### Suite 4: TenantRepository Tests

**File:** `TenantRepositoryImplInvitationTest.kt`

#### 4.1 getPendingInvitations() Tests

| Test Case | Description | Expected Result |
|-----------|-------------|-----------------|
| `testGetPendingInvitationsSuccess` | API returns list | Result.Success with invitations |
| `testGetPendingInvitationsEmpty` | API returns empty list | Result.Success with empty list |
| `testGetPendingInvitationsMultiple` | API returns 5 invitations | All 5 mapped correctly |
| `testGetPendingInvitationsMapsInviter` | Inviter info present | Inviter object created |
| `testGetPendingInvitationsNullInviter` | invitedBy is null | Null handled, Invitation created |
| `testGetPendingInvitationsUnauthorized` | API returns 401 | Result.Failure with Unauthorized |
| `testGetPendingInvitationsServerError` | API returns 500 | Result.Failure with Unknown |
| `testGetPendingInvitationsNetworkError` | Network exception | Result.Failure with Network |

#### 4.2 acceptInvitation() Tests

| Test Case | Description | Expected Result |
|-----------|-------------|-----------------|
| `testAcceptInvitationSuccess` | API returns success | Result.Success with InvitationAccepted |
| `testAcceptInvitationRefreshesTenants` | After success | refreshTenants() called |
| `testAcceptInvitationUnauthorized` | API returns 401 | Result.Failure with Unauthorized |
| `testAcceptInvitationNotFound` | API returns 404 | Result.Failure with NotFound |
| `testAcceptInvitationAlreadyProcessed` | API returns 409 | Result.Failure with Conflict |
| `testAcceptInvitationServerError` | API returns 500 | Result.Failure with Unknown |
| `testAcceptInvitationNetworkError` | Network exception | Result.Failure with Network |

#### 4.3 declineInvitation() Tests

| Test Case | Description | Expected Result |
|-----------|-------------|-----------------|
| `testDeclineInvitationSuccess` | API returns success | Result.Success with Unit |
| `testDeclineInvitationUnauthorized` | API returns 401 | Result.Failure with Unauthorized |
| `testDeclineInvitationNotFound` | API returns 404 | Result.Failure with NotFound |
| `testDeclineInvitationAlreadyProcessed` | API returns 409 | Result.Failure with Conflict |
| `testDeclineInvitationNetworkError` | Network exception | Result.Failure with Network |

---

### Suite 5: InviteAcceptViewModel Tests

**File:** `InviteAcceptViewModelTest.kt`

#### 5.1 Initialization Tests

| Test Case | Description | Expected Result |
|-----------|-------------|-----------------|
| `testInitWithValidToken` | Token in SavedStateHandle | loadInvitationInfo called with token |
| `testInitWithEmptyToken` | Token is empty string | invitationError set, isLoadingInvitation false |
| `testInitWithoutToken` | No token in SavedStateHandle | invitationError set |
| `testInitialStateIsLoading` | Initial state | isLoadingInvitation = true |

#### 5.2 loadInvitationInfo Tests

| Test Case | Description | Expected Result |
|-----------|-------------|-----------------|
| `testLoadInvitationInfoSuccess` | Repository returns success | invitation set, isLoadingInvitation false |
| `testLoadInvitationInfoExpiredError` | errorReason = EXPIRED | invitationError = "This invitation has expired" |
| `testLoadInvitationInfoRevokedError` | errorReason = REVOKED | invitationError = "This invitation has been revoked" |
| `testLoadInvitationInfoAlreadyUsedError` | errorReason = ALREADY_USED | invitationError = "This invitation has already been used" |
| `testLoadInvitationInfoNotFoundError` | errorReason = NOT_FOUND | invitationError = "Invitation not found" |
| `testLoadInvitationInfoGenericError` | valid=false, no errorReason | invitationError = "This invitation is no longer valid" |
| `testLoadInvitationInfoNetworkError` | Repository returns error | invitationError set to exception message |
| `testRetryLoadInvitation` | Call retryLoadInvitation() | loadInvitationInfo called again |

#### 5.3 Form Input Tests

| Test Case | Description | Expected Result |
|-----------|-------------|-----------------|
| `testUpdateDisplayName` | Call with new name | displayName updated, registrationError cleared |
| `testUpdatePassword` | Call with new password | password updated, registrationError cleared |
| `testUpdateConfirmPassword` | Call with confirm | confirmPassword updated, registrationError cleared |
| `testUpdateDisplayNameClearsError` | Had error, update name | registrationError = null |

#### 5.4 Form Validation Tests

| Test Case | Description | Expected Result |
|-----------|-------------|-----------------|
| `testAcceptInvitationEmptyDisplayName` | displayName blank | registrationError set |
| `testAcceptInvitationDisplayNameTooLong` | displayName > 100 chars | registrationError set |
| `testAcceptInvitationEmptyPassword` | password blank | registrationError set |
| `testAcceptInvitationShortPassword` | password < 8 chars | registrationError set |
| `testAcceptInvitationPasswordMismatch` | password != confirmPassword | registrationError set |
| `testAcceptInvitationValidForm` | All valid | No error, repository called |

#### 5.5 Accept Flow Tests

| Test Case | Description | Expected Result |
|-----------|-------------|-----------------|
| `testAcceptInvitationStartsRegistration` | Call acceptInvitation | isRegistering = true |
| `testAcceptInvitationShowsKeyGeneration` | During processing | isGeneratingKeys = true |
| `testAcceptInvitationSuccess` | Repository returns success | isRegistered = true, passwords cleared |
| `testAcceptInvitationFailure` | Repository returns error | registrationError set, isRegistering = false |
| `testAcceptInvitationClearsPasswordsOnSuccess` | After success | password and confirmPassword empty |

#### 5.6 Cleanup Tests

| Test Case | Description | Expected Result |
|-----------|-------------|-----------------|
| `testOnClearedClearsPasswords` | ViewModel cleared | password and confirmPassword empty |

---

### Suite 6: InvitationsViewModel Tests

**File:** `InvitationsViewModelTest.kt`

#### 6.1 Initialization Tests

| Test Case | Description | Expected Result |
|-----------|-------------|-----------------|
| `testInitLoadsPendingInvitations` | On init | loadInvitations called |
| `testInitialStateIsLoading` | Initial state | isLoading = true |

#### 6.2 Load Invitations Tests

| Test Case | Description | Expected Result |
|-----------|-------------|-----------------|
| `testLoadInvitationsSuccess` | Repository returns list | invitations updated, isLoading = false |
| `testLoadInvitationsEmpty` | Repository returns empty | invitations empty, isLoading = false |
| `testLoadInvitationsError` | Repository returns error | error set, isLoading = false |

#### 6.3 Accept Invitation Tests

| Test Case | Description | Expected Result |
|-----------|-------------|-----------------|
| `testAcceptInvitationSetsProcessing` | Call acceptInvitation | isProcessing = true |
| `testAcceptInvitationSuccess` | Repository success | successMessage set, invitations reloaded |
| `testAcceptInvitationError` | Repository error | error set, isProcessing = false |
| `testAcceptInvitationReloadsAfterSuccess` | After success | loadInvitations called |

#### 6.4 Decline Invitation Tests

| Test Case | Description | Expected Result |
|-----------|-------------|-----------------|
| `testDeclineInvitationSetsProcessing` | Call declineInvitation | isProcessing = true |
| `testDeclineInvitationSuccess` | Repository success | successMessage = "Invitation declined" |
| `testDeclineInvitationError` | Repository error | error set |
| `testDeclineInvitationReloadsAfterSuccess` | After success | loadInvitations called |

#### 6.5 Message Clearing Tests

| Test Case | Description | Expected Result |
|-----------|-------------|-----------------|
| `testClearError` | Call clearError() | error = null |
| `testClearSuccessMessage` | Call clearSuccessMessage() | successMessage = null |

---

### Suite 7: Deep Link Handler Tests

**File:** `DeepLinkHandlerTest.kt`

#### 7.1 Custom Scheme Tests

| Test Case | Description | Expected Result |
|-----------|-------------|-----------------|
| `testParseCustomSchemeInvite` | `securesharing://invite/abc123` | AcceptInvitation("abc123") |
| `testParseCustomSchemeInviteWithDashes` | `securesharing://invite/abc-123-def` | AcceptInvitation("abc-123-def") |
| `testParseCustomSchemeInviteWithUnderscores` | `securesharing://invite/abc_123` | AcceptInvitation("abc_123") |
| `testParseCustomSchemeInviteUrlEncoded` | URL-encoded token | Token decoded correctly |

#### 7.2 HTTP Scheme Tests

| Test Case | Description | Expected Result |
|-----------|-------------|-----------------|
| `testParseHttpSchemeInvite` | `https://app.securesharing.example/invite/abc` | AcceptInvitation("abc") |
| `testParseHttpSchemeWithQueryParams` | URL with ?ref=email | Token extracted, params ignored |
| `testParseHttpSchemeWithPort` | URL with :8443 | Parsed correctly |
| `testParseHttpSchemeTrailingSlash` | URL ending with / | Token extracted |

#### 7.3 Error Cases

| Test Case | Description | Expected Result |
|-----------|-------------|-----------------|
| `testParseIntentNull` | null Intent | Returns null |
| `testParseIntentNullData` | Intent with null data | Returns null |
| `testParseUnsupportedScheme` | `ftp://...` | Returns null |
| `testParseMissingToken` | `/invite/` with no token | Returns null |
| `testParseEmptyToken` | `/invite/` empty path | Returns null |
| `testParseUnsupportedPath` | `/login/...` | Returns null |
| `testParseMalformedUri` | Invalid URI | Handled gracefully, returns null |

#### 7.4 Edge Cases

| Test Case | Description | Expected Result |
|-----------|-------------|-----------------|
| `testParseTokenWithSpecialChars` | Token with `%20`, `+` | Properly decoded |
| `testParseVeryLongToken` | 256+ character token | Handled correctly |
| `testParseTokenWithNumbers` | All numeric token | Parsed correctly |

---

### Suite 8: UI/Compose Tests

**File:** `InviteAcceptScreenTest.kt`

#### 8.1 Loading State Tests

| Test Case | Description | Expected Result |
|-----------|-------------|-----------------|
| `testShowsLoadingIndicator` | isLoadingInvitation = true | CircularProgressIndicator visible |
| `testHidesContentWhileLoading` | isLoadingInvitation = true | Form not visible |

#### 8.2 Error State Tests

| Test Case | Description | Expected Result |
|-----------|-------------|-----------------|
| `testShowsInvitationError` | invitationError set | Error card visible |
| `testErrorCardShowsRetryButton` | Error displayed | Retry button present |
| `testRetryButtonCallsRetry` | Click retry | ViewModel.retryLoadInvitation called |

#### 8.3 Valid Invitation Tests

| Test Case | Description | Expected Result |
|-----------|-------------|-----------------|
| `testShowsInvitationInfo` | Valid invitation | Organization name visible |
| `testShowsInviterName` | inviterName present | Inviter name displayed |
| `testShowsInvitationMessage` | message present | Message displayed |
| `testShowsInvitedEmail` | email present | Email displayed |

#### 8.4 Form Tests

| Test Case | Description | Expected Result |
|-----------|-------------|-----------------|
| `testDisplayNameFieldVisible` | Valid invitation | TextField visible |
| `testPasswordFieldVisible` | Valid invitation | Password field visible |
| `testConfirmPasswordFieldVisible` | Valid invitation | Confirm password visible |
| `testDisplayNameInputUpdatesState` | Type in field | ViewModel.updateDisplayName called |
| `testPasswordInputUpdatesState` | Type in field | ViewModel.updatePassword called |
| `testShowsRegistrationError` | registrationError set | Error message visible |
| `testCreateAccountButtonEnabled` | Form valid | Button enabled |
| `testCreateAccountButtonDisabled` | Form invalid | Button disabled |

#### 8.5 Registration State Tests

| Test Case | Description | Expected Result |
|-----------|-------------|-----------------|
| `testShowsProgressDuringRegistration` | isRegistering = true | Progress indicator visible |
| `testShowsKeyGenMessage` | isGeneratingKeys = true | Key generation message visible |
| `testFormDisabledDuringRegistration` | isRegistering = true | Input fields disabled |

---

**File:** `InvitationsScreenTest.kt`

#### 8.6 List Tests

| Test Case | Description | Expected Result |
|-----------|-------------|-----------------|
| `testShowsLoadingIndicator` | isLoading = true | Progress indicator visible |
| `testShowsInvitationsList` | invitations not empty | List items visible |
| `testShowsEmptyState` | invitations empty | Empty message visible |
| `testInvitationCardShowsTenantName` | Invitation present | Tenant name displayed |
| `testInvitationCardShowsInviterInfo` | Invitation present | Inviter info displayed |

#### 8.7 Action Tests

| Test Case | Description | Expected Result |
|-----------|-------------|-----------------|
| `testAcceptButtonCallsAccept` | Click accept | ViewModel.acceptInvitation called |
| `testDeclineButtonShowsDialog` | Click decline | Confirmation dialog visible |
| `testConfirmDeclineCallsDecline` | Confirm in dialog | ViewModel.declineInvitation called |
| `testCancelDeclineClosesDialog` | Cancel in dialog | Dialog dismissed |

#### 8.8 Feedback Tests

| Test Case | Description | Expected Result |
|-----------|-------------|-----------------|
| `testShowsErrorSnackbar` | error set | Snackbar visible with error |
| `testShowsSuccessSnackbar` | successMessage set | Snackbar visible with success |
| `testButtonsDisabledWhileProcessing` | isProcessing = true | Accept/Decline disabled |

---

### Suite 9: Integration Tests

**File:** `InvitationIntegrationTest.kt`

#### 9.1 Token Invitation Flow

| Test Case | Description | Expected Result |
|-----------|-------------|-----------------|
| `testFullTokenInvitationFlow` | Complete new user flow | User registered, logged in, keys unlocked |
| `testTokenFlowWithExpiredInvitation` | Expired invitation | Error shown, cannot proceed |
| `testTokenFlowWithNetworkErrorAndRetry` | Network error, then success | Retry works, flow completes |
| `testTokenFlowNavigationFromDeepLink` | Deep link received | Navigates to InviteAcceptScreen |

#### 9.2 Pending Invitation Flow

| Test Case | Description | Expected Result |
|-----------|-------------|-----------------|
| `testFullPendingInvitationAcceptFlow` | Accept pending invitation | Tenant added, list refreshed |
| `testPendingInvitationDeclineFlow` | Decline invitation | Invitation removed from list |
| `testMultiplePendingInvitations` | Accept one of several | Correct one processed |

#### 9.3 Multi-Tenant Flow

| Test Case | Description | Expected Result |
|-----------|-------------|-----------------|
| `testSwitchToNewTenantAfterAcceptance` | Accept invitation | Can switch to new tenant |

---

## Edge Cases

### Data Validation Edge Cases

| Category | Test Cases |
|----------|------------|
| **String lengths** | Empty, 1 char, max length, max+1, very long (1000+) |
| **Unicode** | Emojis, RTL text, special characters, zero-width chars |
| **Whitespace** | Leading, trailing, only whitespace, tabs, newlines |
| **Passwords** | Min length, all numbers, all symbols, spaces |

### Network Edge Cases

| Category | Test Cases |
|----------|------------|
| **Timeouts** | Connection timeout, read timeout during key gen |
| **Rate limiting** | 429 response handling |
| **Intermittent** | Fail once then succeed on retry |
| **Large payloads** | Very long invitation messages |

### Crypto Edge Cases

| Category | Test Cases |
|----------|------------|
| **Key generation** | Failure, partial generation |
| **Encryption** | Corrupted output, wrong key size |
| **Memory** | Zeroization verification |

### Concurrency Edge Cases

| Category | Test Cases |
|----------|------------|
| **Rapid actions** | Double-tap accept button |
| **Race conditions** | Accept while list refreshing |
| **Lifecycle** | Config change during registration |

---

## Security Test Cases

### Password Security

| Test Case | Description |
|-----------|-------------|
| `testPasswordNotStoredAsString` | Password uses CharArray, not String |
| `testPasswordZeroizedAfterUse` | CharArray.fill(0) called |
| `testPasswordNotInExceptionMessages` | Exceptions don't contain password |
| `testPasswordNotInLogcat` | No password in debug logs |
| `testPasswordFieldMasked` | UI shows dots, not text |

### Token Security

| Test Case | Description |
|-----------|-------------|
| `testTokenNotInSharedPreferences` | Token not in plain storage |
| `testRefreshTokenSecurelyStored` | Uses encrypted storage |
| `testTokenNotInUrlQueryParams` | Token in path, not query |

### Key Material Security

| Test Case | Description |
|-----------|-------------|
| `testMasterKeyEncrypted` | Master key encrypted before storage |
| `testPrivateKeysEncrypted` | Private keys encrypted |
| `testKeyMaterialZeroized` | Keys zeroized after use |

---

## Mock Dependencies

### Required Mocks

```kotlin
// Repository layer
val apiService: ApiService = mockk()
val secureStorage: SecureStorage = mockk()

// Crypto layer
val cryptoManager: CryptoManager = mockk()
val keyManager: KeyManager = mockk()
val cryptoConfig: CryptoConfig = mockk()

// Other
val deviceManager: DeviceManager = mockk()
val cacheManager: CacheManager = mockk()
val pushNotificationManager: PushNotificationManager = mockk()
val gson: Gson = Gson()

// ViewModel
val savedStateHandle: SavedStateHandle = SavedStateHandle(mapOf("token" to "test-token"))
```

### Mock Responses

```kotlin
// Valid invitation response
val validInviteInfoDto = InviteInfoDto(
    id = "inv-123",
    email = "user@example.com",
    role = "member",
    tenantName = "Test Organization",
    inviterName = "John Doe",
    message = "Welcome to our team!",
    expiresAt = "2025-12-31T23:59:59Z",
    valid = true,
    errorReason = null
)

// Expired invitation
val expiredInviteInfoDto = validInviteInfoDto.copy(
    valid = false,
    errorReason = "expired"
)

// Pending invitation list
val pendingInvitations = listOf(
    InvitationDto(
        id = "inv-1",
        tenantId = "tenant-1",
        tenantName = "Org One",
        tenantSlug = "org-one",
        role = "member",
        invitedBy = InviterDto("user-1", "inviter@example.com", "Jane Smith"),
        invitedAt = "2025-01-15T10:00:00Z"
    )
)
```

---

## Test File Structure

```
android/app/src/test/java/my/ssdid/drive/
├── domain/model/
│   └── InvitationTest.kt
├── data/
│   ├── remote/dto/
│   │   └── InvitationDtoTest.kt
│   └── repository/
│       ├── AuthRepositoryImplInvitationTest.kt
│       └── TenantRepositoryImplInvitationTest.kt
├── presentation/
│   ├── auth/
│   │   └── InviteAcceptViewModelTest.kt
│   └── settings/
│       └── InvitationsViewModelTest.kt
├── util/
│   └── DeepLinkHandlerTest.kt
└── invitation/
    ├── InvitationSystemTestPlan.md
    ├── fixtures/
    │   └── InvitationTestFixtures.kt
    └── mocks/
        ├── MockApiService.kt
        └── MockSecureStorage.kt

android/app/src/androidTest/java/my/ssdid/drive/
├── presentation/auth/
│   └── InviteAcceptScreenTest.kt
├── presentation/settings/
│   └── InvitationsScreenTest.kt
└── integration/
    └── InvitationIntegrationTest.kt
```

---

## Coverage Goals

| Layer | Target Coverage |
|-------|-----------------|
| Domain Models | 100% |
| DTOs | 100% |
| Repositories | 95% |
| ViewModels | 90% |
| UI/Compose | 80% |
| **Overall** | **85%+** |

---

## Test Execution

### Unit Tests (JVM)
```bash
./gradlew testDebugUnitTest --tests "my.ssdid.drive.domain.model.InvitationTest"
./gradlew testDebugUnitTest --tests "my.ssdid.drive.data.repository.*InvitationTest"
./gradlew testDebugUnitTest --tests "my.ssdid.drive.presentation.*InvitationTest"
```

### Instrumented Tests (Device/Emulator)
```bash
./gradlew connectedDebugAndroidTest --tests "my.ssdid.drive.presentation.auth.InviteAcceptScreenTest"
./gradlew connectedDebugAndroidTest --tests "my.ssdid.drive.integration.*"
```

### Coverage Report
```bash
./gradlew jacocoTestReport
# Report at: build/reports/jacoco/test/html/index.html
```

---

## Summary

This test plan covers **200+ test cases** across:
- **9 test suites**
- **Domain models** (TokenInvitation, Invitation, Inviter, etc.)
- **DTOs** (serialization/deserialization)
- **Repositories** (AuthRepository, TenantRepository)
- **ViewModels** (InviteAcceptViewModel, InvitationsViewModel)
- **Deep links** (custom scheme and HTTP)
- **UI/Compose** (screens and interactions)
- **Integration** (end-to-end flows)
- **Security** (password handling, key material)
- **Edge cases** (validation, network, crypto)
