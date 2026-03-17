# SSDID Drive — Client Test Cases

Comprehensive test case documentation across all clients: iOS, Android, Desktop (Tauri), and Admin Portal.

---

## Table of Contents

1. [Test Infrastructure](#test-infrastructure)
2. [iOS (Swift / XCTest)](#ios)
3. [Android (Kotlin / JUnit + Compose)](#android)
4. [Desktop (React / Vitest)](#desktop)
5. [Admin Portal (React / Vitest)](#admin-portal)
6. [Cross-Client E2E Scenarios](#cross-client-e2e-scenarios)

---

## Test Infrastructure

| Client  | Framework              | Runner                        | Commands                                        |
|---------|------------------------|-------------------------------|-------------------------------------------------|
| iOS     | XCTest                 | Xcode / xcodebuild            | `xcodebuild test -scheme SsdidDrive`            |
| Android | JUnit4, MockK, Turbine | Gradle                        | `./gradlew test` / `./gradlew connectedAndroidTest` |
| Desktop | Vitest, Testing Library| npm                           | `cd clients/desktop && npm test`                |
| Admin   | Vitest, Testing Library| npm                           | `cd clients/admin && npm test`                  |

---

## iOS

**Location:** `clients/ios/SsdidDrive/SsdidDriveTests/`

### Existing Tests (18 files)

| File | Area | Cases |
|------|------|-------|
| `Crypto/CryptoTests.swift` | Key generation, signing | Key pair generation, sign/verify round-trip |
| `Crypto/FileEncryptionServiceTests.swift` | File encryption | Encrypt/decrypt round-trip, wrong key rejection |
| `Settings/BaseViewModelTests.swift` | ViewModel base | Loading state, error handling |
| `Settings/MembersViewModelTests.swift` | Members list | Fetch members, role display |
| `Settings/CreateInvitationViewModelTests.swift` | Invitation creation | Validate email, send invitation |
| `Settings/InvitationsListViewModelTests.swift` | Invitations list | Fetch, revoke invitations |
| `Settings/SettingsViewModelTests.swift` | Settings | Toggle biometric, auto-lock |
| `Settings/JoinTenantViewModelTests.swift` | Join tenant | Code validation, submit |
| `Invitation/InvitationTests.swift` | Invitation model | Parsing, status mapping |
| `Invitation/DeepLinkTests.swift` | Deep link parsing | URL parsing, validation, security |
| `Invitation/InviteAcceptViewModelTests.swift` | Invite acceptance | Token validation, wallet flow |
| `Presentation/FileBrowserSearchTests.swift` | File search | Search filtering, debounce |
| `KeyManagerTests.swift` | Key management | Key derivation, storage |
| `ModelTests.swift` | Data models | Encoding/decoding |
| `SecurityManagerTests.swift` | Security | Screen capture, clipboard |
| `AuthRepositoryKdfUpgradeTests.swift` | KDF migration | Upgrade from legacy KDF |
| `TieredKdfTests.swift` | Tiered KDF | Multi-tier key derivation |
| `ShamirSecretSharingTests.swift` | Secret sharing | Split/reconstruct shares |

### Required Test Cases

#### TC-iOS-AUTH: Authentication Flow

| ID | Case | Precondition | Steps | Expected |
|----|------|-------------|-------|----------|
| AUTH-01 | Wallet detection — installed | ssdid-wallet installed on device | Open login screen | Layout A: "Open SSDID Wallet" button visible, email/OIDC collapsed |
| AUTH-02 | Wallet detection — not installed | ssdid-wallet not installed | Open login screen | Layout B: email + OIDC primary, QR code visible |
| AUTH-03 | QR challenge creation | Login screen visible | `viewDidAppear` fires | `createChallenge()` called, QR code displayed, SSE listener started |
| AUTH-04 | SSE session token delivery | SSE connected, wallet approved | Backend sends `event: authenticated` | Token parsed, saved to Keychain, navigates to main |
| AUTH-05 | Wallet callback — app alive | App in background, wallet approved | Wallet opens `ssdid-drive://auth/callback?session_token=X` | `scene(_:openURLContexts:)` fires, token saved, navigates to main |
| AUTH-06 | Wallet callback — app killed | App terminated, wallet approved | Wallet opens callback URL, app cold-starts | `pendingStartupURL` set, `.authCallback` handled in unauthenticated branch |
| AUTH-07 | Session token validation | Callback received | Token with invalid characters | `isValidSessionToken` returns false, error shown |
| AUTH-08 | SSE timeout | SSE connected, 5min elapsed | Server sends `event: timeout` | `isExpired = true`, refresh button shown |
| AUTH-09 | Email + TOTP login | Email entered | Tap "Continue with Email" | `emailLogin()` called, navigates to TOTP if required |
| AUTH-10 | OIDC login | Google button tapped | Tap "Sign in with Google" | OIDC flow launched (ASWebAuthenticationSession) |
| AUTH-11 | Invite code → wallet flow | User enters invite code | Code submitted → wallet opens | `pendingInviteCode` set, `invite_code` in deeplink URL |
| AUTH-12 | Challenge refresh | QR expired | Tap refresh | New challenge created, new QR displayed, SSE reconnected |

#### TC-iOS-DEEPLINK: Deep Link Handling

| ID | Case | Precondition | Steps | Expected |
|----|------|-------------|-------|----------|
| DL-01 | Custom scheme — file | App running | Open `ssdid-drive://file/{id}` | File preview shown |
| DL-02 | Custom scheme — folder | App running | Open `ssdid-drive://folder/{id}` | Folder opened in browser |
| DL-03 | Custom scheme — share | App running | Open `ssdid-drive://share/{id}` | Share detail shown |
| DL-04 | Custom scheme — invite | Not authenticated | Open `ssdid-drive://invite/{token}` | Invite acceptance screen shown |
| DL-05 | Universal link | App running | Open `https://drive.ssdid.my/file/{id}` | File preview shown |
| DL-06 | Action token from MenuBarHelper | App running | Open `ssdid-drive://action/{token}` | Token resolved from SharedDefaults, action executed |
| DL-07 | Spotlight search result | App killed | Tap Spotlight result | App launches, file preview shown |
| DL-08 | Invalid/malicious URL | App running | Open `ssdid-drive://file/../../../etc/passwd` | Rejected by path traversal check |
| DL-09 | Pending deep link after auth | Not authenticated, deep link received | Complete authentication | Pending deep link processed after `authDidComplete()` |

#### TC-iOS-FILES: File Operations

| ID | Case | Steps | Expected |
|----|------|-------|----------|
| FILE-01 | Upload single file | Tap upload, select file | Progress shown, file appears in list |
| FILE-02 | Upload batch | Select multiple files | Batch progress, all files listed |
| FILE-03 | Download file | Tap file → download | File decrypted, opened in preview |
| FILE-04 | Delete file | Swipe to delete | Confirmation dialog, file removed |
| FILE-05 | Create folder | Tap create folder | Folder appears in tree |
| FILE-06 | Move file | Long press → move | File moved to target folder |
| FILE-07 | Search files | Type in search bar | Results filtered in real-time |
| FILE-08 | Pull to refresh | Pull down on file list | List refreshes from server |
| FILE-09 | Empty state | No files | Empty state illustration shown |
| FILE-10 | Offline mode | No network | Cached files accessible, upload queued |

#### TC-iOS-SHARE: Sharing

| ID | Case | Steps | Expected |
|----|------|-------|----------|
| SHARE-01 | Create share link | Select file → share | Share created, link copied |
| SHARE-02 | Set share expiry | Create share with expiry | Share auto-revokes after expiry |
| SHARE-03 | Revoke share | Tap revoke on active share | Share deactivated immediately |
| SHARE-04 | View received shares | Open "Shared with Me" | List of shares from others shown |
| SHARE-05 | Download shared file | Tap shared file | File decrypted with share key |

#### TC-iOS-SECURITY: Security

| ID | Case | Steps | Expected |
|----|------|-------|----------|
| SEC-01 | Screen capture protection | Take screenshot in release build | Secure text field overlay prevents capture |
| SEC-02 | Auto-lock — timeout | Background app > timeout duration | Lock screen shown on return |
| SEC-03 | Auto-lock — disabled | Biometric off | No lock on return from background |
| SEC-04 | Biometric unlock | Lock screen shown | Face ID/Touch ID prompt, unlock on success |
| SEC-05 | Lock via menu (macOS Catalyst) | Cmd+L or menu → Lock | Keys locked, lock screen shown |
| SEC-06 | Multi-window logout (macOS) | Logout in one window | `.userDidLogout` notification → all windows lock |

#### TC-iOS-NOTIFICATION: Notifications

| ID | Case | Steps | Expected |
|----|------|-------|----------|
| NOTIF-01 | Push tap — open share | Tap push with share action | Navigate to share detail |
| NOTIF-02 | Push tap — open file | Tap push with file action | Navigate to file preview |
| NOTIF-03 | Push tap — no action | Tap generic push | Navigate to notifications tab |
| NOTIF-04 | Badge count | Receive push | Badge updated |

---

## Android

**Location:** `clients/android/app/src/androidTest/` (E2E) and `clients/android/app/src/test/` (unit)

### Existing Tests

#### E2E Tests (13 files in `androidTest/kotlin/my/ssdid/drive/e2e/`)

| File | Coverage |
|------|----------|
| `RegistrationLoginE2eTest.kt` | Full registration + login flow |
| `BiometricAuthE2eTest.kt` | Biometric enrollment + unlock |
| `UploadDownloadE2eTest.kt` | File upload + download |
| `ShareFolderE2eTest.kt` | Folder sharing |
| `ShareRevokeE2eTest.kt` | Share revocation |
| `DeepLinkE2eTest.kt` | Deep link handling |
| `OfflineModeE2eTest.kt` | Offline queue + sync |
| `ErrorHandlingE2eTest.kt` | Network errors, API failures |
| `NotificationE2eTest.kt` | Push notification handling |
| `SettingsProfileE2eTest.kt` | Settings + profile |
| `TenantSwitcherE2eTest.kt` | Multi-tenant switching |
| `RecoveryFlowE2eTest.kt` | Key recovery |
| `FullFlowUiE2eTest.kt` | Full end-to-end journey |

### Required Test Cases

#### TC-AND-AUTH: Authentication Flow

| ID | Case | Steps | Expected |
|----|------|-------|----------|
| AUTH-01 | Wallet detection — installed | Open login | `resolveActivity(Intent(ACTION_VIEW, "ssdid://"))` returns non-null → wallet button visible |
| AUTH-02 | Wallet detection — not installed | Open login | resolveActivity returns null → email/OIDC primary, QR visible |
| AUTH-03 | Open wallet deep link | Tap "Open SSDID Wallet" | `ssdid://login?...` intent launched |
| AUTH-04 | SSE token delivery | Wallet approved cross-device | SSE event parsed, token saved to EncryptedSharedPreferences |
| AUTH-05 | Callback deep link | Wallet approved same-device | `ssdid-drive://auth/callback?session_token=X` received via intent filter |
| AUTH-06 | Invite code flow | Enter invite code → approve in wallet | `invite_code` in deep link URL, token saved |
| AUTH-07 | Email + TOTP | Enter email → TOTP code | Session token received |
| AUTH-08 | OIDC Google | Tap Google sign-in | Chrome Custom Tab opens, token returned |
| AUTH-09 | Token validation | Invalid token received | Rejected, error shown |

#### TC-AND-VM: ViewModel Unit Tests (currently missing)

| ID | Case | Target |
|----|------|--------|
| VM-01 | FileBrowserViewModel — load files | Verify StateFlow emissions: Loading → Success |
| VM-02 | FileBrowserViewModel — search | Verify debounced search filtering |
| VM-03 | FileBrowserViewModel — empty state | Verify empty state when folder is empty |
| VM-04 | ShareFileViewModel — create share | Verify share creation flow |
| VM-05 | ShareFileViewModel — revoke | Verify revocation |
| VM-06 | NotificationViewModel — mark read | Verify notification state change |
| VM-07 | ChatViewModel — send message | Verify PII chat send |
| VM-08 | SettingsViewModel — toggle biometric | Verify preference update |
| VM-09 | LoginViewModel — createChallenge | Verify QR payload + SSE connection |
| VM-10 | LoginViewModel — handleCallback | Verify token validation + save |

#### TC-AND-REPO: Repository Unit Tests (currently missing)

| ID | Case | Target |
|----|------|--------|
| REPO-01 | FileRepository — upload | Mock API, verify multipart upload |
| REPO-02 | FileRepository — download + decrypt | Mock API, verify decryption |
| REPO-03 | ShareRepository — create | Mock API, verify share creation |
| REPO-04 | AuthRepository — session expiry | Verify token refresh / logout on 401 |
| REPO-05 | OfflineQueue — enqueue + dequeue | Verify FIFO ordering |
| REPO-06 | OfflineQueue — retry on reconnect | Verify network listener triggers sync |

#### TC-AND-CRYPTO: Crypto Unit Tests (currently missing)

| ID | Case | Target |
|----|------|--------|
| CRYPTO-01 | AesGcmProvider — encrypt/decrypt | Round-trip verification |
| CRYPTO-02 | MlKemProvider — encaps/decaps | KEM round-trip |
| CRYPTO-03 | MlDsaProvider — sign/verify | Signature round-trip |
| CRYPTO-04 | KazKemProvider — encaps/decaps | KAZ-KEM round-trip |
| CRYPTO-05 | KazSignProvider — sign/verify | KAZ-Sign round-trip |
| CRYPTO-06 | SecureMemory — zeroize | Memory wiped after use |

---

## Desktop

**Location:** `clients/desktop/src/` (co-located `__tests__/` directories)

### Existing Tests (72 files)

#### Stores (13/13 — 100%)

| File | Cases |
|------|-------|
| `authStore.test.ts` | Login, logout, token refresh, session expiry |
| `fileStore.test.ts` | Load files, upload, download, delete, move |
| `shareStore.test.ts` | Create share, revoke, list shares |
| `favoritesStore.test.ts` | Add/remove favorites |
| `notificationStore.test.ts` | Fetch, mark read, badge count |
| `onboardingStore.test.ts` | Step progression, completion |
| `piiStore.test.ts` | PII chat conversations |
| `tenantStore.test.ts` | Tenant switching, current tenant |
| `memberStore.test.ts` | Members list, roles |
| `invitationStore.test.ts` | Create, list, revoke invitations |
| `recoveryStore.test.ts` | Recovery setup, key reconstruction |
| `settingsStore.test.ts` | Preferences, biometric toggle |
| `activityStore.test.ts` | Activity log |

#### Hooks (12/12 — 100%)

| File | Cases |
|------|-------|
| `useAutoUpdate.test.ts` | Check for updates, install |
| `useBiometric.test.ts` | Biometric availability, auth |
| `useDeepLink.test.ts` | URL parsing, navigation |
| `useDropZone.test.ts` | Drag enter/leave/drop |
| `useFocusReturn.test.ts` | Focus management |
| `useKeyboardShortcuts.test.ts` | Shortcut registration, dispatch |
| `useOneSignal.test.ts` | Push registration |
| `useOnlineStatus.test.ts` | Online/offline detection |
| `usePushPermission.test.ts` | Permission request |
| `useSync.test.ts` | Sync state management |
| `useToast.test.ts` | Toast show/dismiss |
| `useVirtualList.test.ts` | Virtual scrolling |

#### Pages (14/31 — 45%)

| Tested | Untested |
|--------|----------|
| LoginPage, RegisterPage, EmailLoginPage | ActivityPage, RecoveryPage |
| FilesPage, MySharesPage, SharedWithMePage | TenantRequestPage |
| FavoritesPage, SettingsPage | NotificationsPage |
| JoinTenantPage, OnboardingPage | FilePreviewPage |
| PiiChatPage, InvitationsPage | TrashPage |
| TotpSetupPage, MembersPage | ProfilePage |

#### Components (31/92 — 34%)

Tested: FileList, FileRow, FolderTree, UploadProgress, ShareDialog, Sidebar, TopBar, BreadcrumbNav, SearchBar, EmptyState, ErrorBoundary, plus ~20 more.

### Required Test Cases

#### TC-DT-PAGE: Untested Pages

| ID | Case | Target |
|----|------|--------|
| PAGE-01 | ActivityPage — load activities | Fetch + render activity list |
| PAGE-02 | ActivityPage — filter by type | Filter dropdown changes results |
| PAGE-03 | RecoveryPage — setup flow | Generate shares, display codes |
| PAGE-04 | RecoveryPage — recover | Enter shares, reconstruct key |
| PAGE-05 | NotificationsPage — list | Render notifications, mark read |
| PAGE-06 | FilePreviewPage — image | Render image preview |
| PAGE-07 | FilePreviewPage — PDF | Render PDF viewer |
| PAGE-08 | FilePreviewPage — unsupported | Show "no preview" message |
| PAGE-09 | TrashPage — list deleted | Show trashed files |
| PAGE-10 | TrashPage — restore | Restore file from trash |
| PAGE-11 | ProfilePage — display name | Show/edit display name |
| PAGE-12 | TenantRequestPage — submit | Form validation + submit |

#### TC-DT-COMP: Untested Components

| ID | Case | Target |
|----|------|--------|
| COMP-01 | CreateShareDialog — form | Expiry picker, permission selector, submit |
| COMP-02 | EditShareDialog — update | Modify expiry, permissions |
| COMP-03 | FileUploadDialog — progress | Multi-file progress bars |
| COMP-04 | ConfirmDialog — confirm/cancel | Callback on confirm/cancel |
| COMP-05 | QrCodeDisplay — render | QR image from payload string |
| COMP-06 | BiometricPrompt — success/fail | Biometric auth states |
| COMP-07 | TenantSwitcher — switch | Switch active tenant |
| COMP-08 | NotificationBell — badge | Unread count badge |

#### TC-DT-E2E: End-to-End (Playwright)

| ID | Case | Steps | Expected |
|----|------|-------|----------|
| E2E-01 | Full login flow | Open app → QR scan → authenticated | Main file browser shown |
| E2E-02 | Upload + download | Upload file → download → compare | Files match |
| E2E-03 | Share + access | Create share → open share link | Shared file accessible |
| E2E-04 | Invite + join | Send invite → accept → join tenant | New member visible |
| E2E-05 | Offline → online | Disconnect → queue upload → reconnect | Upload completes on reconnect |

---

## Admin Portal

**Location:** `clients/admin/src/`

### Existing Tests (2 files)

| File | Cases |
|------|-------|
| `components/__tests__/InviteUserDialog.test.tsx` | Open/close, email validation, role selection, submit |
| `pages/__tests__/TenantDetailPage.test.tsx` | Load tenant, members list, invitations, revoke |

### Required Test Cases

#### TC-ADM-PAGE: Pages

| ID | Case | Target | Priority |
|----|------|--------|----------|
| ADM-01 | LoginPage — OIDC redirect | Initiate OIDC login | High |
| ADM-02 | AuthCallbackPage — token exchange | Handle OIDC callback, store token | High |
| ADM-03 | BootstrapPage — superadmin setup | First-time admin registration | High |
| ADM-04 | DashboardPage — stats | Load and display tenant/user stats | Medium |
| ADM-05 | TenantsPage — list | Paginated tenant list, search | Medium |
| ADM-06 | TenantsPage — create | Create tenant dialog, validation | Medium |
| ADM-07 | TenantsPage — disable/enable | Toggle tenant status | Medium |
| ADM-08 | UsersPage — list | Paginated user list, search | Medium |
| ADM-09 | AuditLogPage — list | Paginated audit log | Medium |
| ADM-10 | AuditLogPage — filters | Filter by actor, action, date range | Medium |

#### TC-ADM-COMP: Components

| ID | Case | Target | Priority |
|----|------|--------|----------|
| ADM-11 | DataTable — render | Column headers, rows, loading skeleton | High |
| ADM-12 | DataTable — empty | Empty state message | Medium |
| ADM-13 | Pagination — navigate | Page forward/back, total display | Medium |
| ADM-14 | CreateTenantDialog — validation | Required fields, slug format | High |
| ADM-15 | EditTenantDialog — update | Edit name, quota, disabled status | Medium |
| ADM-16 | StatsCard — render | Label, value, icon | Low |
| ADM-17 | Layout — sidebar | Navigation links, active state | Medium |
| ADM-18 | Layout — auth guard | Redirect to login if unauthenticated | High |

#### TC-ADM-STORE: State Management

| ID | Case | Target | Priority |
|----|------|--------|----------|
| ADM-19 | adminStore — fetchTenants | API call, pagination, store update | High |
| ADM-20 | adminStore — createTenant | API call, optimistic update | High |
| ADM-21 | adminStore — fetchUsers | Paginated user list | Medium |
| ADM-22 | adminStore — auth | Login, logout, token storage | High |
| ADM-23 | adminStore — audit log | Fetch with filters | Medium |

---

## Cross-Client E2E Scenarios

These test the full system across wallet + drive + backend.

| ID | Scenario | Clients | Steps | Expected |
|----|----------|---------|-------|----------|
| X-01 | New user onboarding (same-device) | Wallet + Drive iOS | Admin invites → user enters code in Drive → wallet opens → approve → callback to Drive | User lands on "My Files" with valid session |
| X-02 | New user onboarding (cross-device) | Wallet (phone) + Drive (desktop) | Admin invites → user enters code in Drive desktop → scans QR with wallet → approve → SSE delivers token | Desktop shows "My Files" |
| X-03 | Returning user login (same-device) | Wallet + Drive iOS | Open Drive → tap "Open SSDID Wallet" → approve → callback | Session restored, files visible |
| X-04 | Returning user login (QR) | Wallet (phone) + Drive (desktop) | Open Drive desktop → scan QR → approve → SSE delivers | Session restored |
| X-05 | Session expiry | Any client + Backend | Session expires on server → client makes API call | 401 → auto-logout → login screen |
| X-06 | Multi-tenant switch | Drive iOS/Android | User in tenant A → switch to tenant B | Files refresh to tenant B content |
| X-07 | Shared file access | Drive (sender) + Drive (receiver) | Sender creates share → receiver opens share link | Receiver sees shared file |
| X-08 | Recovery flow | Drive + Wallet | User sets up recovery → loses device → recovers on new device | Keys reconstructed, files accessible |
| X-09 | Concurrent sessions | Drive iOS + Drive Desktop | Login on both → upload on iOS → check desktop | File appears on desktop via sync |
| X-10 | Invite revocation | Admin + Drive | Admin revokes invite → user tries to use it | Error: "Invitation revoked" |

---

## Coverage Summary

| Client  | Unit Tests | E2E Tests | Coverage | Priority Gaps |
|---------|-----------|-----------|----------|---------------|
| iOS     | 18 files  | 0         | ~40%     | UI layer, FileProvider, deeplink callback |
| Android | 0 files   | 13 files  | ~25%     | **All unit tests missing**: ViewModels, Repos, Crypto |
| Desktop | 72 files  | 1 file    | ~55%     | Pages (55% untested), components (66% untested) |
| Admin   | 2 files   | 0         | ~13%     | **Critical**: Login, Dashboard, all stores |

### Priority Order

1. **Android unit tests** — zero unit test coverage, only E2E
2. **Admin portal** — 13% coverage, critical for operations
3. **iOS deeplink + auth tests** — active bugs in this area
4. **Desktop pages + components** — stores/hooks are solid, UI layer needs work
