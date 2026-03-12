# SSDID Drive Deep Link Protocol

Protocol specification for deep link communication between SSDID Drive and SSDID Wallet on iOS and Android.

## URL Schemes

| App | Registered Scheme | Queries (canOpenURL) |
|-----|-------------------|----------------------|
| SSDID Drive | `ssdid-drive` | `ssdid` |
| SSDID Wallet | `ssdid` | `ssdid-drive` |

## Same-Device Flow (Drive → Wallet → Drive)

### Step 1: Drive opens Wallet

Drive constructs a `ssdid://login?...` URL and opens it via `UIApplication.shared.open()` (iOS) or `Intent` (Android).

```
ssdid://login?server_url=<url>&service_name=<name>&challenge_id=<id>&callback_url=ssdid-drive://auth/callback&requested_claims=<json>
```

| Parameter | Required | Description |
|-----------|----------|-------------|
| `server_url` | Yes | HTTPS URL of the Drive API (e.g., `https://drive.ssdid.my`) |
| `service_name` | No | Human-readable service name (default: `ssdid-drive`) |
| `challenge_id` | No | Challenge correlation ID for SSE delivery on the cross-device path |
| `callback_url` | No | URL scheme to call back with `session_token` (e.g., `ssdid-drive://auth/callback`) |
| `requested_claims` | No | JSON array: `[{"key":"name","required":"true"},{"key":"email","required":"false"}]` |

### Step 2: Wallet authenticates

1. Wallet parses the URL via `DeepLinkHandler` → `DeepLinkAction.login`
2. Routes to `DriveLoginScreen` with identity picker and claims consent
3. If no credential exists for the selected identity, registers first:
   - `POST /api/auth/ssdid/register` with DID + key ID
   - Signs the returned challenge
   - `POST /api/auth/ssdid/register/verify` with signed challenge → receives Verifiable Credential
4. Authenticates with the credential:
   - `POST /api/auth/ssdid/authenticate` with VC + optional `challenge_id`
   - Receives `session_token`

### Step 3: Wallet calls back to Drive

```
ssdid-drive://auth/callback?session_token=<token>
```

| Parameter | Required | Description |
|-----------|----------|-------------|
| `session_token` | Yes | Bearer token for Drive API authentication |

Drive validates the token format (16–512 chars, alphanumeric + `-_.:`) before storing in Keychain.

## Cross-Device Flow (QR Code + SSE)

### QR Content

The QR code contains the same `ssdid://login?...` URL string as Step 1 above. The wallet scans the QR, parses it as a `ssdid://` URL, and follows the same authentication flow.

No `callback_url` is needed for cross-device — the session token is delivered via SSE instead.

### SSE Subscription

Drive subscribes to server-sent events after initiating the challenge:

```
GET /api/auth/ssdid/events?challenge_id=<id>&subscriber_secret=<secret>
```

The `subscriber_secret` is returned by `POST /api/auth/ssdid/login/initiate` and authorizes the SSE subscription. The server returns 403 if the secret is invalid.

### SSE Events

```
event: authenticated
data: {"session_token":"<token>"}

event: timeout
data: {"reason":"timeout"}

: keep-alive
```

- **`authenticated`** — Wallet completed authentication. Drive extracts `session_token` from JSON data.
- **`timeout`** — Challenge expired (server default: 5 minutes). Drive shows "Expired" and allows retry.
- **`: keep-alive`** — SSE comment sent every 30 seconds. Ignored by the client.

### SSE Connection

- Timeout: 310 seconds (slightly longer than server's 5-minute challenge TTL)
- Accept header: `text/event-stream`
- Uses the same SSL-pinned URLSession as other API calls
- Cancels previous stream on retry

## Backend Endpoints

| Method | Path | Purpose |
|--------|------|---------|
| `POST` | `/api/auth/ssdid/login/initiate` | Create challenge, returns `challenge_id`, `subscriber_secret`, `qr_payload` |
| `POST` | `/api/auth/ssdid/register` | Start registration (DID + key ID → challenge + server signature) |
| `POST` | `/api/auth/ssdid/register/verify` | Complete registration (signed challenge → Verifiable Credential) |
| `POST` | `/api/auth/ssdid/authenticate` | Authenticate (VC + optional challenge_id → session_token) |
| `GET` | `/api/auth/ssdid/events` | SSE stream (challenge_id + subscriber_secret → events) |

## Callback URL Validation

Both Drive and Wallet validate callback URLs before use:

**Blocked schemes:** `javascript`, `data`, `file`, `blob`, `vbscript`

**HTTPS callbacks** must have a non-empty host.

**Custom scheme callbacks** (e.g., `ssdid-drive://`) must match `^[a-z][a-z0-9+\-.]*$`.

## Security Considerations

- **Token validation:** Drive validates session token format before Keychain storage (length 16–512, charset `[a-zA-Z0-9\-_.:]`)
- **SSL pinning:** All connections (API calls + SSE) use the same pinning-aware URLSession with SHA-256 public key hashes
- **Server URL validation:** Wallet validates `server_url` is HTTPS-only, rejects private IPs, loopback, and non-standard ports
- **Subscriber secret:** SSE endpoint requires the secret returned at challenge creation — prevents unauthorized subscription
- **Challenge expiry:** Server enforces 5-minute TTL on challenges
- **Credential caching:** Wallet stores VCs in vault; expired credentials (401) are deleted and re-registration is triggered on retry

## Platform Notes

### iOS

- Drive registers `ssdid-drive://` via `CFBundleURLSchemes` in Info.plist
- Drive queries `ssdid` via `LSApplicationQueriesSchemes` for `canOpenURL` check
- Wallet registers `ssdid://` via `urlTypes` in XcodeGen `project.yml`
- Wallet queries `ssdid-drive` via `LSApplicationQueriesSchemes`
- Universal Links require `apple-app-site-association` at `https://drive.ssdid.my/.well-known/` and `https://ssdid.my/.well-known/`
- Deep links arrive via `onOpenURL` → `AppCoordinator.handleDeepLink()` → `RootView.routeDeepLink()`

### Android

- Drive registers `ssdid-drive://` via intent filter in `AndroidManifest.xml`
- Wallet registers `ssdid://` via intent filter in `AndroidManifest.xml`
- Callback uses explicit `Intent` with `ACTION_VIEW` to return to Drive
