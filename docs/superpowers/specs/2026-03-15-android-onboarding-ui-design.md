# Android Onboarding UI Improvements — Design Spec

## Goal

Complete the Android onboarding loop for enterprise B2B users by adding missing UI screens and extending existing ones to support all 3 auth methods (Email+TOTP, OIDC, SSDID Wallet) across invitation acceptance, organization requests, and team invitations.

## Context

The backend now supports:
- 3 auth methods for invitation acceptance (Email+TOTP, OIDC with `invitation_token`, Wallet)
- `InvitationAcceptanceService` with unified validation
- TenantRequest submission and approval
- Invitation creation with `email_sent` status and audit logging

The Android client is missing UI for several of these flows, and the invitation acceptance screen only supports wallet auth.

## Scope

4 changes, ordered by priority:

1. **Extend InviteAcceptScreen** — add Email+TOTP and OIDC auth methods (currently wallet-only)
2. **Extend LoginScreen** — add "Have an invite code?" and "Request organization" entry points
3. **New TenantRequestScreen** — form to request an organization
4. **New InviteTeamScreen** — form for Owner/Admin to invite members

## Architecture

All screens follow the existing pattern:
- `*Screen.kt` (Composable) + `*ViewModel.kt` (Hilt `@HiltViewModel`)
- `data class *UiState` for state management
- Repository layer for API calls
- Material 3 theme with existing color scheme

### Navigation Changes

```
NavGraph additions:
  Screen.TenantRequest    → "tenant-request"
  Screen.InviteTeam       → "invite-team"

Modified screens:
  LoginScreen             → adds navigation links to JoinTenant + TenantRequest
  InviteAcceptScreen      → adds Email+TOTP and OIDC acceptance buttons
  SettingsScreen          → adds "Invite Team Member" menu item (Owner/Admin only)
```

---

## Screen 1: InviteAcceptScreen Extension

**File:** `presentation/auth/InviteAcceptScreen.kt` (modify existing)
**File:** `presentation/auth/InviteAcceptViewModel.kt` (modify existing)

### Current Behavior
Shows invitation details + single "Accept with SSDID Wallet" button.

### New Behavior
Shows invitation details card at top, then all auth methods below:

```
┌─────────────────────────────┐
│   You're invited to         │
│   join "Acme Corp"          │
│   as Member                 │
│   Invited by: John Doe      │
│   Email: you@acme.com       │
│   "Welcome to the team!"    │
├─────────────────────────────┤
│                             │
│  Already have an account?   │
│  [Sign In to Accept]        │ ← for existing users
│                             │
│  ── or create account ──    │
│                             │
│  [Continue with Email]      │ ← email registration + invitation
│  [Sign in with Google]      │ ← OIDC registration + invitation
│  [Sign in with Microsoft]   │ ← OIDC registration + invitation
│  [Accept with SSDID Wallet] │ ← existing wallet flow
│                             │
└─────────────────────────────┘
```

### Auth Method Flows

**Email+TOTP path:**
1. User taps "Continue with Email"
2. Navigate to email registration flow with `invitationToken` parameter
3. `EmailRegister` → OTP verify → account created → invitation auto-accepted
4. Navigate to Files

**OIDC path:**
1. User taps "Sign in with Google/Microsoft"
2. Launch OIDC authorize with `invitation_token` query parameter
3. Server handles registration + invitation acceptance in `OidcCallback`
4. Redirect back to app with session token
5. Navigate to Files

**Wallet path:**
1. Existing flow (unchanged)

**Existing user path:**
1. User taps "Sign In to Accept"
2. Navigate to LoginScreen with `returnTo=invite/{token}` parameter
3. After login, navigate back to InviteAcceptScreen
4. Auto-accept invitation using existing session (POST `/api/invitations/{id}/accept`)

### State Changes

```kotlin
data class InviteAcceptUiState(
    val token: String = "",
    val invitation: TokenInvitation? = null,
    val isLoadingInvitation: Boolean = true,
    val invitationError: String? = null,
    // Auth method states
    val selectedAuthMethod: AuthMethod? = null, // Email, Google, Microsoft, Wallet
    val isLoading: Boolean = false,
    val isWaitingForWallet: Boolean = false,
    val isAccepted: Boolean = false,
    val error: String? = null
)
```

---

## Screen 2: LoginScreen Extension

**File:** `presentation/auth/LoginScreen.kt` (modify existing)

### Changes

Add two navigation links to the existing LoginScreen:

**Top of screen (before email field):**
```
┌─────────────────────────────┐
│  ┌───────────────────────┐  │
│  │ Have an invite code?  │  │
│  │ [Enter Code →]        │  │
│  └───────────────────────┘  │
│                             │
│  ── or sign in ──           │
│  ... existing auth UI ...   │
```

This is an `OutlinedCard` with a `TextButton` that navigates to the existing `JoinTenantScreen`.

**Bottom of screen (after auth buttons):**
```
│  ... existing auth UI ...   │
│                             │
│  Need an organization?      │
│  Request one →              │ ← TextButton, navigates to TenantRequestScreen
└─────────────────────────────┘
```

### Navigation Params

Add `onNavigateToJoinTenant: () -> Unit` and `onNavigateToTenantRequest: () -> Unit` to `LoginScreen` composable parameters.

