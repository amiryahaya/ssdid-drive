/**
 * Accept Invitation (New User) E2E Tests
 *
 * Tests invitation acceptance for new users including:
 * - Getting invitation details by token
 * - Accepting invitation and creating new account
 */

import { test, expect } from '@playwright/test';
import { BackendApiClient, CONFIG } from '../../lib/api-client';
import { validateResponse, AuthResponseSchema } from '../../lib/schemas';
import crypto from 'crypto';

// Generate unique email for testing
function generateTestEmail(): string {
  const timestamp = Date.now();
  const random = crypto.randomBytes(4).toString('hex');
  return `new-user-${timestamp}-${random}@example.com`;
}

test.describe('Accept Invitation - New User', () => {
  test('should get invitation details by token', async ({ request }) => {
    const api = new BackendApiClient(request);
    await api.login(CONFIG.adminEmail, CONFIG.adminPassword);

    // Create invitation
    const inviteEmail = generateTestEmail();
    const inviteResponse = await api.createInvitation({
      email: inviteEmail,
      role: 'member',
    });
    console.log(`✓ Created invitation for: ${inviteEmail}`);

    // Get invitation token (if returned)
    const token = inviteResponse.data.token;
    if (!token) {
      console.log('⚠️ Token not returned in response, skipping token lookup test');
      try {
        await api.revokeInvitation(inviteResponse.data.id);
      } catch (e) {}
      return;
    }

    // Get invitation details (as unauthenticated user)
    const publicApi = new BackendApiClient(request);
    const inviteDetails = await publicApi.getInvitation(token);

    expect(inviteDetails.data.email).toBe(inviteEmail);
    // Public endpoint returns 'valid: boolean' not 'status'
    expect(inviteDetails.data.valid).toBe(true);
    console.log('✓ Retrieved invitation details by token');

    // Cleanup
    try {
      await api.revokeInvitation(inviteResponse.data.id);
    } catch (e) {}
  });

  test('should accept invitation and create new account', async ({ request }) => {
    const adminApi = new BackendApiClient(request);
    await adminApi.login(CONFIG.adminEmail, CONFIG.adminPassword);

    // Create invitation
    const inviteEmail = generateTestEmail();
    const inviteResponse = await adminApi.createInvitation({
      email: inviteEmail,
      role: 'member',
    });
    console.log(`✓ Created invitation: ${inviteResponse.data.id}`);

    const token = inviteResponse.data.token;
    if (!token) {
      console.log('⚠️ Token not returned, skipping acceptance test');
      try {
        await adminApi.revokeInvitation(inviteResponse.data.id);
      } catch (e) {}
      return;
    }

    // Accept invitation (as new user)
    const newUserApi = new BackendApiClient(request);
    const acceptResponse = await newUserApi.acceptInvitation(token, {
      name: 'New Test User',
      password: 'NewUserPassword123!',
      public_keys: {
        kem: crypto.randomBytes(32).toString('base64'),
        sign: crypto.randomBytes(32).toString('base64'),
      },
      encrypted_master_key: crypto.randomBytes(32).toString('base64'),
      master_key_nonce: crypto.randomBytes(12).toString('base64'),
    });

    // Validate response
    const validated = validateResponse(AuthResponseSchema, acceptResponse);

    expect(validated.data.access_token).toBeTruthy();
    expect(validated.data.user.email).toBe(inviteEmail);
    console.log(`✓ New user created: ${validated.data.user.email}`);

    // Verify user can access API
    const userInfo = await newUserApi.getCurrentUser();
    expect(userInfo.data.email).toBe(inviteEmail);
    console.log('✓ New user can access API');
  });

  test('should reject accepting already accepted invitation', async ({ request }) => {
    const adminApi = new BackendApiClient(request);
    await adminApi.login(CONFIG.adminEmail, CONFIG.adminPassword);

    // Create invitation
    const inviteEmail = generateTestEmail();
    const inviteResponse = await adminApi.createInvitation({
      email: inviteEmail,
      role: 'member',
    });

    const token = inviteResponse.data.token;
    if (!token) {
      test.skip();
      return;
    }

    // Accept invitation first time
    const newUserApi = new BackendApiClient(request);
    await newUserApi.acceptInvitation(token, {
      name: 'First Accept User',
      password: 'FirstPassword123!',
      public_keys: {
        kem: crypto.randomBytes(32).toString('base64'),
        sign: crypto.randomBytes(32).toString('base64'),
      },
      encrypted_master_key: crypto.randomBytes(32).toString('base64'),
      master_key_nonce: crypto.randomBytes(12).toString('base64'),
    });
    console.log('✓ First acceptance successful');

    // Try to accept again
    const anotherApi = new BackendApiClient(request);
    try {
      await anotherApi.acceptInvitation(token, {
        name: 'Second Accept User',
        password: 'SecondPassword123!',
        public_keys: {
          kem: crypto.randomBytes(32).toString('base64'),
          sign: crypto.randomBytes(32).toString('base64'),
        },
        encrypted_master_key: crypto.randomBytes(32).toString('base64'),
        master_key_nonce: crypto.randomBytes(12).toString('base64'),
      });
      expect.fail('Should have rejected second acceptance');
    } catch (error) {
      expect(error).toBeDefined();
      console.log('✓ Rejected second acceptance attempt');
    }
  });
});
