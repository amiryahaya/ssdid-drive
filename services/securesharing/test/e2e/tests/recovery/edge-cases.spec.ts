/**
 * Recovery Edge Cases E2E Tests
 *
 * Tests for edge cases and error handling:
 * - Cannot complete recovery with insufficient approvals
 * - Cannot approve own recovery request
 * - Cannot create recovery request without config
 * - Cancel a pending recovery request
 * - Non-trustee cannot approve a recovery request
 * - Invalid share index returns error
 */

import { test, expect } from '@playwright/test';
import { BackendApiClient } from '../../lib/api-client';
import crypto from 'crypto';

// Test users from seed data
const TEST_USERS = {
  owner: {
    email: 'user1@e2e-test.local',
    password: 'TestUserPassword123!',
  },
  trustee1: {
    email: 'user2@e2e-test.local',
    password: 'TestUserPassword123!',
  },
  trustee2: {
    email: 'user3@e2e-test.local',
    password: 'TestUserPassword123!',
  },
  trustee3: {
    email: 'admin@e2e-test.local',
    password: 'E2eTestAdminPassword123!',
  },
};

// Helper to generate crypto params for recovery shares
function generateShareCryptoParams() {
  return {
    encrypted_share: crypto.randomBytes(64).toString('base64'),
    kem_ciphertext: crypto.randomBytes(1088).toString('base64'),
    signature: crypto.randomBytes(64).toString('base64'),
  };
}

// Helper to generate approval crypto params
function generateApprovalCryptoParams() {
  return {
    reencrypted_share: crypto.randomBytes(64).toString('base64'),
    kem_ciphertext: crypto.randomBytes(1088).toString('base64'),
    signature: crypto.randomBytes(64).toString('base64'),
  };
}

// Helper to login and get user ID
async function loginAndGetUserId(
  request: any,
  email: string,
  password: string
): Promise<{ api: BackendApiClient; userId: string }> {
  const api = new BackendApiClient(request);
  await api.login(email, password);
  const userInfo = await api.getCurrentUser();
  return { api, userId: userInfo.data.id };
}

