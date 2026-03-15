# SSDID SDK Migration — Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace inline SSDID protocol code in Android and iOS clients with calls to the `ssdid-sdk` library, reducing ~500 lines of duplicated URI building and callback parsing.

**Architecture:** Extend `ssdid-sdk` with a `SsdidLoginRequest` builder matching the existing `ssdid://login?...` deeplink contract. Rebuild UniFFI bindings. Integrate native libraries into Android (JNI .so) and iOS (XCFramework). Replace inline code with SDK calls. No backend or desktop changes.

**Tech Stack:** Rust (ssdid-sdk), UniFFI (Kotlin/Swift bindings), Kotlin (Android), Swift (iOS)

**Repos:**
- SDK: `~/Workspace/ssdid-sdk/`
- Drive: `~/Workspace/ssdid-drive/`

---

## Important: Callback Format Mismatch

The SDK's `SsdidCallback::parse()` expects `?status=success&response_id=...` format. But the ssdid-drive wallet callbacks use `?session_token=...` (no `status` parameter for auth callbacks) and `?session_token=...&status=success` for invite callbacks.

**Decision:** The SDK callback parser can be used for **invite callbacks** (which have `status=success`). For **auth callbacks** (`ssdid-drive://auth/callback?session_token=...`), the parsing is trivial (extract one query param) — keep inline in clients. Don't force the SDK to know about session tokens.

---

## File Structure

### SDK Changes (`~/Workspace/ssdid-sdk/`)

| Action | File | Responsibility |
|--------|------|----------------|
| Create | `crates/ssdid-sdk-core/src/login_request.rs` | Login deeplink builder |
| Modify | `crates/ssdid-sdk-core/src/lib.rs` | Export new module |
| Modify | `crates/ssdid-sdk-ffi/src/lib.rs` | FFI wrapper for login builder |
| Regen | `bindings/kotlin/uniffi/ssdid_sdk_ffi/ssdid_sdk_ffi.kt` | Kotlin bindings |
| Regen | `bindings/swift/ssdid_sdk_ffi.swift` | Swift bindings |

### Android Changes (`~/Workspace/ssdid-drive/clients/android/`)

| Action | File | Responsibility |
|--------|------|----------------|
| Add | `app/libs/arm64-v8a/libssdid_sdk_ffi.so` | Native library |
| Add | `app/src/main/kotlin/.../ssdid_sdk_ffi.kt` | Generated Kotlin bindings |
| Modify | `data/repository/AuthRepositoryImpl.kt` | Replace URI building with SDK |
| Modify | `util/DeepLinkHandler.kt` | Replace invite callback parsing with SDK |

### iOS Changes (`~/Workspace/ssdid-drive/clients/ios/`)

| Action | File | Responsibility |
|--------|------|----------------|
| Add | `Frameworks/SsdidSdkFfi.xcframework` | Native framework |
| Add | `SsdidDrive/Core/SsdidSdk/ssdid_sdk_ffi.swift` | Generated Swift bindings |
| Modify | `Presentation/Auth/LoginViewModel.swift` | Replace URI building with SDK |
| Modify | `Core/Utils/DeepLinkParser.swift` | Replace invite callback parsing with SDK |

---

## Chunk 1: Extend ssdid-sdk with SsdidLoginRequest

### Task 1: Add SsdidLoginRequest builder to ssdid-sdk-core

**Repo:** `~/Workspace/ssdid-sdk/`
**Files:**
- Create: `crates/ssdid-sdk-core/src/login_request.rs`
- Modify: `crates/ssdid-sdk-core/src/lib.rs`

- [ ] **Step 1: Write failing test**

Add to `crates/ssdid-sdk-core/src/login_request.rs`:

