# iOS Onboarding UI Improvements — Design Spec

## Goal

Achieve feature parity with the Android client for enterprise B2B onboarding: multi-auth login (Email+TOTP, OIDC, Wallet), multi-auth invitation acceptance, tenant request submission, and invitation creation polish.

## Context

The iOS client currently only supports SSDID Wallet (QR code) for login and invitation acceptance. The backend now supports all 3 auth methods. The Android client was just updated with these features. iOS needs to catch up.

**Architecture constraint:** Keep UIKit + Coordinator pattern for auth screens. New standalone screens (TenantRequest) use SwiftUI in UIHostingController as modal presentations — matching the existing pattern for JoinTenantView, CreateInvitationView.

## Scope

6 changes, ordered by priority:

1. **Extend LoginViewController** — add email+TOTP, OIDC buttons, org request link (UIKit)
2. **New TotpVerifyViewController** — 6-digit TOTP input after email login (UIKit)
3. **Extend InviteAcceptViewController** — add multi-auth buttons (UIKit)
4. **New TenantRequestView** — org request form (SwiftUI modal)
5. **Enhance CreateInvitationView** — add copy/share for short code, email_sent status
6. **Wire navigation** — AuthCoordinator additions for TOTP and TenantRequest

---

## Screen 1: LoginViewController Extension

**File:** `Presentation/Auth/LoginViewController.swift` (modify)
**File:** `Presentation/Auth/LoginViewModel.swift` (modify)

### Layout Change

Current: Logo → QR code (250px) → Refresh → Open Wallet

New (top to bottom):
1. Logo (80x80) + "SSDID Drive" title + subtitle
2. **"Have an invite code?"** card (already exists as link button — make more prominent)
3. Divider: "or sign in"
4. **Email text field** (UITextField, email keyboard)
5. **"Continue with Email"** button (primary style)
6. Divider: "or"
7. **"Sign in with Google"** button (secondary style)
8. **"Sign in with Microsoft"** button (secondary style)
9. Divider: "or scan with wallet"
10. **QR Code** (reduced to 150px — deprioritized but still available)
11. **"Open SSDID Wallet"** button (secondary, kept)
12. **"Need an organization? Request one"** text button (bottom)

Wrap in UIScrollView to handle smaller screens.

### ViewModel Additions

```swift
// New published properties
@Published var email: String = ""
@Published var navigateToTotp: String? = nil  // email to pass to TOTP screen

// New methods
func emailLogin() {
    // Call POST /api/auth/email/login with email
    // If success (TOTP required) → set navigateToTotp = email
    // If error → set errorMessage
}

func handleOidcResult(provider: String, idToken: String) {
    // Call authRepository.oidcVerify(provider, idToken)
    // If success → save session, set isAuthenticated
    // If error → set errorMessage
}
```

### OIDC Integration

Use `ASWebAuthenticationSession` for Google/Microsoft SSO:
- Build authorize URL: `GET /api/auth/oidc/{provider}/authorize?redirect_uri=ssdid-drive://oidc/callback`
- Present ASWebAuthenticationSession
- On callback: extract token from redirect, call `oidcVerify`
- Or use native Google Sign-In / MSAL SDK if already integrated

Check existing OIDC integration in the codebase first — there may be infrastructure already.

### Delegate/Coordinator Callbacks

```swift
protocol LoginViewControllerDelegate: AnyObject {
    // Existing
    func loginDidComplete()
    func loginDidRequestInviteCode()
    // New
    func loginDidRequestTotpVerify(email: String)
    func loginDidRequestTenantRequest()
}
```

---

## Screen 2: TotpVerifyViewController (New)

**File:** `Presentation/Auth/TotpVerifyViewController.swift` (new)
**File:** `Presentation/Auth/TotpVerifyViewModel.swift` (new)

### Layout

```
┌─────────────────────────────┐
│  ← Back          (nav bar)  │
│                             │
│  🔐 (lock.fill, 48pt)      │
│                             │
│  Two-Factor Authentication  │
│  Enter the 6-digit code     │
│  from your authenticator    │
│                             │
│  [______] (centered, 32pt)  │
│  monospaced, 6 chars max    │
│                             │
│  [Verify]  (primary button) │
│                             │
│  Error text (red, hidden)   │
│                             │
│  Lost your authenticator?   │
│  Recover access →           │
└─────────────────────────────┘
```

### ViewModel

```swift
class TotpVerifyViewModel: BaseViewModel {
    let email: String
    @Published var code: String = ""
    @Published var isAuthenticated: Bool = false

    func verify() {
        // Call POST /api/auth/totp/verify with email + code
        // If success → save session, set isAuthenticated
        // If error → set errorMessage
    }
}
```

### Auto-submit

