# Deep Link Integration Plan: SSDID Drive ↔ SSDID Wallet (iOS)

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Fix all critical mismatches between ssdid-drive iOS and ssdid-wallet iOS deep link implementations so the same-device and cross-device authentication flows work end-to-end.

**Architecture:** The wallet is the source of truth for the authentication protocol. The Android wallet has a working implementation. We align both iOS apps to the Android wallet's proven contract: Drive sends `ssdid://login?server_url=...&service_name=...&challenge_id=...&callback_url=ssdid-drive://auth/callback&requested_claims=...`, wallet processes authentication and calls back via `ssdid-drive://auth/callback?session_token=...`. QR codes contain the same `ssdid://login?...` URL string (not raw JSON). The `DriveLoginScreen` is the correct wallet destination (not `AuthFlowScreen`).

**Tech Stack:** Swift (iOS, both repos), XcodeGen (project.yml)

**Repos:**
- `~/Workspace/ssdid-drive` — Drive app (client)
- `~/Workspace/ssdid-wallet` — Wallet app (authenticator)

---

## Phase 1: Wallet iOS Fixes (ssdid-wallet repo)

These must be done first because the wallet is the receiving end.

### Task 1: Register `ssdid://` URL scheme in wallet iOS

**Files:**
- Modify: `ios/project.yml`

**Why:** The wallet's `project.yml` has `GENERATE_INFOPLIST_FILE: true` but no `urlTypes`. The `ssdid://` scheme is not registered with iOS. When Drive opens `ssdid://login?...`, iOS doesn't know which app to launch. Android already has this via `AndroidManifest.xml`.

**Step 1:** Add `urlTypes` to the SsdidWallet target in `ios/project.yml`:

```yaml
# Under targets > SsdidWallet, after the settings block:
    urlTypes:
      - name: SsdidWallet
        schemes: [ssdid]
```

**Step 2:** Add `LSApplicationQueriesSchemes` for `ssdid-drive` to enable `canOpenURL` checks when calling back:

```yaml
# Under targets > SsdidWallet > settings > base:
        INFOPLIST_KEY_LSApplicationQueriesSchemes: "ssdid-drive"
```

Note: XcodeGen may not support this via settings. Alternative — add a partial Info.plist:

Create `ios/SsdidWallet/Info.plist`:
```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>LSApplicationQueriesSchemes</key>
    <array>
        <string>ssdid-drive</string>
    </array>
</dict>
</plist>
```

And reference it in project.yml:
```yaml
    settings:
      base:
        GENERATE_INFOPLIST_FILE: true
        INFOPLIST_FILE: SsdidWallet/Info.plist
```

**Verify:** Run `xcodegen generate` and inspect the generated xcodeproj's Info.plist for both `CFBundleURLTypes` with `ssdid` and `LSApplicationQueriesSchemes` with `ssdid-drive`.

---

### Task 2: Add `callback_url` and `requested_claims` to wallet iOS DeepLinkHandler

**Files:**
- Modify: `ios/SsdidWallet/Platform/DeepLink/DeepLinkHandler.swift`

**Why:** The iOS wallet `DeepLinkAction.authenticate` only captures `serverUrl` and `sessionId`. It's missing `callback_url`, `requested_claims`, and `accepted_algorithms` that the Android wallet handles. The `login` action is also missing these fields.

**Step 1:** Update the `DeepLinkAction` enum to include callback and claims:

```swift
enum DeepLinkAction: Equatable {
    case register(serverUrl: String, serverDid: String?)
    case authenticate(serverUrl: String, callbackUrl: String, sessionId: String?, requestedClaims: String?, acceptedAlgorithms: String?)
    case sign(serverUrl: String, sessionToken: String)
    case credentialOffer(issuerUrl: String, offerId: String)
    case login(serverUrl: String, serviceName: String?, challengeId: String?, callbackUrl: String, requestedClaims: String?)
}
```

**Step 2:** Update the `authenticate` case in `parse(url:)` to extract new parameters:

```swift
case "authenticate":
    guard let serverUrl = params["server_url"] else {
        throw DeepLinkError.missingRequiredParameter("server_url")
    }
    try urlValidator.validate(urlString: serverUrl)
    let callbackUrl = params["callback_url"] ?? ""
    return .authenticate(
        serverUrl: serverUrl,
        callbackUrl: callbackUrl,
        sessionId: params["session_id"],
        requestedClaims: params["requested_claims"],
        acceptedAlgorithms: params["accepted_algorithms"]
    )
```

