# OIDC Adapter

**Version**: 1.0.0
**Status**: Draft
**Last Updated**: 2025-01

## 1. Overview

This document specifies the OpenID Connect (OIDC) adapter implementation for SecureSharing. OIDC enables authentication via enterprise identity providers like Azure AD, Okta, Auth0, and Google Workspace.

## 2. Supported OIDC Providers

| Provider | Authorization | Token | PKCE Support |
|----------|---------------|-------|--------------|
| Azure AD | ✓ | ✓ | ✓ |
| Okta | ✓ | ✓ | ✓ |
| Auth0 | ✓ | ✓ | ✓ |
| Google | ✓ | ✓ | ✓ |
| Keycloak | ✓ | ✓ | ✓ |
| Generic | ✓ | ✓ | Configurable |

## 3. Provider Configuration

### 3.1 Configuration Schema

```typescript
interface OidcConfig {
  // Provider identification
  displayName: string;
  providerType: 'azure' | 'okta' | 'auth0' | 'google' | 'keycloak' | 'generic';

  // OIDC discovery
  issuer: string;  // e.g., "https://login.microsoftonline.com/{tenant}/v2.0"
  discoveryUrl?: string;  // Override discovery endpoint

  // Client credentials
  clientId: string;
  clientSecret?: string;  // Optional for PKCE-only flows

  // OAuth2 settings
  scopes: string[];
  responseType: 'code' | 'id_token' | 'code id_token';
  responseMode: 'query' | 'fragment' | 'form_post';

  // PKCE settings
  pkceEnabled: boolean;
  pkceMethod: 'S256' | 'plain';

  // Token settings
  tokenEndpointAuthMethod: 'client_secret_basic' | 'client_secret_post' | 'private_key_jwt' | 'none';

  // Additional parameters
  additionalParams?: Record<string, string>;

  // Session settings
  sessionExpiry: number;

  // Vault password (always required for OIDC)
  requireVaultPassword: boolean;

  // User attribute mapping
  attributeMapping: {
    userId: string;      // Claim for user ID (default: "sub")
    email: string;       // Claim for email (default: "email")
    displayName: string; // Claim for display name (default: "name")
  };
}
```

### 3.2 Azure AD Configuration

```typescript
const azureAdConfig: OidcConfig = {
  displayName: 'Microsoft',
  providerType: 'azure',
  issuer: 'https://login.microsoftonline.com/{tenant-id}/v2.0',
  clientId: 'client-id',
  clientSecret: 'encrypted:...',
  scopes: ['openid', 'email', 'profile', 'offline_access'],
  responseType: 'code',
  responseMode: 'query',
  pkceEnabled: true,
  pkceMethod: 'S256',
  tokenEndpointAuthMethod: 'client_secret_post',
  sessionExpiry: 3600,
  requireVaultPassword: true,
  attributeMapping: {
    userId: 'oid',
    email: 'email',
    displayName: 'name'
  }
};
```

### 3.3 Okta Configuration

```typescript
const oktaConfig: OidcConfig = {
  displayName: 'Okta',
  providerType: 'okta',
  issuer: 'https://{domain}.okta.com/oauth2/default',
  clientId: 'client-id',
  clientSecret: 'encrypted:...',
  scopes: ['openid', 'email', 'profile'],
  responseType: 'code',
  responseMode: 'query',
  pkceEnabled: true,
  pkceMethod: 'S256',
  tokenEndpointAuthMethod: 'client_secret_basic',
  sessionExpiry: 3600,
  requireVaultPassword: true,
  attributeMapping: {
    userId: 'sub',
    email: 'email',
    displayName: 'name'
  }
};
```

### 3.4 Google Configuration

```typescript
const googleConfig: OidcConfig = {
  displayName: 'Google',
  providerType: 'google',
  issuer: 'https://accounts.google.com',
  clientId: 'client-id.apps.googleusercontent.com',
  clientSecret: 'encrypted:...',
  scopes: ['openid', 'email', 'profile'],
  responseType: 'code',
  responseMode: 'query',
  pkceEnabled: true,
  pkceMethod: 'S256',
  tokenEndpointAuthMethod: 'client_secret_post',
  sessionExpiry: 3600,
  requireVaultPassword: true,
  attributeMapping: {
    userId: 'sub',
    email: 'email',
    displayName: 'name'
  }
};
```

## 4. OIDC Provider Implementation