```rust
#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn builds_login_deeplink_with_all_fields() {
        let request = SsdidLoginRequest::builder()
            .server_url("https://drive.ssdid.my/api")
            .service_name("SSDID Drive")
            .challenge_id("abc-123")
            .callback_scheme("ssdiddrive")
            .build()
            .unwrap();

        let deeplink = request.to_deeplink();
        assert!(deeplink.starts_with("ssdid://login?"));
        assert!(deeplink.contains("server_url=https"));
        assert!(deeplink.contains("service_name=SSDID+Drive"));
        assert!(deeplink.contains("challenge_id=abc-123"));
        assert!(deeplink.contains("callback_url=ssdiddrive%3A%2F%2Fauth%2Fcallback"));
    }

    #[test]
    fn builds_login_deeplink_with_requested_claims() {
        let request = SsdidLoginRequest::builder()
            .server_url("https://drive.ssdid.my/api")
            .service_name("SSDID Drive")
            .challenge_id("abc-123")
            .callback_scheme("ssdiddrive")
            .requested_claim("name", true)
            .requested_claim("email", false)
            .build()
            .unwrap();

        let deeplink = request.to_deeplink();
        // requested_claims should be JSON-encoded
        assert!(deeplink.contains("requested_claims="));
    }

    #[test]
    fn rejects_missing_server_url() {
        let result = SsdidLoginRequest::builder()
            .service_name("Test")
            .challenge_id("abc")
            .callback_scheme("test")
            .build();
        assert!(result.is_err());
    }

    #[test]
    fn rejects_http_server_url() {
        let result = SsdidLoginRequest::builder()
            .server_url("http://insecure.example.com")
            .service_name("Test")
            .challenge_id("abc")
            .callback_scheme("test")
            .build();
        assert!(result.is_err());
    }

    #[test]
    fn rejects_missing_callback_scheme() {
        let result = SsdidLoginRequest::builder()
            .server_url("https://drive.ssdid.my/api")
            .service_name("Test")
            .challenge_id("abc")
            .build();
        assert!(result.is_err());
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd ~/Workspace/ssdid-sdk && cargo test -p ssdid-sdk-core`
Expected: FAIL — module and struct don't exist yet

- [ ] **Step 3: Implement SsdidLoginRequest**

Create `crates/ssdid-sdk-core/src/login_request.rs`:

```rust
use crate::error::{SdkError, SdkResult};
use serde_json::json;

const MAX_URL_LEN: usize = 2048;

/// Builds an `ssdid://login?...` deeplink for SSDID Wallet authentication.
///
/// Output format matches the contract expected by the SSDID Wallet app:
/// `ssdid://login?server_url=...&service_name=...&challenge_id=...&callback_url=...&requested_claims=...`
#[derive(Debug)]
pub struct SsdidLoginRequest {
    deeplink: String,
}

impl SsdidLoginRequest {
    pub fn builder() -> LoginRequestBuilder {
        LoginRequestBuilder::new()
    }

    pub fn to_deeplink(&self) -> &str {
        &self.deeplink
    }

    pub fn to_qr_string(&self) -> &str {
        &self.deeplink
    }
}

#[derive(Debug)]
pub struct LoginRequestBuilder {
    server_url: Option<String>,
    service_name: Option<String>,
    challenge_id: Option<String>,
    callback_scheme: Option<String>,
    requested_claims: Vec<(String, bool)>, // (claim_name, required)
    // Optional fields from backend challenge response
    challenge: Option<String>,
    server_did: Option<String>,
    server_key_id: Option<String>,
    server_signature: Option<String>,
    registry_url: Option<String>,
}

impl LoginRequestBuilder {
    fn new() -> Self {
        Self {
            server_url: None,
            service_name: None,
            challenge_id: None,
            callback_scheme: None,
            requested_claims: vec![],
            challenge: None,
            server_did: None,
            server_key_id: None,
            server_signature: None,
            registry_url: None,
        }
    }

    pub fn server_url(mut self, url: &str) -> Self {
        self.server_url = Some(url.to_string());
        self
    }

    pub fn service_name(mut self, name: &str) -> Self {
        self.service_name = Some(name.to_string());
        self
    }

    pub fn challenge_id(mut self, id: &str) -> Self {
        self.challenge_id = Some(id.to_string());
        self
    }

    pub fn callback_scheme(mut self, scheme: &str) -> Self {
        self.callback_scheme = Some(scheme.to_string());
        self
    }

    pub fn requested_claim(mut self, name: &str, required: bool) -> Self {
        self.requested_claims.push((name.to_string(), required));
        self
    }

    pub fn challenge(mut self, challenge: &str) -> Self {
        self.challenge = Some(challenge.to_string());
        self
    }

    pub fn server_did(mut self, did: &str) -> Self {
        self.server_did = Some(did.to_string());
        self
    }

    pub fn server_key_id(mut self, key_id: &str) -> Self {
        self.server_key_id = Some(key_id.to_string());
        self
    }

    pub fn server_signature(mut self, sig: &str) -> Self {
        self.server_signature = Some(sig.to_string());
        self
    }

    pub fn registry_url(mut self, url: &str) -> Self {
        self.registry_url = Some(url.to_string());
        self
    }

