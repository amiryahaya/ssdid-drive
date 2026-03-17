# OIDC Onboarding Flow — iOS + Android Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Enable Google and Microsoft sign-in on iOS and Android with invite code support, so enterprise users can join an organization via OIDC instead of only via SSDID Wallet.

**Architecture:** Both platforms open a system browser (ASWebAuthenticationSession on iOS, Chrome Custom Tabs on Android) pointing to `GET /api/auth/oidc/{provider}/authorize?redirect_uri=ssdid-drive://auth/callback&invitation_token=X`. The backend handles the full OAuth flow, then redirects back to the app with a session token via the custom scheme. The app's existing deep link handler receives the token and completes login.

**Tech Stack:** Swift/UIKit + ASWebAuthenticationSession (iOS), Kotlin/Compose + Chrome Custom Tabs (Android)

---

## How It Works

```
  User taps "Sign in with Google"
       │
       ▼
  App opens system browser:
  GET /api/auth/oidc/google/authorize
    ?redirect_uri=ssdid-drive://auth/callback
    &invitation_token=INVITE-CODE (if joining org)
       │
       ▼
  Backend stores state in session, redirects to Google
       │
       ▼
  Google auth page → user signs in → consent
       │
       ▼
  Google redirects to backend:
  GET /api/auth/oidc/google/callback?code=X&state=Y
       │
       ▼
  Backend exchanges code, validates token, creates session
  If invitation_token → creates user + accepts invitation
       │
       ▼
  Backend redirects to:
  ssdid-drive://auth/callback?token=SESSION_TOKEN&provider=google
       │
       ▼
  App receives deep link → saves token → navigates to main
```

## File Structure

### iOS (Chunk 1)
- Modify: `clients/ios/SsdidDrive/SsdidDrive/Presentation/Coordinators/AuthCoordinator.swift` — Launch ASWebAuthenticationSession
- Modify: `clients/ios/SsdidDrive/SsdidDrive/SceneDelegate.swift` — Handle OIDC callback (already handles auth callback)
- Modify: `clients/ios/SsdidDrive/SsdidDrive/Presentation/Auth/LoginViewModel.swift` — Store pending invite code for OIDC

### Android (Chunk 2)
- Modify: `clients/android/app/src/main/kotlin/my/ssdid/drive/presentation/auth/LoginViewModel.kt` — Launch Chrome Custom Tab, pass invite code
- Modify: `clients/android/app/src/main/kotlin/my/ssdid/drive/presentation/auth/LoginScreen.kt` — Wire OIDC button to browser launch
- Modify: `clients/android/app/src/main/kotlin/my/ssdid/drive/presentation/navigation/NavGraph.kt` — Handle OIDC callback from deep link

---

## Chunk 1: iOS — OIDC via ASWebAuthenticationSession

### Task 1: iOS — Implement OIDC browser flow in AuthCoordinator

The OIDC buttons already exist in `LoginViewController` and call `delegate?.loginDidRequestOidc(provider:)`. Currently the delegate method in `AuthCoordinator` shows a "coming soon" alert. Replace it with a real browser-based OAuth flow.

**Files:**
- Modify: `clients/ios/SsdidDrive/SsdidDrive/Presentation/Coordinators/AuthCoordinator.swift`

- [ ] **Step 1: Import AuthenticationServices**

Add at top of file:
```swift
import AuthenticationServices
```

- [ ] **Step 2: Add ASWebAuthenticationSession property**

Add to AuthCoordinator properties:
```swift
private var authSession: ASWebAuthenticationSession?
```

- [ ] **Step 3: Replace the stub with real OIDC flow**

Replace `loginDidRequestOidc(provider:)` in the `LoginViewControllerDelegate` extension:

