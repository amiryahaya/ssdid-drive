/**
 * OneSignal Push Notification Service
 *
 * Handles initialization and management of OneSignal web push notifications.
 * Integrates with the auth system to sync user IDs for targeted notifications.
 */

import OneSignal from 'react-onesignal';

const ONESIGNAL_APP_ID = import.meta.env.VITE_ONESIGNAL_APP_ID || '';
const SAFARI_WEB_ID = import.meta.env.VITE_ONESIGNAL_SAFARI_WEB_ID || '';

let isInitialized = false;

/**
 * Initialize OneSignal SDK
 * Should be called once when the app starts
 */
export async function initOneSignal(): Promise<void> {
  if (isInitialized) {
    console.log('[OneSignal] Already initialized');
    return;
  }

  try {
    await OneSignal.init({
      appId: ONESIGNAL_APP_ID,
      safari_web_id: SAFARI_WEB_ID,
      allowLocalhostAsSecureOrigin: true, // For development
    });

    isInitialized = true;
    console.log('[OneSignal] Initialized successfully');

    // Log permission state
    const permission = await OneSignal.Notifications.permission;
    console.log('[OneSignal] Current permission:', permission);
  } catch (error) {
    console.error('[OneSignal] Failed to initialize:', error);
  }
}

/**
 * Request notification permission from the user
 * Returns true if permission was granted
 */
export async function requestPermission(): Promise<boolean> {
  try {
    const permission = await OneSignal.Notifications.requestPermission();
    console.log('[OneSignal] Permission result:', permission);
    return permission;
  } catch (error) {
    console.error('[OneSignal] Permission request failed:', error);
    return false;
  }
}

/**
 * Check if notifications are enabled
 */
export async function isPushEnabled(): Promise<boolean> {
  try {
    return await OneSignal.Notifications.permission;
  } catch {
    return false;
  }
}

/**
 * Set the external user ID to associate notifications with the user
 * Call this after successful login
 */
export async function setExternalUserId(userId: string): Promise<void> {
  try {
    await OneSignal.login(userId);
    console.log('[OneSignal] External user ID set:', userId);
  } catch (error) {
    console.error('[OneSignal] Failed to set external user ID:', error);
  }
}

/**
 * Clear the external user ID on logout
 */
export async function clearExternalUserId(): Promise<void> {
  try {
    await OneSignal.logout();
    console.log('[OneSignal] External user ID cleared');
  } catch (error) {
    console.error('[OneSignal] Failed to clear external user ID:', error);
  }
}

/**
 * Add tags for user segmentation
 * Useful for sending targeted notifications
 */
export async function setUserTags(tags: Record<string, string>): Promise<void> {
  try {
    await OneSignal.User.addTags(tags);
    console.log('[OneSignal] Tags set:', tags);
  } catch (error) {
    console.error('[OneSignal] Failed to set tags:', error);
  }
}

/**
 * Set user email for OneSignal
 */
export async function setUserEmail(email: string): Promise<void> {
  try {
    await OneSignal.User.addEmail(email);
    console.log('[OneSignal] Email set:', email);
  } catch (error) {
    console.error('[OneSignal] Failed to set email:', error);
  }
}

// eslint-disable-next-line @typescript-eslint/no-explicit-any
type NotificationCallback = (event: any) => void;

/**
 * Register a callback for notification clicks
 */
export function onNotificationClick(callback: NotificationCallback): void {
  OneSignal.Notifications.addEventListener('click', callback);
}

/**
 * Remove notification click listener
 */
export function offNotificationClick(callback: NotificationCallback): void {
  OneSignal.Notifications.removeEventListener('click', callback);
}

/**
 * Register a callback for foreground notifications
 */
export function onForegroundNotification(callback: NotificationCallback): void {
  OneSignal.Notifications.addEventListener('foregroundWillDisplay', callback);
}

/**
 * Remove foreground notification listener
 */
export function offForegroundNotification(callback: NotificationCallback): void {
  OneSignal.Notifications.removeEventListener('foregroundWillDisplay', callback);
}

export default {
  init: initOneSignal,
  requestPermission,
  isPushEnabled,
  setExternalUserId,
  clearExternalUserId,
  setUserTags,
  setUserEmail,
  onNotificationClick,
  offNotificationClick,
  onForegroundNotification,
  offForegroundNotification,
};