    pub fn build(self) -> SdkResult<SsdidLoginRequest> {
        let server_url = self.server_url
            .ok_or_else(|| SdkError::InvalidConfig("server_url is required".into()))?;
        let service_name = self.service_name
            .ok_or_else(|| SdkError::InvalidConfig("service_name is required".into()))?;
        let challenge_id = self.challenge_id
            .ok_or_else(|| SdkError::InvalidConfig("challenge_id is required".into()))?;
        let callback_scheme = self.callback_scheme
            .ok_or_else(|| SdkError::InvalidConfig("callback_scheme is required".into()))?;

        // Validate HTTPS
        if !server_url.starts_with("https://") {
            return Err(SdkError::InvalidUrl("server_url must use HTTPS".into()));
        }

        // Validate callback scheme is not HTTP
        if callback_scheme.starts_with("http") {
            return Err(SdkError::InvalidUrl("callback_scheme must be a custom scheme, not HTTP".into()));
        }

        let callback_url = format!("{callback_scheme}://auth/callback");

        let mut params = vec![
            ("server_url", server_url),
            ("service_name", service_name),
            ("challenge_id", challenge_id),
            ("callback_url", callback_url),
        ];

        if let Some(ref challenge) = self.challenge {
            params.push(("challenge", challenge.clone()));
        }
        if let Some(ref did) = self.server_did {
            params.push(("server_did", did.clone()));
        }
        if let Some(ref key_id) = self.server_key_id {
            params.push(("server_key_id", key_id.clone()));
        }
        if let Some(ref sig) = self.server_signature {
            params.push(("server_signature", sig.clone()));
        }
        if let Some(ref url) = self.registry_url {
            params.push(("registry_url", url.clone()));
        }

        if !self.requested_claims.is_empty() {
            let claims: serde_json::Value = self.requested_claims.iter().map(|(name, required)| {
                json!({ "name": name, "required": required })
            }).collect();
            params.push(("requested_claims", claims.to_string()));
        }

        let query = url::form_urlencoded::Serializer::new(String::new())
            .extend_pairs(params.iter().map(|(k, v)| (*k, v.as_str())))
            .finish();

        let deeplink = format!("ssdid://login?{query}");

        if deeplink.len() > MAX_URL_LEN {
            return Err(SdkError::InvalidUrl(format!(
                "deeplink exceeds {MAX_URL_LEN} bytes ({} bytes)", deeplink.len()
            )));
        }

        Ok(SsdidLoginRequest { deeplink })
    }
}
```

- [ ] **Step 4: Export from lib.rs**

In `crates/ssdid-sdk-core/src/lib.rs`, add:
```rust
pub mod login_request;
```

- [ ] **Step 5: Run tests**

Run: `cd ~/Workspace/ssdid-sdk && cargo test -p ssdid-sdk-core`
Expected: All tests PASS (existing + 5 new)

- [ ] **Step 6: Commit**

```bash
cd ~/Workspace/ssdid-sdk
git add crates/ssdid-sdk-core/src/login_request.rs crates/ssdid-sdk-core/src/lib.rs
git commit -m "feat: add SsdidLoginRequest builder for ssdid://login deeplinks"
```

---

### Task 2: Add FFI wrapper and regenerate bindings

**Repo:** `~/Workspace/ssdid-sdk/`
**Files:**
- Modify: `crates/ssdid-sdk-ffi/src/lib.rs`

- [ ] **Step 1: Add FFI function for login request**

In `crates/ssdid-sdk-ffi/src/lib.rs`, add:

```rust
#[derive(uniffi::Record)]
pub struct FfiRequestedClaim {
    pub name: String,
    pub required: bool,
}

#[uniffi::export]
pub fn build_login_request(
    server_url: String,
    service_name: String,
    challenge_id: String,
    callback_scheme: String,
    requested_claims: Vec<FfiRequestedClaim>,
    challenge: Option<String>,
    server_did: Option<String>,
    server_key_id: Option<String>,
    server_signature: Option<String>,
    registry_url: Option<String>,
) -> Result<String, FfiSdkError> {
    let mut builder = ssdid_sdk_core::login_request::SsdidLoginRequest::builder()
        .server_url(&server_url)
        .service_name(&service_name)
        .challenge_id(&challenge_id)
        .callback_scheme(&callback_scheme);

    for claim in &requested_claims {
        builder = builder.requested_claim(&claim.name, claim.required);
    }

    if let Some(ref c) = challenge {
        builder = builder.challenge(c);
    }
    if let Some(ref d) = server_did {
        builder = builder.server_did(d);
    }
    if let Some(ref k) = server_key_id {
        builder = builder.server_key_id(k);
    }
    if let Some(ref s) = server_signature {
        builder = builder.server_signature(s);
    }
    if let Some(ref r) = registry_url {
        builder = builder.registry_url(r);
    }

    let request = builder.build()?;
    Ok(request.to_deeplink().to_string())
}
```

- [ ] **Step 2: Build and generate bindings**

```bash
cd ~/Workspace/ssdid-sdk
cargo build
cargo run -p ssdid-sdk-ffi --bin uniffi-bindgen generate \
    crates/ssdid-sdk-ffi/src/lib.rs \
    --language kotlin --out-dir bindings/kotlin
