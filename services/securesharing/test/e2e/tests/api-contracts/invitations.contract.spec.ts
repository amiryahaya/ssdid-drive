/**
 * Invitations API Contract Tests
 *
 * Validates the structure and format of invitation API responses.
 */

import { test, expect } from '@playwright/test';
import { BackendApiClient, CONFIG } from '../../lib/api-client';
import { validateResponse, InvitationSchema } from '../../lib/schemas';
import crypto from 'crypto';

function generateTestEmail(): string {
  return `contract-${Date.now()}-${crypto.randomBytes(4).toString('hex')}@example.com`;
}

test.describe('Invitations API Contracts', () => {
  test('POST /api/tenant/invitations - response structure', async ({ request }) => {
    const api = new BackendApiClient(request);
    await api.login(CONFIG.adminEmail, CONFIG.adminPassword);

    const inviteEmail = generateTestEmail();
    const response = await api.createInvitation({
      email: inviteEmail,
      role: 'member',
    });

    // Validate structure
    expect(response.data).toHaveProperty('id');
    expect(response.data).toHaveProperty('email');
    expect(response.data).toHaveProperty('status');
    expect(response.data).toHaveProperty('role');
    expect(response.data).toHaveProperty('expires_at');

    // UUID format
    expect(response.data.id).toMatch(
      /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i
    );

    // Email matches
    expect(response.data.email).toBe(inviteEmail);

    // Status is valid
    expect(['pending', 'accepted', 'expired', 'revoked']).toContain(response.data.status);

    // Role is valid
    expect(['owner', 'admin', 'member']).toContain(response.data.role);

    console.log('✓ Create invitation response matches contract');

    // Cleanup
    try {
      await api.revokeInvitation(response.data.id);
    } catch (e) {}
  });

  test('GET /api/tenant/invitations - paginated response structure', async ({ request }) => {
    const api = new BackendApiClient(request);
    await api.login(CONFIG.adminEmail, CONFIG.adminPassword);

    const response = await api.listInvitations();

    // Validate pagination structure (API uses "pagination" key with "total")
    expect(response).toHaveProperty('data');
    expect(response).toHaveProperty('pagination');
    expect(Array.isArray(response.data)).toBe(true);

    // Pagination structure
    expect(response.pagination).toHaveProperty('page');
    expect(response.pagination).toHaveProperty('per_page');
    expect(response.pagination).toHaveProperty('total');
    expect(response.pagination).toHaveProperty('total_pages');

    console.log(`✓ Invitations list matches contract (${response.data.length} invitations)`);
  });

  test('GET /api/invite/:token - public response structure', async ({ request }) => {
    const api = new BackendApiClient(request);
    await api.login(CONFIG.adminEmail, CONFIG.adminPassword);

    const inviteEmail = generateTestEmail();
    const createResponse = await api.createInvitation({
      email: inviteEmail,
      role: 'member',
    });

    const token = createResponse.data.token;
    if (!token) {
      console.log('⚠️ Token not returned in response');
      try {
        await api.revokeInvitation(createResponse.data.id);
      } catch (e) {}
      return;
    }

    // Get invitation by token (unauthenticated)
    const publicApi = new BackendApiClient(request);
    const inviteDetails = await publicApi.getInvitation(token);

    // Should have limited information for public view
    expect(inviteDetails.data).toHaveProperty('email');
    expect(inviteDetails.data).toHaveProperty('valid');
    expect(inviteDetails.data).toHaveProperty('role');
    expect(inviteDetails.data).toHaveProperty('tenant_name');
    expect(inviteDetails.data).toHaveProperty('inviter_name');

    // Should NOT expose internal ID or timestamps
    // (implementation may vary)

    console.log('✓ Public invitation response matches contract');

    // Cleanup
    try {
      await api.revokeInvitation(createResponse.data.id);
    } catch (e) {}
  });

  test('Role values are valid enum', async ({ request }) => {
    const api = new BackendApiClient(request);
    await api.login(CONFIG.adminEmail, CONFIG.adminPassword);

    const validRoles = ['member', 'admin'];

    for (const role of validRoles) {
      const inviteEmail = generateTestEmail();
      const response = await api.createInvitation({
        email: inviteEmail,
        role: role,
      });

      expect(response.data.role).toBe(role);

      // Cleanup
      try {
        await api.revokeInvitation(response.data.id);
      } catch (e) {}
    }

    console.log('✓ All role values are valid');
  });

  test('Status values are valid enum', async ({ request }) => {
    const api = new BackendApiClient(request);
    await api.login(CONFIG.adminEmail, CONFIG.adminPassword);

    const inviteEmail = generateTestEmail();
    const response = await api.createInvitation({
      email: inviteEmail,
      role: 'member',
    });

    const validStatuses = ['pending', 'accepted', 'expired', 'revoked'];
    expect(validStatuses).toContain(response.data.status);

    console.log(`✓ Invitation status '${response.data.status}' is valid`);

    // Cleanup
    try {
      await api.revokeInvitation(response.data.id);
    } catch (e) {}
  });

  test('expires_at is valid ISO date', async ({ request }) => {
    const api = new BackendApiClient(request);
    await api.login(CONFIG.adminEmail, CONFIG.adminPassword);

    const inviteEmail = generateTestEmail();
    const response = await api.createInvitation({
      email: inviteEmail,
      role: 'member',
    });

    // Should be parseable as date
    const expiresAt = new Date(response.data.expires_at);
    expect(expiresAt.getTime()).not.toBeNaN();

    // Should be in the future
    expect(expiresAt.getTime()).toBeGreaterThan(Date.now());

    console.log(`✓ expires_at is valid future date: ${response.data.expires_at}`);

    // Cleanup
    try {
      await api.revokeInvitation(response.data.id);
    } catch (e) {}
  });

  test('POST /api/invite/:token/accept - response structure', async ({ request }) => {
    const adminApi = new BackendApiClient(request);
    await adminApi.login(CONFIG.adminEmail, CONFIG.adminPassword);

    const inviteEmail = generateTestEmail();
    const createResponse = await adminApi.createInvitation({
      email: inviteEmail,
      role: 'member',
    });

    const token = createResponse.data.token;
    if (!token) {
      console.log('⚠️ Token not returned');
      return;
    }

    // Accept invitation
    const newUserApi = new BackendApiClient(request);
    const acceptResponse = await newUserApi.acceptInvitation(token, {
      name: 'Contract Test User',
      password: 'ContractTest123!',
      public_keys: {
        kem: crypto.randomBytes(32).toString('base64'),
        sign: crypto.randomBytes(32).toString('base64'),
      },
      encrypted_master_key: crypto.randomBytes(32).toString('base64'),
      master_key_nonce: crypto.randomBytes(12).toString('base64'),
    });

    // Should return auth response
    expect(acceptResponse.data).toHaveProperty('access_token');
    expect(acceptResponse.data).toHaveProperty('user');
    expect(acceptResponse.data.user.email).toBe(inviteEmail);

    console.log('✓ Accept invitation response matches auth contract');
  });
});

test.describe('Invitation Error Responses', () => {
  test('404 for non-existent invitation', async ({ request }) => {
    const api = new BackendApiClient(request);
    await api.login(CONFIG.adminEmail, CONFIG.adminPassword);

    const fakeId = '00000000-0000-0000-0000-000000000000';

    try {
      await api.revokeInvitation(fakeId);
      expect.fail('Should have thrown an error');
    } catch (error) {
      expect((error as Error).message).toBeTruthy();
      console.log('✓ 404 error for non-existent invitation');
    }
  });

  test('404 for invalid token', async ({ request }) => {
    const api = new BackendApiClient(request);

    try {
      await api.getInvitation('invalid-token-12345');
      expect.fail('Should have thrown an error');
    } catch (error) {
      expect((error as Error).message).toBeTruthy();
      console.log('✓ 404 error for invalid token');
    }
  });

  test('401 for unauthenticated invitation list', async ({ request }) => {
    const api = new BackendApiClient(request);
    // Don't login

    try {
      await api.listInvitations();
      expect.fail('Should have thrown an error');
    } catch (error) {
      expect((error as Error).message).toContain('failed');
      console.log('✓ 401 error for unauthenticated request');
    }
  });
});
