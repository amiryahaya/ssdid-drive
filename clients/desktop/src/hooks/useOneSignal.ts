/**
 * OneSignal Integration Hook
 *
 * Manages OneSignal lifecycle and syncs with auth/notification stores.
 */

import { useEffect, useRef, useCallback } from 'react';
import { useAuthStore } from '@/stores/authStore';
import { useNotificationStore } from '@/stores/notificationStore';
import {
  initOneSignal,
  setExternalUserId,
  clearExternalUserId,
  setUserEmail,
  setUserTags,
  onNotificationClick,
  offNotificationClick,
  onForegroundNotification,
  offForegroundNotification,
} from '@/services/onesignal';

/**
 * Hook that manages OneSignal integration with the app
 * - Initializes OneSignal on mount
 * - Syncs user ID when auth state changes
 * - Refreshes notifications when push notifications arrive
 */
export function useOneSignal() {
  const user = useAuthStore((state) => state.user);
  const isAuthenticated = useAuthStore((state) => state.isAuthenticated);
  const loadNotifications = useNotificationStore((state) => state.loadNotifications);

  const previousUserIdRef = useRef<string | null>(null);
  const isInitializedRef = useRef(false);

  // Handle notification click - navigate or perform action
  const handleNotificationClick = useCallback(
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    (event: any) => {
      console.log('[OneSignal] Notification clicked:', event);

      // Refresh notifications list
      loadNotifications();

      // Handle deep linking based on notification data
      const additionalData = event?.notification?.additionalData;
      if (additionalData) {
        // Example: Navigate based on notification type
        const type = additionalData.type as string;
        const itemId = additionalData.itemId as string;

        if (type === 'share_received' && itemId) {
          // Could navigate to shared item
          console.log('[OneSignal] Share received notification, item:', itemId);
        } else if (type === 'recovery_request') {
          // Could navigate to recovery settings
          console.log('[OneSignal] Recovery request notification');
        }
      }
    },
    [loadNotifications]
  );

  // Handle foreground notifications - refresh notification list
  const handleForegroundNotification = useCallback(
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    (event: any) => {
      console.log('[OneSignal] Foreground notification:', event?.notification);

      // Refresh notifications list to show the new notification
      loadNotifications();
    },
    [loadNotifications]
  );

  // Initialize OneSignal on mount
  useEffect(() => {
    if (isInitializedRef.current) return;

    const initialize = async () => {
      await initOneSignal();
      isInitializedRef.current = true;
    };

    initialize();
  }, []);

  // Set up notification listeners
  useEffect(() => {
    onNotificationClick(handleNotificationClick);
    onForegroundNotification(handleForegroundNotification);

    return () => {
      offNotificationClick(handleNotificationClick);
      offForegroundNotification(handleForegroundNotification);
    };
  }, [handleNotificationClick, handleForegroundNotification]);

  // Sync user ID with OneSignal when auth state changes
  useEffect(() => {
    const syncUser = async () => {
      const currentUserId = user?.id || null;

      // Skip if user ID hasn't changed
      if (currentUserId === previousUserIdRef.current) {
        return;
      }

      previousUserIdRef.current = currentUserId;

      if (isAuthenticated && user) {
        // User logged in - set external user ID and email
        await setExternalUserId(user.id);
        await setUserEmail(user.email);

        // Set additional tags for segmentation
        await setUserTags({
          tenant_id: user.tenantId,
          platform: 'desktop',
        });

        console.log('[OneSignal] User synced:', user.id);
      } else {
        // User logged out - clear external user ID
        await clearExternalUserId();
        console.log('[OneSignal] User cleared');
      }
    };

    syncUser();
  }, [user, isAuthenticated]);
}
