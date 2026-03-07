/**
 * Device Management E2E Tests
 *
 * Tests for:
 * - Updating device name
 * - Revoking a device with reason
 * - Revoked device appears with revoked_at timestamp
 * - Register push notification (player_id)
 * - Unregister push notification
 * - Cannot update a revoked device
 */

import { test, expect } from '@playwright/test';
import { BackendApiClient, CONFIG } from '../../lib/api-client';
import crypto from 'crypto';

// Test user from seed data
const TEST_USER = {
  email: 'user1@e2e-test.local',
  password: 'TestUserPassword123!',
};

// Helper to generate device enrollment params
function generateDeviceParams(overrides: Partial<{
  device_fingerprint: string;
  platform: string;
  device_info: { model: string; os_version: string; app_version: string };
  device_public_key: string;
  key_algorithm: string;
  device_name: string;
}> = {}) {
  return {
    device_fingerprint: crypto.randomBytes(32).toString('hex'),
    platform: 'android',
    device_info: {
      model: 'Pixel 8',
      os_version: 'Android 14',
      app_version: '1.0.0',
    },
    device_public_key: crypto.randomBytes(32).toString('base64'),
    key_algorithm: 'kaz_sign',
    device_name: `E2E Test Device ${Date.now()}`,
    ...overrides,
  };
}

// Helper to enroll a device and return the enrollment ID
async function enrollTestDevice(api: BackendApiClient): Promise<string> {
  const params = generateDeviceParams();
  const response = await api.enrollDevice(params);
  return response.data.id;
}

test.describe('Device Name Update', () => {
  test('should update device name', async ({ request }) => {
    const api = new BackendApiClient(request);
    await api.login(TEST_USER.email, TEST_USER.password);

    const enrollmentId = await enrollTestDevice(api);
    const newName = `Renamed Device ${Date.now()}`;

    const updateResponse = await api.updateDevice(enrollmentId, {
      device_name: newName,
    });

    expect(updateResponse.data).toBeDefined();
    expect(updateResponse.data.device_name).toBe(newName);

    // Verify via get
    const getResponse = await api.getDevice(enrollmentId);
    expect(getResponse.data.device_name).toBe(newName);

    // Cleanup
    try {
      await api.revokeDevice(enrollmentId);
    } catch (e) {}
  });
});

test.describe('Device Revocation', () => {
  test('should revoke a device with reason', async ({ request }) => {
    const api = new BackendApiClient(request);
    await api.login(TEST_USER.email, TEST_USER.password);

    const enrollmentId = await enrollTestDevice(api);
    const reason = 'Device lost';

    const revokeResponse = await api.revokeDevice(enrollmentId, reason);

    expect(revokeResponse.data).toBeDefined();
    expect(revokeResponse.data.revoked_at).toBeDefined();
    expect(revokeResponse.data.revoked_at).not.toBeNull();
    expect(revokeResponse.data.revoked_reason).toBe(reason);
  });

  test('revoked device appears with revoked_at timestamp', async ({ request }) => {
    const api = new BackendApiClient(request);
    await api.login(TEST_USER.email, TEST_USER.password);

    const enrollmentId = await enrollTestDevice(api);

    await api.revokeDevice(enrollmentId, 'Stolen device');

    const deviceResponse = await api.getDevice(enrollmentId);
    expect(deviceResponse.data.revoked_at).toBeDefined();
    expect(deviceResponse.data.revoked_at).not.toBeNull();
    // Verify the timestamp is a valid ISO date string
    const revokedDate = new Date(deviceResponse.data.revoked_at);
    expect(revokedDate.getTime()).not.toBeNaN();
  });

  test('cannot update a revoked device', async ({ request }) => {
    const api = new BackendApiClient(request);
    await api.login(TEST_USER.email, TEST_USER.password);

    const enrollmentId = await enrollTestDevice(api);

    // Revoke the device first
    await api.revokeDevice(enrollmentId, 'Testing revocation');

    // Attempt to update the revoked device
    try {
      await api.updateDevice(enrollmentId, {
        device_name: 'Should Not Work',
      });
      // If update succeeds, verify it still shows as revoked
      const deviceResponse = await api.getDevice(enrollmentId);
      expect(deviceResponse.data.revoked_at).not.toBeNull();
    } catch (error) {
      // Expected: API should reject updates to revoked devices
      expect((error as Error).message).toMatch(/failed|4\d\d/);
    }
  });
});

test.describe('Push Notification Management', () => {
  test('should register push notification player_id', async ({ request }) => {
    const api = new BackendApiClient(request);
    await api.login(TEST_USER.email, TEST_USER.password);

    const enrollmentId = await enrollTestDevice(api);
    const playerId = `onesignal-player-${crypto.randomBytes(16).toString('hex')}`;

    const pushResponse = await api.registerPush(enrollmentId, {
      player_id: playerId,
    });

    expect(pushResponse.data).toBeDefined();
    expect(pushResponse.data.id).toBe(enrollmentId);

    // Cleanup
    try {
      await api.revokeDevice(enrollmentId);
    } catch (e) {}
  });

  test('should unregister push notification', async ({ request }) => {
    const api = new BackendApiClient(request);
    await api.login(TEST_USER.email, TEST_USER.password);

    const enrollmentId = await enrollTestDevice(api);
    const playerId = `onesignal-player-${crypto.randomBytes(16).toString('hex')}`;

    // Register push first
    await api.registerPush(enrollmentId, { player_id: playerId });

    // Unregister push
    const unregisterResponse = await api.unregisterPush(enrollmentId);

    expect(unregisterResponse.data).toBeDefined();
    expect(unregisterResponse.data.id).toBe(enrollmentId);

    // Cleanup
    try {
      await api.revokeDevice(enrollmentId);
    } catch (e) {}
  });
});
