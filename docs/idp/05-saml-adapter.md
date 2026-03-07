# SAML Adapter

**Version**: 1.0.0
**Status**: Draft
**Last Updated**: 2025-01

## 1. Overview

This document specifies the SAML 2.0 adapter implementation for SecureSharing. SAML enables authentication via enterprise identity providers that support SAML 2.0 federation, common in large organizations with existing SAML infrastructure.

## 2. Supported SAML Providers

| Provider | SP-Initiated | IdP-Initiated | Signed Assertions |
|----------|--------------|---------------|-------------------|
| ADFS | Yes | Yes | Yes |
| Azure AD | Yes | Yes | Yes |
| Okta | Yes | Yes | Yes |
| OneLogin | Yes | Yes | Yes |
| PingFederate | Yes | Yes | Yes |
| Shibboleth | Yes | Yes | Yes |
| Generic SAML 2.0 | Yes | Configurable | Configurable |

## 3. Provider Configuration

### 3.1 Configuration Schema

```typescript
interface SamlConfig {
  // Provider identification
  displayName: string;

  // Service Provider (SecureSharing) settings
  entityId: string;                    // SP entity ID
  assertionConsumerServiceUrl: string; // ACS URL

  // Identity Provider settings
  idpEntityId: string;                 // IdP entity ID
  ssoUrl: string;                      // IdP SSO URL (HTTP-Redirect or HTTP-POST)
  sloUrl?: string;                     // IdP SLO URL (optional)
  certificate: string;                 // IdP signing certificate (PEM format)

  // Request signing (SP to IdP)
  signRequests: boolean;
  signatureAlgorithm: 'RSA-SHA256' | 'RSA-SHA384' | 'RSA-SHA512';
  privateKey?: string;                 // SP private key for signing (encrypted)
  spCertificate?: string;              // SP certificate for IdP verification

  // Assertion settings
  wantAssertionsSigned: boolean;
  wantAssertionsEncrypted: boolean;
  decryptionPrivateKey?: string;       // For encrypted assertions

  // Binding preferences
  authnRequestBinding: 'HTTP-Redirect' | 'HTTP-POST';

  // Name ID settings
  nameIdFormat: 'unspecified' | 'emailAddress' | 'persistent' | 'transient';

  // Session settings
  sessionExpiry: number;               // In seconds

  // Vault password (always required for SAML)
  requireVaultPassword: boolean;

  // Attribute mapping
  attributeMapping: {
    userId: string;                    // Attribute for user ID
    email: string;                     // Attribute for email
    displayName: string;               // Attribute for display name
  };

  // Optional: Additional requested attributes
  requestedAttributes?: {
    name: string;
    friendlyName?: string;
    isRequired: boolean;
  }[];
}
```

### 3.2 ADFS Configuration

```typescript
const adfsConfig: SamlConfig = {
  displayName: 'ADFS',
  entityId: 'https://securesharing.com/saml/metadata',
  assertionConsumerServiceUrl: 'https://api.securesharing.com/v1/auth/saml/acs',
  idpEntityId: 'http://adfs.company.com/adfs/services/trust',
  ssoUrl: 'https://adfs.company.com/adfs/ls/',
  sloUrl: 'https://adfs.company.com/adfs/ls/?wa=wsignout1.0',
  certificate: '-----BEGIN CERTIFICATE-----\n...\n-----END CERTIFICATE-----',
  signRequests: true,
  signatureAlgorithm: 'RSA-SHA256',
  privateKey: 'encrypted:...',
  spCertificate: '-----BEGIN CERTIFICATE-----\n...\n-----END CERTIFICATE-----',
  wantAssertionsSigned: true,
  wantAssertionsEncrypted: false,
  authnRequestBinding: 'HTTP-Redirect',
  nameIdFormat: 'emailAddress',
  sessionExpiry: 3600,
  requireVaultPassword: true,
  attributeMapping: {
    userId: 'http://schemas.microsoft.com/identity/claims/objectidentifier',
    email: 'http://schemas.xmlsoap.org/ws/2005/05/identity/claims/emailaddress',
    displayName: 'http://schemas.xmlsoap.org/ws/2005/05/identity/claims/name'
  }
};
```

### 3.3 Azure AD SAML Configuration

