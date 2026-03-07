# Authentication API

**Version**: 1.1.0
**Status**: Draft
**Last Updated**: 2026-01

## 1. Overview

Authentication in SecureSharing is handled through pluggable identity providers. The server verifies identity but never has access to encryption keys.

**Base URL**: `https://api.securesharing.com/v1`

## 2. Tenant Resolution

Requests must identify the tenant context. The following methods are supported (in order of precedence):

| Method | Format | Example | Use Case |
|--------|--------|---------|----------|
| Subdomain | `{slug}.securesharing.com` | `acme-corp.securesharing.com` | Production apps |
| Header | `X-Tenant-ID: {id or slug}` | `X-Tenant-ID: acme-corp` | API clients, development |
| JWT Claim | `tid` in token payload | - | Authenticated requests |

**Resolution Order**:
1. For **authenticated requests**: Tenant is extracted from JWT `tid` claim
2. For **unauthenticated requests**: Use subdomain or `X-Tenant-ID` header

> **Note**: Query parameter `?tenant=` is deprecated. Use the header instead.

## 3. Authentication Flow

```
┌────────────────────────────────────────────────────────────────┐
│                    AUTHENTICATION FLOW                          │
├────────────────────────────────────────────────────────────────┤
│                                                                 │
│  1. Client initiates auth with IdP (get challenge/redirect)    │
│  2. User authenticates with IdP (WebAuthn/OIDC/SAML)           │
│  3. Client submits IdP response to login/complete endpoint     │
│  4. Server validates and returns session + key bundle directly │
│  5. Client derives keys locally (never sent to server)         │
│                                                                 │
│  NOTE: No separate "auth token → session token" exchange.      │
│  The login completion endpoint returns everything in one call. │
│                                                                 │
└────────────────────────────────────────────────────────────────┘
```

## 4. Endpoints

### 4.1 Get Available Identity Providers

Returns the list of configured identity providers for a tenant.

```http
GET /auth/providers
X-Tenant-ID: acme-corp
```

**Headers**:
| Header | Required | Description |
|--------|----------|-------------|
| `X-Tenant-ID` | Yes* | Tenant slug or ID (*not required if using subdomain) |

**Response** `200 OK`:
```json
{
  "success": true,
  "data": {
    "providers": [
      {
        "id": "550e8400-e29b-41d4-a716-446655440000",
        "type": "webauthn",
        "name": "Passkey",
        "enabled": true,
        "priority": 1
      },
      {
        "id": "660e8400-e29b-41d4-a716-446655440001",
        "type": "oidc",
        "name": "Company SSO",
        "enabled": true,
        "priority": 2,
        "login_url": "https://api.securesharing.com/v1/auth/oidc/660e8400/login"
      }
    ]
  }
}
```

---

### 4.2 WebAuthn Registration Options

Get options for registering a new passkey.

```http
POST /auth/webauthn/register/options
```

**Request Body**:
```json
{
  "tenant_id": "550e8400-e29b-41d4-a716-446655440000",
  "email": "user@example.com",
  "display_name": "John Doe"
}
```

**Response** `200 OK`:
```json
{
  "success": true,
  "data": {
    "challenge": "base64...",
    "rp": {
      "name": "SecureSharing",
      "id": "securesharing.com"
    },
    "user": {
      "id": "base64...",
      "name": "user@example.com",
      "displayName": "John Doe"
    },
    "pubKeyCredParams": [
      {"type": "public-key", "alg": -7},
      {"type": "public-key", "alg": -257}
    ],
    "authenticatorSelection": {
      "authenticatorAttachment": "platform",
      "residentKey": "required",
      "userVerification": "required"
    },
    "timeout": 300000,
    "attestation": "none",
    "extensions": {
      "prf": {}
    }
  }
}
```

---

### 4.3 WebAuthn Registration Complete

Complete passkey registration with credential and user keys.

```http
POST /auth/webauthn/register/complete
```

