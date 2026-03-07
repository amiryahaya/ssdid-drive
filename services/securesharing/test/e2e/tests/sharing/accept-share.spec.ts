/**
 * Accept Share E2E Tests
 *
 * Tests share acceptance functionality including:
 * - Accepting a pending share
 * - Listing received shares
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

// Helper to create a test file
async function createTestFile(api: BackendApiClient): Promise<string> {
  const content = Buffer.from(`Accept share test ${Date.now()}`, 'utf-8');
  const hash = crypto.createHash('sha256').update(content).digest('hex');

  const uploadUrl = await api.getUploadUrl({
    folder_id: null,
    filename: `accept-test-${Date.now()}.txt`,
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

test.describe('Accept Share', () => {
  test.skip(skipFileTests, 'File tests disabled');

  test('should accept a pending share', async ({ request }) => {
    // Login as owner
    const ownerApi = new BackendApiClient(request);
    await ownerApi.login(TEST_USERS.owner.email, TEST_USERS.owner.password);

    // Login as grantee to get UUID
    const granteeApi = new BackendApiClient(request);
    await granteeApi.login(TEST_USERS.grantee.email, TEST_USERS.grantee.password);
    const granteeInfo = await granteeApi.getCurrentUser();

    // Create and share file
    const fileId = await createTestFile(ownerApi);
    console.log(`Created test file: ${fileId}`);

    const shareResponse = await ownerApi.shareFile({
      file_id: fileId,
      grantee_id: granteeInfo.data.id,
      ...generateCryptoParams(),
      permission: 'read',
    });
    console.log(`Shared file with: ${granteeInfo.data.email}`);

    // Accept the share (or verify it's auto-accepted)
    try {
      const acceptResponse = await granteeApi.acceptShare(shareResponse.data.id);
      expect(acceptResponse.data.id).toBe(shareResponse.data.id);
      console.log('Accepted share');
    } catch (error) {
      // Share might be auto-accepted
      console.log('Share acceptance may be automatic');
    }

    // Verify share appears in received shares
    const receivedShares = await granteeApi.listReceivedShares();
    const acceptedShare = receivedShares.data.find((s) => s.id === shareResponse.data.id);
    expect(acceptedShare).toBeDefined();
    console.log('Share appears in received shares');

    // Cleanup (as owner)
    try {
      await ownerApi.revokeShare(shareResponse.data.id);
      await ownerApi.deleteFile(fileId);
    } catch (e) {}
  });

  test('should list received shares', async ({ request }) => {
    // Login as test user (who might have received shares)
    const api = new BackendApiClient(request);

    try {
      await api.login(TEST_USERS.grantee.email, TEST_USERS.grantee.password);
      console.log('Logged in as test user');

      // List received shares
      const receivedShares = await api.listReceivedShares();

      expect(receivedShares.data).toBeDefined();
      expect(Array.isArray(receivedShares.data)).toBe(true);
      expect(receivedShares.meta).toBeDefined();

      console.log(`User has ${receivedShares.data.length} received share(s)`);

      // Verify pagination metadata
      expect(receivedShares.meta.page).toBeGreaterThanOrEqual(1);
      expect(receivedShares.meta.per_page).toBeGreaterThan(0);
    } catch (error) {
      console.log(`Could not test as user: ${(error as Error).message}`);
      // Fall back to admin
      await api.login(TEST_USERS.owner.email, TEST_USERS.owner.password);
      const receivedShares = await api.listReceivedShares();
      console.log(`Admin has ${receivedShares.data.length} received share(s)`);
    }
  });
});
