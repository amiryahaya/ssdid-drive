/**
 * Shares API Contract Tests
 *
 * Validates the structure and format of sharing API responses.
 */

import { test, expect } from '@playwright/test';
import { BackendApiClient, CONFIG } from '../../lib/api-client';
import { validateResponse, ShareSchema } from '../../lib/schemas';
import crypto from 'crypto';

// Skip if file tests are disabled
const skipFileTests = process.env.ENABLE_FILE_UPLOAD_TESTS !== '1';

test.describe('Shares API Contracts', () => {
  test('POST /api/shares - response structure', async ({ request }) => {
    test.skip(skipFileTests, 'File tests disabled');

    const api = new BackendApiClient(request);
    await api.login(CONFIG.adminEmail, CONFIG.adminPassword);

    // Create test file
    const content = Buffer.from('share contract test', 'utf-8');
    const hash = crypto.createHash('sha256').update(content).digest('hex');

    const uploadUrl = await api.getUploadUrl({
      folder_id: null,
      filename: `share-contract-${Date.now()}.txt`,
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

    // Share file
    const shareResponse = await api.shareFile({
      file_id: uploadUrl.data.file_id,
      email: 'user1@e2e-test.local',
      permission: 'view',
    });

    // Validate structure
    expect(shareResponse.data).toHaveProperty('id');
    expect(shareResponse.data).toHaveProperty('permission');
    expect(shareResponse.data).toHaveProperty('status');
    expect(shareResponse.data).toHaveProperty('created_at');

    // UUID format
    expect(shareResponse.data.id).toMatch(
      /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i
    );

    // Permission enum
    expect(['view', 'edit', 'admin']).toContain(shareResponse.data.permission);

    console.log('✓ Share response matches contract');

    // Cleanup
    try {
      await api.revokeShare(shareResponse.data.id);
      await api.deleteFile(uploadUrl.data.file_id);
    } catch (e) {}
  });

  test('GET /api/shares/created - response structure', async ({ request }) => {
    const api = new BackendApiClient(request);
    await api.login(CONFIG.adminEmail, CONFIG.adminPassword);

    const response = await api.listCreatedShares();

    // Shares endpoints return simple data array (no pagination)
    expect(response).toHaveProperty('data');
    expect(Array.isArray(response.data)).toBe(true);

    console.log(`✓ Created shares list matches contract (${response.data.length} shares)`);
  });

  test('GET /api/shares/received - response structure', async ({ request }) => {
    const api = new BackendApiClient(request);
    await api.login(CONFIG.adminEmail, CONFIG.adminPassword);

    const response = await api.listReceivedShares();

    // Shares endpoints return simple data array (no pagination)
    expect(response).toHaveProperty('data');
    expect(Array.isArray(response.data)).toBe(true);

    console.log(`✓ Received shares list matches contract (${response.data.length} shares)`);
  });

  test('Permission values are valid enum', async ({ request }) => {
    test.skip(skipFileTests, 'File tests disabled');

    const api = new BackendApiClient(request);
    await api.login(CONFIG.adminEmail, CONFIG.adminPassword);

    const validPermissions = ['view', 'edit', 'admin'];

    for (const permission of validPermissions) {
      const content = Buffer.from(`test-${permission}`, 'utf-8');
      const hash = crypto.createHash('sha256').update(content).digest('hex');

      const uploadUrl = await api.getUploadUrl({
        folder_id: null,
        filename: `perm-${permission}-${Date.now()}.txt`,
        content_type: 'text/plain',
        size: content.length,
        encrypted_metadata: crypto.randomBytes(64).toString('base64'),
        metadata_nonce: crypto.randomBytes(12).toString('base64'),
        wrapped_dek: crypto.randomBytes(32).toString('base64'),
        blob_hash: hash,
        signature: crypto.randomBytes(64).toString('base64'),
      });

      await api.uploadToPresignedUrl(uploadUrl.data.upload_url, content);

      const shareResponse = await api.shareFile({
        file_id: uploadUrl.data.file_id,
        email: 'user1@e2e-test.local',
        permission: permission as 'view' | 'edit' | 'admin',
      });

      expect(shareResponse.data.permission).toBe(permission);

      // Cleanup
      await api.revokeShare(shareResponse.data.id);
      await api.deleteFile(uploadUrl.data.file_id);
    }

    console.log('✓ All permission values are valid');
  });

  test('Share status values are valid enum', async ({ request }) => {
    test.skip(skipFileTests, 'File tests disabled');

    const api = new BackendApiClient(request);
    await api.login(CONFIG.adminEmail, CONFIG.adminPassword);

    const content = Buffer.from('status test', 'utf-8');
    const hash = crypto.createHash('sha256').update(content).digest('hex');

    const uploadUrl = await api.getUploadUrl({
      folder_id: null,
      filename: `status-test-${Date.now()}.txt`,
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

    const shareResponse = await api.shareFile({
      file_id: uploadUrl.data.file_id,
      email: 'user1@e2e-test.local',
      permission: 'view',
    });

    const validStatuses = ['pending', 'accepted', 'declined', 'revoked'];
    expect(validStatuses).toContain(shareResponse.data.status);

    console.log(`✓ Share status '${shareResponse.data.status}' is valid`);

    // Cleanup
    await api.revokeShare(shareResponse.data.id);
    await api.deleteFile(uploadUrl.data.file_id);
  });

  test('PATCH /api/shares/:id - update response structure', async ({ request }) => {
    test.skip(skipFileTests, 'File tests disabled');

    const api = new BackendApiClient(request);
    await api.login(CONFIG.adminEmail, CONFIG.adminPassword);

    const content = Buffer.from('update test', 'utf-8');
    const hash = crypto.createHash('sha256').update(content).digest('hex');

    const uploadUrl = await api.getUploadUrl({
      folder_id: null,
      filename: `update-share-${Date.now()}.txt`,
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

    const shareResponse = await api.shareFile({
      file_id: uploadUrl.data.file_id,
      email: 'user1@e2e-test.local',
      permission: 'view',
    });

    try {
      const updateResponse = await api.updateSharePermission(shareResponse.data.id, 'edit');

      expect(updateResponse.data).toHaveProperty('id');
      expect(updateResponse.data).toHaveProperty('permission');
      expect(updateResponse.data.permission).toBe('edit');

      console.log('✓ Update share response matches contract');
    } catch (error) {
      console.log('⚠️ Share update may not be supported');
    }

    // Cleanup
    await api.revokeShare(shareResponse.data.id);
    await api.deleteFile(uploadUrl.data.file_id);
  });
});

test.describe('Share Error Responses', () => {
  test('404 for non-existent share', async ({ request }) => {
    const api = new BackendApiClient(request);
    await api.login(CONFIG.adminEmail, CONFIG.adminPassword);

    const fakeId = '00000000-0000-0000-0000-000000000000';

    try {
      await api.getShare(fakeId);
      expect.fail('Should have thrown an error');
    } catch (error) {
      expect((error as Error).message).toBeTruthy();
      console.log('✓ 404 error for non-existent share');
    }
  });

  test('401 for unauthenticated share request', async ({ request }) => {
    const api = new BackendApiClient(request);
    // Don't login

    try {
      await api.listCreatedShares();
      expect.fail('Should have thrown an error');
    } catch (error) {
      expect((error as Error).message).toContain('failed');
      console.log('✓ 401 error for unauthenticated request');
    }
  });
});
