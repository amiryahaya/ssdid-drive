# Invitation Flow

**Version**: 1.0.0
**Status**: Draft
**Last Updated**: 2026-01-19

## 1. Overview

This document describes the invitation-based user onboarding flow for SecureSharing. Unlike standard registration, users can only join a tenant through invitations sent by administrators or permitted users.

### Key Differences from Standard Registration

| Aspect | Standard Registration | Invitation-Based |
|--------|----------------------|------------------|
| Initiation | User self-initiates | Admin/user sends invitation |
| Tenant Selection | User specifies tenant | Pre-determined by invitation |
| Role Assignment | Default role | Pre-assigned by inviter |
| Email Verification | Required separately | Implicit via invitation token |
| Access Control | Open (if enabled) | Controlled by inviter permissions |

## 2. Prerequisites

### For Inviter
- Active user account with appropriate role
- Permission to invite (admin, or peer invites enabled)

### For Invitee
- Valid email address
- Access to invitation email
- Client application installed (mobile) or web access

## 3. Flow Diagrams

### 3.1 Admin Creates Invitation

```
+-----------------------------------------------------------------------------+
|                         ADMIN INVITATION CREATION                            |
+-----------------------------------------------------------------------------+

ADMIN (Dashboard)                    SERVER                         EMAIL SERVICE
      |                                |                                  |
      | 1. Enter email, select role    |                                  |
      |------------------------------->|                                  |
      |                                |                                  |
      |                                | 2. Validate request              |
      |                                |    - Check email not registered  |
      |                                |    - Check no pending invitation |
      |                                |    - Validate role hierarchy     |
      |                                |    - Check tenant limits         |
      |                                |                                  |
      |                                | 3. Generate secure token         |
      |                                |    token = random(32 bytes)      |
      |                                |    hash = SHA256(token)          |
      |                                |                                  |
      |                                | 4. Create invitation record      |
      |                                |    - Store hash (not token)      |
      |                                |    - Set expiration (7 days)     |
      |                                |                                  |
      | 5. Return confirmation         |                                  |
      |<-------------------------------|                                  |
      |                                |                                  |
      |                                | 6. Send invitation email         |
      |                                |---------------------------------->|
      |                                |                                  |
      |                                |                                  | 7. Deliver to invitee
      |                                |                                  |    (contains token URL)
      |                                |                                  |
+-----------------------------------------------------------------------------+
```

### 3.2 User Accepts Invitation (Web)

```
+-----------------------------------------------------------------------------+
|                         WEB INVITATION ACCEPTANCE                            |
+-----------------------------------------------------------------------------+

USER (Browser)                       SERVER                         DATABASE
      |                                |                                  |
      | 1. Click invitation link       |                                  |
      |    /invite/{token}             |                                  |
      |------------------------------->|                                  |
      |                                |                                  |
      |                                | 2. Validate token                |
      |                                |    hash = SHA256(token)          |
      |                                |------------------------------->  |
      |                                |                                  |
      |                                | 3. Return invitation             |
      |                                |    (if valid & not expired)      |
      |                                |<-------------------------------  |
      |                                |                                  |
      | 4. Show invitation details     |                                  |
      |    - Tenant name               |                                  |
      |    - Inviter name              |                                  |
      |    - Assigned role             |                                  |
      |    - Personal message          |                                  |
      |<-------------------------------|                                  |
      |                                |                                  |
      | 5. User enters:                |                                  |
      |    - Display name              |                                  |
      |    - Password                  |                                  |
      |------------------------------->|                                  |
      |                                |                                  |
      | +------------------------------|------------------------------+   |
      | | 6. CLIENT-SIDE KEY GENERATION (same as standard registration)|  |
      | |                              |                              |   |
      | |  a. Generate Master Key      |                              |   |
      | |  b. Derive key from password (Argon2id)                     |   |
      | |  c. Encrypt MK with derived key                             |   |
      | |  d. Generate PQC key pairs (ML-KEM, ML-DSA, KAZ-KEM, KAZ-SIGN)  |
      | |  e. Encrypt private keys with MK                            |   |
      | |  f. Create root folder KEK                                  |   |
      | |  g. Sign root folder creation                               |   |
      | +------------------------------|------------------------------+   |
      |                                |                                  |
      | 7. Submit registration bundle  |                                  |
      |------------------------------->|                                  |
      |                                |                                  |
      |                                | 8. Server processing             |
      |                                |    - Re-validate invitation      |
      |                                |    - Verify signatures           |
      |                                |    - Create user (with role)     |
      |                                |    - Store key bundle            |
      |                                |    - Create root folder          |
      |                                |    - Mark invitation accepted    |
      |                                |    - Issue session tokens        |
      |                                |------------------------------->  |
      |                                |                                  |
      | 9. Return session + user info  |                                  |
      |<-------------------------------|                                  |
      |                                |                                  |
      | 10. Redirect to dashboard      |                                  |
      |                                |                                  |
+-----------------------------------------------------------------------------+
```

