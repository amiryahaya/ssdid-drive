# CI/CD Setup Guide

This document describes how to configure the CI/CD pipelines for SecureSharing on GitHub Actions.

## Table of Contents

- [Overview](#overview)
- [iOS CI/CD](#ios-cicd)
  - [Workflow Jobs](#ios-workflow-jobs)
  - [Required Secrets for iOS](#required-secrets-for-ios)
  - [How to Obtain iOS Secrets](#how-to-obtain-ios-secrets)
- [Android CI/CD](#android-cicd)
  - [Workflow Jobs](#android-workflow-jobs)
  - [Required Secrets for Android](#required-secrets-for-android)
  - [How to Obtain Android Secrets](#how-to-obtain-android-secrets)
- [Desktop CI/CD](#desktop-cicd)
- [Configuring Secrets in GitHub](#configuring-secrets-in-github)

---

## Overview

The SecureSharing project uses GitHub Actions for continuous integration and deployment. Each platform (iOS, Android, Desktop) has its own workflow file:

| Platform | Workflow File | Trigger Paths |
|----------|---------------|---------------|
| iOS | `.github/workflows/ios.yml` | `clients/ios/**` |
| Android | `.github/workflows/android.yml` | `clients/android/**` |
| Desktop | `.github/workflows/desktop-ci.yml` | `clients/desktop/**` |

All workflows are triggered on:
- Push to `main` or `develop` branches
- Pull requests to `main` or `develop` branches
- Manual trigger via `workflow_dispatch`

---

## iOS CI/CD

### iOS Workflow Jobs

| Job | Description | When |
|-----|-------------|------|
| **Lint** | SwiftLint code analysis | All pushes/PRs |
| **Unit Tests** | Run XCTest suite with coverage | All pushes/PRs |
| **Build Debug** | Build simulator app | After tests pass |
| **Build Release** | Archive with code signing | Main branch only |
| **Upload to TestFlight** | Deploy to TestFlight | Main branch + secrets configured |

### Required Secrets for iOS

#### Code Signing Secrets

| Secret Name | Description | Required For |
|-------------|-------------|--------------|
| `IOS_BUILD_CERTIFICATE_BASE64` | Distribution certificate (.p12) encoded in base64 | Signed release builds |
| `IOS_P12_PASSWORD` | Password for the .p12 certificate | Signed release builds |
| `IOS_PROVISION_PROFILE_BASE64` | Provisioning profile (.mobileprovision) encoded in base64 | Signed release builds |
| `IOS_KEYCHAIN_PASSWORD` | Temporary keychain password (any secure string) | Signed release builds |
| `APPLE_TEAM_ID` | Apple Developer Team ID (10-character string) | Signed release builds |

#### App Store Connect Secrets (for TestFlight)

| Secret Name | Description | Required For |
|-------------|-------------|--------------|
| `APP_STORE_CONNECT_API_KEY_ID` | App Store Connect API Key ID | TestFlight uploads |
| `APP_STORE_CONNECT_ISSUER_ID` | App Store Connect Issuer ID | TestFlight uploads |
| `APP_STORE_CONNECT_API_KEY_BASE64` | API Key file (.p8) encoded in base64 | TestFlight uploads |

### How to Obtain iOS Secrets

#### 1. Distribution Certificate (`IOS_BUILD_CERTIFICATE_BASE64`, `IOS_P12_PASSWORD`)

1. Open **Keychain Access** on your Mac
2. Go to **Keychain Access > Certificate Assistant > Request a Certificate from a Certificate Authority**
3. Save the CSR file
4. Go to [Apple Developer Portal](https://developer.apple.com/account/resources/certificates/list)
5. Create a new **Apple Distribution** certificate using your CSR
6. Download the certificate and double-click to install in Keychain
7. In Keychain Access, find the certificate, right-click > **Export**
8. Save as .p12 file with a strong password
9. Encode to base64:
   ```bash
   base64 -i Certificates.p12 | pbcopy
   ```
10. The clipboard now contains `IOS_BUILD_CERTIFICATE_BASE64`
11. The password you set is `IOS_P12_PASSWORD`

#### 2. Provisioning Profile (`IOS_PROVISION_PROFILE_BASE64`)

1. Go to [Apple Developer Portal > Profiles](https://developer.apple.com/account/resources/profiles/list)
2. Create a new **App Store** distribution profile
3. Select your app's Bundle ID (`com.securesharing.SecureSharing`)
4. Select the distribution certificate created above
5. Download the .mobileprovision file
6. Encode to base64:
   ```bash
   base64 -i SecureSharing_AppStore.mobileprovision | pbcopy
   ```
7. The clipboard now contains `IOS_PROVISION_PROFILE_BASE64`

#### 3. Apple Team ID (`APPLE_TEAM_ID`)

1. Go to [Apple Developer Portal](https://developer.apple.com/account)
2. Your Team ID is shown in the top-right under your name
3. It's a 10-character alphanumeric string (e.g., `ABC123DEF4`)

#### 4. App Store Connect API Key

1. Go to [App Store Connect > Users and Access > Keys](https://appstoreconnect.apple.com/access/api)
2. Click the **+** button to create a new key
3. Name: `CI/CD Key` (or any name)
4. Access: **App Manager** or **Admin**
5. Download the .p8 file (you can only download it once!)
6. Note the **Key ID** shown in the table
7. Note the **Issuer ID** shown at the top of the page
8. Encode the .p8 file to base64:
   ```bash
   base64 -i AuthKey_XXXXXXXXXX.p8 | pbcopy
   ```

| Value | Secret Name |
|-------|-------------|
| Key ID (e.g., `ABC123DEFG`) | `APP_STORE_CONNECT_API_KEY_ID` |
| Issuer ID (e.g., `12345678-1234-1234-1234-123456789012`) | `APP_STORE_CONNECT_ISSUER_ID` |
| Base64 encoded .p8 file | `APP_STORE_CONNECT_API_KEY_BASE64` |

#### 5. Keychain Password (`IOS_KEYCHAIN_PASSWORD`)

This is a temporary password used to create a keychain during CI. Generate any secure random string:
```bash
openssl rand -base64 32
```

---

## Android CI/CD

### Android Workflow Jobs

| Job | Description | When |
|-----|-------------|------|
| **Lint** | Android Lint analysis | All pushes/PRs |
| **Unit Tests** | Run JUnit tests | All pushes/PRs |
| **Build Debug APK** | Build debug variant | After lint & tests pass |
| **Build Staging APK** | Build staging variant | Develop branch only |
| **Build Release** | Build signed release APK/AAB | Main branch only |
| **Instrumentation Tests** | Run on emulator | Pull requests only |

### Required Secrets for Android

| Secret Name | Description | Required For |
|-------------|-------------|--------------|
| `KEYSTORE_BASE64` | Release keystore (.jks) encoded in base64 | Signed release builds |
| `KEYSTORE_PASSWORD` | Keystore password | Signed release builds |
| `KEY_ALIAS` | Key alias within the keystore | Signed release builds |
| `KEY_PASSWORD` | Password for the key alias | Signed release builds |

### How to Obtain Android Secrets

#### 1. Create a Release Keystore

If you don't have a keystore yet:

```bash
keytool -genkey -v -keystore release.jks -keyalg RSA -keysize 2048 -validity 10000 -alias securesharing
```

You'll be prompted for:
- **Keystore password** → `KEYSTORE_PASSWORD`
- **Key password** → `KEY_PASSWORD` (can be same as keystore password)
- **Alias** → `KEY_ALIAS` (e.g., `securesharing`)

#### 2. Encode Keystore to Base64

```bash
base64 -i release.jks | pbcopy  # macOS
# or
base64 release.jks | xclip -selection clipboard  # Linux
```

The clipboard now contains `KEYSTORE_BASE64`.

#### Summary of Android Secrets

| Secret | Example Value |
|--------|---------------|
| `KEYSTORE_BASE64` | `MIIKfQIBAzCCCjcGCSqGS...` (long base64 string) |
| `KEYSTORE_PASSWORD` | `your-keystore-password` |
| `KEY_ALIAS` | `securesharing` |
| `KEY_PASSWORD` | `your-key-password` |

---

## Desktop CI/CD

### Desktop Workflow Jobs

| Job | Description | When |
|-----|-------------|------|
| **Lint** | ESLint + TypeScript check | All pushes/PRs |
| **Test Frontend** | Vitest tests | All pushes/PRs |
| **Test Backend** | Rust tests | All pushes/PRs |
| **Build Check** | Verify builds on all platforms | After tests pass |

### Release Workflow (desktop-release.yml)

Triggered by tags matching `desktop-v*` or manual dispatch.

#### Required Secrets for Desktop

| Secret Name | Description | Required For |
|-------------|-------------|--------------|
| `APPLE_CERTIFICATE` | macOS signing certificate (base64) | macOS builds |
| `APPLE_CERTIFICATE_PASSWORD` | Certificate password | macOS builds |
| `APPLE_SIGNING_IDENTITY` | Signing identity string | macOS builds |
| `APPLE_ID` | Apple ID email for notarization | macOS notarization |
| `APPLE_PASSWORD` | App-specific password | macOS notarization |
| `APPLE_TEAM_ID` | Apple Developer Team ID | macOS builds |

---

## Configuring Secrets in GitHub

1. Go to your repository on GitHub
2. Click **Settings** > **Secrets and variables** > **Actions**
3. Click **New repository secret**
4. Enter the secret name and value
5. Click **Add secret**

### Recommended Secret Organization

For better organization, you can use **Environments** in GitHub:

1. Go to **Settings** > **Environments**
2. Create environments: `development`, `staging`, `production`
3. Add secrets specific to each environment
4. Configure environment protection rules (e.g., require approval for production)

---

## Troubleshooting

### iOS Build Fails with Code Signing Error

1. Verify the certificate hasn't expired
2. Ensure the provisioning profile matches the bundle ID
3. Check that the Team ID is correct
4. Verify the certificate and profile are for **distribution** (not development)

### Android Build Fails with Keystore Error

1. Verify the keystore base64 encoding is correct
2. Check that passwords don't contain special characters that need escaping
3. Ensure the key alias matches exactly (case-sensitive)

### TestFlight Upload Fails

1. Verify the App Store Connect API key has sufficient permissions
2. Check that the app version/build number is unique
3. Ensure the app is set up in App Store Connect

---

## Security Best Practices

1. **Never commit secrets** to the repository
2. **Rotate secrets regularly** (at least annually)
3. **Use environment protection** for production secrets
4. **Limit secret access** to only necessary workflows
5. **Audit secret usage** periodically in GitHub Actions logs
6. **Use separate keys** for CI/CD vs manual deployments

---

## Quick Reference

### iOS Secrets Checklist

- [ ] `IOS_BUILD_CERTIFICATE_BASE64`
- [ ] `IOS_P12_PASSWORD`
- [ ] `IOS_PROVISION_PROFILE_BASE64`
- [ ] `IOS_KEYCHAIN_PASSWORD`
- [ ] `APPLE_TEAM_ID`
- [ ] `APP_STORE_CONNECT_API_KEY_ID`
- [ ] `APP_STORE_CONNECT_ISSUER_ID`
- [ ] `APP_STORE_CONNECT_API_KEY_BASE64`

### Android Secrets Checklist

- [ ] `KEYSTORE_BASE64`
- [ ] `KEYSTORE_PASSWORD`
- [ ] `KEY_ALIAS`
- [ ] `KEY_PASSWORD`

### Desktop Secrets Checklist (macOS)

- [ ] `APPLE_CERTIFICATE`
- [ ] `APPLE_CERTIFICATE_PASSWORD`
- [ ] `APPLE_SIGNING_IDENTITY`
- [ ] `APPLE_ID`
- [ ] `APPLE_PASSWORD`
- [ ] `APPLE_TEAM_ID`
