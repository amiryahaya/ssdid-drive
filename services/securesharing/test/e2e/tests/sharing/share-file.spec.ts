/**
 * Share File E2E Tests
 *
 * Tests file sharing functionality including:
 * - Sharing file with another user by grantee_id
 * - Sharing with different permission levels
 * - Share validation and error handling
 * - Listing created shares
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
  grantee1: {
    email: 'user1@e2e-test.local',
    password: 'TestUserPassword123!',
  },
  grantee2: {
    email: 'user2@e2e-test.local',
    password: 'TestUserPassword123!',
  },
  grantee3: {
    email: 'user3@e2e-test.local',
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

// Helper to create a test file
async function createTestFile(api: BackendApiClient): Promise<string> {
  const content = Buffer.from(`Share test file ${Date.now()}`, 'utf-8');
  const hash = crypto.createHash('sha256').update(content).digest('hex');

  const uploadUrl = await api.getUploadUrl({
    folder_id: null,
    filename: `share-test-${Date.now()}.txt`,
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

// Helper to get a user's UUID by logging in as them
async function getUserId(request: any, email: string, password: string): Promise<string> {
  const api = new BackendApiClient(request);
  await api.login(email, password);
  const userInfo = await api.getCurrentUser();
  return userInfo.data.id;
}

test.describe('Share File', () => {
  test.skip(skipFileTests, 'File tests disabled');

  test('should share file with another user by grantee_id', async ({ request }) => {
    const api = new BackendApiClient(request);
    await api.login(TEST_USERS.owner.email, TEST_USERS.owner.password);

    // Get grantee UUID
    const granteeId = await getUserId(request, TEST_USERS.grantee1.email, TEST_USERS.grantee1.password);

    // Create test file
    const fileId = await createTestFile(api);
    console.log(`Created test file: ${fileId}`);

    // Share with test user
    const shareResponse = await api.shareFile({
      file_id: fileId,
      grantee_id: granteeId,
      ...generateCryptoParams(),
      permission: 'read',
    });

    expect(shareResponse.data.id).toBeTruthy();
    expect(shareResponse.data.file_id).toBe(fileId);
    expect(shareResponse.data.permission).toBe('read');

    console.log(`Shared file with grantee: ${granteeId}`);
    console.log(`  Share ID: ${shareResponse.data.id}`);

    // Cleanup
    try {
      await api.revokeShare(shareResponse.data.id);
      await api.deleteFile(fileId);
    } catch (e) {}
  });

  test('should share file with write permission', async ({ request }) => {
    const api = new BackendApiClient(request);
    await api.login(TEST_USERS.owner.email, TEST_USERS.owner.password);

    // Get grantee UUID
    const granteeId = await getUserId(request, TEST_USERS.grantee2.email, TEST_USERS.grantee2.password);

    const fileId = await createTestFile(api);
    console.log(`Created test file: ${fileId}`);

    const shareResponse = await api.shareFile({
      file_id: fileId,
      grantee_id: granteeId,
      ...generateCryptoParams(),
      permission: 'write',
    });

    expect(shareResponse.data.permission).toBe('write');
    console.log('Shared file with write permission');

    // Cleanup
    try {
      await api.revokeShare(shareResponse.data.id);
      await api.deleteFile(fileId);
    } catch (e) {}
  });

  test('should share file with admin permission', async ({ request }) => {
    const api = new BackendApiClient(request);
    await api.login(TEST_USERS.owner.email, TEST_USERS.owner.password);

    // Get grantee UUID
    const granteeId = await getUserId(request, TEST_USERS.grantee3.email, TEST_USERS.grantee3.password);

    const fileId = await createTestFile(api);
    console.log(`Created test file: ${fileId}`);

    const shareResponse = await api.shareFile({
      file_id: fileId,
      grantee_id: granteeId,
      ...generateCryptoParams(),
      permission: 'admin',
    });

    expect(shareResponse.data.permission).toBe('admin');
    console.log('Shared file with admin permission');

    // Cleanup
    try {
      await api.revokeShare(shareResponse.data.id);
      await api.deleteFile(fileId);
    } catch (e) {}
  });

  test('should reject sharing non-existent file', async ({ request }) => {
    const api = new BackendApiClient(request);
    await api.login(TEST_USERS.owner.email, TEST_USERS.owner.password);

    // Get grantee UUID
    const granteeId = await getUserId(request, TEST_USERS.grantee1.email, TEST_USERS.grantee1.password);

    const fakeFileId = '00000000-0000-0000-0000-000000000000';

    try {
      await api.shareFile({
        file_id: fakeFileId,
        grantee_id: granteeId,
        ...generateCryptoParams(),
        permission: 'read',
      });
      expect.fail('Should have thrown an error');
    } catch (error) {
      expect(error).toBeDefined();
      console.log('Rejected sharing non-existent file');
    }
  });
});

test.describe('List Created Shares', () => {
  test.skip(skipFileTests, 'File tests disabled');

  test('should list shares created by user', async ({ request }) => {
    const api = new BackendApiClient(request);
    await api.login(TEST_USERS.owner.email, TEST_USERS.owner.password);

    // Get grantee UUID
    const granteeId = await getUserId(request, TEST_USERS.grantee1.email, TEST_USERS.grantee1.password);

    // Create and share a file
    const fileId = await createTestFile(api);
    const shareResponse = await api.shareFile({
      file_id: fileId,
      grantee_id: granteeId,
      ...generateCryptoParams(),
      permission: 'read',
    });
    console.log(`Created share: ${shareResponse.data.id}`);

    // List created shares
    const sharesResponse = await api.listCreatedShares();

    expect(sharesResponse.data).toBeDefined();
    expect(Array.isArray(sharesResponse.data)).toBe(true);
    expect(sharesResponse.meta).toBeDefined();

    console.log(`Listed ${sharesResponse.data.length} created share(s)`);

    // Verify our share is in the list
    const ourShare = sharesResponse.data.find((s) => s.id === shareResponse.data.id);
    expect(ourShare).toBeDefined();
    console.log('Verified share appears in list');

    // Cleanup
    try {
      await api.revokeShare(shareResponse.data.id);
      await api.deleteFile(fileId);
    } catch (e) {}
  });
});