### 3.3 Mobile Deep Link Flow

```
+-----------------------------------------------------------------------------+
|                         MOBILE DEEP LINK FLOW                                |
+-----------------------------------------------------------------------------+

USER (Email)                    MOBILE DEVICE                         APP
      |                              |                                  |
      | 1. Tap invitation link       |                                  |
      |----------------------------->|                                  |
      |                              |                                  |
      |                              | 2. Check if app installed        |
      |                              |                                  |
      |              +---------------+-----------------+                |
      |              |                                 |                |
      |              v                                 v                |
      |         [App Installed]               [Not Installed]          |
      |              |                                 |                |
      |              |                                 v                |
      |              |                          App Store/Play Store   |
      |              |                                 |                |
      |              |                                 v                |
      |              |                          Install & Open         |
      |              |                          (deferred deep link)   |
      |              |                                 |                |
      |              +---------------+-----------------+                |
      |                              |                                  |
      |                              | 3. App opens with token         |
      |                              |--------------------------------->|
      |                              |                                  |
      |                              |                   4. Fetch invitation info
      |                              |                      GET /invite/{token}
      |                              |                                  |
      |                              |                   5. Show accept screen
      |                              |                      - Tenant name
      |                              |                      - Inviter name
      |                              |                      - Role badge
      |                              |                      - Message
      |                              |<---------------------------------|
      |                              |                                  |
      | 6. User taps "Accept"        |                                  |
      |----------------------------->|--------------------------------->|
      |                              |                                  |
      |                              |                   7. Show registration form
      |                              |                      - Name input
      |                              |                      - Password input
      |                              |                      - Confirm password
      |                              |<---------------------------------|
      |                              |                                  |
      | 8. User submits form         |                                  |
      |----------------------------->|--------------------------------->|
      |                              |                                  |
      |                              |                   9. Key generation
      |                              |                      (progress indicator)
      |                              |                                  |
      |                              |                   10. POST /invite/{token}/accept
      |                              |                                  |
      |                              |                   11. Success - navigate to
      |                              |                       main app screen
      |                              |<---------------------------------|
      |                              |                                  |
+-----------------------------------------------------------------------------+
```

## 4. Detailed Steps

### 4.1 Create Invitation (Admin)

#### API Request

```http
POST /api/v1/invitations
Authorization: Bearer <access_token>
Content-Type: application/json

{
  "email": "newuser@example.com",
  "role": "member",
  "message": "Welcome to the team! Looking forward to collaborating."
}
```

#### Server Validation

```elixir
defp validate_invitation(changeset, inviter, tenant) do
  changeset
  |> validate_email_not_registered_in_tenant()
  |> validate_no_pending_invitation_for_email()
  |> validate_inviter_can_invite_role(inviter)
  |> validate_tenant_invitation_limit(tenant)
  |> validate_email_domain_allowed(tenant)
end

defp can_invite_role?(inviter_role, target_role) do
  role_level = %{admin: 3, manager: 2, member: 1}
  role_level[inviter_role] >= role_level[target_role]
end
```

### 4.2 Token Generation

```elixir
defp generate_token(changeset) do
  # Generate cryptographically secure random token
  token = :crypto.strong_rand_bytes(32) |> Base.url_encode64(padding: false)

  # Store hash for secure lookup
  token_hash = :crypto.hash(:sha256, token) |> Base.encode16(case: :lower)

  changeset
  |> put_change(:token, token)        # Virtual field, sent via email
  |> put_change(:token_hash, token_hash)  # Stored in database
end
```

### 4.3 Invitation Email