cargo run -p ssdid-sdk-ffi --bin uniffi-bindgen generate \
    crates/ssdid-sdk-ffi/src/lib.rs \
    --language swift --out-dir bindings/swift
```

Check the exact uniffi-bindgen command by reading the existing build instructions in `README.md` or `Makefile`.

- [ ] **Step 3: Verify bindings generated**

Check that `bindings/kotlin/uniffi/ssdid_sdk_ffi/ssdid_sdk_ffi.kt` contains `buildLoginRequest` function.
Check that `bindings/swift/ssdid_sdk_ffi.swift` contains `buildLoginRequest` function.

- [ ] **Step 4: Run all SDK tests**

Run: `cd ~/Workspace/ssdid-sdk && cargo test`
Expected: All 48+ tests PASS

- [ ] **Step 5: Commit**

```bash
cd ~/Workspace/ssdid-sdk
git add crates/ssdid-sdk-ffi/src/lib.rs bindings/
git commit -m "feat: add FFI wrapper for login request builder and regenerate bindings"
```

---

### Task 3: Build native libraries for Android and iOS

**Repo:** `~/Workspace/ssdid-sdk/`

- [ ] **Step 1: Build Android native library**

```bash
cd ~/Workspace/ssdid-sdk

# Install Android targets if not already
rustup target add aarch64-linux-android armv7-linux-androideabi x86_64-linux-android

# Build for arm64 (most common)
cargo build --target aarch64-linux-android --release -p ssdid-sdk-ffi
```

Note: This requires Android NDK configured. Check if `ANDROID_NDK_HOME` is set. If using cargo-ndk:
```bash
cargo ndk -t arm64-v8a build --release -p ssdid-sdk-ffi
```

Output: `target/aarch64-linux-android/release/libssdid_sdk_ffi.so`

- [ ] **Step 2: Build iOS native library**

```bash
# Install iOS targets
rustup target add aarch64-apple-ios aarch64-apple-ios-sim x86_64-apple-ios

# Build for device
cargo build --target aarch64-apple-ios --release -p ssdid-sdk-ffi

# Build for simulator (arm64 Mac)
cargo build --target aarch64-apple-ios-sim --release -p ssdid-sdk-ffi

# Create XCFramework
xcodebuild -create-xcframework \
    -library target/aarch64-apple-ios/release/libssdid_sdk_ffi.a \
    -headers bindings/swift/ssdid_sdk_ffiFFI.h \
    -library target/aarch64-apple-ios-sim/release/libssdid_sdk_ffi.a \
    -headers bindings/swift/ssdid_sdk_ffiFFI.h \
    -output SsdidSdkFfi.xcframework
```

- [ ] **Step 3: Copy to ssdid-drive clients**

```bash
# Android
mkdir -p ~/Workspace/ssdid-drive/clients/android/app/src/main/jniLibs/arm64-v8a/
cp target/aarch64-linux-android/release/libssdid_sdk_ffi.so \
    ~/Workspace/ssdid-drive/clients/android/app/src/main/jniLibs/arm64-v8a/

# Copy Kotlin bindings
cp bindings/kotlin/uniffi/ssdid_sdk_ffi/ssdid_sdk_ffi.kt \
    ~/Workspace/ssdid-drive/clients/android/app/src/main/kotlin/my/ssdid/drive/sdk/

# iOS
cp -r SsdidSdkFfi.xcframework \
    ~/Workspace/ssdid-drive/clients/ios/SsdidDrive/Frameworks/

# Copy Swift bindings
cp bindings/swift/ssdid_sdk_ffi.swift \
    ~/Workspace/ssdid-drive/clients/ios/SsdidDrive/SsdidDrive/Core/SsdidSdk/