When code reaches 6 digits, auto-trigger `verify()` (matching Android behavior).

### Coordinator

`AuthCoordinator.showTotpVerify(email:)` pushes onto navigation stack.

---

## Screen 3: InviteAcceptViewController Extension

**File:** `Presentation/Auth/InviteAcceptViewController.swift` (modify)
**File:** `Presentation/Auth/InviteAcceptViewModel.swift` (modify)

### Layout Change

Current: Invitation card → "Accept with SSDID Wallet" → "Already have an account? Sign In"

New (after invitation card):
1. **"Sign In to Accept"** button (secondary) — for existing authenticated users
2. Divider: "or create account"
3. **"Continue with Email"** button (secondary)
4. **"Sign in with Google"** button (secondary)
5. **"Sign in with Microsoft"** button (secondary)
6. **"Accept with SSDID Wallet"** button (primary, kept)

Hide all buttons when `isWaitingForWallet` is true.

### ViewModel Additions

```swift
@Published var isAcceptingAsExisting: Bool = false
@Published var acceptError: String? = nil

func acceptAsExistingUser() {
    // Call tenantRepository.acceptInvitationByToken(token)
    // On success → set isRegistered = true
}

func handleOidcResult(provider: String, idToken: String) {
    // Call authRepository.oidcVerify(provider, idToken, invitationToken: token)
    // On success → set isRegistered = true
}
```

### Email Registration with Invitation

"Continue with Email" navigates to an email registration flow that passes the invitation token. Either:
- Reuse existing email registration if available
- Or create a simple 2-step flow: email entry → OTP verify (like Android's InviteEmailRegisterScreen)

The Coordinator handles: `authCoordinator.showEmailRegisterForInvitation(token:)`

---

## Screen 4: TenantRequestView (New SwiftUI)

**File:** `Presentation/Settings/TenantRequestView.swift` (new)
**File:** `Presentation/Settings/TenantRequestViewModel.swift` (new)

Follows `JoinTenantView` pattern exactly — SwiftUI view presented as modal.

### Layout

```swift
struct TenantRequestView: View {
    @StateObject var viewModel = TenantRequestViewModel()

    var body: some View {
        NavigationView {
            // If submitted → success state
            // Else → form (org name, reason, submit button)
        }
        .navigationTitle("Request Organization")
    }
}
```

### Form State
- Organization name (required)
- Reason (optional, 500 char max with counter)
- Submit button (disabled when loading or name blank)

### Success State
- Checkmark icon (green)
- "Request Submitted!" heading
- "An administrator will review your request."
- "Done" button (dismisses modal)

### Repository

Add to `TenantRepository`:
```swift
func submitTenantRequest(organizationName: String, reason: String?) async throws -> TenantRequestResult
```

Calls `POST /api/tenant-requests`.

### Access Points
- LoginViewController: "Need an organization? Request one" → presents modal
- SettingsViewController: "Request Organization" menu item → presents modal

---

## Screen 5: CreateInvitationView Enhancement

**File:** `Presentation/Settings/CreateInvitationView.swift` (modify)

### Changes to Success State

Add after "Invitation created!" message:
- Short code in large monospace text (same as Android)
- **Copy button** — copies to UIPasteboard, shows "Copied!" toast
- **Share button** — launches UIActivityViewController with invite text
- **`email_sent` status** — show "Email sent" checkmark or "Email failed" warning based on API response

### ViewModel Change

Update to read `emailSent` and `emailError` from the API response (backend now returns these fields).

---

## Screen 6: Navigation Wiring

### AuthCoordinator Additions

```swift
// New methods
func showTotpVerify(email: String) {
    let vm = TotpVerifyViewModel(email: email, authRepository: authRepository)
    let vc = TotpVerifyViewController(viewModel: vm)
    vc.delegate = self
    navigationController.pushViewController(vc, animated: true)
}

func showTenantRequestModal() {
    let view = TenantRequestView()
    let hostingVC = UIHostingController(rootView: view)
    navigationController.present(hostingVC, animated: true)
}
```

### LoginViewControllerDelegate Extension

Add `loginDidRequestTotpVerify(email:)` and `loginDidRequestTenantRequest()` to protocol.

### Deep Link Handling

No changes needed — existing SceneDelegate deep link handling continues to work since we're extending UIKit VCs, not replacing them.

---

## Testing

Each new ViewModel gets unit tests with XCTest + Combine expectations:
- `TotpVerifyViewModelTests` — verify code validation, API call, success/error states
- `TenantRequestViewModelTests` — blank name validation, submit success, conflict error

Extend existing tests:
- `LoginViewModelTests` — add email login and OIDC result tests
- `InviteAcceptViewModelTests` — add multi-auth method tests
