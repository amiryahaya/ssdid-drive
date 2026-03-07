# Login Flow

**Version**: 1.0.0
**Status**: Draft
**Last Updated**: 2025-01

## 1. Overview

This document describes the user login flow for SecureSharing. Login involves identity verification, key bundle retrieval, and client-side key decryption.

## 2. Prerequisites

- User has completed registration
- User has access to their registered credential (Passkey, Digital ID, or OIDC account)
- Client application with crypto library (see Platform Notes below)

### Platform Notes

This document provides **native code examples for all supported platforms**:

| Platform | Language | Auth API | Key Storage | Crypto |
|----------|----------|----------|-------------|--------|
| **Desktop** | Rust (Tauri) | `webauthn-rs` | OS Keychain/DPAPI + TPM | Native Rust |
| **iOS** | Swift | `AuthenticationServices` | Keychain + Secure Enclave | Rust FFI |
| **Android** | Kotlin | `Fido2ApiClient` | Keystore + StrongBox | Rust JNI |

> **Note**: SecureSharing uses native clients exclusively. No web/browser client is provided. See [Architecture Overview](../specs/01-architecture-overview.md) Section 3.1.

> **API Path Convention**: Client code examples use `/api/v1/...` paths assuming the app proxies
> API requests to `https://api.securesharing.com/v1/...`. For direct API calls, remove the
> `/api/v1` prefix and use the API base URL directly.

## 3. Login Flow Diagram

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                            USER LOGIN FLOW                                   │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│  ┌─────────┐         ┌─────────┐         ┌─────────┐         ┌─────────┐   │
│  │  User   │         │ Client  │         │ Server  │         │   IdP   │   │
│  └────┬────┘         └────┬────┘         └────┬────┘         └────┬────┘   │
│       │                   │                   │                   │         │
│       │  1. Start Login   │                   │                   │         │
│       │──────────────────▶│                   │                   │         │
│       │                   │                   │                   │         │
│       │                   │  2. Get Tenant IdP Config            │         │
│       │                   │──────────────────▶│                   │         │
│       │                   │                   │                   │         │
│       │                   │  3. Return IdP Options               │         │
│       │                   │◀──────────────────│                   │         │
│       │                   │                   │                   │         │
│       │  4. Choose IdP /  │                   │                   │         │
│       │     Enter Email   │                   │                   │         │
│       │──────────────────▶│                   │                   │         │
│       │                   │                   │                   │         │
│       │                   │  5. Initiate Auth (if needed)        │         │
│       │                   │──────────────────────────────────────▶│         │
│       │                   │                   │                   │         │
│       │  6. Authenticate with IdP                                │         │
│       │◀─────────────────────────────────────────────────────────▶│         │
│       │                   │                   │                   │         │
│       │                   │  7. Complete Login                   │         │
│       │                   │──────────────────▶│                   │         │
│       │                   │                   │                   │         │
│       │                   │  8. Session + Key Bundle             │         │
│       │                   │◀──────────────────│                   │         │
│       │                   │                   │                   │         │
│       │                   │  ┌────────────────────────────────┐  │         │
│       │                   │  │  9. CLIENT-SIDE DECRYPTION     │  │         │
│       │                   │  │                                │  │         │
│       │                   │  │  a. Derive auth key from IdP   │  │         │
│       │                   │  │     material / vault password  │  │         │
│       │                   │  │                                │  │         │
│       │                   │  │  b. Decrypt Master Key         │  │         │
│       │                   │  │                                │  │         │
│       │                   │  │  c. Decrypt private keys       │  │         │
│       │                   │  │     using MK                   │  │         │
│       │                   │  │                                │  │         │
│       │                   │  │  d. Store keys in memory       │  │         │
│       │                   │  │                                │  │         │
│       │                   │  └────────────────────────────────┘  │         │
│       │                   │                   │                   │         │
│       │  10. Login Complete                   │                   │         │
│       │◀──────────────────│                   │                   │         │
│       │                   │                   │                   │         │
└─────────────────────────────────────────────────────────────────────────────┘
```

**Key Points**:
- Step 7-8: Login completion returns **both session token AND key bundle** in a single response
- No separate API call needed for key bundle retrieval
- No separate auth_token → session_token exchange

## 4. Detailed Steps

### 4.1 Step 1-4: IdP Selection

#### Web (TypeScript)

```typescript
const response = await fetch('/api/v1/auth/providers', {
  method: 'GET',
  headers: { 'X-Tenant-ID': tenantId }
});
const { data: { providers } } = await response.json();
const selectedProvider = await userSelectProvider(providers);
```

#### Desktop (Rust/Tauri)

```rust
use reqwest::Client;
use serde::Deserialize;

