# Invitation & Onboarding Design

## Overview

Invite-only onboarding for SSDID Drive targeting enterprise B2B. No open registration. All users enter through invitations. Authentication supports three methods: Email+TOTP, OIDC (Google/Microsoft), and SSDID Wallet.

## Principles

- **Invite-only** — no self-registration, no open sign-up
- **Top-down tenant creation** — users request tenants, SuperAdmin approves (requester auto-becomes Owner)
- **Multi-auth** — Email+TOTP, OIDC (Google/Microsoft), SSDID Wallet — all 3 supported for invitation acceptance
- **Multi-tenant** — a user can belong to multiple tenants via separate invitations
- **Email-verified** — invitation email must match the accepting user's email across all auth methods

## Roles & Permissions

| Role | Scope | Can Invite | Can Manage Members | Created By |
|------|-------|------------|-------------------|------------|
| SuperAdmin | System-wide (admin portal) | Owners (to any tenant) | All users | `AdminDid` in appsettings |
| Owner | Tenant (inside app) | Admins, Members | Yes | SuperAdmin invite |
| Admin | Tenant (inside app) | Members | View only | Owner invite |
| Member | Tenant (inside app) | No | No | Owner/Admin invite |

## Bootstrap Flow

```
1. Deploy SSDID Drive with AdminDid in appsettings
2. SuperAdmin registers with matching DID → auto-promoted
3. User registers (any auth method) and submits TenantRequest
4. SuperAdmin approves → tenant created + requester becomes Owner (automatic)
5. Owner invites Admins/Members (inside the app, via email)
6. Invitees accept using any auth method (Email+TOTP, OIDC, or Wallet)
```

## Invitation Flow

### Creating an Invitation

1. Owner/Admin opens "Invite" in the app (or SuperAdmin in admin portal)
2. Selects role (Owner can invite Admin/Member, Admin can invite Member only)
3. Server generates unique invite with:
   - **Short code**: `ACME-7K9X` (for manual entry)
   - **Link**: `https://drive.ssdid.my/invite/ACME-7K9X` (for sharing)
   - **QR code**: same link rendered as QR (for in-person)
4. Admin shares via any channel (WhatsApp, email, verbal, printed QR)

### Accepting an Invitation (New User)

```
Invitee receives code/link/QR
    ↓
Clicks link or scans QR
    ↓
App installed? → Opens app with invite pre-filled
App NOT installed? → Landing page: download links + displays code
    ↓
Opens SSDID Drive app
    ↓
Enters invite code (or pre-filled from deep link)
    ↓
App fetches invite details → shows "Join [Tenant] as [Role]?"
    ↓
User scans login QR with SSDID Wallet
    ↓
Wallet shows consent (requested_claims: name, email)
    ↓
Registration + accept invite in one flow:
  - Server creates User (no personal tenant)
  - Server validates invite token
  - Server creates UserTenant with invited role
  - Invite status → Accepted
    ↓
User lands in tenant workspace
```

### Accepting an Invitation (Existing User)

```
Existing user receives code/link/QR
    ↓
Opens app → enters invite code
    ↓
App fetches invite details → shows "Join [Tenant] as [Role]?"
    ↓
User confirms → POST /api/invitations/{id}/accept
    ↓
Server creates UserTenant → user now belongs to new tenant
    ↓
User switches to new tenant
```

## Invitation Properties

| Field | Description |
|-------|-------------|
| Token | Unique, URL-safe, 32 random bytes |
| Short Code | Human-readable format (e.g. `ACME-7K9X`) |
| Tenant | Which tenant the invite is for |
| Role | Member, Admin (Owner only via SuperAdmin) |
| Status | Pending, Accepted, Declined, Expired, Revoked |
| ExpiresAt | 7 days from creation (configurable) |
| InvitedBy | User who created the invite |
| Message | Optional invite message |

## Invitation Tracking

| Status | Meaning |
|--------|---------|
| Pending | Invited, hasn't accepted yet |
| Accepted | User joined the tenant |
| Declined | User explicitly declined |
| Expired | TTL passed without acceptance |
| Revoked | Inviter/admin cancelled |

No install tracking — we only know the outcome.

## What Exists (Already Built)

- `Invitation` entity with all fields above (except short code)
- `CreateInvitation` — generates token, checks caller role
- `AcceptInvitation` — validates, creates UserTenant, notifications
- `DeclineInvitation`, `RevokeInvitation`, `ListInvitations`
- `GetInvitationByToken` — public endpoint for resolving tokens
- `UserTenant` many-to-many with roles
- SSDID Wallet QR login flow
- `requested_claims` in QR payload

## What Needs to Be Built

### Backend

1. **Short code generation** — add human-readable code to Invitation (e.g. `ACME-7K9X`)
2. **Modify RegisterVerify** — accept `invite_token`, skip personal tenant creation, join invite tenant instead
3. **Enforce invite-only** — reject registration without valid invite token
4. **Invite role constraints** — Owner can invite Admin/Member, Admin can invite Member only
5. **Landing page invite route** — `/invite/{code}` resolves to app deep link or download page
6. **Switch tenant endpoint** — `POST /api/users/switch-tenant/{tenantId}`

### Desktop/Mobile App

7. **Invite code entry screen** — first-launch or "Join Tenant" flow
8. **Invitation management UI** — Owner/Admin can create, list, revoke invitations
9. **Member management UI** — Owner can view/remove members, change roles
10. **Tenant switcher** — switch between tenants user belongs to

### Admin Portal

11. **Invitation creation for tenants** — SuperAdmin creates first Owner invite

## Future (Not Now)

- **Organizations** — sub-units under tenants, hierarchical structure
- **Organization-level roles** — separate from tenant roles
- **Self-service organization creation** — users request, admin approves
