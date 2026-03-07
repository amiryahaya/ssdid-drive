# Registration Flow

**Version**: 1.0.0
**Status**: Draft
**Last Updated**: 2025-01

## 1. Overview

This document describes the user registration flow for SecureSharing. Registration involves identity verification, cryptographic key generation, and optional recovery share setup.

## 2. Registration Modes

SecureSharing supports two registration modes:

| Mode | Description | When Used |
|------|-------------|-----------|
| **IdP-based** | User initiates registration via identity provider | Self-service (if enabled) |
| **Invitation-based** | User receives invitation link from admin/user | Invitation-only tenants |

### Invitation-Based Registration

For tenants with invitation-only access, users receive an invitation link via email and complete registration through the invitation flow:

1. Admin creates invitation → User receives email
2. User clicks link → App validates token
3. User completes registration form → Keys generated
4. Account created with pre-assigned role

For detailed invitation flow documentation, see [Invitation Flow](./09-invitation-flow.md).

The key generation and cryptographic operations are **identical** for both modes. The difference is:
- IdP-based: User selects tenant and IdP
- Invitation-based: Tenant, role, and email are pre-determined by invitation

## 3. Prerequisites

- User has a supported identity provider (Passkey, Digital ID, or OIDC)
- Tenant has been provisioned (for enterprise users)
- Client application with crypto library (see Platform Notes below)
- **For invitation-based**: Valid, unexpired invitation token

### Platform Notes

This document provides code examples for all supported platforms. Each section shows the implementation for:

| Platform | Crypto Library | WebAuthn API | Key Storage | Notes |
|----------|---------------|--------------|-------------|-------|
| **Desktop (Rust/Tauri)** | Native Rust (`ring`, `pqcrypto`) | `webauthn-rs` | OS keychain + TPM | Production ready |
| **iOS (Swift)** | Rust via FFI | `ASAuthorizationController` | Keychain + Secure Enclave | Hardware-backed keys |
| **Android (Kotlin)** | Rust via JNI | `CredentialManager` | Keystore + StrongBox | Hardware-backed keys |

> **Note**: SecureSharing uses native clients exclusively. No web/browser client is provided. See [Architecture Overview](../specs/01-architecture-overview.md) Section 3.1 for details.

## 4. Registration Flow Diagram (IdP-based)

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                         USER REGISTRATION FLOW                               │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│  ┌─────────┐         ┌─────────┐         ┌─────────┐         ┌─────────┐   │
│  │  User   │         │ Client  │         │ Server  │         │   IdP   │   │
│  └────┬────┘         └────┬────┘         └────┬────┘         └────┬────┘   │
│       │                   │                   │                   │         │
│       │  1. Start Registration               │                   │         │
│       │──────────────────▶│                   │                   │         │
│       │                   │                   │                   │         │
│       │                   │  2. Get Tenant IdP Config            │         │
│       │                   │──────────────────▶│                   │         │
│       │                   │                   │                   │         │
│       │                   │  3. Return IdP Options               │         │
│       │                   │◀──────────────────│                   │         │
│       │                   │                   │                   │         │
│       │  4. Choose IdP    │                   │                   │         │
│       │──────────────────▶│                   │                   │         │
│       │                   │                   │                   │         │
│       │                   │  5. Initiate IdP Auth                │         │
│       │                   │──────────────────────────────────────▶│         │
│       │                   │                   │                   │         │
│       │  6. IdP Authentication (varies by provider)              │         │
│       │◀─────────────────────────────────────────────────────────▶│         │
│       │                   │                   │                   │         │
│       │                   │  7. Auth Callback │                   │         │
│       │                   │◀──────────────────────────────────────│         │
│       │                   │                   │                   │         │
│       │                   │  ┌────────────────────────────────┐  │         │
│       │                   │  │  8. CLIENT-SIDE KEY GENERATION │  │         │
│       │                   │  │                                │  │         │
│       │                   │  │  a. Generate Master Key (MK)   │  │         │
│       │                   │  │     random 256 bits            │  │         │
│       │                   │  │                                │  │         │
│       │                   │  │  b. Derive auth key from IdP   │  │         │
│       │                   │  │     - Passkey: PRF extension   │  │         │
│       │                   │  │     - OIDC: Argon2id(vault_pw) │  │         │
│       │                   │  │                                │  │         │
│       │                   │  │  c. Encrypt MK with auth key   │  │         │
│       │                   │  │     AES-256-GCM                │  │         │
│       │                   │  │                                │  │         │
│       │                   │  │  d. Generate PQC key pairs     │  │         │
│       │                   │  │     - ML-KEM-768               │  │         │
│       │                   │  │     - ML-DSA-65                │  │         │
│       │                   │  │     - KAZ-KEM                  │  │         │
│       │                   │  │     - KAZ-SIGN                 │  │         │
│       │                   │  │                                │  │         │
│       │                   │  │  e. Encrypt private keys w/ MK │  │         │
│       │                   │  │                                │  │         │
│       │                   │  │  f. Create root folder KEK     │  │         │
│       │                   │  │     - Generate random KEK      │  │         │
│       │                   │  │     - Encapsulate for user PK  │  │         │
│       │                   │  │                                │  │         │
│       │                   │  └────────────────────────────────┘  │         │
│       │                   │                   │                   │         │
│       │                   │  9. Upload Registration Bundle        │         │
│       │                   │──────────────────▶│                   │         │
│       │                   │                   │                   │         │
│       │                   │                   │  ┌─────────────┐  │         │
│       │                   │                   │  │ 10. Create: │  │         │
│       │                   │                   │  │ - User      │  │         │
│       │                   │                   │  │ - KeyBundle │  │         │
│       │                   │                   │  │ - RootFolder│  │         │
│       │                   │                   │  │ - Credential│  │         │
│       │                   │                   │  └─────────────┘  │         │
│       │                   │                   │                   │         │
│       │                   │  11. Registration Complete           │         │
│       │                   │◀──────────────────│                   │         │
│       │                   │                   │                   │         │
│       │  12. Success      │                   │                   │         │
│       │◀──────────────────│                   │                   │         │
│       │                   │                   │                   │         │
└─────────────────────────────────────────────────────────────────────────────┘
```

## 5. Detailed Steps (IdP-based)

> **API Path Convention**: Client code examples use `/api/v1/...` paths assuming the app proxies
> API requests to `https://api.securesharing.com/v1/...`. For direct API calls, remove the
> `/api/v1` prefix and use the API base URL directly.

### 5.1 Step 1-3: Tenant Discovery

```typescript
// Client requests available IdPs for tenant
// Tenant can be specified via: subdomain, X-Tenant-ID header, or X-Tenant-Slug header
const response = await fetch('/api/v1/auth/providers', {
  method: 'GET',
  headers: {
    'X-Tenant-ID': tenantId  // UUID or slug; not needed if using subdomain
  }
});

// Response
{
  "success": true,
  "data": {
    "tenant": {
      "id": "550e8400-e29b-41d4-a716-446655440000",
      "name": "Acme Corp",
      "registration_enabled": true
    },
    "providers": [
      {
        "id": "webauthn",
        "name": "Passkey",
        "type": "webauthn",
        "priority": 1
      },
      {
        "id": "mydigital",
        "name": "MyDigital ID",
        "type": "digital_id",
        "priority": 2
      },
      {
        "id": "azure-ad",
        "name": "Microsoft SSO",
        "type": "oidc",
        "priority": 3
      }
    ]
  }
}
```

### 5.2 Step 4-7: Identity Provider Authentication

#### 5.2.1 WebAuthn Registration

