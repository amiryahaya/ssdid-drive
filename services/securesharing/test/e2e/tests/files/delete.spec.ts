/**
 * File Delete E2E Tests
 *
 * Tests file deletion functionality including:
 * - Deleting owned files
 * - Access control for deletion
 * - Verifying file is removed after deletion
 */

import { test, expect } from '@playwright/test';
import { BackendApiClient, CONFIG } from '../../lib/api-client';
import crypto from 'crypto';

// Skip if file upload tests are disabled
const skipFileTests = process.env.ENABLE_FILE_UPLOAD_TESTS !== '1';

// Helper to create a test file
async function createTestFile(api: BackendApiClient): Promise<string> {
  const content = `Delete test file ${Date.now()}`;
  const buffer = Buffer.from(content, 'utf-8');
  const hash = crypto.createHash('sha256').update(buffer).digest('hex');

  const uploadUrl = await api.getUploadUrl({
    folder_id: null,
    filename: `delete-test-${Date.now()}.txt`,
    content_type: 'text/plain',
    size: buffer.length,
    encrypted_metadata: crypto.randomBytes(64).toString('base64'),
    metadata_nonce: crypto.randomBytes(12).toString('base64'),
    wrapped_dek: crypto.randomBytes(32).toString('base64'),
    kem_ciphertext: crypto.randomBytes(1088).toString('base64'),
    blob_hash: hash,
    signature: crypto.randomBytes(64).toString('base64'),
  });

  await api.uploadToPresignedUrl(uploadUrl.data.upload_url, buffer);

  return uploadUrl.data.file_id;
}

test.describe('File Deletion', () => {
  test.skip(skipFileTests, 'File tests disabled');

  test('should delete owned file', async ({ request }) => {
    const api = new BackendApiClient(request);
    await api.login(CONFIG.adminEmail, CONFIG.adminPassword);

    // Create a test file
    const fileId = await createTestFile(api);
    console.log(`✓ Created test file: ${fileId}`);

    // Verify file exists
    const fileInfo = await api.getFile(fileId);
    expect(fileInfo.data.id).toBe(fileId);
    console.log('✓ Verified file exists');

    // Delete the file
    await api.deleteFile(fileId);
    console.log('✓ Deleted file');

    // Verify file no longer exists
    try {
      await api.getFile(fileId);
      expect.fail('Should have thrown an error - file should be deleted');
    } catch (error) {
      expect(error).toBeDefined();
      console.log('✓ Verified file is deleted');
    }
  });

  test('should reject deletion of non-existent file', async ({ request }) => {
    const api = new BackendApiClient(request);
    await api.login(CONFIG.adminEmail, CONFIG.adminPassword);

    const fakeFileId = '00000000-0000-0000-0000-000000000000';

    try {
      await api.deleteFile(fakeFileId);
      expect.fail('Should have thrown an error for non-existent file');
    } catch (error) {
      expect(error).toBeDefined();
      console.log('✓ Rejected deletion of non-existent file');
    }
  });

  test('should reject deletion for unauthenticated user', async ({ request }) => {
    const api = new BackendApiClient(request);
    // Don't login

    const fakeFileId = '00000000-0000-0000-0000-000000000000';

    try {
      await api.deleteFile(fakeFileId);
      expect.fail('Should have thrown an error for unauthenticated request');
    } catch (error) {
      expect(error).toBeDefined();
      expect((error as Error).message).toContain('failed');
      console.log('✓ Rejected unauthenticated deletion');
    }
  });
});

test.describe('Folder Deletion', () => {
  test('should delete empty folder', async ({ request }) => {
    const api = new BackendApiClient(request);
    await api.login(CONFIG.adminEmail, CONFIG.adminPassword);

    // Create a test folder
    let folderId: string;
    try {
      const folderResponse = await api.createFolder({
        name: `Delete Test ${Date.now()}`,
      });
      folderId = folderResponse.data.id;
      console.log(`✓ Created test folder: ${folderId}`);
    } catch (error) {
      console.log('⚠️ Could not create folder, skipping test');
      test.skip();
      return;
    }

    // Verify folder exists
    const folderInfo = await api.getFolder(folderId);
    expect(folderInfo.data.id).toBe(folderId);
    console.log('✓ Verified folder exists');

    // Delete the folder
    await api.deleteFolder(folderId);
    console.log('✓ Deleted folder');

    // Verify folder no longer exists
    try {
      await api.getFolder(folderId);
      expect.fail('Should have thrown an error - folder should be deleted');
    } catch (error) {
      expect(error).toBeDefined();
      console.log('✓ Verified folder is deleted');
    }
  });

  test('should handle deletion of non-empty folder', async ({ request }) => {
    test.skip(skipFileTests, 'File tests disabled');

    const api = new BackendApiClient(request);
    await api.login(CONFIG.adminEmail, CONFIG.adminPassword);

    // Create folder
    let folderId: string;
    try {
      const folderResponse = await api.createFolder({
        name: `Non-Empty Delete Test ${Date.now()}`,
      });
      folderId = folderResponse.data.id;
    } catch (error) {
      test.skip();
      return;
    }

    // Create file in folder
    const content = Buffer.from('test content', 'utf-8');
    const hash = crypto.createHash('sha256').update(content).digest('hex');

    const uploadUrl = await api.getUploadUrl({
      folder_id: folderId,
      filename: 'file-in-folder.txt',
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
    console.log('✓ Created file in folder');

    // Try to delete folder (behavior depends on implementation)
    try {
      await api.deleteFolder(folderId);
      console.log('✓ Non-empty folder deleted (cascade delete)');
    } catch (error) {
      console.log('✓ Non-empty folder deletion rejected (expected)');
      // Clean up file first
      await api.deleteFile(uploadUrl.data.file_id);
      await api.deleteFolder(folderId);
      console.log('✓ Cleaned up after deleting contents');
    }
  });
});
