# QR Desktop Client Auth Wiring — Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Wire the desktop client's QR-based authentication to the ssdid-drive backend's existing `LoginInitiate` and SSE endpoints, replacing client-side challenge generation with server-issued challenges.

**Architecture:** The backend already has `POST /login/initiate` (challenge + subscriber secret + QR payload), SSE at `GET /events`, and `NotifyCompletion` on successful auth. The desktop client currently generates challenges client-side — we replace that with a `fetch()` call to the backend. We also add `subscriber_secret` to the SSE URL for security.

**Tech Stack:** TypeScript, React 18, Vitest, Vite, qrcode.react, EventSource (SSE)

---

### Task 1: Add `Ssdid:ServiceUrl` to backend config

**Files:**
- Modify: `src/SsdidDrive.Api/appsettings.Development.json`

The backend `LoginInitiate.cs:27` reads `config["Ssdid:ServiceUrl"]` but falls back to `""`. Add the dev value so QR payloads contain the correct URL.

**Step 1: Add ServiceUrl to dev config**

Edit `src/SsdidDrive.Api/appsettings.Development.json` to:

```json
{
  "Logging": {
    "LogLevel": {
      "Default": "Information",
      "Microsoft.AspNetCore": "Information",
      "Microsoft.EntityFrameworkCore.Database.Command": "Information"
    }
  },
  "Ssdid": {
    "ServiceUrl": "http://localhost:5147"
  }
}
```

**Step 2: Verify backend starts and returns ServiceUrl in QR payload**

Run:
```bash
cd ~/Workspace/ssdid-drive/src/SsdidDrive.Api && dotnet run &
sleep 5
curl -s -X POST http://localhost:5147/api/auth/ssdid/login/initiate | python3 -m json.tool
```

Expected: JSON response with `qr_payload.service_url` = `"http://localhost:5147"`.

**Step 3: Commit**

```bash
git add src/SsdidDrive.Api/appsettings.Development.json
git commit -m "feat(auth): add Ssdid:ServiceUrl to dev config for QR payload"
```

---

### Task 2: Add `subscriberSecret` to `ChallengeResult` interface

**Files:**
- Modify: `clients/desktop/src/services/tauri.ts:27-31`
- Test: `clients/desktop/src/services/__tests__/tauri.test.ts`

**Step 1: Write the failing test**

Add to `clients/desktop/src/services/__tests__/tauri.test.ts`, inside a new `describe('createChallenge')` block:

```typescript
describe('createChallenge', () => {
  it('should call backend login/initiate and return subscriberSecret', async () => {
    const mockResponse = {
      challenge_id: 'abc123',
      subscriber_secret: 'secret-xyz',
      qr_payload: {
        action: 'login',
        service_url: 'http://localhost:5147',
        service_name: 'ssdid-drive',
        challenge_id: 'abc123',
        challenge: 'base64challenge',
        server_did: 'did:ssdid:test',
        server_key_id: 'did:ssdid:test#key-1',
        server_signature: 'sig123',
        registry_url: 'https://registry.ssdid.my',
      },
    };

    global.fetch = vi.fn().mockResolvedValue({
      ok: true,
      json: () => Promise.resolve(mockResponse),
    });

    const { createChallenge } = await import('../tauri');
    const result = await createChallenge('authenticate');

    expect(global.fetch).toHaveBeenCalledWith(
      expect.stringContaining('/api/auth/ssdid/login/initiate'),
      expect.objectContaining({ method: 'POST' })
    );
    expect(result.challengeId).toBe('abc123');
    expect(result.subscriberSecret).toBe('secret-xyz');
    expect(result.serverDid).toBe('did:ssdid:test');
    expect(result.qrPayload).toContain('abc123');
  });

  it('should throw on non-ok response', async () => {
    global.fetch = vi.fn().mockResolvedValue({
      ok: false,
      status: 500,
      statusText: 'Internal Server Error',
    });

    const { createChallenge } = await import('../tauri');
    await expect(createChallenge('authenticate')).rejects.toThrow();
  });
});
```

