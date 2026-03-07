# SecureSharing Backend Service - Comprehensive Test Plan

## Document Information

| Attribute | Value |
|-----------|-------|
| Version | 1.0 |
| Last Updated | 2026-01-24 |
| Service | SecureSharing Backend |
| Framework | Elixir/Phoenix 1.8 |
| Test Framework | ExUnit |

---

## 1. Overview

### 1.1 Purpose

This document provides a comprehensive test plan for the SecureSharing backend service, ensuring secure file sharing with post-quantum cryptography (PQC), multi-tenancy, and social recovery features are thoroughly tested.

### 1.2 Objectives

- Verify secure end-to-end encrypted file sharing functionality
- Validate post-quantum cryptographic operations (KAZ-KEM, KAZ-SIGN, ML-KEM, ML-DSA)
- Ensure multi-tenant isolation and data security
- Test social recovery workflow completeness
- Confirm API endpoint correctness and security
- Establish performance baselines

### 1.3 Service Description

SecureSharing is a secure file sharing platform with:
- **End-to-end encryption** using hybrid PQC algorithms
- **Multi-tenancy** with tenant isolation
- **Device management** with key enrollment
- **File/folder hierarchy** with sharing permissions
- **Social recovery** using Shamir's Secret Sharing
- **Real-time notifications** via WebSockets
- **Admin portal** for system management

---

## 2. System Architecture

### 2.1 Core Modules

| Module | Description | Priority |
|--------|-------------|----------|
| `Accounts` | User registration, authentication, multi-tenancy | P0 |
| `Crypto` | PQC key management (KEM + Signatures) | P0 |
| `Files` | File metadata and operations | P0 |
| `Sharing` | Share permissions and access control | P0 |
| `Devices` | Device enrollment and key management | P0 |
| `Recovery` | Social recovery with trustees | P1 |
| `Notifications` | Push notifications and real-time updates | P1 |
| `Invitations` | User invitation workflow | P1 |
| `Audit` | Event logging and compliance | P2 |
| `Storage` | S3/local file storage | P1 |
| `Cache` | ETS-based caching layer | P2 |

### 2.2 API Structure

```
/api
├── /auth           # Authentication (public)
├── /tenants        # Multi-tenancy management
├── /invitations    # User invitations
├── /me             # Current user profile
├── /users          # User lookup for sharing
├── /devices        # Device management
├── /folders        # Folder hierarchy
├── /files          # File operations
├── /shares         # Sharing management
├── /recovery       # Social recovery
└── /notifications  # Notification management

/admin
├── /login          # Admin authentication
├── /tenants        # Tenant management
├── /users          # User management
├── /audit          # Audit logs
└── /notifications  # System notifications

/health
├── /              # Basic health check
└── /ready         # Readiness probe
```

---

## 3. Test Scope

### 3.1 In Scope

| Component | Test Types |
|-----------|------------|
| Authentication | Unit, Integration, Security, E2E |
| Multi-tenancy | Unit, Integration, Security |
| Cryptography (PQC) | Unit, Integration, Security |
| File Management | Unit, Integration, E2E |
| Folder Hierarchy | Unit, Integration |
| Sharing | Unit, Integration, Security, E2E |
| Device Management | Unit, Integration, Security |
| Social Recovery | Unit, Integration, E2E |
| Notifications | Unit, Integration, WebSocket |
| Invitations | Unit, Integration, E2E |
| Admin Portal | Integration, LiveView |
| API Security | Security, Penetration |
| Performance | Load, Stress, Scalability |

### 3.2 Out of Scope

- Client applications (iOS, Android, Desktop, Web)
- External storage providers (AWS S3 mocked)
- Third-party IdP integration (future feature)
- Infrastructure/deployment testing

---

## 4. Test Strategy

### 4.1 Test Pyramid

```
        ┌─────────────────┐
        │    E2E Tests    │  (8 flows)
        │  Full workflows │
        ├─────────────────┤
        │  Integration    │  (15+ tests)
        │  API + Database │
        ├─────────────────┤
        │   Unit Tests    │  (100+ tests)
        │ Business Logic  │
        └─────────────────┘
```