**Request Body**:
```json
{
  "tenant_id": "550e8400-e29b-41d4-a716-446655440000",
  "credential": {
    "id": "base64url...",
    "rawId": "base64url...",
    "type": "public-key",
    "response": {
      "clientDataJSON": "base64url...",
      "attestationObject": "base64url..."
    },
    "clientExtensionResults": {
      "prf": {
        "enabled": true
      }
    }
  },
  "user_registration": {
    "email": "user@example.com",
    "display_name": "John Doe",
    "public_keys": {
      "ml_kem": "base64...",
      "ml_dsa": "base64...",
      "kaz_kem": "base64...",
      "kaz_sign": "base64..."
    },
    "encrypted_master_key": "base64...",
    "mk_nonce": "base64...",
    "encrypted_private_keys": {
      "ml_kem": {"ciphertext": "base64...", "nonce": "base64..."},
      "ml_dsa": {"ciphertext": "base64...", "nonce": "base64..."},
      "kaz_kem": {"ciphertext": "base64...", "nonce": "base64..."},
      "kaz_sign": {"ciphertext": "base64...", "nonce": "base64..."}
    }
  },
  "root_folder": {
    "encrypted_metadata": "base64...",
    "metadata_nonce": "base64...",
    "owner_key_access": {
      "wrapped_kek": "base64...",
      "kem_ciphertexts": [
        {"algorithm": "ML-KEM-768", "ciphertext": "base64..."},
        {"algorithm": "KAZ-KEM", "ciphertext": "base64..."}
      ]
    },
    "created_at": "2025-01-15T10:30:00.000Z",
    "signature": {
      "ml_dsa": "base64...",
      "kaz_sign": "base64..."
    }
  }
}
```

**Root Folder Fields**:
| Field | Type | Description |
|-------|------|-------------|
| `encrypted_metadata` | Base64 | Encrypted folder metadata (name, etc.) |
| `metadata_nonce` | Base64 | 12-byte nonce for metadata encryption |
| `owner_key_access` | object | Root KEK encapsulated for owner |
| `created_at` | ISO8601 | Client timestamp (included in signature) |
| `signature` | object | Owner's signature over folder creation |

