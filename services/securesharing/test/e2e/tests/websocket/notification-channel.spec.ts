/**
 * Notification Channel E2E Tests
 *
 * Tests real-time notification scenarios by exercising the HTTP API and
 * verifying notification persistence through the REST notifications endpoint.
 *
 * The backend NotificationChannel (notification:{user_id}) broadcasts events when:
 * - A file or folder is shared with a user (share_received)
 * - A share is revoked (share_revoked)
 * - A recovery request is created (recovery_request)
 * - A recovery is approved (recovery_approval)
 * - A tenant invitation is sent (tenant_invitation)
 *
 * The NotificationChannel persists notifications to the database before
 * broadcasting, so we can verify them through the REST API at:
 *   GET /api/notifications
 *   GET /api/notifications/unread_count
 *   POST /api/notifications/:id/read
 *   POST /api/notifications/read_all
 *   DELETE /api/notifications/:id
 *
 * Test scenarios:
 * - Share a file and verify grantee receives a "share_received" notification
 * - Revoke a share and verify grantee receives a "share_revoked" notification
 * - Verify notification read/unread tracking
 * - Verify mark all notifications as read
 * - Verify notification dismissal (deletion)
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

// Helper to generate crypto params for sharing
function generateShareCryptoParams() {
  return {
    wrapped_key: crypto.randomBytes(64).toString('base64'),
    kem_ciphertext: crypto.randomBytes(1088).toString('base64'),
    signature: crypto.randomBytes(64).toString('base64'),
  };
}

// Helper to generate crypto params for file uploads
function generateFileCryptoParams() {
  return {
    encrypted_metadata: crypto.randomBytes(64).toString('base64'),
    metadata_nonce: crypto.randomBytes(12).toString('base64'),
    wrapped_dek: crypto.randomBytes(32).toString('base64'),
    kem_ciphertext: crypto.randomBytes(1088).toString('base64'),
    signature: crypto.randomBytes(64).toString('base64'),
  };
}

// Helper to create a test file
async function createTestFile(api: BackendApiClient): Promise<string> {
  const content = Buffer.from(`Notification test file ${Date.now()}`, 'utf-8');
  const hash = crypto.createHash('sha256').update(content).digest('hex');

  const uploadUrl = await api.getUploadUrl({
    folder_id: null,
    filename: `notif-test-${Date.now()}.txt`,
    content_type: 'text/plain',
    size: content.length,
    ...generateFileCryptoParams(),
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

test.describe('Notification Channel - Share Notifications', () => {
  test.skip(skipFileTests, 'File tests disabled -- set ENABLE_FILE_UPLOAD_TESTS=1');

  test('grantee should receive a notification when a file is shared with them', async ({
    request,
  }) => {
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

    // Mark all existing notifications as read so we have a clean baseline
    await granteeApi.markAllNotificationsRead();

    // Record initial unread count
    const initialCount = await granteeApi.getUnreadNotificationCount();
    const initialUnread = initialCount.data.unread_count;

    // Owner creates a file and shares it with grantee
    const fileId = await createTestFile(ownerApi);
    const shareResponse = await ownerApi.shareFile({
      file_id: fileId,
      grantee_id: granteeId,
      ...generateShareCryptoParams(),
      permission: 'read',
    });

    // The backend persists a "share_received" notification for the grantee
    // via NotificationChannel.broadcast_share_received/2.
    // Verify the notification appears via the REST API.
    const notifications = await granteeApi.getNotifications({ limit: 10 });
    const shareNotification = notifications.data.find(
      (n) => n.type === 'share_received' && n.data && (n.data as any).id === shareResponse.data.id
    );
    expect(shareNotification).toBeTruthy();
    expect(shareNotification!.title).toBe('New Share');
    expect(shareNotification!.body).toContain('shared a file with you');
    expect(shareNotification!.read_at).toBeNull();

    // Verify unread count increased
    const afterShareCount = await granteeApi.getUnreadNotificationCount();
    expect(afterShareCount.data.unread_count).toBeGreaterThan(initialUnread);

    // Cleanup
    try {
      await ownerApi.revokeShare(shareResponse.data.id);
      await ownerApi.deleteFile(fileId);
    } catch (e) {
      // Ignore cleanup errors
    }
  });

  test('grantee should receive a notification when a share is revoked', async ({ request }) => {
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

    // Mark all existing notifications as read for clean baseline
    await granteeApi.markAllNotificationsRead();

    // Owner creates a file and shares it
    const fileId = await createTestFile(ownerApi);
    const shareResponse = await ownerApi.shareFile({
      file_id: fileId,
      grantee_id: granteeId,
      ...generateShareCryptoParams(),
      permission: 'read',
    });

    // Mark the share notification as read so we can distinguish the revoke notification
    const afterShare = await granteeApi.getNotifications({ limit: 5 });
    for (const n of afterShare.data) {
      if (n.type === 'share_received' && !n.read_at) {
        await granteeApi.markNotificationRead(n.id);
      }
    }

    // Owner revokes the share
    // This triggers NotificationChannel.broadcast_share_revoked/2
    await ownerApi.revokeShare(shareResponse.data.id);

    // Verify the "share_revoked" notification appears for the grantee
    const notifications = await granteeApi.getNotifications({ limit: 10 });
    const revokeNotification = notifications.data.find(
      (n) =>
        n.type === 'share_revoked' && n.data && (n.data as any).id === shareResponse.data.id
    );
    expect(revokeNotification).toBeTruthy();
    expect(revokeNotification!.title).toBe('Share Revoked');
    expect(revokeNotification!.body).toContain('revoked');

    // Cleanup
    try {
      await ownerApi.deleteFile(fileId);
    } catch (e) {
      // Ignore cleanup errors
    }
  });

  test('grantee should receive a notification when a folder is shared', async ({ request }) => {
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

    // Mark all existing notifications as read
    await granteeApi.markAllNotificationsRead();

    // Owner creates a folder and shares it
    const folderResponse = await ownerApi.createFolder({
      name: `Notif Shared Folder ${Date.now()}`,
    });
    const folderId = folderResponse.data.id;

    const shareResponse = await ownerApi.shareFolder({
      folder_id: folderId,
      grantee_id: granteeId,
      ...generateShareCryptoParams(),
      permission: 'read',
      recursive: true,
    });

    // Verify the "share_received" notification appears with folder resource type
    const notifications = await granteeApi.getNotifications({ limit: 10 });
    const shareNotification = notifications.data.find(
      (n) => n.type === 'share_received' && n.data && (n.data as any).id === shareResponse.data.id
    );
    expect(shareNotification).toBeTruthy();
    expect(shareNotification!.body).toContain('shared a folder with you');

    // Cleanup
    try {
      await ownerApi.revokeShare(shareResponse.data.id);
      await ownerApi.deleteFolder(folderId);
    } catch (e) {
      // Ignore cleanup errors
    }
  });
});

test.describe('Notification Channel - Read/Unread Tracking', () => {
  test.skip(skipFileTests, 'File tests disabled -- set ENABLE_FILE_UPLOAD_TESTS=1');

  test('should mark a single notification as read', async ({ request }) => {
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

    // Mark all existing notifications as read for a clean baseline
    await granteeApi.markAllNotificationsRead();

    // Create a share to generate a notification
    const fileId = await createTestFile(ownerApi);
    const shareResponse = await ownerApi.shareFile({
      file_id: fileId,
      grantee_id: granteeId,
      ...generateShareCryptoParams(),
      permission: 'read',
    });

    // Find the unread notification
    const notifications = await granteeApi.getNotifications({ unread_only: true });
    expect(notifications.data.length).toBeGreaterThanOrEqual(1);

    const targetNotification = notifications.data.find((n) => n.type === 'share_received');
    expect(targetNotification).toBeTruthy();
    expect(targetNotification!.read_at).toBeNull();

    // Mark it as read
    const markResult = await granteeApi.markNotificationRead(targetNotification!.id);
    expect(markResult.data.notification_id).toBe(targetNotification!.id);

    // Verify it is now read
    const afterMark = await granteeApi.getNotifications({ limit: 10 });
    const markedNotification = afterMark.data.find((n) => n.id === targetNotification!.id);
    expect(markedNotification).toBeTruthy();
    expect(markedNotification!.read_at).not.toBeNull();

    // Verify it does not appear in unread-only listing
    const unreadOnly = await granteeApi.getNotifications({ unread_only: true });
    const stillUnread = unreadOnly.data.find((n) => n.id === targetNotification!.id);
    expect(stillUnread).toBeUndefined();

    // Cleanup
    try {
      await ownerApi.revokeShare(shareResponse.data.id);
      await ownerApi.deleteFile(fileId);
    } catch (e) {
      // Ignore cleanup errors
    }
  });

  test('should mark all notifications as read', async ({ request }) => {
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

    // Mark all existing notifications as read first
    await granteeApi.markAllNotificationsRead();

    // Create multiple shares to generate multiple notifications
    const fileIds: string[] = [];
    const shareIds: string[] = [];

    for (let i = 0; i < 2; i++) {
      const fileId = await createTestFile(ownerApi);
      fileIds.push(fileId);

      const shareResponse = await ownerApi.shareFile({
        file_id: fileId,
        grantee_id: granteeId,
        ...generateShareCryptoParams(),
        permission: 'read',
      });
      shareIds.push(shareResponse.data.id);
    }

    // Verify there are unread notifications
    const beforeMarkAll = await granteeApi.getUnreadNotificationCount();
    expect(beforeMarkAll.data.unread_count).toBeGreaterThanOrEqual(2);

    // Mark all as read
    const markAllResult = await granteeApi.markAllNotificationsRead();
    expect(markAllResult.data.unread_count).toBe(0);
    expect(markAllResult.data.marked_count).toBeGreaterThanOrEqual(2);

    // Verify unread count is now 0
    const afterMarkAll = await granteeApi.getUnreadNotificationCount();
    expect(afterMarkAll.data.unread_count).toBe(0);

    // Cleanup
    try {
      for (const shareId of shareIds) {
        await ownerApi.revokeShare(shareId);
      }
      for (const fileId of fileIds) {
        await ownerApi.deleteFile(fileId);
      }
    } catch (e) {
      // Ignore cleanup errors
    }
  });

  test('should delete (dismiss) a notification', async ({ request }) => {
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

    // Mark all existing notifications as read
    await granteeApi.markAllNotificationsRead();

    // Create a share to generate a notification
    const fileId = await createTestFile(ownerApi);
    const shareResponse = await ownerApi.shareFile({
      file_id: fileId,
      grantee_id: granteeId,
      ...generateShareCryptoParams(),
      permission: 'read',
    });

    // Find the notification
    const notifications = await granteeApi.getNotifications({ limit: 10 });
    const targetNotification = notifications.data.find(
      (n) => n.type === 'share_received' && n.data && (n.data as any).id === shareResponse.data.id
    );
    expect(targetNotification).toBeTruthy();

    // Delete (dismiss) the notification
    await granteeApi.deleteNotification(targetNotification!.id);

    // Verify the notification is gone
    const afterDelete = await granteeApi.getNotifications({ limit: 50 });
    const deletedNotification = afterDelete.data.find((n) => n.id === targetNotification!.id);
    expect(deletedNotification).toBeUndefined();

    // Cleanup
    try {
      await ownerApi.revokeShare(shareResponse.data.id);
      await ownerApi.deleteFile(fileId);
    } catch (e) {
      // Ignore cleanup errors
    }
  });
});

test.describe('Notification Channel - Notification Listing and Pagination', () => {
  test('should list notifications with pagination', async ({ request }) => {
    const { api: granteeApi } = await loginAndGetUserId(
      request,
      TEST_USERS.grantee.email,
      TEST_USERS.grantee.password
    );

    // Fetch notifications with limit
    const response = await granteeApi.getNotifications({ limit: 5, offset: 0 });
    expect(response.data).toBeDefined();
    expect(Array.isArray(response.data)).toBe(true);
    expect(response.meta).toBeDefined();
    expect(typeof response.meta.unread_count).toBe('number');

    // Each notification should have the expected fields
    if (response.data.length > 0) {
      const notification = response.data[0];
      expect(notification.id).toBeTruthy();
      expect(notification.type).toBeTruthy();
      expect(notification.title).toBeTruthy();
      expect(notification.body).toBeTruthy();
      expect(notification.created_at).toBeTruthy();
      // read_at can be null or a timestamp string
      expect(notification.read_at === null || typeof notification.read_at === 'string').toBe(true);
    }
  });

  test('should filter notifications by unread_only', async ({ request }) => {
    const { api: granteeApi } = await loginAndGetUserId(
      request,
      TEST_USERS.grantee.email,
      TEST_USERS.grantee.password
    );

    // Fetch only unread notifications
    const unreadResponse = await granteeApi.getNotifications({ unread_only: true });
    expect(unreadResponse.data).toBeDefined();

    // All returned notifications should be unread (read_at is null)
    for (const notification of unreadResponse.data) {
      expect(notification.read_at).toBeNull();
    }
  });

  test('should get unread notification count', async ({ request }) => {
    const { api: granteeApi } = await loginAndGetUserId(
      request,
      TEST_USERS.grantee.email,
      TEST_USERS.grantee.password
    );

    const response = await granteeApi.getUnreadNotificationCount();
    expect(response.data).toBeDefined();
    expect(typeof response.data.unread_count).toBe('number');
    expect(response.data.unread_count).toBeGreaterThanOrEqual(0);
  });
});

test.describe('Notification Channel - Share Operation Side Effects', () => {
  test.skip(skipFileTests, 'File tests disabled -- set ENABLE_FILE_UPLOAD_TESTS=1');

  test('share and revoke should each produce a persistent notification', async ({ request }) => {
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

    // Mark all existing notifications as read for clean baseline
    await granteeApi.markAllNotificationsRead();
    const initialCount = await granteeApi.getUnreadNotificationCount();
    expect(initialCount.data.unread_count).toBe(0);

    // Step 1: Share a file
    const fileId = await createTestFile(ownerApi);
    const shareResponse = await ownerApi.shareFile({
      file_id: fileId,
      grantee_id: granteeId,
      ...generateShareCryptoParams(),
      permission: 'write',
    });

    // Verify share notification
    const afterShareCount = await granteeApi.getUnreadNotificationCount();
    expect(afterShareCount.data.unread_count).toBeGreaterThanOrEqual(1);

    // Step 2: Revoke the share
    await ownerApi.revokeShare(shareResponse.data.id);

    // Verify revoke notification
    const afterRevokeCount = await granteeApi.getUnreadNotificationCount();
    expect(afterRevokeCount.data.unread_count).toBeGreaterThanOrEqual(2);

    // Verify both notification types exist
    const allNotifications = await granteeApi.getNotifications({ unread_only: true });
    const types = allNotifications.data.map((n) => n.type);
    expect(types).toContain('share_received');
    expect(types).toContain('share_revoked');

    // Cleanup
    try {
      await ownerApi.deleteFile(fileId);
    } catch (e) {
      // Ignore cleanup errors
    }
  });

  test('updating share permission should complete successfully', async ({ request }) => {
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

    // Create file and share
    const fileId = await createTestFile(ownerApi);
    const shareResponse = await ownerApi.shareFile({
      file_id: fileId,
      grantee_id: granteeId,
      ...generateShareCryptoParams(),
      permission: 'read',
    });

    // Update permission from read to write
    const updatedShare = await ownerApi.updateSharePermission(shareResponse.data.id, {
      permission: 'write',
      signature: crypto.randomBytes(64).toString('base64'),
    });
    expect(updatedShare.data.permission).toBe('write');

    // Verify grantee can still see the file via received shares
    const receivedShares = await granteeApi.listReceivedShares();
    const updatedReceivedShare = receivedShares.data.find(
      (s) => s.id === shareResponse.data.id
    );
    expect(updatedReceivedShare).toBeTruthy();

    // Cleanup
    try {
      await ownerApi.revokeShare(shareResponse.data.id);
      await ownerApi.deleteFile(fileId);
    } catch (e) {
      // Ignore cleanup errors
    }
  });
});