### 4.2 Test Categories

| Category | ID Prefix | Priority | Coverage Target |
|----------|-----------|----------|-----------------|
| Unit Tests | UT-* | P0 | > 80% |
| Integration Tests | IT-* | P0 | All APIs |
| Security Tests | SEC-* | P0 | All critical paths |
| E2E Tests | E2E-* | P1 | Core workflows |
| Performance Tests | PERF-* | P1 | SLA metrics |
| LiveView Tests | LV-* | P2 | Admin portal |

### 4.3 Test Tags

| Tag | Description | When to Run |
|-----|-------------|-------------|
| `:integration` | Requires database | Always (CI) |
| `:crypto` | Requires NIF compilation | Always (CI) |
| `:s3` | Requires S3/MinIO | Integration env |
| `:websocket` | WebSocket channel tests | Always (CI) |
| `:slow` | Long-running tests | Nightly |
| `:skip` | Temporarily disabled | Manual only |

---

## 5. Test Categories

### 5.1 Unit Tests (UT)

#### UT-ACCT: Accounts Module

| Test ID | Description | File |
|---------|-------------|------|
| UT-ACCT-001 | User registration validation | `accounts_test.exs` |
| UT-ACCT-002 | User email uniqueness | `accounts_test.exs` |
| UT-ACCT-003 | Password hashing (Argon2) | `accounts_test.exs` |
| UT-ACCT-004 | User authentication | `accounts_test.exs` |
| UT-ACCT-005 | User profile update | `accounts_test.exs` |
| UT-ACCT-006 | Tenant creation | `accounts_test.exs` |
| UT-ACCT-007 | User-tenant association | `accounts_test.exs` |
| UT-ACCT-008 | Role assignment (owner/admin/member) | `accounts_test.exs` |
| UT-ACCT-009 | IdP configuration | `accounts_test.exs` |
| UT-ACCT-010 | Credential management | `accounts_test.exs` |

#### UT-CRYPTO: Cryptography Module

| Test ID | Description | File |
|---------|-------------|------|
| UT-CRYPTO-001 | KAZ-KEM key generation | `crypto_test.exs` |
| UT-CRYPTO-002 | KAZ-KEM encapsulation | `crypto_test.exs` |
| UT-CRYPTO-003 | KAZ-KEM decapsulation | `crypto_test.exs` |
| UT-CRYPTO-004 | KAZ-SIGN key generation | `crypto_test.exs` |
| UT-CRYPTO-005 | KAZ-SIGN signing | `crypto_test.exs` |
| UT-CRYPTO-006 | KAZ-SIGN verification | `crypto_test.exs` |
| UT-CRYPTO-007 | ML-KEM key generation | `crypto_test.exs` |
| UT-CRYPTO-008 | ML-KEM encapsulation | `crypto_test.exs` |
| UT-CRYPTO-009 | ML-DSA key generation | `crypto_test.exs` |
| UT-CRYPTO-010 | ML-DSA signing | `crypto_test.exs` |
| UT-CRYPTO-011 | Hybrid KEM (KAZ + ML-KEM) | `crypto_test.exs` |
| UT-CRYPTO-012 | Hybrid Sign (KAZ + ML-DSA) | `crypto_test.exs` |
| UT-CRYPTO-013 | Key bundle generation | `crypto_test.exs` |
| UT-CRYPTO-014 | Key serialization/deserialization | `crypto_test.exs` |

#### UT-FILE: Files Module

| Test ID | Description | File |
|---------|-------------|------|
| UT-FILE-001 | File metadata creation | `files_test.exs` |
| UT-FILE-002 | File update | `files_test.exs` |
| UT-FILE-003 | File deletion | `files_test.exs` |
| UT-FILE-004 | Folder creation | `files_test.exs` |
| UT-FILE-005 | Folder hierarchy | `files_test.exs` |
| UT-FILE-006 | File move operation | `files_test.exs` |
| UT-FILE-007 | Folder move operation | `files_test.exs` |
| UT-FILE-008 | Root folder access | `files_test.exs` |
| UT-FILE-009 | Children enumeration | `files_test.exs` |
| UT-FILE-010 | File size validation | `files_test.exs` |

