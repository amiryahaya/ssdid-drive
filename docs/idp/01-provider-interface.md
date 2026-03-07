# Identity Provider Interface

**Version**: 1.0.0
**Status**: Draft
**Last Updated**: 2025-01

## 1. Overview

This document defines the abstract interface for identity providers (IdPs) in SecureSharing. The pluggable IdP architecture allows tenants to configure multiple authentication methods.

## 2. Provider Interface

### 2.1 Core Interface Definition

```typescript
interface IdentityProvider {
  /**
   * Unique identifier for this provider type
   */
  readonly type: IdpType;

  /**
   * Human-readable provider name
   */
  readonly displayName: string;

  /**
   * Check if this provider can derive cryptographic key material
   */
  readonly supportsKeyDerivation: boolean;

  /**
   * Initialize the provider with tenant-specific configuration
   */
  initialize(config: IdpConfig): Promise<void>;

  /**
   * Start authentication flow
   * Returns auth request data (e.g., challenge for WebAuthn, redirect URL for OIDC)
   */
  initiateAuth(context: AuthContext): Promise<AuthRequest>;

  /**
   * Validate authentication response
   * Returns authenticated user info and optional key material
   */
  validateAuth(response: AuthResponse): Promise<AuthResult>;

  /**
   * Get key material for encryption key derivation
   * Only available if supportsKeyDerivation is true
   */
  getKeyMaterial?(context: KeyMaterialContext): Promise<KeyMaterial>;

  /**
   * Refresh authentication (if supported)
   */
  refreshAuth?(token: RefreshToken): Promise<AuthResult>;

  /**
   * Revoke authentication
   */
  revokeAuth?(token: string): Promise<void>;

  /**
   * Get user profile information
   */
  getUserProfile(token: string): Promise<UserProfile>;
}
```

### 2.2 Type Definitions

```typescript
type IdpType = 'webauthn' | 'digital_id' | 'oidc' | 'saml';

interface IdpConfig {
  id: string;              // Provider instance ID
  tenantId: string;        // Tenant this config belongs to
  type: IdpType;
  enabled: boolean;
  priority: number;        // Display order
  settings: Record<string, unknown>;  // Type-specific settings
}

interface AuthContext {
  flow: 'registration' | 'login';
  email?: string;
  redirectUri?: string;
  state?: string;
  nonce?: string;
}

interface AuthRequest {
  type: IdpType;
  // WebAuthn
  publicKeyOptions?: PublicKeyCredentialCreationOptions | PublicKeyCredentialRequestOptions;
  // OIDC/SAML
  authorizationUrl?: string;
  // Digital ID
  qrCodeData?: string;
  sessionId?: string;
}

interface AuthResponse {
  type: IdpType;
  // WebAuthn
  credential?: PublicKeyCredential;
  // OIDC
  code?: string;
  state?: string;
  // Digital ID
  signedAssertion?: string;
}

interface AuthResult {
  success: boolean;
  userId?: string;          // Internal user ID (if existing user)
  externalId: string;       // ID from the IdP
  email: string;
  displayName?: string;
  keyMaterial?: KeyMaterial;
  token?: string;           // Auth token for session creation
  metadata?: Record<string, unknown>;
}

interface KeyMaterial {
  source: 'prf' | 'certificate' | 'derived' | 'vault_password';
  value?: Uint8Array;       // Direct key material (e.g., PRF output)
  requiresPassword: boolean; // If true, vault password needed
  salt?: Uint8Array;        // Salt for password derivation
}

interface UserProfile {
  id: string;
  email: string;
  displayName?: string;
  verified: boolean;
  metadata?: Record<string, unknown>;
}
```

## 3. Provider Registry

### 3.1 Registry Implementation

```typescript
class IdentityProviderRegistry {
  private providers: Map<IdpType, typeof IdentityProvider> = new Map();
  private instances: Map<string, IdentityProvider> = new Map();

  /**
   * Register a provider implementation
   */
  register(type: IdpType, providerClass: typeof IdentityProvider): void {
    this.providers.set(type, providerClass);
  }

  /**
   * Create and initialize a provider instance
   */
  async createInstance(config: IdpConfig): Promise<IdentityProvider> {
    const ProviderClass = this.providers.get(config.type);
    if (!ProviderClass) {
      throw new Error(`Unknown provider type: ${config.type}`);
    }

    const instance = new ProviderClass();
    await instance.initialize(config);

    this.instances.set(config.id, instance);
    return instance;
  }

  /**
   * Get a provider instance
   */
  getInstance(configId: string): IdentityProvider | undefined {
    return this.instances.get(configId);
  }

  /**
   * Get all registered provider types
   */
  getAvailableTypes(): IdpType[] {
    return Array.from(this.providers.keys());
  }
}

// Global registry
export const idpRegistry = new IdentityProviderRegistry();

// Register default providers
idpRegistry.register('webauthn', WebAuthnProvider);
idpRegistry.register('digital_id', DigitalIdProvider);
idpRegistry.register('oidc', OidcProvider);
idpRegistry.register('saml', SamlProvider);
```