**Web (TypeScript)**
```typescript
// Client initiates WebAuthn registration
const optionsResponse = await fetch('/api/v1/auth/webauthn/register/options', {
  method: 'POST',
  headers: { 'Content-Type': 'application/json' },
  body: JSON.stringify({
    email: 'user@example.com',
    display_name: 'John Doe'
  })
});

const { data: options } = await optionsResponse.json();

// Create credential with PRF extension
const credential = await navigator.credentials.create({
  publicKey: {
    ...options,
    extensions: {
      prf: {
        eval: {
          first: new TextEncoder().encode("securesharing-mk-encryption")
        }
      }
    }
  }
}) as PublicKeyCredential;

// Extract PRF output for key derivation
const prfOutput = credential.getClientExtensionResults().prf?.results?.first;
if (!prfOutput) {
  throw new Error('E_PRF_NOT_SUPPORTED');
}
```

**Desktop (Rust/Tauri)**
```rust
use webauthn_rs::prelude::*;
use reqwest::Client;
use serde::{Deserialize, Serialize};

#[derive(Deserialize)]
struct RegisterOptionsResponse {
    success: bool,
    data: CreationChallengeResponse,
}

pub async fn webauthn_register(
    client: &Client,
    api_base: &str,
    email: &str,
    display_name: &str,
) -> Result<(RegisterPublicKeyCredential, Vec<u8>), Error> {
    // Get registration options from server
    let options_resp: RegisterOptionsResponse = client
        .post(format!("{}/auth/webauthn/register/options", api_base))
        .json(&serde_json::json!({
            "email": email,
            "display_name": display_name
        }))
        .send()
        .await?
        .json()
        .await?;

    // Create WebAuthn client
    let webauthn = Webauthn::builder()?
        .rp_id("securesharing.com")
        .rp_origin("https://app.securesharing.com")
        .build()?;

    // Create credential with PRF extension
    let prf_salt = b"securesharing-mk-encryption";
    let (credential, prf_output) = webauthn
        .create_credential_with_prf(
            &options_resp.data,
            prf_salt,
        )
        .await?;

    Ok((credential, prf_output))
}
```

**iOS (Swift)**
```swift
import AuthenticationServices

class WebAuthnRegistrationDelegate: NSObject,
    ASAuthorizationControllerDelegate,
    ASAuthorizationControllerPresentationContextProviding {

    private var continuation: CheckedContinuation<(ASAuthorizationPlatformPublicKeyCredentialRegistration, Data), Error>?

    func register(
        email: String,
        displayName: String
    ) async throws -> (ASAuthorizationPlatformPublicKeyCredentialRegistration, Data) {
        // Fetch registration options from server
        let optionsURL = URL(string: "\(apiBase)/auth/webauthn/register/options")!
        var request = URLRequest(url: optionsURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode([
            "email": email,
            "display_name": displayName
        ])

        let (data, _) = try await URLSession.shared.data(for: request)
        let options = try JSONDecoder().decode(WebAuthnOptionsResponse.self, from: data)

        // Create passkey registration request
        let publicKeyProvider = ASAuthorizationPlatformPublicKeyCredentialProvider(
            relyingPartyIdentifier: "securesharing.com"
        )

        let registrationRequest = publicKeyProvider.createCredentialRegistrationRequest(
            challenge: Data(base64Encoded: options.data.challenge)!,
            name: email,
            userID: Data(options.data.user.id.utf8)
        )

        // Configure PRF extension for key material
        if #available(iOS 17.0, *) {
            let prfInput = ASAuthorizationPublicKeyCredentialPRFRegistrationInput(
                inputValues: ASAuthorizationPublicKeyCredentialPRFValues(
                    saltInput1: "securesharing-mk-encryption".data(using: .utf8)!
                )
            )
            registrationRequest.prf = prfInput
        }

        // Present authorization controller
        let controller = ASAuthorizationController(authorizationRequests: [registrationRequest])
        controller.delegate = self
        controller.presentationContextProvider = self

        return try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            controller.performRequests()
        }
    }

    func authorizationController(
        controller: ASAuthorizationController,
        didCompleteWithAuthorization authorization: ASAuthorization
    ) {
        guard let credential = authorization.credential
            as? ASAuthorizationPlatformPublicKeyCredentialRegistration else {
            continuation?.resume(throwing: WebAuthnError.invalidCredentialType)
            return
        }

        // Extract PRF output
        var prfOutput = Data()
        if #available(iOS 17.0, *),
           let prfResult = credential.prf,
           let output = prfResult.first {
            prfOutput = output
        }

        continuation?.resume(returning: (credential, prfOutput))
    }

    func authorizationController(
        controller: ASAuthorizationController,
        didCompleteWithError error: Error
    ) {
        continuation?.resume(throwing: error)
    }

    func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        return UIApplication.shared.windows.first!
    }
}
```

**Android (Kotlin)**
```kotlin
import androidx.credentials.CreatePublicKeyCredentialRequest
import androidx.credentials.CredentialManager
import androidx.credentials.PublicKeyCredential
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import org.json.JSONObject

class WebAuthnRegistration(
    private val context: Context,
    private val apiClient: ApiClient
) {
    private val credentialManager = CredentialManager.create(context)

    suspend fun register(
        email: String,
        displayName: String
    ): Pair<PublicKeyCredential, ByteArray> = withContext(Dispatchers.IO) {
        // Fetch registration options from server
        val optionsResponse = apiClient.post(
            "/auth/webauthn/register/options",
            mapOf(
                "email" to email,
                "display_name" to displayName
            )
        )

        val options = optionsResponse.getJSONObject("data")

        // Add PRF extension to options
        val extensions = options.optJSONObject("extensions") ?: JSONObject()
        extensions.put("prf", JSONObject().apply {
            put("eval", JSONObject().apply {
                put("first", base64Encode("securesharing-mk-encryption".toByteArray()))
            })
        })
        options.put("extensions", extensions)

        // Create credential request
        val requestJson = options.toString()
        val request = CreatePublicKeyCredentialRequest(
            requestJson = requestJson,
            preferImmediatelyAvailableCredentials = false
        )

        // Execute credential creation
        val result = credentialManager.createCredential(
            context = context,
            request = request
        )

        val credential = result as PublicKeyCredential

        // Parse PRF output from response
        val responseJson = JSONObject(credential.authenticationResponseJson)
        val clientExtResults = responseJson.optJSONObject("clientExtensionResults")
        val prfResults = clientExtResults?.optJSONObject("prf")?.optJSONObject("results")
        val prfOutput = prfResults?.optString("first")?.let { base64Decode(it) }
            ?: throw WebAuthnException("PRF extension not supported")

        Pair(credential, prfOutput)
    }
}
```

#### 5.2.2 OIDC Registration

**Web (TypeScript)**
```typescript
// Client initiates OIDC flow - redirect to provider login
// Note: This is a GET redirect, not a POST
const providerId = 'azure-ad';
const redirectUri = encodeURIComponent('https://app.securesharing.com/auth/callback');
const state = generateCsrfState(); // Client-generated CSRF token
sessionStorage.setItem('oidc_state', state);

window.location.href = `/api/v1/auth/oidc/${providerId}/login?redirect_uri=${redirectUri}&state=${state}`;

// After IdP redirects back to callback with authorization code:
// Verify state matches to prevent CSRF
const returnedState = new URLSearchParams(window.location.search).get('state');
if (returnedState !== sessionStorage.getItem('oidc_state')) {
  throw new Error('E_CSRF_MISMATCH');
}

// User must create vault password (for OIDC without PRF)
const vaultPassword = await promptVaultPassword();
```

