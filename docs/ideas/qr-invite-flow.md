# QR-Based Invitation Flow (Idea - On Hold)

## Concept

Instead of inviting by DID or email, use channel-agnostic invite links/QR codes.

## Flow

1. **Admin creates invitation** → server generates unique invite token/link
2. **Admin shares the link** — QR code, messaging app, email, any channel
3. **Invitee opens link in wallet** → deep link `ssdid://invite?token=abc123&service=https://drive.ssdid.my`
4. **Wallet shows consent** — "You've been invited to [Tenant] as [Role]"
5. **Invitee picks which identity to use** → wallet presents chosen DID's VC to accept
6. **Server binds that DID to the tenant** — done

## Why This Approach

- No dependency on email or specific DID — inviter doesn't need to know anything about invitee
- User chooses which identity to associate with the tenant
- Channel-agnostic — works via QR, deep link, copy-paste
- Already half-built — `CreateInvitation` generates a token, `GetInvitationByToken` exists

## Status

On hold — exploring push notification approach first.
