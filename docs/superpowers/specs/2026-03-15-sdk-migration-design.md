# SSDID SDK Migration — Design Spec

## Goal

Replace inline SSDID protocol code in Android and iOS clients with calls to the `ssdid-sdk` library. Reduces ~500 lines of duplicated URI building and callback parsing across 2 platforms to single SDK calls.

## Scope

### In Scope
1. **Extend ssdid-sdk** — add `SsdidLoginRequest` builder matching existing `ssdid://login?...` deeplink contract
2. **Android** — replace inline URI building + callback parsing with SDK (Kotlin UniFFI bindings)
3. **iOS** — replace inline URI building + callback parsing + QR generation with SDK (Swift UniFFI bindings)

### NOT In Scope
- Backend API (.NET) — unchanged, no SDK consumption
- Desktop client (TypeScript) — no JS bindings in SDK
- Admin portal (React) — no JS bindings in SDK
- SSE listeners — remain platform-specific (URLSession on iOS, OkHttp on Android)
- HTTP challenge initiation — remains in each client's repository layer
- Session management — unchanged
- DCQL/VP token features — future work

## Architecture

```
ssdid-sdk (Rust + UniFFI)
├── SsdidLoginRequest::builder()     ← NEW: builds ssdid://login?... URIs
├── SsdidCallback::parse()           ← EXISTING: parses wallet callbacks
├── generate_qr_png()                ← EXISTING: QR code generation
└── UniFFI bindings → Kotlin + Swift

Android consumes via:
  - Generated Kotlin bindings (uniffi/ssdid_sdk_ffi.kt)
  - Native .so library (libssdid_sdk_ffi.so)

iOS consumes via:
  - Generated Swift bindings (ssdid_sdk_ffi.swift)
  - XCFramework (ssdid_sdk_ffi.xcframework)
```

## SDK Extension: SsdidLoginRequest

New builder in `ssdid-sdk-core` that generates the exact URI format the wallet expects:

```rust
pub struct SsdidLoginRequest { ... }

impl SsdidLoginRequest {
    pub fn builder() -> SsdidLoginRequestBuilder { ... }
    pub fn to_deeplink(&self) -> String { ... }
    pub fn to_qr_string(&self) -> String { ... }  // same as deeplink for login
}

// Builder:
SsdidLoginRequest::builder()
    .server_url("https://drive.ssdid.my/api")
    .service_name("SSDID Drive")
    .challenge_id("uuid-here")
    .challenge("base64-challenge")
    .server_did("did:ssdid:server")
    .server_key_id("key-1")
    .server_signature("sig-base64")
    .registry_url("https://registry.ssdid.my")
    .callback_scheme("ssdiddrive")
    .requested_claims(&[("name", Required), ("email", Optional)])
    .build()?;

// Output: ssdid://login?server_url=...&service_name=...&challenge_id=...&callback_url=ssdiddrive://auth/callback&requested_claims=...
```

## Client Migration

### Android
**Replace in `AuthRepositoryImpl.kt`:**
- Inline `ssdid://authenticate?...` URI building → `buildLoginRequest()` from SDK
- Inline deep link parsing in `DeepLinkHandler.kt` (auth/invite callbacks) → `parseCallback()` from SDK

**Keep:**
- SSE listening via OkHttp EventSource (SDK doesn't provide SSE)
- HTTP calls to backend API
- All non-auth deep link routing (file, folder, share)

### iOS
**Replace in `LoginViewModel.swift`:**
- `URLComponents` building `ssdid://login?...` → `buildLoginRequest()` from SDK
- QR code generation via `CIQRCodeGenerator` → `generateQrCode()` from SDK

**Replace in `DeepLinkParser.swift`:**
- Auth callback parsing → `parseCallback()` from SDK
- Invite callback parsing → `parseCallback()` from SDK

**Keep:**
- SSE listening via `URLSession.bytes`
- HTTP calls to backend API
- All non-auth deep link routing (file, folder, share)

## Integration Method

### Android
1. Build SDK native library: `cargo build --target aarch64-linux-android --release`
2. Copy `.so` to `clients/android/app/src/main/jniLibs/arm64-v8a/`
3. Copy generated Kotlin bindings to source tree
4. Import: `import uniffi.ssdid_sdk_ffi.*`

### iOS
1. Build SDK XCFramework: `cargo build --target aarch64-apple-ios --release`
2. Add XCFramework to `clients/ios/SsdidDrive/Frameworks/`
3. Copy generated Swift bindings to source tree
4. Import: `import ssdid_sdk_ffi`

## Error Mapping

| SDK Error | Android Maps To | iOS Maps To |
|-----------|----------------|-------------|
| `SdkError::InvalidConfig` | `AppException.Unknown` | `BaseViewModel.handleError` |
| `SdkError::InvalidUrl` | `AppException.Unknown` | `BaseViewModel.handleError` |
| `SdkError::ResponseParseError` | `AppException.Unknown` | `BaseViewModel.handleError` |

## Testing

- SDK: existing 48 Rust tests (all passing)
- Android: existing auth tests should pass unchanged (behavior identical)
- iOS: existing auth tests should pass unchanged
- New: integration test verifying SDK-generated URI matches old inline URI
