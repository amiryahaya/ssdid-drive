# WebAuthn Adapter

**Version**: 1.0.0
**Status**: Draft
**Last Updated**: 2025-01

## 1. Overview

This document specifies the WebAuthn (Passkey) adapter implementation for SecureSharing. WebAuthn provides hardware-bound authentication with optional PRF extension for cryptographic key derivation.

## 2. Provider Configuration

### 2.1 Configuration Schema

```typescript
interface WebAuthnConfig {
  // Relying Party configuration
  rpId: string;                    // e.g., "securesharing.com"
  rpName: string;                  // e.g., "SecureSharing"

  // Registration options
  attestation: 'none' | 'indirect' | 'direct' | 'enterprise';
  userVerification: 'required' | 'preferred' | 'discouraged';
  residentKey: 'required' | 'preferred' | 'discouraged';

  // PRF extension
  prfEnabled: boolean;             // Enable PRF for key derivation
  prfFallbackEnabled: boolean;     // Allow fallback to vault password

  // Security options
  timeout: number;                 // Milliseconds (default: 60000)
  authenticatorSelection?: {
    authenticatorAttachment?: 'platform' | 'cross-platform';
    requireResidentKey?: boolean;
  };

  // Supported algorithms (default: ES256, RS256)
  pubKeyCredParams?: PublicKeyCredentialParameters[];
}
```

### 2.2 Default Configuration

```typescript
const defaultWebAuthnConfig: WebAuthnConfig = {
  rpId: 'securesharing.com',
  rpName: 'SecureSharing',
  attestation: 'none',
  userVerification: 'required',
  residentKey: 'preferred',
  prfEnabled: true,
  prfFallbackEnabled: true,
  timeout: 60000,
  pubKeyCredParams: [
    { type: 'public-key', alg: -7 },   // ES256
    { type: 'public-key', alg: -257 }  // RS256
  ]
};
```

## 3. WebAuthn Provider Implementation

