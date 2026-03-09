# QR Scan + Deeplink Desktop Client Design

## Overview

Wire the desktop client's QR-based authentication to the ssdid-drive backend's existing `LoginInitiate` and SSE endpoints. The backend already has the server-side challenge generation, subscriber secrets, and SSE completion notification. The desktop client currently generates challenges client-side — this needs to call the backend instead.

## Architecture

### Flow: Desktop Login via Wallet QR Scan

```
Desktop Client                 ssdid-drive API                  SSDID Wallet
     |                              |                               |
     |-- POST /login/initiate ----->|                               |
     |<-- {challenge_id,            |                               |
     |     subscriber_secret,       |                               |
     |     qr_payload} -------------|                               |
     |                              |                               |
     |-- GET /events?challenge_id   |                               |
     |   &subscriber_secret ------->| (SSE stream)                  |
     |                              |                               |
     |   [Display QR from           |                               |
     |    qr_payload JSON]          |                               |
     |                              |                               |
     |                              |<-- POST /register ------------|
     |                              |    {did, key_id}              |
     |                              |-- challenge + server_sig ---->|
     |                              |<-- POST /register/verify -----|
     |                              |-- VC + session_token          |
     |                              |                               |
     |                              | NotifyCompletion(             |
     |                              |   challenge_id, session_token)|
     |<-- SSE: authenticated -------|                               |
     |    {session_token}           |                               |
```

### QR Payload Format (from LoginInitiate)

```json
{
  "action": "login",
  "service_url": "https://drive.ssdid.my",
  "service_name": "ssdid-drive",
  "challenge_id": "a1b2c3...",
  "challenge": "base64url(32 random bytes)",
  "server_did": "did:ssdid:rUUr8i4n4WlFmHJ2KxXxqQ",
  "server_key_id": "did:ssdid:rUUr8i4n4WlFmHJ2KxXxqQ#key-1",
  "server_signature": "uBase64url(...)",
  "registry_url": "https://registry.ssdid.my"
}
```

## Changes Required

### 1. Desktop Client — `tauri.ts` (frontend)

Replace client-side challenge generation with backend call:

```typescript
export async function createChallenge(
  action: 'authenticate' | 'register'
): Promise<ChallengeResult> {
  const baseUrl = await getApiBaseUrl();
  const resp = await fetch(`${baseUrl}/api/auth/ssdid/login/initiate`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
  });
  const data = await resp.json();
  return {
    serverDid: data.qr_payload.server_did,
    challengeId: data.challenge_id,
    subscriberSecret: data.subscriber_secret,
    qrPayload: JSON.stringify(data.qr_payload),
  };
}
```

### 2. Desktop Client — `QrChallenge.tsx`

Pass `subscriberSecret` to the SSE URL:

```typescript
const sseUrl = `${serverUrl}/api/auth/ssdid/events?challenge_id=${challengeId}&subscriber_secret=${subscriberSecret}`;
```

### 3. Desktop Client — `ChallengeResult` type

Add `subscriberSecret` field:

```typescript
export interface ChallengeResult {
  serverDid: string;
  challengeId: string;
  subscriberSecret: string;
  qrPayload: string;
}
```

### 4. Backend — `LoginInitiate.cs`

Add `Ssdid:ServiceUrl` to config (currently empty string fallback). For dev: `http://localhost:5147`.

### 5. Backend — Wire challenge_id to SSE notification

When `POST /register/verify` or `POST /authenticate` succeeds, call `NotifyCompletion(challengeId, sessionToken)` on the SSE bus. This requires the wallet to pass `challenge_id` in the verify/authenticate request.

### 6. Wallet — Pass challenge_id through flows

Add `challenge_id` to `RegisterStartRequest` and `AuthenticateRequest` DTOs so the backend can correlate.

## Configuration

```json
{
  "Ssdid": {
    "ServiceUrl": "http://localhost:5147"
  }
}
```

Desktop client needs the API base URL. For development, read from env or Tauri config. The Rust `api_client.rs` already has `SSDID_DRIVE_API_URL` env var support.

## Security

- Subscriber secrets prevent unauthorized SSE subscription (already implemented)
- Challenge TTL: 5 minutes (already implemented)
- Session TTL: 1 hour (already implemented)
- Server signature on challenge proves server identity to wallet
