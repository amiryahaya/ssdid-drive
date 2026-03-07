# SecureSharing Windows Client - System Architecture Design Document

**Version:** 1.0
**Date:** 2026-01-20
**Author:** System Architecture Team
**Status:** Draft for Review

---

## Executive Summary

This document presents a comprehensive architectural design for the SecureSharing native Windows client, targeting Windows 10 (version 1903+) and Windows 11. The client will provide full feature parity with existing Android and iOS implementations while leveraging Windows-specific security capabilities including Windows Hello, DPAPI, TPM 2.0, and Windows Credential Manager.

The recommended technology stack is **WinUI 3 with .NET 10**, combined with **Rust native libraries** for post-quantum cryptography. This approach balances native Windows integration, modern UI capabilities, cryptographic performance, and long-term maintainability.

---

## Table of Contents

1. [Requirements Recap](#1-requirements-recap)
2. [Technology Stack Recommendation](#2-technology-stack-recommendation)
3. [Architecture Overview](#3-architecture-overview)
4. [Security Architecture](#4-security-architecture)
5. [UI/UX Considerations](#5-uiux-considerations)
6. [Cryptography Implementation Strategy](#6-cryptography-implementation-strategy)
7. [Data Storage and Sync Architecture](#7-data-storage-and-sync-architecture)
8. [Development Phases and Milestones](#8-development-phases-and-milestones)
9. [File Structure and Module Organization](#9-file-structure-and-module-organization)
10. [Alternative Approaches Considered](#10-alternative-approaches-considered)
11. [Risk Assessment](#11-risk-assessment)
12. [Open Questions](#12-open-questions)

---

## 1. Requirements Recap

### 1.1 Functional Requirements

| Requirement | Description | Priority |
|-------------|-------------|----------|
| User Authentication | Registration, login with MK derivation, WebAuthn support | Critical |
| File Management | Browse, upload, download, delete, rename, move files/folders | Critical |
| Encryption | Client-side PQC encryption (ML-KEM + KAZ-KEM, ML-DSA + KAZ-SIGN) | Critical |
| File Sharing | Share with users, permission management, share links | Critical |
| Key Recovery | Shamir secret sharing, trustee management | Critical |
| Offline Mode | Local caching, queued operations, background sync | High |
| Notifications | Push notifications, in-app notifications | High |
| Multi-Tenant | Support multiple tenant contexts | High |
| Search | Client-side file/folder search | Medium |
| Favorites | Star files for quick access | Medium |

### 1.2 Non-Functional Requirements

| Requirement | Specification |
|-------------|---------------|
| Platform Support | Windows 10 (1903+), Windows 11 |
| Form Factors | Desktop (mouse/keyboard), Tablet (touch) |
| Architecture | x64, ARM64 |
| Performance | File encryption <100ms/MB, UI response <100ms |
| Security | Zero-knowledge, FIPS 203/204 compliance ready |
| Offline Storage | Up to 10GB cached files |
| Memory | <200MB idle, <500MB active |

### 1.3 Security Requirements

- Windows Hello integration for biometric/PIN authentication
- DPAPI for secure credential storage
- TPM 2.0 for hardware-backed key protection (when available)
- Secure memory handling (zero on free)
- Screenshot prevention for sensitive documents
- Auto-lock on inactivity

---

## 2. Technology Stack Recommendation

### 2.1 Recommended Stack: WinUI 3 + .NET 10 + Rust

```
+--------------------------------------------------+
|                  Presentation Layer               |
|    WinUI 3 + Windows App SDK 1.5+ + XAML/C#      |
+--------------------------------------------------+
                         |
+--------------------------------------------------+
|                  Application Layer                |
|         .NET 10 + MVVM + Dependency Injection      |
+--------------------------------------------------+
                         |
+--------------------------------------------------+
|                   Domain Layer                    |
|     Use Cases + Repositories + Domain Models      |
+--------------------------------------------------+
                         |
+--------------------------------------------------+
|                   Data Layer                      |
|   SQLite (EF Core) + HTTP Client + File System   |
+--------------------------------------------------+
                         |
+--------------------------------------------------+
|              Native Crypto Layer                  |
|  Rust FFI: ML-KEM, ML-DSA, KAZ-KEM, KAZ-SIGN     |
+--------------------------------------------------+
                         |
+--------------------------------------------------+
|           Platform Security Layer                 |
|  Windows Hello + DPAPI + TPM 2.0 + Credential Mgr |
+--------------------------------------------------+
```

### 2.2 Technology Justification

| Component | Technology | Rationale |
|-----------|------------|-----------|
| **UI Framework** | WinUI 3 | Native Windows 11 design language, Fluent UI, responsive layouts, excellent touch support |
| **Runtime** | .NET 10 | Latest .NET with native AOT, improved performance, Windows integration |
| **MVVM Framework** | CommunityToolkit.Mvvm | Microsoft-supported, source generators, minimal boilerplate |
| **Dependency Injection** | Microsoft.Extensions.DI | Standard .NET DI, familiar patterns |
| **Local Database** | SQLite + EF Core | Cross-platform compatible schema, robust ORM |
| **HTTP Client** | System.Net.Http + Refit | Type-safe API calls, automatic serialization |
| **Crypto (PQC)** | Rust via P/Invoke | Performance-critical, proven implementations (pqcrypto crate) |
| **Crypto (Classic)** | System.Security.Cryptography | AES-GCM, SHA-256, HKDF built-in |
| **Key Derivation** | Konscious.Security.Cryptography | Argon2id implementation for .NET |
| **Windows Security** | Windows.Security.Credentials | Windows Hello, Credential Manager |

### 2.3 Alternative Analysis Summary

| Option | Pros | Cons | Verdict |
|--------|------|------|---------|
| **WinUI 3 + .NET** | Native feel, Windows integration, mature ecosystem | Windows-only | **Recommended** |
| **Tauri + Rust** | Cross-platform, small binary, Rust everywhere | Less native UI, WebView limitations | Good alternative |
| **.NET MAUI** | Cross-platform, single codebase | Desktop UI maturity issues, performance | Not recommended |
| **Electron** | Web tech, easy cross-platform | Large binary, memory heavy | Not recommended |

---

## 3. Architecture Overview

### 3.1 High-Level Architecture

```
                                    +------------------+
                                    |  SecureSharing   |
                                    |     Backend      |
                                    +--------+---------+
                                             |
                                     HTTPS/REST API
                                             |
+------------------------------------------------------------------------------------+
|                              Windows Client Application                             |
+------------------------------------------------------------------------------------+
|                                                                                    |
|  +---------------------------+  +---------------------------+  +----------------+  |
|  |    Presentation Layer     |  |    Presentation Layer     |  |   System Tray  |  |
|  |      (Desktop Mode)       |  |      (Tablet Mode)        |  |   Background   |  |
|  +---------------------------+  +---------------------------+  +----------------+  |
|              |                              |                          |           |
|  +-----------+------------------------------+------------+-------------+           |
|  |                        ViewModel Layer                              |           |
|  |    AuthViewModel | FilesViewModel | SharingViewModel | SettingsVM   |           |
|  +---------------------------------------------------------------------+           |
|                                      |                                             |
|  +---------------------------------------------------------------------+           |
|  |                         Domain Layer                                 |           |
|  |  +---------------+  +---------------+  +---------------+            |           |
|  |  | Auth Use Cases|  | File Use Cases|  |Share Use Cases|   ...      |           |
|  |  +---------------+  +---------------+  +---------------+            |           |
|  |                           |                                         |           |
|  |  +----------------------------------------------------------+      |           |
|  |  |              Repository Interfaces                        |      |           |
|  |  +----------------------------------------------------------+      |           |
|  +---------------------------------------------------------------------+           |
|                                      |                                             |
|  +---------------------------------------------------------------------+           |
|  |                          Data Layer                                 |           |
|  |  +----------------+  +----------------+  +--------------------+     |           |
|  |  | API Repository |  |Local Repository|  | Sync Coordinator   |     |           |
|  |  |   (Remote)     |  |   (SQLite)     |  | (Offline Queue)    |     |           |
|  |  +----------------+  +----------------+  +--------------------+     |           |
|  +---------------------------------------------------------------------+           |
|                                      |                                             |
|  +---------------------------------------------------------------------+           |
|  |                    Infrastructure Layer                             |           |
|  |  +---------------+  +---------------+  +------------------+         |           |
|  |  | CryptoManager |  | KeyManager    |  | SecureStorage    |         |           |
|  |  | (PQC + AES)   |  | (MK/KEK/DEK)  |  | (DPAPI/Hello)    |         |           |
|  |  +---------------+  +---------------+  +------------------+         |           |
|  |          |                  |                   |                   |           |
|  |  +----------------------------------------------------------+      |           |
|  |  |              Native Rust Crypto Library                   |      |           |
|  |  |     ML-KEM-768 | ML-DSA-65 | KAZ-KEM | KAZ-SIGN          |      |           |
|  |  +----------------------------------------------------------+      |           |
|  +---------------------------------------------------------------------+           |
|                                      |                                             |
|  +---------------------------------------------------------------------+           |
|  |                    Platform Integration                             |           |
|  |  Windows Hello | DPAPI | TPM 2.0 | Credential Manager | File System |           |
|  +---------------------------------------------------------------------+           |
|                                                                                    |
+------------------------------------------------------------------------------------+
```

### 3.2 Component Responsibilities

#### 3.2.1 Presentation Layer

| Component | Responsibility |
|-----------|----------------|
| **Shell** | Main window, navigation, adaptive layout switching |
| **AuthPages** | Login, registration, biometric setup, password change |
| **FilePages** | File browser, upload, download, preview, search |
| **SharingPages** | Share dialog, permissions, share links, received shares |
| **RecoveryPages** | Trustee setup, recovery requests, share approval |
| **SettingsPages** | Profile, security settings, notifications, about |
| **SystemTray** | Background operations, quick actions, notifications |

#### 3.2.2 ViewModel Layer

| Component | Responsibility |
|-----------|----------------|
| **AuthViewModel** | Login state, credential management, biometric flow |
| **FileBrowserViewModel** | File/folder listing, selection, navigation state |
| **FileUploadViewModel** | Upload queue, progress tracking, encryption status |
| **SharingViewModel** | Share creation, recipient search, permission editing |
| **RecoveryViewModel** | Trustee management, recovery request handling |
| **SettingsViewModel** | User preferences, security configuration |
| **SyncViewModel** | Sync status, offline queue, conflict resolution |

#### 3.2.3 Domain Layer

| Component | Responsibility |
|-----------|----------------|
| **LoginUseCase** | Orchestrate login flow, MK derivation, key loading |
| **RegisterUseCase** | Key generation, credential creation, recovery setup |
| **UploadFileUseCase** | Encrypt file, generate DEK, upload to server |
| **DownloadFileUseCase** | Download, decrypt, verify signatures |
| **ShareFileUseCase** | Re-encrypt DEK for recipient, create share grant |
| **CreateFolderUseCase** | Generate KEK, wrap for owner, create folder |
| **RecoveryUseCase** | Shamir split/combine, trustee communication |

#### 3.2.4 Data Layer

| Component | Responsibility |
|-----------|----------------|
| **ApiClient** | HTTP communication with backend, token management |
| **LocalDatabase** | SQLite via EF Core, encrypted metadata cache |
| **FileCache** | Local encrypted file storage, LRU eviction |
| **SyncCoordinator** | Offline queue, background sync, conflict detection |
| **NotificationService** | Push notification handling, OneSignal integration |

#### 3.2.5 Infrastructure Layer

| Component | Responsibility |
|-----------|----------------|
| **CryptoManager** | Hybrid encryption/decryption, dual signatures |
| **KeyManager** | Key hierarchy management (MK, KEK, DEK) |
| **SecureStorageService** | DPAPI encryption, Windows Hello integration |
| **TpmService** | TPM 2.0 key operations (when available) |
| **BiometricService** | Windows Hello enrollment and verification |

### 3.3 Data Flow Diagrams

#### 3.3.1 File Upload Flow

```
User selects file(s)
        |
        v
+------------------+
| FileUploadVM     |
| - Validate size  |
| - Check quota    |
+------------------+
        |
        v
+------------------+
| UploadFileUseCase|
+------------------+
        |
        v
+------------------+       +------------------+
| CryptoManager    |<------| KeyManager       |
| - Generate DEK   |       | - Get folder KEK |
| - Encrypt file   |       | - Wrap DEK       |
| - Sign content   |       +------------------+
+------------------+
        |
        v
+------------------+
| ApiRepository    |
| - Upload blob    |
| - Create file    |
|   record         |
+------------------+
        |
        v
+------------------+
| LocalRepository  |
| - Cache metadata |
| - Update folder  |
+------------------+
        |
        v
UI Update: File appears in list
```

#### 3.3.2 File Sharing Flow

```
User selects file, chooses recipient
        |
        v
+------------------+
| SharingViewModel |
| - Search users   |
| - Select perms   |
+------------------+
        |
        v
+------------------+
| ShareFileUseCase |
+------------------+
        |
        v
+------------------+       +------------------+
| ApiRepository    |------>| Get recipient    |
|                  |       | public keys      |
+------------------+       +------------------+
        |
        v
+------------------+       +------------------+
| CryptoManager    |<------| KeyManager       |
| - Decrypt DEK    |       | - Owner privkey  |
| - Re-encrypt for |       +------------------+
|   recipient      |
+------------------+
        |
        v
+------------------+
| ApiRepository    |
| - Create share   |
|   grant          |
+------------------+
        |
        v
Notification sent to recipient
```

---

## 4. Security Architecture

### 4.1 Key Hierarchy Implementation

The Windows client implements the same three-tier key hierarchy as mobile clients:

```
+-------------------------------------------------------------------+
|                         Master Key (MK)                            |
|  - 256-bit symmetric key                                          |
|  - Derived from password via Argon2id + HKDF-SHA384               |
|  - Or stored encrypted by Windows Hello credential                 |
|  - Protected by DPAPI when at rest                                |
+-------------------------------------------------------------------+
                                |
                    Unwraps (AES-256-GCM)
                                |
                                v
+-------------------------------------------------------------------+
|                    Key Encryption Key (KEK)                        |
|  - Per-folder key for organizing file access                      |
|  - Stored as wrapped_kek in folder metadata                       |
|  - Enables folder-level sharing                                   |
+-------------------------------------------------------------------+
                                |
                    Unwraps (AES-256-GCM)
                                |
                                v
+-------------------------------------------------------------------+
|                      Data Encryption Key (DEK)                     |
|  - Per-file key                                                   |
|  - Stored as wrapped_dek in file metadata                         |
|  - Used for AES-256-GCM file encryption                           |
+-------------------------------------------------------------------+
```

### 4.2 Windows Hello Integration

```
+-------------------------------------------------------------------+
|                    Windows Hello Authentication                    |
+-------------------------------------------------------------------+
|                                                                   |
|  Enrollment Flow:                                                 |
|  ================                                                 |
|  1. User logs in with password (derives MK)                       |
|  2. Create Windows Hello credential (face/fingerprint/PIN)        |
|  3. Generate protection key via Windows.Security.Credentials      |
|  4. Encrypt MK with protection key                                |
|  5. Store encrypted MK in Credential Manager                      |
|                                                                   |
|  Authentication Flow:                                             |
|  ====================                                             |
|  1. Prompt Windows Hello verification                             |
|  2. On success, retrieve protection key                           |
|  3. Load encrypted MK from Credential Manager                     |
|  4. Decrypt MK with protection key                                |
|  5. Proceed with normal session initialization                    |
|                                                                   |
|  Fallback:                                                        |
|  =========                                                        |
|  - 3 failed biometric attempts -> password entry                  |
|  - Windows Hello unavailable -> password only                     |
|                                                                   |
+-------------------------------------------------------------------+
```

#### 4.2.1 Windows Hello Implementation Details

```csharp
// Pseudo-code for Windows Hello integration
public class WindowsHelloService : IBiometricService
{
    public async Task<bool> IsAvailableAsync()
    {
        return await KeyCredentialManager.IsSupportedAsync();
    }

    public async Task<BiometricEnrollResult> EnrollAsync(byte[] masterKey)
    {
        // Create credential
        var result = await KeyCredentialManager.RequestCreateAsync(
            "SecureSharing_MasterKey",
            KeyCredentialCreationOption.ReplaceExisting);

        if (result.Status == KeyCredentialStatus.Success)
        {
            // Get the credential's public key for encryption
            var credential = result.Credential;

            // Generate a data protection key
            var protectionKey = CryptographicBuffer.GenerateRandom(32);

            // Encrypt MK with protection key
            var encryptedMK = EncryptWithAesGcm(masterKey, protectionKey);

            // Sign protection key with credential (proves possession)
            var signature = await credential.RequestSignAsync(
                CryptographicBuffer.CreateFromByteArray(protectionKey));

            // Store encrypted MK and signature in Credential Manager
            await StoreInCredentialManager(encryptedMK, signature);

            return BiometricEnrollResult.Success;
        }

        return BiometricEnrollResult.Failed;
    }

    public async Task<byte[]?> AuthenticateAsync()
    {
        var result = await KeyCredentialManager.OpenAsync("SecureSharing_MasterKey");

        if (result.Status == KeyCredentialStatus.Success)
        {
            // Retrieve encrypted MK
            var (encryptedMK, storedSignature) = await LoadFromCredentialManager();

            // Request verification (triggers biometric prompt)
            var signResult = await result.Credential.RequestSignAsync(
                CryptographicBuffer.CreateFromByteArray(/* challenge */));

            if (signResult.Status == KeyCredentialStatus.Success)
            {
                // Derive protection key and decrypt MK
                return DecryptMasterKey(encryptedMK);
            }
        }

        return null; // Fall back to password
    }
}
```

### 4.3 DPAPI Integration

```
+-------------------------------------------------------------------+
|                         DPAPI Usage                                |
+-------------------------------------------------------------------+
|                                                                   |
|  Protected Data:                                                  |
|  ===============                                                  |
|  1. Encrypted Master Key (when biometrics disabled)               |
|  2. Session tokens                                                |
|  3. Cached credentials                                            |
|  4. Local database encryption key                                 |
|                                                                   |
|  Protection Scope:                                                |
|  =================                                                |
|  - CurrentUser scope (default)                                    |
|  - Data tied to Windows user account                              |
|  - Portable across user's devices (with roaming profile)          |
|                                                                   |
|  Implementation:                                                  |
|  ===============                                                  |
|  using System.Security.Cryptography;                              |
|                                                                   |
|  byte[] Protect(byte[] data)                                      |
|  {                                                                |
|      return ProtectedData.Protect(                                |
|          data,                                                    |
|          entropy,  // App-specific additional entropy             |
|          DataProtectionScope.CurrentUser                          |
|      );                                                           |
|  }                                                                |
|                                                                   |
+-------------------------------------------------------------------+
```

### 4.4 TPM 2.0 Integration

```
+-------------------------------------------------------------------+
|                      TPM 2.0 Usage                                 |
+-------------------------------------------------------------------+
|                                                                   |
|  Primary Use Cases:                                               |
|  ==================                                               |
|  1. Hardware-backed storage for biometric protection key          |
|  2. Device attestation (proving genuine Windows device)           |
|  3. Secure random number generation                               |
|                                                                   |
|  Detection & Fallback:                                            |
|  =====================                                            |
|  - Check TPM availability via WMI or TBS API                      |
|  - If unavailable: fall back to software-only DPAPI               |
|  - Log security level for audit purposes                          |
|                                                                   |
|  Windows Hello + TPM:                                             |
|  ====================                                             |
|  - Windows Hello automatically uses TPM when available            |
|  - No additional code needed for TPM-backed biometrics            |
|  - KeyCredentialManager handles TPM interaction                   |
|                                                                   |
|  Device Attestation (Optional):                                   |
|  ==============================                                   |
|  - Generate TPM-backed key pair for device identity               |
|  - Send public key + attestation to server during enrollment      |
|  - Server can verify device authenticity                          |
|                                                                   |
+-------------------------------------------------------------------+
```

### 4.5 Credential Manager Integration

```
+-------------------------------------------------------------------+
|                   Windows Credential Manager                       |
+-------------------------------------------------------------------+
|                                                                   |
|  Stored Credentials:                                              |
|  ===================                                              |
|  - Target: "SecureSharing/{tenantId}/{userId}"                    |
|  - Username: User email                                           |
|  - Password: Encrypted access token (DPAPI protected)             |
|                                                                   |
|  Additional Entries:                                              |
|  ===================                                              |
|  - "SecureSharing/BiometricKey": Encrypted MK for Hello           |
|  - "SecureSharing/DeviceId": Unique device identifier             |
|                                                                   |
|  Benefits:                                                        |
|  =========                                                        |
|  - Survives app reinstall                                         |
|  - User can view/delete in Control Panel                          |
|  - Follows Windows security policies                              |
|                                                                   |
+-------------------------------------------------------------------+
```

### 4.6 Secure Memory Handling

```csharp
// Secure byte array that zeros memory on disposal
public sealed class SecureBytes : IDisposable
{
    private byte[] _data;
    private bool _disposed;

    public SecureBytes(int length)
    {
        _data = new byte[length];
    }

    public Span<byte> AsSpan() => _data.AsSpan();

    public void Dispose()
    {
        if (!_disposed)
        {
            CryptographicOperations.ZeroMemory(_data);
            _disposed = true;
        }
    }
}

// Usage pattern
using var masterKey = new SecureBytes(32);
DeriveKeyFromPassword(password, masterKey.AsSpan());
// Key is zeroed when scope exits
```

### 4.7 Security State Machine

```
+-------------+     Password/Biometric     +-------------+
|   Locked    |-------------------------->|  Unlocked   |
|             |                           |             |
| - No keys   |     Timeout/Manual Lock   | - MK in     |
|   in memory |<--------------------------| - KEKs      |
| - UI locked |                           |   cached    |
+-------------+                           +-------------+
      |                                         |
      | App Close                               | Background
      v                                         v
+-------------+                           +-------------+
|   Closed    |                           | Background  |
|             |                           |             |
| - All keys  |                           | - MK may    |
|   cleared   |                           |   persist   |
| - Session   |                           | - Limited   |
|   ended     |                           |   ops only  |
+-------------+                           +-------------+
```

### 4.8 Auto-Lock Implementation

```csharp
public class AutoLockService
{
    private readonly ISecuritySettings _settings;
    private readonly IKeyManager _keyManager;
    private DispatcherTimer _timer;
    private DateTime _lastActivity;

    public void Initialize()
    {
        // Monitor user activity
        InputManager.Current.PostProcessInput += OnUserActivity;

        // Start inactivity timer
        _timer = new DispatcherTimer
        {
            Interval = TimeSpan.FromSeconds(30)
        };
        _timer.Tick += CheckInactivity;
        _timer.Start();

        // Monitor app lifecycle
        Application.Current.EnteredBackground += OnAppBackground;
    }

    private void CheckInactivity(object sender, object e)
    {
        var timeout = _settings.AutoLockTimeout;
        if (timeout == TimeSpan.Zero) return; // Disabled

        if (DateTime.UtcNow - _lastActivity > timeout)
        {
            LockApplication();
        }
    }

    private void LockApplication()
    {
        _keyManager.ClearSessionKeys();
        NavigationService.NavigateToLockScreen();
    }
}
```

---

## 5. UI/UX Considerations

### 5.1 Adaptive Layout Strategy

The application supports two primary modes with automatic switching based on input method and window size:

```
+-------------------------------------------------------------------+
|                      Desktop Mode (>768px)                         |
+-------------------------------------------------------------------+
| +----------+ +---------------------------------------------------+ |
| |          | |                                                   | |
| | Nav Rail | |              Content Area                         | |
| | (Fixed)  | |                                                   | |
| |          | | +-----------------------------------------------+ | |
| | [Files]  | | |            Toolbar                             | | |
| | [Shared] | | | [Upload] [New Folder] [Search...] [View] [Sort]| | |
| | [Recent] | | +-----------------------------------------------+ | |
| | [Trash]  | |                                                   | |
| |          | | +-----------------------------------------------+ | |
| | -------- | | |           File/Folder Grid or List            | | |
| |          | | |                                                 | | |
| | [Notif]  | | |  [Folder]  [Folder]  [File]    [File]         | | |
| | [Settings| | |  [File]    [File]    [File]    [File]         | | |
| |          | | |                                                 | | |
| +----------+ | +-----------------------------------------------+ | |
|              |                                                   | |
|              | +-----------------------------------------------+ | |
|              | |            Status Bar                          | | |
|              | | [Sync: Up to date] [2 items selected] [Usage]  | | |
|              | +-----------------------------------------------+ | |
|              +---------------------------------------------------+ |
+-------------------------------------------------------------------+
```

```
+-------------------------------------------------------------------+
|                      Tablet Mode (<768px)                          |
+-------------------------------------------------------------------+
| +---------------------------------------------------------------+ |
| |  [=]  Files                              [Search] [Upload]    | |
| +---------------------------------------------------------------+ |
| |                                                               | |
| |  +----------------------------------------------------------+ | |
| |  |                    File List                              | | |
| |  |                                                           | | |
| |  |  +-----------------------------------------------------+  | | |
| |  |  | [Icon] Document.pdf                                 |  | | |
| |  |  |        Modified: Jan 20, 2026  Size: 2.4 MB        >|  | | |
| |  |  +-----------------------------------------------------+  | | |
| |  |                                                           | | |
| |  |  +-----------------------------------------------------+  | | |
| |  |  | [Icon] Project Folder                               |  | | |
| |  |  |        12 items                                    >|  | | |
| |  |  +-----------------------------------------------------+  | | |
| |  |                                                           | | |
| |  +----------------------------------------------------------+ | |
| |                                                               | |
| +---------------------------------------------------------------+ |
| |  [Files]    [Shared]    [Recent]    [Settings]               | |
| +---------------------------------------------------------------+ |
+-------------------------------------------------------------------+
```

### 5.2 Mode Detection and Switching

```csharp
public class AdaptiveLayoutService
{
    public LayoutMode CurrentMode { get; private set; }

    public void Initialize(Window window)
    {
        window.SizeChanged += OnWindowSizeChanged;

        // Detect touch input
        var pointer = PointerDevice.GetPointerDevices()
            .Any(d => d.PointerDeviceType == PointerDeviceType.Touch);

        UpdateLayoutMode(window.Bounds.Width, pointer);
    }

    private void UpdateLayoutMode(double width, bool hasTouch)
    {
        CurrentMode = (width, hasTouch) switch
        {
            (< 768, _) => LayoutMode.Tablet,
            (_, true) when TabletModeEnabled => LayoutMode.Tablet,
            _ => LayoutMode.Desktop
        };

        OnLayoutModeChanged?.Invoke(CurrentMode);
    }
}
```

### 5.3 Component Design Specifications

#### 5.3.1 File Browser

| Mode | Layout | Interactions |
|------|--------|--------------|
| Desktop | Grid (default) or List view | Click to select, double-click to open, right-click for context menu |
| Tablet | List view only | Tap to select, long-press for context menu, swipe for quick actions |

#### 5.3.2 File Preview

| Feature | Desktop | Tablet |
|---------|---------|--------|
| Window | Separate window or side panel | Full-screen overlay |
| Navigation | Keyboard arrows | Swipe gestures |
| Actions | Toolbar buttons | Bottom action bar |
| Zoom | Mouse scroll + Ctrl | Pinch-to-zoom |

#### 5.3.3 Dialogs

| Dialog Type | Desktop | Tablet |
|-------------|---------|--------|
| Share | Modal dialog (400px width) | Full-screen |
| Settings | Side panel (600px) | Full-screen with back nav |
| Confirmation | Centered modal | Bottom sheet |

### 5.4 Touch Optimization

```xaml
<!-- Touch-friendly list item template -->
<DataTemplate x:Key="FileListItemTemplate">
    <Grid MinHeight="64" Padding="16,12">
        <Grid.ColumnDefinitions>
            <ColumnDefinition Width="48"/>
            <ColumnDefinition Width="*"/>
            <ColumnDefinition Width="Auto"/>
        </Grid.ColumnDefinitions>

        <!-- Icon with touch target -->
        <Border Width="40" Height="40" CornerRadius="4">
            <Image Source="{Binding Icon}" Stretch="Uniform"/>
        </Border>

        <!-- File info -->
        <StackPanel Grid.Column="1" Margin="12,0" VerticalAlignment="Center">
            <TextBlock Text="{Binding Name}" Style="{StaticResource BodyTextStyle}"/>
            <TextBlock Text="{Binding Subtitle}" Style="{StaticResource CaptionTextStyle}"/>
        </StackPanel>

        <!-- Chevron for navigation -->
        <FontIcon Grid.Column="2" Glyph="&#xE76C;" FontSize="14"/>
    </Grid>
</DataTemplate>
```

### 5.5 Keyboard Navigation

| Action | Shortcut |
|--------|----------|
| Upload file | Ctrl+U |
| New folder | Ctrl+Shift+N |
| Search | Ctrl+F |
| Select all | Ctrl+A |
| Delete | Delete |
| Refresh | F5 |
| Properties | Alt+Enter |
| Share | Ctrl+Shift+S |
| Download | Ctrl+D |
| Navigation back | Alt+Left |
| Navigation forward | Alt+Right |

### 5.6 Accessibility

- **Screen Reader Support**: All interactive elements have AutomationProperties
- **High Contrast**: Respect system high contrast themes
- **Keyboard Navigation**: Full tab navigation support
- **Reduced Motion**: Respect prefers-reduced-motion setting
- **Text Scaling**: Support 100%-400% system text scaling

---

## 6. Cryptography Implementation Strategy

### 6.1 Algorithm Suite

| Algorithm | Purpose | Implementation |
|-----------|---------|----------------|
| **ML-KEM-768** | NIST PQC key encapsulation | Rust (pqcrypto-kyber) |
| **ML-DSA-65** | NIST PQC digital signature | Rust (pqcrypto-dilithium) |
| **KAZ-KEM** | Secondary KEM (hybrid defense) | Rust (custom port) |
| **KAZ-SIGN** | Secondary signature (hybrid defense) | Rust (custom port) |
| **AES-256-GCM** | Symmetric encryption | .NET BCL |
| **SHA-256** | Hashing, key derivation | .NET BCL |
| **HKDF-SHA384** | Key derivation | .NET BCL |
| **Argon2id** | Password hashing | Konscious.Security.Cryptography |

### 6.2 Native Library Architecture

```
/native/windows_crypto/
├── Cargo.toml
├── src/
│   ├── lib.rs           # FFI exports
│   ├── ml_kem.rs        # ML-KEM-768 wrapper
│   ├── ml_dsa.rs        # ML-DSA-65 wrapper
│   ├── kaz_kem.rs       # KAZ-KEM implementation
│   ├── kaz_sign.rs      # KAZ-SIGN implementation
│   └── ffi.rs           # C ABI definitions
└── build/
    ├── x64/
    │   └── securesharing_crypto.dll
    └── arm64/
        └── securesharing_crypto.dll
```

### 6.3 FFI Interface Definition

```rust
// lib.rs - Rust FFI exports
use std::slice;

/// ML-KEM-768 key pair generation
#[no_mangle]
pub extern "C" fn mlkem_keygen(
    public_key: *mut u8,    // 1184 bytes
    secret_key: *mut u8,    // 2400 bytes
) -> i32 {
    // Implementation
}

/// ML-KEM-768 encapsulation
#[no_mangle]
pub extern "C" fn mlkem_encapsulate(
    public_key: *const u8,  // 1184 bytes
    ciphertext: *mut u8,    // 1088 bytes
    shared_secret: *mut u8, // 32 bytes
) -> i32 {
    // Implementation
}

/// ML-KEM-768 decapsulation
#[no_mangle]
pub extern "C" fn mlkem_decapsulate(
    secret_key: *const u8,   // 2400 bytes
    ciphertext: *const u8,   // 1088 bytes
    shared_secret: *mut u8,  // 32 bytes
) -> i32 {
    // Implementation
}

// Similar exports for ML-DSA, KAZ-KEM, KAZ-SIGN...
```

### 6.4 C# P/Invoke Wrapper

```csharp
// NativeCrypto.cs
internal static class NativeCrypto
{
    private const string DllName = "securesharing_crypto";

    // ML-KEM-768
    public const int MLKEM_PUBLIC_KEY_SIZE = 1184;
    public const int MLKEM_SECRET_KEY_SIZE = 2400;
    public const int MLKEM_CIPHERTEXT_SIZE = 1088;
    public const int MLKEM_SHARED_SECRET_SIZE = 32;

    [DllImport(DllName, CallingConvention = CallingConvention.Cdecl)]
    public static extern int mlkem_keygen(
        byte[] publicKey,
        byte[] secretKey
    );

    [DllImport(DllName, CallingConvention = CallingConvention.Cdecl)]
    public static extern int mlkem_encapsulate(
        byte[] publicKey,
        byte[] ciphertext,
        byte[] sharedSecret
    );

    [DllImport(DllName, CallingConvention = CallingConvention.Cdecl)]
    public static extern int mlkem_decapsulate(
        byte[] secretKey,
        byte[] ciphertext,
        byte[] sharedSecret
    );

    // ML-DSA-65
    public const int MLDSA_PUBLIC_KEY_SIZE = 1952;
    public const int MLDSA_SECRET_KEY_SIZE = 4032;
    public const int MLDSA_SIGNATURE_SIZE = 3309;

    [DllImport(DllName, CallingConvention = CallingConvention.Cdecl)]
    public static extern int mldsa_keygen(
        byte[] publicKey,
        byte[] secretKey
    );

    [DllImport(DllName, CallingConvention = CallingConvention.Cdecl)]
    public static extern int mldsa_sign(
        byte[] secretKey,
        byte[] message,
        int messageLen,
        byte[] signature,
        out int signatureLen
    );

    [DllImport(DllName, CallingConvention = CallingConvention.Cdecl)]
    public static extern int mldsa_verify(
        byte[] publicKey,
        byte[] message,
        int messageLen,
        byte[] signature,
        int signatureLen
    );

    // KAZ-KEM and KAZ-SIGN similar...
}
```

### 6.5 CryptoManager Implementation

```csharp
public sealed class CryptoManager : ICryptoManager
{
    private readonly IKeyManager _keyManager;

    // Encrypted envelope structure (matches mobile implementations)
    public record EncryptedEnvelope(
        byte[] KazKemCiphertext,
        byte[] MlKemCiphertext,
        byte[] Nonce,
        byte[] EncryptedContent,
        byte[] AuthTag,
        byte[]? KazSignSignature,
        byte[]? MlDsaSignature
    );

    public EncryptedEnvelope Encrypt(
        ReadOnlySpan<byte> plaintext,
        PublicKeys recipientKeys,
        bool sign = true)
    {
        // 1. Hybrid encapsulation
        var (kazCiphertext, kazSecret) = KazKemEncapsulate(recipientKeys.KazKemPublicKey);
        var (mlCiphertext, mlSecret) = MlKemEncapsulate(recipientKeys.MlKemPublicKey);

        // 2. Combine secrets: SHA256(kazSecret || mlSecret)
        using var combinedSecret = new SecureBytes(64);
        kazSecret.CopyTo(combinedSecret.AsSpan()[..32]);
        mlSecret.CopyTo(combinedSecret.AsSpan()[32..]);

        var encryptionKey = SHA256.HashData(combinedSecret.AsSpan());

        // 3. Encrypt with AES-256-GCM
        var nonce = RandomNumberGenerator.GetBytes(12);
        var ciphertext = new byte[plaintext.Length];
        var tag = new byte[16];

        using var aes = new AesGcm(encryptionKey, 16);
        aes.Encrypt(nonce, plaintext, ciphertext, tag);

        // 4. Optionally sign
        byte[]? kazSig = null, mlSig = null;
        if (sign && _keyManager.CurrentKeyBundle != null)
        {
            kazSig = KazSign(ciphertext, _keyManager.CurrentKeyBundle.KazSignPrivateKey);
            mlSig = MlDsaSign(ciphertext, _keyManager.CurrentKeyBundle.MlDsaPrivateKey);
        }

        // 5. Zero sensitive data
        CryptographicOperations.ZeroMemory(encryptionKey);
        CryptographicOperations.ZeroMemory(kazSecret);
        CryptographicOperations.ZeroMemory(mlSecret);

        return new EncryptedEnvelope(
            kazCiphertext, mlCiphertext, nonce,
            ciphertext, tag, kazSig, mlSig
        );
    }

    public byte[] Decrypt(EncryptedEnvelope envelope)
    {
        var keyBundle = _keyManager.CurrentKeyBundle
            ?? throw new CryptoException("Keys not available");

        // 1. Hybrid decapsulation
        var kazSecret = KazKemDecapsulate(
            envelope.KazKemCiphertext,
            keyBundle.KazKemPrivateKey
        );
        var mlSecret = MlKemDecapsulate(
            envelope.MlKemCiphertext,
            keyBundle.MlKemPrivateKey
        );

        // 2. Combine secrets
        using var combinedSecret = new SecureBytes(64);
        kazSecret.CopyTo(combinedSecret.AsSpan()[..32]);
        mlSecret.CopyTo(combinedSecret.AsSpan()[32..]);

        var decryptionKey = SHA256.HashData(combinedSecret.AsSpan());

        // 3. Decrypt
        var plaintext = new byte[envelope.EncryptedContent.Length];
        using var aes = new AesGcm(decryptionKey, 16);
        aes.Decrypt(envelope.Nonce, envelope.EncryptedContent, envelope.AuthTag, plaintext);

        // 4. Zero sensitive data
        CryptographicOperations.ZeroMemory(decryptionKey);
        CryptographicOperations.ZeroMemory(kazSecret);
        CryptographicOperations.ZeroMemory(mlSecret);

        return plaintext;
    }

    private (byte[] ciphertext, byte[] secret) MlKemEncapsulate(byte[] publicKey)
    {
        var ciphertext = new byte[NativeCrypto.MLKEM_CIPHERTEXT_SIZE];
        var secret = new byte[NativeCrypto.MLKEM_SHARED_SECRET_SIZE];

        var result = NativeCrypto.mlkem_encapsulate(publicKey, ciphertext, secret);
        if (result != 0)
            throw new CryptoException($"ML-KEM encapsulation failed: {result}");

        return (ciphertext, secret);
    }

    // Similar implementations for other operations...
}
```

### 6.6 Key Derivation

```csharp
public class KeyDerivationService : IKeyDerivationService
{
    // Argon2id parameters (matching mobile implementations)
    private const int MemoryCost = 65536;  // 64 MiB
    private const int TimeCost = 3;
    private const int Parallelism = 4;
    private const int HashLength = 32;

    public byte[] DeriveKeyFromPassword(string password, byte[] salt)
    {
        using var argon2 = new Argon2id(Encoding.UTF8.GetBytes(password))
        {
            Salt = salt,
            MemorySize = MemoryCost,
            Iterations = TimeCost,
            DegreeOfParallelism = Parallelism
        };

        return argon2.GetBytes(HashLength);
    }

    public byte[] DeriveKeyWithHkdf(byte[] inputKey, byte[] salt, byte[] info, int length)
    {
        return HKDF.DeriveKey(
            HashAlgorithmName.SHA384,
            inputKey,
            length,
            salt,
            info
        );
    }
}
```

---

## 7. Data Storage and Sync Architecture

### 7.1 Local Database Schema

```sql
-- SQLite schema for local storage (encrypted at rest via DPAPI)

-- Cached user data
CREATE TABLE users (
    id TEXT PRIMARY KEY,
    tenant_id TEXT NOT NULL,
    email TEXT NOT NULL,
    name TEXT,
    public_keys_json TEXT NOT NULL,  -- Encrypted
    last_synced_at INTEGER,
    UNIQUE(tenant_id, email)
);

-- Folder cache
CREATE TABLE folders (
    id TEXT PRIMARY KEY,
    tenant_id TEXT NOT NULL,
    parent_id TEXT,
    name_encrypted TEXT NOT NULL,    -- Encrypted with parent KEK
    owner_id TEXT NOT NULL,
    created_at INTEGER NOT NULL,
    updated_at INTEGER NOT NULL,
    wrapped_kek TEXT,                -- For owner access
    is_shared INTEGER DEFAULT 0,
    last_synced_at INTEGER,
    sync_status TEXT DEFAULT 'synced',
    FOREIGN KEY (parent_id) REFERENCES folders(id)
);

-- File metadata cache
CREATE TABLE files (
    id TEXT PRIMARY KEY,
    tenant_id TEXT NOT NULL,
    folder_id TEXT NOT NULL,
    name_encrypted TEXT NOT NULL,    -- Encrypted with folder KEK
    mime_type TEXT,
    size INTEGER NOT NULL,
    owner_id TEXT NOT NULL,
    created_at INTEGER NOT NULL,
    updated_at INTEGER NOT NULL,
    wrapped_dek TEXT NOT NULL,
    blob_storage_key TEXT,
    checksum TEXT,
    last_synced_at INTEGER,
    sync_status TEXT DEFAULT 'synced',
    local_cache_path TEXT,           -- Path to local encrypted file
    is_favorited INTEGER DEFAULT 0,
    FOREIGN KEY (folder_id) REFERENCES folders(id)
);

-- Share grants cache
CREATE TABLE share_grants (
    id TEXT PRIMARY KEY,
    resource_type TEXT NOT NULL,     -- 'file' or 'folder'
    resource_id TEXT NOT NULL,
    grantor_id TEXT NOT NULL,
    grantee_id TEXT NOT NULL,
    permission TEXT NOT NULL,        -- 'viewer' or 'editor'
    encrypted_key TEXT NOT NULL,     -- Re-encrypted for grantee
    expires_at INTEGER,
    created_at INTEGER NOT NULL,
    last_synced_at INTEGER
);

-- Offline operation queue
CREATE TABLE sync_queue (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    operation_type TEXT NOT NULL,    -- 'create', 'update', 'delete', 'upload'
    resource_type TEXT NOT NULL,     -- 'file', 'folder', 'share'
    resource_id TEXT,
    payload_json TEXT NOT NULL,      -- Operation-specific data
    created_at INTEGER NOT NULL,
    retry_count INTEGER DEFAULT 0,
    last_error TEXT,
    status TEXT DEFAULT 'pending'    -- 'pending', 'in_progress', 'failed', 'completed'
);

-- Notifications cache
CREATE TABLE notifications (
    id TEXT PRIMARY KEY,
    type TEXT NOT NULL,
    title TEXT NOT NULL,
    body TEXT,
    data_json TEXT,
    is_read INTEGER DEFAULT 0,
    created_at INTEGER NOT NULL
);

-- Indices
CREATE INDEX idx_folders_parent ON folders(parent_id);
CREATE INDEX idx_folders_tenant ON folders(tenant_id);
CREATE INDEX idx_files_folder ON files(folder_id);
CREATE INDEX idx_files_tenant ON files(tenant_id);
CREATE INDEX idx_files_favorited ON files(is_favorited) WHERE is_favorited = 1;
CREATE INDEX idx_sync_queue_status ON sync_queue(status);
CREATE INDEX idx_share_grants_grantee ON share_grants(grantee_id);
```

### 7.2 File Cache Strategy

```
+-------------------------------------------------------------------+
|                      Local File Cache                              |
+-------------------------------------------------------------------+
|                                                                   |
|  Location: %LOCALAPPDATA%\SecureSharing\Cache\                    |
|                                                                   |
|  Structure:                                                       |
|  ==========                                                       |
|  Cache/                                                           |
|  ├── {tenant_id}/                                                 |
|  │   ├── files/                                                   |
|  │   │   ├── {file_id}.enc          # Encrypted file content     |
|  │   │   └── {file_id}.meta         # Local metadata             |
|  │   ├── thumbnails/                                              |
|  │   │   └── {file_id}.thumb        # Encrypted thumbnail        |
|  │   └── temp/                                                    |
|  │       └── upload_{uuid}.tmp      # Pending uploads            |
|  └── database.db                    # SQLite (DPAPI encrypted)    |
|                                                                   |
|  Cache Policy:                                                    |
|  =============                                                    |
|  - Max size: 10 GB (configurable)                                 |
|  - Eviction: LRU with priority for favorites                      |
|  - Favorites: Never evicted automatically                         |
|  - Cleanup: On app start, remove orphaned files                   |
|                                                                   |
+-------------------------------------------------------------------+
```

### 7.3 Sync Coordinator

```csharp
public class SyncCoordinator : ISyncCoordinator
{
    private readonly IApiClient _apiClient;
    private readonly ILocalRepository _localRepo;
    private readonly ISyncQueue _syncQueue;
    private readonly IConnectivityService _connectivity;

    private CancellationTokenSource? _syncCts;

    public SyncState CurrentState { get; private set; }

    public async Task StartBackgroundSyncAsync()
    {
        _syncCts = new CancellationTokenSource();

        while (!_syncCts.IsCancellationRequested)
        {
            if (_connectivity.IsConnected)
            {
                await SyncCycleAsync(_syncCts.Token);
            }

            await Task.Delay(TimeSpan.FromMinutes(5), _syncCts.Token);
        }
    }

    private async Task SyncCycleAsync(CancellationToken ct)
    {
        try
        {
            CurrentState = SyncState.Syncing;
            OnSyncStateChanged?.Invoke(CurrentState);

            // 1. Process offline queue (local -> remote)
            await ProcessOfflineQueueAsync(ct);

            // 2. Fetch remote changes (remote -> local)
            await FetchRemoteChangesAsync(ct);

            // 3. Resolve conflicts if any
            await ResolveConflictsAsync(ct);

            CurrentState = SyncState.Synced;
        }
        catch (OperationCanceledException)
        {
            CurrentState = SyncState.Paused;
        }
        catch (Exception ex)
        {
            CurrentState = SyncState.Error;
            LastError = ex.Message;
        }
        finally
        {
            OnSyncStateChanged?.Invoke(CurrentState);
        }
    }

    private async Task ProcessOfflineQueueAsync(CancellationToken ct)
    {
        var pendingOps = await _syncQueue.GetPendingOperationsAsync();

        foreach (var op in pendingOps)
        {
            ct.ThrowIfCancellationRequested();

            try
            {
                await ExecuteOperationAsync(op, ct);
                await _syncQueue.MarkCompletedAsync(op.Id);
            }
            catch (ConflictException)
            {
                // Mark for conflict resolution
                await _syncQueue.MarkConflictAsync(op.Id);
            }
            catch (Exception ex)
            {
                op.RetryCount++;
                op.LastError = ex.Message;

                if (op.RetryCount >= 3)
                {
                    await _syncQueue.MarkFailedAsync(op.Id, ex.Message);
                }
            }
        }
    }

    private async Task FetchRemoteChangesAsync(CancellationToken ct)
    {
        var lastSync = await _localRepo.GetLastSyncTimestampAsync();

        // Fetch changed folders
        var folders = await _apiClient.GetFoldersAsync(modifiedSince: lastSync, ct);
        foreach (var folder in folders)
        {
            await _localRepo.UpsertFolderAsync(folder);
        }

        // Fetch changed files
        var files = await _apiClient.GetFilesAsync(modifiedSince: lastSync, ct);
        foreach (var file in files)
        {
            await _localRepo.UpsertFileAsync(file);
        }

        // Fetch new shares
        var shares = await _apiClient.GetReceivedSharesAsync(modifiedSince: lastSync, ct);
        foreach (var share in shares)
        {
            await _localRepo.UpsertShareGrantAsync(share);
        }

        await _localRepo.SetLastSyncTimestampAsync(DateTime.UtcNow);
    }
}
```

### 7.4 Conflict Resolution

```
+-------------------------------------------------------------------+
|                    Conflict Resolution Strategy                    |
+-------------------------------------------------------------------+
|                                                                   |
|  Conflict Types:                                                  |
|  ===============                                                  |
|  1. Edit-Edit: Both local and remote modified same file          |
|  2. Edit-Delete: Local edit, remote delete (or vice versa)       |
|  3. Create-Create: Same name created in same folder              |
|                                                                   |
|  Resolution Policies:                                             |
|  ====================                                             |
|                                                                   |
|  Default: "Last Write Wins"                                       |
|  - Compare timestamps, keep newer version                         |
|  - Archive older version locally (optional recovery)              |
|                                                                   |
|  User Prompt (for significant conflicts):                         |
|  - Show diff if text file                                         |
|  - Options: Keep Local, Keep Remote, Keep Both, Merge             |
|                                                                   |
|  Auto-Resolve Rules:                                              |
|  - Metadata-only changes: merge silently                          |
|  - Content changes within 1 minute: prompt user                   |
|  - Delete vs edit: prompt user                                    |
|                                                                   |
+-------------------------------------------------------------------+
```

### 7.5 Offline Queue Operations

```csharp
public class SyncQueue : ISyncQueue
{
    public enum OperationType
    {
        CreateFolder,
        RenameFolder,
        MoveFolder,
        DeleteFolder,
        UploadFile,
        RenameFile,
        MoveFile,
        DeleteFile,
        CreateShare,
        RevokeShare,
        UpdateShare
    }

    public async Task QueueOperationAsync(OperationType type, string resourceType,
        string? resourceId, object payload)
    {
        var operation = new SyncOperation
        {
            OperationType = type.ToString(),
            ResourceType = resourceType,
            ResourceId = resourceId,
            PayloadJson = JsonSerializer.Serialize(payload),
            CreatedAt = DateTime.UtcNow,
            Status = "pending"
        };

        await _database.InsertAsync(operation);

        // Trigger immediate sync if online
        if (_connectivity.IsConnected)
        {
            _ = _syncCoordinator.TriggerSyncAsync();
        }
    }

    public async Task<List<SyncOperation>> GetPendingOperationsAsync()
    {
        return await _database.Table<SyncOperation>()
            .Where(o => o.Status == "pending")
            .OrderBy(o => o.CreatedAt)
            .ToListAsync();
    }
}
```

---

## 8. Development Phases and Milestones

### Phase 1: Foundation (8 weeks)

**Objective:** Establish core infrastructure and security foundation

| Week | Deliverables |
|------|--------------|
| 1-2 | Project setup, CI/CD, architecture scaffolding |
| 3-4 | Rust crypto library (ML-KEM, ML-DSA), P/Invoke wrappers |
| 5-6 | KAZ-KEM, KAZ-SIGN implementation, CryptoManager |
| 7-8 | DPAPI integration, Credential Manager, basic KeyManager |

**Exit Criteria:**
- All four PQC algorithms passing test vectors
- Key derivation from password working
- Basic secure storage operational

### Phase 2: Authentication (6 weeks)

**Objective:** Complete authentication flows with Windows integration

| Week | Deliverables |
|------|--------------|
| 9-10 | Registration flow, key generation, server enrollment |
| 11-12 | Login flow, MK derivation, session management |
| 13-14 | Windows Hello enrollment and authentication |

**Exit Criteria:**
- Can register new user with PQC keys
- Can login and derive master key
- Windows Hello biometric unlock working
- Password change flow complete

### Phase 3: File Management (8 weeks)

**Objective:** Core file operations with encryption

| Week | Deliverables |
|------|--------------|
| 15-16 | Folder creation, navigation, KEK management |
| 17-18 | File upload with encryption, progress tracking |
| 19-20 | File download with decryption, caching |
| 21-22 | File operations (rename, move, delete), batch operations |

**Exit Criteria:**
- Create folders with proper KEK hierarchy
- Upload/download files with full encryption
- Local caching operational
- Bulk operations working

### Phase 4: Sharing & Collaboration (6 weeks)

**Objective:** File sharing and collaboration features

| Week | Deliverables |
|------|--------------|
| 23-24 | User search, share creation, key re-encryption |
| 25-26 | Permission management, share revocation |
| 27-28 | Received shares view, shared folder access |

**Exit Criteria:**
- Share files/folders with other users
- Edit/revoke share permissions
- Access shared content with decryption

### Phase 5: Recovery & Sync (6 weeks)

**Objective:** Key recovery and offline capabilities

| Week | Deliverables |
|------|--------------|
| 29-30 | Shamir secret splitting, trustee enrollment |
| 31-32 | Recovery request flow, share reassembly |
| 33-34 | Offline queue, background sync, conflict resolution |

**Exit Criteria:**
- Full recovery flow operational
- Offline operations queued and synced
- Conflict detection and resolution working

### Phase 6: Polish & Security (4 weeks)

**Objective:** Hardening, testing, and launch preparation

| Week | Deliverables |
|------|--------------|
| 35-36 | Security audit, penetration testing, fixes |
| 37-38 | Performance optimization, UI polish, accessibility |

**Exit Criteria:**
- Security audit passed
- Performance targets met
- Accessibility compliance verified

### Timeline Summary

```
+-------+-------+-------+-------+-------+-------+-------+-------+-------+
| Week  | 1-8   | 9-14  | 15-22 | 23-28 | 29-34 | 35-38 |
+-------+-------+-------+-------+-------+-------+-------+-------+-------+
| Phase | Found | Auth  | Files | Share | Recov | Polish|
|       | ation |       |       |       | +Sync |       |
+-------+-------+-------+-------+-------+-------+-------+-------+-------+

Total: 38 weeks (~9.5 months)
```

### Risk Buffer

Add 4 weeks buffer for:
- Unexpected cryptographic implementation challenges
- Windows API compatibility issues
- Security audit findings requiring rework
- Integration testing with backend

**Total Project Duration: 42 weeks (~10.5 months)**

---

## 9. File Structure and Module Organization

```
SecureSharing.Windows/
├── .github/
│   └── workflows/
│       ├── build.yml
│       └── release.yml
│
├── docs/
│   ├── architecture.md
│   ├── security.md
│   └── api-integration.md
│
├── native/
│   └── securesharing_crypto/
│       ├── Cargo.toml
│       ├── Cargo.lock
│       ├── src/
│       │   ├── lib.rs
│       │   ├── ffi.rs
│       │   ├── ml_kem.rs
│       │   ├── ml_dsa.rs
│       │   ├── kaz_kem.rs
│       │   ├── kaz_sign.rs
│       │   └── error.rs
│       └── tests/
│           └── vectors/
│
├── src/
│   ├── SecureSharing.sln
│   │
│   ├── SecureSharing.App/                    # WinUI 3 Application
│   │   ├── SecureSharing.App.csproj
│   │   ├── App.xaml
│   │   ├── App.xaml.cs
│   │   ├── Package.appxmanifest
│   │   │
│   │   ├── Assets/
│   │   │   ├── Logo/
│   │   │   ├── Icons/
│   │   │   └── Images/
│   │   │
│   │   ├── Styles/
│   │   │   ├── Colors.xaml
│   │   │   ├── Typography.xaml
│   │   │   ├── Controls.xaml
│   │   │   └── Themes/
│   │   │       ├── Light.xaml
│   │   │       └── Dark.xaml
│   │   │
│   │   ├── Views/
│   │   │   ├── Shell/
│   │   │   │   ├── MainWindow.xaml
│   │   │   │   ├── NavigationView.xaml
│   │   │   │   └── SystemTrayIcon.cs
│   │   │   │
│   │   │   ├── Auth/
│   │   │   │   ├── LoginPage.xaml
│   │   │   │   ├── RegisterPage.xaml
│   │   │   │   ├── BiometricSetupPage.xaml
│   │   │   │   └── LockScreenPage.xaml
│   │   │   │
│   │   │   ├── Files/
│   │   │   │   ├── FileBrowserPage.xaml
│   │   │   │   ├── FilePreviewPage.xaml
│   │   │   │   ├── UploadDialog.xaml
│   │   │   │   └── Components/
│   │   │   │       ├── FileListItem.xaml
│   │   │   │       ├── FolderTreeView.xaml
│   │   │   │       └── BreadcrumbBar.xaml
│   │   │   │
│   │   │   ├── Sharing/
│   │   │   │   ├── ShareDialog.xaml
│   │   │   │   ├── SharedWithMePage.xaml
│   │   │   │   └── ManageSharesPage.xaml
│   │   │   │
│   │   │   ├── Recovery/
│   │   │   │   ├── TrusteeSetupPage.xaml
│   │   │   │   ├── RecoveryRequestPage.xaml
│   │   │   │   └── ApproveSharePage.xaml
│   │   │   │
│   │   │   ├── Settings/
│   │   │   │   ├── SettingsPage.xaml
│   │   │   │   ├── SecuritySettingsPage.xaml
│   │   │   │   ├── ProfilePage.xaml
│   │   │   │   └── AboutPage.xaml
│   │   │   │
│   │   │   └── Common/
│   │   │       ├── LoadingOverlay.xaml
│   │   │       ├── ErrorDialog.xaml
│   │   │       └── ConfirmationDialog.xaml
│   │   │
│   │   └── Converters/
│   │       ├── FileSizeConverter.cs
│   │       ├── DateTimeConverter.cs
│   │       └── BoolToVisibilityConverter.cs
│   │
│   ├── SecureSharing.ViewModels/             # MVVM ViewModels
│   │   ├── SecureSharing.ViewModels.csproj
│   │   │
│   │   ├── Base/
│   │   │   ├── ViewModelBase.cs
│   │   │   └── AsyncRelayCommand.cs
│   │   │
│   │   ├── Auth/
│   │   │   ├── LoginViewModel.cs
│   │   │   ├── RegisterViewModel.cs
│   │   │   └── BiometricSetupViewModel.cs
│   │   │
│   │   ├── Files/
│   │   │   ├── FileBrowserViewModel.cs
│   │   │   ├── FilePreviewViewModel.cs
│   │   │   └── UploadViewModel.cs
│   │   │
│   │   ├── Sharing/
│   │   │   ├── ShareDialogViewModel.cs
│   │   │   └── SharedWithMeViewModel.cs
│   │   │
│   │   ├── Recovery/
│   │   │   ├── TrusteeSetupViewModel.cs
│   │   │   └── RecoveryViewModel.cs
│   │   │
│   │   └── Settings/
│   │       ├── SettingsViewModel.cs
│   │       └── ProfileViewModel.cs
│   │
│   ├── SecureSharing.Domain/                 # Domain Layer
│   │   ├── SecureSharing.Domain.csproj
│   │   │
│   │   ├── Models/
│   │   │   ├── User.cs
│   │   │   ├── Folder.cs
│   │   │   ├── FileItem.cs
│   │   │   ├── ShareGrant.cs
│   │   │   ├── RecoveryShare.cs
│   │   │   ├── Notification.cs
│   │   │   └── KeyBundle.cs
│   │   │
│   │   ├── Repositories/
│   │   │   ├── IUserRepository.cs
│   │   │   ├── IFolderRepository.cs
│   │   │   ├── IFileRepository.cs
│   │   │   ├── IShareRepository.cs
│   │   │   └── IRecoveryRepository.cs
│   │   │
│   │   └── UseCases/
│   │       ├── Auth/
│   │       │   ├── LoginUseCase.cs
│   │       │   ├── RegisterUseCase.cs
│   │       │   └── ChangePasswordUseCase.cs
│   │       │
│   │       ├── Files/
│   │       │   ├── CreateFolderUseCase.cs
│   │       │   ├── UploadFileUseCase.cs
│   │       │   ├── DownloadFileUseCase.cs
│   │       │   └── DeleteFileUseCase.cs
│   │       │
│   │       ├── Sharing/
│   │       │   ├── ShareFileUseCase.cs
│   │       │   ├── RevokeShareUseCase.cs
│   │       │   └── AcceptShareUseCase.cs
│   │       │
│   │       └── Recovery/
│   │           ├── SetupRecoveryUseCase.cs
│   │           ├── RequestRecoveryUseCase.cs
│   │           └── ApproveRecoveryUseCase.cs
│   │
│   ├── SecureSharing.Data/                   # Data Layer
│   │   ├── SecureSharing.Data.csproj
│   │   │
│   │   ├── Remote/
│   │   │   ├── ApiClient.cs
│   │   │   ├── AuthInterceptor.cs
│   │   │   ├── Endpoints/
│   │   │   │   ├── IAuthApi.cs
│   │   │   │   ├── IFoldersApi.cs
│   │   │   │   ├── IFilesApi.cs
│   │   │   │   ├── ISharesApi.cs
│   │   │   │   └── IRecoveryApi.cs
│   │   │   └── DTOs/
│   │   │       ├── LoginRequest.cs
│   │   │       ├── LoginResponse.cs
│   │   │       ├── FileDTO.cs
│   │   │       └── ...
│   │   │
│   │   ├── Local/
│   │   │   ├── AppDbContext.cs
│   │   │   ├── Entities/
│   │   │   │   ├── CachedFolder.cs
│   │   │   │   ├── CachedFile.cs
│   │   │   │   └── SyncOperation.cs
│   │   │   ├── Migrations/
│   │   │   └── Repositories/
│   │   │       ├── LocalFolderRepository.cs
│   │   │       ├── LocalFileRepository.cs
│   │   │       └── SyncQueueRepository.cs
│   │   │
│   │   ├── Repositories/
│   │   │   ├── UserRepository.cs
│   │   │   ├── FolderRepository.cs
│   │   │   ├── FileRepository.cs
│   │   │   └── ShareRepository.cs
│   │   │
│   │   └── Sync/
│   │       ├── SyncCoordinator.cs
│   │       ├── ConflictResolver.cs
│   │       └── FileCacheManager.cs
│   │
│   ├── SecureSharing.Infrastructure/         # Infrastructure Layer
│   │   ├── SecureSharing.Infrastructure.csproj
│   │   │
│   │   ├── Crypto/
│   │   │   ├── NativeCrypto.cs               # P/Invoke declarations
│   │   │   ├── CryptoManager.cs
│   │   │   ├── KeyManager.cs
│   │   │   ├── KeyDerivationService.cs
│   │   │   ├── ShamirSecretSharing.cs
│   │   │   └── Models/
│   │   │       ├── EncryptedEnvelope.cs
│   │   │       ├── DualSignature.cs
│   │   │       └── KeyBundle.cs
│   │   │
│   │   ├── Security/
│   │   │   ├── SecureStorageService.cs       # DPAPI wrapper
│   │   │   ├── WindowsHelloService.cs
│   │   │   ├── TpmService.cs
│   │   │   ├── CredentialManagerService.cs
│   │   │   └── SecureMemory.cs
│   │   │
│   │   ├── Services/
│   │   │   ├── ConnectivityService.cs
│   │   │   ├── NotificationService.cs
│   │   │   ├── AutoLockService.cs
│   │   │   └── FileTypeService.cs
│   │   │
│   │   └── Platform/
│   │       ├── WindowsHelpers.cs
│   │       └── SystemTrayService.cs
│   │
│   ├── SecureSharing.Core/                   # Shared Core
│   │   ├── SecureSharing.Core.csproj
│   │   │
│   │   ├── Extensions/
│   │   │   ├── ByteArrayExtensions.cs
│   │   │   └── StringExtensions.cs
│   │   │
│   │   ├── Exceptions/
│   │   │   ├── CryptoException.cs
│   │   │   ├── AuthException.cs
│   │   │   └── SyncException.cs
│   │   │
│   │   └── Constants/
│   │       ├── CryptoConstants.cs
│   │       └── ApiConstants.cs
│   │
│   └── SecureSharing.Tests/                  # Test Projects
│       ├── SecureSharing.Tests.Unit/
│       │   ├── Crypto/
│       │   │   ├── CryptoManagerTests.cs
│       │   │   └── KeyDerivationTests.cs
│       │   ├── UseCases/
│       │   └── ViewModels/
│       │
│       ├── SecureSharing.Tests.Integration/
│       │   ├── ApiClientTests.cs
│       │   └── SyncTests.cs
│       │
│       └── SecureSharing.Tests.Crypto/
│           ├── MlKemVectorTests.cs
│           ├── MlDsaVectorTests.cs
│           ├── KazKemTests.cs
│           └── KazSignTests.cs
│
├── tools/
│   ├── build-native.ps1                      # Build Rust library
│   └── generate-api-client.ps1               # OpenAPI codegen
│
├── .editorconfig
├── .gitignore
├── Directory.Build.props
├── Directory.Packages.props                   # Central package management
└── README.md
```

### 9.1 Project Dependencies

```
SecureSharing.App
    ├── SecureSharing.ViewModels
    │   └── SecureSharing.Domain
    │       └── SecureSharing.Core
    └── SecureSharing.Infrastructure
        ├── SecureSharing.Data
        │   ├── SecureSharing.Domain
        │   └── SecureSharing.Core
        └── SecureSharing.Core
```

### 9.2 NuGet Packages (Directory.Packages.props)

```xml
<Project>
  <PropertyGroup>
    <ManagePackageVersionsCentrally>true</ManagePackageVersionsCentrally>
    <CentralPackageTransitivePinningEnabled>true</CentralPackageTransitivePinningEnabled>
  </PropertyGroup>
  <ItemGroup>
    <!-- UI -->
    <PackageVersion Include="Microsoft.WindowsAppSDK" Version="1.7.250127001" />
    <PackageVersion Include="CommunityToolkit.WinUI.UI" Version="8.1.250115" />

    <!-- MVVM -->
    <PackageVersion Include="CommunityToolkit.Mvvm" Version="8.4.0" />
    <PackageVersion Include="Microsoft.Extensions.DependencyInjection" Version="10.0.0" />

    <!-- Data -->
    <PackageVersion Include="Microsoft.EntityFrameworkCore.Sqlite" Version="10.0.0" />
    <PackageVersion Include="Refit" Version="8.0.0" />
    <PackageVersion Include="Refit.HttpClientFactory" Version="8.0.0" />

    <!-- Crypto -->
    <PackageVersion Include="Konscious.Security.Cryptography.Argon2" Version="1.4.0" />

    <!-- Utilities -->
    <PackageVersion Include="Serilog" Version="4.2.0" />
    <PackageVersion Include="Serilog.Sinks.File" Version="6.0.0" />
    <PackageVersion Include="Polly" Version="8.5.0" />

    <!-- Testing -->
    <PackageVersion Include="xunit" Version="2.9.3" />
    <PackageVersion Include="Moq" Version="4.20.72" />
    <PackageVersion Include="FluentAssertions" Version="7.0.0" />
  </ItemGroup>
</Project>
```

---

## 10. Alternative Approaches Considered

### 10.1 Technology Stack Alternatives

#### Option A: Tauri + Rust (Cross-Platform)

**Pros:**
- Rust everywhere (crypto + business logic)
- Smaller binary size (~10MB vs ~50MB)
- True cross-platform (Windows, macOS, Linux)
- Memory safety guarantees

**Cons:**
- WebView-based UI less native feeling
- Windows Hello integration requires additional work
- Smaller ecosystem for enterprise Windows features
- Team may need Rust expertise

**Verdict:** Strong alternative if cross-platform is higher priority than native Windows feel.

#### Option B: .NET MAUI

**Pros:**
- Microsoft-supported cross-platform
- Single codebase for Windows, macOS, iOS, Android
- .NET ecosystem

**Cons:**
- Desktop UI still maturing (WinUI 3 underneath anyway)
- Performance overhead from abstraction layer
- Less control over platform-specific features

**Verdict:** Not recommended due to maturity concerns for desktop.

#### Option C: Electron + TypeScript

**Pros:**
- Web technology, rapid development
- Extensive ecosystem
- Cross-platform

**Cons:**
- 150MB+ binary size
- High memory usage (300MB+ idle)
- Security concerns (Chromium attack surface)
- Performance limitations

**Verdict:** Not recommended for security-focused application.

### 10.2 Cryptography Implementation Alternatives

#### Option A: BouncyCastle.NET

**Pros:**
- Pure .NET, no native dependencies
- Battle-tested library
- ML-KEM, ML-DSA support

**Cons:**
- No KAZ-KEM, KAZ-SIGN (would need porting)
- Performance may be slower than native
- Large library size

**Verdict:** Could work but would require porting KAZ algorithms.

#### Option B: liboqs via C Bindings

**Pros:**
- Reference PQC implementations
- Well-tested

**Cons:**
- C library, more complex integration
- No KAZ algorithms

**Verdict:** Rust provides better safety guarantees.

#### Option C: Windows CNG (Cryptography Next Generation)

**Pros:**
- Native Windows integration
- Hardware acceleration

**Cons:**
- No PQC support yet (as of 2026)
- Would still need separate PQC library

**Verdict:** Use CNG for classic crypto, Rust for PQC.

### 10.3 UI Framework Alternatives

#### Option A: WPF (Windows Presentation Foundation)

**Pros:**
- Mature, stable
- Rich ecosystem
- Good for complex UIs

**Cons:**
- Dated visual style
- No native Windows 11 design language
- Limited touch optimization

**Verdict:** WinUI 3 provides better modern experience.

#### Option B: Avalonia UI

**Pros:**
- Cross-platform XAML
- .NET, familiar patterns

**Cons:**
- Not native Windows look
- Smaller ecosystem
- Windows Hello integration complexity

**Verdict:** Good for cross-platform, but WinUI 3 better for Windows-only.

---

## 11. Risk Assessment

### 11.1 Technical Risks

| Risk | Probability | Impact | Mitigation |
|------|-------------|--------|------------|
| KAZ algorithm porting complexity | Medium | High | Start with reference implementation, comprehensive test vectors |
| Windows Hello edge cases | Medium | Medium | Extensive testing across hardware, graceful fallback to password |
| WinUI 3 bugs/limitations | Medium | Medium | Stay updated with SDK releases, implement workarounds |
| Performance on lower-end hardware | Low | Medium | Profile early, optimize hot paths, test on target hardware |
| DPAPI roaming profile issues | Low | Medium | Document limitations, provide export option |

### 11.2 Security Risks

| Risk | Probability | Impact | Mitigation |
|------|-------------|--------|------------|
| Side-channel attacks on crypto | Low | Critical | Use constant-time implementations, security audit |
| Memory disclosure | Low | High | SecureBytes pattern, aggressive zeroing |
| Credential theft from memory | Low | High | Auto-lock, minimize key lifetime in memory |
| Malicious DLL injection | Low | High | Code signing, DLL verification |
| Local database tampering | Low | Medium | DPAPI encryption, integrity checks |

### 11.3 Project Risks

| Risk | Probability | Impact | Mitigation |
|------|-------------|--------|------------|
| Team unfamiliar with Rust | Medium | Medium | Training, start with simpler components |
| Schedule slippage | Medium | Medium | Buffer weeks, phased delivery, MVP scope |
| Backend API changes | Low | Medium | Version API, coordinate with backend team |
| Windows API deprecation | Low | Low | Use stable, documented APIs |

### 11.4 Risk Response Plan

**Critical Path Items:**
1. PQC cryptography implementation (blocks all encryption features)
2. Key derivation and management (blocks authentication)
3. Windows Hello integration (blocks biometric feature)

**Fallback Strategies:**
- If Rust crypto proves difficult: Use BouncyCastle.NET + port KAZ algorithms in C#
- If WinUI 3 issues: Fall back to WPF with modern theme
- If Windows Hello problematic: Password-only MVP, add biometrics later

---

## 12. Open Questions

### 12.1 Requiring User Input

1. **Multi-Tenant Support Strategy**
   - Should the app support switching between tenants without re-login?
   - How should tenant-specific theming/branding be handled?

2. **Offline Duration Limits**
   - Maximum allowed offline period before forced re-authentication?
   - Should cached data expire after a certain period?

3. **Recovery Trustee Communication**
   - Should the Windows app support being a recovery trustee?
   - How should recovery share approvals be notified (push, email, in-app)?

4. **Feature Parity Prioritization**
   - Which features are MVP vs. post-launch for Windows?
   - Any Windows-specific features not on mobile?

### 12.2 Requiring Further Research

1. **TPM 2.0 Attestation**
   - Determine if device attestation should be implemented for enterprise use
   - Research Windows attestation APIs and server-side verification

2. **MSIX Distribution**
   - Microsoft Store vs. sideloading vs. enterprise deployment
   - Auto-update mechanism selection

3. **Accessibility Compliance**
   - WCAG 2.1 level required (A, AA, AAA)?
   - Screen reader testing approach

4. **Internationalization**
   - Which languages for initial release?
   - RTL language support required?

### 12.3 Backend Coordination Needed

1. **Device Registration API**
   - Confirm device attestation requirements
   - Windows-specific device metadata to send

2. **Push Notification Integration**
   - OneSignal Windows SDK vs. WNS directly
   - Background notification handling

3. **Rate Limiting Considerations**
   - Sync frequency limits
   - Bulk operation quotas

---

## Appendix A: Glossary

| Term | Definition |
|------|------------|
| **MK** | Master Key - Root key derived from user password |
| **KEK** | Key Encryption Key - Per-folder key for access control |
| **DEK** | Data Encryption Key - Per-file key for content encryption |
| **ML-KEM** | Module-Lattice Key Encapsulation Mechanism (NIST FIPS 203) |
| **ML-DSA** | Module-Lattice Digital Signature Algorithm (NIST FIPS 204) |
| **KAZ-KEM** | Kazakhstan's KEM algorithm |
| **KAZ-SIGN** | Kazakhstan's signature algorithm |
| **DPAPI** | Data Protection API - Windows credential protection |
| **TPM** | Trusted Platform Module - Hardware security chip |
| **PQC** | Post-Quantum Cryptography |

---

## Appendix B: API Endpoint Summary

| Category | Endpoint | Method | Purpose |
|----------|----------|--------|---------|
| Auth | `/api/auth/login` | POST | Password login |
| Auth | `/api/auth/register` | POST | New user registration |
| Auth | `/api/auth/refresh` | POST | Token refresh |
| Folders | `/api/folders` | GET, POST | List, create folders |
| Folders | `/api/folders/{id}` | GET, PUT, DELETE | Folder operations |
| Files | `/api/files` | GET, POST | List, upload files |
| Files | `/api/files/{id}` | GET, PUT, DELETE | File operations |
| Files | `/api/files/{id}/download` | GET | Download file blob |
| Shares | `/api/shares` | GET, POST | List, create shares |
| Shares | `/api/shares/{id}` | DELETE | Revoke share |
| Recovery | `/api/recovery/shares` | GET, POST | Trustee management |
| Recovery | `/api/recovery/request` | POST | Initiate recovery |
| Notifications | `/api/notifications` | GET | List notifications |
| Devices | `/api/devices/{id}/push` | POST | Register push token |

---

## Approval

This design document requires approval before implementation begins.

| Role | Name | Date | Signature |
|------|------|------|-----------|
| Project Lead | | | |
| Security Lead | | | |
| Backend Lead | | | |
| Product Owner | | | |

---

*Document generated: 2026-01-20*
*Last updated: 2026-01-20*