#[derive(Deserialize)]
struct ProvidersResponse {
    data: ProvidersData,
}

#[derive(Deserialize)]
struct ProvidersData {
    providers: Vec<IdpProvider>,
}

async fn get_providers(client: &Client, tenant_id: &str) -> Result<Vec<IdpProvider>> {
    let response: ProvidersResponse = client
        .get(format!("{}/auth/providers", API_BASE))
        .header("X-Tenant-ID", tenant_id)
        .send()
        .await?
        .json()
        .await?;
    Ok(response.data.providers)
}
```

#### iOS (Swift)

```swift
func getProviders(tenantId: String) async throws -> [IdpProvider] {
    var request = URLRequest(url: URL(string: "\(apiBase)/auth/providers")!)
    request.setValue(tenantId, forHTTPHeaderField: "X-Tenant-ID")

    let (data, _) = try await URLSession.shared.data(for: request)
    let response = try JSONDecoder().decode(ProvidersResponse.self, from: data)
    return response.data.providers
}
```

#### Android (Kotlin)

```kotlin
suspend fun getProviders(tenantId: String): List<IdpProvider> {
    val response = httpClient.get("$apiBase/auth/providers") {
        header("X-Tenant-ID", tenantId)
    }
    return response.body<ProvidersResponse>().data.providers
}
```

### 4.2 Step 5-7: Identity Provider Authentication

#### 4.2.1 WebAuthn Login

##### Web (TypeScript)

```typescript
// Get authentication options from server
const optionsResponse = await fetch('/api/v1/auth/webauthn/login/options', {
  method: 'POST',
  headers: { 'Content-Type': 'application/json' },
  body: JSON.stringify({ email: 'user@example.com' })
});
const { data: options } = await optionsResponse.json();

// Authenticate with PRF extension for key material
const assertion = await navigator.credentials.get({
  publicKey: {
    ...options,
    extensions: {
      prf: { eval: { first: new TextEncoder().encode("securesharing-mk-encryption") } }
    }
  }
});

// Extract PRF output (used to decrypt master key)
const prfOutput = assertion.getClientExtensionResults().prf?.results?.first;
if (!prfOutput) throw new Error('PRF extension not supported');

// Complete login - returns session + key bundle
const loginResponse = await fetch('/api/v1/auth/webauthn/login/complete', {
  method: 'POST',
  headers: { 'Content-Type': 'application/json' },
  body: JSON.stringify({
    tenant_id: tenantId,
    credential: {
      id: assertion.id,
      rawId: base64Encode(assertion.rawId),
      type: 'public-key',
      response: {
        clientDataJSON: base64Encode(assertion.response.clientDataJSON),
        authenticatorData: base64Encode(assertion.response.authenticatorData),
        signature: base64Encode(assertion.response.signature),
        userHandle: base64Encode(assertion.response.userHandle)
      },
      clientExtensionResults: { prf: { results: { first: base64Encode(prfOutput) } } }
    }
  })
});
const { data: { user, session, key_bundle } } = await loginResponse.json();
```

##### Desktop (Rust/Tauri)

```rust
use webauthn_rs::prelude::*;
use tauri::State;

#[tauri::command]
async fn webauthn_login(
    email: String,
    tenant_id: String,
    http: State<'_, HttpClient>,
) -> Result<LoginResult, Error> {
    // Get authentication options from server
    let options: WebAuthnOptions = http
        .post(format!("{}/auth/webauthn/login/options", API_BASE))
        .json(&serde_json::json!({ "email": email }))
        .send().await?
        .json().await?;

    // Create WebAuthn authenticator with PRF extension
    let mut authenticator = WebAuthnAuthenticator::new();
    authenticator.set_prf_input(b"securesharing-mk-encryption");

    // Perform authentication (triggers system UI)
    let assertion = authenticator
        .get_assertion(&options.public_key)
        .await
        .map_err(|e| Error::WebAuthn(e))?;

    // Extract PRF output for key derivation
    let prf_output = assertion.prf_output
        .ok_or(Error::PrfNotSupported)?;

    // Complete login with server
    let login_response: LoginResponse = http
        .post(format!("{}/auth/webauthn/login/complete", API_BASE))
        .json(&CompleteLoginRequest {
            tenant_id,
            credential: assertion.into(),
        })
        .send().await?
        .json().await?;

    Ok(LoginResult {
        user: login_response.data.user,
        session: login_response.data.session,
        key_bundle: login_response.data.key_bundle,
        prf_output,  // Passed to key decryption
    })
}
```

##### iOS (Swift)

```swift
import AuthenticationServices