> **Note**: Root folder has no `parent_id` or `wrapped_kek` (it's the top of the hierarchy).
> The KEK is only accessible via `owner_key_access` encapsulation.
> See [Signature Protocol](../crypto/05-signature-protocol.md) Section 4.4 for signature payload.

**Response** `201 Created`:
```json
{
  "success": true,
  "data": {
    "user": {
      "id": "770e8400-e29b-41d4-a716-446655440002",
      "email": "user@example.com",
      "display_name": "John Doe",
      "status": "active"
    },
    "root_folder": {
      "id": "880e8400-e29b-41d4-a716-446655440003"
    },
    "session": {
      "token": "eyJhbGciOiJFZERTQSIs...",
      "expires_at": "2025-01-15T22:30:00.000Z"
    }
  }
}
```

---

### 4.4 WebAuthn Login Options

Get options for authenticating with passkey.

```http
POST /auth/webauthn/login/options
```

**Request Body**:
```json
{
  "tenant_id": "550e8400-e29b-41d4-a716-446655440000",
  "email": "user@example.com"
}
```

**Response** `200 OK`:
```json
{
  "success": true,
  "data": {
    "challenge": "base64...",
    "rpId": "securesharing.com",
    "timeout": 300000,
    "userVerification": "required",
    "allowCredentials": [
      {
        "type": "public-key",
        "id": "base64url..."
      }
    ],
    "extensions": {
      "prf": {
        "eval": {
          "first": "base64..."
        }
      }
    }
  }
}
```

---

### 4.5 WebAuthn Login Complete

Complete passkey authentication.

```http
POST /auth/webauthn/login/complete
```

**Request Body**:
```json
{
  "tenant_id": "550e8400-e29b-41d4-a716-446655440000",
  "credential": {
    "id": "base64url...",
    "rawId": "base64url...",
    "type": "public-key",
    "response": {
      "clientDataJSON": "base64url...",
      "authenticatorData": "base64url...",
      "signature": "base64url...",
      "userHandle": "base64url..."
    },
    "clientExtensionResults": {
      "prf": {
        "results": {
          "first": "base64..."
        }
      }
    }
  }
}
```

**Response** `200 OK`:
```json
{
  "success": true,
  "data": {
    "user": {
      "id": "770e8400-e29b-41d4-a716-446655440002",
      "email": "user@example.com",
      "display_name": "John Doe",
      "status": "active",
      "role": "member"
    },
    "session": {
      "token": "eyJhbGciOiJFZERTQSIs...",
      "expires_at": "2025-01-15T22:30:00.000Z"
    },
    "key_bundle": {
      "encrypted_master_key": "base64...",
      "mk_nonce": "base64...",
      "public_keys": {
        "ml_kem": "base64...",
        "ml_dsa": "base64...",
        "kaz_kem": "base64...",
        "kaz_sign": "base64..."
      },
      "encrypted_private_keys": {
        "ml_kem": {"ciphertext": "base64...", "nonce": "base64..."},
        "ml_dsa": {"ciphertext": "base64...", "nonce": "base64..."},
        "kaz_kem": {"ciphertext": "base64...", "nonce": "base64..."},
        "kaz_sign": {"ciphertext": "base64...", "nonce": "base64..."}
      }
    }
  }
}
```

---

### 4.6 OIDC Login Initiate

Redirect to OIDC provider for authentication.

```http
GET /auth/oidc/{provider_id}/login
```

**Query Parameters**:
| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `redirect_uri` | string | Yes | Where to redirect after auth |
| `state` | string | Yes | CSRF protection state |

**Response** `302 Found`:
```
Location: https://idp.example.com/authorize?client_id=...&redirect_uri=...&state=...
```

---

### 4.7 OIDC Callback

Handle OIDC callback after provider authentication.

```http
POST /auth/oidc/{provider_id}/callback
```

**Request Body**:
```json
{
  "code": "authorization_code_from_idp",
  "state": "original_state_value"
}
```

**Response for Existing User** `200 OK`:
```json
{
  "success": true,
  "data": {
    "status": "existing_user",
    "user": { /* user object */ },
    "session": { /* session object */ },
    "key_bundle": { /* encrypted keys */ }
  }
}
```

**Response for New User** `200 OK`:
```json
{
  "success": true,
  "data": {
    "status": "new_user",
    "registration_token": "temp_token_for_registration",
    "user_info": {
      "email": "user@example.com",
      "name": "John Doe",
      "external_id": "idp_user_id"
    }
  }
}
```

---

### 4.8 Complete OIDC Registration

Complete registration for new OIDC user (requires vault password).

```http
POST /auth/oidc/register/complete
```

**Request Body**:
```json
{
  "registration_token": "temp_token_from_callback",
  "vault_password_salt": "base64...",
  "user_registration": {
    "display_name": "John Doe",
    "public_keys": {
      "ml_kem": "base64...",
      "ml_dsa": "base64...",
      "kaz_kem": "base64...",
      "kaz_sign": "base64..."
    },
    "encrypted_master_key": "base64...",
    "mk_nonce": "base64...",
    "encrypted_private_keys": {
      "ml_kem": {"ciphertext": "base64...", "nonce": "base64..."},
      "ml_dsa": {"ciphertext": "base64...", "nonce": "base64..."},
      "kaz_kem": {"ciphertext": "base64...", "nonce": "base64..."},
      "kaz_sign": {"ciphertext": "base64...", "nonce": "base64..."}
    }
  },
  "root_folder": {
    "encrypted_metadata": "base64...",
    "metadata_nonce": "base64...",
    "owner_key_access": {
      "wrapped_kek": "base64...",
      "kem_ciphertexts": [
        {"algorithm": "ML-KEM-768", "ciphertext": "base64..."},
        {"algorithm": "KAZ-KEM", "ciphertext": "base64..."}
      ]
    },
    "created_at": "2025-01-15T10:30:00.000Z",
    "signature": {
      "ml_dsa": "base64...",
      "kaz_sign": "base64..."
    }
  }
}
```

> **Note**: See WebAuthn registration (Section 4.3) for `root_folder` field descriptions.

**Response** `201 Created`:
```json
{
  "success": true,
  "data": {
    "user": {
      "id": "770e8400-e29b-41d4-a716-446655440002",
      "email": "user@example.com",
      "display_name": "John Doe",
      "status": "active"
    },
    "root_folder": {
      "id": "880e8400-e29b-41d4-a716-446655440003"
    },
    "session": {
      "token": "eyJhbGciOiJFZERTQSIs...",
      "expires_at": "2025-01-15T22:30:00.000Z"
    }
  }
}
```

---

### 4.9 SAML SP Metadata

Get SAML Service Provider metadata for IdP configuration.

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
        <md:NameIDFormat>urn:oasis:names:tc:SAML:1.1:nameid-format:emailAddress</md:NameIDFormat>
        <md:AssertionConsumerService
            Binding="urn:oasis:names:tc:SAML:2.0:bindings:HTTP-POST"
            Location="https://api.securesharing.com/v1/auth/saml/acs"
            index="0"
            isDefault="true"/>
    </md:SPSSODescriptor>
</md:EntityDescriptor>
```

---

### 4.10 SAML Login Initiate

Initiate SAML authentication flow.

```http
POST /auth/saml/{provider_id}/login
```

**Request Body**:
```json
{
  "redirect_uri": "https://app.securesharing.com/auth/callback"
}
```

**Response for HTTP-Redirect binding** `200 OK`:
```json
{
  "success": true,
  "data": {
    "binding": "HTTP-Redirect",
    "authorization_url": "https://idp.example.com/saml/sso?SAMLRequest=...&RelayState=..."
  }
}
```

**Response for HTTP-POST binding** `200 OK`:
```json
{
  "success": true,
  "data": {
    "binding": "HTTP-POST",
    "post_url": "https://idp.example.com/saml/sso",
    "saml_request": "base64...",
    "relay_state": "request_id"
  }
}
```

---

### 4.11 SAML Assertion Consumer Service (ACS)

Handle SAML response from IdP after authentication.

```http
POST /auth/saml/acs
Content-Type: application/x-www-form-urlencoded
```

**Request Body** (form-encoded):
```
SAMLResponse=base64...&RelayState=request_id
```

**Alternative JSON Request Body**:
```json
{
  "saml_response": "base64...",
  "relay_state": "request_id"
}
```

**Response for Existing User** `200 OK`:
```json
{
  "success": true,
  "data": {
    "status": "existing_user",
    "user": {
      "id": "770e8400-e29b-41d4-a716-446655440002",
      "email": "user@example.com",
      "display_name": "John Doe"
    },
    "session": {
      "token": "eyJhbGciOiJFZERTQSIs...",
      "expires_at": "2025-01-15T22:30:00.000Z"
    },
    "key_bundle": { /* encrypted keys */ },
    "key_material": "base64...",
    "key_salt": "base64..."
  }
}
```

**Response for New User** `200 OK`:
```json
{
  "success": true,
  "data": {
    "status": "new_user",
    "flow": "registration",
    "registration_token": "temp_token_for_registration",
    "user_info": {
      "email": "user@example.com",
      "name": "John Doe",
      "external_id": "saml_name_id"
    },
    "key_material": "base64...",
    "key_salt": "base64..."
  }
}
```

---

### 4.12 Complete SAML Registration

Complete registration for new SAML user (requires vault password).

```http
POST /auth/saml/register/complete
```

**Request Body**:
```json
{
  "registration_token": "temp_token_from_acs",
  "vault_password_salt": "base64...",
  "user_registration": {
    "display_name": "John Doe",
    "public_keys": {
      "ml_kem": "base64...",
      "ml_dsa": "base64...",
      "kaz_kem": "base64...",
      "kaz_sign": "base64..."
    },
    "encrypted_master_key": "base64...",
    "mk_nonce": "base64...",
    "encrypted_private_keys": {
      "ml_kem": {"ciphertext": "base64...", "nonce": "base64..."},
      "ml_dsa": {"ciphertext": "base64...", "nonce": "base64..."},
      "kaz_kem": {"ciphertext": "base64...", "nonce": "base64..."},
      "kaz_sign": {"ciphertext": "base64...", "nonce": "base64..."}
    }
  }
}
```

**Response** `201 Created`:
```json
{
  "success": true,
  "data": {
    "user": {
      "id": "770e8400-e29b-41d4-a716-446655440002",
      "email": "user@example.com",
      "display_name": "John Doe",
      "status": "active"
    },
    "session": {
      "token": "eyJhbGciOiJFZERTQSIs...",
      "expires_at": "2025-01-15T22:30:00.000Z"
    }
  }
}
```

---

### 4.13 Digital ID Login Initiate

Initiate Digital ID authentication. Supports multiple authentication modes: redirect, QR code, or deep link.

```http
POST /auth/digital-id/{provider_id}/authorize
Content-Type: application/json
```

**Request Body**:
```json
{
  "redirect_uri": "https://app.example.com/auth/callback",
  "mode": "qr"
}
```

**Request Fields**:
| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `redirect_uri` | string | Yes | Where to redirect after auth |
| `mode` | string | No | `redirect`, `qr`, or `deep_link` (default: `redirect`) |

**Response** `200 OK`:
```json
{
  "success": true,
  "data": {
    "session_id": "did-session-abc123",
    "authorization_url": "https://mydigital.gov.my/auth?...",
    "qr_code_data": "mydigital://auth?session=abc123&...",
    "deep_link": "mydigital://auth?session=abc123&...",
    "expires_at": "2025-01-15T10:35:00.000Z"
  }
}
```

**Response Fields**:
| Field | Type | Description |
|-------|------|-------------|
| `session_id` | string | Session ID for polling (QR/deep link modes) |
| `authorization_url` | string | URL for redirect mode |
| `qr_code_data` | string | Data to encode as QR code (QR mode) |
| `deep_link` | string | Deep link URL for mobile (deep link mode) |
| `expires_at` | ISO8601 | When the auth session expires |

---

### 4.14 Digital ID Auth Status (Polling)

Poll for authentication status when using QR code or deep link modes.

```http
GET /auth/digital-id/status/{session_id}
```

**Response** `200 OK` (pending):
```json
{
  "success": true,
  "data": {
    "status": "pending",
    "message": "Waiting for user to complete authentication"
  }
}
```

**Response** `200 OK` (completed - existing user):
```json
{
  "success": true,
  "data": {
    "status": "completed",
    "result": {
      "type": "existing_user",
      "user": {
        "id": "770e8400-e29b-41d4-a716-446655440002",
        "email": "user@example.com",
        "display_name": "John Doe"
      },
      "session": {
        "token": "eyJhbGciOiJFZERTQSIs...",
        "expires_at": "2025-01-15T22:30:00.000Z"
      },
      "key_bundle": {
        "vault_encrypted_master_key": "base64...",
        "vault_mk_nonce": "base64...",
        "vault_salt": "base64...",
        "public_keys": { /* ... */ },
        "encrypted_private_keys": { /* ... */ }
      }
    }
  }
}
```

**Response** `200 OK` (completed - new user):
```json
{
  "success": true,
  "data": {
    "status": "completed",
    "result": {
      "type": "new_user",
      "registration_token": "temp_token_for_registration",
      "user_info": {
        "email": "user@example.com",
        "name": "John Doe",
        "external_id": "mydigital_user_id"
      },
      "key_material": "base64...",
      "key_salt": "base64..."
    }
  }
}
```

**Response** `200 OK` (failed):
```json
{
  "success": true,
  "data": {
    "status": "failed",
    "error": "E_AUTH_TIMEOUT",
    "message": "Authentication session expired"
  }
}
```

**Status Values**:
| Status | Description |
|--------|-------------|
| `pending` | Waiting for user to authenticate |
| `completed` | Authentication successful |
| `failed` | Authentication failed or timed out |

---

### 4.15 Digital ID Callback

Handle Digital ID callback after provider authentication. Used for redirect mode or direct callbacks.

```http
POST /auth/digital-id/{provider_id}/callback
Content-Type: application/json
```

**Request Body**:
```json
{
  "code": "authorization_code_from_idp",
  "state": "original_state_value"
}
```

**Response for Existing User** `200 OK`:
```json
{
  "success": true,
  "data": {
    "status": "existing_user",
    "user": {
      "id": "770e8400-e29b-41d4-a716-446655440002",
      "email": "user@example.com",
      "display_name": "John Doe"
    },
    "session": {
      "token": "eyJhbGciOiJFZERTQSIs...",
      "expires_at": "2025-01-15T22:30:00.000Z"
    },
    "key_bundle": {
      "vault_encrypted_master_key": "base64...",
      "vault_mk_nonce": "base64...",
      "vault_salt": "base64...",
      "public_keys": { /* ... */ },
      "encrypted_private_keys": { /* ... */ }
    }
  }
}
```

**Response for New User** `200 OK`:
```json
{
  "success": true,
  "data": {
    "status": "new_user",
    "registration_token": "temp_token_for_registration",
    "user_info": {
      "email": "user@example.com",
      "name": "John Doe",
      "external_id": "mydigital_user_id"
    },
    "key_material": "base64...",
    "key_salt": "base64..."
  }
}
```

> **Note**: `key_material` and `key_salt` are provided for key derivation. For Digital ID with `provides_key_material=true`, client derives encryption key from certificate. For `provides_key_material=false`, client uses vault password.

---

### 4.16 Complete Digital ID Registration

Complete registration for new Digital ID user.

```http
POST /auth/digital-id/register/complete
Content-Type: application/json
```

**Request Body** (with vault password - `provides_key_material=false`):
```json
{
  "registration_token": "temp_token_from_callback",
  "vault_password_salt": "base64...",
  "user_registration": {
    "display_name": "John Doe",
    "public_keys": {
      "ml_kem": "base64...",
      "ml_dsa": "base64...",
      "kaz_kem": "base64...",
      "kaz_sign": "base64..."
    },
    "vault_encrypted_master_key": "base64...",
    "vault_mk_nonce": "base64...",
    "encrypted_private_keys": {
      "ml_kem": {"ciphertext": "base64...", "nonce": "base64..."},
      "ml_dsa": {"ciphertext": "base64...", "nonce": "base64..."},
      "kaz_kem": {"ciphertext": "base64...", "nonce": "base64..."},
      "kaz_sign": {"ciphertext": "base64...", "nonce": "base64..."}
    }
  }
}
```

**Request Body** (with key material - `provides_key_material=true`):
```json
{
  "registration_token": "temp_token_from_callback",
  "user_registration": {
    "display_name": "John Doe",
    "public_keys": {
      "ml_kem": "base64...",
      "ml_dsa": "base64...",
      "kaz_kem": "base64...",
      "kaz_sign": "base64..."
    },
    "encrypted_private_keys": {
      "ml_kem": {"ciphertext": "base64...", "nonce": "base64..."},
      "ml_dsa": {"ciphertext": "base64...", "nonce": "base64..."},
      "kaz_kem": {"ciphertext": "base64...", "nonce": "base64..."},
      "kaz_sign": {"ciphertext": "base64...", "nonce": "base64..."}
    }
  },
  "credential": {
    "encrypted_master_key": "base64...",
    "mk_nonce": "base64..."
  }
}
```

> **Note**: When `IdpConfig.provides_key_material=true`, MK is stored in credential (no vault). When `false`, MK is stored in user's vault fields.

**Response** `201 Created`:
```json
{
  "success": true,
  "data": {
    "user": {
      "id": "770e8400-e29b-41d4-a716-446655440002",
      "email": "user@example.com",
      "display_name": "John Doe",
      "status": "active"
    },
    "session": {
      "token": "eyJhbGciOiJFZERTQSIs...",
      "expires_at": "2025-01-15T22:30:00.000Z"
    }
  }
}
```

---

### 4.17 Refresh Session

Refresh an expiring session token.

```http
POST /auth/session/refresh
Authorization: Bearer <current_token>
```

**Response** `200 OK`:
```json
{
  "success": true,
  "data": {
    "session": {
      "token": "eyJhbGciOiJFZERTQSIs...",
      "expires_at": "2025-01-16T10:30:00.000Z"
    }
  }
}
```

---

### 4.18 Logout

Invalidate current session.

```http
POST /auth/logout
Authorization: Bearer <token>
```

**Response** `200 OK`:
```json
{
  "success": true,
  "data": {
    "message": "Session invalidated"
  }
}
```

---

### 4.19 Get Current User

Get authenticated user's profile and key bundle.

```http
GET /auth/me
Authorization: Bearer <token>
```

**Response** `200 OK`:
```json
{
  "success": true,
  "data": {
    "user": {
      "id": "770e8400-e29b-41d4-a716-446655440002",
      "tenant_id": "550e8400-e29b-41d4-a716-446655440000",
      "email": "user@example.com",
      "display_name": "John Doe",
      "status": "active",
      "role": "member",
      "recovery_setup_complete": true,
      "created_at": "2025-01-01T00:00:00.000Z"
    },
    "tenant": {
      "id": "550e8400-e29b-41d4-a716-446655440000",
      "name": "Acme Corp",
      "slug": "acme-corp",
      "plan": "enterprise"
    },
    "key_bundle": {
      "public_keys": { /* ... */ },
      "encrypted_master_key": "base64...",
      "mk_nonce": "base64...",
      "encrypted_private_keys": { /* ... */ }
    }
  }
}
```

## 5. Credential Management

Endpoints for managing user authentication credentials (passkeys, SSO links).

### 5.1 List Credentials

List all credentials for the authenticated user.

```http
GET /auth/credentials
Authorization: Bearer <token>
```

**Response** `200 OK`:
```json
{
  "success": true,
  "data": {
    "credentials": [
      {
        "id": "880e8400-e29b-41d4-a716-446655440003",
        "type": "webauthn",
        "display_name": "MacBook Pro Passkey",
        "last_used_at": "2025-01-14T10:30:00.000Z",
        "created_at": "2025-01-01T00:00:00.000Z"
      },
      {
        "id": "990e8400-e29b-41d4-a716-446655440004",
        "type": "webauthn",
        "display_name": "iPhone Passkey",
        "last_used_at": "2025-01-13T15:00:00.000Z",
        "created_at": "2025-01-05T00:00:00.000Z"
      },
      {
        "id": "aa0e8400-e29b-41d4-a716-446655440005",
        "type": "saml",
        "display_name": "Acme Corp SSO",
        "idp_config": {
          "id": "bb0e8400-e29b-41d4-a716-446655440006",
          "name": "Acme Corp SSO",
          "type": "saml"
        },
        "last_used_at": "2025-01-10T09:00:00.000Z",
        "created_at": "2025-01-02T00:00:00.000Z"
      },
      {
        "id": "cc0e8400-e29b-41d4-a716-446655440007",
        "type": "digital_id",
        "display_name": "MyDigital ID",
        "idp_config": {
          "id": "dd0e8400-e29b-41d4-a716-446655440008",
          "name": "MyDigital ID",
          "type": "digital_id"
        },
        "last_used_at": null,
        "created_at": "2025-01-08T00:00:00.000Z"
      }
    ]
  }
}
```

**Response Fields**:
| Field | Type | Description |
|-------|------|-------------|
| `id` | UUID | Credential ID |
| `type` | string | `webauthn`, `oidc`, `saml`, or `digital_id` |
| `display_name` | string | For passkeys: `device_name`. For federated: `IdpConfig.name` |
| `idp_config` | object | Present for federated credentials (OIDC, SAML, Digital ID) |
| `last_used_at` | ISO8601 | Last authentication time (null if never used) |
| `created_at` | ISO8601 | When credential was added |

> **UI Note**: Display `display_name` to users rather than `type`. Users don't need to know the underlying protocol (OIDC vs SAML).

---

### 5.2 Get Credential Details

Get details for a specific credential.

```http
GET /auth/credentials/{credential_id}
Authorization: Bearer <token>
```

**Response** `200 OK`:
```json
{
  "success": true,
  "data": {
    "id": "880e8400-e29b-41d4-a716-446655440003",
    "type": "webauthn",
    "display_name": "MacBook Pro Passkey",
    "transports": ["internal", "hybrid"],
    "last_used_at": "2025-01-14T10:30:00.000Z",
    "created_at": "2025-01-01T00:00:00.000Z"
  }
}
```

---

### 5.3 Update Credential Name

Update a credential's display name (for passkeys).

```http
PATCH /auth/credentials/{credential_id}
Authorization: Bearer <token>
Content-Type: application/json
```

**Request Body**:
```json
{
  "display_name": "Work MacBook"
}
```

**Response** `200 OK`:
```json
{
  "success": true,
  "data": {
    "id": "880e8400-e29b-41d4-a716-446655440003",
    "display_name": "Work MacBook",
    "updated_at": "2025-01-15T10:30:00.000Z"
  }
}
```

> **Note**: Only `display_name` can be updated. For federated credentials, this field is derived from `IdpConfig.name` and cannot be changed.

---

### 5.4 Add Passkey

Add an additional passkey to the user's account. User must already be authenticated.

```http
POST /auth/credentials/passkey/options
Authorization: Bearer <token>
```

**Response** `200 OK`:
```json
{
  "success": true,
  "data": {
    "challenge": "base64url...",
    "rp": {
      "id": "securesharing.com",
      "name": "SecureSharing"
    },
    "user": {
      "id": "base64url...",
      "name": "user@example.com",
      "displayName": "John Doe"
    },
    "pubKeyCredParams": [
      { "type": "public-key", "alg": -7 },
      { "type": "public-key", "alg": -257 }
    ],
    "timeout": 60000,
    "attestation": "none",
    "authenticatorSelection": {
      "residentKey": "required",
      "userVerification": "required"
    },
    "excludeCredentials": [
      {
        "type": "public-key",
        "id": "base64url...",
        "transports": ["internal", "hybrid"]
      }
    ]
  }
}
```

---

### 5.5 Complete Add Passkey

Complete passkey registration with attestation response.

```http
POST /auth/credentials/passkey/complete
Authorization: Bearer <token>
Content-Type: application/json
```

**Request Body**:
```json
{
  "credential": {
    "id": "base64url...",
    "rawId": "base64url...",
    "type": "public-key",
    "response": {
      "clientDataJSON": "base64url...",
      "attestationObject": "base64url..."
    },
    "authenticatorAttachment": "platform"
  },
  "device_name": "iPhone 15 Pro",
  "encrypted_master_key": "base64...",
  "mk_nonce": "base64..."
}
```

**Request Fields**:
| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `credential` | object | Yes | WebAuthn attestation response |
| `device_name` | string | No | User-friendly name for passkey |
| `encrypted_master_key` | Base64 | Yes | MK encrypted with new passkey's PRF output |
| `mk_nonce` | Base64 | Yes | Nonce for MK encryption |

> **Important**: Client must decrypt MK using current credential, then re-encrypt with new passkey's PRF output.

**Response** `201 Created`:
```json
{
  "success": true,
  "data": {
    "id": "ee0e8400-e29b-41d4-a716-446655440009",
    "type": "webauthn",
    "display_name": "iPhone 15 Pro",
    "created_at": "2025-01-15T10:30:00.000Z"
  }
}
```

---

### 5.6 Remove Credential

Remove a credential from the user's account.

```http
DELETE /auth/credentials/{credential_id}
Authorization: Bearer <token>
```

**Validation Rules**:
- Cannot remove the last credential (user would be locked out)
- Cannot remove the only credential with key material if vault is not set up
- Cannot remove credential currently being used for this session

**Response** `200 OK`:
```json
{
  "success": true,
  "data": {
    "message": "Credential removed",
    "removed_at": "2025-01-15T10:30:00.000Z"
  }
}
```

**Response** `400 Bad Request` (last credential):
```json
{
  "success": false,
  "error": {
    "code": "E_LAST_CREDENTIAL",
    "message": "Cannot remove your only sign-in method"
  }
}
```

---

### 5.7 Setup Vault Password

Set up vault password for OIDC/SAML/Digital ID credentials. Required when adding a federated credential to a WebAuthn-only user.

```http
POST /auth/vault/setup
Authorization: Bearer <token>
Content-Type: application/json
```

**Request Body**:
```json
{
  "vault_encrypted_master_key": "base64...",
  "vault_mk_nonce": "base64...",
  "vault_salt": "base64..."
}
```

**Request Fields**:
| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `vault_encrypted_master_key` | Base64 | Yes | MK encrypted with vault password-derived key |
| `vault_mk_nonce` | Base64 | Yes | Nonce for vault MK encryption |
| `vault_salt` | Base64 | Yes | Salt for Argon2id(vault_password) |

> **Client Flow**:
> 1. User provides vault password
> 2. Client generates random `vault_salt`
> 3. Client derives key: `HKDF(Argon2id(password, salt), "master-key")`
> 4. Client encrypts MK with derived key
> 5. Client sends encrypted MK, nonce, and salt to server

**Response** `200 OK`:
```json
{
  "success": true,
  "data": {
    "message": "Vault password configured",
    "configured_at": "2025-01-15T10:30:00.000Z"
  }
}
```

---

## 6. Session Token Format

Sessions use JWT with EdDSA signatures.

**Header**:
```json
{
  "alg": "EdDSA",
  "typ": "JWT"
}
```

**Payload**:
```json
{
  "sub": "770e8400-e29b-41d4-a716-446655440002",
  "tid": "550e8400-e29b-41d4-a716-446655440000",
  "role": "member",
  "iat": 1705312200,
  "exp": 1705355400
}
```

**Claims**:
| Claim | Description |
|-------|-------------|
| `sub` | User ID |
| `tid` | Tenant ID |
| `role` | User role in tenant |
| `iat` | Issued at timestamp |
| `exp` | Expiration timestamp |

## 7. Error Responses

| Code | HTTP | Description |
|------|------|-------------|
| `E_INVALID_CREDENTIALS` | 401 | Authentication failed |
| `E_CREDENTIAL_NOT_FOUND` | 404 | Credential does not exist |
| `E_CHALLENGE_EXPIRED` | 400 | WebAuthn challenge expired |
| `E_CHALLENGE_INVALID` | 400 | WebAuthn challenge mismatch |
| `E_PROVIDER_NOT_FOUND` | 404 | IdP not configured |
| `E_PROVIDER_DISABLED` | 400 | IdP is disabled |
| `E_OIDC_ERROR` | 400 | OIDC provider error |
| `E_SAML_INVALID_RESPONSE` | 400 | Invalid SAML response |
| `E_SAML_SIGNATURE_INVALID` | 400 | SAML signature verification failed |
| `E_SAML_ASSERTION_EXPIRED` | 400 | SAML assertion expired |
| `E_SAML_MISSING_ATTRIBUTES` | 400 | Required SAML attributes not found |
| `E_SESSION_EXPIRED` | 401 | Session token expired |
| `E_SESSION_INVALID` | 401 | Invalid session token |
| `E_LAST_CREDENTIAL` | 400 | Cannot remove only sign-in method |
| `E_CREDENTIAL_IN_USE` | 400 | Cannot remove credential used for current session |
| `E_VAULT_REQUIRED` | 400 | Vault password required for this operation |
| `E_VAULT_ALREADY_CONFIGURED` | 400 | Vault password already set up |
| `E_CREDENTIAL_UPDATE_FORBIDDEN` | 403 | Cannot update this credential type |
| `E_DIGITAL_ID_ERROR` | 400 | Digital ID provider error |
| `E_DIGITAL_ID_SESSION_EXPIRED` | 400 | Digital ID auth session expired |
| `E_DIGITAL_ID_INVALID_CERTIFICATE` | 400 | Invalid Digital ID certificate |
| `E_DIGITAL_ID_VERIFICATION_FAILED` | 400 | Digital ID identity verification failed |
| `E_AUTH_TIMEOUT` | 408 | Authentication session timed out |
| `E_AUTH_CANCELLED` | 400 | User cancelled authentication |
