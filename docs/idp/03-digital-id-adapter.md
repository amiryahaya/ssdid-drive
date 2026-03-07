# Digital ID Adapter

**Version**: 1.0.0
**Status**: Draft
**Last Updated**: 2025-01

## 1. Overview

This document specifies the Digital ID adapter implementation for SecureSharing. Digital IDs are government-issued electronic identities used in Malaysia (MyDigital ID), Singapore (SingPass), and other countries.

## 2. Supported Digital ID Providers

| Provider | Country | Authentication | Certificate |
|----------|---------|----------------|-------------|
| MyDigital ID | Malaysia | Mobile app + QR/Push | PKI-based |
| SingPass | Singapore | Mobile app + QR/Push | PKI-based |
| Custom | Various | Configurable | PKI-based |

## 3. Provider Configuration

### 3.1 Configuration Schema

```typescript
interface DigitalIdConfig {
  // Provider identification
  provider: 'mydigital_my' | 'singpass_sg' | 'custom';
  displayName: string;

  // API endpoints
  apiEndpoint: string;
  authorizationEndpoint: string;
  tokenEndpoint: string;
  userInfoEndpoint: string;

  // Client credentials
  clientId: string;
  clientSecret: string;  // Encrypted at rest

  // Certificate configuration
  certificateFingerprint?: string;
  trustedCaCerts?: string[];

  // Security options
  signatureAlgorithm: 'RS256' | 'ES256' | 'EdDSA';
  encryptionAlgorithm?: string;

  // Session options
  timeout: number;         // Authentication timeout in ms
  sessionExpiry: number;   // Session expiry in seconds

  // Vault password settings
  requireVaultPassword: boolean;  // Always true for Digital ID
}
```

### 3.2 MyDigital ID Configuration

```typescript
const myDigitalIdConfig: DigitalIdConfig = {
  provider: 'mydigital_my',
  displayName: 'MyDigital ID',
  apiEndpoint: 'https://api.mydigital.gov.my/v1',
  authorizationEndpoint: 'https://api.mydigital.gov.my/v1/authorize',
  tokenEndpoint: 'https://api.mydigital.gov.my/v1/token',
  userInfoEndpoint: 'https://api.mydigital.gov.my/v1/userinfo',
  clientId: 'securesharing-client',
  clientSecret: 'encrypted:...',
  signatureAlgorithm: 'RS256',
  timeout: 300000,  // 5 minutes for mobile authentication
  sessionExpiry: 3600,
  requireVaultPassword: true
};
```

### 3.3 SingPass Configuration

```typescript
const singPassConfig: DigitalIdConfig = {
  provider: 'singpass_sg',
  displayName: 'SingPass',
  apiEndpoint: 'https://api.singpass.gov.sg/v2',
  authorizationEndpoint: 'https://api.singpass.gov.sg/v2/authorize',
  tokenEndpoint: 'https://api.singpass.gov.sg/v2/token',
  userInfoEndpoint: 'https://api.singpass.gov.sg/v2/userinfo',
  clientId: 'securesharing-sg',
  clientSecret: 'encrypted:...',
  signatureAlgorithm: 'ES256',
  timeout: 300000,
  sessionExpiry: 3600,
  requireVaultPassword: true
};
```

## 4. Digital ID Provider Implementation