#### UT-SHARE: Sharing Module

| Test ID | Description | File |
|---------|-------------|------|
| UT-SHARE-001 | Share creation (file) | `sharing_test.exs` |
| UT-SHARE-002 | Share creation (folder) | `sharing_test.exs` |
| UT-SHARE-003 | Permission levels (view/edit) | `sharing_test.exs` |
| UT-SHARE-004 | Share revocation | `sharing_test.exs` |
| UT-SHARE-005 | Expiry date handling | `sharing_test.exs` |
| UT-SHARE-006 | Received shares listing | `sharing_test.exs` |
| UT-SHARE-007 | Created shares listing | `sharing_test.exs` |
| UT-SHARE-008 | Permission update | `sharing_test.exs` |
| UT-SHARE-009 | Cascade delete (folder share) | `sharing_test.exs` |
| UT-SHARE-010 | Share with encrypted key | `sharing_test.exs` |

#### UT-DEV: Devices Module

| Test ID | Description | File |
|---------|-------------|------|
| UT-DEV-001 | Device enrollment | `devices_test.exs` |
| UT-DEV-002 | Device listing | `devices_test.exs` |
| UT-DEV-003 | Device update | `devices_test.exs` |
| UT-DEV-004 | Device deletion | `devices_test.exs` |
| UT-DEV-005 | Push token registration | `devices_test.exs` |
| UT-DEV-006 | Device key storage | `devices_test.exs` |
| UT-DEV-007 | Device limit per user | `devices_test.exs` |

#### UT-RECV: Recovery Module

| Test ID | Description | File |
|---------|-------------|------|
| UT-RECV-001 | Recovery setup (Shamir split) | `recovery_test.exs` |
| UT-RECV-002 | Trustee share creation | `recovery_test.exs` |
| UT-RECV-003 | Trustee share acceptance | `recovery_test.exs` |
| UT-RECV-004 | Trustee share rejection | `recovery_test.exs` |
| UT-RECV-005 | Recovery request creation | `recovery_test.exs` |
| UT-RECV-006 | Trustee approval | `recovery_test.exs` |
| UT-RECV-007 | Recovery completion | `recovery_test.exs` |
| UT-RECV-008 | Threshold validation (k-of-n) | `recovery_test.exs` |
| UT-RECV-009 | Recovery share revocation | `recovery_test.exs` |
| UT-RECV-010 | Recovery request cancellation | `recovery_test.exs` |

#### UT-INV: Invitations Module

| Test ID | Description | File |
|---------|-------------|------|
| UT-INV-001 | Invitation creation | `invitations_test.exs` |
| UT-INV-002 | Invitation token generation | `invitations_test.exs` |
| UT-INV-003 | Invitation acceptance | `invitations_test.exs` |
| UT-INV-004 | Invitation revocation | `invitations_test.exs` |
| UT-INV-005 | Invitation expiry | `invitations_test.exs` |
| UT-INV-006 | Invitation resend | `invitations_test.exs` |
| UT-INV-007 | Email validation | `invitations_test.exs` |

#### UT-AUDIT: Audit Module

| Test ID | Description | File |
|---------|-------------|------|
| UT-AUDIT-001 | Event logging | `audit_test.exs` |
| UT-AUDIT-002 | Event types | `audit_test.exs` |
| UT-AUDIT-003 | Actor attribution | `audit_test.exs` |
| UT-AUDIT-004 | Metadata storage | `audit_test.exs` |
| UT-AUDIT-005 | Event querying | `audit_test.exs` |

#### UT-STORE: Storage Module

| Test ID | Description | File |
|---------|-------------|------|
| UT-STORE-001 | Local storage upload | `storage/local_provider_test.exs` |
| UT-STORE-002 | Local storage download | `storage/local_provider_test.exs` |
| UT-STORE-003 | Local storage delete | `storage/local_provider_test.exs` |
| UT-STORE-004 | Presigned URL generation | `storage/storage_test.exs` |
| UT-STORE-005 | Storage provider selection | `storage/storage_test.exs` |

