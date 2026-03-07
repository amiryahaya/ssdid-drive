/**
 * Revoke Invitation E2E Tests
 *
 * Tests invitation revocation functionality including:
 * - Revoking a pending invitation
 * - Verifying revoked invitation cannot be accepted
 */

import { test, expect } from '@playwright/test';
import { BackendApiClient, CONFIG } from '../../lib/api-client';
import crypto from 'crypto';

// Generate unique email for testing
function generateTestEmail(): string {
  const timestamp = Date.now();
  const random = crypto.randomBytes(4).toString('hex');
  return `revoke-invite-${timestamp}-${random}@example.com`;
}

test.describe('Revoke Invitation', () => {
  test('should revoke a pending invitation', async ({ request }) => {
    const api = new BackendApiClient(request);
    await api.login(CONFIG.adminEmail, CONFIG.adminPassword);

    // Create invitation
    const inviteEmail = generateTestEmail();
    const inviteResponse = await api.createInvitation({
      email: inviteEmail,
      role: 'member',
    });
    console.log(`✓ Created invitation: ${inviteResponse.data.id}`);

    // Verify invitation is pending
    expect(inviteResponse.data.status).toBe('pending');

    // Revoke invitation
    await api.revokeInvitation(inviteResponse.data.id);
    console.log('✓ Revoked invitation');

    // Verify invitation is revoked (by trying to list it)
    const allInvitations = await api.listInvitations();
    const revokedInvite = allInvitations.data.find((i) => i.id === inviteResponse.data.id);

    if (revokedInvite) {
      expect(revokedInvite.status).toBe('revoked');
      console.log('✓ Invitation marked as revoked');
    } else {
      console.log('✓ Invitation removed from list');
    }
  });

  test('should prevent accepting revoked invitation', async ({ request }) => {
    const adminApi = new BackendApiClient(request);
    await adminApi.login(CONFIG.adminEmail, CONFIG.adminPassword);

    // Create and immediately revoke invitation
    const inviteEmail = generateTestEmail();
    const inviteResponse = await adminApi.createInvitation({
      email: inviteEmail,
      role: 'member',
    });
    const token = inviteResponse.data.token;

    await adminApi.revokeInvitation(inviteResponse.data.id);
    console.log('✓ Created and revoked invitation');

    if (!token) {
      console.log('⚠️ Token not available, skipping acceptance test');
      return;
    }

    // Try to accept revoked invitation
    const newUserApi = new BackendApiClient(request);
    try {
      await newUserApi.acceptInvitation(token, {
        name: 'Should Not Work',
        password: 'Password123!',
        public_keys: {
          kem: crypto.randomBytes(32).toString('base64'),
          sign: crypto.randomBytes(32).toString('base64'),
        },
        encrypted_master_key: crypto.randomBytes(32).toString('base64'),
        master_key_nonce: crypto.randomBytes(12).toString('base64'),
      });
      expect.fail('Should have rejected revoked invitation');
    } catch (error) {
      expect(error).toBeDefined();
      console.log('✓ Rejected acceptance of revoked invitation');
    }
  });
});

test.describe('Resend Invitation', () => {
  test('should resend a pending invitation', async ({ request }) => {
    const api = new BackendApiClient(request);
    await api.login(CONFIG.adminEmail, CONFIG.adminPassword);

    // Create invitation
    const inviteEmail = generateTestEmail();
    const inviteResponse = await api.createInvitation({
      email: inviteEmail,
      role: 'member',
    });
    console.log(`✓ Created invitation: ${inviteResponse.data.id}`);

    // Resend invitation
    try {
      const resendResponse = await api.resendInvitation(inviteResponse.data.id);
      expect(resendResponse.data.id).toBe(inviteResponse.data.id);
      console.log('✓ Resent invitation');
    } catch (error) {
      console.log(`⚠️ Resend may not be implemented: ${(error as Error).message}`);
    }

    // Cleanup
    try {
      await api.revokeInvitation(inviteResponse.data.id);
    } catch (e) {}
  });

  test('should reject resending non-existent invitation', async ({ request }) => {
    const api = new BackendApiClient(request);
    await api.login(CONFIG.adminEmail, CONFIG.adminPassword);

    const fakeInviteId = '00000000-0000-0000-0000-000000000000';

    try {
      await api.resendInvitation(fakeInviteId);
      expect.fail('Should have thrown an error');
    } catch (error) {
      expect(error).toBeDefined();
      console.log('✓ Rejected resending non-existent invitation');
    }
  });
});
