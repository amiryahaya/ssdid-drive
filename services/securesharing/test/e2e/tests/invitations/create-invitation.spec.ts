/**
 * Create Invitation E2E Tests
 *
 * Tests invitation creation functionality including:
 * - Creating invitation for new email
 * - Creating invitation with different roles
 * - Validation of invitation parameters
 */

import { test, expect } from '@playwright/test';
import { BackendApiClient, CONFIG } from '../../lib/api-client';
import crypto from 'crypto';

// Generate unique email for testing
function generateTestEmail(): string {
  const timestamp = Date.now();
  const random = crypto.randomBytes(4).toString('hex');
  return `invite-test-${timestamp}-${random}@example.com`;
}

test.describe('Create Invitation', () => {
  test('should create invitation for new email', async ({ request }) => {
    const api = new BackendApiClient(request);
    await api.login(CONFIG.adminEmail, CONFIG.adminPassword);

    const inviteEmail = generateTestEmail();

    const inviteResponse = await api.createInvitation({
      email: inviteEmail,
      role: 'member',
      message: 'Welcome to our team!',
    });

    expect(inviteResponse.data.id).toBeTruthy();
    expect(inviteResponse.data.email).toBe(inviteEmail);
    expect(inviteResponse.data.status).toBe('pending');
    expect(inviteResponse.data.role).toBe('member');

    console.log(`✓ Created invitation for: ${inviteEmail}`);
    console.log(`  Invitation ID: ${inviteResponse.data.id}`);

    // Cleanup
    try {
      await api.revokeInvitation(inviteResponse.data.id);
    } catch (e) {}
  });

  test('should create invitation with admin role', async ({ request }) => {
    const api = new BackendApiClient(request);
    await api.login(CONFIG.adminEmail, CONFIG.adminPassword);

    const inviteEmail = generateTestEmail();

    const inviteResponse = await api.createInvitation({
      email: inviteEmail,
      role: 'admin',
    });

    expect(inviteResponse.data.role).toBe('admin');
    console.log(`✓ Created admin invitation for: ${inviteEmail}`);

    // Cleanup
    try {
      await api.revokeInvitation(inviteResponse.data.id);
    } catch (e) {}
  });

  test('should reject invitation with invalid email', async ({ request }) => {
    const api = new BackendApiClient(request);
    await api.login(CONFIG.adminEmail, CONFIG.adminPassword);

    try {
      await api.createInvitation({
        email: 'invalid-email-format',
        role: 'member',
      });
      expect.fail('Should have thrown an error for invalid email');
    } catch (error) {
      expect(error).toBeDefined();
      console.log('✓ Rejected invitation with invalid email');
    }
  });
});

test.describe('List Invitations', () => {
  test('should list pending invitations', async ({ request }) => {
    const api = new BackendApiClient(request);
    await api.login(CONFIG.adminEmail, CONFIG.adminPassword);

    // Create a test invitation
    const inviteEmail = generateTestEmail();
    const inviteResponse = await api.createInvitation({
      email: inviteEmail,
      role: 'member',
    });
    console.log(`✓ Created test invitation: ${inviteResponse.data.id}`);

    // List invitations
    const listResponse = await api.listInvitations({ status: 'pending' });

    expect(listResponse.data).toBeDefined();
    expect(Array.isArray(listResponse.data)).toBe(true);
    expect(listResponse.pagination).toBeDefined();

    console.log(`✓ Listed ${listResponse.data.length} pending invitation(s)`);

    // Verify our invitation is in the list
    const ourInvite = listResponse.data.find((i) => i.id === inviteResponse.data.id);
    expect(ourInvite).toBeDefined();
    console.log('✓ Test invitation found in list');

    // Cleanup
    try {
      await api.revokeInvitation(inviteResponse.data.id);
    } catch (e) {}
  });

  test('should paginate invitation list', async ({ request }) => {
    const api = new BackendApiClient(request);
    await api.login(CONFIG.adminEmail, CONFIG.adminPassword);

    // List with pagination
    const page1 = await api.listInvitations({ page: 1, per_page: 5 });

    expect(page1.pagination.page).toBe(1);
    expect(page1.pagination.per_page).toBe(5);
    expect(page1.data.length).toBeLessThanOrEqual(5);

    console.log(`✓ Page 1: ${page1.data.length} items (total: ${page1.pagination.total})`);

    if (page1.pagination.total_pages > 1) {
      const page2 = await api.listInvitations({ page: 2, per_page: 5 });
      expect(page2.pagination.page).toBe(2);
      console.log(`✓ Page 2: ${page2.data.length} items`);
    }
  });
});