**Desktop (Rust/Tauri)**
```rust
use tauri::Manager;
use oauth2::{
    AuthorizationCode, CsrfToken, PkceCodeChallenge, PkceCodeVerifier,
    TokenResponse, basic::BasicClient,
};
use tokio::sync::oneshot;

pub struct OidcRegistration {
    client: BasicClient,
    pkce_verifier: Option<PkceCodeVerifier>,
}

impl OidcRegistration {
    pub async fn initiate_flow(
        &mut self,
        app_handle: &tauri::AppHandle,
    ) -> Result<String, Error> {
        // Generate PKCE challenge
        let (pkce_challenge, pkce_verifier) = PkceCodeChallenge::new_random_sha256();
        self.pkce_verifier = Some(pkce_verifier);

        // Generate authorization URL
        let (auth_url, csrf_token) = self.client
            .authorize_url(CsrfToken::new_random)
            .set_pkce_challenge(pkce_challenge)
            .add_scope(oauth2::Scope::new("openid".to_string()))
            .add_scope(oauth2::Scope::new("profile".to_string()))
            .add_scope(oauth2::Scope::new("email".to_string()))
            .url();

        // Open system browser for authentication
        open::that(auth_url.to_string())?;

        // Wait for callback via deep link (securesharing://auth/callback)
        let (tx, rx) = oneshot::channel();
        app_handle.once_global("oidc-callback", move |event| {
            let _ = tx.send(event.payload().map(String::from));
        });

        let callback_params = rx.await??;
        Ok(callback_params)
    }

    pub async fn complete_flow(
        &mut self,
        auth_code: &str,
    ) -> Result<OidcTokens, Error> {
        let verifier = self.pkce_verifier.take()
            .ok_or(Error::NoPkceVerifier)?;

        let token_response = self.client
            .exchange_code(AuthorizationCode::new(auth_code.to_string()))
            .set_pkce_verifier(verifier)
            .request_async(oauth2::reqwest::async_http_client)
            .await?;

        Ok(OidcTokens {
            access_token: token_response.access_token().secret().clone(),
            id_token: token_response.extra_fields().id_token.clone(),
        })
    }
}

// Prompt for vault password via native dialog
pub async fn prompt_vault_password(app_handle: &tauri::AppHandle) -> Result<String, Error> {
    // Emit event to show password dialog in frontend
    app_handle.emit_all("show-vault-password-dialog", ())?;

    // Wait for response
    let (tx, rx) = oneshot::channel();
    app_handle.once_global("vault-password-response", move |event| {
        let _ = tx.send(event.payload().map(String::from));
    });

    rx.await?.ok_or(Error::PasswordCancelled)
}
```

**iOS (Swift)**
```swift
import AuthenticationServices

class OidcRegistration: NSObject, ASWebAuthenticationPresentationContextProviding {
    private let apiBase: String
    private var stateToken: String?

    init(apiBase: String) {
        self.apiBase = apiBase
    }

    func initiateFlow(providerId: String) async throws -> OidcTokens {
        // Generate state for CSRF protection
        stateToken = UUID().uuidString

        // Build authorization URL
        let redirectUri = "securesharing://auth/callback"
        let loginURL = URL(string: "\(apiBase)/auth/oidc/\(providerId)/login")!
            .appending(queryItems: [
                URLQueryItem(name: "redirect_uri", value: redirectUri),
                URLQueryItem(name: "state", value: stateToken)
            ])

        // Use ASWebAuthenticationSession for secure OAuth flow
        let session = ASWebAuthenticationSession(
            url: loginURL,
            callbackURLScheme: "securesharing"
        ) { callbackURL, error in
            // Handled via continuation below
        }

        session.presentationContextProvider = self
        session.prefersEphemeralWebBrowserSession = false

        // Execute authentication flow
        let callbackURL = try await withCheckedThrowingContinuation { continuation in
            session.completionHandler = { url, error in
                if let error = error {
                    continuation.resume(throwing: error)
                } else if let url = url {
                    continuation.resume(returning: url)
                } else {
                    continuation.resume(throwing: OidcError.noCallback)
                }
            }
            session.start()
        }

        // Verify state
        guard let components = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false),
              let returnedState = components.queryItems?.first(where: { $0.name == "state" })?.value,
              returnedState == stateToken else {
            throw OidcError.stateMismatch
        }

        // Extract authorization code
        guard let code = components.queryItems?.first(where: { $0.name == "code" })?.value else {
            throw OidcError.noAuthorizationCode
        }

        return OidcTokens(authorizationCode: code)
    }

    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        return UIApplication.shared.windows.first!
    }
}

// Prompt vault password with system alert
func promptVaultPassword() async throws -> String {
    return try await withCheckedThrowingContinuation { continuation in
        DispatchQueue.main.async {
            let alert = UIAlertController(
                title: "Create Vault Password",
                message: "This password protects your encryption keys. Store it securely.",
                preferredStyle: .alert
            )

            alert.addTextField { textField in
                textField.isSecureTextEntry = true
                textField.placeholder = "Enter vault password"
            }

            alert.addTextField { textField in
                textField.isSecureTextEntry = true
                textField.placeholder = "Confirm password"
            }

            alert.addAction(UIAlertAction(title: "Cancel", style: .cancel) { _ in
                continuation.resume(throwing: OidcError.passwordCancelled)
            })

            alert.addAction(UIAlertAction(title: "Create", style: .default) { _ in
                guard let password = alert.textFields?[0].text,
                      let confirm = alert.textFields?[1].text,
                      password == confirm,
                      !password.isEmpty else {
                    continuation.resume(throwing: OidcError.passwordMismatch)
                    return
                }
                continuation.resume(returning: password)
            })

            UIApplication.shared.windows.first?.rootViewController?
                .present(alert, animated: true)
        }
    }
}
```

**Android (Kotlin)**
```kotlin
import android.content.Intent
import android.net.Uri
import androidx.browser.customtabs.CustomTabsIntent
import kotlinx.coroutines.suspendCancellableCoroutine
import java.security.SecureRandom
import java.util.Base64
import kotlin.coroutines.resume
import kotlin.coroutines.resumeWithException

class OidcRegistration(
    private val context: Context,
    private val apiBase: String
) {
    private var stateToken: String? = null
    private var codeVerifier: String? = null

    suspend fun initiateFlow(providerId: String): String {
        // Generate PKCE code verifier and challenge
        val verifier = generateCodeVerifier()
        codeVerifier = verifier
        val challenge = generateCodeChallenge(verifier)

        // Generate state for CSRF protection
        stateToken = generateSecureRandom(32)

        // Build authorization URL
        val redirectUri = "securesharing://auth/callback"
        val loginUrl = Uri.parse("$apiBase/auth/oidc/$providerId/login")
            .buildUpon()
            .appendQueryParameter("redirect_uri", redirectUri)
            .appendQueryParameter("state", stateToken)
            .appendQueryParameter("code_challenge", challenge)
            .appendQueryParameter("code_challenge_method", "S256")
            .build()

        // Launch Custom Tab for OAuth flow
        val customTabsIntent = CustomTabsIntent.Builder()
            .setShowTitle(true)
            .build()

        customTabsIntent.launchUrl(context, loginUrl)

        // Return state for later verification
        return stateToken!!
    }

    fun handleCallback(callbackUri: Uri): OidcTokens {
        // Verify state
        val returnedState = callbackUri.getQueryParameter("state")
        if (returnedState != stateToken) {
            throw OidcException("State mismatch - possible CSRF attack")
        }

        // Extract authorization code
        val code = callbackUri.getQueryParameter("code")
            ?: throw OidcException("No authorization code in callback")

        return OidcTokens(
            authorizationCode = code,
            codeVerifier = codeVerifier!!
        )
    }

    private fun generateCodeVerifier(): String {
        val bytes = ByteArray(32)
        SecureRandom().nextBytes(bytes)
        return Base64.getUrlEncoder().withoutPadding().encodeToString(bytes)
    }

    private fun generateCodeChallenge(verifier: String): String {
        val digest = java.security.MessageDigest.getInstance("SHA-256")
        val hash = digest.digest(verifier.toByteArray(Charsets.US_ASCII))
        return Base64.getUrlEncoder().withoutPadding().encodeToString(hash)
    }

    private fun generateSecureRandom(length: Int): String {
        val bytes = ByteArray(length)
        SecureRandom().nextBytes(bytes)
        return Base64.getUrlEncoder().withoutPadding().encodeToString(bytes)
    }
}

// Vault password dialog
suspend fun promptVaultPassword(activity: Activity): String =
    suspendCancellableCoroutine { continuation ->
        val dialogView = LayoutInflater.from(activity)
            .inflate(R.layout.dialog_vault_password, null)

        val passwordInput = dialogView.findViewById<EditText>(R.id.password_input)
        val confirmInput = dialogView.findViewById<EditText>(R.id.confirm_input)

        AlertDialog.Builder(activity)
            .setTitle("Create Vault Password")
            .setMessage("This password protects your encryption keys. Store it securely.")
            .setView(dialogView)
            .setPositiveButton("Create") { _, _ ->
                val password = passwordInput.text.toString()
                val confirm = confirmInput.text.toString()

                if (password.isEmpty() || password != confirm) {
                    continuation.resumeWithException(
                        OidcException("Passwords don't match")
                    )
                } else {
                    continuation.resume(password)
                }
            }
            .setNegativeButton("Cancel") { _, _ ->
                continuation.resumeWithException(
                    OidcException("Password entry cancelled")
                )
            }
            .setOnCancelListener {
                continuation.resumeWithException(
                    OidcException("Password entry cancelled")
                )
            }
            .show()
    }
```

