# Admin Portal — Invite User to Tenant

## Summary

Add the ability for SuperAdmins to invite users as tenant Owner or Admin from the admin portal. The invite UI lives on the existing TenantDetailPage, reusing the existing invitation infrastructure (code generation, accept/decline flow).

## Role Matrix

| Action | SuperAdmin | Owner | Admin | Member |
|---|---|---|---|---|
| **Platform** | | | | |
| Create tenant | Yes | - | - | - |
| Edit/disable tenant | Yes | - | - | - |
| View all users | Yes | - | - | - |
| Suspend/activate user | Yes | - | - | - |
| Assign SuperAdmin role | Yes | - | - | - |
| View audit log | Yes | - | - | - |
| **Tenant Invitations** | | | | |
| Invite Owner | Yes | - | - | - |
| Invite Admin | Yes | Yes | - | - |
| Invite Member | -* | Yes | Yes | - |
| Revoke invitation | Yes (own) | Yes (own) | Yes (own) | - |
| **Tenant Members** | | | | |
| View members | Yes | Yes | Yes | Yes |
| Change role to Owner | - | Yes | - | - |
| Change role to Admin | - | Yes | - | - |
| Change role to Member | - | Yes | Yes* | - |
| Remove member | - | Yes | Yes* | - |

*Admin can only manage Members, not other Admins or Owners. SuperAdmin does not invite Members — that's the responsibility of tenant Owners/Admins via the desktop client.

## Backend

### New Endpoints (under `/api/admin/tenants/{tenantId}/invitations`)

**`POST /api/admin/tenants/{tenantId}/invitations`** — Create invitation

- Request: `{ "email": "user@example.com", "role": "owner" | "admin", "message?": "optional text" }`
- `email` is required (unlike tenant-scoped invitations where it's optional)
- Validates: tenant exists, email format, role is owner or admin only
- Rejects if a pending invitation already exists for the same email + tenant
- Rejects if the user is already a member of the tenant
- Reuses existing `Invitation` entity, sets SuperAdmin as `InvitedById`
- Generates same short code + token as existing invitations (looks up tenant slug via route param `{tenantId}`)
- Sends email notification if email service is configured; creates in-app notification if user exists
- Response: invitation object with `short_code`
- Errors: 400 (validation), 404 (tenant not found), 409 (duplicate invitation / already a member)

**`GET /api/admin/tenants/{tenantId}/invitations`** — List invitations

- Returns all invitations for the tenant (any status)
- Query params: `page` (default 1), `page_size` (default 20)
- Response: `{ "items": [...], "page": 1, "page_size": 20, "total": N }` (matches existing admin API conventions)

**`DELETE /api/admin/tenants/{tenantId}/invitations/{id}`** — Revoke invitation

- Only revokes pending invitations
- Returns 404 if invitation doesn't belong to the tenant

### Key Design Decisions

- Separate admin endpoint bypasses the existing `CreateInvitation.cs` role restriction (which rejects "owner" role)
- The SuperAdmin does NOT need to be a member of the tenant to create invitations
- The accept/decline flow remains unchanged — invitees use the desktop/mobile client with the same code
- The existing `AcceptInvitation` endpoint already handles adding users with Owner role

## Frontend (Admin Portal)

### New Files

- `clients/admin/src/components/InviteUserDialog.tsx` — Modal dialog with:
  - Email input (required)
  - Owner/Admin role toggle (defaults to Owner)
  - Optional message field (500 char limit)
  - Success state showing invite code with copy button and expiry

### Modified Files

- `clients/admin/src/pages/TenantDetailPage.tsx`:
  - "Invite User" button next to Members heading
  - New "Pending Invitations" section below members table
  - Revoke button per invitation with confirmation prompt
  - Empty state when no pending invitations

- `clients/admin/src/stores/adminStore.ts`:
  - `tenantInvitations: AdminInvitation[]`
  - `tenantInvitationsLoading: boolean`
  - `createAdminInvitation(tenantId, email, role, message?)`
  - `fetchTenantInvitations(tenantId)`
  - `revokeAdminInvitation(tenantId, invitationId)`

### UX Details

- Invitations auto-refresh after create/revoke
- Role toggle defaults to Owner (primary use case: bootstrapping new tenants)
- Success state shows code with copy-to-clipboard
- Revoke has confirmation prompt
- Empty state message when no pending invitations

## Testing

### Backend

- SuperAdmin can create Owner invitation for a tenant
- SuperAdmin can create Admin invitation for a tenant
- SuperAdmin cannot create Member invitation (rejected)
- Non-SuperAdmin gets 403
- Listing invitations returns only that tenant's invitations
- Revoking a pending invitation works
- Revoking an already-accepted invitation fails
- Accepting a SuperAdmin-created Owner invitation adds user as Owner
- Duplicate pending invitation for same email + tenant returns 409
- Inviting an existing tenant member returns 409

### Frontend

- InviteUserDialog renders with email, role toggle, message fields
- Role toggle switches between Owner and Admin
- Submit calls createAdminInvitation with correct params
- Success state shows invite code with copy button
- TenantDetailPage shows "Invite User" button
- Pending invitations table renders with revoke buttons
- Revoke triggers confirmation before calling API
- Empty state when no pending invitations
