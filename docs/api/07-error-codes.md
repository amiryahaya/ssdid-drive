# Error Codes Reference

**Version**: 1.0.0
**Status**: Draft
**Last Updated**: 2025-01

## 1. Overview

This document provides a comprehensive reference of all error codes returned by the SecureSharing API.

## 2. Error Response Format

All errors follow this format:

```json
{
  "success": false,
  "error": {
    "code": "E_ERROR_CODE",
    "message": "Human-readable error message",
    "details": {
      "field": "additional context"
    }
  }
}
```

## 3. Error Categories

### 3.1 Authentication Errors (E_AUTH_*)

| Code | HTTP | Message | Description |
|------|------|---------|-------------|
| `E_UNAUTHORIZED` | 401 | Authentication required | No auth token provided |
| `E_TOKEN_EXPIRED` | 401 | Session token has expired | JWT expired |
| `E_TOKEN_INVALID` | 401 | Invalid authentication token | Malformed or tampered JWT |
| `E_TOKEN_REVOKED` | 401 | Session has been revoked | Explicit logout or security revocation |
| `E_INVALID_CREDENTIALS` | 401 | Invalid credentials | Login failed |
| `E_CREDENTIAL_NOT_FOUND` | 401 | No credential found for user | WebAuthn credential missing |
| `E_CHALLENGE_EXPIRED` | 400 | Authentication challenge expired | WebAuthn challenge timeout |
| `E_CHALLENGE_INVALID` | 400 | Invalid authentication challenge | Challenge mismatch |
| `E_MFA_REQUIRED` | 401 | Multi-factor authentication required | Need additional auth factor |
| `E_PROVIDER_NOT_FOUND` | 404 | Identity provider not found | IdP not configured |
| `E_PROVIDER_DISABLED` | 400 | Identity provider is disabled | IdP disabled by admin |
| `E_OIDC_ERROR` | 400 | OIDC provider error | External IdP failure |

### 3.2 Authorization Errors (E_PERM_*)

| Code | HTTP | Message | Description |
|------|------|---------|-------------|
| `E_FORBIDDEN` | 403 | Access denied | Generic permission denied |
| `E_PERMISSION_DENIED` | 403 | Insufficient permissions | Specific permission missing |
| `E_INSUFFICIENT_ROLE` | 403 | Requires higher role | Admin/owner role needed |
| `E_TENANT_MISMATCH` | 403 | Resource belongs to different tenant | Cross-tenant access attempt |
| `E_NOT_OWNER` | 403 | Must be resource owner | Owner-only operation |
| `E_SHARE_REQUIRED` | 403 | No share grant for resource | Need share to access |
| `E_SHARE_EXPIRED` | 403 | Share grant has expired | Time-limited share ended |

### 3.3 Resource Errors (E_RES_*)

| Code | HTTP | Message | Description |
|------|------|---------|-------------|
| `E_NOT_FOUND` | 404 | Resource not found | Generic not found |
| `E_USER_NOT_FOUND` | 404 | User not found | User ID invalid |
| `E_TENANT_NOT_FOUND` | 404 | Tenant not found | Tenant ID invalid |
| `E_FILE_NOT_FOUND` | 404 | File not found | File ID invalid or deleted |
| `E_FOLDER_NOT_FOUND` | 404 | Folder not found | Folder ID invalid |
| `E_SHARE_NOT_FOUND` | 404 | Share not found | Share ID invalid |
| `E_PARENT_NOT_FOUND` | 404 | Parent folder not found | Invalid parent_id |
| `E_REQUEST_NOT_FOUND` | 404 | Recovery request not found | Invalid request ID |
| `E_CONFLICT` | 409 | Resource already exists | Duplicate creation |
| `E_SHARE_EXISTS` | 409 | Share already exists | Duplicate share |
| `E_FILE_DELETED` | 410 | File has been deleted | File in trash |
| `E_FOLDER_DELETED` | 410 | Folder has been deleted | Folder in trash |

### 3.4 Validation Errors (E_VAL_*)

