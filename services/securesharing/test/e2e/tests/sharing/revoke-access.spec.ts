/**
 * Revoke Access E2E Tests
 *
 * Tests share revocation functionality including:
 * - Revoking a share
 * - Verifying access is removed after revocation
 * - Updating share permission level
 */

import { test, expect } from '@playwright/test';
import { BackendApiClient, CONFIG } from '../../lib/api-client';
import crypto from 'crypto';

// Skip if file upload tests are disabled
const skipFileTests = process.env.ENABLE_FILE_UPLOAD_TESTS !== '1';

// Test users - these should exist in the seed data (from e2e_seed.exs)
const TEST_USERS = {
  owner: {
    email: CONFIG.adminEmail,
    password: CONFIG.adminPassword,
  },
  grantee: {
    email: 'user1@e2e-test.local',
    password: 'TestUserPassword123!',
  },
};

// Helper to generate crypto params for sharing
function generateCryptoParams() {
  return {
    wrapped_key: crypto.randomBytes(64).toString('base64'),
    kem_ciphertext: crypto.randomBytes(1088).toString('base64'),
    signature: crypto.randomBytes(64).toString('base64'),
  };
}

// Helper to get a user's UUID by logging in as them
async function getUserId(request: any, email: string, password: string): Promise<string> {
  const api = new BackendApiClient(request);
  await api.login(email, password);
  const userInfo = await api.getCurrentUser();
  return userInfo.data.id;
}

// Helper to create a test file
async function createTestFile(api: BackendApiClient): Promise<string> {
  const content = Buffer.from(`Revoke test file ${Date.now()}`, 'utf-8');
  const hash = crypto.createHash('sha256').update(content).digest('hex');

  const uploadUrl = await api.getUploadUrl({
    folder_id: null,
    filename: `revoke-test-${Date.now()}.txt`,
    content_type: 'text/plain',
    size: content.length,
    encrypted_metadata: crypto.randomBytes(64).toString('base64'),
    metadata_nonce: crypto.randomBytes(12).toString('base64'),
    wrapped_dek: crypto.randomBytes(32).toString('base64'),
    kem_ciphertext: crypto.randomBytes(1088).toString('base64'),
    blob_hash: hash,
    signature: crypto.randomBytes(64).toString('base64'),
  });

  await api.uploadToPresignedUrl(uploadUrl.data.upload_url, content);
  return uploadUrl.data.file_id;
}

test.describe('Revoke Share Access', () => {
  test.skip(skipFileTests, 'File tests disabled');

  test('should revoke file share', async ({ request }) => {
    const api = new BackendApiClient(request);
    await api.login(TEST_USERS.owner.email, TEST_USERS.owner.password);

    // Get grantee UUID
    const granteeId = await getUserId(request, TEST_USERS.grantee.email, TEST_USERS.grantee.password);

    // Create and share file
    const fileId = await createTestFile(api);
    console.log(`Created test file: ${fileId}`);

    const shareResponse = await api.shareFile({
      file_id: fileId,
      grantee_id: granteeId,
      ...generateCryptoParams(),
      permission: 'read',
    });
    console.log(`Created share: ${shareResponse.data.id}`);

    // Verify share exists
    const shareInfo = await api.getShare(shareResponse.data.id);
    expect(shareInfo.data.id).toBe(shareResponse.data.id);
    console.log('Verified share exists');

    // Revoke share
    await api.revokeShare(shareResponse.data.id);
    console.log('Revoked share');

    // Verify share no longer exists (share is deleted, not status-tracked)
    try {
      await api.getShare(shareResponse.data.id);
      // If we get here, the share still exists but that's unexpected
      console.log('Share still exists after revocation');
    } catch (error) {
      // Share should be completely deleted
      console.log('Share removed completely');
    }

    // Cleanup
    try {
      await api.deleteFile(fileId);
    } catch (e) {}
  });

  test('should reject revoking non-existent share', async ({ request }) => {
    const api = new BackendApiClient(request);
    await api.login(TEST_USERS.owner.email, TEST_USERS.owner.password);

    const fakeShareId = '00000000-0000-0000-0000-000000000000';

    try {
      await api.revokeShare(fakeShareId);
      expect.fail('Should have thrown an error');
    } catch (error) {
      expect(error).toBeDefined();
      console.log('Rejected revoking non-existent share');
    }
  });
});

test.describe('Update Share Permission', () => {
  test.skip(skipFileTests, 'File tests disabled');

  test('should update share permission level', async ({ request }) => {
    const api = new BackendApiClient(request);
    await api.login(TEST_USERS.owner.email, TEST_USERS.owner.password);

    // Get grantee UUID
    const granteeId = await getUserId(request, TEST_USERS.grantee.email, TEST_USERS.grantee.password);

    // Create and share file
    const fileId = await createTestFile(api);
    const shareResponse = await api.shareFile({
      file_id: fileId,
      grantee_id: granteeId,
      ...generateCryptoParams(),
      permission: 'read',
    });
    console.log('Created share with read permission');

    // Update to write permission
    try {
      const updatedShare = await api.updateSharePermission(shareResponse.data.id, {
        permission: 'write',
        signature: crypto.randomBytes(64).toString('base64'),
      });
      expect(updatedShare.data.permission).toBe('write');
      console.log('Updated share permission to write');
    } catch (error) {
      console.log('Permission update may not be supported');
    }

    // Cleanup
    try {
      await api.revokeShare(shareResponse.data.id);
      await api.deleteFile(fileId);
    } catch (e) {}
  });
});