```typescript
const azureAdSamlConfig: SamlConfig = {
  displayName: 'Azure AD',
  entityId: 'https://securesharing.com/saml/metadata',
  assertionConsumerServiceUrl: 'https://api.securesharing.com/v1/auth/saml/acs',
  idpEntityId: 'https://sts.windows.net/{tenant-id}/',
  ssoUrl: 'https://login.microsoftonline.com/{tenant-id}/saml2',
  sloUrl: 'https://login.microsoftonline.com/{tenant-id}/saml2',
  certificate: '-----BEGIN CERTIFICATE-----\n...\n-----END CERTIFICATE-----',
  signRequests: false,
  signatureAlgorithm: 'RSA-SHA256',
  wantAssertionsSigned: true,
  wantAssertionsEncrypted: false,
  authnRequestBinding: 'HTTP-Redirect',
  nameIdFormat: 'emailAddress',
  sessionExpiry: 3600,
  requireVaultPassword: true,
  attributeMapping: {
    userId: 'http://schemas.microsoft.com/identity/claims/objectidentifier',
    email: 'http://schemas.xmlsoap.org/ws/2005/05/identity/claims/emailaddress',
    displayName: 'http://schemas.microsoft.com/identity/claims/displayname'
  }
};
```

### 3.4 Okta SAML Configuration

```typescript
const oktaSamlConfig: SamlConfig = {
  displayName: 'Okta',
  entityId: 'https://securesharing.com/saml/metadata',
  assertionConsumerServiceUrl: 'https://api.securesharing.com/v1/auth/saml/acs',
  idpEntityId: 'http://www.okta.com/{idp-id}',
  ssoUrl: 'https://{domain}.okta.com/app/{app-id}/sso/saml',
  sloUrl: 'https://{domain}.okta.com/app/{app-id}/slo/saml',
  certificate: '-----BEGIN CERTIFICATE-----\n...\n-----END CERTIFICATE-----',
  signRequests: false,
  signatureAlgorithm: 'RSA-SHA256',
  wantAssertionsSigned: true,
  wantAssertionsEncrypted: false,
  authnRequestBinding: 'HTTP-POST',
  nameIdFormat: 'emailAddress',
  sessionExpiry: 3600,
  requireVaultPassword: true,
  attributeMapping: {
    userId: 'id',
    email: 'email',
    displayName: 'displayName'
  }
};
```

## 4. SAML Provider Implementation