```

Adjust paths based on actual project structure. The key is:
- Android: `.so` in `jniLibs/`, Kotlin bindings in source tree
- iOS: `.xcframework` in `Frameworks/`, Swift bindings in source tree

- [ ] **Step 4: Commit in ssdid-drive**

```bash
cd ~/Workspace/ssdid-drive
git add clients/android/ clients/ios/
git commit -m "chore: add ssdid-sdk native libraries and generated bindings"
```

---

## Chunk 2: Android SDK Integration

### Task 4: Replace URI building in Android AuthRepositoryImpl

**Repo:** `~/Workspace/ssdid-drive/`
**Files:**
- Modify: `clients/android/app/src/main/kotlin/my/ssdid/drive/data/repository/AuthRepositoryImpl.kt`

- [ ] **Step 1: Read the current URI building code**

Read `AuthRepositoryImpl.kt` and find the section that builds `ssdid://authenticate?...` or `ssdid://login?...` URIs. Note the exact parameters used.

- [ ] **Step 2: Replace with SDK call**

Replace the inline URI building with:

```kotlin
import uniffi.ssdid_sdk_ffi.buildLoginRequest
import uniffi.ssdid_sdk_ffi.FfiRequestedClaim

// Replace inline URL building:
val deeplink = buildLoginRequest(
    serverUrl = serverUrl,
    serviceName = "SSDID Drive",
    challengeId = challengeId,
    callbackScheme = "ssdiddrive",
    requestedClaims = listOf(
        FfiRequestedClaim(name = "name", required = true),
        FfiRequestedClaim(name = "email", required = false)
    ),
    challenge = challenge,
    serverDid = serverDid,
    serverKeyId = serverKeyId,
    serverSignature = serverSignature,
    registryUrl = registryUrl
)
```

Keep the SSE listening code unchanged. Only replace the URI construction.

- [ ] **Step 3: Build**

Run: `cd ~/Workspace/ssdid-drive/clients/android && ./gradlew assembleDevDebug 2>&1 | tail -5`

- [ ] **Step 4: Commit**

```bash
cd ~/Workspace/ssdid-drive
git add clients/android/
git commit -m "refactor(android): replace inline URI building with ssdid-sdk"
```

---

### Task 5: Replace invite callback parsing in Android DeepLinkHandler

**Repo:** `~/Workspace/ssdid-drive/`
**Files:**
- Modify: `clients/android/app/src/main/kotlin/my/ssdid/drive/util/DeepLinkHandler.kt`

- [ ] **Step 1: Read DeepLinkHandler.kt**

Find the `parseCustomScheme` method. Identify the invite callback parsing section (`ssdiddrive://invite/callback?session_token=...&status=...`).

- [ ] **Step 2: Replace invite callback parsing with SDK**

For the invite callback parsing (which uses `status` parameter), use the SDK:

```kotlin
import uniffi.ssdid_sdk_ffi.parseCallback
import uniffi.ssdid_sdk_ffi.FfiCallback

// In the invite callback section:
"invite" -> {
    val segment = pathSegments.firstOrNull()
    if (segment == "callback") {
        try {
            val callback = parseCallback(uri.toString())
            when (callback) {
                is FfiCallback.Success -> {
                    val sessionToken = uri.getQueryParameter("session_token")
                    if (sessionToken != null) {
                        DeepLinkAction.WalletInviteCallback(sessionToken)
                    } else null
                }
                is FfiCallback.Denied -> null
                is FfiCallback.Error -> {
                    val message = uri.getQueryParameter("message") ?: callback.code
                    DeepLinkAction.WalletInviteError(message)
                }
            }
        } catch (e: Exception) {
            // Fallback: SDK parse failed, try extracting session_token directly
            val sessionToken = uri.getQueryParameter("session_token")
            if (sessionToken != null) DeepLinkAction.WalletInviteCallback(sessionToken) else null
        }
    } else { /* existing token handling */ }
}
```