| Code | HTTP | Message | Description |
|------|------|---------|-------------|
| `E_VALIDATION_FAILED` | 400 | Request validation failed | Generic validation error |
| `E_INVALID_JSON` | 400 | Malformed JSON in request body | JSON parse error |
| `E_MISSING_FIELD` | 400 | Required field missing | Missing required param |
| `E_INVALID_FIELD` | 400 | Invalid field value | Field validation failed |
| `E_INVALID_UUID` | 400 | Invalid UUID format | UUID parse error |
| `E_INVALID_BASE64` | 400 | Invalid Base64 encoding | Base64 decode error |
| `E_INVALID_TIMESTAMP` | 400 | Invalid timestamp format | ISO 8601 parse error |
| `E_INVALID_EMAIL` | 400 | Invalid email format | Email validation failed |
| `E_FIELD_TOO_LONG` | 400 | Field exceeds maximum length | Length limit exceeded |
| `E_INVALID_ENUM` | 400 | Invalid enum value | Not in allowed values |

### 3.5 Cryptographic Errors (E_CRYPTO_*)

| Code | HTTP | Message | Description |
|------|------|---------|-------------|
| `E_SIGNATURE_INVALID` | 400 | Signature verification failed | Bad signature |
| `E_SIGNATURE_MISSING` | 400 | Required signature missing | No signature provided |
| `E_HASH_MISMATCH` | 400 | Hash verification failed | Content integrity error |
| `E_KEY_INVALID` | 400 | Invalid key format | Key parse/validation error |
| `E_DECRYPTION_FAILED` | 400 | Decryption failed | Wrong key or corrupt data |
| `E_KEM_INVALID` | 400 | Invalid KEM ciphertext | KEM decapsulation failed |

### 3.6 Business Logic Errors (E_BIZ_*)

| Code | HTTP | Message | Description |
|------|------|---------|-------------|
| `E_CANNOT_DELETE_ROOT` | 400 | Cannot delete root folder | Root folder protected |
| `E_FOLDER_NOT_EMPTY` | 400 | Folder is not empty | Need recursive=true |
| `E_CIRCULAR_REFERENCE` | 400 | Operation would create cycle | Folder move loop |
| `E_CANNOT_SHARE_SELF` | 400 | Cannot share with yourself | Self-share attempt |
| `E_CANNOT_MODIFY_SELF` | 400 | Cannot modify own account | Self-role change |
| `E_CANNOT_DELETE_OWNER` | 400 | Cannot delete tenant owner | Owner protected |
| `E_KEK_ROTATION_INCOMPLETE` | 400 | KEK rotation incomplete | Missing children |
| `E_THRESHOLD_NOT_REACHED` | 400 | Recovery threshold not reached | Need more approvals |
| `E_ALREADY_APPROVED` | 400 | Already approved | Duplicate approval |
| `E_REQUEST_EXPIRED` | 400 | Recovery request expired | Timeout reached |
| `E_REQUEST_COMPLETED` | 400 | Recovery already completed | Cannot modify |
| `E_RECOVERY_NOT_SETUP` | 400 | Recovery not configured | No shares distributed |

### 3.7 Quota/Limit Errors (E_LIMIT_*)

| Code | HTTP | Message | Description |
|------|------|---------|-------------|
| `E_QUOTA_EXCEEDED` | 402 | Storage quota exceeded | Tenant storage full |
| `E_USER_LIMIT_EXCEEDED` | 402 | User limit exceeded | Tenant user cap reached |
| `E_FILE_TOO_LARGE` | 413 | File exceeds size limit | Max file size exceeded |
| `E_RATE_LIMITED` | 429 | Too many requests | Rate limit hit |
| `E_UPLOAD_LIMIT` | 429 | Upload limit exceeded | Too many uploads |
| `E_LINK_MAX_DOWNLOADS` | 400 | Download limit reached | Share link exhausted |

### 3.8 Upload/Download Errors (E_XFER_*)

| Code | HTTP | Message | Description |
|------|------|---------|-------------|
| `E_UPLOAD_EXPIRED` | 400 | Upload URL expired | Pre-signed URL timeout |
| `E_UPLOAD_INCOMPLETE` | 400 | Upload not completed | Blob not fully uploaded |
| `E_UPLOAD_FAILED` | 500 | Upload failed | Storage write error |
| `E_DOWNLOAD_FAILED` | 500 | Download failed | Storage read error |
| `E_MULTIPART_INVALID` | 400 | Invalid multipart upload | Part mismatch |

### 3.9 Server Errors (E_SRV_*)

