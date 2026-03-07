/**
 * Folder Channel E2E Tests
 *
 * Tests real-time folder update scenarios by exercising the HTTP API and
 * verifying side effects through folder content listing endpoints.
 *
 * The backend FolderChannel (folder:{folder_id}) broadcasts events when:
 * - Files are added/removed/updated in a folder
 * - Subfolders are added/removed
 *
 * Since Playwright does not natively support Phoenix channels (which use a
 * custom protocol over WebSocket), these tests verify the HTTP-visible side
 * effects of folder operations that would trigger channel broadcasts.
 *
 * Test scenarios:
 * - Create a folder and verify it appears in folder listing
 * - Upload a file to a folder and verify it appears in folder contents
 * - Delete a file from a folder and verify it is removed from contents
 * - Create a subfolder and verify it appears in parent listing
 */

import { test, expect } from '@playwright/test';
import { BackendApiClient, CONFIG } from '../../lib/api-client';
import crypto from 'crypto';

// Skip entire suite if file upload tests are disabled (S3 not available)
const skipFileTests = process.env.ENABLE_FILE_UPLOAD_TESTS !== '1';

// Test users from seed data
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

// Helper to generate crypto params for file uploads
function generateCryptoParams() {
  return {
    encrypted_metadata: crypto.randomBytes(64).toString('base64'),
    metadata_nonce: crypto.randomBytes(12).toString('base64'),
    wrapped_dek: crypto.randomBytes(32).toString('base64'),
    kem_ciphertext: crypto.randomBytes(1088).toString('base64'),
    signature: crypto.randomBytes(64).toString('base64'),
  };
}

// Helper to generate crypto params for sharing
function generateShareCryptoParams() {
  return {
    wrapped_key: crypto.randomBytes(64).toString('base64'),
    kem_ciphertext: crypto.randomBytes(1088).toString('base64'),
    signature: crypto.randomBytes(64).toString('base64'),
  };
}

