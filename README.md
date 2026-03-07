# SSDID Drive

Secure file sharing platform with post-quantum cryptography and self-sovereign identity (SSDID) authentication.

## Architecture

- **Backend API** (`src/SsdidDrive.Api/`) — .NET 10 minimal API with PQC crypto, DID-based auth
- **Android Client** (`clients/android/`) — Kotlin/Jetpack Compose (`my.ssdid.drive`)
- **Desktop Client** (`clients/desktop/`) — Tauri v2 + React/TypeScript (`my.ssdid.drive.desktop`)
- **iOS Client** (`clients/ios/`) — Swift with XcodeGen (`my.ssdid.drive.app`)

## Auth Flow

Users authenticate via the **SSDID Wallet** app (`my.ssdid.wallet`):
- Desktop: QR code displayed → wallet scans and signs challenge
- Mobile: Deep link → wallet signs challenge → callback

## Crypto

5 signature algorithm families (Ed25519, ECDSA, ML-DSA, SLH-DSA, KAZ-Sign) with 19 total variants.
File encryption uses PQC KEM (ML-KEM, KAZ-KEM) for key encapsulation + AES-256-GCM.

## Development

```bash
# Backend
dotnet build src/SsdidDrive.Api/
dotnet test tests/SsdidDrive.Api.Tests/

# Desktop
cd clients/desktop && npm install && npm run tauri:dev

# Android
cd clients/android && ./gradlew assembleDebug
```