Note: Keep the `auth` callback parsing as-is (it doesn't use `status` parameter, just extracts `session_token`). The SDK callback parser requires `status` which the auth callback doesn't have.

- [ ] **Step 3: Build and verify**

Run: `cd ~/Workspace/ssdid-drive/clients/android && ./gradlew assembleDevDebug 2>&1 | tail -5`

- [ ] **Step 4: Commit**

```bash
cd ~/Workspace/ssdid-drive
git add clients/android/
git commit -m "refactor(android): use ssdid-sdk for invite callback parsing"
```

---

## Chunk 3: iOS SDK Integration

### Task 6: Replace URI building in iOS LoginViewModel

**Repo:** `~/Workspace/ssdid-drive/`
**Files:**
- Modify: `clients/ios/SsdidDrive/SsdidDrive/Presentation/Auth/LoginViewModel.swift`

- [ ] **Step 1: Read LoginViewModel.swift**

Find the section that builds the `ssdid://login?...` URL using `URLComponents`.

- [ ] **Step 2: Replace with SDK call**

```swift
import ssdid_sdk_ffi

// Replace URLComponents-based URI building with:
let deeplink = try buildLoginRequest(
    serverUrl: serverUrl,
    serviceName: "SSDID Drive",
    challengeId: challengeId,
    callbackScheme: "ssdid-drive",
    requestedClaims: [
        FfiRequestedClaim(name: "name", required: true),
        FfiRequestedClaim(name: "email", required: false)
    ],
    challenge: challenge,
    serverDid: serverDid,
    serverKeyId: serverKeyId,
    serverSignature: serverSignature,
    registryUrl: registryUrl
)

self.qrPayload = deeplink
self.walletDeepLink = URL(string: deeplink)
```

Keep SSE listening code unchanged.

- [ ] **Step 3: Build**

Build via Xcode or xcodebuild.

- [ ] **Step 4: Commit**

```bash
cd ~/Workspace/ssdid-drive
git add clients/ios/
git commit -m "refactor(ios): replace inline URI building with ssdid-sdk"
```

---

### Task 7: Replace invite callback parsing in iOS DeepLinkParser

**Repo:** `~/Workspace/ssdid-drive/`
**Files:**
- Modify: `clients/ios/SsdidDrive/SsdidDrive/Core/Utils/DeepLinkParser.swift`

- [ ] **Step 1: Read DeepLinkParser.swift**

Find the invite callback parsing section.

- [ ] **Step 2: Replace invite callback parsing with SDK**

```swift
import ssdid_sdk_ffi

// For invite callbacks (ssdid-drive://invite/callback?status=success&session_token=...):
if path == "invite" && segments.first == "callback" {
    do {
        let callback = try parseCallback(uri: url.absoluteString)
        switch callback {
        case .success(_):
            if let sessionToken = components.queryItems?.first(where: { $0.name == "session_token" })?.value {
                return .walletInviteCallback(sessionToken: sessionToken)
            }
        case .denied:
            return nil
        case .error(let code):
            return .walletInviteError(message: code)
        }
    } catch {
        // Fallback: extract session_token directly
        if let sessionToken = components.queryItems?.first(where: { $0.name == "session_token" })?.value {
            return .walletInviteCallback(sessionToken: sessionToken)
        }
    }
}
```

Keep auth callback parsing as-is (simple `session_token` extraction).

- [ ] **Step 3: Build**

- [ ] **Step 4: Commit**

```bash
cd ~/Workspace/ssdid-drive
git add clients/ios/
git commit -m "refactor(ios): use ssdid-sdk for invite callback parsing"
```

---

### Task 8: Final verification

- [ ] **Step 1: Run Android tests**

```bash
cd ~/Workspace/ssdid-drive/clients/android && ./gradlew testDevDebugUnitTest 2>&1 | tail -10
```

- [ ] **Step 2: Build iOS**

```bash
cd ~/Workspace/ssdid-drive/clients/ios/SsdidDrive && xcodegen generate && xcodebuild build -scheme SsdidDrive -destination 'platform=iOS Simulator,name=iPhone 16' -quiet 2>&1 | tail -10
```

- [ ] **Step 3: Run SDK tests**

```bash
cd ~/Workspace/ssdid-sdk && cargo test
```

- [ ] **Step 4: Push both repos**

```bash
cd ~/Workspace/ssdid-sdk && git push origin main
cd ~/Workspace/ssdid-drive && git push origin main
```

---

## Implementation Order & Dependencies

```
Task 1: SsdidLoginRequest builder (SDK) ──┐
Task 2: FFI wrapper + bindings (SDK)     ──┼── Chunk 1 (sequential, SDK repo)
Task 3: Build native libs + copy         ──┘
                                           │
Task 4: Android URI building (Drive)     ──┤── Chunk 2 (sequential, Drive repo)
Task 5: Android callback parsing (Drive) ──┘
                                           │
Task 6: iOS URI building (Drive)         ──┤── Chunk 3 (sequential, Drive repo)
Task 7: iOS callback parsing (Drive)     ──┤   Can parallel with Chunk 2
Task 8: Final verification               ──┘
```

Chunks 2 and 3 can run in parallel (different platforms, different files).
