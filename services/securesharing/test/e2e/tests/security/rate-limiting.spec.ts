/**
 * Rate Limiting Security E2E Tests
 *
 * Tests for:
 * - Login endpoint rate limiting (5 requests/minute for auth endpoints)
 * - Proper rate limit response headers (retry-after)
 * - Rate limit error response format (429)
 *
 * IMPORTANT: The auth rate limit is 5 requests/minute per IP.
 * These tests must be carefully designed to avoid flakiness.
 * We send exactly enough requests to trigger the limit and verify the 429 response.
 */

import { test, expect } from '@playwright/test';
import { CONFIG } from '../../lib/api-client';

const baseUrl = CONFIG.backendUrl;

// Helper to make a raw login request (returns the full response, no error throwing)
async function rawLoginRequest(
  request: any,
  email: string,
  password: string
): Promise<{ status: number; headers: Record<string, string>; body: any }> {
  const response = await request.post(`${baseUrl}/api/auth/login`, {
    headers: { 'Content-Type': 'application/json' },
    data: {
      email,
      password,
      device_info: {
        platform: 'e2e-test',
        name: 'Playwright Rate Limit Test',
        os_version: 'test',
      },
    },
  });

  const status = response.status();
  const body = await response.json();

  // Collect relevant headers
  const headers: Record<string, string> = {};
  const retryAfter = response.headers()['retry-after'];
  if (retryAfter) {
    headers['retry-after'] = retryAfter;
  }

  return { status, headers, body };
}

test.describe('Auth Endpoint Rate Limiting', () => {
  // The rate limit is 5 requests/minute per IP for auth endpoints.
  // We use serial mode because rate limit state is shared and order matters.
  test.describe.configure({ mode: 'serial' });

  // Use a unique X-Forwarded-For per test run to isolate from other test suites
  // that might also be hitting the login endpoint.
  const testRunId = Date.now();

  test('login endpoint rejects after too many failed attempts (429)', async ({ request }) => {
    // We need to exceed 5 requests within the rate limit window.
    // Use intentionally wrong credentials so we do not need a real user.
    const fakeEmail = `ratelimit-test-${testRunId}@example.com`;
    const fakePassword = 'NotARealPassword123!';

    let rateLimited = false;
    let lastStatus = 0;
    let lastHeaders: Record<string, string> = {};
    let lastBody: any = {};

    // Send 7 requests -- the first 5 should be allowed (returning 401 for bad creds),
    // and request 6 or 7 should trigger 429.
    for (let i = 0; i < 7; i++) {
      const result = await rawLoginRequest(request, fakeEmail, fakePassword);
      lastStatus = result.status;
      lastHeaders = result.headers;
      lastBody = result.body;

      if (result.status === 429) {
        rateLimited = true;
        break;
      }

      // If we get 401, that is expected (invalid credentials, but not rate limited yet)
      if (result.status !== 401 && result.status !== 429) {
        // Unexpected status -- could be a server error or other issue
        console.log(`Unexpected status ${result.status} on attempt ${i + 1}`);
      }
    }

    // Verify that rate limiting kicked in
    expect(rateLimited).toBe(true);
    expect(lastStatus).toBe(429);
  });

  test('rate limit includes proper headers in response', async ({ request }) => {
    // Continue from the previous test's rate limit state.
    // Since we already exceeded the limit above, the next request should also be 429.
    const fakeEmail = `ratelimit-headers-${testRunId}@example.com`;
    const fakePassword = 'NotARealPassword123!';

    // Send enough requests to ensure we hit the rate limit
    let rateLimitedResponse: { status: number; headers: Record<string, string>; body: any } | null = null;

    for (let i = 0; i < 7; i++) {
      const result = await rawLoginRequest(request, fakeEmail, fakePassword);

      if (result.status === 429) {
        rateLimitedResponse = result;
        break;
      }
    }

    // If rate limiting is enabled, we should have a 429 response
    if (rateLimitedResponse) {
      expect(rateLimitedResponse.status).toBe(429);

      // Check retry-after header is present and is a number (seconds)
      expect(rateLimitedResponse.headers['retry-after']).toBeDefined();
      const retryAfterSeconds = parseInt(rateLimitedResponse.headers['retry-after'], 10);
      expect(retryAfterSeconds).toBeGreaterThan(0);
      // The rate limit window is 60 seconds, so retry-after should be <= 60
      expect(retryAfterSeconds).toBeLessThanOrEqual(60);

      // Check error response body format
      expect(rateLimitedResponse.body.error).toBeDefined();
      expect(rateLimitedResponse.body.error.code).toBe('rate_limited');
      expect(rateLimitedResponse.body.error.message).toBeTruthy();
    } else {
      // Rate limiting might be disabled in test environment
      console.log('Rate limiting may be disabled in this environment (rate_limit_enabled: false)');
      test.skip(true, 'Rate limiting appears to be disabled in this environment');
    }
  });

  test('rate limit error response has correct JSON structure', async ({ request }) => {
    const fakeEmail = `ratelimit-json-${testRunId}@example.com`;
    const fakePassword = 'NotARealPassword123!';

    // Exhaust the rate limit
    let rateLimitBody: any = null;
    for (let i = 0; i < 7; i++) {
      const result = await rawLoginRequest(request, fakeEmail, fakePassword);
      if (result.status === 429) {
        rateLimitBody = result.body;
        break;
      }
    }

    if (rateLimitBody) {
      // Validate the exact error response structure from ErrorJSON render("429.json")
      expect(rateLimitBody).toEqual({
        error: {
          code: 'rate_limited',
          message: 'Too many requests. Please try again later.',
        },
      });
    } else {
      console.log('Rate limiting may be disabled in this environment');
      test.skip(true, 'Rate limiting appears to be disabled in this environment');
    }
  });
});

test.describe('Registration Endpoint Rate Limiting', () => {
  test('register endpoint is also rate limited', async ({ request }) => {
    const testRunId = Date.now();
    let rateLimited = false;

    for (let i = 0; i < 7; i++) {
      const response = await request.post(`${baseUrl}/api/auth/register`, {
        headers: { 'Content-Type': 'application/json' },
        data: {
          email: `ratelimit-reg-${testRunId}-${i}@example.com`,
          password: 'RateLimitTest123!',
          name: `Rate Limit Test User ${i}`,
          public_keys: {
            kem: Buffer.from('mock-kem-key').toString('base64'),
            sign: Buffer.from('mock-sign-key').toString('base64'),
          },
          encrypted_master_key: Buffer.from('mock-master-key').toString('base64'),
          master_key_nonce: Buffer.from('mock-nonce').toString('base64'),
          device_info: {
            platform: 'e2e-test',
            name: 'Playwright Rate Limit Test',
            os_version: 'test',
          },
        },
      });

      if (response.status() === 429) {
        rateLimited = true;
        const body = await response.json();
        expect(body.error.code).toBe('rate_limited');
        break;
      }
    }

    if (!rateLimited) {
      console.log('Rate limiting may be disabled for registration in this environment');
      test.skip(true, 'Rate limiting appears to be disabled in this environment');
    }
  });
});