```typescript
class WebAuthnProvider implements IdentityProvider {
  readonly type = 'webauthn';
  readonly displayName = 'Passkey';
  readonly supportsKeyDerivation = true;

  private config: WebAuthnConfig;
  private rpId: string;

  async initialize(config: IdpConfig): Promise<void> {
    this.config = { ...defaultWebAuthnConfig, ...config.settings } as WebAuthnConfig;
    this.rpId = this.config.rpId;
  }

  async initiateAuth(context: AuthContext): Promise<AuthRequest> {
    if (context.flow === 'registration') {
      return this.initiateRegistration(context);
    } else {
      return this.initiateLogin(context);
    }
  }

  private async initiateRegistration(context: AuthContext): Promise<AuthRequest> {
    // Generate challenge
    const challenge = crypto.getRandomValues(new Uint8Array(32));

    // Store challenge for verification
    await this.storeChallenge(challenge, context);

    const publicKeyOptions: PublicKeyCredentialCreationOptions = {
      challenge,
      rp: {
        id: this.rpId,
        name: this.config.rpName
      },
      user: {
        id: new TextEncoder().encode(context.email || generateUserId()),
        name: context.email || 'user',
        displayName: context.email || 'User'
      },
      pubKeyCredParams: this.config.pubKeyCredParams!,
      timeout: this.config.timeout,
      attestation: this.config.attestation,
      authenticatorSelection: {
        ...this.config.authenticatorSelection,
        userVerification: this.config.userVerification,
        residentKey: this.config.residentKey
      },
      extensions: this.buildExtensions()
    };

    return {
      type: 'webauthn',
      publicKeyOptions
    };
  }

  private async initiateLogin(context: AuthContext): Promise<AuthRequest> {
    // Generate challenge
    const challenge = crypto.getRandomValues(new Uint8Array(32));

    // Get allowed credentials for user (if email provided)
    let allowCredentials: PublicKeyCredentialDescriptor[] | undefined;
    if (context.email) {
      const credentials = await this.getUserCredentials(context.email);
      if (credentials.length > 0) {
        allowCredentials = credentials.map(c => ({
          type: 'public-key' as const,
          id: base64Decode(c.credential_id)
        }));
      }
    }

    // Store challenge for verification
    await this.storeChallenge(challenge, context);

    const publicKeyOptions: PublicKeyCredentialRequestOptions = {
      challenge,
      rpId: this.rpId,
      timeout: this.config.timeout,
      userVerification: this.config.userVerification,
      allowCredentials,
      extensions: this.buildExtensions()
    };

    return {
      type: 'webauthn',
      publicKeyOptions
    };
  }

  private buildExtensions(): AuthenticationExtensionsClientInputs {
    const extensions: AuthenticationExtensionsClientInputs = {};

    if (this.config.prfEnabled) {
      extensions.prf = {
        eval: {
          first: new TextEncoder().encode('securesharing-mk-encryption')
        }
      };
    }

    return extensions;
  }

  async validateAuth(response: AuthResponse): Promise<AuthResult> {
    const credential = response.credential;
    if (!credential) {
      throw new IdpError('INVALID_CREDENTIAL', 'No credential provided');
    }

    // Determine if this is registration or login
    const isRegistration = 'attestationObject' in credential.response;

    if (isRegistration) {
      return this.validateRegistration(credential);
    } else {
      return this.validateLogin(credential);
    }
  }

  private async validateRegistration(
    credential: PublicKeyCredential
  ): Promise<AuthResult> {
    const response = credential.response as AuthenticatorAttestationResponse;

    // Verify attestation
    const verification = await verifyRegistrationResponse({
      response: {
        id: credential.id,
        rawId: base64Encode(new Uint8Array(credential.rawId)),
        response: {
          clientDataJSON: base64Encode(new Uint8Array(response.clientDataJSON)),
          attestationObject: base64Encode(new Uint8Array(response.attestationObject))
        },
        type: 'public-key',
        clientExtensionResults: credential.getClientExtensionResults()
      },
      expectedChallenge: await this.getStoredChallenge(),
      expectedOrigin: `https://${this.rpId}`,
      expectedRPID: this.rpId
    });

    if (!verification.verified) {
      throw new IdpError('AUTH_FAILED', 'Registration verification failed');
    }

    // Extract PRF output if available
    const keyMaterial = this.extractKeyMaterial(credential);

    return {
      success: true,
      externalId: credential.id,
      email: '', // Set by caller
      keyMaterial,
      metadata: {
        credentialId: credential.id,
        publicKey: base64Encode(verification.registrationInfo!.credentialPublicKey),
        counter: verification.registrationInfo!.counter,
        credentialType: verification.registrationInfo!.credentialType,
        attestationType: verification.registrationInfo!.attestationObject
      }
    };
  }

  private async validateLogin(
    credential: PublicKeyCredential
  ): Promise<AuthResult> {
    const response = credential.response as AuthenticatorAssertionResponse;

    // Get stored credential
    const storedCredential = await this.getCredentialById(credential.id);
    if (!storedCredential) {
      throw new IdpError('CREDENTIAL_NOT_FOUND', 'Credential not registered');
    }

    // Verify assertion
    const verification = await verifyAuthenticationResponse({
      response: {
        id: credential.id,
        rawId: base64Encode(new Uint8Array(credential.rawId)),
        response: {
          clientDataJSON: base64Encode(new Uint8Array(response.clientDataJSON)),
          authenticatorData: base64Encode(new Uint8Array(response.authenticatorData)),
          signature: base64Encode(new Uint8Array(response.signature)),
          userHandle: response.userHandle
            ? base64Encode(new Uint8Array(response.userHandle))
            : undefined
        },
        type: 'public-key',
        clientExtensionResults: credential.getClientExtensionResults()
      },
      expectedChallenge: await this.getStoredChallenge(),
      expectedOrigin: `https://${this.rpId}`,
      expectedRPID: this.rpId,
      authenticator: {
        credentialID: base64Decode(storedCredential.credential_id),
        credentialPublicKey: base64Decode(storedCredential.public_key),
        counter: storedCredential.counter
      }
    });

    if (!verification.verified) {
      throw new IdpError('AUTH_FAILED', 'Authentication verification failed');
    }

    // Update counter
    await this.updateCredentialCounter(credential.id, verification.authenticationInfo.newCounter);

    // Extract PRF output if available
    const keyMaterial = this.extractKeyMaterial(credential);

    return {
      success: true,
      userId: storedCredential.user_id,
      externalId: credential.id,
      email: storedCredential.email,
      keyMaterial,
      metadata: {
        counter: verification.authenticationInfo.newCounter
      }
    };
  }

  private extractKeyMaterial(credential: PublicKeyCredential): KeyMaterial {
    const extensions = credential.getClientExtensionResults();

    if (extensions.prf?.results?.first) {
      // PRF output available - direct key derivation possible
      return {
        source: 'prf',
        value: new Uint8Array(extensions.prf.results.first),
        requiresPassword: false
      };
    }

    // PRF not available - require vault password
    if (this.config.prfFallbackEnabled) {
      return {
        source: 'derived',
        requiresPassword: true
      };
    }

    throw new IdpError(
      'KEY_DERIVATION_FAILED',
      'PRF extension not supported and fallback disabled'
    );
  }

  async getKeyMaterial(context: KeyMaterialContext): Promise<KeyMaterial> {
    // This is called after validateAuth, key material is already extracted
    throw new Error('Key material extracted during validateAuth');
  }

  async getUserProfile(token: string): Promise<UserProfile> {
    const credential = await this.getCredentialByToken(token);
    return {
      id: credential.user_id,
      email: credential.email,
      displayName: credential.display_name,
      verified: true
    };
  }

  // Helper methods
  private async storeChallenge(challenge: Uint8Array, context: AuthContext): Promise<void> {
    await challengeStore.set(context.state || 'default', {
      challenge: base64Encode(challenge),
      createdAt: Date.now(),
      expiresAt: Date.now() + this.config.timeout
    });
  }

  private async getStoredChallenge(): Promise<string> {
    const stored = await challengeStore.get('default');
    if (!stored || Date.now() > stored.expiresAt) {
      throw new IdpError('AUTH_EXPIRED', 'Challenge expired');
    }
    return stored.challenge;
  }

  private async getUserCredentials(email: string): Promise<StoredCredential[]> {
    return await db.credentials.findByEmail(email, 'webauthn');
  }

  private async getCredentialById(credentialId: string): Promise<StoredCredential | null> {
    return await db.credentials.findByCredentialId(credentialId);
  }

  private async updateCredentialCounter(credentialId: string, counter: number): Promise<void> {
    await db.credentials.updateCounter(credentialId, counter);
  }
}
```

## 4. Client-Side Integration

### 4.1 Registration Flow

```typescript
async function registerWithWebAuthn(
  email: string,
  displayName: string
): Promise<RegistrationResult> {

  // Get registration options from server
  const optionsResponse = await fetch('/api/v1/auth/webauthn/register/options', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ email, display_name: displayName })
  });

  const { data: options } = await optionsResponse.json();

  // Create credential
  const credential = await navigator.credentials.create({
    publicKey: deserializeOptions(options.publicKeyOptions)
  }) as PublicKeyCredential;

  if (!credential) {
    throw new Error('Credential creation cancelled');
  }

  // Check PRF support
  const extensions = credential.getClientExtensionResults();
  const prfSupported = !!extensions.prf?.results?.first;

  // If PRF not supported, prompt for vault password
  let vaultPassword: string | undefined;
  if (!prfSupported) {
    vaultPassword = await promptVaultPassword(
      'Your device does not support secure key derivation. ' +
      'Please create a vault password to protect your encryption keys.'
    );
  }

  // Submit registration
  const response = await fetch('/api/v1/auth/webauthn/register/complete', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({
      credential: serializeCredential(credential),
      vault_password_required: !prfSupported
    })
  });

  const { data } = await response.json();

  return {
    userId: data.user.id,
    credential: {
      id: credential.id,
      prfSupported
    },
    keyMaterial: prfSupported
      ? new Uint8Array(extensions.prf!.results!.first!)
      : null,
    vaultPassword
  };
}
```

### 4.2 Login Flow

```typescript
interface WebAuthnLoginResult {
  user: {
    id: string;
    email: string;
    display_name: string;
    status: string;
  };
  session: {
    token: string;
    expires_at: string;
  };
  keyBundle: {
    encrypted_master_key: string;
    mk_nonce: string;
    public_keys: PublicKeys;
    encrypted_private_keys: EncryptedPrivateKeys;
  };
  keyMaterial: Uint8Array | null;  // PRF output for MK decryption
  vaultPassword?: string;           // Fallback if PRF not available
}

