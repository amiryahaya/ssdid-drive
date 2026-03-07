# SecureSharing Android Client

A secure, end-to-end encrypted file sharing application for Android with post-quantum cryptography support.

## Features

- **End-to-End Encryption**: All files are encrypted client-side before upload
- **Post-Quantum Cryptography**: Dual-algorithm approach using both classical and PQC algorithms
  - KAZ-KEM + ML-KEM-768 for key encapsulation
  - KAZ-SIGN + ML-DSA-65 for digital signatures
- **Secure File Sharing**: Share files with other users using hybrid encryption
- **Folder Organization**: Hierarchical folder structure with encrypted metadata
- **Key Recovery**: Shamir Secret Sharing for master key recovery via trusted contacts
- **Offline Support**: Local caching with background sync
- **Biometric Authentication**: Optional fingerprint/face unlock

## Tech Stack

| Component | Technology |
|-----------|------------|
| Language | Kotlin 1.9+ |
| UI | Jetpack Compose + Material3 |
| Architecture | MVVM + Clean Architecture |
| DI | Hilt |
| Networking | Retrofit + OkHttp |
| Database | Room |
| Preferences | DataStore |
| Async | Kotlin Coroutines + Flow |
| Background | WorkManager |
| Image Loading | Coil |
| Crash Reporting | Sentry |
| PQC Crypto | KAZ-KEM, KAZ-SIGN, Bouncy Castle |

## Requirements

- Android Studio Hedgehog (2023.1.1) or newer
- JDK 17
- Android SDK 34
- Min SDK: 24 (Android 7.0)
- Target SDK: 34 (Android 14)
- NDK 25.2.9519653 (for native PQC libraries)

## Project Structure

```
android/
├── app/
│   └── src/main/
│       ├── kotlin/com/securesharing/
│       │   ├── SecureSharingApp.kt      # Application class
│       │   ├── MainActivity.kt           # Single activity
│       │   ├── di/                       # Hilt modules
│       │   ├── data/                     # Data layer
│       │   │   ├── remote/               # API services, DTOs
│       │   │   ├── local/                # Room DAOs, entities
│       │   │   ├── repository/           # Repository implementations
│       │   │   └── sync/                 # Offline sync
│       │   ├── domain/                   # Domain layer
│       │   │   ├── model/                # Domain entities
│       │   │   ├── repository/           # Repository interfaces
│       │   │   └── usecase/              # Use cases
│       │   ├── presentation/             # UI layer
│       │   │   ├── auth/                 # Login/Register
│       │   │   ├── files/                # File browser
│       │   │   ├── sharing/              # Share management
│       │   │   ├── recovery/             # Key recovery
│       │   │   ├── settings/             # Settings
│       │   │   └── common/               # Shared components
│       │   ├── crypto/                   # Cryptography
│       │   │   ├── CryptoManager.kt      # Central crypto operations
│       │   │   ├── KeyManager.kt         # Key storage
│       │   │   ├── FileEncryptor.kt      # File encryption
│       │   │   ├── FolderKeyManager.kt   # Folder KEK management
│       │   │   └── providers/            # Algorithm providers
│       │   └── util/                     # Utilities
│       └── res/                          # Resources
├── libs/                                 # Native AAR libraries
│   ├── kazkem-release.aar
│   └── kazsign-release.aar
├── build.gradle.kts
└── proguard-rules.pro
```

## Setup

### 1. Clone the Repository

```bash
git clone https://github.com/amiryahaya/secure-sharing.git
cd secure-sharing/android
```

### 2. Add PQC Libraries

Copy the KAZ-KEM and KAZ-SIGN AAR files to the `app/libs/` directory:

```bash
mkdir -p app/libs
cp /path/to/kazkem-release.aar app/libs/
cp /path/to/kazsign-release.aar app/libs/
```

### 3. Configure API Endpoint

Update the API base URL in `app/build.gradle.kts`:

```kotlin
// Debug (local development)
buildConfigField("String", "API_BASE_URL", "\"http://10.0.2.2:4000/api/\"")

// Release (production)
buildConfigField("String", "API_BASE_URL", "\"https://api.yourdomain.com/api/\"")
```

### 4. Configure Sentry (Optional)

Update the Sentry DSN in `app/build.gradle.kts`:

```kotlin
buildConfigField("String", "SENTRY_DSN", "\"https://your-key@your-org.ingest.sentry.io/project-id\"")
```