### 3.2 Provider Selection for Tenant

```typescript
async function getProvidersForTenant(tenantId: string): Promise<IdpConfig[]> {
  const configs = await db.idpConfigs.findMany({
    where: { tenant_id: tenantId, enabled: true },
    orderBy: { priority: 'asc' }
  });

  return configs;
}

async function selectProviderForUser(
  tenantId: string,
  email: string
): Promise<IdpConfig | null> {
  // Check user's registered credentials
  const user = await db.users.findByEmail(tenantId, email);

  if (user) {
    // Return provider for user's primary credential
    const credential = await db.credentials.findPrimary(user.id);
    if (credential) {
      return await db.idpConfigs.findOne({
        tenant_id: tenantId,
        type: credential.type
      });
    }
  }

  // Return first available provider for new users
  const providers = await getProvidersForTenant(tenantId);
  return providers[0] || null;
}
```

## 4. Key Material Derivation

**Canonical Specification**: See [docs/crypto/02-key-hierarchy.md](../crypto/02-key-hierarchy.md) Section 3.1 for the authoritative key derivation specification.

### 4.1 Key Material Sources

| Provider | Key Material Source | Requires Vault Password |
|----------|---------------------|-------------------------|
| WebAuthn | PRF extension output (32 bytes) | No |
| WebAuthn (no PRF) | N/A (must use vault password) | Yes |
| Digital ID | SHA-256(certificate_public_key) | Yes |
| OIDC | SHA-256({sub, iss, aud}) | Yes |
| SAML | SHA-256(assertion_id + issuer) | Yes |

### 4.2 Key Derivation Flow

The derivation uses **HKDF(concatenate(...))** to combine password key with IdP material.
**XOR is NOT used** as it can be fragile with predictable inputs.

```typescript
async function deriveEncryptionKey(
  authResult: AuthResult,
  vaultPassword?: string
): Promise<Uint8Array> {

  const keyMaterial = authResult.keyMaterial;

  if (!keyMaterial) {
    throw new Error('No key material available');
  }

  // WebAuthn with PRF: Direct key material
  if (keyMaterial.source === 'prf') {
    return hkdfDerive(
      keyMaterial.value!,
      "SecureSharing-MasterKey-v1",  // salt
      "mk-encryption-key",            // info
      32
    );
  }

  // Digital ID / OIDC / SAML: Vault password required
  if (keyMaterial.requiresPassword) {
    if (!vaultPassword) {
      throw new Error('Vault password required');
    }

    // Step 1: Derive key from vault password using Argon2id
    const salt = keyMaterial.salt || await generateSalt();
    const passwordKey = await argon2id(vaultPassword, {
      salt,
      memory: 65536,      // 64 MiB
      iterations: 3,
      parallelism: 4,
      hashLength: 32
    });

    // Step 2: Combine password key with IdP material via HKDF
    // This provides cryptographically secure mixing (NOT XOR)
    if (keyMaterial.value) {
      return hkdfDerive(
        concatenate(passwordKey, keyMaterial.value),
        "SecureSharing-MasterKey-v1",  // salt
        "mk-encryption-key",            // info
        32
      );
    }

    // Fallback: password-only (not recommended)
    return hkdfDerive(
      passwordKey,
      "SecureSharing-MasterKey-v1",
      "mk-encryption-key",
      32
    );
  }

  throw new Error('Invalid key material configuration');
}
```

## 5. Provider Configuration Schema

### 5.1 Database Schema

```sql
CREATE TABLE idp_configs (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id UUID NOT NULL REFERENCES tenants(id),
    type VARCHAR(50) NOT NULL,
    name VARCHAR(255) NOT NULL,
    enabled BOOLEAN NOT NULL DEFAULT true,
    priority INTEGER NOT NULL DEFAULT 100,
    settings JSONB NOT NULL DEFAULT '{}',
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    CONSTRAINT valid_type CHECK (type IN ('webauthn', 'digital_id', 'oidc', 'saml'))
);

CREATE INDEX idx_idp_configs_tenant ON idp_configs(tenant_id);
CREATE UNIQUE INDEX idx_idp_configs_tenant_type ON idp_configs(tenant_id, type)
    WHERE enabled = true;
```

### 5.2 Configuration Examples

