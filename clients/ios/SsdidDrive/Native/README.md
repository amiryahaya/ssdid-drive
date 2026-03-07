# iOS Native PQC Libraries

This directory contains the native C implementations for ML-KEM and ML-DSA using liboqs, compiled as xcframeworks for iOS.

## Overview

The SsdidDrive iOS app uses post-quantum cryptography for secure file sharing. This includes:

- **ML-KEM-768** (NIST FIPS 203) - Key Encapsulation Mechanism for hybrid encryption
- **ML-DSA-65** (NIST FIPS 204) - Digital Signature Algorithm for authentication

Both implementations use [liboqs](https://github.com/open-quantum-safe/liboqs) (Open Quantum Safe) for the underlying cryptographic operations.

## Directory Structure

```
Native/
├── MlKemNative/
│   ├── include/
│   │   ├── mlkem.h           # C API header
│   │   └── module.modulemap  # Swift module map
│   └── src/
│       └── mlkem.c           # Implementation using liboqs
├── MlDsaNative/
│   ├── include/
│   │   ├── mldsa.h           # C API header
│   │   └── module.modulemap  # Swift module map
│   └── src/
│       └── mldsa.c           # Implementation using liboqs
├── build-xcframeworks.sh     # Build script
└── README.md                 # This file
```

## Prerequisites

Before building, ensure you have:

1. **Xcode** with command line tools installed
   ```bash
   xcode-select --install
   ```

2. **CMake** (for building liboqs)
   ```bash
   brew install cmake
   ```

3. **Ninja** (optional, but faster builds)
   ```bash
   brew install ninja
   ```

## Building the xcframeworks

Run the build script from this directory:

```bash
cd clients/ios/SsdidDrive/Native
./build-xcframeworks.sh
```

The script will:
1. Download liboqs v0.10.1
2. Build liboqs for all platforms (iOS device, simulator, macOS, Mac Catalyst)
3. Compile the ML-KEM and ML-DSA wrapper libraries
4. Create xcframeworks in `../Frameworks/`

### Build Output

After successful build:
- `../Frameworks/MlKemNative.xcframework`
- `../Frameworks/MlDsaNative.xcframework`

## Integration with Xcode

1. Add the xcframeworks to your Xcode project:
   - Drag `MlKemNative.xcframework` and `MlDsaNative.xcframework` into your project
   - Or use "Add Files to Project" and select both frameworks

2. In Build Settings:
   - Ensure "Framework Search Paths" includes the Frameworks directory
   - The Swift compiler will automatically detect the frameworks via `#if canImport(MlKemNative)`

## API Usage

### ML-KEM (Key Encapsulation)

```swift
import MlKemNative

// Initialize
try MlKem.initialize()

// Generate key pair
let keyPair = try MlKem.generateKeyPair()

// Encapsulate (sender side)
let result = try MlKem.encapsulate(publicKey: keyPair.publicKey)
// result.ciphertext - send this to recipient
// result.sharedSecret - use for symmetric encryption

// Decapsulate (recipient side)
let sharedSecret = try MlKem.decapsulate(
    ciphertext: result.ciphertext,
    secretKey: keyPair.secretKey
)

// Cleanup
MlKem.cleanup()
```

### ML-DSA (Digital Signatures)

```swift
import MlDsaNative

// Initialize
try MlDsa.initialize()

// Generate key pair
let keyPair = try MlDsa.generateKeyPair()

// Sign a message
let signature = try MlDsa.sign(
    message: messageData,
    secretKey: keyPair.secretKey
)

// Verify signature
let isValid = try MlDsa.verify(
    signature: signature.signature,
    message: messageData,
    publicKey: keyPair.publicKey
)

// Cleanup
MlDsa.cleanup()
```

### Static API (Compatible with existing code)

For compatibility with existing `MLKEM` and `MLDSA` enum usage:

```swift
// ML-KEM
let (publicKey, privateKey) = try MLKEM.generateKeyPair()
let (ciphertext, sharedSecret) = try MLKEM.encapsulate(publicKey: publicKey)
let recoveredSecret = try MLKEM.decapsulate(ciphertext: ciphertext, privateKey: privateKey)

// ML-DSA
let (pubKey, privKey) = try MLDSA.generateKeyPair()
let sig = try MLDSA.sign(message: data, privateKey: privKey)
let valid = try MLDSA.verify(signature: sig, message: data, publicKey: pubKey)
```

## Key Sizes (ML-KEM-768)

| Parameter | Size (bytes) |
|-----------|--------------|
| Public Key | 1184 |
| Secret Key | 2400 |
| Ciphertext | 1088 |
| Shared Secret | 32 |

## Key Sizes (ML-DSA-65)

| Parameter | Size (bytes) |
|-----------|--------------|
| Public Key | 1952 |
| Secret Key | 4032 |
| Signature | 3309 |

## Fallback Behavior

If the native frameworks are not available (e.g., during development without building), the Swift code falls back to a placeholder implementation. This allows the app to compile and run, but:

- **The placeholder is NOT cryptographically secure**
- Real security is provided by KAZ-KEM/KAZ-SIGN in the hybrid scheme
- For production builds, always include the native frameworks

## Troubleshooting

### Build fails with "SDK not found"
Ensure Xcode is properly installed and the iOS SDK is available:
```bash
xcrun --sdk iphoneos --show-sdk-path
```

### linker errors about missing symbols
The liboqs library may have been built incorrectly. Clean and rebuild:
```bash
rm -rf build/
./build-xcframeworks.sh
```

### Framework not found at runtime
Ensure the xcframeworks are properly embedded:
- In Xcode, select your target → General → Frameworks, Libraries, and Embedded Content
- Both frameworks should be listed with "Embed & Sign"

## Security Notes

1. **Memory Safety**: All secret keys are securely zeroed after use
2. **Thread Safety**: All operations are thread-safe with proper locking
3. **Side-Channel Resistance**: liboqs implementations include constant-time operations
4. **Hybrid Security**: Used alongside KAZ algorithms for defense-in-depth