---

## Screen 3: TenantRequestScreen (New)

**File:** `presentation/tenant/TenantRequestScreen.kt` (new)
**File:** `presentation/tenant/TenantRequestViewModel.kt` (new)

### Layout

```
┌─────────────────────────────┐
│  ← Request Organization     │  TopAppBar with back
├─────────────────────────────┤
│                             │
│  🏢 (Business icon, 64dp)  │
│                             │
│  Create Your Organization   │
│  Request a new organization │
│  for your team.             │
│                             │
│  Organization Name *        │
│  [                        ] │
│                             │
│  Reason (optional)          │
│  [                        ] │  multiline, max 500 chars
│  [                        ] │
│                             │
│  [Submit Request]           │  full-width, primary
│                             │
└─────────────────────────────┘

SUCCESS STATE:
┌─────────────────────────────┐
│  ✓ Request Submitted        │
│                             │
│  Your request for           │
│  "Acme Corp" has been       │
│  submitted. An admin will   │
│  review and approve it.     │
│                             │
│  You'll be notified when    │
│  your organization is       │
│  ready.                     │
│                             │
│  [Back to Home]             │
└─────────────────────────────┘
```

### State

```kotlin
data class TenantRequestUiState(
    val organizationName: String = "",
    val reason: String = "",
    val isLoading: Boolean = false,
    val isSubmitted: Boolean = false,
    val error: String? = null
)
```

### Validation
- Organization name: required, trimmed, non-blank
- Reason: optional, max 500 chars
- Duplicate check: backend returns 409 if user already has a pending request

### Repository

Add to `TenantRepository`:
```kotlin
suspend fun submitTenantRequest(name: String, reason: String?): Result<TenantRequestResponse>
```

Calls `POST /api/tenant-requests` with body `{ organization_name, reason }`.

### Access
- From LoginScreen: "Need an organization? Request one" link (pre-auth, must be logged in first)
- From Settings: "Request Organization" menu item (post-auth)
- Note: The endpoint requires authentication, so the pre-auth link should navigate to login first if not authenticated

---

## Screen 4: InviteTeamScreen (New)

**File:** `presentation/tenant/InviteTeamScreen.kt` (new)
**File:** `presentation/tenant/InviteTeamViewModel.kt` (new)

### Layout

```
┌─────────────────────────────┐
│  ← Invite Team Member       │  TopAppBar with back
├─────────────────────────────┤
│                             │
│  Email Address *            │
│  [john@acme.com          ]  │  email keyboard
│                             │
│  Role                       │
│  [  Member  |  Admin  ]     │  SegmentedButton
│                             │
│  Message (optional)         │
│  [Welcome to the team!   ]  │  max 500 chars
│  [                       ]  │
│                             │
│  [Send Invitation]          │  full-width, primary
│                             │
└─────────────────────────────┘

SUCCESS STATE:
┌─────────────────────────────┐
│  ✓ Invitation Sent!         │
│                             │
│  Invite Code: ACME-7K9X    │
│  [Copy]  [Share]            │
│                             │
│  Email: ✓ Sent              │  or "⚠ Failed to send"
│                             │
│  [Invite Another]           │  resets form
│  [Done]                     │  navigates back
└─────────────────────────────┘
```

### State

```kotlin
data class InviteTeamUiState(
    val email: String = "",
    val role: TenantRole = TenantRole.Member,
    val message: String = "",
    val isLoading: Boolean = false,
    // Success state
    val createdInvitation: CreatedInvitation? = null,
    val error: String? = null
)

data class CreatedInvitation(
    val shortCode: String,
    val token: String,
    val emailSent: Boolean,
    val emailError: String?
)
```

### Validation
- Email: required, valid format (client-side check before API call)
- Role: Member or Admin (Owner can invite both, Admin can only invite Member — backend enforces)
- Message: optional, max 500 chars

### Actions
- **Copy Code:** Copy short code to clipboard with toast "Copied!"
- **Share:** Android share sheet with text: "Join Acme Corp on SSDID Drive! Use invite code: ACME-7K9X or visit: https://drive.ssdid.my/invite/ACME-7K9X"
- **Invite Another:** Reset form, keep role selection

### Access
- Settings → "Invite Team Member" (visible only if user's role is Owner or Admin)
- Use `currentUser.role` from `UserTenants` to determine visibility

### Repository

Add to `TenantRepository`:
```kotlin
suspend fun createInvitation(email: String, role: String, message: String?): Result<InvitationResponse>
```

Calls `POST /api/invitations` with body `{ email, role, message }`.

---

## Error Handling

All screens follow the existing pattern:
- Inline error text (red, below the action button)
- Network errors: "Unable to connect. Check your internet connection."
- 409 Conflict: Show specific message (e.g., "You already have a pending request")
- 403 Forbidden: Show specific message (e.g., "Only owners and admins can invite members")
- Loading states: Button shows `CircularProgressIndicator`, disabled during loading

## Testing

Each new screen gets:
- Unit tests for ViewModel (mock repository, verify state transitions)
- UI tests for composable (verify rendering, interaction)
- Follow existing test patterns in `src/androidTest/` and `src/test/`