class WebAuthnLoginController: NSObject, ASAuthorizationControllerDelegate {
    private var continuation: CheckedContinuation<ASAuthorizationResult, Error>?
    private let apiClient: APIClient

    func login(email: String, tenantId: String) async throws -> LoginResult {
        // Get authentication options from server
        let options = try await apiClient.getWebAuthnLoginOptions(email: email)

        // Create platform credential request with PRF
        let provider = ASAuthorizationPlatformPublicKeyCredentialProvider(
            relyingPartyIdentifier: options.rpId
        )
        let request = provider.createCredentialAssertionRequest(
            challenge: options.challenge
        )

        // Add PRF extension for key material
        if #available(iOS 17.0, *) {
            request.prf = ASAuthorizationPublicKeyCredentialPRFAssertionInput(
                inputValues: ASAuthorizationPublicKeyCredentialPRFValues(
                    saltInput: "securesharing-mk-encryption".data(using: .utf8)!
                )
            )
        }

        // Present authentication UI
        let controller = ASAuthorizationController(authorizationRequests: [request])
        controller.delegate = self
        controller.presentationContextProvider = self

        let result = try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            controller.performRequests()
        }

        guard let credential = result.credential as? ASAuthorizationPlatformPublicKeyCredentialAssertion else {
            throw LoginError.invalidCredential
        }

        // Extract PRF output
        let prfOutput: Data
        if #available(iOS 17.0, *) {
            guard let prf = credential.prf?.first else {
                throw LoginError.prfNotSupported
            }
            prfOutput = prf.saltOutput
        } else {
            throw LoginError.prfNotSupported
        }

        // Complete login with server
        let loginResult = try await apiClient.completeWebAuthnLogin(
            tenantId: tenantId,
            credential: credential
        )

        return LoginResult(
            user: loginResult.user,
            session: loginResult.session,
            keyBundle: loginResult.keyBundle,
            prfOutput: prfOutput
        )
    }

    func authorizationController(
        controller: ASAuthorizationController,
        didCompleteWithAuthorization authorization: ASAuthorization
    ) {
        continuation?.resume(returning: authorization)
    }

    func authorizationController(
        controller: ASAuthorizationController,
        didCompleteWithError error: Error
    ) {
        continuation?.resume(throwing: error)
    }
}
```

##### Android (Kotlin)

```kotlin
import androidx.credentials.*
import com.google.android.gms.fido.fido2.api.common.*

class WebAuthnLoginManager(
    private val context: Context,
    private val apiClient: ApiClient
) {
    private val credentialManager = CredentialManager.create(context)

    suspend fun login(email: String, tenantId: String): LoginResult {
        // Get authentication options from server
        val options = apiClient.getWebAuthnLoginOptions(email)

        // Build GetCredentialRequest with PRF extension
        val publicKeyRequest = GetPublicKeyCredentialOption(
            requestJson = buildGetCredentialRequestJson(options),
            clientDataHash = null,
            allowedProviders = emptySet()
        )

        val request = GetCredentialRequest(listOf(publicKeyRequest))

        // Perform authentication (triggers system UI)
        val result = credentialManager.getCredential(context, request)
        val credential = result.credential as PublicKeyCredential

        // Parse response and extract PRF output
        val response = credential.authenticationResponseJson.toAuthResponse()
        val prfOutput = response.clientExtensionResults?.prf?.results?.first
            ?: throw LoginException("PRF not supported")

        // Complete login with server
        val loginResponse = apiClient.completeWebAuthnLogin(
            tenantId = tenantId,
            credential = credential.toServerFormat()
        )

        return LoginResult(
            user = loginResponse.user,
            session = loginResponse.session,
            keyBundle = loginResponse.keyBundle,
            prfOutput = prfOutput.decodeBase64()
        )
    }

    private fun buildGetCredentialRequestJson(options: WebAuthnOptions): String {
        return JSONObject().apply {
            put("challenge", options.challenge.encodeBase64())
            put("rpId", options.rpId)
            put("userVerification", "required")
            put("extensions", JSONObject().apply {
                put("prf", JSONObject().apply {
                    put("eval", JSONObject().apply {
                        put("first", "securesharing-mk-encryption".encodeToByteArray().encodeBase64())
                    })
                })
            })
            options.allowCredentials?.let { creds ->
                put("allowCredentials", JSONArray(creds.map { it.toJson() }))
            }
        }.toString()
    }
}
```

#### 4.2.2 OIDC Login

```typescript
// Initiate OIDC flow - redirect to provider login
// Note: This is a GET redirect, not a POST
const providerId = 'azure-ad';
const redirectUri = encodeURIComponent('https://app.securesharing.com/auth/callback');
const state = generateCsrfState(); // Client-generated CSRF token
window.location.href = `/api/v1/auth/oidc/${providerId}/login?redirect_uri=${redirectUri}&state=${state}`;