#### UT-CACHE: Cache Module

| Test ID | Description | File |
|---------|-------------|------|
| UT-CACHE-001 | Cache put | `cache_test.exs` |
| UT-CACHE-002 | Cache get | `cache_test.exs` |
| UT-CACHE-003 | Cache delete | `cache_test.exs` |
| UT-CACHE-004 | Cache TTL expiry | `cache_test.exs` |
| UT-CACHE-005 | Cache invalidation | `cache_test.exs` |

#### UT-TENANT: Multi-tenancy

| Test ID | Description | File |
|---------|-------------|------|
| UT-TENANT-001 | Tenant creation | `multi_tenancy_test.exs` |
| UT-TENANT-002 | Tenant isolation | `multi_tenancy_test.exs` |
| UT-TENANT-003 | Cross-tenant access denied | `multi_tenancy_test.exs` |
| UT-TENANT-004 | Tenant switching | `multi_tenancy_test.exs` |
| UT-TENANT-005 | Tenant member roles | `multi_tenancy_test.exs` |
| UT-TENANT-006 | Tenant data scoping | `multi_tenancy_test.exs` |

---

### 5.2 Integration Tests (IT)

#### IT-AUTH: Authentication Flow

| Test ID | Description | File |
|---------|-------------|------|
| IT-AUTH-001 | POST /api/auth/register | `integration/registration_flow_test.exs` |
| IT-AUTH-002 | POST /api/auth/login | `integration/login_flow_test.exs` |
| IT-AUTH-003 | POST /api/auth/logout | `integration/login_flow_test.exs` |
| IT-AUTH-004 | POST /api/auth/refresh | `integration/login_flow_test.exs` |
| IT-AUTH-005 | Token expiration handling | `integration/login_flow_test.exs` |
| IT-AUTH-006 | Invalid credentials rejection | `integration/login_flow_test.exs` |

#### IT-FILE: File Operations

| Test ID | Description | File |
|---------|-------------|------|
| IT-FILE-001 | Full upload flow (URL → upload → confirm) | `integration/full_upload_flow_test.exs` |
| IT-FILE-002 | Full download flow (request → URL → download) | `integration/download_flow_test.exs` |
| IT-FILE-003 | File CRUD via API | `integration/full_upload_flow_test.exs` |
| IT-FILE-004 | Folder CRUD via API | `integration/full_upload_flow_test.exs` |
| IT-FILE-005 | File move between folders | `integration/full_upload_flow_test.exs` |

#### IT-SHARE: Sharing Flow

| Test ID | Description | File |
|---------|-------------|------|
| IT-SHARE-001 | Full share flow (create → accept → access) | `integration/full_share_flow_test.exs` |
| IT-SHARE-002 | Share revocation flow | `integration/revoke_access_flow_test.exs` |
| IT-SHARE-003 | Permission update flow | `integration/full_share_flow_test.exs` |
| IT-SHARE-004 | Expiry enforcement | `integration/full_share_flow_test.exs` |

#### IT-RECV: Recovery Flow

| Test ID | Description | File |
|---------|-------------|------|
| IT-RECV-001 | Full recovery setup flow | `integration/full_recovery_flow_test.exs` |
| IT-RECV-002 | Trustee approval flow | `integration/full_recovery_flow_test.exs` |
| IT-RECV-003 | Recovery completion flow | `integration/full_recovery_flow_test.exs` |
| IT-RECV-004 | Threshold met verification | `integration/full_recovery_flow_test.exs` |

#### IT-INV: Invitation Flow

| Test ID | Description | File |
|---------|-------------|------|
| IT-INV-001 | Full invitation flow (send → accept → onboard) | `integration/invitation_flow_test.exs` |
| IT-INV-002 | Invitation rejection flow | `integration/invitation_flow_test.exs` |
| IT-INV-003 | Invitation resend flow | `integration/invitation_flow_test.exs` |

#### IT-API: API Controllers