```typescript
class SamlProvider implements IdentityProvider {
  readonly type = 'saml';
  readonly displayName: string;
  readonly supportsKeyDerivation = false;  // Requires vault password

  private config: SamlConfig;

  async initialize(config: IdpConfig): Promise<void> {
    this.config = config.settings as SamlConfig;
    this.displayName = this.config.displayName;

    // Parse and validate IdP certificate
    this.idpCertificate = parseCertificate(this.config.certificate);

    // Decrypt SP private key if present
    if (this.config.privateKey?.startsWith('encrypted:')) {
      this.spPrivateKey = await decryptSecret(this.config.privateKey);
    }

    // Decrypt decryption private key if present
    if (this.config.decryptionPrivateKey?.startsWith('encrypted:')) {
      this.decryptionKey = await decryptSecret(this.config.decryptionPrivateKey);
    }
  }

  async initiateAuth(context: AuthContext): Promise<AuthRequest> {
    // Generate unique request ID
    const requestId = `_${generateUuid()}`;
    const issueInstant = new Date().toISOString();

    // Build AuthnRequest
    const authnRequest = this.buildAuthnRequest(requestId, issueInstant, context);

    // Store request state for validation
    await this.storeAuthState(requestId, {
      flow: context.flow,
      redirectUri: context.redirectUri!,
      createdAt: Date.now()
    });

    // Generate authorization URL based on binding
    if (this.config.authnRequestBinding === 'HTTP-Redirect') {
      const deflatedRequest = await deflate(authnRequest);
      const encodedRequest = base64Encode(deflatedRequest);

      const url = new URL(this.config.ssoUrl);
      url.searchParams.set('SAMLRequest', encodedRequest);
      url.searchParams.set('RelayState', requestId);

      if (this.config.signRequests) {
        // Sign the URL parameters
        const signature = await this.signRedirectBinding(url);
        url.searchParams.set('SigAlg', this.getSignatureAlgorithmUri());
        url.searchParams.set('Signature', signature);
      }

      return {
        type: 'saml',
        authorizationUrl: url.toString()
      };
    } else {
      // HTTP-POST binding
      let signedRequest = authnRequest;
      if (this.config.signRequests) {
        signedRequest = await this.signPostBinding(authnRequest);
      }

      return {
        type: 'saml',
        samlRequest: base64Encode(signedRequest),
        relayState: requestId,
        postUrl: this.config.ssoUrl
      };
    }
  }

  async validateAuth(response: AuthResponse): Promise<AuthResult> {
    const { samlResponse, relayState } = response;

    if (!samlResponse || !relayState) {
      throw new IdpError('AUTH_FAILED', 'Missing SAML response or RelayState');
    }

    // Retrieve stored state
    const storedState = await this.getAuthState(relayState);
    if (!storedState) {
      throw new IdpError('AUTH_FAILED', 'Invalid or expired RelayState');
    }

    // Decode SAML response
    const decodedResponse = base64Decode(samlResponse);
    const responseXml = new TextDecoder().decode(decodedResponse);

    // Parse SAML response
    const parsedResponse = await this.parseSamlResponse(responseXml);

    // Validate response
    await this.validateSamlResponse(parsedResponse, relayState);

    // Decrypt assertion if encrypted
    let assertion = parsedResponse.assertion;
    if (parsedResponse.encryptedAssertion) {
      assertion = await this.decryptAssertion(parsedResponse.encryptedAssertion);
    }

    // Validate assertion signature
    if (this.config.wantAssertionsSigned) {
      await this.validateAssertionSignature(assertion);
    }

    // Extract attributes
    const attributes = this.extractAttributes(assertion);

    // Clear stored state
    await this.clearAuthState(relayState);

    const userId = attributes[this.config.attributeMapping.userId];
    const email = attributes[this.config.attributeMapping.email];
    const displayName = attributes[this.config.attributeMapping.displayName];

    if (!userId || !email) {
      throw new IdpError('AUTH_FAILED', 'Required attributes not found in SAML assertion');
    }

    return {
      success: true,
      externalId: userId,
      email,
      displayName,
      keyMaterial: {
        source: 'derived',
        value: await this.deriveKeyMaterial(assertion),
        requiresPassword: true,
        salt: await this.generateSalt(userId)
      },
      metadata: {
        sessionIndex: assertion.sessionIndex,
        nameId: assertion.nameId,
        nameIdFormat: assertion.nameIdFormat
      }
    };
  }

  private buildAuthnRequest(
    requestId: string,
    issueInstant: string,
    context: AuthContext
  ): string {
    return `<?xml version="1.0" encoding="UTF-8"?>
<samlp:AuthnRequest
    xmlns:samlp="urn:oasis:names:tc:SAML:2.0:protocol"
    xmlns:saml="urn:oasis:names:tc:SAML:2.0:assertion"
    ID="${requestId}"
    Version="2.0"
    IssueInstant="${issueInstant}"
    Destination="${this.config.ssoUrl}"
    AssertionConsumerServiceURL="${this.config.assertionConsumerServiceUrl}"
    ProtocolBinding="urn:oasis:names:tc:SAML:2.0:bindings:HTTP-POST">
    <saml:Issuer>${this.config.entityId}</saml:Issuer>
    <samlp:NameIDPolicy
        Format="urn:oasis:names:tc:SAML:1.1:nameid-format:${this.config.nameIdFormat}"
        AllowCreate="true"/>