### 5.3 Step 8: Client-Side Key Generation

**Reference Implementation (TypeScript Pseudocode)**

> **Note**: This TypeScript example serves as reference pseudocode for understanding the algorithm flow. SecureSharing uses native clients only - see Desktop/iOS/Android examples above for production implementations.

```typescript
async function generateRegistrationKeys(
  authKeyMaterial: Uint8Array,
  vaultPassword?: string
): Promise<RegistrationBundle> {

  // 8a. Generate random Master Key
  const masterKey = crypto.getRandomValues(new Uint8Array(32));

  // 8b. Derive auth encryption key
  let authKey: Uint8Array;
  if (authKeyMaterial) {
    // Passkey with PRF - derive key via HKDF
    authKey = await hkdfDerive(authKeyMaterial, "master-key-encryption", 32);
  } else {
    // OIDC - use vault password with Argon2id
    authKey = await argon2id(vaultPassword, {
      memory: 65536,
      iterations: 3,
      parallelism: 4,
      hashLength: 32
    });
  }

  // 8c. Encrypt Master Key with AES-256-GCM
  const mkNonce = crypto.getRandomValues(new Uint8Array(12));
  const encryptedMk = await aesGcmEncrypt(authKey, mkNonce, masterKey);

  // 8d. Generate PQC key pairs (via crypto provider)
  const mlKemKeyPair = await cryptoProvider.kemKeyGen('ML-KEM-768');
  const mlDsaKeyPair = await cryptoProvider.signKeyGen('ML-DSA-65');
  const kazKemKeyPair = await cryptoProvider.kemKeyGen('KAZ-KEM');
  const kazSignKeyPair = await cryptoProvider.signKeyGen('KAZ-SIGN');

  // 8e. Encrypt private keys with MK
  const encryptedPrivateKeys = {
    ml_kem: await encryptPrivateKey(masterKey, mlKemKeyPair.privateKey),
    ml_dsa: await encryptPrivateKey(masterKey, mlDsaKeyPair.privateKey),
    kaz_kem: await encryptPrivateKey(masterKey, kazKemKeyPair.privateKey),
    kaz_sign: await encryptPrivateKey(masterKey, kazSignKeyPair.privateKey)
  };

  // 8f. Create root folder KEK and metadata
  const rootKek = crypto.getRandomValues(new Uint8Array(32));
  const { wrappedKey, kemCiphertexts } = await encapsulateKey(rootKek, {
    ml_kem: mlKemKeyPair.publicKey,
    kaz_kem: kazKemKeyPair.publicKey
  });

  // 8g. Encrypt root folder metadata
  const folderMetadata = { name: 'My Vault', color: null, icon: null };
  const metadataNonce = crypto.getRandomValues(new Uint8Array(12));
  const metadataAad = new TextEncoder().encode('folder-metadata');
  const encryptedMetadata = await aesGcmEncrypt(
    rootKek, metadataNonce,
    new TextEncoder().encode(JSON.stringify(folderMetadata)),
    metadataAad
  );

  // 8h. Sign root folder creation (see crypto/05-signature-protocol.md Section 4.4)
  const createdAt = new Date().toISOString();
  const folderSignaturePayload = canonicalSerialize({
    parentId: null,  // Root folder has no parent
    encryptedMetadata: base64Encode(encryptedMetadata),
    metadataNonce: base64Encode(metadataNonce),
    ownerKeyAccess: {
      wrapped_kek: base64Encode(wrappedKey),
      kem_ciphertexts: kemCiphertexts
    },
    wrappedKek: null,  // Root folder has no parent KEK
    createdAt
  });
  const folderSignature = await combinedSign(
    mlDsaKeyPair.privateKey,
    kazSignKeyPair.privateKey,
    folderSignaturePayload
  );

  // Clear sensitive data from memory
  masterKey.fill(0);
  authKey.fill(0);
  rootKek.fill(0);

  return {
    encrypted_master_key: base64Encode(encryptedMk),
    mk_nonce: base64Encode(mkNonce),
    public_keys: {
      ml_kem: base64Encode(mlKemKeyPair.publicKey),
      ml_dsa: base64Encode(mlDsaKeyPair.publicKey),
      kaz_kem: base64Encode(kazKemKeyPair.publicKey),
      kaz_sign: base64Encode(kazSignKeyPair.publicKey)
    },
    encrypted_private_keys: encryptedPrivateKeys,
    root_folder: {
      encrypted_metadata: base64Encode(encryptedMetadata),
      metadata_nonce: base64Encode(metadataNonce),
      owner_key_access: {
        wrapped_kek: base64Encode(wrappedKey),
        kem_ciphertexts: kemCiphertexts
      },
      created_at: createdAt,
      signature: folderSignature
    }
  };
}
```