| Test ID | Description | File |
|---------|-------------|------|
| IT-API-001 | Health endpoints | `controllers/health_controller_test.exs` |
| IT-API-002 | Error response format | `controllers/error_json_test.exs` |
| IT-API-003 | Invitation controller | `controllers/api/invitation_controller_test.exs` |
| IT-API-004 | Invite controller | `controllers/api/invite_controller_test.exs` |

#### IT-WS: WebSocket Channels

| Test ID | Description | File |
|---------|-------------|------|
| IT-WS-001 | User socket authentication | `channels/user_socket_test.exs` |
| IT-WS-002 | Folder channel (real-time updates) | `channels/folder_channel_test.exs` |
| IT-WS-003 | Notification channel | `channels/notification_channel_test.exs` |

---

### 5.3 Security Tests (SEC)

#### SEC-AUTH: Authentication Security

| Test ID | Description | Priority |
|---------|-------------|----------|
| SEC-AUTH-001 | JWT token validation | P0 |
| SEC-AUTH-002 | Token expiration enforcement | P0 |
| SEC-AUTH-003 | Token blocklist after logout | P0 |
| SEC-AUTH-004 | Rate limiting on auth endpoints | P0 |
| SEC-AUTH-005 | Password strength requirements | P1 |
| SEC-AUTH-006 | Brute force protection | P0 |

**File:** `auth/token_blocklist_test.exs`

#### SEC-ACCESS: Access Control

| Test ID | Description | Priority |
|---------|-------------|----------|
| SEC-ACCESS-001 | Unauthenticated access denied | P0 |
| SEC-ACCESS-002 | Cross-tenant access denied | P0 |
| SEC-ACCESS-003 | File owner verification | P0 |
| SEC-ACCESS-004 | Share permission enforcement | P0 |
| SEC-ACCESS-005 | Admin-only endpoint protection | P0 |
| SEC-ACCESS-006 | Device ownership verification | P1 |

#### SEC-CRYPTO: Cryptographic Security

| Test ID | Description | Priority |
|---------|-------------|----------|
| SEC-CRYPTO-001 | Key entropy verification | P0 |
| SEC-CRYPTO-002 | No private key exposure in API | P0 |
| SEC-CRYPTO-003 | Encrypted key storage | P0 |
| SEC-CRYPTO-004 | Signature verification on operations | P0 |
| SEC-CRYPTO-005 | Key rotation support | P1 |

#### SEC-DATA: Data Protection

| Test ID | Description | Priority |
|---------|-------------|----------|
| SEC-DATA-001 | No plaintext secrets in logs | P0 |
| SEC-DATA-002 | Sensitive fields excluded from JSON | P0 |
| SEC-DATA-003 | Database encryption at rest | P1 |
| SEC-DATA-004 | Secure session handling | P0 |

#### SEC-INPUT: Input Validation

| Test ID | Description | Priority |
|---------|-------------|----------|
| SEC-INPUT-001 | SQL injection prevention | P0 |
| SEC-INPUT-002 | XSS prevention | P0 |
| SEC-INPUT-003 | Path traversal prevention | P0 |
| SEC-INPUT-004 | File upload validation | P0 |
| SEC-INPUT-005 | JSON depth/size limits | P1 |

---

### 5.4 End-to-End Tests (E2E)

| Test ID | Description | File |
|---------|-------------|------|
| E2E-001 | User registration → Login → Upload → Share → Download | `integration/full_share_flow_test.exs` |
| E2E-002 | Registration → Device enrollment → Key setup | `integration/registration_flow_test.exs` |
| E2E-003 | Upload → Share → Revoke → Access denied | `integration/revoke_access_flow_test.exs` |
| E2E-004 | Recovery setup → Request → Approve → Complete | `integration/full_recovery_flow_test.exs` |
| E2E-005 | Invitation → Accept → Join tenant → Access files | `integration/invitation_flow_test.exs` |
| E2E-006 | Login → Upload → Move → Download | `integration/full_upload_flow_test.exs` |
| E2E-007 | Create folder → Add files → Share folder | `integration/full_share_flow_test.exs` |
| E2E-008 | Multi-device sync (upload on A, access on B) | `integration/download_flow_test.exs` |

---

### 5.5 LiveView Tests (LV)