// After IdP redirects back to callback with authorization code...
// Handle the callback
const callbackResponse = await fetch(`/api/v1/auth/oidc/${providerId}/callback`, {
  method: 'POST',
  headers: { 'Content-Type': 'application/json' },
  body: JSON.stringify({
    code: authorizationCode,
    state: state
  })
});

const { data: callbackData } = await callbackResponse.json();

// For existing users, response includes session and key_bundle directly
if (callbackData.status === 'existing_user') {
  const { user, session, key_bundle: keyBundle } = callbackData;
  // Prompt for vault password to decrypt keys
  const vaultPassword = await promptVaultPassword();
  // Continue to key decryption (step 10)
}

// For new users, redirect to registration flow
if (callbackData.status === 'new_user') {
  // See registration flow docs/flows/01-registration-flow.md
  const { registration_token, user_info } = callbackData;
  redirectToRegistration(registration_token, user_info);
}
```

### 4.3 Key Bundle (Included in Login Response)

> **Important: Zero-Knowledge Property**
>
> The key bundle returned by the server is **fully encrypted**. The server stores it but **cannot decrypt it**. Decryption requires the **auth key**, which is derived from:
> - Passkey: PRF output (hardware-bound, never leaves client)
> - OIDC: Vault password (known only to user)
>
> If the user loses their auth key source (device or password), the key bundle becomes undecryptable, requiring [Shamir recovery](./08-recovery-flow.md).

The key bundle is returned **directly in the login response** (see Section 4.2). No separate API call is needed.

**Key Bundle Structure** (from `key_bundle` field in login response):
```typescript
{
  "encrypted_master_key": "base64...",
  "mk_nonce": "base64...",
  "public_keys": {
    "ml_kem": "base64...",
    "ml_dsa": "base64...",
    "kaz_kem": "base64...",
    "kaz_sign": "base64..."
  },
  "encrypted_private_keys": {
    "ml_kem": {"ciphertext": "base64...", "nonce": "base64..."},
    "ml_dsa": {"ciphertext": "base64...", "nonce": "base64..."},
    "kaz_kem": {"ciphertext": "base64...", "nonce": "base64..."},
    "kaz_sign": {"ciphertext": "base64...", "nonce": "base64..."}
  }
}
```

> **Note**: If you need to retrieve the key bundle again (e.g., after the session is already established), use `GET /api/v1/auth/me` which returns the current user profile along with the key bundle.

### 4.4 Step 10: Client-Side Key Decryption

#### Web (TypeScript)

```typescript
async function decryptKeyBundle(
  keyBundle: EncryptedKeyBundle,
  authKeyMaterial: Uint8Array | null,
  vaultPassword: string | null
): Promise<DecryptedKeys> {
  // Derive auth encryption key
  let authKey: Uint8Array;
  if (authKeyMaterial) {
    authKey = await hkdfDerive(authKeyMaterial, "master-key-encryption", 32);
  } else if (vaultPassword) {
    authKey = await argon2id(vaultPassword, {
      memory: 65536, iterations: 3, parallelism: 4, hashLength: 32
    });
  } else {
    throw new Error('No authentication key material available');
  }

  // Decrypt Master Key
  const masterKey = await aesGcmDecrypt(
    authKey,
    base64Decode(keyBundle.mk_nonce),
    base64Decode(keyBundle.encrypted_master_key)
  );
  authKey.fill(0);  // Clear auth key

  // Decrypt private keys
  const privateKeys = {
    ml_kem: await decryptPrivateKey(masterKey, keyBundle.encrypted_private_keys.ml_kem),
    ml_dsa: await decryptPrivateKey(masterKey, keyBundle.encrypted_private_keys.ml_dsa),
    kaz_kem: await decryptPrivateKey(masterKey, keyBundle.encrypted_private_keys.kaz_kem),
    kaz_sign: await decryptPrivateKey(masterKey, keyBundle.encrypted_private_keys.kaz_sign)
  };

  return { masterKey, privateKeys };
}

async function decryptPrivateKey(
  masterKey: Uint8Array,
  encryptedKey: { ciphertext: string; nonce: string }
): Promise<Uint8Array> {
  return await aesGcmDecrypt(
    masterKey,
    base64Decode(encryptedKey.nonce),
    base64Decode(encryptedKey.ciphertext)
  );
}
```

#### Desktop (Rust/Tauri)

```rust
use aes_gcm::{Aes256Gcm, KeyInit, aead::Aead};
use argon2::{Argon2, Params};
use hkdf::Hkdf;
use sha2::Sha384;
use zeroize::Zeroize;

