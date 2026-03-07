# SecureSharing Web & API Invitation System Test Plan

## Overview

This document outlines a comprehensive test plan for the SecureSharing invitation system covering backend API endpoints, business logic, data validation, security, and edge cases.

**Tech Stack:**
- Backend: Elixir/Phoenix 1.7+
- Database: PostgreSQL with Ecto ORM
- Job Queue: Oban
- Email: Swoosh

**Total Test Cases: ~250+**

---

## Table of Contents

1. [API Endpoint Tests - Public](#1-api-endpoint-tests---public)
2. [API Endpoint Tests - Protected](#2-api-endpoint-tests---protected)
3. [Business Logic Tests](#3-business-logic-tests)
4. [Data Validation Tests](#4-data-validation-tests)
5. [Security Tests](#5-security-tests)
6. [Database & Schema Tests](#6-database--schema-tests)
7. [Email Tests](#7-email-tests)
8. [Scheduled Job Tests](#8-scheduled-job-tests)
9. [Integration Tests](#9-integration-tests)
10. [Performance Tests](#10-performance-tests)
11. [Edge Cases](#11-edge-cases)

---

## 1. API Endpoint Tests - Public

### 1.1 GET /api/invite/:token - Get Invitation Info

#### Success Cases
| Test Case | Description | Expected |
|-----------|-------------|----------|
| INV-API-001 | Valid token returns invitation info | 200, invitation data |
| INV-API-002 | Returns tenant name correctly | tenantName populated |
| INV-API-003 | Returns inviter name when available | inviterName populated |
| INV-API-004 | Returns role correctly (admin) | role = "admin" |
| INV-API-005 | Returns role correctly (manager) | role = "manager" |
| INV-API-006 | Returns role correctly (member) | role = "member" |
| INV-API-007 | Returns message when provided | message populated |
| INV-API-008 | Returns null message when not provided | message = null |
| INV-API-009 | Returns expiration date | expiresAt populated |
| INV-API-010 | Valid pending invitation returns valid=true | valid = true |

#### Error Cases - Invalid Tokens
| Test Case | Description | Expected |
|-----------|-------------|----------|
| INV-API-011 | Invalid token format returns error | 200, valid=false, error_reason="not_found" |
| INV-API-012 | Non-existent token returns error | 200, valid=false, error_reason="not_found" |
| INV-API-013 | Empty token returns 404 | 404 Not Found |
| INV-API-014 | Token with special characters | 200, valid=false, error_reason="not_found" |
| INV-API-015 | Extremely long token (>1000 chars) | 400 Bad Request |
| INV-API-016 | SQL injection attempt in token | 200, valid=false (no injection) |
| INV-API-017 | Token with null bytes | 400 Bad Request |

#### Error Cases - Invitation Status
| Test Case | Description | Expected |
|-----------|-------------|----------|
| INV-API-018 | Expired invitation returns error info | 200, valid=false, error_reason="expired" |
| INV-API-019 | Revoked invitation returns error info | 200, valid=false, error_reason="revoked" |
| INV-API-020 | Already accepted invitation returns error | 200, valid=false, error_reason="already_used" |
| INV-API-021 | Invitation expiring in 1 minute still valid | 200, valid=true |
| INV-API-022 | Invitation expired 1 second ago | 200, valid=false, error_reason="expired" |

### 1.2 POST /api/invite/:token/accept - Accept Invitation

#### Success Cases
| Test Case | Description | Expected |
|-----------|-------------|----------|
| INV-API-023 | Accept with valid data creates user | 201, user + tokens |
| INV-API-024 | User is assigned correct role | role matches invitation |
| INV-API-025 | User is added to correct tenant | tenantId matches |
| INV-API-026 | Access token is returned | accessToken present |
| INV-API-027 | Refresh token is returned | refreshToken present |
| INV-API-028 | Token type is Bearer | tokenType = "Bearer" |
| INV-API-029 | Expires in reasonable time | expiresIn > 0 |
| INV-API-030 | User email matches invitation email | user.email matches |
| INV-API-031 | Invitation marked as accepted | status = "accepted" |
| INV-API-032 | Invitation accepted_at is set | accepted_at populated |
| INV-API-033 | Accept with PQC keys | keys stored correctly |

#### Validation Error Cases
| Test Case | Description | Expected |
|-----------|-------------|----------|
| INV-API-034 | Missing display_name | 422, validation error |
| INV-API-035 | Empty display_name | 422, validation error |
| INV-API-036 | Display name too long (>100 chars) | 422, validation error |
| INV-API-037 | Display name with only spaces | 422, validation error |
| INV-API-038 | Missing password | 422, validation error |
| INV-API-039 | Password too short (<8 chars) | 422, validation error |
| INV-API-040 | Password too long (>128 chars) | 422, validation error |
| INV-API-041 | Missing public_keys | 422, validation error |
| INV-API-042 | Invalid public_keys structure | 422, validation error |
| INV-API-043 | Missing encrypted_master_key | 422, validation error |
| INV-API-044 | Invalid Base64 in encrypted_master_key | 422, validation error |
| INV-API-045 | Missing encrypted_private_keys | 422, validation error |
| INV-API-046 | Missing key_derivation_salt | 422, validation error |
| INV-API-047 | Empty request body | 422, validation error |
| INV-API-048 | Malformed JSON body | 400, bad request |

#### Token Error Cases
| Test Case | Description | Expected |
|-----------|-------------|----------|
| INV-API-049 | Invalid token | 404 Not Found |
| INV-API-050 | Expired invitation | 410 Gone |
| INV-API-051 | Revoked invitation | 410 Gone |
| INV-API-052 | Already accepted invitation | 409 Conflict |
| INV-API-053 | Token for different email (if email mismatch check) | 422 |

---

## 2. API Endpoint Tests - Protected

### 2.1 GET /api/tenant/invitations - List Invitations

#### Success Cases
| Test Case | Description | Expected |
|-----------|-------------|----------|
| INV-API-054 | Admin lists all invitations | 200, invitation array |
| INV-API-055 | Owner lists all invitations | 200, invitation array |
| INV-API-056 | Manager lists all invitations | 200, invitation array |
| INV-API-057 | Pagination returns correct page | pagination metadata |
| INV-API-058 | Per_page limits results | correct count |
| INV-API-059 | Filter by status=pending | only pending returned |
| INV-API-060 | Filter by status=accepted | only accepted returned |
| INV-API-061 | Filter by status=expired | only expired returned |
| INV-API-062 | Filter by status=revoked | only revoked returned |
| INV-API-063 | Returns inviter info | invitedBy populated |
| INV-API-064 | Empty list when no invitations | empty array |
| INV-API-065 | Only returns current tenant's invitations | no cross-tenant data |

#### Authorization Error Cases
| Test Case | Description | Expected |
|-----------|-------------|----------|
| INV-API-066 | Member cannot list invitations | 403 Forbidden |
| INV-API-067 | Missing auth token | 401 Unauthorized |
| INV-API-068 | Invalid auth token | 401 Unauthorized |
| INV-API-069 | Expired auth token | 401 Unauthorized |
| INV-API-070 | User from different tenant | 403 Forbidden |

### 2.2 POST /api/tenant/invitations - Create Invitation

#### Success Cases
| Test Case | Description | Expected |
|-----------|-------------|----------|
| INV-API-071 | Admin creates invitation | 201, invitation created |
| INV-API-072 | Owner creates invitation | 201 |
| INV-API-073 | Manager creates invitation | 201 |
| INV-API-074 | Create with member role | role = "member" |
| INV-API-075 | Create with manager role (by admin) | role = "manager" |
| INV-API-076 | Create with admin role (by owner) | role = "admin" |
| INV-API-077 | Create with custom message | message stored |
| INV-API-078 | Create without message | message = null |
| INV-API-079 | Expiration date is set | expiresAt populated |
| INV-API-080 | Status is pending | status = "pending" |
| INV-API-081 | Inviter ID is set | inviterId = current user |
| INV-API-082 | Email is normalized to lowercase | email lowercased |
| INV-API-083 | Email with spaces is trimmed | spaces removed |

#### Validation Error Cases
| Test Case | Description | Expected |
|-----------|-------------|----------|
| INV-API-084 | Missing email | 422, validation error |
| INV-API-085 | Empty email | 422, validation error |
| INV-API-086 | Invalid email format (no @) | 422, validation error |
| INV-API-087 | Invalid email format (no domain) | 422, validation error |
| INV-API-088 | Email too long (>255 chars) | 422, validation error |
| INV-API-089 | Invalid role value | 422, validation error |
| INV-API-090 | Message too long (>1000 chars) | 422, validation error |
| INV-API-091 | Email is inviter's own email | 422, cannot_invite_self |

#### Business Rule Error Cases
| Test Case | Description | Expected |
|-----------|-------------|----------|
| INV-API-092 | Email already registered in tenant | 409 Conflict |
| INV-API-093 | Pending invitation exists for email | 409 Conflict |
| INV-API-094 | Manager inviting admin role | 403 Forbidden |
| INV-API-095 | Member inviting anyone | 403 Forbidden |
| INV-API-096 | Manager inviting manager role | 403 Forbidden |
| INV-API-097 | Tenant invitation limit reached | 422, limit_reached |

#### Authorization Error Cases
| Test Case | Description | Expected |
|-----------|-------------|----------|
| INV-API-098 | No auth token | 401 Unauthorized |
| INV-API-099 | Member role user | 403 Forbidden |

### 2.3 GET /api/tenant/invitations/:id - Get Single Invitation

| Test Case | Description | Expected |
|-----------|-------------|----------|
| INV-API-100 | Admin gets invitation | 200, invitation data |
| INV-API-101 | Non-existent ID | 404 Not Found |
| INV-API-102 | ID from different tenant | 404 Not Found |
| INV-API-103 | Invalid UUID format | 400 Bad Request |
| INV-API-104 | Member cannot get | 403 Forbidden |

### 2.4 DELETE /api/tenant/invitations/:id - Revoke Invitation

| Test Case | Description | Expected |
|-----------|-------------|----------|
| INV-API-105 | Admin revokes pending invitation | 204 No Content |
| INV-API-106 | Owner revokes pending invitation | 204 |
| INV-API-107 | Revoke non-existent invitation | 404 Not Found |
| INV-API-108 | Revoke already accepted invitation | 422, cannot_revoke |
| INV-API-109 | Revoke already expired invitation | 422, cannot_revoke |
| INV-API-110 | Revoke already revoked invitation | 422, cannot_revoke |
| INV-API-111 | Member cannot revoke | 403 Forbidden |
| INV-API-112 | Revoke invitation from other tenant | 404 Not Found |

### 2.5 POST /api/tenant/invitations/:id/resend - Resend Invitation

| Test Case | Description | Expected |
|-----------|-------------|----------|
| INV-API-113 | Resend pending invitation | 200, new token generated |
| INV-API-114 | Expiration extended | new expiresAt |
| INV-API-115 | Resend non-pending invitation | 422, cannot_resend |
| INV-API-116 | Resend limit exceeded (3/24h) | 429 Too Many Requests |
| INV-API-117 | Resend non-existent invitation | 404 Not Found |
| INV-API-118 | Member cannot resend | 403 Forbidden |

### 2.6 GET /api/invitations - List User's Pending Invitations

| Test Case | Description | Expected |
|-----------|-------------|----------|
| INV-API-119 | User sees their pending invitations | 200, array |
| INV-API-120 | Only pending status returned | all status = "pending" |
| INV-API-121 | Empty when no invitations | empty array |
| INV-API-122 | Contains tenant info | tenantName populated |

### 2.7 POST /api/invitations/:id/accept - Accept Pending Invitation (Existing User)

| Test Case | Description | Expected |
|-----------|-------------|----------|
| INV-API-123 | Existing user accepts invitation | 200, success |
| INV-API-124 | User added to new tenant | membership created |
| INV-API-125 | Accept non-existent invitation | 404 Not Found |
| INV-API-126 | Accept invitation for different user | 403 Forbidden |
| INV-API-127 | Accept already accepted invitation | 409 Conflict |

### 2.8 POST /api/invitations/:id/decline - Decline Invitation

| Test Case | Description | Expected |
|-----------|-------------|----------|
| INV-API-128 | Decline pending invitation | 204 No Content |
| INV-API-129 | Decline non-existent | 404 Not Found |
| INV-API-130 | Decline already accepted | 422, cannot_decline |

---

## 3. Business Logic Tests

### 3.1 Token Generation & Storage

| Test Case | Description | Expected |
|-----------|-------------|----------|
| INV-BL-001 | Token is 32 bytes (256 bits) | 43-44 chars Base64 |
| INV-BL-002 | Token is cryptographically random | no patterns |
| INV-BL-003 | Token is URL-safe Base64 | no +/= chars |
| INV-BL-004 | Only hash stored in database | token_hash in DB |
| INV-BL-005 | Original token not in database | token column empty |
| INV-BL-006 | Token only available at creation time | subsequent gets return nil |
| INV-BL-007 | Token hash is SHA-256 | 64 char hex string |
| INV-BL-008 | Same token generates same hash | deterministic |
| INV-BL-009 | Different tokens generate different hashes | unique |

### 3.2 Token Lookup

| Test Case | Description | Expected |
|-----------|-------------|----------|
| INV-BL-010 | Lookup by valid token finds invitation | invitation returned |
| INV-BL-011 | Lookup by invalid token returns nil | nil |
| INV-BL-012 | Lookup is constant-time | no timing attacks |
| INV-BL-013 | Lookup preloads tenant | tenant data available |
| INV-BL-014 | Lookup preloads inviter | inviter data available |

### 3.3 Invitation Creation

| Test Case | Description | Expected |
|-----------|-------------|----------|
| INV-BL-015 | Creates with valid attributes | {:ok, invitation} |
| INV-BL-016 | Sets default role to member | role = :member |
| INV-BL-017 | Sets default status to pending | status = :pending |
| INV-BL-018 | Calculates expiration correctly | 7 days default |
| INV-BL-019 | Respects tenant expiration setting | custom expiry |
| INV-BL-020 | Normalizes email to lowercase | lowercase stored |
| INV-BL-021 | Trims whitespace from email | no leading/trailing spaces |
| INV-BL-022 | Generates unique token per invitation | no duplicates |

### 3.4 Role Hierarchy

| Test Case | Description | Expected |
|-----------|-------------|----------|
| INV-BL-023 | Owner can invite admin | allowed |
| INV-BL-024 | Owner can invite manager | allowed |
| INV-BL-025 | Owner can invite member | allowed |
| INV-BL-026 | Admin can invite admin | allowed |
| INV-BL-027 | Admin can invite manager | allowed |
| INV-BL-028 | Admin can invite member | allowed |
| INV-BL-029 | Manager can invite member | allowed |
| INV-BL-030 | Manager cannot invite manager | denied |
| INV-BL-031 | Manager cannot invite admin | denied |
| INV-BL-032 | Member cannot invite anyone | denied |
| INV-BL-033 | Platform admin can invite any role | allowed |

### 3.5 Invitation Acceptance

| Test Case | Description | Expected |
|-----------|-------------|----------|
| INV-BL-034 | Creates user in transaction | atomic |
| INV-BL-035 | Adds user to tenant | membership created |
| INV-BL-036 | Assigns correct role | role matches invitation |
| INV-BL-037 | Sets invitation to accepted | status = :accepted |
| INV-BL-038 | Sets accepted_at timestamp | timestamp populated |
| INV-BL-039 | Sets accepted_by_id | user ID linked |
| INV-BL-040 | Stores public keys | keys in database |
| INV-BL-041 | Stores encrypted private keys | encrypted data stored |
| INV-BL-042 | Rollback on user creation failure | no partial state |
| INV-BL-043 | Rollback on membership failure | no partial state |

### 3.6 Invitation Revocation

| Test Case | Description | Expected |
|-----------|-------------|----------|
| INV-BL-044 | Revokes pending invitation | status = :revoked |
| INV-BL-045 | Cannot revoke accepted | {:error, :cannot_revoke} |
| INV-BL-046 | Cannot revoke expired | {:error, :cannot_revoke} |
| INV-BL-047 | Cannot revoke already revoked | {:error, :cannot_revoke} |

### 3.7 Invitation Resend

| Test Case | Description | Expected |
|-----------|-------------|----------|
| INV-BL-048 | Generates new token | different from original |
| INV-BL-049 | Extends expiration | new expires_at |
| INV-BL-050 | Cannot resend non-pending | {:error, :cannot_resend} |
| INV-BL-051 | Increments resend count | count updated |

### 3.8 Expiration

| Test Case | Description | Expected |
|-----------|-------------|----------|
| INV-BL-052 | Marks expired invitations | status = :expired |
| INV-BL-053 | Only affects pending status | accepted unchanged |
| INV-BL-054 | Bulk update efficient | uses UPDATE WHERE |
| INV-BL-055 | Returns count of expired | {:ok, count} |

---

## 4. Data Validation Tests

### 4.1 Email Validation

| Test Case | Description | Expected |
|-----------|-------------|----------|
| INV-VAL-001 | Valid email (user@example.com) | valid |
| INV-VAL-002 | Valid email with subdomain | valid |
| INV-VAL-003 | Valid email with + tag | valid |
| INV-VAL-004 | Valid email with numbers | valid |
| INV-VAL-005 | Valid email with dots | valid |
| INV-VAL-006 | Missing @ symbol | invalid |
| INV-VAL-007 | Missing domain | invalid |
| INV-VAL-008 | Missing local part | invalid |
| INV-VAL-009 | Double @ symbol | invalid |
| INV-VAL-010 | Leading dot in local | invalid |
| INV-VAL-011 | Trailing dot in local | invalid |
| INV-VAL-012 | Email with spaces | invalid |
| INV-VAL-013 | Email over 255 chars | invalid |
| INV-VAL-014 | Unicode in local part | check RFC compliance |
| INV-VAL-015 | Empty string | invalid |
| INV-VAL-016 | Null value | invalid |

### 4.2 Display Name Validation

| Test Case | Description | Expected |
|-----------|-------------|----------|
| INV-VAL-017 | Valid display name | valid |
| INV-VAL-018 | Display name with spaces | valid |
| INV-VAL-019 | Display name with numbers | valid |
| INV-VAL-020 | Display name with unicode | valid |
| INV-VAL-021 | Empty display name | invalid |
| INV-VAL-022 | Only whitespace | invalid |
| INV-VAL-023 | Over 100 characters | invalid |
| INV-VAL-024 | Exactly 100 characters | valid |
| INV-VAL-025 | Display name with special chars | valid |

### 4.3 Password Validation

| Test Case | Description | Expected |
|-----------|-------------|----------|
| INV-VAL-026 | Valid password (8+ chars) | valid |
| INV-VAL-027 | Password exactly 8 chars | valid |
| INV-VAL-028 | Password 7 chars | invalid |
| INV-VAL-029 | Password 128 chars | valid |
| INV-VAL-030 | Password over 128 chars | invalid |
| INV-VAL-031 | Empty password | invalid |
| INV-VAL-032 | Password with spaces | valid |
| INV-VAL-033 | Password with unicode | valid |
| INV-VAL-034 | Password with special chars | valid |

### 4.4 Role Validation

| Test Case | Description | Expected |
|-----------|-------------|----------|
| INV-VAL-035 | Valid role "admin" | valid |
| INV-VAL-036 | Valid role "manager" | valid |
| INV-VAL-037 | Valid role "member" | valid |
| INV-VAL-038 | Invalid role "owner" | invalid (owner not invitable) |
| INV-VAL-039 | Invalid role "superadmin" | invalid |
| INV-VAL-040 | Empty role | default to member |
| INV-VAL-041 | Role case sensitivity | case-insensitive |

### 4.5 Message Validation

| Test Case | Description | Expected |
|-----------|-------------|----------|
| INV-VAL-042 | Valid message | valid |
| INV-VAL-043 | Empty message | valid (optional) |
| INV-VAL-044 | Null message | valid (optional) |
| INV-VAL-045 | Message 1000 chars | valid |
| INV-VAL-046 | Message over 1000 chars | invalid |
| INV-VAL-047 | Message with HTML | sanitized or rejected |
| INV-VAL-048 | Message with scripts | sanitized or rejected |

### 4.6 Cryptographic Data Validation

| Test Case | Description | Expected |
|-----------|-------------|----------|
| INV-VAL-049 | Valid Base64 public_keys.kem | valid |
| INV-VAL-050 | Invalid Base64 public_keys.kem | invalid |
| INV-VAL-051 | Empty public_keys.kem | invalid |
| INV-VAL-052 | Valid Base64 public_keys.sign | valid |
| INV-VAL-053 | Valid Base64 encrypted_master_key | valid |
| INV-VAL-054 | Invalid Base64 encrypted_master_key | invalid |
| INV-VAL-055 | Valid Base64 encrypted_private_keys | valid |
| INV-VAL-056 | Valid Base64 key_derivation_salt | valid |
| INV-VAL-057 | Oversized encrypted data (>1MB) | invalid |

---

## 5. Security Tests

### 5.1 Token Security

| Test Case | Description | Expected |
|-----------|-------------|----------|
| INV-SEC-001 | Token has sufficient entropy | 256 bits |
| INV-SEC-002 | Token not predictable | random |
| INV-SEC-003 | Token not guessable by enumeration | rate limited |
| INV-SEC-004 | Token hash lookup constant-time | no timing leak |
| INV-SEC-005 | Original token not logged | logs clean |
| INV-SEC-006 | Token not in error responses | not exposed |
| INV-SEC-007 | Token hash not reversible | SHA-256 |

### 5.2 Rate Limiting

| Test Case | Description | Expected |
|-----------|-------------|----------|
| INV-SEC-008 | Create invitation rate limit (20/hr) | 429 after limit |
| INV-SEC-009 | Accept invitation rate limit (10/hr) | 429 after limit |
| INV-SEC-010 | Get invitation info rate limit (60/min) | 429 after limit |
| INV-SEC-011 | Resend invitation rate limit (3/24hr) | 429 after limit |
| INV-SEC-012 | Rate limit per IP for public endpoints | IP-based |
| INV-SEC-013 | Rate limit per user for protected endpoints | user-based |
| INV-SEC-014 | Rate limit headers returned | X-RateLimit-* headers |

### 5.3 Authorization

| Test Case | Description | Expected |
|-----------|-------------|----------|
| INV-SEC-015 | Tenant isolation - cannot access other tenant | 403/404 |
| INV-SEC-016 | Role enforcement - member cannot invite | 403 |
| INV-SEC-017 | Role hierarchy - cannot escalate | 403 |
| INV-SEC-018 | Token required for protected endpoints | 401 |
| INV-SEC-019 | Expired token rejected | 401 |
| INV-SEC-020 | Invalid token signature rejected | 401 |
| INV-SEC-021 | User can only accept own invitations | 403 |

### 5.4 Input Sanitization

| Test Case | Description | Expected |
|-----------|-------------|----------|
| INV-SEC-022 | SQL injection in email | no injection |
| INV-SEC-023 | SQL injection in token | no injection |
| INV-SEC-024 | SQL injection in display_name | no injection |
| INV-SEC-025 | XSS in message field | sanitized |
| INV-SEC-026 | XSS in display_name | sanitized |
| INV-SEC-027 | Path traversal in token | rejected |
| INV-SEC-028 | Null bytes in input | rejected |
| INV-SEC-029 | Unicode normalization attacks | handled |

### 5.5 CSRF Protection

| Test Case | Description | Expected |
|-----------|-------------|----------|
| INV-SEC-030 | POST without CSRF token (if applicable) | 403 |
| INV-SEC-031 | DELETE without CSRF token | 403 |
| INV-SEC-032 | API uses JWT (no CSRF needed) | works |

### 5.6 Audit Logging

| Test Case | Description | Expected |
|-----------|-------------|----------|
| INV-SEC-033 | Invitation created logged | event recorded |
| INV-SEC-034 | Invitation accepted logged | event recorded |
| INV-SEC-035 | Invitation revoked logged | event recorded |
| INV-SEC-036 | Invitation expired logged | event recorded |
| INV-SEC-037 | Failed attempts logged | event recorded |
| INV-SEC-038 | Logs include IP address | IP recorded |
| INV-SEC-039 | Logs include user agent | UA recorded |

---

## 6. Database & Schema Tests

### 6.1 Table Structure

| Test Case | Description | Expected |
|-----------|-------------|----------|
| INV-DB-001 | Table exists | invitations table |
| INV-DB-002 | ID is UUIDv7 | proper format |
| INV-DB-003 | token_hash is NOT NULL | constraint |
| INV-DB-004 | token_hash is UNIQUE | constraint |
| INV-DB-005 | email is NOT NULL | constraint |
| INV-DB-006 | email max 255 chars | constraint |
| INV-DB-007 | role has valid enum values | constraint |
| INV-DB-008 | status has valid enum values | constraint |
| INV-DB-009 | expires_at is NOT NULL | constraint |
| INV-DB-010 | tenant_id foreign key | constraint |
| INV-DB-011 | inviter_id foreign key | constraint |
| INV-DB-012 | accepted_by_id foreign key | constraint |
| INV-DB-013 | Cascade delete on tenant | cascades |
| INV-DB-014 | Cascade delete on inviter | cascades |

### 6.2 Indexes

| Test Case | Description | Expected |
|-----------|-------------|----------|
| INV-DB-015 | Index on token_hash | exists |
| INV-DB-016 | Index on email | exists |
| INV-DB-017 | Index on tenant_id | exists |
| INV-DB-018 | Index on status | exists |
| INV-DB-019 | Partial index on expires_at | exists |
| INV-DB-020 | Unique index on (tenant_id, email) pending | exists |

### 6.3 Constraints

| Test Case | Description | Expected |
|-----------|-------------|----------|
| INV-DB-021 | Cannot insert duplicate token_hash | error |
| INV-DB-022 | Cannot insert null required fields | error |
| INV-DB-023 | Cannot insert invalid role | error |
| INV-DB-024 | Cannot insert invalid status | error |
| INV-DB-025 | Cannot have two pending for same email/tenant | error |

### 6.4 Performance

| Test Case | Description | Expected |
|-----------|-------------|----------|
| INV-DB-026 | Token lookup uses index | EXPLAIN shows index |
| INV-DB-027 | List by tenant uses index | EXPLAIN shows index |
| INV-DB-028 | Status filter uses index | EXPLAIN shows index |
| INV-DB-029 | Expiry check uses partial index | EXPLAIN shows index |

---

## 7. Email Tests

### 7.1 Invitation Email

| Test Case | Description | Expected |
|-----------|-------------|----------|
| INV-EMAIL-001 | Email sent on invitation creation | email queued |
| INV-EMAIL-002 | Correct recipient (invitee email) | to: invitee |
| INV-EMAIL-003 | Subject includes tenant name | subject correct |
| INV-EMAIL-004 | Body includes invitation link | link present |
| INV-EMAIL-005 | Link contains correct token | token in URL |
| INV-EMAIL-006 | Body includes inviter name | inviter shown |
| INV-EMAIL-007 | Body includes custom message | message shown |
| INV-EMAIL-008 | HTML version rendered | HTML present |
| INV-EMAIL-009 | Plain text version rendered | text present |
| INV-EMAIL-010 | Email sent asynchronously | non-blocking |

### 7.2 Acceptance Notification Email

| Test Case | Description | Expected |
|-----------|-------------|----------|
| INV-EMAIL-011 | Notification sent to inviter | to: inviter |
| INV-EMAIL-012 | Subject includes new user name | subject correct |
| INV-EMAIL-013 | Body includes confirmation | content correct |

### 7.3 Welcome Email

| Test Case | Description | Expected |
|-----------|-------------|----------|
| INV-EMAIL-014 | Welcome email sent to new user | to: new user |
| INV-EMAIL-015 | Subject includes tenant name | subject correct |
| INV-EMAIL-016 | Body includes onboarding info | content correct |

### 7.4 Resend Email

| Test Case | Description | Expected |
|-----------|-------------|----------|
| INV-EMAIL-017 | Email sent on resend | email queued |
| INV-EMAIL-018 | Contains new token | new token in link |
| INV-EMAIL-019 | Indicates it's a resend | text mentions resend |

### 7.5 Email Failures

| Test Case | Description | Expected |
|-----------|-------------|----------|
| INV-EMAIL-020 | Invitation still created if email fails | invitation exists |
| INV-EMAIL-021 | Email failure logged | error logged |
| INV-EMAIL-022 | Retry on temporary failure | retry attempted |

---

## 8. Scheduled Job Tests

### 8.1 Expire Invitations Worker

| Test Case | Description | Expected |
|-----------|-------------|----------|
| INV-JOB-001 | Job runs on schedule (hourly) | scheduled |
| INV-JOB-002 | Expires past-due invitations | status changed |
| INV-JOB-003 | Does not affect accepted invitations | unchanged |
| INV-JOB-004 | Does not affect revoked invitations | unchanged |
| INV-JOB-005 | Does not affect not-yet-expired | unchanged |
| INV-JOB-006 | Job completes successfully | {:ok, count} |
| INV-JOB-007 | Job logs results | info logged |
| INV-JOB-008 | Job handles empty set | no error |
| INV-JOB-009 | Job retries on failure | retry attempted |
| INV-JOB-010 | Job has max attempts | 3 attempts |

---

## 9. Integration Tests

### 9.1 Complete Invitation Flow

| Test Case | Description | Expected |
|-----------|-------------|----------|
| INV-INT-001 | Admin creates → user receives email → accepts → logged in | full flow |
| INV-INT-002 | Create → revoke → acceptance fails | proper error |
| INV-INT-003 | Create → expire → acceptance fails | proper error |
| INV-INT-004 | Create → accept → second accept fails | conflict |
| INV-INT-005 | Create → resend → accept with new token | works |
| INV-INT-006 | Create → accept with old token after resend | fails |

### 9.2 Multi-tenant Scenarios

| Test Case | Description | Expected |
|-----------|-------------|----------|
| INV-INT-007 | Same email invited to multiple tenants | both work |
| INV-INT-008 | User accepts one, declines another | correct state |
| INV-INT-009 | Existing user invited to new tenant | can accept |
| INV-INT-010 | Admin of tenant A cannot see tenant B invitations | isolated |

### 9.3 Concurrent Operations

| Test Case | Description | Expected |
|-----------|-------------|----------|
| INV-INT-011 | Two simultaneous accepts of same invitation | one succeeds |
| INV-INT-012 | Accept and revoke simultaneously | consistent state |
| INV-INT-013 | Multiple invitations created simultaneously | all unique tokens |

### 9.4 Deep Link Integration

| Test Case | Description | Expected |
|-----------|-------------|----------|
| INV-INT-014 | Mobile deep link opens invitation | app shows invite |
| INV-INT-015 | Web universal link opens invitation | web shows invite |
| INV-INT-016 | Deep link with invalid token | error shown |

---

## 10. Performance Tests

### 10.1 Load Testing

| Test Case | Description | Expected |
|-----------|-------------|----------|
| INV-PERF-001 | 100 concurrent invitation creations | all succeed |
| INV-PERF-002 | 1000 invitation lookups/second | <100ms avg |
| INV-PERF-003 | 10,000 invitations in list query | <500ms |
| INV-PERF-004 | Bulk expiration of 1000 invitations | <1s |

### 10.2 Response Times

| Test Case | Description | Expected |
|-----------|-------------|----------|
| INV-PERF-005 | GET invitation info p95 | <100ms |
| INV-PERF-006 | POST create invitation p95 | <200ms |
| INV-PERF-007 | POST accept invitation p95 | <500ms |
| INV-PERF-008 | GET list invitations p95 | <200ms |

---

## 11. Edge Cases

### 11.1 Boundary Conditions

| Test Case | Description | Expected |
|-----------|-------------|----------|
| INV-EDGE-001 | Invitation expires exactly now | treated as expired |
| INV-EDGE-002 | Invitation expires in 1 second | still valid |
| INV-EDGE-003 | Email at exactly 255 characters | valid |
| INV-EDGE-004 | Display name at exactly 100 characters | valid |
| INV-EDGE-005 | Password at exactly 8 characters | valid |
| INV-EDGE-006 | First invitation for tenant | works |
| INV-EDGE-007 | Last allowed invitation (quota) | works |
| INV-EDGE-008 | One over quota | rejected |

### 11.2 Special Characters

| Test Case | Description | Expected |
|-----------|-------------|----------|
| INV-EDGE-009 | Email with + addressing | valid |
| INV-EDGE-010 | Email with dots | valid |
| INV-EDGE-011 | Email with long TLD | valid |
| INV-EDGE-012 | Display name with emoji | valid |
| INV-EDGE-013 | Message with newlines | preserved |
| INV-EDGE-014 | Message with emoji | valid |

### 11.3 State Transitions

| Test Case | Description | Expected |
|-----------|-------------|----------|
| INV-EDGE-015 | Pending → Accepted | valid |
| INV-EDGE-016 | Pending → Expired | valid |
| INV-EDGE-017 | Pending → Revoked | valid |
| INV-EDGE-018 | Accepted → anything | invalid |
| INV-EDGE-019 | Expired → anything | invalid |
| INV-EDGE-020 | Revoked → anything | invalid |

### 11.4 Null/Empty Handling

| Test Case | Description | Expected |
|-----------|-------------|----------|
| INV-EDGE-021 | Null message stored | null in DB |
| INV-EDGE-022 | Empty string message | stored as empty |
| INV-EDGE-023 | Null inviter name displayed | "Unknown" or hidden |
| INV-EDGE-024 | Deleted inviter (cascade) | invitation deleted |
| INV-EDGE-025 | Deleted tenant (cascade) | invitation deleted |

### 11.5 Clock/Timezone Issues

| Test Case | Description | Expected |
|-----------|-------------|----------|
| INV-EDGE-026 | Server in UTC, client in different TZ | consistent |
| INV-EDGE-027 | DST transition during invitation period | handled |
| INV-EDGE-028 | Leap second handling | no issues |

### 11.6 Recovery Scenarios

| Test Case | Description | Expected |
|-----------|-------------|----------|
| INV-EDGE-029 | Database connection lost mid-accept | rollback |
| INV-EDGE-030 | Email service down | invitation created, email queued |
| INV-EDGE-031 | Partial data in request | validation error |

---

## Test Implementation Guide

### File Structure
```
test/
├── secure_sharing/
│   ├── invitations_test.exs              # Business logic tests
│   ├── invitations/
│   │   ├── invitation_test.exs           # Schema tests
│   │   └── token_test.exs                # Token generation tests
│   └── workers/
│       └── expire_invitations_worker_test.exs
├── secure_sharing_web/
│   └── controllers/
│       └── api/
│           ├── invite_controller_test.exs      # Public API tests
│           ├── invitation_controller_test.exs  # Protected API tests
│           └── invitation_json_test.exs        # JSON rendering tests
├── support/
│   ├── fixtures/
│   │   └── invitation_fixtures.ex        # Test data factories
│   └── helpers/
│       └── invitation_helpers.ex         # Test helpers
└── integration/
    └── invitation_flow_test.exs          # End-to-end tests
```

### Test Helpers
```elixir
defmodule SecureSharing.Test.InvitationHelpers do
  def create_invitation_fixture(attrs \\ %{})
  def create_pending_invitation(tenant, inviter, email)
  def create_accepted_invitation(tenant, inviter, email)
  def create_expired_invitation(tenant, inviter, email)
  def create_revoked_invitation(tenant, inviter, email)
  def generate_test_token()
  def assert_invitation_email_sent(email)
end
```

### Running Tests
```bash
# All invitation tests
mix test test/secure_sharing/invitations_test.exs

# Controller tests
mix test test/secure_sharing_web/controllers/api/invite_controller_test.exs
mix test test/secure_sharing_web/controllers/api/invitation_controller_test.exs

# Integration tests
mix test test/integration/invitation_flow_test.exs

# With coverage
mix test --cover test/secure_sharing/invitations_test.exs

# Specific test
mix test test/secure_sharing/invitations_test.exs:42
```

---

## Summary

| Category | Test Count |
|----------|------------|
| API - Public Endpoints | ~53 |
| API - Protected Endpoints | ~75 |
| Business Logic | ~55 |
| Data Validation | ~57 |
| Security | ~39 |
| Database & Schema | ~29 |
| Email | ~22 |
| Scheduled Jobs | ~10 |
| Integration | ~16 |
| Performance | ~8 |
| Edge Cases | ~31 |
| **Total** | **~395** |

This test plan provides comprehensive coverage of the SecureSharing invitation system's web and API functionality, ensuring reliability, security, and proper handling of all edge cases.