</samlp:AuthnRequest>`;
  }

  private async validateSamlResponse(
    response: ParsedSamlResponse,
    expectedInResponseTo: string
  ): Promise<void> {
    // Check status
    if (response.status !== 'urn:oasis:names:tc:SAML:2.0:status:Success') {
      throw new IdpError('AUTH_FAILED', `SAML authentication failed: ${response.statusMessage}`);
    }

    // Check InResponseTo
    if (response.inResponseTo !== expectedInResponseTo) {
      throw new IdpError('AUTH_FAILED', 'Invalid InResponseTo');
    }

    // Check destination
    if (response.destination !== this.config.assertionConsumerServiceUrl) {
      throw new IdpError('AUTH_FAILED', 'Invalid Destination');
    }

    // Validate signature on response
    await this.validateResponseSignature(response);

    // Check timing
    const now = Date.now();
    if (response.notBefore && new Date(response.notBefore).getTime() > now) {
      throw new IdpError('AUTH_FAILED', 'Assertion not yet valid');
    }
    if (response.notOnOrAfter && new Date(response.notOnOrAfter).getTime() <= now) {
      throw new IdpError('AUTH_FAILED', 'Assertion expired');
    }

    // Check audience
    if (response.audience && response.audience !== this.config.entityId) {
      throw new IdpError('AUTH_FAILED', 'Invalid Audience');
    }
  }

  private async validateResponseSignature(response: ParsedSamlResponse): Promise<void> {
    if (!response.signature) {
      if (this.config.wantAssertionsSigned) {
        // Signature will be checked on assertion
        return;
      }
      throw new IdpError('AUTH_FAILED', 'Response is not signed');
    }

    const isValid = await verifySamlSignature(
      response.signedXml,
      response.signature,
      this.idpCertificate
    );

    if (!isValid) {
      throw new IdpError('AUTH_FAILED', 'Invalid response signature');
    }
  }

  private async validateAssertionSignature(assertion: SamlAssertion): Promise<void> {
    if (!assertion.signature) {
      throw new IdpError('AUTH_FAILED', 'Assertion is not signed');
    }

    const isValid = await verifySamlSignature(
      assertion.signedXml,
      assertion.signature,
      this.idpCertificate
    );

    if (!isValid) {
      throw new IdpError('AUTH_FAILED', 'Invalid assertion signature');
    }
  }

  private async decryptAssertion(encryptedAssertion: string): Promise<SamlAssertion> {
    if (!this.decryptionKey) {
      throw new IdpError('AUTH_FAILED', 'Encrypted assertion but no decryption key configured');
    }

    return await decryptSamlAssertion(encryptedAssertion, this.decryptionKey);
  }

  private extractAttributes(assertion: SamlAssertion): Record<string, string> {
    const attributes: Record<string, string> = {};

    for (const attr of assertion.attributes) {
      attributes[attr.name] = attr.value;
      if (attr.friendlyName) {
        attributes[attr.friendlyName] = attr.value;
      }
    }

    // Also include NameID
    if (assertion.nameId) {
      attributes['NameID'] = assertion.nameId;
    }

    return attributes;
  }

  private async deriveKeyMaterial(assertion: SamlAssertion): Promise<Uint8Array> {
    // Combine stable assertion properties for key material
    const material = JSON.stringify({
      issuer: assertion.issuer,
      nameId: assertion.nameId,
      sessionIndex: assertion.sessionIndex
    });

    return await sha256(material);
  }

  private async generateSalt(userId: string): Promise<Uint8Array> {
    return await sha256(`securesharing:${this.config.idpEntityId}:${userId}`);
  }

  async revokeAuth(sessionData: SamlSessionData): Promise<void> {
    if (!this.config.sloUrl) {
      return; // SLO not configured
    }

    // Build LogoutRequest
    const logoutRequest = this.buildLogoutRequest(sessionData);

    // Send logout request (similar to AuthnRequest)
    // Implementation depends on binding
  }

  async getUserProfile(sessionData: SamlSessionData): Promise<UserProfile> {
    // SAML doesn't have a userinfo endpoint like OIDC
    // Return cached data from assertion
    return {
      id: sessionData.nameId,
      email: sessionData.email,
      displayName: sessionData.displayName,
      verified: true  // SAML assertions are IdP-verified
    };
  }

  // Helper methods for signing
  private getSignatureAlgorithmUri(): string {
    const algorithms: Record<string, string> = {
      'RSA-SHA256': 'http://www.w3.org/2001/04/xmldsig-more#rsa-sha256',
      'RSA-SHA384': 'http://www.w3.org/2001/04/xmldsig-more#rsa-sha384',
      'RSA-SHA512': 'http://www.w3.org/2001/04/xmldsig-more#rsa-sha512'
    };
    return algorithms[this.config.signatureAlgorithm];
  }

  private async signRedirectBinding(url: URL): Promise<string> {
    const signData = [
      `SAMLRequest=${encodeURIComponent(url.searchParams.get('SAMLRequest')!)}`,
      `RelayState=${encodeURIComponent(url.searchParams.get('RelayState')!)}`,
      `SigAlg=${encodeURIComponent(this.getSignatureAlgorithmUri())}`
    ].join('&');

    return await signWithPrivateKey(signData, this.spPrivateKey!, this.config.signatureAlgorithm);
  }

  private async signPostBinding(request: string): Promise<string> {
    return await signXml(request, this.spPrivateKey!, this.config.signatureAlgorithm);
  }

  // State management
  private async storeAuthState(requestId: string, data: AuthStateData): Promise<void> {
    await authStateStore.set(requestId, data, 600000); // 10 minutes
  }

  private async getAuthState(requestId: string): Promise<AuthStateData | null> {
    return await authStateStore.get(requestId);
  }

  private async clearAuthState(requestId: string): Promise<void> {
    await authStateStore.delete(requestId);
  }
}
```