```
Subject: You've been invited to join {tenant_name} on SecureSharing

-----------------------------------------------------------

Hi there,

{inviter_name} has invited you to join {tenant_name} on SecureSharing.

{message}

SecureSharing is a secure file sharing platform with
post-quantum encryption to protect your sensitive files.

[ Accept Invitation ]
    |
    +-> https://app.securesharing.example/invite/{token}

This invitation expires on {expires_at}.

-----------------------------------------------------------

If you didn't expect this invitation, you can safely ignore this email.
```

### 4.4 Accept Invitation - Client Processing

#### Fetch Invitation Info

```typescript
// Mobile/Web client
async function fetchInvitationInfo(token: string): Promise<InvitationInfo> {
  const response = await fetch(`/api/v1/invite/${token}`);
  const { data } = await response.json();

  if (!data.valid) {
    throw new InvitationError(data.error_reason);
  }

  return {
    tenantName: data.tenant_name,
    inviterName: data.inviter_name,
    role: data.role,
    email: data.email,
    message: data.message,
    expiresAt: new Date(data.expires_at)
  };
}
```

#### Generate Keys and Register

```typescript
async function acceptInvitation(
  token: string,
  displayName: string,
  password: string
): Promise<SessionInfo> {

  // 1. Generate Master Key
  const masterKey = crypto.getRandomValues(new Uint8Array(32));

  // 2. Derive auth key from password
  const salt = crypto.getRandomValues(new Uint8Array(16));
  const authKey = await argon2id(password, salt, {
    memory: 65536,
    iterations: 3,
    parallelism: 4,
    hashLength: 32
  });

  // 3. Encrypt Master Key
  const mkNonce = crypto.getRandomValues(new Uint8Array(12));
  const encryptedMk = await aesGcmEncrypt(authKey, mkNonce, masterKey);

  // 4. Generate PQC key pairs
  const mlKemKeyPair = await cryptoProvider.kemKeyGen('ML-KEM-768');
  const mlDsaKeyPair = await cryptoProvider.signKeyGen('ML-DSA-65');
  const kazKemKeyPair = await cryptoProvider.kemKeyGen('KAZ-KEM');
  const kazSignKeyPair = await cryptoProvider.signKeyGen('KAZ-SIGN');

  // 5. Encrypt private keys with MK
  const encryptedPrivateKeys = {
    ml_kem: await encryptPrivateKey(masterKey, mlKemKeyPair.privateKey),
    ml_dsa: await encryptPrivateKey(masterKey, mlDsaKeyPair.privateKey),
    kaz_kem: await encryptPrivateKey(masterKey, kazKemKeyPair.privateKey),
    kaz_sign: await encryptPrivateKey(masterKey, kazSignKeyPair.privateKey)
  };

  // 6. Create root folder KEK
  const rootKek = crypto.getRandomValues(new Uint8Array(32));
  const { wrappedKey, kemCiphertexts } = await encapsulateKey(rootKek, {
    ml_kem: mlKemKeyPair.publicKey,
    kaz_kem: kazKemKeyPair.publicKey
  });

  // 7. Encrypt and sign root folder
  const folderMetadata = { name: 'My Vault', color: null, icon: null };
  const metadataNonce = crypto.getRandomValues(new Uint8Array(12));
  const encryptedMetadata = await aesGcmEncrypt(
    rootKek, metadataNonce,
    JSON.stringify(folderMetadata)
  );

  const createdAt = new Date().toISOString();
  const folderSignature = await combinedSign(
    mlDsaKeyPair.privateKey,
    kazSignKeyPair.privateKey,
    canonicalize({ /* folder data */ })
  );

  // 8. Submit to server
  const response = await fetch(`/api/v1/invite/${token}/accept`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({
      display_name: displayName,
      password: password,  // For server-side validation only
      public_keys: {
        ml_kem: base64Encode(mlKemKeyPair.publicKey),
        ml_dsa: base64Encode(mlDsaKeyPair.publicKey),
        kaz_kem: base64Encode(kazKemKeyPair.publicKey),
        kaz_sign: base64Encode(kazSignKeyPair.publicKey)
      },
      encrypted_master_key: base64Encode(encryptedMk),
      mk_nonce: base64Encode(mkNonce),
      encrypted_private_keys: encryptedPrivateKeys,
      key_derivation_salt: base64Encode(salt),
      root_folder: {
        encrypted_metadata: base64Encode(encryptedMetadata),
        metadata_nonce: base64Encode(metadataNonce),
        owner_key_access: { wrapped_kek: wrappedKey, kem_ciphertexts: kemCiphertexts },
        created_at: createdAt,
        signature: folderSignature
      }
    })
  });

  // 9. Clear sensitive data
  masterKey.fill(0);
  authKey.fill(0);
  rootKek.fill(0);

  return await response.json();
}
```