**Step 3:** Update the `login` case similarly:

```swift
case "login":
    guard let serverUrl = params["server_url"] else {
        throw DeepLinkError.missingRequiredParameter("server_url")
    }
    try urlValidator.validate(urlString: serverUrl)
    let callbackUrl = params["callback_url"] ?? ""
    return .login(
        serverUrl: serverUrl,
        serviceName: params["service_name"],
        challengeId: params["challenge_id"],
        callbackUrl: callbackUrl,
        requestedClaims: params["requested_claims"]
    )
```

**Step 4:** Add callback URL validation (port from Android's `isValidCallbackUrl`):

```swift
static func isValidCallbackUrl(_ url: String) -> Bool {
    guard !url.isEmpty, let parsed = URL(string: url), let scheme = parsed.scheme?.lowercased() else {
        return false
    }
    let dangerousSchemes: Set<String> = ["javascript", "data", "file", "blob", "vbscript"]
    if dangerousSchemes.contains(scheme) { return false }
    if scheme == "https" { return parsed.host?.isEmpty == false }
    // Allow custom app schemes (e.g., ssdid-drive)
    return scheme.range(of: "^[a-z][a-z0-9+\\-.]*$", options: .regularExpression) != nil
}
```

**Verify:** Update `DeepLinkHandlerTests.swift` to test new parameters and callback URL validation.

---

### Task 3: Route `login` deep links to `DriveLoginScreen` with callback support

**Files:**
- Modify: `ios/SsdidWallet/UI/Navigation/ContentView.swift` (deep link consumption)
- Modify: `ios/SsdidWallet/Feature/Scan/ScanQrScreen.swift` (QR scan routing)
- Modify: `ios/SsdidWallet/App/AppCoordinator.swift` or wherever deep links are consumed and routed

**Why:** Currently the wallet's `ScanQrScreen.handleQrContent` only handles `ssdid://auth` and `ssdid://register` by extracting params named `"url"`, `"callback"`, `"did"`. It does NOT handle `ssdid://login`. Deep links from `AppCoordinator.pendingDeepLink` need to be consumed and routed to `DriveLoginScreen`.

**Step 1:** Find where `consumeDeepLink()` is called and route `DeepLinkAction.login` to `DriveLoginScreen`:

```swift
if let url = coordinator.consumeDeepLink() {
    let handler = DeepLinkHandler()
    if let action = try? handler.parse(url: url) {
        switch action {
        case .login(let serverUrl, let serviceName, let challengeId, let callbackUrl, let requestedClaims):
            router.push(.driveLogin(
                serviceUrl: serverUrl,
                serviceName: serviceName ?? "SSDID Drive",
                challengeId: challengeId ?? "",
                requestedClaims: requestedClaims ?? ""
            ))
            // Store callbackUrl for post-auth (see Task 4)
        case .authenticate(let serverUrl, let callbackUrl, _, let requestedClaims, let acceptedAlgorithms):
            // Route to consent or authFlow as before
            ...
        }
    }
}
```

**Step 2:** Update `ScanQrScreen.handleQrContent` to parse QR content as `ssdid://login?...` URL:

```swift
private func handleQrContent(_ content: String) {
    guard let url = URL(string: content), url.scheme == "ssdid" else { return }
    let handler = DeepLinkHandler()
    guard let action = try? handler.parse(url: url) else { return }

    switch action {
    case .login(let serverUrl, let serviceName, let challengeId, _, let requestedClaims):
        router.push(.driveLogin(
            serviceUrl: serverUrl,
            serviceName: serviceName ?? "SSDID Drive",
            challengeId: challengeId ?? "",
            requestedClaims: requestedClaims ?? ""
        ))
    case .register(let serverUrl, let serverDid):
        router.push(.registration(serverUrl: serverUrl, serverDid: serverDid ?? ""))
    case .authenticate(let serverUrl, let callbackUrl, _, _, _):
        router.push(.authFlow(serverUrl: serverUrl, callbackUrl: callbackUrl))
    default:
        break
    }
}
```

This replaces the ad-hoc `queryItem("url")` parsing with the validated `DeepLinkHandler`.

**Verify:** Build wallet, scan a QR code containing `ssdid://login?server_url=https://drive.ssdid.my&service_name=ssdid-drive&challenge_id=abc123&requested_claims=[{"key":"name","required":"true"}]`. Should navigate to `DriveLoginScreen`.

---

### Task 4: Implement real authentication and callback in `DriveLoginScreen` (iOS)

**Files:**
- Modify: `ios/SsdidWallet/Feature/Auth/DriveLoginScreen.swift`
- Create: `ios/SsdidWallet/Feature/Auth/DriveLoginViewModel.swift` (new, mirrors Android's `DriveLoginViewModel.kt`)

**Why:** The iOS `DriveLoginScreen` is a UI shell with mock authentication (1.5s delay → `router.pop()`). Android has a real `DriveLoginViewModel` that: validates the service URL, loads identities from vault, registers if needed, signs the challenge, authenticates, and returns session token. We need to port this logic to iOS AND add the callback to Drive.

**Step 1:** Create `DriveLoginViewModel.swift` mirroring Android's structure:

```swift
@MainActor
final class DriveLoginViewModel: ObservableObject {
    let serviceUrl: String
    let serviceName: String
    let challengeId: String
    let callbackUrl: String
    let requestedClaims: [ClaimRequest]

    @Published var state: DriveLoginState = .loading
    @Published var identities: [Identity] = []
    @Published var selectedIdentity: Identity?
    @Published var selectedClaims: Set<String> = []

    private let vault: Vault
    private let httpClient: SsdidHttpClient
    private let verifier: Verifier

    func approve() async {
        guard let identity = selectedIdentity else { return }
        state = .submitting

        do {
            let driveApi = httpClient.driveApi(serviceUrl)

            // Get or register credential
            var credential = vault.getCredentialForDid(identity.did)
            if credential == nil {
                credential = try await registerWithDrive(identity: identity, driveApi: driveApi)
            }

            // Authenticate
            let response = try await driveApi.authenticate(credential: credential!, challengeId: challengeId)
            state = .success(sessionToken: response.sessionToken)
        } catch {
            state = .error(message: error.localizedDescription)
        }
    }
}
```

**Step 2:** Add callback URL opening on success in `DriveLoginScreen`:

```swift
case .success(let sessionToken):
    // Build callback URL with session token
    let callbackUrl = viewModel.callbackUrl
    VStack { ... success UI ... }
    Button {
        if !callbackUrl.isEmpty,
           var components = URLComponents(string: callbackUrl) {
            var items = components.queryItems ?? []
            items.append(URLQueryItem(name: "session_token", value: sessionToken))
            components.queryItems = items
            if let url = components.url {
                UIApplication.shared.open(url)
            }
        }
        router.pop()
    } label: {
        Text(callbackUrl.isEmpty ? "Done" : "Return to SSDID Drive")
    }
```

**Step 3:** Wire `DriveLoginScreen` to the view model:

```swift
struct DriveLoginScreen: View {
    @StateObject private var viewModel: DriveLoginViewModel

    init(serviceUrl: String, serviceName: String, challengeId: String,
         callbackUrl: String, requestedClaims: String) {
        _viewModel = StateObject(wrappedValue: DriveLoginViewModel(
            serviceUrl: serviceUrl, serviceName: serviceName,
            challengeId: challengeId, callbackUrl: callbackUrl,
            requestedClaims: requestedClaims
        ))
    }
}
```

**Note:** The `DriveLoginScreen.init` currently doesn't take `callbackUrl`. Need to add it to `AppRouter.Route.driveLogin` as well:

```swift
case driveLogin(serviceUrl: String, serviceName: String, challengeId: String,
                callbackUrl: String, requestedClaims: String)
```

And in `ContentView.swift`:
```swift
case .driveLogin(let serviceUrl, let serviceName, let challengeId, let callbackUrl, let requestedClaims):
    DriveLoginScreen(serviceUrl: serviceUrl, serviceName: serviceName,
                     challengeId: challengeId, callbackUrl: callbackUrl,
                     requestedClaims: requestedClaims)
```

**Verify:** Deep link `ssdid://login?server_url=https://drive.ssdid.my&service_name=ssdid-drive&challenge_id=abc&callback_url=ssdid-drive://auth/callback&requested_claims=[{"key":"name","required":"true"}]` should show DriveLoginScreen with identity picker, perform real auth on "Approve", then open `ssdid-drive://auth/callback?session_token=<real-token>`.

---

## Phase 2: Drive iOS Fixes (ssdid-drive repo)

### Task 5: Align Drive QR payload and deep link to `ssdid://login?...` URL format

**Files:**
- Modify: `clients/ios/SsdidDrive/SsdidDrive/Presentation/Auth/LoginViewModel.swift`

**Why:** Drive currently serializes the backend's QR payload as raw JSON and sends `ssdid://authenticate?payload=<json>&callback=...`. The wallet expects a `ssdid://login?server_url=...&challenge_id=...` URL. Both the QR content AND the wallet deep link must be `ssdid://login?...` URL strings.

**Step 1:** Rewrite `createChallenge()` to construct a `ssdid://login?...` URL from the backend response:

```swift
func createChallenge() {
    isLoading = true
    isExpired = false
    clearError()

    Task {
        do {
            let response = try await SsdidAuthService.shared.initiateLogin()
            self.challengeId = response.challengeId

            // Build ssdid://login?... URL that wallet understands
            var components = URLComponents()
            components.scheme = "ssdid"
            components.host = "login"

            // Extract fields from the backend's qr_payload
            let qr = response.qrPayload
            var queryItems = [
                URLQueryItem(name: "server_url", value: qr["service_url"] as? String ?? SsdidAuthService.shared.baseURL),
                URLQueryItem(name: "service_name", value: qr["service_name"] as? String ?? "ssdid-drive"),
                URLQueryItem(name: "challenge_id", value: response.challengeId),
                URLQueryItem(name: "callback_url", value: "ssdid-drive://auth/callback"),
            ]

            // Include requested_claims if present
            if let claims = qr["requested_claims"],
               let claimsData = try? JSONSerialization.data(withJSONObject: claims),
               let claimsString = String(data: claimsData, encoding: .utf8) {
                queryItems.append(URLQueryItem(name: "requested_claims", value: claimsString))
            }

            components.queryItems = queryItems
            let loginUrl = components.url!

            // QR code contains the URL string (wallet scans → opens as URL)
            self.qrPayload = loginUrl.absoluteString

            // Same URL used for same-device deep link
            self.walletDeepLink = loginUrl

            self.isLoading = false

            // Listen for SSE completion
            listenForCompletion(
                challengeId: response.challengeId,
                subscriberSecret: response.subscriberSecret
            )
        } catch {
            self.handleError(error)
        }
    }
}
```

**Verify:** The QR code displayed should contain a scannable string like `ssdid://login?server_url=https://drive.ssdid.my&service_name=ssdid-drive&challenge_id=abc&callback_url=ssdid-drive://auth/callback&requested_claims=...`. Wallet should be able to scan this and route to DriveLoginScreen.

---

### Task 6: Fix Drive SSE to use pinning-aware URLSession

**Files:**
- Modify: `clients/ios/SsdidDrive/SsdidDrive/Presentation/Auth/LoginViewModel.swift`
- Modify: `clients/ios/SsdidDrive/SsdidDrive/Data/Remote/SsdidAuthService.swift`

**Why:** The SSE connection in `listenForCompletion()` uses `URLSession.shared` directly, bypassing the SSL-pinning session configured in `SsdidAuthService`.

**Step 1:** Expose the session from `SsdidAuthService`:

```swift
// In SsdidAuthService.swift, add:
/// URLSession with SSL pinning (when configured)
var urlSession: URLSession { session }
```

**Step 2:** Use it in `LoginViewModel.listenForCompletion()`:

```swift
// Change:
let (bytes, response) = try await URLSession.shared.bytes(for: request)
// To:
let (bytes, response) = try await SsdidAuthService.shared.urlSession.bytes(for: request)
```

---

### Task 7: Fix Drive associated domains to match DeepLinkParser hosts

**Files:**
- Modify: `clients/ios/SsdidDrive/SsdidDrive.entitlements`

**Why:** Entitlements declare `applinks:app.ssdid-drive.app` and `applinks:ssdid-drive.app` but `DeepLinkParser.allowedUniversalLinkHosts` has `drive.ssdid.my` and `ssdid.my`. Universal Links won't work until these match.

**Step 1:** Update entitlements to match the actual domains:

```xml
<key>com.apple.developer.associated-domains</key>
<array>
    <string>applinks:drive.ssdid.my</string>
    <string>applinks:ssdid.my</string>
</array>
```

**Note:** The `apple-app-site-association` file must be hosted at `https://drive.ssdid.my/.well-known/apple-app-site-association` and `https://ssdid.my/.well-known/apple-app-site-association` for Universal Links to work. This is a server-side deployment task.

---

## Phase 3: Protocol Documentation

### Task 8: Create shared deep link protocol spec

**Files:**
- Create: `docs/ssdid-drive-deeplink-protocol.md`

**Why:** The current state has 4 different interpretations of the deep link contract across Drive iOS, Wallet iOS, Wallet Android, and the QR scanner. A single source of truth prevents future drift.

**Content:**

```markdown
# SSDID Drive Deep Link Protocol

## Same-Device Flow (Drive → Wallet → Drive)

### Step 1: Drive opens wallet
URL: `ssdid://login?server_url=<service_url>&service_name=<name>&challenge_id=<id>&callback_url=ssdid-drive://auth/callback&requested_claims=<json>`

Parameters:
| Param | Required | Description |
|-------|----------|-------------|
| server_url | Yes | HTTPS URL of the Drive API |
| service_name | No | Human-readable service name (default: "ssdid-drive") |
| challenge_id | No | Challenge correlation ID for SSE delivery |
| callback_url | No | URL scheme to call back with session_token |
| requested_claims | No | JSON array of `[{"key":"name","required":"true"}]` |

### Step 2: Wallet calls back to Drive
URL: `ssdid-drive://auth/callback?session_token=<token>`

Parameters:
| Param | Required | Description |
|-------|----------|-------------|
| session_token | Yes | Bearer token for API authentication |

## Cross-Device Flow (QR Code + SSE)

### QR Content
Same URL string as Step 1 above. The QR code contains a `ssdid://login?...` URL.

### SSE Subscription
`GET /api/auth/ssdid/events?challenge_id=<id>&subscriber_secret=<secret>`

Events:
- `event: authenticated` / `data: {"session_token":"..."}`
- `event: timeout` / `data: {"reason":"timeout"}`
- `: keep-alive` (SSE comment, every 30s)

## URL Schemes

| App | Registered Scheme | Queries |
|-----|-------------------|---------|
| SSDID Drive | `ssdid-drive` | `ssdid` |
| SSDID Wallet | `ssdid` | `ssdid-drive` |
```

---

## Summary: Execution Order

| Phase | Task | Repo | Fixes Review IDs | Depends On |
|-------|------|------|------------------|------------|
| 1 | T1: Register `ssdid://` scheme | wallet | C1, I4, I5 | — |
| 1 | T2: Add callback/claims to DeepLinkHandler | wallet | C2, I1, M3 | — |
| 1 | T3: Route `login` to DriveLoginScreen | wallet | C3, I2, M1 | T2 |
| 1 | T4: Real auth + callback in DriveLoginScreen | wallet | C4, C5, S2 | T1, T2, T3 |
| 2 | T5: Align QR/deep link to `ssdid://login?...` | drive | C2, C3, M1 | — |
| 2 | T6: SSE pinning-aware session | drive | M2 | — |
| 2 | T7: Fix associated domains | drive | I3 | — |
| 3 | T8: Protocol spec doc | drive | S1 | T1-T7 |

**Phase 1 and Phase 2 can run in parallel** (different repos). T8 should be written last after both sides are verified working together.

**Integration test:** After all tasks, verify the complete flow:
1. Drive shows QR on login screen
2. Wallet scans QR → DriveLoginScreen appears with service info
3. User selects identity, taps "Approve"
4. Wallet authenticates with Drive backend
5. Wallet opens `ssdid-drive://auth/callback?session_token=<real-token>`
6. Drive receives token, saves to Keychain, transitions to main screen
7. (Separately) Cross-device: SSE listener receives authenticated event with token
