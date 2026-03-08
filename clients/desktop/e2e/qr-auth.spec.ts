import { test, expect, type Page, type Route } from '@playwright/test';

const MOCK_LOGIN_INITIATE_RESPONSE = {
  challenge_id: 'e2e-challenge-abc123',
  subscriber_secret: 'e2e-secret-xyz789',
  qr_payload: {
    action: 'login',
    service_url: 'http://localhost:5147',
    service_name: 'ssdid-drive',
    challenge_id: 'e2e-challenge-abc123',
    challenge: 'dGVzdC1jaGFsbGVuZ2UtYmFzZTY0',
    server_did: 'did:ssdid:e2eTestServerDid',
    server_key_id: 'did:ssdid:e2eTestServerDid#key-1',
    server_signature: 'e2e-mock-signature',
    registry_url: 'https://registry.ssdid.my',
  },
};

/** Mock Tauri invoke — all calls fail gracefully */
async function mockTauri(page: Page) {
  await page.addInitScript(() => {
    // @ts-expect-error mock Tauri API
    window.__TAURI_INTERNALS__ = {
      invoke: (_cmd: string) =>
        Promise.reject(new Error('Not in Tauri context')),
    };
  });
}

/** Route login/initiate with success response */
async function mockLoginInitiate(
  page: Page,
  handler?: (route: Route) => void
) {
  await page.route('**/api/auth/ssdid/login/initiate', (route) => {
    if (handler) {
      handler(route);
    } else {
      route.fulfill({
        status: 200,
        contentType: 'application/json',
        body: JSON.stringify(MOCK_LOGIN_INITIATE_RESPONSE),
      });
    }
  });
}

/** Route SSE events with keepalive */
async function mockSseEvents(page: Page) {
  await page.route('**/api/auth/ssdid/events**', (route) => {
    route.fulfill({
      status: 200,
      contentType: 'text/event-stream',
      headers: { 'Cache-Control': 'no-cache', Connection: 'keep-alive' },
      body: ':keepalive\n\n',
    });
  });
}

test.describe('QR Auth Flow', () => {
  test.beforeEach(async ({ page }) => {
    await mockTauri(page);
    await mockLoginInitiate(page);
    await mockSseEvents(page);
  });

  test('login page shows QR code with server-issued challenge', async ({
    page,
  }) => {
    await page.goto('/login');

    const qrCode = page.locator('svg').first();
    await expect(qrCode).toBeVisible({ timeout: 10000 });
    await expect(page.getByText('Scan with SSDID Wallet')).toBeVisible();
    await expect(
      page.getByText(/scan this QR code to sign in/)
    ).toBeVisible();
  });

  test('login/initiate is called with POST method', async ({ page }) => {
    const apiCalled = page.waitForRequest(
      (req) =>
        req.url().includes('/api/auth/ssdid/login/initiate') &&
        req.method() === 'POST'
    );

    await page.goto('/login');
    const request = await apiCalled;

    expect(request.method()).toBe('POST');
  });

  test('register page shows QR code with register action', async ({
    page,
  }) => {
    await page.goto('/register');

    const qrCode = page.locator('svg').first();
    await expect(qrCode).toBeVisible({ timeout: 10000 });
    await expect(
      page.getByText(/scan this QR code to register/)
    ).toBeVisible();
  });

  // Note: SSE subscriber_secret URL verification is covered by Vitest unit tests
  // (QrChallenge.test.tsx). Playwright cannot intercept EventSource connections.
});

test.describe('QR Auth Flow — error handling', () => {
  test('shows error state when login/initiate fails', async ({ page }) => {
    await mockTauri(page);
    await mockLoginInitiate(page, (route) => {
      route.fulfill({
        status: 500,
        contentType: 'application/json',
        body: JSON.stringify({ error: 'Internal Server Error' }),
      });
    });

    await page.goto('/login');

    await expect(
      page.getByText(/Login initiate failed/)
    ).toBeVisible({ timeout: 10000 });
    await expect(
      page.getByRole('button', { name: /try again/i })
    ).toBeVisible();
  });

  test('retry button works after error', async ({ page }) => {
    await mockTauri(page);

    // Track POST calls (React strict mode in dev may cause double renders)
    // Use "all fail until toggled" approach instead of counter
    let shouldSucceed = false;

    await mockLoginInitiate(page, (route) => {
      if (shouldSucceed) {
        route.fulfill({
          status: 200,
          contentType: 'application/json',
          body: JSON.stringify(MOCK_LOGIN_INITIATE_RESPONSE),
        });
      } else {
        route.fulfill({
          status: 500,
          contentType: 'application/json',
          body: JSON.stringify({ error: 'Server Error' }),
        });
      }
    });
    await mockSseEvents(page);

    await page.goto('/login');

    // Wait for error state
    await expect(
      page.getByRole('button', { name: /try again/i })
    ).toBeVisible({ timeout: 10000 });

    // Toggle to success mode before clicking retry
    shouldSucceed = true;

    // Click retry
    await page.getByRole('button', { name: /try again/i }).click();

    // QR code should appear
    const qrCode = page.locator('svg').first();
    await expect(qrCode).toBeVisible({ timeout: 10000 });
    await expect(page.getByText('Scan with SSDID Wallet')).toBeVisible();
  });
});