**Desktop (Rust/Tauri)**
```rust
use aes_gcm::{Aes256Gcm, KeyInit, Nonce};
use aes_gcm::aead::Aead;
use argon2::{Argon2, Params};
use hkdf::Hkdf;
use pqcrypto_mlkem::mlkem768;
use pqcrypto_mldsa::mldsa65;
use rand::{RngCore, rngs::OsRng};
use sha2::Sha384;
use zeroize::Zeroize;

// KAZ-KEM bindings (your custom Rust crate)
use kaz_crypto::{kaz_kem, kaz_sign};

pub struct RegistrationKeys {
    pub encrypted_master_key: Vec<u8>,
    pub mk_nonce: Vec<u8>,
    pub public_keys: PublicKeys,
    pub encrypted_private_keys: EncryptedPrivateKeys,
    pub root_folder_kek: RootFolderKek,
}

pub fn generate_registration_keys(
    auth_key_material: Option<&[u8]>,
    vault_password: Option<&str>,
) -> Result<RegistrationKeys, CryptoError> {
    // 8a. Generate random Master Key (256-bit)
    let mut master_key = [0u8; 32];
    OsRng.fill_bytes(&mut master_key);

    // 8b. Derive auth encryption key
    let mut auth_key = [0u8; 32];
    if let Some(prf_output) = auth_key_material {
        // Passkey with PRF - derive key via HKDF-SHA384
        let hkdf = Hkdf::<Sha384>::new(None, prf_output);
        hkdf.expand(b"master-key-encryption", &mut auth_key)
            .map_err(|_| CryptoError::HkdfExpandFailed)?;
    } else if let Some(password) = vault_password {
        // OIDC - use vault password with Argon2id
        let params = Params::new(65536, 3, 4, Some(32))
            .map_err(|_| CryptoError::Argon2ParamsFailed)?;
        let argon2 = Argon2::new(argon2::Algorithm::Argon2id, argon2::Version::V0x13, params);

        let salt = generate_salt();
        argon2.hash_password_into(password.as_bytes(), &salt, &mut auth_key)
            .map_err(|_| CryptoError::Argon2HashFailed)?;
    } else {
        return Err(CryptoError::NoAuthMaterial);
    }

    // 8c. Encrypt Master Key with AES-256-GCM
    let mut mk_nonce = [0u8; 12];
    OsRng.fill_bytes(&mut mk_nonce);

    let cipher = Aes256Gcm::new_from_slice(&auth_key)
        .map_err(|_| CryptoError::CipherInitFailed)?;
    let encrypted_mk = cipher.encrypt(Nonce::from_slice(&mk_nonce), master_key.as_ref())
        .map_err(|_| CryptoError::EncryptionFailed)?;

    // 8d. Generate PQC key pairs
    let (ml_kem_pk, ml_kem_sk) = mlkem768::keypair();
    let (ml_dsa_pk, ml_dsa_sk) = mldsa65::keypair();
    let (kaz_kem_pk, kaz_kem_sk) = kaz_kem::keypair();
    let (kaz_sign_pk, kaz_sign_sk) = kaz_sign::keypair();

    // 8e. Encrypt private keys with MK
    let encrypted_private_keys = EncryptedPrivateKeys {
        ml_kem: encrypt_private_key(&master_key, ml_kem_sk.as_bytes())?,
        ml_dsa: encrypt_private_key(&master_key, ml_dsa_sk.as_bytes())?,
        kaz_kem: encrypt_private_key(&master_key, kaz_kem_sk.as_bytes())?,
        kaz_sign: encrypt_private_key(&master_key, kaz_sign_sk.as_bytes())?,
    };

    // 8f. Create root folder KEK
    let mut root_kek = [0u8; 32];
    OsRng.fill_bytes(&mut root_kek);
    let root_folder_kek = encapsulate_key(&root_kek, &ml_kem_pk, &kaz_kem_pk)?;

    // Clear sensitive data from memory
    master_key.zeroize();
    auth_key.zeroize();
    root_kek.zeroize();

    Ok(RegistrationKeys {
        encrypted_master_key: encrypted_mk,
        mk_nonce: mk_nonce.to_vec(),
        public_keys: PublicKeys {
            ml_kem: ml_kem_pk.as_bytes().to_vec(),
            ml_dsa: ml_dsa_pk.as_bytes().to_vec(),
            kaz_kem: kaz_kem_pk.as_bytes().to_vec(),
            kaz_sign: kaz_sign_pk.as_bytes().to_vec(),
        },
        encrypted_private_keys,
        root_folder_kek,
    })
}

fn encrypt_private_key(master_key: &[u8], private_key: &[u8]) -> Result<EncryptedKey, CryptoError> {
    let mut nonce = [0u8; 12];
    OsRng.fill_bytes(&mut nonce);

    let cipher = Aes256Gcm::new_from_slice(master_key)
        .map_err(|_| CryptoError::CipherInitFailed)?;
    let ciphertext = cipher.encrypt(Nonce::from_slice(&nonce), private_key)
        .map_err(|_| CryptoError::EncryptionFailed)?;

    Ok(EncryptedKey {
        ciphertext,
        nonce: nonce.to_vec(),
    })
}

fn encapsulate_key(
    key: &[u8],
    ml_kem_pk: &mlkem768::PublicKey,
    kaz_kem_pk: &kaz_kem::PublicKey,
) -> Result<RootFolderKek, CryptoError> {
    // Encapsulate with ML-KEM-768
    let (ml_ciphertext, ml_shared_secret) = mlkem768::encapsulate(ml_kem_pk);

    // Encapsulate with KAZ-KEM
    let (kaz_ciphertext, kaz_shared_secret) = kaz_kem::encapsulate(kaz_kem_pk);

    // Combine shared secrets via HKDF
    let combined_ikm = [ml_shared_secret.as_bytes(), kaz_shared_secret.as_bytes()].concat();
    let hkdf = Hkdf::<Sha384>::new(None, &combined_ikm);
    let mut wrapping_key = [0u8; 32];
    hkdf.expand(b"kek-wrapping", &mut wrapping_key)
        .map_err(|_| CryptoError::HkdfExpandFailed)?;

    // Wrap the KEK with combined key using AES-256-KWP
    let wrapped_kek = aes_kw::wrap(&wrapping_key, key)
        .map_err(|_| CryptoError::KeyWrapFailed)?;

    Ok(RootFolderKek {
        wrapped_kek,
        kem_ciphertexts: vec![
            KemCiphertext { algorithm: "ML-KEM-768".into(), ciphertext: ml_ciphertext.as_bytes().to_vec() },
            KemCiphertext { algorithm: "KAZ-KEM".into(), ciphertext: kaz_ciphertext.as_bytes().to_vec() },
        ],
    })
}
```