pub struct DecryptedKeys {
    pub master_key: Vec<u8>,
    pub private_keys: PrivateKeys,
}

pub fn decrypt_key_bundle(
    key_bundle: &EncryptedKeyBundle,
    auth_key_material: Option<&[u8]>,
    vault_password: Option<&str>,
) -> Result<DecryptedKeys, CryptoError> {
    // Derive auth encryption key
    let mut auth_key = if let Some(prf_output) = auth_key_material {
        // Passkey with PRF - use HKDF
        let hk = Hkdf::<Sha384>::new(None, prf_output);
        let mut okm = [0u8; 32];
        hk.expand(b"master-key-encryption", &mut okm)
            .map_err(|_| CryptoError::HkdfError)?;
        okm.to_vec()
    } else if let Some(password) = vault_password {
        // OIDC - use Argon2id
        let params = Params::new(65536, 3, 4, Some(32))
            .map_err(|_| CryptoError::Argon2Error)?;
        let argon2 = Argon2::new(argon2::Algorithm::Argon2id, argon2::Version::V0x13, params);
        let mut output = [0u8; 32];
        argon2.hash_password_into(password.as_bytes(), &key_bundle.mk_salt, &mut output)
            .map_err(|_| CryptoError::Argon2Error)?;
        output.to_vec()
    } else {
        return Err(CryptoError::NoKeyMaterial);
    };

    // Decrypt Master Key
    let cipher = Aes256Gcm::new_from_slice(&auth_key)
        .map_err(|_| CryptoError::KeyError)?;
    let master_key = cipher
        .decrypt(
            key_bundle.mk_nonce.as_slice().into(),
            key_bundle.encrypted_master_key.as_slice(),
        )
        .map_err(|_| CryptoError::DecryptionFailed)?;

    // Clear auth key
    auth_key.zeroize();

    // Decrypt private keys
    let private_keys = PrivateKeys {
        ml_kem: decrypt_private_key(&master_key, &key_bundle.encrypted_private_keys.ml_kem)?,
        ml_dsa: decrypt_private_key(&master_key, &key_bundle.encrypted_private_keys.ml_dsa)?,
        kaz_kem: decrypt_private_key(&master_key, &key_bundle.encrypted_private_keys.kaz_kem)?,
        kaz_sign: decrypt_private_key(&master_key, &key_bundle.encrypted_private_keys.kaz_sign)?,
    };

    Ok(DecryptedKeys { master_key, private_keys })
}

fn decrypt_private_key(master_key: &[u8], encrypted: &EncryptedKey) -> Result<Vec<u8>, CryptoError> {
    let cipher = Aes256Gcm::new_from_slice(master_key)
        .map_err(|_| CryptoError::KeyError)?;
    cipher
        .decrypt(encrypted.nonce.as_slice().into(), encrypted.ciphertext.as_slice())
        .map_err(|_| CryptoError::DecryptionFailed)
}
```

#### iOS (Swift)

```swift
import CryptoKit
import Foundation

struct DecryptedKeys {
    let masterKey: SymmetricKey
    let privateKeys: PrivateKeys
}

func decryptKeyBundle(
    keyBundle: EncryptedKeyBundle,
    authKeyMaterial: Data?,
    vaultPassword: String?
) throws -> DecryptedKeys {
    // Derive auth encryption key
    let authKey: SymmetricKey
    if let prfOutput = authKeyMaterial {
        // Passkey with PRF - use HKDF
        let derivedKey = HKDF<SHA384>.deriveKey(
            inputKeyMaterial: SymmetricKey(data: prfOutput),
            info: "master-key-encryption".data(using: .utf8)!,
            outputByteCount: 32
        )
        authKey = derivedKey
    } else if let password = vaultPassword {
        // OIDC - use Argon2id (via external library)
        let derivedKey = try Argon2.hash(
            password: password,
            salt: keyBundle.mkSalt,
            iterations: 3,
            memory: 65536,
            parallelism: 4,
            length: 32
        )
        authKey = SymmetricKey(data: derivedKey)
    } else {
        throw CryptoError.noKeyMaterial
    }

    // Decrypt Master Key
    let masterKeyData = try AES.GCM.open(
        AES.GCM.SealedBox(
            nonce: AES.GCM.Nonce(data: keyBundle.mkNonce),
            ciphertext: keyBundle.encryptedMasterKey.dropLast(16),
            tag: keyBundle.encryptedMasterKey.suffix(16)
        ),
        using: authKey
    )
    let masterKey = SymmetricKey(data: masterKeyData)

    // Decrypt private keys
    let privateKeys = PrivateKeys(
        mlKem: try decryptPrivateKey(masterKey: masterKey, encrypted: keyBundle.encryptedPrivateKeys.mlKem),
        mlDsa: try decryptPrivateKey(masterKey: masterKey, encrypted: keyBundle.encryptedPrivateKeys.mlDsa),
        kazKem: try decryptPrivateKey(masterKey: masterKey, encrypted: keyBundle.encryptedPrivateKeys.kazKem),
        kazSign: try decryptPrivateKey(masterKey: masterKey, encrypted: keyBundle.encryptedPrivateKeys.kazSign)
    )

    return DecryptedKeys(masterKey: masterKey, privateKeys: privateKeys)
}

