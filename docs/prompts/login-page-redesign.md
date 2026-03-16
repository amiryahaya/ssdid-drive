# Login Page Redesign — Smart Wallet Detection

## Problem

The login page is too long — showing email field, OIDC buttons, QR code, wallet button, and org request link all at once. Users scroll to find what they need. The QR code takes significant space but is only useful for cross-device flows.

## Solution

Detect if ssdid-wallet is installed on the same device. Show different layouts based on detection.

## Wallet Detection

### iOS
```swift
// Already configured in Info.plist: LSApplicationQueriesSchemes includes "ssdid"
let walletInstalled = UIApplication.shared.canOpenURL(URL(string: "ssdid://")!)
```

### Android
```kotlin
val intent = Intent(Intent.ACTION_VIEW, Uri.parse("ssdid://"))
val walletInstalled = intent.resolveActivity(packageManager) != null
```

## Layout A: Wallet Installed (Same Device)

Primary action: "Open SSDID Wallet" — one tap to authenticate.
Other methods collapsed behind "Other sign in options" disclosure.

```
┌─────────────────────────────┐
│  [Logo]                     │
│  SSDID Drive                │
│  Sign in to your account    │
│                             │
│  [Have an invite code? →]   │  ← card, navigates to JoinTenant
│                             │
│  ┌───────────────────────┐  │
│  │  🔐 Open SSDID Wallet │  │  ← PRIMARY button, full width, 56pt height
│  │     Tap to sign in    │  │     blue/primary color
│  └───────────────────────┘  │
│                             │
│  ── other sign in options ──│  ← disclosure button, collapsed by default
│                             │
│  When expanded:             │
│  [Email field]              │
│  [Continue with Email]      │
│  [Google]  [Microsoft]      │
│                             │
│  Need an organization? →    │
│  Lost device? Recover →     │
└─────────────────────────────┘
```

- "Open SSDID Wallet" button immediately creates challenge + opens wallet
- No QR code shown (same device — QR is pointless)
- Other methods are accessible but not prominent
- SSE listener starts in background for wallet callback

## Layout B: No Wallet (Show All Methods)

Primary actions: Email/OIDC (most enterprise users don't have the wallet).
QR code shown for cross-device wallet scanning.
"Get SSDID Wallet" link to app store.

```
┌─────────────────────────────┐
│  [Logo]                     │
│  SSDID Drive                │
│  Sign in to your account    │
│                             │
│  [Have an invite code? →]   │
│                             │
│  [Email field]              │
│  [Continue with Email]      │  ← primary button
│                             │
│  ── or sign in with ──      │
│                             │
│  [Google]  [Microsoft]      │  ← secondary buttons, side by side
│                             │
│  ── or scan with wallet ──  │
│                             │
│  [QR Code] (150x150)        │  ← for cross-device scanning
│  Get SSDID Wallet →         │  ← links to App Store / Play Store
│                             │
│  Need an organization? →    │
│  Lost device? Recover →     │
└─────────────────────────────┘
```

## Implementation Details

### Detection Timing
- Check wallet availability in `viewDidLoad` / `onCreateView` (before any UI is shown)
- Cache the result — don't re-check on every render
- On iOS: `canOpenURL` is synchronous and fast
- On Android: `resolveActivity` is synchronous and fast

### "Other sign in options" Disclosure
- iOS: `UIStackView` with animated `isHidden` toggle on subviews
- Android: `AnimatedVisibility` in Compose with `expandVertically()` transition
- Arrow icon rotates 90° when expanded
- Remember expansion state (don't collapse on re-render)

### Challenge Creation
- **Wallet installed**: Create challenge eagerly on page load (wallet button needs it immediately)
- **No wallet**: Create challenge lazily (only when QR section becomes visible or user scrolls)
- This saves a network call for non-wallet users

### SSE Listener
- Start SSE listener as soon as challenge is created (both layouts)
- If wallet is opened, SSE delivers the session token
- If user uses email/OIDC instead, SSE is a no-op

### Invite Code Context
- If user came from JoinTenant (has `pendingInviteCode`), the "Open SSDID Wallet" button should:
  1. Set `pendingInviteCode` on the view model
  2. Create a new challenge with `invite_code` in the deeplink
  3. Open wallet with the invite-aware deeplink

## Files to Change

### iOS
- `Presentation/Auth/LoginViewController.swift` — layout refactor
- `Presentation/Auth/LoginViewModel.swift` — add `isWalletInstalled` property

### Android
- `presentation/auth/LoginScreen.kt` — layout refactor
- `presentation/auth/LoginViewModel.kt` — add wallet detection

## UX Guidelines Applied
- Touch target: wallet button ≥ 56pt height (exceeds 44pt minimum)
- Loading state: show spinner in wallet button after tap
- Error feedback: inline error below wallet button if wallet can't open
- Transitions: 200ms expand/collapse for "other options" disclosure
- No layout shift: reserve space or animate smoothly