```typescript
class DigitalIdProvider implements IdentityProvider {
  readonly type = 'digital_id';
  readonly displayName: string;
  readonly supportsKeyDerivation = false;  // Requires vault password

  private config: DigitalIdConfig;
  private httpClient: HttpClient;

  async initialize(config: IdpConfig): Promise<void> {
    this.config = config.settings as DigitalIdConfig;
    this.displayName = this.config.displayName;

    // Initialize HTTP client with certificate pinning
    this.httpClient = new HttpClient({
      baseUrl: this.config.apiEndpoint,
      certificateFingerprint: this.config.certificateFingerprint,
      timeout: this.config.timeout
    });

    // Decrypt client secret
    this.config.clientSecret = await decryptSecret(this.config.clientSecret);
  }

  async initiateAuth(context: AuthContext): Promise<AuthRequest> {
    // Generate state and nonce
    const state = base64UrlEncode(crypto.getRandomValues(new Uint8Array(32)));
    const nonce = base64UrlEncode(crypto.getRandomValues(new Uint8Array(32)));

    // Store state for verification
    await this.storeAuthState(state, {
      nonce,
      flow: context.flow,
      redirectUri: context.redirectUri,
      createdAt: Date.now()
    });

    // Build authorization URL
    const authUrl = new URL(this.config.authorizationEndpoint);
    authUrl.searchParams.set('client_id', this.config.clientId);
    authUrl.searchParams.set('response_type', 'code');
    authUrl.searchParams.set('redirect_uri', context.redirectUri!);
    authUrl.searchParams.set('scope', 'openid profile email');
    authUrl.searchParams.set('state', state);
    authUrl.searchParams.set('nonce', nonce);

    // Add provider-specific parameters
    if (this.config.provider === 'mydigital_my') {
      authUrl.searchParams.set('acr_values', 'face_id');
    } else if (this.config.provider === 'singpass_sg') {
      authUrl.searchParams.set('acr_values', 'urn:singpass:level2');
    }

    // Generate QR code for mobile app authentication
    const qrCodeData = await this.generateQrCode(state, nonce);

    return {
      type: 'digital_id',
      authorizationUrl: authUrl.toString(),
      qrCodeData,
      sessionId: state
    };
  }

  async validateAuth(response: AuthResponse): Promise<AuthResult> {
    const { code, state } = response;

    if (!code || !state) {
      throw new IdpError('AUTH_FAILED', 'Missing authorization code or state');
    }

    // Retrieve and verify stored state
    const storedState = await this.getAuthState(state);
    if (!storedState) {
      throw new IdpError('AUTH_FAILED', 'Invalid or expired state');
    }

    // Exchange code for tokens
    const tokens = await this.exchangeCode(code, storedState.redirectUri);

    // Verify ID token
    const idToken = await this.verifyIdToken(tokens.id_token, storedState.nonce);

    // Get user info
    const userInfo = await this.getUserInfo(tokens.access_token);

    // Extract certificate information for key derivation
    const certInfo = await this.extractCertificateInfo(idToken);

    // Clear stored state
    await this.clearAuthState(state);

    return {
      success: true,
      externalId: userInfo.sub,
      email: userInfo.email,
      displayName: userInfo.name,
      keyMaterial: {
        source: 'certificate',
        value: certInfo.publicKeyHash,
        requiresPassword: true,
        salt: certInfo.publicKeyHash.slice(0, 16)  // Use part of cert as salt
      },
      metadata: {
        provider: this.config.provider,
        idNumber: userInfo.id_number,
        verified: userInfo.verified,
        certificate: certInfo
      }
    };
  }

  private async exchangeCode(
    code: string,
    redirectUri: string
  ): Promise<TokenResponse> {

    const response = await this.httpClient.post(this.config.tokenEndpoint, {
      grant_type: 'authorization_code',
      code,
      redirect_uri: redirectUri,
      client_id: this.config.clientId,
      client_secret: this.config.clientSecret
    });

    if (!response.ok) {
      throw new IdpError('AUTH_FAILED', 'Token exchange failed');
    }

    return response.json();
  }

  private async verifyIdToken(
    idToken: string,
    expectedNonce: string
  ): Promise<JwtPayload> {

    // Get provider's JWKS
    const jwks = await this.getJwks();

    // Verify token signature
    const payload = await verifyJwt(idToken, jwks, {
      algorithms: [this.config.signatureAlgorithm],
      issuer: this.config.apiEndpoint,
      audience: this.config.clientId
    });

    // Verify nonce
    if (payload.nonce !== expectedNonce) {
      throw new IdpError('AUTH_FAILED', 'Invalid nonce');
    }

    return payload;
  }

  private async getUserInfo(accessToken: string): Promise<UserInfo> {
    const response = await this.httpClient.get(this.config.userInfoEndpoint, {
      headers: {
        'Authorization': `Bearer ${accessToken}`
      }
    });

    if (!response.ok) {
      throw new IdpError('AUTH_FAILED', 'Failed to get user info');
    }

    return response.json();
  }

  private async extractCertificateInfo(idToken: JwtPayload): Promise<CertInfo> {
    // Extract certificate from token claims
    const certClaim = idToken['x5c'] || idToken['certificate'];

    if (!certClaim) {
      // Generate deterministic hash from user info
      return {
        publicKeyHash: await sha256(idToken.sub + idToken.iss)
      };
    }

    // Parse certificate
    const cert = parseCertificate(certClaim);

    return {
      publicKeyHash: await sha256(cert.publicKey),
      subject: cert.subject,
      issuer: cert.issuer,
      validFrom: cert.validFrom,
      validTo: cert.validTo
    };
  }

  private async generateQrCode(state: string, nonce: string): Promise<string> {
    // Generate QR code for mobile app deep link
    const deepLink = this.buildDeepLink(state, nonce);
    return await generateQrCodeDataUrl(deepLink);
  }

  private buildDeepLink(state: string, nonce: string): string {
    const schemes: Record<string, string> = {
      'mydigital_my': 'mydigitalid://',
      'singpass_sg': 'singpass://'
    };

    const scheme = schemes[this.config.provider] || 'digitalid://';
    return `${scheme}auth?state=${state}&nonce=${nonce}&client_id=${this.config.clientId}`;
  }

  async getUserProfile(token: string): Promise<UserProfile> {
    const userInfo = await this.getUserInfo(token);

    return {
      id: userInfo.sub,
      email: userInfo.email,
      displayName: userInfo.name,
      verified: userInfo.verified || true,
      metadata: {
        idNumber: userInfo.id_number,
        provider: this.config.provider
      }
    };
  }

  // State management
  private async storeAuthState(state: string, data: AuthStateData): Promise<void> {
    await authStateStore.set(state, data, this.config.timeout);
  }

  private async getAuthState(state: string): Promise<AuthStateData | null> {
    return await authStateStore.get(state);
  }

  private async clearAuthState(state: string): Promise<void> {
    await authStateStore.delete(state);
  }

  // JWKS management
  private jwksCache: { keys: JWK[]; fetchedAt: number } | null = null;

  private async getJwks(): Promise<JWK[]> {
    const JWKS_CACHE_TTL = 3600000; // 1 hour

    if (this.jwksCache && Date.now() - this.jwksCache.fetchedAt < JWKS_CACHE_TTL) {
      return this.jwksCache.keys;
    }

    const response = await this.httpClient.get(
      `${this.config.apiEndpoint}/.well-known/jwks.json`
    );

    const jwks = await response.json();
    this.jwksCache = { keys: jwks.keys, fetchedAt: Date.now() };

    return jwks.keys;
  }
}
```