| Test ID | Description | File |
|---------|-------------|------|
| LV-001 | Admin dashboard rendering | `live/admin/dashboard_live_test.exs` |
| LV-002 | User management CRUD | `live/admin/user_live_test.exs` |
| LV-003 | Tenant management CRUD | `live/admin/tenant_live_test.exs` |
| LV-004 | Admin authentication | `live/admin/login_live_test.exs` |

---

### 5.6 Performance Tests (PERF)

| Test ID | Description | Target |
|---------|-------------|--------|
| PERF-001 | Authentication latency (p95) | < 100ms |
| PERF-002 | File metadata retrieval (p95) | < 50ms |
| PERF-003 | Share creation latency (p95) | < 100ms |
| PERF-004 | Presigned URL generation (p95) | < 50ms |
| PERF-005 | Concurrent users (100 parallel) | No errors |
| PERF-006 | Database query performance | < 10ms avg |
| PERF-007 | WebSocket connection handling | 1000+ concurrent |

---

## 6. Test Matrix

### 6.1 Feature Coverage Matrix

| Feature | Unit | Integration | Security | E2E | LiveView |
|---------|:----:|:-----------:|:--------:|:---:|:--------:|
| User Registration | ✅ | ✅ | ✅ | ✅ | ⬜ |
| Authentication | ✅ | ✅ | ✅ | ✅ | ⬜ |
| Multi-tenancy | ✅ | ✅ | ✅ | ✅ | ✅ |
| File Management | ✅ | ✅ | ✅ | ✅ | ⬜ |
| Folder Hierarchy | ✅ | ✅ | ⬜ | ✅ | ⬜ |
| Sharing | ✅ | ✅ | ✅ | ✅ | ⬜ |
| Device Management | ✅ | ✅ | ✅ | ⬜ | ⬜ |
| Social Recovery | ✅ | ✅ | ⬜ | ✅ | ⬜ |
| Invitations | ✅ | ✅ | ⬜ | ✅ | ⬜ |
| Notifications | ⬜ | ✅ | ⬜ | ⬜ | ⬜ |
| Cryptography | ✅ | ⬜ | ✅ | ⬜ | ⬜ |
| Admin Portal | ⬜ | ⬜ | ⬜ | ⬜ | ✅ |

### 6.2 API Endpoint Coverage

| Endpoint Group | Endpoints | Unit | Integration | Security |
|----------------|-----------|:----:|:-----------:|:--------:|
| `/api/auth/*` | 5 | ✅ | ✅ | ✅ |
| `/api/tenants/*` | 8 | ✅ | ✅ | ✅ |
| `/api/invitations/*` | 4 | ✅ | ✅ | ⬜ |
| `/api/me/*` | 4 | ✅ | ⬜ | ✅ |
| `/api/users/*` | 2 | ✅ | ⬜ | ✅ |
| `/api/devices/*` | 7 | ✅ | ⬜ | ✅ |
| `/api/folders/*` | 8 | ✅ | ✅ | ✅ |
| `/api/files/*` | 6 | ✅ | ✅ | ✅ |
| `/api/shares/*` | 7 | ✅ | ✅ | ✅ |
| `/api/recovery/*` | 12 | ✅ | ✅ | ⬜ |
| `/api/notifications/*` | 5 | ⬜ | ⬜ | ⬜ |
| `/health/*` | 2 | ✅ | ✅ | ⬜ |

---

## 7. Acceptance Criteria

### 7.1 Release Criteria

| Criterion | Target | Status |
|-----------|--------|--------|
| Unit test pass rate | 100% | TBD |
| Integration test pass rate | 100% | TBD |
| Security test pass rate | 100% | TBD |
| Code coverage (lines) | > 80% | TBD |
| Critical bugs | 0 | TBD |
| High bugs | 0 | TBD |
| Performance SLA met | Yes | TBD |

### 7.2 Security Criteria

| Criterion | Required |
|-----------|----------|
| No authentication bypass | ✅ Required |
| Cross-tenant isolation verified | ✅ Required |
| No private key exposure | ✅ Required |
| Rate limiting enforced | ✅ Required |
| SQL injection prevented | ✅ Required |
| Token blocklist working | ✅ Required |

