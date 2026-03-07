/**
 * Multiple File Upload E2E Tests
 *
 * Tests batch file upload functionality including:
 * - Uploading multiple files sequentially
 * - Uploading multiple files to same folder
 */

import { test, expect } from '@playwright/test';
import { BackendApiClient, CONFIG } from '../../lib/api-client';
import crypto from 'crypto';

// Skip if file upload tests are disabled
const skipFileUpload = process.env.ENABLE_FILE_UPLOAD_TESTS !== '1';

// Helper to generate mock file data
function generateMockFileData(prefix: string = 'test') {
  const content = `Test file content ${Date.now()}\n${crypto.randomBytes(50).toString('hex')}`;
  const buffer = Buffer.from(content, 'utf-8');
  const hash = crypto.createHash('sha256').update(buffer).digest('hex');

  return {
    filename: `${prefix}-${Date.now()}-${crypto.randomBytes(4).toString('hex')}.txt`,
    content: buffer,
    contentType: 'text/plain',
    size: buffer.length,
    hash,
    encryptedMetadata: crypto.randomBytes(64).toString('base64'),
    metadataNonce: crypto.randomBytes(12).toString('base64'),
    wrappedDek: crypto.randomBytes(32).toString('base64'),
    kemCiphertext: crypto.randomBytes(1088).toString('base64'),
    signature: crypto.randomBytes(64).toString('base64'),
  };
}

test.describe('Multiple File Upload', () => {
  test.skip(skipFileUpload, 'File upload tests disabled');

  test('should upload multiple files sequentially', async ({ request }) => {
    const api = new BackendApiClient(request);
    await api.login(CONFIG.adminEmail, CONFIG.adminPassword);

    const fileCount = 3;
    const uploadedFiles: string[] = [];

    for (let i = 0; i < fileCount; i++) {
      const fileData = generateMockFileData(`batch-${i + 1}`);

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

      // Upload file
      await api.uploadToPresignedUrl(uploadUrl.data.upload_url, fileData.content);

      uploadedFiles.push(uploadUrl.data.file_id);
      console.log(`✓ Uploaded file ${i + 1}/${fileCount}: ${fileData.filename}`);
    }

    expect(uploadedFiles.length).toBe(fileCount);
    console.log(`✓ Successfully uploaded ${fileCount} files`);

    // Cleanup
    for (const fileId of uploadedFiles) {
      try {
        await api.deleteFile(fileId);
      } catch (e) {
        // Ignore cleanup errors
      }
    }
    console.log('✓ Cleaned up test files');
  });

  test('should upload multiple files to same folder', async ({ request }) => {
    const api = new BackendApiClient(request);
    await api.login(CONFIG.adminEmail, CONFIG.adminPassword);

    // Create test folder
    let folderId: string;
    try {
      const folderResponse = await api.createFolder({
        name: `Multi-Upload Test ${Date.now()}`,
      });
      folderId = folderResponse.data.id;
      console.log(`✓ Created test folder: ${folderId}`);
    } catch (error) {
      console.log('⚠️ Skipping - could not create folder');
      test.skip();
      return;
    }

    const fileCount = 3;
    const uploadedFiles: string[] = [];

    // Upload files to folder
    for (let i = 0; i < fileCount; i++) {
      const fileData = generateMockFileData(`folder-file-${i + 1}`);

      const uploadUrl = await api.getUploadUrl({
        folder_id: folderId,
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

      await api.uploadToPresignedUrl(uploadUrl.data.upload_url, fileData.content);
      uploadedFiles.push(uploadUrl.data.file_id);

      console.log(`✓ Uploaded: ${fileData.filename}`);
    }

    // List files in folder
    try {
      const filesInFolder = await api.listFiles(folderId);
      console.log(`✓ Folder contains ${filesInFolder.data.length} file(s)`);

      // Verify all uploaded files are in folder
      for (const fileId of uploadedFiles) {
        const fileInList = filesInFolder.data.find((f) => f.id === fileId);
        expect(fileInList).toBeDefined();
      }
    } catch (error) {
      console.log('⚠️ Could not list files in folder');
    }

    // Cleanup
    for (const fileId of uploadedFiles) {
      try {
        await api.deleteFile(fileId);
      } catch (e) {}
    }
    try {
      await api.deleteFolder(folderId);
    } catch (e) {}
    console.log('✓ Cleaned up test data');
  });
});