private func decryptPrivateKey(masterKey: SymmetricKey, encrypted: EncryptedKey) throws -> Data {
    return try AES.GCM.open(
        AES.GCM.SealedBox(
            nonce: AES.GCM.Nonce(data: encrypted.nonce),
            ciphertext: encrypted.ciphertext.dropLast(16),
            tag: encrypted.ciphertext.suffix(16)
        ),
        using: masterKey
    )
}
```

#### Android (Kotlin)

```kotlin
import com.google.crypto.tink.aead.AesGcmKeyManager
import com.google.crypto.tink.subtle.Hkdf
import org.signal.argon2.Argon2

data class DecryptedKeys(
    val masterKey: ByteArray,
    val privateKeys: PrivateKeys
)

class KeyDecryptor {
    fun decryptKeyBundle(
        keyBundle: EncryptedKeyBundle,
        authKeyMaterial: ByteArray?,
        vaultPassword: String?
    ): DecryptedKeys {
        // Derive auth encryption key
        val authKey: ByteArray = when {
            authKeyMaterial != null -> {
                // Passkey with PRF - use HKDF
                Hkdf.computeHkdf(
                    "HMACSHA384",
                    authKeyMaterial,
                    null,
                    "master-key-encryption".toByteArray(),
                    32
                )
            }
            vaultPassword != null -> {
                // OIDC - use Argon2id
                Argon2.Builder(Argon2.Version.V13)
                    .type(Argon2.Type.Argon2id)
                    .memoryCostKiB(65536)
                    .parallelism(4)
                    .iterations(3)
                    .hashLength(32)
                    .build()
                    .hash(vaultPassword.toByteArray(), keyBundle.mkSalt)
                    .hash
            }
            else -> throw CryptoException("No key material available")
        }

        // Decrypt Master Key
        val masterKey = aesGcmDecrypt(
            key = authKey,
            nonce = keyBundle.mkNonce,
            ciphertext = keyBundle.encryptedMasterKey
        )
        authKey.fill(0)  // Clear auth key

        // Decrypt private keys
        val privateKeys = PrivateKeys(
            mlKem = decryptPrivateKey(masterKey, keyBundle.encryptedPrivateKeys.mlKem),
            mlDsa = decryptPrivateKey(masterKey, keyBundle.encryptedPrivateKeys.mlDsa),
            kazKem = decryptPrivateKey(masterKey, keyBundle.encryptedPrivateKeys.kazKem),
            kazSign = decryptPrivateKey(masterKey, keyBundle.encryptedPrivateKeys.kazSign)
        )

        return DecryptedKeys(masterKey, privateKeys)
    }

    private fun decryptPrivateKey(masterKey: ByteArray, encrypted: EncryptedKey): ByteArray {
        return aesGcmDecrypt(masterKey, encrypted.nonce, encrypted.ciphertext)
    }

    private fun aesGcmDecrypt(key: ByteArray, nonce: ByteArray, ciphertext: ByteArray): ByteArray {
        val cipher = javax.crypto.Cipher.getInstance("AES/GCM/NoPadding")
        val secretKey = javax.crypto.spec.SecretKeySpec(key, "AES")
        val gcmSpec = javax.crypto.spec.GCMParameterSpec(128, nonce)
        cipher.init(javax.crypto.Cipher.DECRYPT_MODE, secretKey, gcmSpec)
        return cipher.doFinal(ciphertext)
    }
}
```

### 4.5 Session Token (Included in Login Response)

The session token is returned **directly in the login response** (see Section 4.2). No separate token exchange is needed.

**Session Response Structure** (from `session` field in login response):
```typescript
{
  "token": "eyJhbGciOiJFZERTQSIs...",
  "expires_at": "2025-01-15T22:30:00.000Z"
}
```

The `user` object is also included in the login response:
```typescript
{
  "id": "660e8400-e29b-41d4-a716-446655440001",
  "email": "user@example.com",
  "display_name": "John Doe",
  "status": "active",
  "role": "member"
}
```

## 5. Session Management

### 5.1 Token Storage

```typescript
// Store session token (secure cookie or memory)
// NEVER store in localStorage for security