### 4.5 Server Processing

```elixir
def accept_invitation(token, params) do
  Repo.transaction(fn ->
    # 1. Validate token
    invitation = validate_and_get_invitation(token)

    # 2. Verify not already used
    if invitation.status != :pending do
      throw {:error, :invitation_#{invitation.status}}
    end

    # 3. Check not expired
    if DateTime.compare(invitation.expires_at, DateTime.utc_now()) == :lt do
      throw {:error, :invitation_expired}
    end

    # 4. Verify root folder signature
    verify_folder_signature!(params.public_keys, params.root_folder)

    # 5. Create user with pre-assigned role
    user = create_user(%{
      email: invitation.email,
      display_name: params.display_name,
      tenant_id: invitation.tenant_id,
      role: invitation.role,
      status: :active
    })

    # 6. Store key bundle
    create_key_bundle(user.id, params)

    # 7. Create root folder
    create_root_folder(user.id, params.root_folder)

    # 8. Mark invitation as accepted
    update_invitation(invitation, %{
      status: :accepted,
      accepted_at: DateTime.utc_now(),
      accepted_by_id: user.id
    })

    # 9. Notify inviter
    send_acceptance_notification(invitation.inviter_id, user)

    # 10. Issue session
    session = create_session(user)

    {user, session}
  end)
end
```

## 5. Mobile Implementation

### 5.1 Android Deep Link Handler

```kotlin
class InvitationActivity : ComponentActivity() {

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        // Handle deep link
        val uri = intent.data
        if (uri?.pathSegments?.firstOrNull() == "invite") {
            val token = uri.pathSegments.getOrNull(1)
            if (token != null) {
                handleInvitation(token)
            }
        }
    }

    private fun handleInvitation(token: String) {
        lifecycleScope.launch {
            try {
                // Validate token
                if (!isValidInvitationToken(token)) {
                    showError("Invalid invitation link")
                    return@launch
                }

                // Fetch invitation info
                val invitation = invitationRepository.getInvitationInfo(token)

                if (!invitation.valid) {
                    showError(getErrorMessage(invitation.errorReason))
                    return@launch
                }

                // Navigate to accept screen
                navController.navigate(
                    InvitationAcceptRoute(
                        token = token,
                        tenantName = invitation.tenantName,
                        inviterName = invitation.inviterName,
                        role = invitation.role,
                        email = invitation.email
                    )
                )
            } catch (e: Exception) {
                showError("Failed to load invitation")
            }
        }
    }

    private fun isValidInvitationToken(token: String): Boolean {
        if (token.isEmpty() || token.length < 8 || token.length > 256) return false

        val pathTraversalPatterns = listOf("../", "..\\", "%2e%2e", "%252e")
        if (pathTraversalPatterns.any { token.lowercase().contains(it) }) return false

        val allowedChars = ('a'..'z') + ('A'..'Z') + ('0'..'9') + listOf('-', '_', '.')
        return token.all { it in allowedChars }
    }
}
```

### 5.2 iOS Universal Link Handler

```swift
class AppCoordinator: ObservableObject {

    func handleUniversalLink(_ url: URL) {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: true),
              components.path.hasPrefix("/invite/") else {
            return
        }

        let token = String(components.path.dropFirst("/invite/".count))

        guard isValidInvitationToken(token) else {
            showError("Invalid invitation link")
            return
        }

        Task {
            do {
                let invitation = try await invitationService.getInvitationInfo(token: token)

                guard invitation.valid else {
                    showError(getErrorMessage(invitation.errorReason))
                    return
                }

                await MainActor.run {
                    navigationPath.append(
                        InvitationAcceptRoute(
                            token: token,
                            invitation: invitation
                        )
                    )
                }
            } catch {
                showError("Failed to load invitation")
            }
        }
    }

    private func isValidInvitationToken(_ token: String) -> Bool {
        guard !token.isEmpty, token.count >= 8, token.count <= 256 else { return false }

        let pathTraversalPatterns = ["../", "..\\", "%2e%2e", "%252e"]
        for pattern in pathTraversalPatterns {
            if token.lowercased().contains(pattern) { return false }
        }

        let allowedCharacters = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_."))
        return token.unicodeScalars.allSatisfy { allowedCharacters.contains($0) }
    }
}
```