// Helper to create a test file in a specific folder
async function createTestFileInFolder(
  api: BackendApiClient,
  folderId: string,
  filename?: string
): Promise<string> {
  const content = Buffer.from(`Folder channel test file ${Date.now()}`, 'utf-8');
  const hash = crypto.createHash('sha256').update(content).digest('hex');

  const uploadUrl = await api.getUploadUrl({
    folder_id: folderId,
    filename: filename || `folder-test-${Date.now()}.txt`,
    content_type: 'text/plain',
    size: content.length,
    ...generateCryptoParams(),
    blob_hash: hash,
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

test.describe('Folder Channel - Folder Creation and Listing', () => {
  test('should create a folder and verify it appears in folder listing', async ({ request }) => {
    const api = new BackendApiClient(request);
    await api.login(TEST_USERS.owner.email, TEST_USERS.owner.password);

    const folderName = `WS Test Folder ${Date.now()}`;
    const createResponse = await api.createFolder({ name: folderName });
    const folderId = createResponse.data.id;

    expect(folderId).toBeTruthy();

    // Verify the folder appears in the folder listing
    const listResponse = await api.listFolders();
    const createdFolder = listResponse.data.find((f) => f.id === folderId);
    expect(createdFolder).toBeTruthy();

    // Verify folder details via direct get
    const folderDetails = await api.getFolder(folderId);
    expect(folderDetails.data.id).toBe(folderId);

    // Cleanup
    try {
      await api.deleteFolder(folderId);
    } catch (e) {
      // Ignore cleanup errors
    }
  });

  test('should create a subfolder and verify it appears in parent children listing', async ({
    request,
  }) => {
    const api = new BackendApiClient(request);
    await api.login(TEST_USERS.owner.email, TEST_USERS.owner.password);

    // Create parent folder
    const parentResponse = await api.createFolder({
      name: `WS Parent Folder ${Date.now()}`,
    });
    const parentId = parentResponse.data.id;

    // Create subfolder
    const childResponse = await api.createFolder({
      name: `WS Child Folder ${Date.now()}`,
      parent_id: parentId,
    });
    const childId = childResponse.data.id;

    expect(childId).toBeTruthy();

    // Verify the subfolder appears in parent's children listing
    // This is the HTTP equivalent of what the folder channel would broadcast
    // as a "folder_added" event
    const childrenResponse = await api.listFolderChildren(parentId);
    const childFolder = childrenResponse.data.find((f) => f.id === childId);
    expect(childFolder).toBeTruthy();

    // Cleanup
    try {
      await api.deleteFolder(childId);
      await api.deleteFolder(parentId);
    } catch (e) {
      // Ignore cleanup errors
    }
  });
});

test.describe('Folder Channel - File Operations in Folder', () => {
  test.skip(skipFileTests, 'File tests disabled -- set ENABLE_FILE_UPLOAD_TESTS=1');

  test('should upload a file to a folder and verify it appears in folder contents', async ({
    request,
  }) => {
    const api = new BackendApiClient(request);
    await api.login(TEST_USERS.owner.email, TEST_USERS.owner.password);

    // Create a folder for the test
    const folderResponse = await api.createFolder({
      name: `WS File Upload Folder ${Date.now()}`,
    });
    const folderId = folderResponse.data.id;

    // Upload a file to the folder
    // This operation would trigger a "file_added" broadcast on the folder channel
    const fileId = await createTestFileInFolder(api, folderId, `ws-upload-test-${Date.now()}.txt`);

    expect(fileId).toBeTruthy();

    // Verify the file appears in the folder's file listing
    // This is the HTTP equivalent of what a channel subscriber would see
    const filesResponse = await api.listFolderFiles(folderId);
    const uploadedFile = filesResponse.data.find((f) => f.id === fileId);
    expect(uploadedFile).toBeTruthy();

    // Verify file details
    const fileDetails = await api.getFile(fileId);
    expect(fileDetails.data.id).toBe(fileId);
    expect(fileDetails.data.folder_id).toBe(folderId);

    // Cleanup
    try {
      await api.deleteFile(fileId);
      await api.deleteFolder(folderId);
    } catch (e) {
      // Ignore cleanup errors
    }
  });

  test('should delete a file from a folder and verify it is removed from contents', async ({
    request,
  }) => {
    const api = new BackendApiClient(request);
    await api.login(TEST_USERS.owner.email, TEST_USERS.owner.password);

    // Create a folder
    const folderResponse = await api.createFolder({
      name: `WS File Delete Folder ${Date.now()}`,
    });
    const folderId = folderResponse.data.id;

    // Upload a file to the folder
    const fileId = await createTestFileInFolder(api, folderId, `ws-delete-test-${Date.now()}.txt`);

    // Verify file exists in folder listing first
    const beforeDelete = await api.listFolderFiles(folderId);
    const fileBeforeDelete = beforeDelete.data.find((f) => f.id === fileId);
    expect(fileBeforeDelete).toBeTruthy();

    // Delete the file
    // This operation would trigger a "file_removed" broadcast on the folder channel
    await api.deleteFile(fileId);

    // Verify the file no longer appears in the folder's file listing
    const afterDelete = await api.listFolderFiles(folderId);
    const fileAfterDelete = afterDelete.data.find((f) => f.id === fileId);
    expect(fileAfterDelete).toBeUndefined();

    // Verify file is actually gone
    try {
      await api.getFile(fileId);
      throw new Error('File should have been deleted');
    } catch (error) {
      expect((error as Error).message).toMatch(/failed|deleted/);
    }

    // Cleanup
    try {
      await api.deleteFolder(folderId);
    } catch (e) {
      // Ignore cleanup errors
    }
  });

  test('should upload multiple files and verify all appear in folder contents', async ({
    request,
  }) => {
    const api = new BackendApiClient(request);
    await api.login(TEST_USERS.owner.email, TEST_USERS.owner.password);

    // Create a folder
    const folderResponse = await api.createFolder({
      name: `WS Multi File Folder ${Date.now()}`,
    });
    const folderId = folderResponse.data.id;

    // Upload multiple files
    // Each upload would trigger a "file_added" broadcast on the folder channel
    const fileIds: string[] = [];
    for (let i = 0; i < 3; i++) {
      const fileId = await createTestFileInFolder(
        api,
        folderId,
        `ws-multi-test-${i}-${Date.now()}.txt`
      );
      fileIds.push(fileId);
    }

    expect(fileIds).toHaveLength(3);

    // Verify all files appear in the folder's file listing
    const filesResponse = await api.listFolderFiles(folderId);
    for (const fileId of fileIds) {
      const file = filesResponse.data.find((f) => f.id === fileId);
      expect(file).toBeTruthy();
    }

    // Cleanup
    try {
      for (const fileId of fileIds) {
        await api.deleteFile(fileId);
      }
      await api.deleteFolder(folderId);
    } catch (e) {
      // Ignore cleanup errors
    }
  });
});

test.describe('Folder Channel - Subfolder Operations', () => {
  test('should create multiple subfolders and verify all appear in parent children', async ({
    request,
  }) => {
    const api = new BackendApiClient(request);
    await api.login(TEST_USERS.owner.email, TEST_USERS.owner.password);

    // Create parent folder
    const parentResponse = await api.createFolder({
      name: `WS Multi Subfolder Parent ${Date.now()}`,
    });
    const parentId = parentResponse.data.id;

    // Create multiple subfolders
    // Each creation would trigger a "folder_added" broadcast on the parent's channel
    const childIds: string[] = [];
    for (let i = 0; i < 3; i++) {
      const childResponse = await api.createFolder({
        name: `WS Child ${i} ${Date.now()}`,
        parent_id: parentId,
      });
      childIds.push(childResponse.data.id);
    }

    expect(childIds).toHaveLength(3);

    // Verify all subfolders appear in parent's children listing
    const childrenResponse = await api.listFolderChildren(parentId);
    for (const childId of childIds) {
      const child = childrenResponse.data.find((f) => f.id === childId);
      expect(child).toBeTruthy();
    }

    // Cleanup
    try {
      for (const childId of childIds) {
        await api.deleteFolder(childId);
      }
      await api.deleteFolder(parentId);
    } catch (e) {
      // Ignore cleanup errors
    }
  });

  test('should delete a subfolder and verify it is removed from parent children', async ({
    request,
  }) => {
    const api = new BackendApiClient(request);
    await api.login(TEST_USERS.owner.email, TEST_USERS.owner.password);

    // Create parent folder
    const parentResponse = await api.createFolder({
      name: `WS Delete Subfolder Parent ${Date.now()}`,
    });
    const parentId = parentResponse.data.id;

    // Create a subfolder
    const childResponse = await api.createFolder({
      name: `WS Deletable Child ${Date.now()}`,
      parent_id: parentId,
    });
    const childId = childResponse.data.id;

    // Verify it appears in parent's children first
    const beforeDelete = await api.listFolderChildren(parentId);
    const childBeforeDelete = beforeDelete.data.find((f) => f.id === childId);
    expect(childBeforeDelete).toBeTruthy();

    // Delete the subfolder
    // This operation would trigger a "folder_removed" broadcast on the parent's channel
    await api.deleteFolder(childId);

    // Verify the subfolder no longer appears in parent's children
    const afterDelete = await api.listFolderChildren(parentId);
    const childAfterDelete = afterDelete.data.find((f) => f.id === childId);
    expect(childAfterDelete).toBeUndefined();

    // Cleanup
    try {
      await api.deleteFolder(parentId);
    } catch (e) {
      // Ignore cleanup errors
    }
  });
});

test.describe('Folder Channel - Shared Folder Visibility', () => {
  test.skip(skipFileTests, 'File tests disabled -- set ENABLE_FILE_UPLOAD_TESTS=1');

  test('grantee should see files added to a shared folder', async ({ request }) => {
    // Owner creates folder and shares it with grantee
    const { api: ownerApi } = await loginAndGetUserId(
      request,
      TEST_USERS.owner.email,
      TEST_USERS.owner.password
    );
    const { api: granteeApi, userId: granteeId } = await loginAndGetUserId(
      request,
      TEST_USERS.grantee.email,
      TEST_USERS.grantee.password
    );

    // Create folder
    const folderResponse = await ownerApi.createFolder({
      name: `WS Shared Folder ${Date.now()}`,
    });
    const folderId = folderResponse.data.id;

    // Share folder with grantee (read permission)
    // In a real-time scenario, the grantee would receive this via the notification channel
    const shareResponse = await ownerApi.shareFolder({
      folder_id: folderId,
      grantee_id: granteeId,
      ...generateShareCryptoParams(),
      permission: 'read',
      recursive: true,
    });

    // Owner uploads a file to the shared folder
    // In a real-time scenario, this would trigger "file_added" on the folder channel
    const fileId = await createTestFileInFolder(
      ownerApi,
      folderId,
      `ws-shared-file-${Date.now()}.txt`
    );

    // Grantee should be able to see the file in the shared folder
    const granteeFiles = await granteeApi.listFolderFiles(folderId);
    const sharedFile = granteeFiles.data.find((f) => f.id === fileId);
    expect(sharedFile).toBeTruthy();

    // Cleanup
    try {
      await ownerApi.revokeShare(shareResponse.data.id);
      await ownerApi.deleteFile(fileId);
      await ownerApi.deleteFolder(folderId);
    } catch (e) {
      // Ignore cleanup errors
    }
  });
});