async function loginWithWebAuthn(email?: string): Promise<WebAuthnLoginResult> {

  // Get authentication options from server
  const optionsResponse = await fetch('/api/v1/auth/webauthn/login/options', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ email })
  });

  const { data: options } = await optionsResponse.json();

  // Authenticate with PRF extension
  const credential = await navigator.credentials.get({
    publicKey: {
      ...deserializeOptions(options.publicKeyOptions),
      extensions: {
        prf: {
          eval: {
            first: new TextEncoder().encode('securesharing-mk-encryption')
          }
        }
      }
    }
  }) as PublicKeyCredential;

  if (!credential) {
    throw new Error('Authentication cancelled');
  }

  // Check PRF output
  const extensions = credential.getClientExtensionResults();
  const prfOutput = extensions.prf?.results?.first;

  // Complete authentication with server
  // See docs/api/01-authentication.md Section 4.5
  const response = await fetch('/api/v1/auth/webauthn/login/complete', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({
      credential: serializeCredential(credential)
    })
  });

  if (!response.ok) {
    const error = await response.json();
    throw new Error(error.error?.message || 'Authentication failed');
  }

  const { data } = await response.json();

  // If PRF not available, prompt for vault password
  // (user registered with vault password fallback)
  let vaultPassword: string | undefined;
  if (!prfOutput) {
    vaultPassword = await promptVaultPassword(
      'Please enter your vault password to unlock your encryption keys.'
    );
  }

  return {
    user: data.user,
    session: data.session,
    keyBundle: data.key_bundle,
    keyMaterial: prfOutput ? new Uint8Array(prfOutput) : null,
    vaultPassword
  };
}
```

## 5. PRF Extension Details

### 5.1 PRF Salt Management

```typescript
const PRF_SALT = 'securesharing-mk-encryption';

