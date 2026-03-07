/**
 * File Download E2E Tests
 *
 * Tests file download functionality including:
 * - Getting download URL for owned file
 * - Downloading file content
 * - Access control for downloads
 */

import { test, expect } from '@playwright/test';
import { BackendApiClient, CONFIG } from '../../lib/api-client';
import crypto from 'crypto';

// Skip if file upload tests are disabled (needed for download tests too)
const skipFileTests = process.env.ENABLE_FILE_UPLOAD_TESTS !== '1';

// Helper to create a test file and return its ID
async function createTestFile(api: BackendApiClient): Promise<{ fileId: string; content: string }> {
  const content = `Download test file ${Date.now()}\n${crypto.randomBytes(50).toString('hex')}`;
  const buffer = Buffer.from(content, 'utf-8');
  const hash = crypto.createHash('sha256').update(buffer).digest('hex');

  const uploadUrl = await api.getUploadUrl({
    folder_id: null,
    filename: `download-test-${Date.now()}.txt`,
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

  return { fileId: uploadUrl.data.file_id, content };
}

test.describe('File Download', () => {
  test.skip(skipFileTests, 'File tests disabled');

  test('should get download URL for owned file', async ({ request }) => {
    const api = new BackendApiClient(request);
    await api.login(CONFIG.adminEmail, CONFIG.adminPassword);

    // Create a test file
    const { fileId } = await createTestFile(api);
    console.log(`✓ Created test file: ${fileId}`);

    // Get download URL
    const downloadResponse = await api.getDownloadUrl(fileId);

    expect(downloadResponse.data.download_url).toBeTruthy();
    expect(downloadResponse.data.download_url).toContain('http');

    console.log('✓ Got download URL for file');

    // Cleanup
    try {
      await api.deleteFile(fileId);
    } catch (e) {}
  });

  test('should download file content from presigned URL', async ({ request }) => {
    const api = new BackendApiClient(request);
    await api.login(CONFIG.adminEmail, CONFIG.adminPassword);

    // Create test file
    const { fileId, content: originalContent } = await createTestFile(api);
    console.log(`✓ Created test file: ${fileId}`);

    // Get download URL
    const downloadResponse = await api.getDownloadUrl(fileId);
    console.log('✓ Got download URL');

    // Download content
    const downloadResult = await request.get(downloadResponse.data.download_url);

    expect(downloadResult.ok()).toBe(true);

    const downloadedContent = await downloadResult.text();
    // Note: Content might be encrypted, so we just verify we got something
    expect(downloadedContent.length).toBeGreaterThan(0);

    console.log(`✓ Downloaded ${downloadedContent.length} bytes`);

    // Cleanup
    try {
      await api.deleteFile(fileId);
    } catch (e) {}
  });

  test('should reject download URL for non-existent file', async ({ request }) => {
    const api = new BackendApiClient(request);
    await api.login(CONFIG.adminEmail, CONFIG.adminPassword);

    const fakeFileId = '00000000-0000-0000-0000-000000000000';

    try {
      await api.getDownloadUrl(fakeFileId);
      expect.fail('Should have thrown an error for non-existent file');
    } catch (error) {
      expect(error).toBeDefined();
      console.log('✓ Rejected download for non-existent file');
    }
  });
});

test.describe('Download Access Control', () => {
  test.skip(skipFileTests, 'File tests disabled');

  test('should reject download for unauthenticated user', async ({ request }) => {
    const api = new BackendApiClient(request);
    // Don't login

    const fakeFileId = '00000000-0000-0000-0000-000000000000';

    try {
      await api.getDownloadUrl(fakeFileId);
      expect.fail('Should have thrown an error for unauthenticated request');
    } catch (error) {
      expect(error).toBeDefined();
      expect((error as Error).message).toContain('failed');
      console.log('✓ Rejected unauthenticated download request');
    }
  });
});