// Option 1: HttpOnly cookie (preferred for web)
// Set by server with:
// Set-Cookie: session=<token>; HttpOnly; Secure; SameSite=Strict

// Option 2: In-memory only (for sensitive apps)
class SessionManager {
  private sessionToken: string | null = null;

  setSession(token: string) {
    this.sessionToken = token;
  }

  getSession(): string | null {
    return this.sessionToken;
  }

  clearSession() {
    this.sessionToken = null;
  }
}
```

### 5.2 Key Storage

```typescript
// Keys are stored ONLY in memory
class KeyManager {
  private keys: DecryptedKeys | null = null;

  setKeys(keys: DecryptedKeys) {
    this.keys = keys;
  }

  getKeys(): DecryptedKeys | null {
    return this.keys;
  }

  clearKeys() {
    if (this.keys) {
      // Securely clear all key material
      this.keys.masterKey.fill(0);
      this.keys.privateKeys.ml_kem.fill(0);
      this.keys.privateKeys.ml_dsa.fill(0);
      this.keys.privateKeys.kaz_kem.fill(0);
      this.keys.privateKeys.kaz_sign.fill(0);
      // Clear any cached folder KEKs
      this.folderKeks.forEach(kek => kek.fill(0));
      this.folderKeks.clear();
      this.keys = null;
    }
  }

  // Folder KEKs are cached after first decryption
  private folderKeks: Map<string, Uint8Array> = new Map();

  setFolderKek(folderId: string, kek: Uint8Array) {
    this.folderKeks.set(folderId, kek);
  }

  getFolderKek(folderId: string): Uint8Array | undefined {
    return this.folderKeks.get(folderId);
  }
}

// Clear keys on:
// - Explicit logout
// - Tab/window close
// - Session expiry
// - Inactivity timeout
window.addEventListener('beforeunload', () => {
  keyManager.clearKeys();
});
```

## 6. Token Refresh Flow

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                         TOKEN REFRESH FLOW                                   │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│  ┌─────────┐         ┌─────────┐         ┌─────────┐                        │
│  │ Client  │         │ Server  │         │   IdP   │                        │
│  └────┬────┘         └────┬────┘         └────┬────┘                        │
│       │                   │                   │                              │
│       │  1. API Request with near-expiry token                              │
│       │──────────────────▶│                   │                              │
│       │                   │                   │                              │
│       │  2. 401 + refresh hint               │                              │
│       │◀──────────────────│                   │                              │
│       │                   │                   │                              │
│       │  3. Refresh Request                  │                              │
│       │──────────────────▶│                   │                              │
│       │                   │                   │                              │
│       │                   │  4. Validate refresh token                      │
│       │                   │  (if using refresh tokens)                      │
│       │                   │                   │                              │
│       │  5. New Session Token                │                              │
│       │◀──────────────────│                   │                              │
│       │                   │                   │                              │
│       │  [Keys remain in memory - no re-decryption needed]                  │
│       │                   │                   │                              │
└─────────────────────────────────────────────────────────────────────────────┘
```

### Refresh Implementation

```typescript
// Token refresh (session only, keys remain in memory)
async function refreshSession(currentToken: string): Promise<Session> {
  const response = await fetch('/api/v1/auth/session/refresh', {
    method: 'POST',
    headers: {
      'Authorization': `Bearer ${currentToken}`
    }
  });

  if (!response.ok) {
    // Full re-login required
    throw new Error('SESSION_EXPIRED');
  }

  const { data: newSession } = await response.json();
  return newSession;
}

// Proactive refresh before expiry
class TokenRefreshManager {
  private refreshTimer: number | null = null;

  scheduleRefresh(expiresAt: Date) {
    const now = Date.now();
    const expiry = expiresAt.getTime();
    const refreshTime = expiry - (5 * 60 * 1000); // 5 min before expiry

    if (refreshTime > now) {
      this.refreshTimer = setTimeout(
        () => this.performRefresh(),
        refreshTime - now
      );
    }
  }

  private async performRefresh() {
    try {
      const newSession = await refreshSession(currentSession.token);
      sessionManager.setSession(newSession.token);
      this.scheduleRefresh(new Date(newSession.expires_at));
    } catch (error) {
      // Trigger re-login
      this.onSessionExpired();
    }
  }

  private onSessionExpired() {
    keyManager.clearKeys();
    sessionManager.clearSession();
    // Navigate to login
    window.location.href = '/login?reason=session_expired';
  }
}
```