```typescript
class OidcProvider implements IdentityProvider {
  readonly type = 'oidc';
  readonly displayName: string;
  readonly supportsKeyDerivation = false;  // Requires vault password

  private config: OidcConfig;
  private discovery: OidcDiscovery | null = null;

  async initialize(config: IdpConfig): Promise<void> {
    this.config = config.settings as OidcConfig;
    this.displayName = this.config.displayName;

    // Fetch OIDC discovery document
    await this.fetchDiscovery();

    // Decrypt client secret if present
    if (this.config.clientSecret?.startsWith('encrypted:')) {
      this.config.clientSecret = await decryptSecret(this.config.clientSecret);
    }
  }

  private async fetchDiscovery(): Promise<void> {
    const discoveryUrl = this.config.discoveryUrl ||
      `${this.config.issuer}/.well-known/openid-configuration`;

    const response = await fetch(discoveryUrl);
    if (!response.ok) {
      throw new IdpError('IDP_UNAVAILABLE', 'Failed to fetch OIDC discovery');
    }

    this.discovery = await response.json();
  }

  async initiateAuth(context: AuthContext): Promise<AuthRequest> {
    if (!this.discovery) {
      await this.fetchDiscovery();
    }

    // Generate state and nonce
    const state = base64UrlEncode(crypto.getRandomValues(new Uint8Array(32)));
    const nonce = base64UrlEncode(crypto.getRandomValues(new Uint8Array(32)));

    // Generate PKCE if enabled
    let codeVerifier: string | undefined;
    let codeChallenge: string | undefined;

    if (this.config.pkceEnabled) {
      codeVerifier = base64UrlEncode(crypto.getRandomValues(new Uint8Array(32)));
      codeChallenge = await this.generateCodeChallenge(codeVerifier);
    }

    // Store auth state
    await this.storeAuthState(state, {
      nonce,
      codeVerifier,
      flow: context.flow,
      redirectUri: context.redirectUri!,
      createdAt: Date.now()
    });

    // Build authorization URL
    const authUrl = new URL(this.discovery!.authorization_endpoint);
    authUrl.searchParams.set('client_id', this.config.clientId);
    authUrl.searchParams.set('response_type', this.config.responseType);
    authUrl.searchParams.set('redirect_uri', context.redirectUri!);
    authUrl.searchParams.set('scope', this.config.scopes.join(' '));
    authUrl.searchParams.set('state', state);
    authUrl.searchParams.set('nonce', nonce);

    if (codeChallenge) {
      authUrl.searchParams.set('code_challenge', codeChallenge);
      authUrl.searchParams.set('code_challenge_method', this.config.pkceMethod);
    }

    // Add provider-specific parameters
    if (this.config.additionalParams) {
      for (const [key, value] of Object.entries(this.config.additionalParams)) {
        authUrl.searchParams.set(key, value);
      }
    }

    return {
      type: 'oidc',
      authorizationUrl: authUrl.toString()
    };
  }

  async validateAuth(response: AuthResponse): Promise<AuthResult> {
    const { code, state } = response;

    if (!code || !state) {
      throw new IdpError('AUTH_FAILED', 'Missing authorization code or state');
    }

    // Retrieve stored state
    const storedState = await this.getAuthState(state);
    if (!storedState) {
      throw new IdpError('AUTH_FAILED', 'Invalid or expired state');
    }

    // Exchange code for tokens
    const tokens = await this.exchangeCode(code, storedState);

    // Verify ID token
    const idToken = await this.verifyIdToken(tokens.id_token, storedState.nonce);

    // Get user info (optional, for additional claims)
    let userInfo: UserInfo | undefined;
    if (this.discovery!.userinfo_endpoint && tokens.access_token) {
      userInfo = await this.getUserInfo(tokens.access_token);
    }

    // Clear stored state
    await this.clearAuthState(state);

    // Extract user attributes
    const userId = idToken[this.config.attributeMapping.userId] || idToken.sub;
    const email = idToken[this.config.attributeMapping.email] ||
                  userInfo?.email ||
                  idToken.email;
    const displayName = idToken[this.config.attributeMapping.displayName] ||
                        userInfo?.name ||
                        idToken.name;

    return {
      success: true,
      externalId: userId,
      email,
      displayName,
      keyMaterial: {
        source: 'derived',
        value: await this.deriveKeyMaterial(idToken),
        requiresPassword: true,
        salt: await this.generateSalt(userId)
      },
      metadata: {
        provider: this.config.providerType,
        idToken: idToken,
        accessToken: tokens.access_token,
        refreshToken: tokens.refresh_token
      }
    };
  }

  private async exchangeCode(
    code: string,
    storedState: AuthStateData
  ): Promise<TokenResponse> {

    const params = new URLSearchParams();
    params.set('grant_type', 'authorization_code');
    params.set('code', code);
    params.set('redirect_uri', storedState.redirectUri);
    params.set('client_id', this.config.clientId);

    if (this.config.clientSecret &&
        this.config.tokenEndpointAuthMethod === 'client_secret_post') {
      params.set('client_secret', this.config.clientSecret);
    }

    if (storedState.codeVerifier) {
      params.set('code_verifier', storedState.codeVerifier);
    }

    const headers: Record<string, string> = {
      'Content-Type': 'application/x-www-form-urlencoded'
    };

    if (this.config.clientSecret &&
        this.config.tokenEndpointAuthMethod === 'client_secret_basic') {
      const credentials = btoa(`${this.config.clientId}:${this.config.clientSecret}`);
      headers['Authorization'] = `Basic ${credentials}`;
    }

    const response = await fetch(this.discovery!.token_endpoint, {
      method: 'POST',
      headers,
      body: params.toString()
    });

    if (!response.ok) {
      const error = await response.json();
      throw new IdpError('AUTH_FAILED', error.error_description || 'Token exchange failed');
    }

    return response.json();
  }

  private async verifyIdToken(
    idToken: string,
    expectedNonce: string
  ): Promise<JwtPayload> {

    // Get JWKS
    const jwksResponse = await fetch(this.discovery!.jwks_uri);
    const jwks = await jwksResponse.json();

    // Verify token
    const payload = await verifyJwt(idToken, jwks.keys, {
      issuer: this.config.issuer,
      audience: this.config.clientId
    });

    // Verify nonce
    if (payload.nonce !== expectedNonce) {
      throw new IdpError('AUTH_FAILED', 'Invalid nonce');
    }

    return payload;
  }

  private async getUserInfo(accessToken: string): Promise<UserInfo> {
    const response = await fetch(this.discovery!.userinfo_endpoint, {
      headers: {
        'Authorization': `Bearer ${accessToken}`
      }
    });

    if (!response.ok) {
      // UserInfo endpoint is optional, don't fail
      return {};
    }

    return response.json();
  }

  private async deriveKeyMaterial(idToken: JwtPayload): Promise<Uint8Array> {
    // Combine stable claims for key material
    const material = JSON.stringify({
      sub: idToken.sub,
      iss: idToken.iss,
      aud: idToken.aud
    });

    return await sha256(material);
  }

  private async generateSalt(userId: string): Promise<Uint8Array> {
    return await sha256(`securesharing:${this.config.issuer}:${userId}`);
  }

  private async generateCodeChallenge(verifier: string): Promise<string> {
    if (this.config.pkceMethod === 'plain') {
      return verifier;
    }

    const hash = await crypto.subtle.digest(
      'SHA-256',
      new TextEncoder().encode(verifier)
    );

    return base64UrlEncode(new Uint8Array(hash));
  }

  async refreshAuth(refreshToken: string): Promise<AuthResult> {
    const params = new URLSearchParams();
    params.set('grant_type', 'refresh_token');
    params.set('refresh_token', refreshToken);
    params.set('client_id', this.config.clientId);

    if (this.config.clientSecret) {
      params.set('client_secret', this.config.clientSecret);
    }

    const response = await fetch(this.discovery!.token_endpoint, {
      method: 'POST',
      headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
      body: params.toString()
    });

    if (!response.ok) {
      throw new IdpError('AUTH_FAILED', 'Token refresh failed');
    }

    const tokens = await response.json();
    const idToken = await this.verifyIdToken(tokens.id_token, '');

    return {
      success: true,
      externalId: idToken.sub,
      email: idToken.email,
      metadata: {
        accessToken: tokens.access_token,
        refreshToken: tokens.refresh_token || refreshToken
      }
    };
  }

  async revokeAuth(token: string): Promise<void> {
    if (!this.discovery!.revocation_endpoint) {
      return; // Revocation not supported
    }

    const params = new URLSearchParams();
    params.set('token', token);
    params.set('client_id', this.config.clientId);

    if (this.config.clientSecret) {
      params.set('client_secret', this.config.clientSecret);
    }

    await fetch(this.discovery!.revocation_endpoint, {
      method: 'POST',
      headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
      body: params.toString()
    });
  }

  async getUserProfile(token: string): Promise<UserProfile> {
    const userInfo = await this.getUserInfo(token);

    return {
      id: userInfo.sub!,
      email: userInfo.email!,
      displayName: userInfo.name,
      verified: userInfo.email_verified || false
    };
  }

  // State management
  private async storeAuthState(state: string, data: AuthStateData): Promise<void> {
    await authStateStore.set(state, data, 600000); // 10 minutes
  }

  private async getAuthState(state: string): Promise<AuthStateData | null> {
    return await authStateStore.get(state);
  }

  private async clearAuthState(state: string): Promise<void> {
    await authStateStore.delete(state);
  }
}
```