```swift
func loginDidRequestOidc(provider: String) {
    let inviteCode = loginViewModel?.pendingInviteCode ?? ""
    let callbackScheme = "ssdid-drive"

    // Build authorize URL with redirect_uri and optional invite code
    var urlString = "\(Constants.API.baseURL)/api/auth/oidc/\(provider)/authorize"
    urlString += "?redirect_uri=\(callbackScheme)://auth/callback"
    if !inviteCode.isEmpty {
        urlString += "&invitation_token=\(inviteCode.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? inviteCode)"
    }

    guard let url = URL(string: urlString) else { return }

    let session = ASWebAuthenticationSession(
        url: url,
        callbackURLScheme: callbackScheme
    ) { [weak self] callbackURL, error in
        self?.authSession = nil

        if let error = error as? ASWebAuthenticationSessionError,
           error.code == .canceledLogin {
            return // User cancelled — do nothing
        }

        guard let callbackURL = callbackURL else {
            self?.loginViewModel?.errorMessage = "Sign-in was cancelled or failed"
            return
        }

        // The callback URL is: ssdid-drive://auth/callback?token=X&provider=Y
        // Parse the token and handle it
        let components = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false)
        let queryItems = components?.queryItems ?? []

        if let errorMsg = queryItems.first(where: { $0.name == "error" })?.value {
            self?.loginViewModel?.errorMessage = errorMsg
            return
        }

        if let token = queryItems.first(where: { $0.name == "token" })?.value,
           !token.isEmpty {
            self?.loginViewModel?.handleAuthCallback(sessionToken: token)
        } else {
            self?.loginViewModel?.errorMessage = "No session token received"
        }
    }

    // Present as a modal web view
    session.presentationContextProvider = navigationController.topViewController as? ASWebAuthenticationPresentationContextProviding
        ?? navigationController as? ASWebAuthenticationPresentationContextProviding
    session.prefersEphemeralWebBrowserSession = true
    session.start()
    authSession = session
}
```

- [ ] **Step 4: Add ASWebAuthenticationPresentationContextProviding**

Add conformance to `LoginViewController` (or `BaseViewController`). Add at the bottom of `LoginViewController.swift`:

```swift
// MARK: - ASWebAuthenticationPresentationContextProviding
extension LoginViewController: ASWebAuthenticationPresentationContextProviding {
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        view.window ?? ASPresentationAnchor()
    }
}
```

Also import `AuthenticationServices` at the top of `LoginViewController.swift`.

- [ ] **Step 5: Also wire OIDC from InviteAcceptViewController**

Read `AuthCoordinator`'s `inviteAcceptViewModelDidRequestOidc` method. It should similarly launch the browser with the invitation token. Update:

```swift
func inviteAcceptViewModelDidRequestOidc(provider: String, token: String) {
    let callbackScheme = "ssdid-drive"
    var urlString = "\(Constants.API.baseURL)/api/auth/oidc/\(provider)/authorize"
    urlString += "?redirect_uri=\(callbackScheme)://auth/callback"
    urlString += "&invitation_token=\(token.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? token)"

    guard let url = URL(string: urlString) else { return }

    let session = ASWebAuthenticationSession(
        url: url,
        callbackURLScheme: callbackScheme
    ) { [weak self] callbackURL, error in
        self?.authSession = nil

        if let error = error as? ASWebAuthenticationSessionError,
           error.code == .canceledLogin { return }

        guard let callbackURL = callbackURL,
              let components = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false),
              let token = components.queryItems?.first(where: { $0.name == "token" })?.value,
              !token.isEmpty else {
            // Check for error message
            if let callbackURL = callbackURL,
               let errorMsg = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false)?
                .queryItems?.first(where: { $0.name == "error" })?.value {
                self?.inviteAcceptViewModel?.handleWalletError(message: errorMsg)
            }
            return
        }

        self?.inviteAcceptViewModel?.handleWalletCallback(sessionToken: token)
    }

    session.presentationContextProvider = navigationController.topViewController as? ASWebAuthenticationPresentationContextProviding
    session.prefersEphemeralWebBrowserSession = true
    session.start()
    authSession = session
}
```

- [ ] **Step 6: Build and verify**

Build in Xcode — verify no compile errors.

- [ ] **Step 7: Commit**

```bash
git add clients/ios/
git commit -m "feat(ios): implement OIDC sign-in via ASWebAuthenticationSession

Launch system browser for Google/Microsoft sign-in with invite code
support. Backend handles OAuth flow and redirects back with session
token via ssdid-drive:// deep link. Works from both login screen
and invite acceptance screen."
```

---

## Chunk 2: Android — OIDC via Browser Intent

### Task 2: Android — Launch browser for OIDC + handle callback

Android uses the redirect-based flow: open browser → backend handles OAuth → redirects back to app via deep link. The deep link handler already processes `ssdid-drive://auth/callback?token=X`.

**Files:**
- Modify: `clients/android/app/src/main/kotlin/my/ssdid/drive/presentation/auth/LoginViewModel.kt`
- Modify: `clients/android/app/src/main/kotlin/my/ssdid/drive/presentation/auth/LoginScreen.kt`
- Modify: `clients/android/app/src/main/kotlin/my/ssdid/drive/presentation/navigation/NavGraph.kt`

- [ ] **Step 1: Add OIDC browser launch to LoginViewModel**

Read `LoginViewModel.kt`. Add a method to build the authorize URL and expose it as a state event:

```kotlin
// Add to UiState:
val oidcLaunchUrl: String? = null

// Add method:
fun launchOidc(provider: String, inviteCode: String? = null) {
    val baseUrl = BuildConfig.API_BASE_URL.removeSuffix("/api/")
    val redirectUri = "ssdid-drive://auth/callback"
    var url = "$baseUrl/api/auth/oidc/$provider/authorize" +
        "?redirect_uri=${Uri.encode(redirectUri)}"
    if (!inviteCode.isNullOrBlank()) {
        url += "&invitation_token=${Uri.encode(inviteCode)}"
    }
    _uiState.update { it.copy(oidcLaunchUrl = url) }
}

fun onOidcLaunched() {
    _uiState.update { it.copy(oidcLaunchUrl = null) }
}
```

- [ ] **Step 2: Also pass invite code through handleOidcResult**

Update `handleOidcResult` to pass `invitationToken`:

```kotlin
fun handleOidcResult(provider: String, idToken: String, invitationToken: String? = null) {
    viewModelScope.launch {
        _uiState.update { it.copy(isLoading = true, error = null) }
        when (authRepository.oidcVerify(provider, idToken, invitationToken)) {
            is Result.Success -> {
                _uiState.update { it.copy(isLoading = false, isAuthenticated = true) }
            }
            is Result.Error -> {
                _uiState.update {
                    it.copy(isLoading = false, error = "Sign-in failed. Please try again.")
                }
            }
        }
    }
}
```

- [ ] **Step 3: Wire OIDC buttons in LoginScreen to launch browser**

Read `LoginScreen.kt`. Find the Google/Microsoft button `onClick` handlers. Replace with:

```kotlin
// Google button:
onClick = { viewModel.launchOidc("google", pendingInviteCode) }

// Microsoft button:
onClick = { viewModel.launchOidc("microsoft", pendingInviteCode) }
```

Add a `LaunchedEffect` to observe `oidcLaunchUrl` and open browser:

```kotlin
val oidcLaunchUrl = uiState.oidcLaunchUrl
LaunchedEffect(oidcLaunchUrl) {
    if (oidcLaunchUrl != null) {
        val intent = Intent(Intent.ACTION_VIEW, Uri.parse(oidcLaunchUrl))
        context.startActivity(intent)
        viewModel.onOidcLaunched()
    }
}
```

Import `android.content.Intent` and `android.net.Uri`.

- [ ] **Step 4: Handle OIDC callback in deep link handler**

Read `NavGraph.kt` or the deep link handler. The existing deep link handler for `ssdid-drive://auth/callback?session_token=X` already works for wallet callbacks. The OIDC callback uses `token=X` (not `session_token`). Check `DeepLinkHandler.kt` to see if it handles both param names.

If it only handles `session_token`, add `token` as an alternative:

```kotlin
// In DeepLinkHandler or wherever auth callback is parsed:
val sessionToken = queryParams["session_token"] ?: queryParams["token"]
```

Also check for `error` param and display it:
```kotlin
val error = queryParams["error"]
if (!error.isNullOrBlank()) {
    // Show error to user
}
```

- [ ] **Step 5: Run tests**

Run: `cd clients/android && ./gradlew test`

- [ ] **Step 6: Commit**

```bash
git add clients/android/
git commit -m "feat(android): implement OIDC sign-in via browser redirect

Launch system browser for Google/Microsoft sign-in with invite code
support. Backend handles OAuth flow and redirects back with session
token via ssdid-drive:// deep link. Handle both 'token' and
'session_token' query params in callback."
```

---

## Verification

### Manual Test Checklist

**iOS:**
- [ ] Tap "Sign in with Google" → browser opens → Google consent → redirects back → logged in
- [ ] Tap "Sign in with Microsoft" → same flow
- [ ] Enter invite code → tap OIDC → new user created in org
- [ ] Cancel in browser → no crash, stays on login
- [ ] Invalid invite code → error message shown

**Android:**
- [ ] Tap "Sign in with Google" → browser opens → Google consent → redirects back → logged in
- [ ] Tap "Sign in with Microsoft" → same flow
- [ ] Enter invite code → tap OIDC → new user created in org
- [ ] Back button from browser → stays on login
- [ ] Invalid invite code → error message shown

### Prerequisites
- Google OAuth client ID configured in backend `appsettings.json` under `Oidc:Google:ClientId`
- Microsoft OAuth client ID configured under `Oidc:Microsoft:ClientId`
- Custom URL scheme `ssdid-drive://` registered in iOS Info.plist (already done) and Android manifest (already done)