## 5. Client-Side Integration

### 5.1 Authentication Flow

```typescript
async function authenticateWithDigitalId(
  providerId: string,
  redirectUri: string
): Promise<void> {

  // Initiate authentication
  const response = await fetch('/api/v1/auth/digital-id/authorize', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({
      provider_id: providerId,
      redirect_uri: redirectUri
    })
  });

  const { data } = await response.json();

  // Option 1: Redirect to authorization URL
  // window.location.href = data.authorization_url;

  // Option 2: Show QR code for mobile app
  showQrCodeModal({
    qrCodeData: data.qr_code_data,
    sessionId: data.session_id,
    onSuccess: () => handleCallback(data.session_id),
    onTimeout: () => showTimeoutError()
  });

  // Option 3: Deep link for mobile browsers
  if (isMobile()) {
    window.location.href = data.deep_link;
  }
}
```

### 5.2 Callback Handling

```typescript
// Login result returned to the application
interface LoginResult {
  session: {
    token: string;
    expiresAt: Date;
  };
  user: {
    id: string;
    email: string;
    displayName: string;
  };
  encryptionKey: Uint8Array;
  keyBundle: KeyBundle;
}

async function handleDigitalIdCallback(
  code: string,
  state: string
): Promise<LoginResult> {

  // Exchange code for auth result
  // See docs/api/01-authentication.md Section 4.15
  const response = await fetch('/api/v1/auth/digital-id/callback', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ code, state })
  });

  if (!response.ok) {
    const error = await response.json();
    throw new AuthError(error.error.code, error.error.message);
  }

  const { data } = await response.json();

  // Handle existing user vs new user flows
  if (data.status === 'new_user') {
    // Redirect to registration flow
    return handleNewUserRegistration(data);
  }

  // Existing user flow
  // Digital ID always requires vault password for OIDC-style auth
  const vaultPassword = await promptVaultPassword(
    'Please enter your vault password to unlock your encryption keys.'
  );

  // Derive encryption key from key material + vault password
  // See docs/crypto/02-key-hierarchy.md Section 3.1
  const keyMaterial = base64Decode(data.key_material);
  const salt = base64Decode(data.key_salt);

  const encryptionKey = await deriveEncryptionKey(keyMaterial, salt, vaultPassword);

  return {
    session: {
      token: data.session.token,
      expiresAt: new Date(data.session.expires_at)
    },
    user: {
      id: data.user.id,
      email: data.user.email,
      displayName: data.user.display_name
    },
    encryptionKey,
    keyBundle: data.key_bundle
  };
}

async function deriveEncryptionKey(
  keyMaterial: Uint8Array,  // SHA-256(certificate_public_key)
  salt: Uint8Array,         // SHA-256(issuer + user_id)[0:16]
  vaultPassword: string
): Promise<Uint8Array> {

  // Step 1: Derive key from password using Argon2id
  const passwordKey = await argon2id(vaultPassword, {
    salt,
    memory: 65536,      // 64 MiB
    iterations: 3,
    parallelism: 4,
    hashLength: 32
  });

  // Step 2: Combine password key with IdP material via HKDF
  // Uses concatenation, NOT XOR (XOR is fragile with predictable inputs)
  // See docs/crypto/02-key-hierarchy.md Section 3.1 for specification
  return await hkdfDerive(
    concatenate(passwordKey, keyMaterial),
    "SecureSharing-MasterKey-v1",  // salt
    "mk-encryption-key",            // info
    32
  );
}
```

