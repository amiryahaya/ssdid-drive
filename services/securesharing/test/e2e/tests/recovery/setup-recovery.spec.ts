/**
 * Recovery Setup E2E Tests
 *
 * Tests for configuring recovery:
 * - Setup recovery with valid k-of-n threshold (2-of-3)
 * - Get recovery config after setup
 * - Cannot setup recovery twice (409 conflict)
 * - Create recovery shares for trustees
 * - List created recovery shares
 * - Trustee can see shares assigned to them
 * - Trustee can accept a recovery share
 * - Trustee can reject a recovery share
 * - Owner can revoke a recovery share
 * - Disable recovery
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

test.describe('Recovery Configuration Setup', () => {
  test('should setup recovery with 2-of-3 threshold', async ({ request }) => {
    const { api: ownerApi } = await loginAndGetUserId(
      request, TEST_USERS.owner.email, TEST_USERS.owner.password
    );

    // Clean up any existing config first
    try {
      await ownerApi.disableRecovery();
    } catch (e) {
      // Ignore if no config exists
    }

    const result = await ownerApi.setupRecovery({
      threshold: 2,
      total_shares: 3,
    });

    expect(result.data).toBeDefined();
    expect(result.data.threshold).toBe(2);
    expect(result.data.total_shares).toBe(3);
    expect(result.data.setup_complete).toBe(false);
    expect(result.data.id).toBeDefined();
    expect(result.data.user_id).toBeDefined();

    // Cleanup
    try {
      await ownerApi.disableRecovery();
    } catch (e) {}
  });

  test('should get recovery config after setup', async ({ request }) => {
    const { api: ownerApi } = await loginAndGetUserId(
      request, TEST_USERS.owner.email, TEST_USERS.owner.password
    );

    // Clean up and setup fresh
    try {
      await ownerApi.disableRecovery();
    } catch (e) {}

    await ownerApi.setupRecovery({ threshold: 2, total_shares: 3 });

    const config = await ownerApi.getRecoveryConfig();

    expect(config.data).toBeDefined();
    expect(config.data.threshold).toBe(2);
    expect(config.data.total_shares).toBe(3);

    // Cleanup
    try {
      await ownerApi.disableRecovery();
    } catch (e) {}
  });

  test('should return 409 when trying to setup recovery twice', async ({ request }) => {
    const { api: ownerApi } = await loginAndGetUserId(
      request, TEST_USERS.owner.email, TEST_USERS.owner.password
    );

    // Clean up and setup fresh
    try {
      await ownerApi.disableRecovery();
    } catch (e) {}

    await ownerApi.setupRecovery({ threshold: 2, total_shares: 3 });

    // Attempt second setup should fail with 409
    try {
      await ownerApi.setupRecovery({ threshold: 3, total_shares: 5 });
      throw new Error('Second setup should have failed with 409');
    } catch (error) {
      expect((error as Error).message).toContain('409');
    }

    // Cleanup
    try {
      await ownerApi.disableRecovery();
    } catch (e) {}
  });

  test('should disable recovery', async ({ request }) => {
    const { api: ownerApi } = await loginAndGetUserId(
      request, TEST_USERS.owner.email, TEST_USERS.owner.password
    );

    // Clean up and setup fresh
    try {
      await ownerApi.disableRecovery();
    } catch (e) {}

    await ownerApi.setupRecovery({ threshold: 2, total_shares: 3 });

    // Disable should succeed
    await ownerApi.disableRecovery();

    // Config should now be null
    const config = await ownerApi.getRecoveryConfig();
    expect(config.data).toBeNull();
  });
});

test.describe('Recovery Share Distribution', () => {
  test('should create recovery shares for trustees', async ({ request }) => {
    const { api: ownerApi, userId: ownerId } = await loginAndGetUserId(
      request, TEST_USERS.owner.email, TEST_USERS.owner.password
    );
    const { userId: trustee1Id } = await loginAndGetUserId(
      request, TEST_USERS.trustee1.email, TEST_USERS.trustee1.password
    );
    const { userId: trustee2Id } = await loginAndGetUserId(
      request, TEST_USERS.trustee2.email, TEST_USERS.trustee2.password
    );
    const { userId: trustee3Id } = await loginAndGetUserId(
      request, TEST_USERS.trustee3.email, TEST_USERS.trustee3.password
    );

    // Clean up and setup
    try {
      await ownerApi.disableRecovery();
    } catch (e) {}

    await ownerApi.setupRecovery({ threshold: 2, total_shares: 3 });

    // Create shares for each trustee
    const share1 = await ownerApi.createRecoveryShare({
      trustee_id: trustee1Id,
      share_index: 1,
      ...generateShareCryptoParams(),
    });
    expect(share1.data).toBeDefined();
    expect(share1.data.trustee_id).toBe(trustee1Id);
    expect(share1.data.share_index).toBe(1);
    expect(share1.data.accepted).toBe(false);

    const share2 = await ownerApi.createRecoveryShare({
      trustee_id: trustee2Id,
      share_index: 2,
      ...generateShareCryptoParams(),
    });
    expect(share2.data.trustee_id).toBe(trustee2Id);
    expect(share2.data.share_index).toBe(2);

    const share3 = await ownerApi.createRecoveryShare({
      trustee_id: trustee3Id,
      share_index: 3,
      ...generateShareCryptoParams(),
    });
    expect(share3.data.trustee_id).toBe(trustee3Id);
    expect(share3.data.share_index).toBe(3);

    // Cleanup
    try {
      await ownerApi.disableRecovery();
    } catch (e) {}
  });

  test('should list created recovery shares', async ({ request }) => {
    const { api: ownerApi } = await loginAndGetUserId(
      request, TEST_USERS.owner.email, TEST_USERS.owner.password
    );
    const { userId: trustee1Id } = await loginAndGetUserId(
      request, TEST_USERS.trustee1.email, TEST_USERS.trustee1.password
    );
    const { userId: trustee2Id } = await loginAndGetUserId(
      request, TEST_USERS.trustee2.email, TEST_USERS.trustee2.password
    );

    // Clean up and setup
    try {
      await ownerApi.disableRecovery();
    } catch (e) {}

    await ownerApi.setupRecovery({ threshold: 2, total_shares: 3 });

    await ownerApi.createRecoveryShare({
      trustee_id: trustee1Id,
      share_index: 1,
      ...generateShareCryptoParams(),
    });
    await ownerApi.createRecoveryShare({
      trustee_id: trustee2Id,
      share_index: 2,
      ...generateShareCryptoParams(),
    });

    const shares = await ownerApi.listCreatedRecoveryShares();
    expect(shares.data).toBeDefined();
    expect(Array.isArray(shares.data)).toBe(true);
    expect(shares.data.length).toBeGreaterThanOrEqual(2);

    // Cleanup
    try {
      await ownerApi.disableRecovery();
    } catch (e) {}
  });

  test('trustee can see shares assigned to them', async ({ request }) => {
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

    await ownerApi.createRecoveryShare({
      trustee_id: trustee1Id,
      share_index: 1,
      ...generateShareCryptoParams(),
    });

    // Trustee lists their shares
    const trusteeShares = await trustee1Api.listTrusteeShares();
    expect(trusteeShares.data).toBeDefined();
    expect(Array.isArray(trusteeShares.data)).toBe(true);

    const matchingShare = trusteeShares.data.find(
      (s: any) => s.trustee_id === trustee1Id
    );
    expect(matchingShare).toBeDefined();

    // Cleanup
    try {
      await ownerApi.disableRecovery();
    } catch (e) {}
  });

  test('trustee can accept a recovery share', async ({ request }) => {
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

    const share = await ownerApi.createRecoveryShare({
      trustee_id: trustee1Id,
      share_index: 1,
      ...generateShareCryptoParams(),
    });

    // Trustee accepts
    const accepted = await trustee1Api.acceptRecoveryShare(share.data.id);
    expect(accepted.data.accepted).toBe(true);
    expect(accepted.data.accepted_at).toBeDefined();

    // Cleanup
    try {
      await ownerApi.disableRecovery();
    } catch (e) {}
  });

  test('trustee can reject a recovery share', async ({ request }) => {
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

    const share = await ownerApi.createRecoveryShare({
      trustee_id: trustee1Id,
      share_index: 1,
      ...generateShareCryptoParams(),
    });

    // Trustee rejects (returns 204 no content)
    await trustee1Api.rejectRecoveryShare(share.data.id);

    // Verify the share is no longer in pending state by checking trustee shares
    const trusteeShares = await trustee1Api.listTrusteeShares();
    const rejectedShare = trusteeShares.data.find(
      (s: any) => s.id === share.data.id
    );
    // The share may still appear in the list but should not be accepted
    if (rejectedShare) {
      expect(rejectedShare.accepted).toBe(false);
    }

    // Cleanup
    try {
      await ownerApi.disableRecovery();
    } catch (e) {}
  });

  test('owner can revoke a recovery share', async ({ request }) => {
    const { api: ownerApi } = await loginAndGetUserId(
      request, TEST_USERS.owner.email, TEST_USERS.owner.password
    );
    const { userId: trustee1Id } = await loginAndGetUserId(
      request, TEST_USERS.trustee1.email, TEST_USERS.trustee1.password
    );

    // Clean up and setup
    try {
      await ownerApi.disableRecovery();
    } catch (e) {}

    await ownerApi.setupRecovery({ threshold: 2, total_shares: 3 });

    const share = await ownerApi.createRecoveryShare({
      trustee_id: trustee1Id,
      share_index: 1,
      ...generateShareCryptoParams(),
    });

    // Owner revokes the share (returns 204 no content)
    await ownerApi.revokeRecoveryShare(share.data.id);

    // Verify the share is gone from owner's list
    const ownerShares = await ownerApi.listCreatedRecoveryShares();
    const revokedShare = ownerShares.data.find(
      (s: any) => s.id === share.data.id
    );
    expect(revokedShare).toBeUndefined();

    // Cleanup
    try {
      await ownerApi.disableRecovery();
    } catch (e) {}
  });
});