**iOS (Swift)**
```swift
import Foundation
import CryptoKit
import SecureSharingCrypto  // Rust FFI wrapper

struct RegistrationKeys {
    let encryptedMasterKey: Data
    let mkNonce: Data
    let publicKeys: PublicKeys
    let encryptedPrivateKeys: EncryptedPrivateKeys
    let rootFolderKek: RootFolderKek
}

func generateRegistrationKeys(
    authKeyMaterial: Data?,
    vaultPassword: String?
) throws -> RegistrationKeys {
    // 8a. Generate random Master Key (256-bit)
    var masterKey = SymmetricKey(size: .bits256)

    // 8b. Derive auth encryption key
    let authKey: SymmetricKey
    if let prfOutput = authKeyMaterial {
        // Passkey with PRF - derive key via HKDF-SHA384
        authKey = deriveKeyHKDF(
            inputKey: prfOutput,
            info: "master-key-encryption".data(using: .utf8)!,
            outputLength: 32
        )
    } else if let password = vaultPassword {
        // OIDC - use vault password with Argon2id (via Rust FFI)
        let salt = generateSecureRandom(length: 16)
        let derivedKey = SecureSharingCrypto.argon2id(
            password: password,
            salt: salt,
            memory: 65536,
            iterations: 3,
            parallelism: 4,
            hashLength: 32
        )
        authKey = SymmetricKey(data: derivedKey)
    } else {
        throw RegistrationError.noAuthMaterial
    }

    // 8c. Encrypt Master Key with AES-256-GCM
    let mkNonce = AES.GCM.Nonce()
    let sealedMasterKey = try AES.GCM.seal(
        masterKey.withUnsafeBytes { Data($0) },
        using: authKey,
        nonce: mkNonce
    )
    let encryptedMk = sealedMasterKey.combined!

    // 8d. Generate PQC key pairs (via Rust FFI)
    let mlKemKeyPair = SecureSharingCrypto.mlKem768KeyGen()
    let mlDsaKeyPair = SecureSharingCrypto.mlDsa65KeyGen()
    let kazKemKeyPair = SecureSharingCrypto.kazKemKeyGen()
    let kazSignKeyPair = SecureSharingCrypto.kazSignKeyGen()

    // 8e. Encrypt private keys with MK
    let encryptedPrivateKeys = EncryptedPrivateKeys(
        mlKem: try encryptPrivateKey(masterKey: masterKey, privateKey: mlKemKeyPair.privateKey),
        mlDsa: try encryptPrivateKey(masterKey: masterKey, privateKey: mlDsaKeyPair.privateKey),
        kazKem: try encryptPrivateKey(masterKey: masterKey, privateKey: kazKemKeyPair.privateKey),
        kazSign: try encryptPrivateKey(masterKey: masterKey, privateKey: kazSignKeyPair.privateKey)
    )

    // 8f. Create root folder KEK
    let rootKek = SymmetricKey(size: .bits256)
    let rootFolderKek = try encapsulateKey(
        key: rootKek,
        mlKemPublicKey: mlKemKeyPair.publicKey,
        kazKemPublicKey: kazKemKeyPair.publicKey
    )

    return RegistrationKeys(
        encryptedMasterKey: encryptedMk,
        mkNonce: Data(mkNonce),
        publicKeys: PublicKeys(
            mlKem: mlKemKeyPair.publicKey,
            mlDsa: mlDsaKeyPair.publicKey,
            kazKem: kazKemKeyPair.publicKey,
            kazSign: kazSignKeyPair.publicKey
        ),
        encryptedPrivateKeys: encryptedPrivateKeys,
        rootFolderKek: rootFolderKek
    )
}

private func encryptPrivateKey(masterKey: SymmetricKey, privateKey: Data) throws -> EncryptedKey {
    let nonce = AES.GCM.Nonce()
    let sealed = try AES.GCM.seal(privateKey, using: masterKey, nonce: nonce)

    return EncryptedKey(
        ciphertext: sealed.ciphertext + sealed.tag,
        nonce: Data(nonce)
    )
}

private func encapsulateKey(
    key: SymmetricKey,
    mlKemPublicKey: Data,
    kazKemPublicKey: Data
) throws -> RootFolderKek {
    // Encapsulate with ML-KEM-768 (via Rust FFI)
    let mlResult = SecureSharingCrypto.mlKem768Encapsulate(publicKey: mlKemPublicKey)

    // Encapsulate with KAZ-KEM (via Rust FFI)
    let kazResult = SecureSharingCrypto.kazKemEncapsulate(publicKey: kazKemPublicKey)

    // Combine shared secrets via HKDF
    let combinedIkm = mlResult.sharedSecret + kazResult.sharedSecret
    let wrappingKey = deriveKeyHKDF(
        inputKey: combinedIkm,
        info: "kek-wrapping".data(using: .utf8)!,
        outputLength: 32
    )

    // Wrap the KEK with AES-256-KWP
    let keyData = key.withUnsafeBytes { Data($0) }
    let wrappedKek = SecureSharingCrypto.aesKeyWrap(key: wrappingKey, data: keyData)

    return RootFolderKek(
        wrappedKek: wrappedKek,
        kemCiphertexts: [
            KemCiphertext(algorithm: "ML-KEM-768", ciphertext: mlResult.ciphertext),
            KemCiphertext(algorithm: "KAZ-KEM", ciphertext: kazResult.ciphertext)
        ]
    )
}

private func deriveKeyHKDF(inputKey: Data, info: Data, outputLength: Int) -> SymmetricKey {
    let key = SymmetricKey(data: inputKey)
    var derivedKey = Data(count: outputLength)

    derivedKey.withUnsafeMutableBytes { derivedKeyPtr in
        info.withUnsafeBytes { infoPtr in
            HKDF<SHA384>.deriveKey(
                inputKeyMaterial: key,
                info: infoPtr,
                outputByteCount: outputLength
            ).withUnsafeBytes { ptr in
                derivedKeyPtr.copyMemory(from: ptr)
            }
        }
    }

    return SymmetricKey(data: derivedKey)
}
```

**Android (Kotlin)**
```kotlin
import java.security.SecureRandom
import javax.crypto.Cipher
import javax.crypto.spec.GCMParameterSpec
import javax.crypto.spec.SecretKeySpec

// Rust JNI bindings for PQC crypto
import com.securesharing.crypto.NativeCrypto

data class RegistrationKeys(
    val encryptedMasterKey: ByteArray,
    val mkNonce: ByteArray,
    val publicKeys: PublicKeys,
    val encryptedPrivateKeys: EncryptedPrivateKeys,
    val rootFolderKek: RootFolderKek
)

class KeyGenerator(
    private val nativeCrypto: NativeCrypto
) {
    private val secureRandom = SecureRandom()

    fun generateRegistrationKeys(
        authKeyMaterial: ByteArray?,
        vaultPassword: String?
    ): RegistrationKeys {
        // 8a. Generate random Master Key (256-bit)
        val masterKey = ByteArray(32)
        secureRandom.nextBytes(masterKey)

        // 8b. Derive auth encryption key
        val authKey: ByteArray = when {
            authKeyMaterial != null -> {
                // Passkey with PRF - derive key via HKDF-SHA384
                nativeCrypto.hkdfSha384(
                    ikm = authKeyMaterial,
                    salt = null,
                    info = "master-key-encryption".toByteArray(),
                    length = 32
                )
            }
            vaultPassword != null -> {
                // OIDC - use vault password with Argon2id
                val salt = ByteArray(16).also { secureRandom.nextBytes(it) }
                nativeCrypto.argon2id(
                    password = vaultPassword.toByteArray(),
                    salt = salt,
                    memory = 65536,
                    iterations = 3,
                    parallelism = 4,
                    hashLength = 32
                )
            }
            else -> throw IllegalArgumentException("No auth material provided")
        }

        // 8c. Encrypt Master Key with AES-256-GCM
        val mkNonce = ByteArray(12).also { secureRandom.nextBytes(it) }
        val encryptedMk = encryptAesGcm(authKey, mkNonce, masterKey)

        // 8d. Generate PQC key pairs (via Rust JNI)
        val mlKemKeyPair = nativeCrypto.mlKem768KeyGen()
        val mlDsaKeyPair = nativeCrypto.mlDsa65KeyGen()
        val kazKemKeyPair = nativeCrypto.kazKemKeyGen()
        val kazSignKeyPair = nativeCrypto.kazSignKeyGen()

        // 8e. Encrypt private keys with MK
        val encryptedPrivateKeys = EncryptedPrivateKeys(
            mlKem = encryptPrivateKey(masterKey, mlKemKeyPair.privateKey),
            mlDsa = encryptPrivateKey(masterKey, mlDsaKeyPair.privateKey),
            kazKem = encryptPrivateKey(masterKey, kazKemKeyPair.privateKey),
            kazSign = encryptPrivateKey(masterKey, kazSignKeyPair.privateKey)
        )

        // 8f. Create root folder KEK
        val rootKek = ByteArray(32).also { secureRandom.nextBytes(it) }
        val rootFolderKek = encapsulateKey(
            rootKek,
            mlKemKeyPair.publicKey,
            kazKemKeyPair.publicKey
        )

        // Clear sensitive data from memory
        masterKey.fill(0)
        authKey.fill(0)
        rootKek.fill(0)

        return RegistrationKeys(
            encryptedMasterKey = encryptedMk,
            mkNonce = mkNonce,
            publicKeys = PublicKeys(
                mlKem = mlKemKeyPair.publicKey,
                mlDsa = mlDsaKeyPair.publicKey,
                kazKem = kazKemKeyPair.publicKey,
                kazSign = kazSignKeyPair.publicKey
            ),
            encryptedPrivateKeys = encryptedPrivateKeys,
            rootFolderKek = rootFolderKek
        )
    }

    private fun encryptAesGcm(key: ByteArray, nonce: ByteArray, plaintext: ByteArray): ByteArray {
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        val keySpec = SecretKeySpec(key, "AES")
        val gcmSpec = GCMParameterSpec(128, nonce)  // 128-bit tag

        cipher.init(Cipher.ENCRYPT_MODE, keySpec, gcmSpec)
        return cipher.doFinal(plaintext)
    }

    private fun encryptPrivateKey(masterKey: ByteArray, privateKey: ByteArray): EncryptedKey {
        val nonce = ByteArray(12).also { secureRandom.nextBytes(it) }
        val ciphertext = encryptAesGcm(masterKey, nonce, privateKey)

        return EncryptedKey(
            ciphertext = ciphertext,
            nonce = nonce
        )
    }

    private fun encapsulateKey(
        key: ByteArray,
        mlKemPublicKey: ByteArray,
        kazKemPublicKey: ByteArray
    ): RootFolderKek {
        // Encapsulate with ML-KEM-768 (via Rust JNI)
        val mlResult = nativeCrypto.mlKem768Encapsulate(mlKemPublicKey)

        // Encapsulate with KAZ-KEM (via Rust JNI)
        val kazResult = nativeCrypto.kazKemEncapsulate(kazKemPublicKey)

        // Combine shared secrets via HKDF
        val combinedIkm = mlResult.sharedSecret + kazResult.sharedSecret
        val wrappingKey = nativeCrypto.hkdfSha384(
            ikm = combinedIkm,
            salt = null,
            info = "kek-wrapping".toByteArray(),
            length = 32
        )

        // Wrap the KEK with AES-256-KWP
        val wrappedKek = nativeCrypto.aesKeyWrap(wrappingKey, key)

        // Clear sensitive data
        combinedIkm.fill(0)
        wrappingKey.fill(0)

        return RootFolderKek(
            wrappedKek = wrappedKek,
            kemCiphertexts = listOf(
                KemCiphertext(algorithm = "ML-KEM-768", ciphertext = mlResult.ciphertext),
                KemCiphertext(algorithm = "KAZ-KEM", ciphertext = kazResult.ciphertext)
            )
        )
    }
}
```