### 7.3 Performance Criteria

| Metric | Target |
|--------|--------|
| API response time (p95) | < 100ms |
| Authentication latency | < 100ms |
| Database queries | < 10ms avg |
| WebSocket connections | 1000+ concurrent |
| Memory usage (idle) | < 256MB |

---

## 8. Test Environment

### 8.1 Dependencies

```yaml
# Required services
PostgreSQL: 15+
MinIO: latest (S3-compatible, for integration tests)
Redis: 7+ (optional, for distributed cache)

# Native dependencies
Rust: 1.70+ (for PQC NIFs)
OpenSSL: 3.x
```

### 8.2 Environment Variables

```bash
# Test environment
export MIX_ENV=test
export DATABASE_URL=postgres://localhost/secure_sharing_test
export JWT_SECRET=test_secret_key_minimum_32_characters
export SECRET_KEY_BASE=test_secret_key_base_minimum_64_chars_for_phoenix
export S3_BUCKET=secure-sharing-test
export S3_ENDPOINT=http://localhost:9000
export S3_ACCESS_KEY=minioadmin
export S3_SECRET_KEY=minioadmin
```

### 8.3 Database Setup

```bash
# Create and migrate test database
mix ecto.create
mix ecto.migrate

# Reset database
mix ecto.reset

# Run with fresh DB
MIX_ENV=test mix ecto.reset && mix test
```

### 8.4 Native Dependencies

```bash
# Build PQC NIFs (required before running tests)
cd native/kaz_kem && cargo build --release
cd native/kaz_sign && cargo build --release
cd native/ml_kem && cargo build --release
cd native/ml_dsa && cargo build --release
```

---

## 9. Running Tests

### 9.1 Quick Commands

```bash
# Run all tests
mix test

# Run with coverage
mix coveralls.html

# Run specific test file
mix test test/secure_sharing/accounts_test.exs

# Run specific test line
mix test test/secure_sharing/accounts_test.exs:42

# Run integration tests only
mix test test/integration/

# Run with verbose output
mix test --trace

# Run failed tests only
mix test --failed

# Run excluding slow tests
mix test --exclude slow

# Run only tagged tests
mix test --only integration
mix test --only crypto
```

### 9.2 CI Pipeline

```bash
# Full CI run
mix deps.get
mix compile --warnings-as-errors
mix format --check-formatted
mix credo --strict
mix test --cover

# Security-focused run
mix test test/secure_sharing_web/auth/
mix test --only security

# Integration tests
mix test test/integration/
```

### 9.3 Pre-commit Hook

```bash
# Run precommit alias (compile + format + test)
mix precommit
```

---

## 10. Regression Checklist

### 10.1 Pre-Release Checklist

- [ ] All unit tests pass (`mix test test/secure_sharing/`)
- [ ] All integration tests pass (`mix test test/integration/`)
- [ ] All controller tests pass (`mix test test/secure_sharing_web/`)
- [ ] All LiveView tests pass (`mix test test/secure_sharing_web/live/`)
- [ ] Code coverage > 80% (`mix coveralls`)
- [ ] No compiler warnings (`mix compile --warnings-as-errors`)
- [ ] Code formatted (`mix format --check-formatted`)
- [ ] Credo passes (`mix credo --strict`)
- [ ] Database migrations clean (`mix ecto.reset`)
- [ ] API documentation updated

### 10.2 Critical Path Tests

Run these tests before any deployment:

```bash
# Authentication
mix test test/integration/login_flow_test.exs
mix test test/secure_sharing_web/auth/token_blocklist_test.exs

# Core features
mix test test/integration/full_upload_flow_test.exs
mix test test/integration/full_share_flow_test.exs
mix test test/integration/full_recovery_flow_test.exs

# Security
mix test test/secure_sharing/multi_tenancy_test.exs
mix test test/secure_sharing/crypto_test.exs
```

### 10.3 Smoke Tests

```bash
# Minimal verification after deployment
curl -s http://localhost:4000/health | jq .
curl -s http://localhost:4000/health/ready | jq .
```