### 5.3 Polling for Mobile Authentication

```typescript
async function pollForAuthentication(
  sessionId: string,
  timeout: number = 300000
): Promise<AuthResult> {

  const startTime = Date.now();
  const pollInterval = 2000; // 2 seconds

  while (Date.now() - startTime < timeout) {
    const response = await fetch(`/api/v1/auth/digital-id/status/${sessionId}`);
    const { data } = await response.json();

    if (data.status === 'completed') {
      return data.result;
    }

    if (data.status === 'failed') {
      throw new Error(data.error || 'Authentication failed');
    }

    // Wait before next poll
    await sleep(pollInterval);
  }

  throw new Error('Authentication timeout');
}
```

## 6. Key Material Derivation

**Canonical Specification**: See [docs/crypto/02-key-hierarchy.md](../crypto/02-key-hierarchy.md) Section 3.1 for the authoritative key derivation specification.

### 6.1 Derivation Process

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                 DIGITAL ID KEY DERIVATION                                    │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│  Certificate Public Key                 Vault Password                      │
│         │                                     │                              │
│         │ SHA-256                             │                              │
│         ▼                                     │                              │
│  ┌─────────────┐                              │                              │
│  │  IdP Binding│                              │                              │
│  │  Material   │                              │                              │
│  │  (32 bytes) │                              │                              │
│  └──────┬──────┘                              │                              │
│         │                                     │                              │
│         │            Salt = SHA-256(issuer + user_id)[0:16]                 │
│         │                     │                                              │
│         │                     ▼                                              │
│         │              ┌─────────────┐                                       │
│         │              │    Salt     │───────────┐                           │
│         │              │  (16 bytes) │           │                           │
│         │              └─────────────┘           │ Argon2id                  │
│         │                                        ▼                           │
│         │                                 ┌─────────────┐                    │
│         │                                 │  Password   │                    │
│         │                                 │    Key      │                    │
│         │                                 │  (32 bytes) │                    │
│         │                                 └──────┬──────┘                    │
│         │                                        │                           │
│         └────────────────┬───────────────────────┘                           │
│                          │ Concatenate (NOT XOR)                             │
│                          ▼                                                   │
│                   ┌─────────────┐                                            │
│                   │  Combined   │                                            │
│                   │  Material   │                                            │
│                   │  (64 bytes) │                                            │
│                   └──────┬──────┘                                            │
│                          │                                                   │
│                          │ HKDF-SHA-384                                      │
│                          │ salt = "SecureSharing-MasterKey-v1"               │
│                          │ info = "mk-encryption-key"                        │
│                          ▼                                                   │
│                   ┌─────────────┐                                            │
│                   │ Encryption  │                                            │
│                   │    Key      │                                            │
│                   │  (32 bytes) │                                            │
│                   └─────────────┘                                            │
│                                                                              │
│  Why HKDF(concatenate(...)) instead of XOR:                                 │
│  - XOR is fragile if inputs have predictable patterns                       │
│  - HKDF provides cryptographically secure mixing                            │
│  - HKDF provides domain separation via salt and info                        │
│                                                                              │
│  The certificate public key hash provides:                                  │
│  - User-specific binding (prevents password reuse attacks)                  │
│  - Additional entropy                                                       │
│  - Protection against offline password attacks                              │
│                                                                              │
└─────────────────────────────────────────────────────────────────────────────┘
```

## 7. Error Handling

| Error | Cause | User Message |
|-------|-------|--------------|
| AUTH_CANCELLED | User cancelled in mobile app | "Authentication was cancelled" |
| AUTH_TIMEOUT | User didn't respond in time | "Authentication timed out" |
| CERT_EXPIRED | Certificate has expired | "Your Digital ID certificate has expired" |
| CERT_REVOKED | Certificate was revoked | "Your Digital ID has been revoked" |
| NETWORK_ERROR | Cannot reach Digital ID service | "Cannot connect to Digital ID service" |
| INVALID_STATE | State parameter mismatch | "Security error - please try again" |

## 8. Security Considerations

### 8.1 Certificate Verification

- Verify certificate chain to trusted CA
- Check certificate revocation status
- Validate certificate validity period

### 8.2 State Protection

- State parameter prevents CSRF
- Nonce prevents replay attacks
- Short state expiry time

### 8.3 Key Material Security

- Certificate hash provides user binding
- Vault password adds user-specific entropy
- Combined derivation resists offline attacks

### 8.4 Transport Security

- All communication over TLS 1.3
- Certificate pinning for known providers
- Encrypted tokens at rest