// PRF input is consistent across all operations
const prfInput = {
  first: new TextEncoder().encode(PRF_SALT)
};

// For registration
const registrationOptions = {
  publicKey: {
    // ... other options
    extensions: {
      prf: {
        eval: prfInput
      }
    }
  }
};

// For authentication
const authOptions = {
  publicKey: {
    // ... other options
    extensions: {
      prf: {
        eval: prfInput
      }
    }
  }
};
```

### 5.2 PRF Output Processing

```typescript
async function processPreOutput(
  prfOutput: ArrayBuffer
): Promise<Uint8Array> {
  // PRF output is 32 bytes
  const prfBytes = new Uint8Array(prfOutput);

  // Derive encryption key using HKDF
  const encryptionKey = await hkdfDerive(
    prfBytes,
    'master-key-encryption',
    32,  // 256 bits
    'SHA-384'
  );

  // Clear PRF output
  prfBytes.fill(0);

  return encryptionKey;
}
```

## 6. Multiple Passkey Support

### 6.1 Adding Additional Passkeys

```typescript
async function addPasskey(
  existingCredentialId: string,
  existingPrfOutput: Uint8Array
): Promise<void> {

  // Verify with existing credential first
  const verified = await verifyExistingPasskey(existingCredentialId);
  if (!verified) {
    throw new Error('Failed to verify existing passkey');
  }

  // Get current encrypted MK
  const keyBundle = await fetchKeyBundle();

  // Register new passkey
  const options = await fetch('/api/v1/auth/webauthn/register/options', {
    method: 'POST',
    headers: {
      'Authorization': `Bearer ${sessionManager.getSession()}`,
      'Content-Type': 'application/json'
    },
    body: JSON.stringify({ add_credential: true })
  });

  const newCredential = await navigator.credentials.create({
    publicKey: deserializeOptions(options.publicKeyOptions)
  }) as PublicKeyCredential;

  const newExtensions = newCredential.getClientExtensionResults();
  const newPrfOutput = newExtensions.prf?.results?.first;

  if (newPrfOutput) {
    // Decrypt MK with existing key and re-encrypt with new key
    const existingKey = await processPreOutput(existingPrfOutput);
    const mk = await aesGcmDecrypt(
      existingKey,
      base64Decode(keyBundle.mk_nonce),
      base64Decode(keyBundle.encrypted_master_key)
    );

    const newKey = await processPreOutput(newPrfOutput);
    const newNonce = crypto.getRandomValues(new Uint8Array(12));
    const newEncryptedMk = await aesGcmEncrypt(newKey, newNonce, mk);

    // Submit new credential with re-encrypted MK
    await fetch('/api/v1/auth/webauthn/register/complete', {
      method: 'POST',
      headers: {
        'Authorization': `Bearer ${sessionManager.getSession()}`,
        'Content-Type': 'application/json'
      },
      body: JSON.stringify({
        credential: serializeCredential(newCredential),
        encrypted_mk: base64Encode(newEncryptedMk),
        mk_nonce: base64Encode(newNonce)
      })
    });

    // Clear sensitive data
    mk.fill(0);
    existingKey.fill(0);
    newKey.fill(0);
  }
}
```

## 7. Error Handling

| Error | Cause | User Message |
|-------|-------|--------------|
| NotAllowedError | User cancelled or timeout | "Authentication was cancelled or timed out" |
| InvalidStateError | Credential already exists | "This passkey is already registered" |
| NotSupportedError | Platform doesn't support WebAuthn | "Passkeys are not supported on this device" |
| SecurityError | Wrong origin | "Security error - please check the URL" |
| PRF not supported | Browser/authenticator doesn't support PRF | "Vault password required for this device" |

## 8. Security Considerations

### 8.1 Challenge Security

- Challenges are cryptographically random
- Challenges expire after timeout (default 60s)
- Each challenge is single-use

### 8.2 Counter Verification

- Counter must always increase
- Counter rollback indicates cloned credential
- Alert on counter anomalies

### 8.3 PRF Security

- PRF salt is constant per application
- PRF output is hardware-bound
- PRF provides 256-bit entropy
