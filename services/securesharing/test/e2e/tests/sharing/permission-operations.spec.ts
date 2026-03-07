/**
 * Share Permission Operations E2E Tests
 *
 * Tests for:
 * - Updating share permissions (read -> write -> admin)
 * - Write share holder updating files
 * - Admin share holder deleting files
 * - Write share holder cannot delete files
 * - Folder permission inheritance
 */

import { test, expect } from '@playwright/test';
import { BackendApiClient, CONFIG } from '../../lib/api-client';
import crypto from 'crypto';

// Skip entire suite if file upload tests are disabled (S3 not available)
const skipFileTests = process.env.ENABLE_FILE_UPLOAD_TESTS !== '1';

// Note: These tests require both users to be in the same tenant

// Test users - these should exist in the seed data (from e2e_seed.exs)
// Using user1 as owner and user2 as grantee (both in same tenant)
const TEST_USERS = {
  owner: {
    email: 'user1@e2e-test.local',
    password: 'TestUserPassword123!',
  },
  grantee: {
    email: 'user2@e2e-test.local',
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
  const content = Buffer.from(`Permission test file ${Date.now()}`, 'utf-8');
  const hash = crypto.createHash('sha256').update(content).digest('hex');

  const uploadUrl = await api.getUploadUrl({
    folder_id: null,
    filename: `permission-test-${Date.now()}.txt`,
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

test.describe('Update Share Permissions', () => {
  test.skip(skipFileTests, 'File tests disabled — set ENABLE_FILE_UPLOAD_TESTS=1');

  test('should update share permission from read to write', async ({ request }) => {
    const ownerApi = new BackendApiClient(request);
    await ownerApi.login(TEST_USERS.owner.email, TEST_USERS.owner.password);

    const fileId = await createTestFile(ownerApi);

    const { userId: granteeId } = await loginAndGetUserId(
      request, TEST_USERS.grantee.email, TEST_USERS.grantee.password
    );

    const shareResponse = await ownerApi.shareFile({
      file_id: fileId,
      grantee_id: granteeId,
      ...generateCryptoParams(),
      permission: 'read',
    });

    const updatedShare = await ownerApi.updateSharePermission(shareResponse.data.id, {
      permission: 'write',
      signature: crypto.randomBytes(64).toString('base64'),
    });

    expect(updatedShare.data.permission).toBe('write');

    // Cleanup
    try {
      await ownerApi.revokeShare(shareResponse.data.id);
      await ownerApi.deleteFile(fileId);
    } catch (e) {}
  });

  test('should update share permission from write to admin', async ({ request }) => {
    const ownerApi = new BackendApiClient(request);
    await ownerApi.login(TEST_USERS.owner.email, TEST_USERS.owner.password);

    const fileId = await createTestFile(ownerApi);

    const { userId: granteeId } = await loginAndGetUserId(
      request, TEST_USERS.grantee.email, TEST_USERS.grantee.password
    );

    const shareResponse = await ownerApi.shareFile({
      file_id: fileId,
      grantee_id: granteeId,
      ...generateCryptoParams(),
      permission: 'write',
    });

    const updatedShare = await ownerApi.updateSharePermission(shareResponse.data.id, {
      permission: 'admin',
      signature: crypto.randomBytes(64).toString('base64'),
    });

    expect(updatedShare.data.permission).toBe('admin');

    // Cleanup
    try {
      await ownerApi.revokeShare(shareResponse.data.id);
      await ownerApi.deleteFile(fileId);
    } catch (e) {}
  });

  test('should downgrade share permission from admin to read', async ({ request }) => {
    const ownerApi = new BackendApiClient(request);
    await ownerApi.login(TEST_USERS.owner.email, TEST_USERS.owner.password);

    const fileId = await createTestFile(ownerApi);

    const { userId: granteeId } = await loginAndGetUserId(
      request, TEST_USERS.grantee.email, TEST_USERS.grantee.password
    );

    const shareResponse = await ownerApi.shareFile({
      file_id: fileId,
      grantee_id: granteeId,
      ...generateCryptoParams(),
      permission: 'admin',
    });

    const updatedShare = await ownerApi.updateSharePermission(shareResponse.data.id, {
      permission: 'read',
      signature: crypto.randomBytes(64).toString('base64'),
    });

    expect(updatedShare.data.permission).toBe('read');

    // Cleanup
    try {
      await ownerApi.revokeShare(shareResponse.data.id);
      await ownerApi.deleteFile(fileId);
    } catch (e) {}
  });
});

test.describe('Share Holder File Operations', () => {
  test.skip(skipFileTests, 'File tests disabled — set ENABLE_FILE_UPLOAD_TESTS=1');

  test('write share holder can update file status', async ({ request }) => {
    const ownerApi = new BackendApiClient(request);
    await ownerApi.login(TEST_USERS.owner.email, TEST_USERS.owner.password);

    const fileId = await createTestFile(ownerApi);

    const { api: granteeApi, userId: granteeId } = await loginAndGetUserId(
      request, TEST_USERS.grantee.email, TEST_USERS.grantee.password
    );

    const shareResponse = await ownerApi.shareFile({
      file_id: fileId,
      grantee_id: granteeId,
      ...generateCryptoParams(),
      permission: 'write',
    });

    // Grantee should be able to update the file
    const updateResponse = await granteeApi.updateFile(fileId, {
      status: 'uploading',
    });
    expect(updateResponse.data.id).toBe(fileId);

    // Cleanup
    try {
      await ownerApi.revokeShare(shareResponse.data.id);
      await ownerApi.deleteFile(fileId);
    } catch (e) {}
  });

  test('admin share holder can delete file', async ({ request }) => {
    const ownerApi = new BackendApiClient(request);
    await ownerApi.login(TEST_USERS.owner.email, TEST_USERS.owner.password);

    const fileId = await createTestFile(ownerApi);

    const { api: granteeApi, userId: granteeId } = await loginAndGetUserId(
      request, TEST_USERS.grantee.email, TEST_USERS.grantee.password
    );

    await ownerApi.shareFile({
      file_id: fileId,
      grantee_id: granteeId,
      ...generateCryptoParams(),
      permission: 'admin',
    });

    // Grantee (admin) should be able to delete the file
    await granteeApi.deleteFile(fileId);

    // Verify file is gone
    try {
      await ownerApi.getFile(fileId);
      expect.fail('File should have been deleted');
    } catch (error) {
      expect((error as Error).message).toContain('failed');
    }
  });

  test('write share holder CANNOT delete file', async ({ request }) => {
    const ownerApi = new BackendApiClient(request);
    await ownerApi.login(TEST_USERS.owner.email, TEST_USERS.owner.password);

    const fileId = await createTestFile(ownerApi);

    const { api: granteeApi, userId: granteeId } = await loginAndGetUserId(
      request, TEST_USERS.grantee.email, TEST_USERS.grantee.password
    );

    const shareResponse = await ownerApi.shareFile({
      file_id: fileId,
      grantee_id: granteeId,
      ...generateCryptoParams(),
      permission: 'write',
    });

    // Grantee (write only) should NOT be able to delete the file
    try {
      await granteeApi.deleteFile(fileId);
      expect.fail('Write share holder should not be able to delete file');
    } catch (error) {
      expect((error as Error).message).toContain('403');
    }

    // Cleanup
    try {
      await ownerApi.revokeShare(shareResponse.data.id);
      await ownerApi.deleteFile(fileId);
    } catch (e) {}
  });

  test('read share holder CANNOT update file', async ({ request }) => {
    const ownerApi = new BackendApiClient(request);
    await ownerApi.login(TEST_USERS.owner.email, TEST_USERS.owner.password);

    const fileId = await createTestFile(ownerApi);

    const { api: granteeApi, userId: granteeId } = await loginAndGetUserId(
      request, TEST_USERS.grantee.email, TEST_USERS.grantee.password
    );

    const shareResponse = await ownerApi.shareFile({
      file_id: fileId,
      grantee_id: granteeId,
      ...generateCryptoParams(),
      permission: 'read',
    });

    // Grantee (read only) should NOT be able to update the file
    try {
      await granteeApi.updateFile(fileId, { status: 'uploading' });
      expect.fail('Read share holder should not be able to update file');
    } catch (error) {
      expect((error as Error).message).toContain('403');
    }

    // Cleanup
    try {
      await ownerApi.revokeShare(shareResponse.data.id);
      await ownerApi.deleteFile(fileId);
    } catch (e) {}
  });

  test('read share holder CANNOT delete file', async ({ request }) => {
    const ownerApi = new BackendApiClient(request);
    await ownerApi.login(TEST_USERS.owner.email, TEST_USERS.owner.password);

    const fileId = await createTestFile(ownerApi);

    const { api: granteeApi, userId: granteeId } = await loginAndGetUserId(
      request, TEST_USERS.grantee.email, TEST_USERS.grantee.password
    );

    const shareResponse = await ownerApi.shareFile({
      file_id: fileId,
      grantee_id: granteeId,
      ...generateCryptoParams(),
      permission: 'read',
    });

    // Grantee (read only) should NOT be able to delete the file
    try {
      await granteeApi.deleteFile(fileId);
      expect.fail('Read share holder should not be able to delete file');
    } catch (error) {
      expect((error as Error).message).toContain('403');
    }

    // Cleanup
    try {
      await ownerApi.revokeShare(shareResponse.data.id);
      await ownerApi.deleteFile(fileId);
    } catch (e) {}
  });
});

test.describe('Permission Matrix Verification', () => {
  test.skip(skipFileTests, 'File tests disabled — set ENABLE_FILE_UPLOAD_TESTS=1');

  test('permission inheritance from folder share to files', async ({ request }) => {
    const ownerApi = new BackendApiClient(request);
    await ownerApi.login(TEST_USERS.owner.email, TEST_USERS.owner.password);

    // Create a folder
    const folderResponse = await ownerApi.createFolder({
      name: `Permission Test Folder ${Date.now()}`,
    });
    const folderId = folderResponse.data.id;

    // Create a file in the folder
    const content = Buffer.from('Folder permission test', 'utf-8');
    const hash = crypto.createHash('sha256').update(content).digest('hex');

    const uploadUrl = await ownerApi.getUploadUrl({
      folder_id: folderId,
      filename: 'folder-permission-test.txt',
      content_type: 'text/plain',
      size: content.length,
      encrypted_metadata: crypto.randomBytes(64).toString('base64'),
      metadata_nonce: crypto.randomBytes(12).toString('base64'),
      wrapped_dek: crypto.randomBytes(32).toString('base64'),
      kem_ciphertext: crypto.randomBytes(1088).toString('base64'),
      blob_hash: hash,
      signature: crypto.randomBytes(64).toString('base64'),
    });
    await ownerApi.uploadToPresignedUrl(uploadUrl.data.upload_url, content);
    const fileId = uploadUrl.data.file_id;

    const { api: granteeApi, userId: granteeId } = await loginAndGetUserId(
      request, TEST_USERS.grantee.email, TEST_USERS.grantee.password
    );

    // Share the folder with write permission (recursive)
    const shareResponse = await ownerApi.shareFolder({
      folder_id: folderId,
      grantee_id: granteeId,
      ...generateCryptoParams(),
      permission: 'write',
      recursive: true,
    });

    // Grantee should be able to update the file via folder permission
    const updateResponse = await granteeApi.updateFile(fileId, {
      status: 'uploading',
    });
    expect(updateResponse.data.id).toBe(fileId);

    // Cleanup
    try {
      await ownerApi.revokeShare(shareResponse.data.id);
      await ownerApi.deleteFile(fileId);
      await ownerApi.deleteFolder(folderId);
    } catch (e) {}
  });
});
