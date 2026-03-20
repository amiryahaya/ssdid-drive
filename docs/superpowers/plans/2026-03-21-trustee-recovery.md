# Trustee-Based Recovery — Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Enable social recovery where a user distributes encrypted key shares to trusted contacts (trustees) who can collectively approve account recovery when the user is locked out.

**Architecture:** User splits master key via Shamir 3-of-5 → encrypts each share for a trustee → stores shares on backend. When locked out, user initiates recovery request → backend notifies trustees → trustees approve and release their shares → user collects threshold shares → reconstructs key → completes recovery.

**Tech Stack:** .NET 10 (backend), Swift/UIKit (iOS)

---

## Flow

```
  SETUP (authenticated user):
  ┌─────────────────────────────────────────────────┐
  │ 1. User selects 3-5 trustees (org members)      │
  │ 2. Shamir split: masterKey → 5 shares (3-of-5)  │
  │ 3. Encrypt each share for trustee's public key   │
  │ 4. POST /api/recovery/trustees/setup             │
  │    → stores encrypted shares + trustee records   │
  └─────────────────────────────────────────────────┘

  RECOVERY (locked-out user):
  ┌─────────────────────────────────────────────────┐
  │ 1. POST /api/recovery/requests (unauthenticated)│
  │    → creates recovery request, notifies trustees│
  │ 2. Trustees see pending requests in their app   │
  │ 3. Each trustee: POST /api/recovery/requests/   │
  │    {id}/approve → releases their encrypted share│
  │ 4. Once 3+ approve:                             │
  │    GET /api/recovery/requests/{id}/shares        │
  │    → returns all released shares                │
  │ 5. Client decrypts shares, reconstructs key     │
  │ 6. POST /api/recovery/complete (existing)       │
  └─────────────────────────────────────────────────┘
```

## New DB Entities

### RecoveryTrustee
```
Id (Guid), RecoverySetupId (FK), TrusteeUserId (FK),
EncryptedShare (byte[]), ShareIndex (int),
HasAccepted (bool), AcceptedAt (DateTimeOffset?),
CreatedAt (DateTimeOffset)
```

### RecoveryRequest
```
Id (Guid), RequesterId (FK → User),
RecoverySetupId (FK → RecoverySetup),
Status (enum: Pending, Approved, Rejected, Expired, Completed),
ApprovedCount (int), RequiredCount (int),
ExpiresAt (DateTimeOffset), CreatedAt (DateTimeOffset)
```

### RecoveryRequestApproval
```
Id (Guid), RecoveryRequestId (FK), TrusteeUserId (FK),
Decision (enum: Approved, Rejected), DecidedAt (DateTimeOffset)
```

## Backend Endpoints (7 total)

### Chunk 1: Entities + Migration

**Task 1:** Create entities, DbContext config, migration

### Chunk 2: Trustee Setup

**Task 2:** `POST /api/recovery/trustees/setup` — authenticated
- Request: `{ threshold, shares: [{ trustee_user_id, encrypted_share, share_index }] }`
- Validates: all trustees are org members, threshold ≤ shares count
- Creates RecoveryTrustee records, updates RecoverySetup

**Task 3:** `GET /api/recovery/trustees` — authenticated
- Returns list of user's designated trustees with acceptance status

### Chunk 3: Recovery Request Flow

**Task 4:** `POST /api/recovery/requests` — unauthenticated (rate-limited)
- Request: `{ did, key_proof }`
- Creates RecoveryRequest with 48h expiry
- Sends notifications to all trustees

**Task 5:** `GET /api/recovery/requests/pending` — authenticated (trustee view)
- Returns recovery requests where current user is a trustee

**Task 6:** `POST /api/recovery/requests/{id}/approve` — authenticated (trustee)
- Trustee approves → increments ApprovedCount
- When threshold met → status changes to Approved

**Task 7:** `POST /api/recovery/requests/{id}/reject` — authenticated (trustee)
- Trustee rejects

**Task 8:** `GET /api/recovery/requests/{id}/shares` — unauthenticated (rate-limited)
- Only returns shares if request status = Approved
- Returns all released encrypted shares for the requester to decrypt

### Chunk 4: iOS Wiring

**Task 9:** Wire iOS stubs to real endpoints in RecoveryRepositoryImpl

**Task 10:** Wire TrusteeSelectionViewModel to use setup endpoint

**Task 11:** Wire InitiateRecoveryViewModel to use request endpoints

**Task 12:** Wire PendingRequestsViewModel to use trustee endpoints