### 5.4 Step 9: Upload Registration Bundle

The registration completion endpoint is **provider-specific**:

- WebAuthn: `POST /api/v1/auth/webauthn/register/complete`
- OIDC: `POST /api/v1/auth/oidc/register/complete`

#### WebAuthn Registration Complete

```http
POST /api/v1/auth/webauthn/register/complete
Content-Type: application/json

{
  "tenant_id": "550e8400-e29b-41d4-a716-446655440000",
  "credential": {
    "id": "base64url...",
    "rawId": "base64url...",
    "type": "public-key",
    "response": {
      "clientDataJSON": "base64url...",
      "attestationObject": "base64url..."
    },
    "clientExtensionResults": {
      "prf": {
        "enabled": true
      }
    }
  },
  "user_registration": {
    "email": "user@example.com",
    "display_name": "John Doe",
    "public_keys": {
      "ml_kem": "base64...",
      "ml_dsa": "base64...",
      "kaz_kem": "base64...",
      "kaz_sign": "base64..."
    },
    "encrypted_master_key": "base64...",
    "mk_nonce": "base64...",
    "encrypted_private_keys": {
      "ml_kem": {"ciphertext": "base64...", "nonce": "base64..."},
      "ml_dsa": {"ciphertext": "base64...", "nonce": "base64..."},
      "kaz_kem": {"ciphertext": "base64...", "nonce": "base64..."},
      "kaz_sign": {"ciphertext": "base64...", "nonce": "base64..."}
    }
  },
  "root_folder": {
    "encrypted_metadata": "base64...",
    "metadata_nonce": "base64...",
    "owner_key_access": {
      "wrapped_kek": "base64...",
      "kem_ciphertexts": [
        {"algorithm": "ML-KEM-768", "ciphertext": "base64..."},
        {"algorithm": "KAZ-KEM", "ciphertext": "base64..."}
      ]
    },
    "created_at": "2025-01-15T10:30:00.000Z",
    "signature": {
      "ml_dsa": "base64...",
      "kaz_sign": "base64..."
    }
  }
}
```

#### OIDC Registration Complete

For new users authenticated via OIDC, after the callback returns `status: "new_user"`:

```http
POST /api/v1/auth/oidc/register/complete
Content-Type: application/json

{
  "registration_token": "temp_token_from_callback",
  "vault_password_salt": "base64...",
  "user_registration": {
    "display_name": "John Doe",
    "public_keys": {
      "ml_kem": "base64...",
      "ml_dsa": "base64...",
      "kaz_kem": "base64...",
      "kaz_sign": "base64..."
    },
    "encrypted_master_key": "base64...",
    "mk_nonce": "base64...",
    "encrypted_private_keys": {
      "ml_kem": {"ciphertext": "base64...", "nonce": "base64..."},
      "ml_dsa": {"ciphertext": "base64...", "nonce": "base64..."},
      "kaz_kem": {"ciphertext": "base64...", "nonce": "base64..."},
      "kaz_sign": {"ciphertext": "base64...", "nonce": "base64..."}
    }
  },
  "root_folder": {
    "encrypted_metadata": "base64...",
    "metadata_nonce": "base64...",
    "owner_key_access": {
      "wrapped_kek": "base64...",
      "kem_ciphertexts": [
        {"algorithm": "ML-KEM-768", "ciphertext": "base64..."},
        {"algorithm": "KAZ-KEM", "ciphertext": "base64..."}
      ]
    },
    "created_at": "2025-01-15T10:30:00.000Z",
    "signature": {
      "ml_dsa": "base64...",
      "kaz_sign": "base64..."
    }
  }
}
```

### 5.5 Step 10-12: Server Processing

```typescript
// Server-side processing (conceptual)
async function completeRegistration(request: RegistrationRequest) {
  // Validate credential with IdP
  const credentialValid = await validateCredential(request.credential);
  if (!credentialValid) {
    throw new Error('E_INVALID_CREDENTIAL');
  }

  // Create user in transaction
  return await db.transaction(async (tx) => {
    // Create user
    const user = await tx.users.create({
      tenant_id: request.tenant_id,
      email: request.email,
      display_name: request.display_name,
      status: 'active'
    });

    // Store key bundle
    await tx.keyBundles.create({
      user_id: user.id,
      encrypted_master_key: request.key_bundle.encrypted_master_key,
      mk_nonce: request.key_bundle.mk_nonce,
      public_keys: request.key_bundle.public_keys,
      encrypted_private_keys: request.key_bundle.encrypted_private_keys
    });

    // Store credential
    await tx.credentials.create({
      user_id: user.id,
      type: request.credential.type,
      credential_id: request.credential.id,
      public_key: extractPublicKey(request.credential)
    });

    // Verify root folder signature before storing
    const signatureValid = await verifyFolderSignature(
      request.key_bundle.public_keys,
      request.root_folder.signature,
      {
        parentId: null,
        encryptedMetadata: request.root_folder.encrypted_metadata,
        metadataNonce: request.root_folder.metadata_nonce,
        ownerKeyAccess: request.root_folder.owner_key_access,
        wrappedKek: null,
        createdAt: request.root_folder.created_at
      }
    );
    if (!signatureValid) {
      throw new Error('E_SIGNATURE_INVALID');
    }

    // Create root folder
    const rootFolder = await tx.folders.create({
      owner_id: user.id,
      parent_id: null,
      is_root: true,
      encrypted_metadata: request.root_folder.encrypted_metadata,
      metadata_nonce: request.root_folder.metadata_nonce,
      owner_key_access: request.root_folder.owner_key_access,
      wrapped_kek: null,  // Root folder has no parent KEK
      signature: request.root_folder.signature,
      created_at: request.root_folder.created_at
    });

    // Issue session token
    const session = await createSession(user);

    return {
      user,
      root_folder: rootFolder,
      session
    };
  });
}
```

### 5.6 Server Response Format

After successful registration, the server returns the following response:

```http
HTTP/1.1 201 Created
Content-Type: application/json

{
  "success": true,
  "data": {
    "user": {
      "id": "550e8400-e29b-41d4-a716-446655440000",
      "email": "user@example.com",
      "display_name": "John Doe",
      "tenant_id": "660e8400-e29b-41d4-a716-446655440000",
      "status": "active",
      "created_at": "2025-01-15T10:30:00Z",
      "updated_at": "2025-01-15T10:30:00Z"
    },
    "root_folder": {
      "id": "770e8400-e29b-41d4-a716-446655440000",
      "is_root": true,
      "created_at": "2025-01-15T10:30:00Z"
    },
    "session": {
      "access_token": "eyJhbGciOiJFZERTQSIsInR5cCI6IkpXVCJ9...",
      "token_type": "Bearer",
      "expires_in": 3600,
      "expires_at": "2025-01-15T11:30:00Z",
      "refresh_token": "dGhpcyBpcyBhIHJlZnJlc2ggdG9rZW4..."
    }
  }
}
```

#### Response Fields

| Field | Type | Description |
|-------|------|-------------|
| `user.id` | UUID | Unique identifier for the created user |
| `user.email` | string | User's email address |
| `user.display_name` | string | User's display name |
| `user.tenant_id` | UUID | Tenant the user belongs to |
| `user.status` | string | Account status (`active`, `pending`, `suspended`) |
| `user.created_at` | ISO 8601 | Account creation timestamp |
| `root_folder.id` | UUID | User's root folder identifier |
| `root_folder.is_root` | boolean | Always `true` for root folder |
| `session.access_token` | string | JWT for API authentication |
| `session.token_type` | string | Always `Bearer` |
| `session.expires_in` | number | Token validity in seconds |
| `session.expires_at` | ISO 8601 | Token expiration timestamp |
| `session.refresh_token` | string | Token for obtaining new access tokens |

#### Zero-Knowledge Guarantee

The server response intentionally **does NOT include**:

| Data | Reason |
|------|--------|
| Master Key | Generated client-side, never sent to server in plaintext |
| Private Keys | Generated client-side, only encrypted versions stored |
| Root Folder KEK | Generated client-side, wrapped version stored on server |
| Decrypted Metadata | Server only stores encrypted metadata |

The server stores only encrypted blobs and public keys. All cryptographic secrets remain exclusively in client memory.

## 6. Optional: Recovery Share Setup

After registration, users may optionally set up recovery shares.

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                    RECOVERY SHARE SETUP (Optional)                           │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│  ┌─────────┐         ┌─────────┐         ┌─────────┐                        │
│  │  User   │         │ Client  │         │ Server  │                        │
│  └────┬────┘         └────┬────┘         └────┬────┘                        │
│       │                   │                   │                              │
│       │  1. Setup Recovery│                   │                              │
│       │──────────────────▶│                   │                              │
│       │                   │                   │                              │
│       │  2. Select Trustees (k=3, n=5)        │                              │
│       │──────────────────▶│                   │                              │
│       │                   │                   │                              │
│       │                   │  3. Fetch Trustee Public Keys                    │
│       │                   │──────────────────▶│                              │
│       │                   │                   │                              │
│       │                   │  4. Return Public Keys                           │
│       │                   │◀──────────────────│                              │
│       │                   │                   │                              │
│       │                   │  ┌────────────────────────────────┐              │
│       │                   │  │  5. CLIENT-SIDE OPERATIONS     │              │
│       │                   │  │                                │              │
│       │                   │  │  a. Split MK using Shamir      │              │
│       │                   │  │     (k=3, n=5)                 │              │
│       │                   │  │                                │              │
│       │                   │  │  b. For each share:            │              │
│       │                   │  │     - Encapsulate for trustee  │              │
│       │                   │  │     - Sign share assignment    │              │
│       │                   │  │                                │              │
│       │                   │  └────────────────────────────────┘              │
│       │                   │                   │                              │
│       │                   │  6. Upload Encrypted Shares                      │
│       │                   │──────────────────▶│                              │
│       │                   │                   │                              │
│       │                   │                   │  ┌─────────────┐             │
│       │                   │                   │  │ 7. Store    │             │
│       │                   │                   │  │ shares and  │             │
│       │                   │                   │  │ notify      │             │
│       │                   │                   │  │ trustees    │             │
│       │                   │                   │  └─────────────┘             │
│       │                   │                   │                              │
│       │                   │  8. Setup Complete│                              │
│       │                   │◀──────────────────│                              │
│       │                   │                   │                              │
└─────────────────────────────────────────────────────────────────────────────┘
```

### Recovery Share Generation

```typescript
async function setupRecoveryShares(
  masterKey: Uint8Array,
  trustees: TrusteeInfo[],
  threshold: number = 3
): Promise<RecoveryShareBundle[]> {

  // Split MK into shares
  const shares = shamirSplit(masterKey, trustees.length, threshold);

  // Encrypt each share for its trustee
  const shareBundle: RecoveryShareBundle[] = [];

  for (let i = 0; i < trustees.length; i++) {
    const trustee = trustees[i];
    const share = shares[i];

    // Encapsulate share for trustee's public keys
    const { wrappedKey, kemCiphertexts } = await encapsulateKey(
      share.value,
      trustee.publicKeys
    );

    // Sign the share assignment
    const message = canonicalize({
      share_index: share.index,
      trustee_id: trustee.id,
      wrapped_value: wrappedKey
    });

    const signature = await combinedSign(userPrivateKeys, message);

    shareBundle.push({
      trustee_id: trustee.id,
      share_index: share.index,
      encrypted_share: {
        wrapped_value: base64Encode(wrappedKey),
        kem_ciphertexts: kemCiphertexts
      },
      signature: signature
    });
  }

  return shareBundle;
}
```

## 7. Security Considerations

### 7.1 Key Material Protection

- Master Key is generated using CSPRNG
- MK is encrypted before leaving client memory
- Private keys are individually encrypted
- All sensitive material is cleared from memory after use

### 7.2 IdP Security

- WebAuthn provides hardware-bound authentication
- PRF extension provides unique key material per credential
- OIDC requires additional vault password for key derivation
- Digital ID uses certificate-based verification

### 7.3 Server Trust Model

- Server never sees plaintext MK or private keys
- Server stores only encrypted blobs
- Public keys are verifiable but not sensitive
- Registration can be verified without decryption

## 8. Error Handling

| Error Code | Cause | Recovery |
|------------|-------|----------|
| `E_TENANT_NOT_FOUND` | Invalid tenant | Verify tenant ID/slug |
| `E_REGISTRATION_DISABLED` | Tenant disabled registration | Contact admin |
| `E_EMAIL_EXISTS` | Email already registered | Login instead |
| `E_CREDENTIAL_INVALID` | WebAuthn verification failed | Retry registration |
| `E_PRF_NOT_SUPPORTED` | Authenticator doesn't support PRF | Use vault password fallback |
| `E_WEAK_PASSWORD` | Vault password too weak | Choose stronger password |

## 9. Client State After Registration

```typescript
interface PostRegistrationState {
  // Session
  session: {
    token: string;
    expires_at: string;
  };

  // User
  user: {
    id: string;
    email: string;
    tenant_id: string;
  };

  // In-memory keys (cleared on logout/close)
  keys: {
    masterKey: Uint8Array;
    privateKeys: {
      ml_kem: Uint8Array;
      ml_dsa: Uint8Array;
      kaz_kem: Uint8Array;
      kaz_sign: Uint8Array;
    };
  };

  // Root folder access
  rootFolder: {
    id: string;
    kek: Uint8Array;  // Decrypted root KEK
  };
}
```

## 10. Related Documentation

- [Invitation Flow](./09-invitation-flow.md) - Invitation-based user onboarding
- [Login Flow](./02-login-flow.md) - Authentication and key derivation
- [Invitations API](../api/09-invitations.md) - Invitation API specification
- [Invitation System Design](../design/invitation-system.md) - Full design document
- [Key Hierarchy](../crypto/02-key-hierarchy.md) - Key derivation details