**Step 2: Run test to verify it fails**

Run:
```bash
cd ~/Workspace/ssdid-drive/clients/desktop && npx vitest run src/services/__tests__/tauri.test.ts
```

Expected: FAIL — `subscriberSecret` not in return type, `createChallenge` doesn't call fetch.

**Step 3: Update `ChallengeResult` interface and `createChallenge` function**

Edit `clients/desktop/src/services/tauri.ts`:

Replace the `ChallengeResult` interface (lines 27-31):

```typescript
export interface ChallengeResult {
  serverDid: string;
  challengeId: string;
  subscriberSecret: string;
  qrPayload: string;
}
```

Replace the `createChallenge` function (lines 55-79):

```typescript
export async function createChallenge(
  _action: 'authenticate' | 'register'
): Promise<ChallengeResult> {
  const baseUrl = await getApiBaseUrl();
  const resp = await fetch(`${baseUrl}/api/auth/ssdid/login/initiate`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
  });

  if (!resp.ok) {
    throw new Error(`Login initiate failed: ${resp.status} ${resp.statusText}`);
  }

  const data = await resp.json();

  return {
    serverDid: data.qr_payload.server_did,
    challengeId: data.challenge_id,
    subscriberSecret: data.subscriber_secret,
    qrPayload: JSON.stringify(data.qr_payload),
  };
}
```

Add a `getApiBaseUrl` helper above `createChallenge`:

```typescript
async function getApiBaseUrl(): Promise<string> {
  try {
    const info = await invoke<{ api_base_url: string }>('get_api_base_url');
    return info.api_base_url;
  } catch {
    return import.meta.env.VITE_API_BASE_URL ?? 'http://localhost:5147';
  }
}
```

Remove the now-unused `fetchServerInfo` function and `ServerInfo` interface (lines 22-48) — they are replaced by `getApiBaseUrl`. Also update `tauriService.getServerInfo` to remove that method since it's no longer needed.

**Step 4: Run test to verify it passes**

Run:
```bash
cd ~/Workspace/ssdid-drive/clients/desktop && npx vitest run src/services/__tests__/tauri.test.ts
```

Expected: PASS

**Step 5: Commit**

```bash
git add clients/desktop/src/services/tauri.ts clients/desktop/src/services/__tests__/tauri.test.ts
git commit -m "feat(desktop): wire createChallenge to backend login/initiate endpoint"
```

---

### Task 3: Pass `subscriber_secret` in SSE URL

**Files:**
- Modify: `clients/desktop/src/components/auth/QrChallenge.tsx:49`
- Test: `clients/desktop/src/components/auth/__tests__/QrChallenge.test.tsx`

**Step 1: Write the failing test**

Add to `clients/desktop/src/components/auth/__tests__/QrChallenge.test.tsx`:

First, update `mockChallengeResult` to include `subscriberSecret`:

```typescript
const mockChallengeResult = {
  serverDid: 'did:example:server',
  challengeId: 'challenge-123',
  subscriberSecret: 'secret-abc-456',
  qrPayload: mockQrPayload,
};
```

Then add this test:

```typescript
it('should include subscriber_secret in SSE URL', async () => {
  mockCreateChallenge.mockResolvedValue(mockChallengeResult);

  render(
    <QrChallenge action="authenticate" onAuthenticated={mockOnAuthenticated} />
  );

  await waitFor(() => {
    expect(screen.getByTestId('qr-code')).toBeInTheDocument();
  });

  // Verify EventSource was created with subscriber_secret in URL
  expect(MockEventSource).toHaveBeenCalledWith(
    expect.stringContaining('subscriber_secret=secret-abc-456')
  );
});
```

To capture the URL, update the `MockEventSource` class:

```typescript
class MockEventSource {
  static lastUrl: string = '';
  addEventListener = vi.fn();
  close = vi.fn();
  onerror: ((event: Event) => void) | null = null;

  constructor(url: string) {
    MockEventSource.lastUrl = url;
    // eslint-disable-next-line @typescript-eslint/no-this-alias
    mockEventSourceInstance = this;
  }
}
```

**Step 2: Run test to verify it fails**

Run:
```bash
cd ~/Workspace/ssdid-drive/clients/desktop && npx vitest run src/components/auth/__tests__/QrChallenge.test.tsx
```

Expected: FAIL — SSE URL does not contain `subscriber_secret`.

**Step 3: Update QrChallenge to pass subscriber_secret**

Edit `clients/desktop/src/components/auth/QrChallenge.tsx`:

Add `subscriberSecret` state (after line 18):

```typescript
const [subscriberSecret, setSubscriberSecret] = useState<string>('');
```

In `initChallenge`, save it (after `setChallengeId` around line 29):

```typescript
setSubscriberSecret(result.subscriberSecret);
```

Update the SSE useEffect condition (line 45) to include subscriberSecret:

```typescript
if (state !== 'ready' || !challengeId || !serverUrl || !subscriberSecret) {
  return;
}
```

Update the SSE URL (line 49):

```typescript
const sseUrl = `${serverUrl}/api/auth/ssdid/events?challenge_id=${challengeId}&subscriber_secret=${subscriberSecret}`;
```

Update the useEffect dependency array (line 77):

```typescript
}, [state, challengeId, serverUrl, subscriberSecret, onAuthenticated]);
```

**Step 4: Run test to verify it passes**

Run:
```bash
cd ~/Workspace/ssdid-drive/clients/desktop && npx vitest run src/components/auth/__tests__/QrChallenge.test.tsx
```

Expected: PASS (all existing tests + new subscriber_secret test)

**Step 5: Commit**

```bash
git add clients/desktop/src/components/auth/QrChallenge.tsx clients/desktop/src/components/auth/__tests__/QrChallenge.test.tsx
git commit -m "feat(desktop): pass subscriber_secret in SSE URL for secure subscription"
```

---

### Task 4: Run full test suite and verify

**Files:**
- No changes — verification only

**Step 1: Run all desktop tests**

```bash
cd ~/Workspace/ssdid-drive/clients/desktop && npx vitest run
```

Expected: All tests pass. Fix any broken tests that relied on old `ChallengeResult` shape (missing `subscriberSecret`).

**Step 2: Run TypeScript type check**

```bash
cd ~/Workspace/ssdid-drive/clients/desktop && npx tsc --noEmit
```

Expected: No type errors.

**Step 3: Run lint**

```bash
cd ~/Workspace/ssdid-drive/clients/desktop && npm run lint
```

Expected: No lint errors (or only pre-existing ones within the max-warnings threshold).

---

### Task 5: End-to-end smoke test

**Files:**
- No changes — manual verification

**Step 1: Start the backend**

```bash
cd ~/Workspace/ssdid-drive && podman compose up -d  # PostgreSQL
cd ~/Workspace/ssdid-drive/src/SsdidDrive.Api && dotnet run
```

**Step 2: Start the desktop client dev server**

```bash
cd ~/Workspace/ssdid-drive/clients/desktop && VITE_API_BASE_URL=http://localhost:5147 npm run dev
```

**Step 3: Verify QR flow**

1. Open `http://localhost:5173` in browser
2. Navigate to Login page
3. Verify QR code appears (should contain server_did, challenge, etc.)
4. Open browser DevTools Network tab — confirm `POST /api/auth/ssdid/login/initiate` was called
5. Confirm SSE connection to `/api/auth/ssdid/events?challenge_id=...&subscriber_secret=...` is active
6. Wait 5 minutes — QR should show "expired" state when SSE sends timeout event

**Step 4: Commit any final fixes**

```bash
git add -A
git commit -m "fix(desktop): final adjustments from smoke test"
```