## 6. UI Screens

### 6.1 Invitation Accept Screen

```
+---------------------------------------+
|           SecureSharing               |
+---------------------------------------+
|                                       |
|   +-------------------------------+   |
|   |     [Tenant Logo/Icon]        |   |
|   |                               |   |
|   |   You've been invited to      |   |
|   |   join Acme Corporation       |   |
|   |                               |   |
|   |   Invited by: John Doe        |   |
|   |   Your role: Member           |   |
|   |                               |   |
|   |   "Welcome to the team!       |   |
|   |    Looking forward to         |   |
|   |    collaborating."            |   |
|   +-------------------------------+   |
|                                       |
|   +-------------------------------+   |
|   |        [ Accept ]             |   |
|   +-------------------------------+   |
|                                       |
|   Expires in 6 days                   |
|                                       |
+---------------------------------------+
```

### 6.2 Registration Form (After Accept)

```
+---------------------------------------+
|           Create Account              |
+---------------------------------------+
|                                       |
|   Email (from invitation)             |
|   +-------------------------------+   |
|   | newuser@example.com           |   |
|   +-------------------------------+   |
|   (cannot be changed)                 |
|                                       |
|   Display Name                        |
|   +-------------------------------+   |
|   | Jane Smith                    |   |
|   +-------------------------------+   |
|                                       |
|   Password                            |
|   +-------------------------------+   |
|   | ••••••••••••                  |   |
|   +-------------------------------+   |
|                                       |
|   Confirm Password                    |
|   +-------------------------------+   |
|   | ••••••••••••                  |   |
|   +-------------------------------+   |
|                                       |
|   +-------------------------------+   |
|   |     [ Create Account ]        |   |
|   +-------------------------------+   |
|                                       |
+---------------------------------------+
```

### 6.3 Key Generation Progress

```
+---------------------------------------+
|         Setting Up Security           |
+---------------------------------------+
|                                       |
|         [Spinning indicator]          |
|                                       |
|   Generating encryption keys...       |
|                                       |
|   +-------------------------------+   |
|   | ████████████░░░░░░░░  60%     |   |
|   +-------------------------------+   |
|                                       |
|   This may take a few seconds.        |
|   Your keys are being generated       |
|   locally on your device.             |
|                                       |
+---------------------------------------+
```

## 7. Error Handling

| Error | User Message | Recovery Action |
|-------|--------------|-----------------|
| `not_found` | "This invitation link is invalid." | Contact inviter for new link |
| `expired` | "This invitation has expired." | Contact inviter for new invitation |
| `revoked` | "This invitation was cancelled." | Contact inviter |
| `already_used` | "This invitation has already been used." | Login with existing account |
| Network error | "Unable to connect. Please try again." | Retry with exponential backoff |
| Signature invalid | "Security verification failed." | Clear app data, retry |

## 8. Security Considerations

### 8.1 Token Security
- 256-bit random tokens provide 2^256 possible values
- Tokens are single-use and expire after 7 days (configurable)
- Only token hash is stored in database
- Constant-time comparison via hash lookup

### 8.2 Rate Limiting
- Accept attempts limited to 10 per IP per hour
- Prevents brute-force token guessing

### 8.3 Input Validation
- Token validated for path traversal attacks
- Token validated for injection patterns
- Email locked to invitation (cannot be changed)

### 8.4 Zero-Knowledge
- Password never sent to server in plaintext
- Master key generated and encrypted client-side
- Server stores only encrypted key material

## 9. Related Documentation

- [Registration Flow](./01-registration-flow.md) - Standard registration
- [Invitations API](../api/09-invitations.md) - API specification
- [Invitation System Design](../design/invitation-system.md) - Full design document
- [Key Hierarchy](../crypto/02-key-hierarchy.md) - Key derivation details