---

## 11. Test Data

### 11.1 Factory Definitions

Located in `test/support/factory.ex`:

```elixir
# Available factories
:user          # Basic user with tenant
:tenant        # Organization/workspace
:device        # User device with keys
:folder        # Folder in hierarchy
:file          # File metadata
:share         # File/folder share
:invitation    # User invitation
:recovery_config  # Recovery setup
:recovery_share   # Trustee share
```

### 11.2 Test Fixtures

```
test/support/
├── factory.ex           # ExMachina factories
├── conn_case.ex         # Controller test setup
├── data_case.ex         # Database test setup
├── channel_case.ex      # WebSocket test setup
└── fixtures/            # Static test files
    ├── sample.pdf
    ├── sample.docx
    └── test_image.png
```

---

## 12. Test File Index

```
test/
├── integration/
│   ├── full_share_flow_test.exs
│   ├── registration_flow_test.exs
│   ├── full_upload_flow_test.exs
│   ├── full_recovery_flow_test.exs
│   ├── login_flow_test.exs
│   ├── revoke_access_flow_test.exs
│   ├── download_flow_test.exs
│   └── invitation_flow_test.exs
├── secure_sharing/
│   ├── accounts_test.exs
│   ├── audit_test.exs
│   ├── cache_test.exs
│   ├── crypto_test.exs
│   ├── devices_test.exs
│   ├── factory_test.exs
│   ├── files_test.exs
│   ├── invitations_test.exs
│   ├── migrations_test.exs
│   ├── multi_tenancy_test.exs
│   ├── recovery_test.exs
│   ├── schema_constraints_test.exs
│   ├── sharing_test.exs
│   └── storage/
│       ├── local_provider_test.exs
│       └── storage_test.exs
├── secure_sharing_web/
│   ├── auth/
│   │   └── token_blocklist_test.exs
│   ├── channels/
│   │   ├── folder_channel_test.exs
│   │   ├── notification_channel_test.exs
│   │   └── user_socket_test.exs
│   ├── controllers/
│   │   ├── api/
│   │   │   ├── invitation_controller_test.exs
│   │   │   └── invite_controller_test.exs
│   │   ├── error_json_test.exs
│   │   └── health_controller_test.exs
│   ├── helpers/
│   │   ├── binary_helpers_test.exs
│   │   └── pagination_helpers_test.exs
│   └── live/admin/
│       ├── dashboard_live_test.exs
│       ├── tenant_live_test.exs
│       └── user_live_test.exs
├── support/
│   ├── channel_case.ex
│   ├── conn_case.ex
│   ├── data_case.ex
│   ├── email_preview.exs
│   └── factory.ex
└── test_helper.exs
```

---

## 13. Gap Analysis

### 13.1 Missing Test Coverage

| Area | Gap | Priority | Action |
|------|-----|----------|--------|
| Notification API | No controller tests | P1 | Create tests |
| Device API | No integration tests | P1 | Create tests |
| Performance | No benchmarks | P2 | Create benchmark suite |
| Security | No penetration tests | P1 | Create security tests |
| API Rate Limiting | Limited coverage | P1 | Add rate limit tests |

### 13.2 Recommended Additions

1. **Create `test/secure_sharing_web/controllers/api/` tests for:**
   - `auth_controller_test.exs`
   - `tenant_controller_test.exs`
   - `user_controller_test.exs`
   - `device_controller_test.exs`
   - `folder_controller_test.exs`
   - `file_controller_test.exs`
   - `share_controller_test.exs`
   - `recovery_controller_test.exs`
   - `notification_controller_test.exs`

2. **Create `test/secure_sharing/security/` for:**
   - `access_control_test.exs`
   - `input_validation_test.exs`
   - `rate_limiting_test.exs`

3. **Create `test/secure_sharing/performance/` for:**
   - `api_latency_test.exs`
   - `database_query_test.exs`
   - `concurrent_load_test.exs`

---

## Changelog

| Version | Date | Author | Changes |
|---------|------|--------|---------|
| 1.0 | 2026-01-24 | Claude | Initial comprehensive test plan |