| Code | HTTP | Message | Description |
|------|------|---------|-------------|
| `E_INTERNAL_ERROR` | 500 | Internal server error | Unexpected error |
| `E_DATABASE_ERROR` | 503 | Database unavailable | DB connection failure |
| `E_STORAGE_ERROR` | 502 | Storage service unavailable | Object store failure |
| `E_IDP_ERROR` | 502 | Identity provider unavailable | External IdP down |
| `E_SERVICE_UNAVAILABLE` | 503 | Service temporarily unavailable | Maintenance |

### 3.10 Tenant/User Status Errors (E_STATUS_*)

| Code | HTTP | Message | Description |
|------|------|---------|-------------|
| `E_TENANT_SUSPENDED` | 403 | Tenant account suspended | Billing or policy |
| `E_TENANT_DELETED` | 403 | Tenant account deleted | Tenant terminated |
| `E_USER_SUSPENDED` | 403 | User account suspended | Admin action |
| `E_USER_DELETED` | 403 | User account deleted | User terminated |
| `E_NOT_TRUSTEE` | 403 | User is not a trustee | Not assigned as trustee |

## 4. Error Details Schema

### 4.1 Validation Error Details

```json
{
  "success": false,
  "error": {
    "code": "E_VALIDATION_FAILED",
    "message": "Request validation failed",
    "details": {
      "errors": [
        {
          "field": "email",
          "code": "E_INVALID_EMAIL",
          "message": "Invalid email format"
        },
        {
          "field": "permission",
          "code": "E_INVALID_ENUM",
          "message": "Must be one of: read, write, admin"
        }
      ]
    }
  }
}
```

### 4.2 Resource Error Details

```json
{
  "success": false,
  "error": {
    "code": "E_FILE_NOT_FOUND",
    "message": "File not found",
    "details": {
      "resource_type": "file",
      "resource_id": "550e8400-e29b-41d4-a716-446655440000"
    }
  }
}
```

### 4.3 Rate Limit Error Details

```json
{
  "success": false,
  "error": {
    "code": "E_RATE_LIMITED",
    "message": "Too many requests",
    "details": {
      "limit": 100,
      "window": "60s",
      "retry_after": 45
    }
  }
}
```

### 4.4 Quota Error Details

```json
{
  "success": false,
  "error": {
    "code": "E_QUOTA_EXCEEDED",
    "message": "Storage quota exceeded",
    "details": {
      "quota_bytes": 10737418240,
      "used_bytes": 10737418240,
      "requested_bytes": 1048576
    }
  }
}
```

## 5. HTTP Status Code Summary

| HTTP Code | Category | Usage |
|-----------|----------|-------|
| 400 | Bad Request | Validation, business logic errors |
| 401 | Unauthorized | Authentication failures |
| 402 | Payment Required | Quota/billing issues |
| 403 | Forbidden | Authorization failures |
| 404 | Not Found | Resource doesn't exist |
| 409 | Conflict | Duplicate resource |
| 410 | Gone | Deleted resource |
| 413 | Payload Too Large | File size limits |
| 429 | Too Many Requests | Rate limiting |
| 500 | Internal Server Error | Unexpected errors |
| 502 | Bad Gateway | External service failures |
| 503 | Service Unavailable | Temporary unavailability |

## 6. Client Handling Guidelines

### 6.1 Retryable Errors

These errors may succeed on retry:
- `E_RATE_LIMITED` (wait for `retry_after`)
- `E_DATABASE_ERROR` (exponential backoff)
- `E_STORAGE_ERROR` (exponential backoff)
- `E_SERVICE_UNAVAILABLE` (exponential backoff)
- `E_IDP_ERROR` (exponential backoff)

### 6.2 Non-Retryable Errors

These errors require user action:
- All `E_VAL_*` errors (fix input)
- All `E_PERM_*` errors (get permission)
- All `E_AUTH_*` errors (re-authenticate)
- `E_QUOTA_EXCEEDED` (upgrade plan)
- `E_SIGNATURE_INVALID` (re-sign)

### 6.3 Error Logging

Log these errors for investigation:
- All `E_SRV_*` errors
- `E_DECRYPTION_FAILED` (may indicate attack)
- `E_SIGNATURE_INVALID` (may indicate tampering)
- `E_HASH_MISMATCH` (may indicate corruption)