## 5. Client-Side Integration

### 5.1 Authentication Flow

```typescript
async function authenticateWithOidc(
  providerId: string,
  redirectUri: string
): Promise<void> {

  // Initiate authentication
  const response = await fetch('/api/v1/auth/oidc/authorize', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({
      provider_id: providerId,
      redirect_uri: redirectUri
    })
  });

  const { data } = await response.json();

  // Redirect to IdP
  window.location.href = data.authorization_url;
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
  isNewUser: boolean;
}

async function handleOidcCallback(
  code: string,
  state: string
): Promise<LoginResult> {

  // Exchange code for auth result
  // See docs/api/01-authentication.md Section 4.7
  const response = await fetch('/api/v1/auth/oidc/callback', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ code, state })
  });

  if (!response.ok) {
    const error = await response.json();
    throw new AuthError(error.error.code, error.error.message);
  }

  const { data } = await response.json();

  // Handle new user vs existing user
  if (data.status === 'new_user') {
    // Redirect to registration flow
    return handleNewUserRegistration(data);
  }

  // Existing user flow
  // OIDC always requires vault password (no key material from IdP)
  const vaultPassword = await promptVaultPassword(
    'Enter your vault password to unlock your encryption keys.'
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
    keyBundle: data.key_bundle,
    isNewUser: false
  };
}

async function deriveEncryptionKey(
  keyMaterial: Uint8Array,  // SHA-256({sub, iss, aud})
  salt: Uint8Array,         // SHA-256(issuer + sub)[0:16]
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

### 5.3 Token Refresh

```typescript
async function refreshOidcSession(): Promise<void> {
  const session = sessionManager.getSession();

  const response = await fetch('/api/v1/auth/oidc/refresh', {
    method: 'POST',
    headers: {
      'Authorization': `Bearer ${session.token}`,
      'Content-Type': 'application/json'
    }
  });

  if (!response.ok) {
    // Refresh failed, need full re-authentication
    throw new Error('SESSION_EXPIRED');
  }

  const { data } = await response.json();

  // Update session with new token
  sessionManager.setSession({
    token: data.token,
    expiresAt: data.expires_at
  });
}
```

## 6. Key Material Derivation

**Canonical Specification**: See [docs/crypto/02-key-hierarchy.md](../crypto/02-key-hierarchy.md) Section 3.1 for the authoritative key derivation specification.

### 6.1 Derivation Process

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                    OIDC KEY DERIVATION                                       │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│  ID Token Claims                        Vault Password                      │
│  (sub, iss, aud)                              │                              │
│         │                                     │                              │
│         │ SHA-256                             │                              │
│         ▼                                     │                              │
│  ┌─────────────┐                              │                              │
│  │  IdP Binding│                              │                              │
│  │  Material   │                              │                              │
│  │  (32 bytes) │                              │                              │
│  └──────┬──────┘                              │                              │
│         │                                     │                              │
│         │            Salt = SHA-256(issuer + sub)[0:16]                     │
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
│  Why vault password is required:                                            │
│  - OIDC tokens don't provide secret key material                            │
│  - ID token claims are not secret (can be read from JWT)                    │
│  - Vault password adds user-specific entropy                                │
│  - Combined derivation prevents offline attacks                             │
│                                                                              │
└─────────────────────────────────────────────────────────────────────────────┘
```

## 7. Error Handling

| Error | Cause | User Message |
|-------|-------|--------------|
| invalid_request | Missing parameters | "Invalid request" |
| unauthorized_client | Client not authorized | "Application not authorized" |
| access_denied | User denied consent | "Access was denied" |
| invalid_scope | Invalid scopes requested | "Invalid permissions requested" |
| server_error | IdP server error | "Authentication service error" |
| temporarily_unavailable | IdP temporarily down | "Service temporarily unavailable" |
| invalid_grant | Invalid or expired code | "Session expired, please try again" |

## 8. Security Considerations

### 8.1 PKCE (Proof Key for Code Exchange)

- Always enable PKCE for public clients
- Use S256 method (SHA-256) over plain
- Code verifier is 43-128 characters

### 8.2 State and Nonce

- State prevents CSRF attacks
- Nonce prevents replay attacks
- Both are cryptographically random

### 8.3 Token Security

- Access tokens are short-lived
- Refresh tokens stored securely
- ID tokens validated completely

### 8.4 Vault Password

- Required for all OIDC flows
- Minimum strength requirements
- Combined with IdP material for key derivation
