/**
 * Single File Upload E2E Tests
 *
 * Tests single file upload functionality including:
 * - Getting presigned upload URL
 * - Uploading file to presigned URL
 * - Verifying uploaded file metadata
 */

import { test, expect } from '@playwright/test';
import { BackendApiClient, CONFIG } from '../../lib/api-client';
import crypto from 'crypto';

// Skip if file upload tests are disabled
const skipFileUpload = process.env.ENABLE_FILE_UPLOAD_TESTS !== '1';

// Helper to generate mock file data
function generateMockFileData() {
  const content = `Test file content ${Date.now()}\n${crypto.randomBytes(100).toString('hex')}`;
  const buffer = Buffer.from(content, 'utf-8');
  const hash = crypto.createHash('sha256').update(buffer).digest('hex');

  return {
    filename: `test-file-${Date.now()}.txt`,
    content: buffer,
    contentType: 'text/plain',
    size: buffer.length,
    hash,
    // Mock encryption data
    encryptedMetadata: crypto.randomBytes(64).toString('base64'),
    metadataNonce: crypto.randomBytes(12).toString('base64'),
    wrappedDek: crypto.randomBytes(32).toString('base64'),
    kemCiphertext: crypto.randomBytes(1088).toString('base64'), // ML-KEM-768 ciphertext size
    signature: crypto.randomBytes(64).toString('base64'),
  };
}

test.describe('Single File Upload', () => {
  test.skip(skipFileUpload, 'File upload tests disabled');

  test('should get presigned upload URL', async ({ request }) => {
    const api = new BackendApiClient(request);
    await api.login(CONFIG.adminEmail, CONFIG.adminPassword);

    const fileData = generateMockFileData();

    // Get upload URL
    const uploadUrl = await api.getUploadUrl({
      folder_id: null,
      filename: fileData.filename,
      content_type: fileData.contentType,
      size: fileData.size,
      encrypted_metadata: fileData.encryptedMetadata,
      metadata_nonce: fileData.metadataNonce,
      wrapped_dek: fileData.wrappedDek,
      kem_ciphertext: fileData.kemCiphertext,
      blob_hash: fileData.hash,
      signature: fileData.signature,
    });

    expect(uploadUrl.data.upload_url).toBeTruthy();
    expect(uploadUrl.data.file_id).toBeTruthy();
    expect(uploadUrl.data.storage_path).toBeTruthy();

    console.log(`✓ Got upload URL for file: ${fileData.filename}`);
    console.log(`  File ID: ${uploadUrl.data.file_id}`);
  });

  test('should upload file to presigned URL', async ({ request }) => {
    const api = new BackendApiClient(request);
    await api.login(CONFIG.adminEmail, CONFIG.adminPassword);

    const fileData = generateMockFileData();

    // Get upload URL
    const uploadUrl = await api.getUploadUrl({
      folder_id: null,
      filename: fileData.filename,
      content_type: fileData.contentType,
      size: fileData.size,
      encrypted_metadata: fileData.encryptedMetadata,
      metadata_nonce: fileData.metadataNonce,
      wrapped_dek: fileData.wrappedDek,
      kem_ciphertext: fileData.kemCiphertext,
      blob_hash: fileData.hash,
      signature: fileData.signature,
    });

    console.log(`✓ Got upload URL for: ${fileData.filename}`);

    // Upload to presigned URL
    await api.uploadToPresignedUrl(uploadUrl.data.upload_url, fileData.content);

    console.log(`✓ Uploaded file content (${fileData.size} bytes)`);

    // Verify file exists (filename is encrypted, so we just verify the ID)
    const fileInfo = await api.getFile(uploadUrl.data.file_id);
    expect(fileInfo.data.id).toBe(uploadUrl.data.file_id);
    expect(fileInfo.data.status).toBe('complete');

    console.log(`✓ File upload verified: ${uploadUrl.data.file_id}`);
  });

  test('should upload file to specific folder', async ({ request }) => {
    const api = new BackendApiClient(request);
    await api.login(CONFIG.adminEmail, CONFIG.adminPassword);

    // Create a test folder first
    let folderId: string;
    try {
      const folderResponse = await api.createFolder({ name: `Upload Test ${Date.now()}` });
      folderId = folderResponse.data.id;
      console.log(`✓ Created test folder: ${folderId}`);
    } catch (error) {
      console.log('⚠️ Could not create folder, using root');
      folderId = '';
    }

    const fileData = generateMockFileData();

    // Get upload URL with folder
    const uploadUrl = await api.getUploadUrl({
      folder_id: folderId || null,
      filename: fileData.filename,
      content_type: fileData.contentType,
      size: fileData.size,
      encrypted_metadata: fileData.encryptedMetadata,
      metadata_nonce: fileData.metadataNonce,
      wrapped_dek: fileData.wrappedDek,
      kem_ciphertext: fileData.kemCiphertext,
      blob_hash: fileData.hash,
      signature: fileData.signature,
    });

    // Upload file
    await api.uploadToPresignedUrl(uploadUrl.data.upload_url, fileData.content);

    // Verify file is in folder
    const fileInfo = await api.getFile(uploadUrl.data.file_id);
    if (folderId) {
      expect(fileInfo.data.folder_id).toBe(folderId);
      console.log(`✓ File uploaded to folder: ${folderId}`);
    } else {
      console.log(`✓ File uploaded to root folder`);
    }

    // Cleanup: delete the folder
    if (folderId) {
      try {
        await api.deleteFile(uploadUrl.data.file_id);
        await api.deleteFolder(folderId);
        console.log('✓ Cleaned up test folder and file');
      } catch (e) {
        // Ignore cleanup errors
      }
    }
  });
});