test.describe('Recovery Edge Cases', () => {
  test('cannot complete recovery with insufficient approvals', async ({ request }) => {
    const { api: ownerApi } = await loginAndGetUserId(
      request, TEST_USERS.owner.email, TEST_USERS.owner.password
    );
    const { api: trustee1Api, userId: trustee1Id } = await loginAndGetUserId(
      request, TEST_USERS.trustee1.email, TEST_USERS.trustee1.password
    );
    const { userId: trustee2Id } = await loginAndGetUserId(
      request, TEST_USERS.trustee2.email, TEST_USERS.trustee2.password
    );

    // Clean up and setup 2-of-3 recovery
    try {
      await ownerApi.disableRecovery();
    } catch (e) {}

    await ownerApi.setupRecovery({ threshold: 2, total_shares: 3 });

    const share1 = await ownerApi.createRecoveryShare({
      trustee_id: trustee1Id,
      share_index: 1,
      ...generateShareCryptoParams(),
    });
    await ownerApi.createRecoveryShare({
      trustee_id: trustee2Id,
      share_index: 2,
      ...generateShareCryptoParams(),
    });

    await trustee1Api.acceptRecoveryShare(share1.data.id);

    // Create recovery request
    const recoveryRequest = await ownerApi.createRecoveryRequest({
      new_public_key: crypto.randomBytes(32).toString('base64'),
      reason: 'Test insufficient approvals',
    });

    // Only 1 trustee approves (need 2)
    await trustee1Api.approveRecoveryRequest(recoveryRequest.data.id, {
      share_id: share1.data.id,
      ...generateApprovalCryptoParams(),
    });

    // Attempt to complete should fail (threshold not reached, request still pending)
    try {
      await ownerApi.completeRecovery(recoveryRequest.data.id, {
        encrypted_master_key: crypto.randomBytes(64).toString('base64'),
        encrypted_private_keys: crypto.randomBytes(128).toString('base64'),
        key_derivation_salt: crypto.randomBytes(32).toString('base64'),
        public_keys: {
          kem: crypto.randomBytes(1184).toString('base64'),
          sign: crypto.randomBytes(1312).toString('base64'),
        },
      });
      throw new Error('Complete recovery should have failed with insufficient approvals');
    } catch (error) {
      // Should get 412 (threshold_not_reached) or 412 (request_not_approved)
      expect((error as Error).message).toMatch(/41[2]/);
    }

    // Cleanup
    try {
      await ownerApi.cancelRecoveryRequest(recoveryRequest.data.id);
    } catch (e) {}
    try {
      await ownerApi.disableRecovery();
    } catch (e) {}
  });

  test('cannot approve own recovery request (owner is not a trustee of own share)', async ({ request }) => {
    const { api: ownerApi, userId: ownerId } = await loginAndGetUserId(
      request, TEST_USERS.owner.email, TEST_USERS.owner.password
    );
    const { api: trustee1Api, userId: trustee1Id } = await loginAndGetUserId(
      request, TEST_USERS.trustee1.email, TEST_USERS.trustee1.password
    );

    // Clean up and setup
    try {
      await ownerApi.disableRecovery();
    } catch (e) {}

    await ownerApi.setupRecovery({ threshold: 2, total_shares: 3 });

    const share1 = await ownerApi.createRecoveryShare({
      trustee_id: trustee1Id,
      share_index: 1,
      ...generateShareCryptoParams(),
    });
    await trustee1Api.acceptRecoveryShare(share1.data.id);

    // Create recovery request
    const recoveryRequest = await ownerApi.createRecoveryRequest({
      new_public_key: crypto.randomBytes(32).toString('base64'),
    });

    // Owner tries to approve using trustee1's share -- should fail because
    // the verify_trustee check ensures the logged-in user is the trustee of the share
    try {
      await ownerApi.approveRecoveryRequest(recoveryRequest.data.id, {
        share_id: share1.data.id,
        ...generateApprovalCryptoParams(),
      });
      throw new Error('Owner should not be able to approve using a share they do not hold');
    } catch (error) {
      // Should get 403 (forbidden) since owner is not the trustee of share1
      expect((error as Error).message).toContain('403');
    }

    // Cleanup
    try {
      await ownerApi.cancelRecoveryRequest(recoveryRequest.data.id);
    } catch (e) {}
    try {
      await ownerApi.disableRecovery();
    } catch (e) {}
  });

  test('cannot create recovery request without config', async ({ request }) => {
    const { api: ownerApi } = await loginAndGetUserId(
      request, TEST_USERS.owner.email, TEST_USERS.owner.password
    );

    // Ensure no recovery config exists
    try {
      await ownerApi.disableRecovery();
    } catch (e) {}

    // Attempt to create a recovery request without a config
    try {
      await ownerApi.createRecoveryRequest({
        new_public_key: crypto.randomBytes(32).toString('base64'),
        reason: 'No config test',
      });
      throw new Error('Should not be able to create recovery request without config');
    } catch (error) {
      // Should get 404 (no_recovery_config)
      expect((error as Error).message).toContain('404');
    }
  });

  test('cancel a pending recovery request', async ({ request }) => {
    const { api: ownerApi } = await loginAndGetUserId(
      request, TEST_USERS.owner.email, TEST_USERS.owner.password
    );
    const { api: trustee1Api, userId: trustee1Id } = await loginAndGetUserId(
      request, TEST_USERS.trustee1.email, TEST_USERS.trustee1.password
    );

    // Clean up and setup
    try {
      await ownerApi.disableRecovery();
    } catch (e) {}

    await ownerApi.setupRecovery({ threshold: 2, total_shares: 3 });

    const share1 = await ownerApi.createRecoveryShare({
      trustee_id: trustee1Id,
      share_index: 1,
      ...generateShareCryptoParams(),
    });
    await trustee1Api.acceptRecoveryShare(share1.data.id);

    // Create recovery request
    const recoveryRequest = await ownerApi.createRecoveryRequest({
      new_public_key: crypto.randomBytes(32).toString('base64'),
      reason: 'Cancel test',
    });
    expect(recoveryRequest.data.status).toBe('pending');

    // Cancel the request
    await ownerApi.cancelRecoveryRequest(recoveryRequest.data.id);

    // Verify request is gone (should get 404)
    try {
      await ownerApi.getRecoveryRequest(recoveryRequest.data.id);
      throw new Error('Cancelled request should not be found');
    } catch (error) {
      expect((error as Error).message).toContain('404');
    }

    // Cleanup
    try {
      await ownerApi.disableRecovery();
    } catch (e) {}
  });

  test('non-trustee cannot approve a recovery request', async ({ request }) => {
    const { api: ownerApi } = await loginAndGetUserId(
      request, TEST_USERS.owner.email, TEST_USERS.owner.password
    );
    const { api: trustee1Api, userId: trustee1Id } = await loginAndGetUserId(
      request, TEST_USERS.trustee1.email, TEST_USERS.trustee1.password
    );
    const { api: trustee3Api, userId: trustee3Id } = await loginAndGetUserId(
      request, TEST_USERS.trustee3.email, TEST_USERS.trustee3.password
    );

    // Clean up and setup
    try {
      await ownerApi.disableRecovery();
    } catch (e) {}

    await ownerApi.setupRecovery({ threshold: 2, total_shares: 3 });

    // Only give share to trustee1 (not trustee3)
    const share1 = await ownerApi.createRecoveryShare({
      trustee_id: trustee1Id,
      share_index: 1,
      ...generateShareCryptoParams(),
    });
    await trustee1Api.acceptRecoveryShare(share1.data.id);

    // Create recovery request
    const recoveryRequest = await ownerApi.createRecoveryRequest({
      new_public_key: crypto.randomBytes(32).toString('base64'),
    });

    // Trustee3 (who does not hold a share) tries to approve using trustee1's share
    try {
      await trustee3Api.approveRecoveryRequest(recoveryRequest.data.id, {
        share_id: share1.data.id,
        ...generateApprovalCryptoParams(),
      });
      throw new Error('Non-trustee should not be able to approve');
    } catch (error) {
      // Should get 403 (forbidden) since trustee3 is not the trustee of share1
      expect((error as Error).message).toContain('403');
    }

    // Cleanup
    try {
      await ownerApi.cancelRecoveryRequest(recoveryRequest.data.id);
    } catch (e) {}
    try {
      await ownerApi.disableRecovery();
    } catch (e) {}
  });

  test('invalid share index returns error', async ({ request }) => {
    const { api: ownerApi } = await loginAndGetUserId(
      request, TEST_USERS.owner.email, TEST_USERS.owner.password
    );
    const { userId: trustee1Id } = await loginAndGetUserId(
      request, TEST_USERS.trustee1.email, TEST_USERS.trustee1.password
    );

    // Clean up and setup 2-of-3 recovery
    try {
      await ownerApi.disableRecovery();
    } catch (e) {}

    await ownerApi.setupRecovery({ threshold: 2, total_shares: 3 });

    // Attempt to create share with index 0 (out of bounds - must be >= 1)
    try {
      await ownerApi.createRecoveryShare({
        trustee_id: trustee1Id,
        share_index: 0,
        ...generateShareCryptoParams(),
      });
      throw new Error('Share index 0 should be rejected');
    } catch (error) {
      expect((error as Error).message).toMatch(/42[2]/);
    }

    // Attempt to create share with index > total_shares (4 > 3)
    try {
      await ownerApi.createRecoveryShare({
        trustee_id: trustee1Id,
        share_index: 4,
        ...generateShareCryptoParams(),
      });
      throw new Error('Share index 4 should be rejected for 3-share config');
    } catch (error) {
      expect((error as Error).message).toMatch(/42[2]/);
    }

    // Cleanup
    try {
      await ownerApi.disableRecovery();
    } catch (e) {}
  });
});