## 7. Error Handling

| Error Code | Cause | Recovery |
|------------|-------|----------|
| `E_USER_NOT_FOUND` | Email not registered | Register first |
| `E_CREDENTIAL_NOT_FOUND` | No credential for this IdP | Use registered IdP |
| `E_CREDENTIAL_INVALID` | WebAuthn verification failed | Retry |
| `E_WRONG_PASSWORD` | Vault password incorrect | Re-enter password |
| `E_DECRYPTION_FAILED` | Key decryption failed | May need recovery |
| `E_TENANT_SUSPENDED` | Tenant account suspended | Contact admin |
| `E_USER_SUSPENDED` | User account suspended | Contact admin |
| `E_TOKEN_EXPIRED` | Session token expired | Re-login |
| `E_PRF_FAILED` | PRF extension failed | Use vault password fallback |

### Error Recovery Flow

```typescript
async function handleLoginError(error: LoginError) {
  switch (error.code) {
    case 'E_DECRYPTION_FAILED':
      // Keys may have been corrupted or password wrong
      if (error.idpType === 'oidc') {
        // Prompt for vault password again
        const password = await promptVaultPassword('Incorrect password');
        return retryDecryption(password);
      } else {
        // WebAuthn - may need recovery
        return promptRecoveryOption();
      }

    case 'E_CREDENTIAL_NOT_FOUND':
      // User trying wrong IdP
      const availableIdps = await fetchUserIdps(error.email);
      return promptSelectIdp(availableIdps);

    case 'E_TOKEN_EXPIRED':
      // Clear state and re-login
      keyManager.clearKeys();
      sessionManager.clearSession();
      return initiateLogin();

    default:
      throw error;
  }
}
```

## 8. Security Considerations

### 8.1 Key Material Handling

- Keys are decrypted only in client memory
- Keys are never persisted to disk or localStorage
- Keys are cleared on logout, tab close, or timeout
- PRF output is immediately derived into encryption key

### 8.2 Session Security

- Session tokens are short-lived (configurable, default 2 hours)
- Refresh tokens (if used) have longer expiry but require secure storage
- HttpOnly cookies prevent XSS token theft
- CSRF protection via SameSite cookies

### 8.3 Brute Force Protection

- Failed login attempts are rate-limited per IP and per account
- Account lockout after configurable failed attempts
- CAPTCHA may be required after multiple failures

## 9. Multiple Device Support

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                       MULTI-DEVICE LOGIN                                     │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│  Device A (Laptop)              Device B (Phone)                            │
│  ─────────────────              ────────────────                            │
│                                                                              │
│  [Login with Passkey A]         [Login with Passkey B]                      │
│         │                              │                                     │
│         ▼                              ▼                                     │
│  [Decrypt keys with            [Decrypt keys with                           │
│   PRF output A]                 PRF output B]                               │
│         │                              │                                     │
│         ▼                              ▼                                     │
│  [Keys in memory A]            [Keys in memory B]                           │
│         │                              │                                     │
│         ▼                              ▼                                     │
│  [Session Token A]             [Session Token B]                            │
│                                                                              │
│  Both devices have independent sessions with same decrypted keys            │
│  (keys decrypted from same encrypted bundle using different passkeys)       │
│                                                                              │
└─────────────────────────────────────────────────────────────────────────────┘
```

### Multiple Passkey Support

Users can register multiple passkeys for the same account:

```typescript
// Each passkey generates the same MK encryption key via PRF
// PRF salt is constant: "securesharing-mk-encryption"
// Different passkeys on different devices will produce same derived key
// (assuming same credential was synced or same PRF salt used)

// For non-synced passkeys, MK must be re-encrypted for each passkey
interface UserCredentials {
  credentials: {
    id: string;
    type: 'webauthn';
    device_name: string;
    encrypted_mk: string;  // MK encrypted with THIS credential's PRF
    mk_nonce: string;
    created_at: string;
  }[];
}
```

## 10. Logout Flow

```typescript
async function logout() {
  try {
    // Notify server (optional, for audit)
    await fetch('/api/v1/auth/logout', {
      method: 'POST',
      headers: {
        'Authorization': `Bearer ${sessionManager.getSession()}`
      }
    });
  } finally {
    // Always clear local state
    keyManager.clearKeys();
    sessionManager.clearSession();

    // Clear any cached data
    cacheManager.clear();

    // Navigate to login
    window.location.href = '/login';
  }
}
```
