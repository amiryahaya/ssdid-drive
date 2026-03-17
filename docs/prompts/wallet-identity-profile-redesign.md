# Wallet Architecture: Identity-Scoped Profiles

## Context

Currently ssdid-wallet has a **single global profile** (name, email) shared across **multiple identities**. This breaks when:

1. User registers on ssdid-drive with `amir@acme.com` via "Work" identity
2. User changes wallet profile email to `amir@gmail.com`
3. Invitation email matching fails — ssdid-drive expects `amir@acme.com` but wallet now shares `amir@gmail.com`
4. Two identities (Work + Personal) share the same email, which doesn't make sense for different organizations

## Current Architecture (Wrong)

```
Profile (single, global)
├── name: "Amir"
├── email: "amir@acme.com"
│
├── Identity: "Work" (KAZ-SIGN-192)
│   └── did:ssdid:abc...  ← shares profile email
│
└── Identity: "Personal" (Ed25519)
    └── did:ssdid:xyz...  ← shares same profile email (wrong!)
```

Profile is stored as a self-issued VC (`urn:ssdid:profile`) with `ProfileManager`.

## Proposed Architecture (Correct)

Each identity should have its own profile (name, email). The profile travels with the identity, not the wallet.

```
Identity: "Work" (KAZ-SIGN-192)
├── did:ssdid:abc...
├── name: "Amir Yahaya"
├── email: "amir@acme.com" (verified by email OTP)
│
Identity: "Personal" (Ed25519)
├── did:ssdid:xyz...
├── name: "Amir"
├── email: "amir@gmail.com" (verified by email OTP)
```

## What Needs to Change

### 1. Data Model
- Move `name` and `email` from `ProfileManager` (global VC) into `Identity` struct
- Each identity has its own `name: String?` and `email: String?`
- Remove or deprecate the global `ProfileManager` / `urn:ssdid:profile` VC

### 2. Onboarding Flow
- Profile setup screen should be **per-identity**, shown after creating each identity
- Or: ask for name/email during identity creation
- Email verification (OTP) should be per-identity

### 3. DriveLoginScreen / ConsentScreen
- When sharing claims (name, email), read from the **selected identity**, not global profile
- `shared_claims` in `RegisterVerifyRequest` comes from `identity.name`, `identity.email`

### 4. InviteAcceptViewModel
- Same: use selected identity's email for `shared_claims`

### 5. Profile Edit
- Editing name/email edits the **selected identity's** profile, not a global one
- ProfileSetupScreen needs an `identityKeyId` parameter

### 6. ScanQrScreen / DeepLink Routing
- When a deeplink specifies `requested_claims: [name, email]`, the consent screen shows the **selected identity's** values, not global profile

### 7. Migration
- Existing users with a global profile VC: migrate name/email to their first (or only) identity
- Delete the global `urn:ssdid:profile` VC after migration

## Files to Change (iOS)

- `Domain/Vault/Identity.swift` — add `name: String?`, `email: String?`, `emailVerified: Bool`
- `Domain/Profile/ProfileManager.swift` — deprecate or remove
- `Domain/Vault/VaultImpl.swift` — persist identity with profile fields
- `Platform/Storage/VaultStorage.swift` — update serialization
- `Feature/Profile/ProfileSetupScreen.swift` — scope to identity
- `Feature/Auth/DriveLoginScreen.swift` — use `selectedIdentity.email` instead of `ProfileManager`
- `Feature/Invite/InviteAcceptViewModel.swift` — same
- `Feature/Identity/CreateIdentityScreen.swift` — add name/email fields
- `Feature/Identity/WalletHomeScreen.swift` — show per-identity email
- `Feature/Identity/IdentityDetailScreen.swift` — show/edit identity profile

## Files to Change (Android)

- Same pattern: move profile fields into Identity model
- Update all screens that read from global profile

## Impact on ssdid-drive

- `RegisterVerify.cs` already accepts `shared_claims: { name, email }` — no backend change needed
- Invitation email matching uses the email from `shared_claims` — works correctly when identity-scoped
- The `User.Email` field on ssdid-drive is populated from `shared_claims` at registration — correct

## Testing

After the change:
1. Create "Work" identity with `amir@acme.com`
2. Create "Personal" identity with `amir@gmail.com`
3. Register on ssdid-drive using "Work" identity → ssdid-drive gets `amir@acme.com`
4. Accept invitation sent to `amir@acme.com` using "Work" identity → email matches ✓
5. Try accepting invitation sent to `amir@acme.com` using "Personal" identity → email mismatch ✗ (correct behavior)