### 5. Build the Project

```bash
# Debug build
./gradlew assembleDebug

# Release build (requires signing config)
./gradlew assembleRelease
```

## Running

### Local Development

1. Start the backend server:
   ```bash
   cd ../  # SecureSharing root
   mix phx.server
   ```

2. Run the Android app:
   - Open the project in Android Studio
   - Select an emulator or connected device
   - Click Run (or press Shift+F10)

   Note: The emulator uses `10.0.2.2` to reach the host machine's localhost.

### Running Tests

```bash
# Unit tests
./gradlew test

# Instrumentation tests
./gradlew connectedAndroidTest
```

## Architecture

### Clean Architecture Layers

```
┌─────────────────────────────────────────────────────┐
│                  Presentation Layer                  │
│         (ViewModels, Screens, UI Components)         │
├─────────────────────────────────────────────────────┤
│                    Domain Layer                      │
│           (Use Cases, Repository Interfaces)         │
├─────────────────────────────────────────────────────┤
│                     Data Layer                       │
│    (Repository Impl, API Services, DAOs, Crypto)     │
└─────────────────────────────────────────────────────┘
```

### Key Hierarchy

```
Master Key (MK)
    │
    ├──► Encrypted with password (PBKDF2)
    │
    └──► Derives User KEK via HKDF
            │
            └──► Encrypts PQC Private Keys
                    ├── KAZ-KEM Private Key
                    ├── KAZ-SIGN Private Key
                    ├── ML-KEM Private Key
                    └── ML-DSA Private Key

Folder KEK (per folder)
    │
    ├──► Wrapped with parent folder KEK
    │
    └──► Owner copy wrapped with user's KEM keys

File DEK (per file)
    │
    ├──► Wrapped with folder KEK
    │
    └──► Encrypts file content (AES-256-GCM)
```

### Cryptographic Operations

| Operation | Algorithm(s) |
|-----------|-------------|
| Symmetric Encryption | AES-256-GCM |
| Key Derivation | HKDF-SHA384 |
| Key Wrapping | AES-256-KWP |
| Key Encapsulation | KAZ-KEM + ML-KEM-768 |
| Digital Signatures | KAZ-SIGN + ML-DSA-65 |
| Password Hashing | Argon2id (server) |
| Secret Sharing | Shamir's Secret Sharing |

## Security Features

- **Certificate Pinning**: SSL certificate pinning for API connections
- **Encrypted Storage**: Sensitive data stored in EncryptedSharedPreferences
- **Key Zeroization**: Cryptographic keys zeroed from memory after use
- **Root Detection**: Warning on rooted devices
- **Screen Capture Protection**: FLAG_SECURE prevents screenshots
- **Biometric Lock**: Optional biometric authentication
- **Secure Clipboard**: Auto-clear clipboard for sensitive data
- **Data Scrubbing**: Sensitive data stripped from crash reports

## Configuration

### Build Variants

| Variant | Description |
|---------|-------------|
| debug | Local development, logging enabled |
| release | Production, minified, ProGuard enabled |

### ProGuard

ProGuard rules are configured in `proguard-rules.pro` to:
- Keep native JNI methods for PQC libraries
- Preserve crypto provider classes
- Keep Bouncy Castle PQC classes

## API Endpoints

The app communicates with the SecureSharing backend API:

| Endpoint | Description |
|----------|-------------|
| `POST /auth/register` | User registration |
| `POST /auth/login` | User login |
| `GET /folders/root` | Get root folder |
| `POST /folders` | Create folder |
| `POST /files/upload-url` | Get presigned upload URL |
| `GET /files/{id}/download-url` | Get presigned download URL |
| `POST /shares/file` | Share a file |
| `POST /recovery/setup` | Setup key recovery |

See the backend documentation for the complete API reference.

## Contributing

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/amazing-feature`)
3. Commit your changes (`git commit -m 'Add amazing feature'`)
4. Push to the branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request

## License

This project is proprietary software. All rights reserved.

## Acknowledgments

- [KAZ-KEM/KAZ-SIGN](https://github.com/pqc-kaz) - Post-quantum cryptographic algorithms
- [Bouncy Castle](https://www.bouncycastle.org/) - NIST PQC algorithm implementations
- [Jetpack Compose](https://developer.android.com/jetpack/compose) - Modern Android UI toolkit