## 5. Client-Side Integration

### 5.1 Authentication Flow

```typescript
async function authenticateWithSaml(
  providerId: string,
  redirectUri: string
): Promise<void> {

  // Initiate authentication
  const response = await fetch('/api/v1/auth/saml/login', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({
      provider_id: providerId,
      redirect_uri: redirectUri
    })
  });

  const { data } = await response.json();

  if (data.binding === 'HTTP-Redirect') {
    // Redirect to IdP
    window.location.href = data.authorization_url;
  } else {
    // HTTP-POST binding - auto-submit form
    const form = document.createElement('form');
    form.method = 'POST';
    form.action = data.post_url;

    const samlInput = document.createElement('input');
    samlInput.type = 'hidden';
    samlInput.name = 'SAMLRequest';
    samlInput.value = data.saml_request;
    form.appendChild(samlInput);

    const relayInput = document.createElement('input');
    relayInput.type = 'hidden';
    relayInput.name = 'RelayState';
    relayInput.value = data.relay_state;
    form.appendChild(relayInput);

    document.body.appendChild(form);
    form.submit();
  }
}
```

### 5.2 ACS (Assertion Consumer Service) Handling

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

async function handleSamlCallback(
  samlResponse: string,
  relayState: string
): Promise<LoginResult> {

  // Send SAML response to server ACS endpoint
  // See docs/api/01-authentication.md Section 4.11
  const response = await fetch('/api/v1/auth/saml/acs', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({
      saml_response: samlResponse,
      relay_state: relayState
    })
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
  // SAML always requires vault password (no key material from IdP)
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
  keyMaterial: Uint8Array,  // SHA-256(issuer + nameId + sessionIndex)
  salt: Uint8Array,         // SHA-256(idpEntityId + userId)[0:16]
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

## 6. Key Material Derivation

**Canonical Specification**: See [docs/crypto/02-key-hierarchy.md](../crypto/02-key-hierarchy.md) Section 3.1 for the authoritative key derivation specification.

### 6.1 Derivation Process

```
+-----------------------------------------------------------------------------+
|                    SAML KEY DERIVATION                                       |
+-----------------------------------------------------------------------------+
|                                                                              |
|  SAML Assertion                           Vault Password                     |
|  (issuer, nameId, sessionIndex)                 |                            |
|         |                                       |                            |
|         | SHA-256                               |                            |
|         v                                       |                            |
|  +-------------+                                |                            |
|  | IdP Binding |                                |                            |
|  |  Material   |                                |                            |
|  | (32 bytes)  |                                |                            |
|  +------+------+                                |                            |
|         |                                       |                            |
|         |            Salt = SHA-256(idpEntityId + userId)[0:16]              |
|         |                     |                                              |
|         |                     v                                              |
|         |              +-------------+                                       |
|         |              |    Salt     |----------+                            |
|         |              | (16 bytes)  |          |                            |
|         |              +-------------+          | Argon2id                   |
|         |                                       v                            |
|         |                                +-------------+                     |
|         |                                |  Password   |                     |
|         |                                |    Key      |                     |
|         |                                | (32 bytes)  |                     |
|         |                                +------+------+                     |
|         |                                       |                            |
|         +---------------+---------------+-------+                            |
|                         | Concatenate (NOT XOR)                              |
|                         v                                                    |
|                  +-------------+                                             |
|                  |  Combined   |                                             |
|                  |  Material   |                                             |
|                  | (64 bytes)  |                                             |
|                  +------+------+                                             |
|                         |                                                    |
|                         | HKDF-SHA-384                                       |
|                         | salt = "SecureSharing-MasterKey-v1"                |
|                         | info = "mk-encryption-key"                         |
|                         v                                                    |
|                  +-------------+                                             |
|                  | Encryption  |                                             |
|                  |    Key      |                                             |
|                  | (32 bytes)  |                                             |
|                  +-------------+                                             |
|                                                                              |
|  Why vault password is required:                                             |
|  - SAML assertions don't provide secret key material                         |
|  - Assertion attributes are not secret (visible in SAML response)            |
|  - Vault password adds user-specific entropy                                 |
|  - Combined derivation prevents offline attacks                              |
|                                                                              |
+-----------------------------------------------------------------------------+
```

## 7. SP Metadata

### 7.1 Metadata Endpoint

SecureSharing exposes SP metadata for easy IdP configuration:

```http
GET /auth/saml/metadata
X-Tenant-ID: acme-corp
```

**Response** `200 OK`:
```xml
<?xml version="1.0" encoding="UTF-8"?>
<md:EntityDescriptor
    xmlns:md="urn:oasis:names:tc:SAML:2.0:metadata"
    entityID="https://securesharing.com/saml/metadata">
    <md:SPSSODescriptor
        AuthnRequestsSigned="true"
        WantAssertionsSigned="true"
        protocolSupportEnumeration="urn:oasis:names:tc:SAML:2.0:protocol">
        <md:KeyDescriptor use="signing">
            <ds:KeyInfo xmlns:ds="http://www.w3.org/2000/09/xmldsig#">
                <ds:X509Data>
                    <ds:X509Certificate>...</ds:X509Certificate>
                </ds:X509Data>
            </ds:KeyInfo>
        </md:KeyDescriptor>
        <md:NameIDFormat>urn:oasis:names:tc:SAML:1.1:nameid-format:emailAddress</md:NameIDFormat>
        <md:AssertionConsumerService
            Binding="urn:oasis:names:tc:SAML:2.0:bindings:HTTP-POST"
            Location="https://api.securesharing.com/v1/auth/saml/acs"
            index="0"
            isDefault="true"/>
    </md:SPSSODescriptor>
</md:EntityDescriptor>
```

## 8. Error Handling

| SAML Status Code | Error | User Message |
|------------------|-------|--------------|
| `urn:oasis:names:tc:SAML:2.0:status:Requester` | invalid_request | "Invalid authentication request" |
| `urn:oasis:names:tc:SAML:2.0:status:Responder` | idp_error | "Identity provider error" |
| `urn:oasis:names:tc:SAML:2.0:status:AuthnFailed` | auth_failed | "Authentication failed" |
| `urn:oasis:names:tc:SAML:2.0:status:NoPassive` | no_passive | "Passive authentication not possible" |
| `urn:oasis:names:tc:SAML:2.0:status:UnknownPrincipal` | unknown_user | "User not found" |
| Signature validation failed | invalid_signature | "Invalid response signature" |
| Assertion expired | assertion_expired | "Session expired, please try again" |
| Missing required attributes | missing_attributes | "Required user information not provided" |

## 9. Security Considerations

### 9.1 Signature Validation

- Always validate SAML response signatures
- Always validate SAML assertion signatures when configured
- Use strong signature algorithms (SHA-256 or higher)
- Validate certificate chain if using PKI

### 9.2 Replay Prevention

- Validate `InResponseTo` matches the original request ID
- Check `NotBefore` and `NotOnOrAfter` conditions
- Store and check assertion IDs to prevent replay

### 9.3 XML Security

- Use secure XML parsers that prevent XXE attacks
- Validate XML schema compliance
- Canonicalize XML before signature validation

### 9.4 Vault Password

- Required for all SAML flows
- Minimum strength requirements enforced
- Combined with IdP material for key derivation
- Never transmitted to server

### 9.5 Transport Security

- All SAML endpoints require HTTPS
- Certificate validation enabled
- HSTS headers enforced