```typescript
// WebAuthn configuration
const webauthnConfig: IdpConfig = {
  id: 'wauth-001',
  tenantId: 'tenant-001',
  type: 'webauthn',
  enabled: true,
  priority: 1,
  settings: {
    rpId: 'securesharing.com',
    rpName: 'SecureSharing',
    attestation: 'none',
    userVerification: 'required',
    residentKey: 'preferred',
    prfEnabled: true
  }
};

// OIDC configuration
const oidcConfig: IdpConfig = {
  id: 'oidc-001',
  tenantId: 'tenant-001',
  type: 'oidc',
  enabled: true,
  priority: 2,
  settings: {
    issuer: 'https://login.microsoftonline.com/tenant-id/v2.0',
    clientId: 'client-id',
    clientSecret: 'encrypted:...',
    scopes: ['openid', 'email', 'profile'],
    responseType: 'code',
    responseMode: 'query'
  }
};

// Digital ID configuration
const digitalIdConfig: IdpConfig = {
  id: 'did-001',
  tenantId: 'tenant-001',
  type: 'digital_id',
  enabled: true,
  priority: 3,
  settings: {
    provider: 'mydigital_my',
    apiEndpoint: 'https://api.mydigital.gov.my',
    clientId: 'client-id',
    clientSecret: 'encrypted:...',
    certificateFingerprint: 'sha256:...'
  }
};

// SAML configuration
const samlConfig: IdpConfig = {
  id: 'saml-001',
  tenantId: 'tenant-001',
  type: 'saml',
  enabled: true,
  priority: 4,
  settings: {
    displayName: 'Enterprise SSO',
    entityId: 'https://securesharing.com/saml/metadata',
    assertionConsumerServiceUrl: 'https://api.securesharing.com/v1/auth/saml/acs',
    idpEntityId: 'https://idp.company.com/saml',
    ssoUrl: 'https://idp.company.com/saml/sso',
    certificate: '-----BEGIN CERTIFICATE-----\n...\n-----END CERTIFICATE-----',
    signRequests: true,
    signatureAlgorithm: 'RSA-SHA256',
    wantAssertionsSigned: true,
    wantAssertionsEncrypted: false,
    authnRequestBinding: 'HTTP-Redirect',
    nameIdFormat: 'emailAddress',
    attributeMapping: {
      userId: 'uid',
      email: 'email',
      displayName: 'displayName'
    }
  }
};
```

## 6. Error Handling

### 6.1 Provider Errors

```typescript
class IdpError extends Error {
  constructor(
    public code: IdpErrorCode,
    message: string,
    public details?: Record<string, unknown>
  ) {
    super(message);
  }
}

type IdpErrorCode =
  | 'IDP_NOT_CONFIGURED'
  | 'IDP_DISABLED'
  | 'IDP_UNAVAILABLE'
  | 'AUTH_FAILED'
  | 'AUTH_CANCELLED'
  | 'AUTH_EXPIRED'
  | 'INVALID_CREDENTIAL'
  | 'CREDENTIAL_NOT_FOUND'
  | 'KEY_DERIVATION_FAILED'
  | 'VAULT_PASSWORD_REQUIRED'
  | 'INVALID_CONFIGURATION';
```

### 6.2 Error Mapping

```typescript
function mapIdpError(error: unknown): IdpError {
  if (error instanceof IdpError) {
    return error;
  }

  // Map provider-specific errors
  if (isWebAuthnError(error)) {
    return mapWebAuthnError(error);
  }

  if (isOidcError(error)) {
    return mapOidcError(error);
  }

  // Generic error
  return new IdpError(
    'AUTH_FAILED',
    'Authentication failed',
    { originalError: String(error) }
  );
}
```

## 7. Provider Lifecycle

### 7.1 Initialization

```typescript
async function initializeProviders(tenantId: string): Promise<void> {
  const configs = await db.idpConfigs.findMany({
    where: { tenant_id: tenantId, enabled: true }
  });

  for (const config of configs) {
    try {
      await idpRegistry.createInstance(config);
      logger.info(`Initialized IdP: ${config.type} for tenant ${tenantId}`);
    } catch (error) {
      logger.error(`Failed to initialize IdP: ${config.type}`, error);
    }
  }
}
```

### 7.2 Health Checks

```typescript
async function checkProviderHealth(configId: string): Promise<HealthStatus> {
  const provider = idpRegistry.getInstance(configId);
  if (!provider) {
    return { healthy: false, reason: 'Provider not initialized' };
  }

  try {
    // Provider-specific health check
    if ('healthCheck' in provider) {
      return await provider.healthCheck();
    }
    return { healthy: true };
  } catch (error) {
    return { healthy: false, reason: String(error) };
  }
}
```

## 8. Security Considerations

### 8.1 Configuration Security

- Client secrets stored encrypted at rest
- Secrets decrypted only when needed
- Secrets rotated periodically

### 8.2 Token Security

- Tokens validated on every use
- Short token lifetimes
- Secure token storage

### 8.3 Key Material Security

- Key material never logged
- Key material cleared from memory after use
- Vault passwords processed client-side only
