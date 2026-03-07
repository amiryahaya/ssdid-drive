/**
 * Full Recovery Flow E2E Tests
 *
 * End-to-end recovery flow:
 * - Owner sets up 2-of-3 recovery
 * - Owner distributes shares to 3 trustees
 * - All trustees accept their shares
 * - Owner creates recovery request
 * - 2 trustees approve the request (reaching threshold)
 * - Owner completes recovery with new key material
 * - Verify recovery request status shows completed
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

test.describe('Full Recovery Flow', () => {
  test('complete 2-of-3 recovery flow from setup to completion', async ({ request }) => {
    // Step 1: Login all users and get their IDs
    const { api: ownerApi, userId: ownerId } = await loginAndGetUserId(
      request, TEST_USERS.owner.email, TEST_USERS.owner.password
    );
    const { api: trustee1Api, userId: trustee1Id } = await loginAndGetUserId(
      request, TEST_USERS.trustee1.email, TEST_USERS.trustee1.password
    );
    const { api: trustee2Api, userId: trustee2Id } = await loginAndGetUserId(
      request, TEST_USERS.trustee2.email, TEST_USERS.trustee2.password
    );
    const { api: trustee3Api, userId: trustee3Id } = await loginAndGetUserId(
      request, TEST_USERS.trustee3.email, TEST_USERS.trustee3.password
    );

    // Clean up any existing recovery config
    try {
      await ownerApi.disableRecovery();
    } catch (e) {
      // Ignore if no config exists
    }

    // Step 2: Owner sets up 2-of-3 recovery
    const setupResult = await ownerApi.setupRecovery({
      threshold: 2,
      total_shares: 3,
    });
    expect(setupResult.data.threshold).toBe(2);
    expect(setupResult.data.total_shares).toBe(3);

    // Step 3: Owner distributes shares to 3 trustees
    const share1 = await ownerApi.createRecoveryShare({
      trustee_id: trustee1Id,
      share_index: 1,
      ...generateShareCryptoParams(),
    });
    expect(share1.data.id).toBeDefined();

    const share2 = await ownerApi.createRecoveryShare({
      trustee_id: trustee2Id,
      share_index: 2,
      ...generateShareCryptoParams(),
    });
    expect(share2.data.id).toBeDefined();

    const share3 = await ownerApi.createRecoveryShare({
      trustee_id: trustee3Id,
      share_index: 3,
      ...generateShareCryptoParams(),
    });
    expect(share3.data.id).toBeDefined();

    // Step 4: All trustees accept their shares
    const accepted1 = await trustee1Api.acceptRecoveryShare(share1.data.id);
    expect(accepted1.data.accepted).toBe(true);

    const accepted2 = await trustee2Api.acceptRecoveryShare(share2.data.id);
    expect(accepted2.data.accepted).toBe(true);

    const accepted3 = await trustee3Api.acceptRecoveryShare(share3.data.id);
    expect(accepted3.data.accepted).toBe(true);

    // Step 5: Owner creates recovery request
    const newPublicKey = crypto.randomBytes(32).toString('base64');
    const recoveryRequest = await ownerApi.createRecoveryRequest({
      new_public_key: newPublicKey,
      reason: 'Lost device - E2E test',
    });
    expect(recoveryRequest.data.id).toBeDefined();
    expect(recoveryRequest.data.status).toBe('pending');
    expect(recoveryRequest.data.reason).toBe('Lost device - E2E test');

    const requestId = recoveryRequest.data.id;

    // Verify trustees can see pending requests
    const pendingForTrustee1 = await trustee1Api.listPendingRecoveryRequests();
    expect(pendingForTrustee1.data).toBeDefined();
    const matchingRequest = pendingForTrustee1.data.find(
      (r: any) => r.id === requestId
    );
    expect(matchingRequest).toBeDefined();

    // Step 6: First trustee approves
    const approval1 = await trustee1Api.approveRecoveryRequest(requestId, {
      share_id: share1.data.id,
      ...generateApprovalCryptoParams(),
    });
    expect(approval1.data.id).toBeDefined();
    expect(approval1.data.trustee_id).toBe(trustee1Id);

    // Check progress after first approval (1/2)
    const progressAfter1 = await ownerApi.getRecoveryRequest(requestId);
    expect(progressAfter1.data.progress.approvals).toBe(1);
    expect(progressAfter1.data.progress.threshold).toBe(2);

    // Step 7: Second trustee approves (reaches threshold)
    const approval2 = await trustee2Api.approveRecoveryRequest(requestId, {
      share_id: share2.data.id,
      ...generateApprovalCryptoParams(),
    });
    expect(approval2.data.id).toBeDefined();
    expect(approval2.data.trustee_id).toBe(trustee2Id);

    // Check progress after second approval (2/2 - threshold reached)
    const progressAfter2 = await ownerApi.getRecoveryRequest(requestId);
    expect(progressAfter2.data.progress.approvals).toBe(2);
    expect(progressAfter2.data.progress.threshold).toBe(2);
    // Request status should be 'approved' after threshold is reached
    expect(progressAfter2.data.status).toBe('approved');

    // Step 8: Owner completes recovery with new key material
    const completeResult = await ownerApi.completeRecovery(requestId, {
      encrypted_master_key: crypto.randomBytes(64).toString('base64'),
      encrypted_private_keys: crypto.randomBytes(128).toString('base64'),
      key_derivation_salt: crypto.randomBytes(32).toString('base64'),
      public_keys: {
        kem: crypto.randomBytes(1184).toString('base64'),
        sign: crypto.randomBytes(1312).toString('base64'),
      },
    });
    expect(completeResult.data).toBeDefined();
    expect(completeResult.data.message).toContain('Recovery completed');

    // Step 9: Verify the recovery request is now completed
    const finalRequest = await ownerApi.getRecoveryRequest(requestId);
    expect(finalRequest.data.status).toBe('completed');
    expect(finalRequest.data.completed_at).toBeDefined();

    // Cleanup
    try {
      await ownerApi.disableRecovery();
    } catch (e) {}
  });

  test('trustees can see recovery request in pending list', async ({ request }) => {
    const { api: ownerApi } = await loginAndGetUserId(
      request, TEST_USERS.owner.email, TEST_USERS.owner.password
    );
    const { api: trustee1Api, userId: trustee1Id } = await loginAndGetUserId(
      request, TEST_USERS.trustee1.email, TEST_USERS.trustee1.password
    );
    const { api: trustee2Api, userId: trustee2Id } = await loginAndGetUserId(
      request, TEST_USERS.trustee2.email, TEST_USERS.trustee2.password
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
    const share2 = await ownerApi.createRecoveryShare({
      trustee_id: trustee2Id,
      share_index: 2,
      ...generateShareCryptoParams(),
    });

    await trustee1Api.acceptRecoveryShare(share1.data.id);
    await trustee2Api.acceptRecoveryShare(share2.data.id);

    // Create recovery request
    const recoveryRequest = await ownerApi.createRecoveryRequest({
      new_public_key: crypto.randomBytes(32).toString('base64'),
      reason: 'Test pending list',
    });

    // Both trustees should see the pending request
    const pending1 = await trustee1Api.listPendingRecoveryRequests();
    const found1 = pending1.data.find((r: any) => r.id === recoveryRequest.data.id);
    expect(found1).toBeDefined();

    const pending2 = await trustee2Api.listPendingRecoveryRequests();
    const found2 = pending2.data.find((r: any) => r.id === recoveryRequest.data.id);
    expect(found2).toBeDefined();

    // Cleanup
    try {
      await ownerApi.cancelRecoveryRequest(recoveryRequest.data.id);
    } catch (e) {}
    try {
      await ownerApi.disableRecovery();
    } catch (e) {}
  });

  test('owner can list their recovery requests', async ({ request }) => {
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

    // Create a recovery request
    const recoveryRequest = await ownerApi.createRecoveryRequest({
      new_public_key: crypto.randomBytes(32).toString('base64'),
    });

    // Owner can list all their requests
    const requests = await ownerApi.listRecoveryRequests();
    expect(requests.data).toBeDefined();
    expect(Array.isArray(requests.data)).toBe(true);

    const found = requests.data.find((r: any) => r.id === recoveryRequest.data.id);
    expect(found).toBeDefined();
    expect(found.status).toBe('pending');

    // Cleanup
    try {
      await ownerApi.cancelRecoveryRequest(recoveryRequest.data.id);
    } catch (e) {}
    try {
      await ownerApi.disableRecovery();
    } catch (e) {}
  });
});
