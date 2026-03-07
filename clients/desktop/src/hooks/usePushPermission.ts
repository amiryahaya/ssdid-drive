/**
 * Hook to manage push notification permission state
 */

import { useState, useEffect, useCallback } from 'react';
import { requestPermission, isPushEnabled } from '@/services/onesignal';

export type PermissionStatus = 'granted' | 'denied' | 'default' | 'unsupported';

interface PushPermissionState {
  status: PermissionStatus;
  isLoading: boolean;
  requestPermission: () => Promise<boolean>;
  refreshStatus: () => Promise<void>;
}

/**
 * Hook to check and request push notification permissions
 */
export function usePushPermission(): PushPermissionState {
  const [status, setStatus] = useState<PermissionStatus>('default');
  const [isLoading, setIsLoading] = useState(true);

  // Check if notifications are supported
  const checkSupport = useCallback((): boolean => {
    return typeof window !== 'undefined' && 'Notification' in window;
  }, []);

  // Get current permission status
  const refreshStatus = useCallback(async () => {
    if (!checkSupport()) {
      setStatus('unsupported');
      setIsLoading(false);
      return;
    }

    try {
      // Check browser's Notification API permission
      const browserPermission = Notification.permission as PermissionStatus;

      // Also check OneSignal's permission state
      const oneSignalEnabled = await isPushEnabled();

      if (browserPermission === 'granted' && oneSignalEnabled) {
        setStatus('granted');
      } else if (browserPermission === 'denied') {
        setStatus('denied');
      } else {
        setStatus('default');
      }
    } catch (error) {
      console.error('[PushPermission] Error checking status:', error);
      setStatus('default');
    } finally {
      setIsLoading(false);
    }
  }, [checkSupport]);

  // Request permission from user
  const handleRequestPermission = useCallback(async (): Promise<boolean> => {
    if (!checkSupport()) {
      return false;
    }

    setIsLoading(true);
    try {
      const granted = await requestPermission();
      await refreshStatus();
      return granted;
    } catch (error) {
      console.error('[PushPermission] Error requesting permission:', error);
      await refreshStatus();
      return false;
    }
  }, [checkSupport, refreshStatus]);

  // Check permission on mount
  useEffect(() => {
    refreshStatus();
  }, [refreshStatus]);

  // Listen for permission changes (some browsers support this)
  useEffect(() => {
    if (!checkSupport()) return;

    // Poll for permission changes since not all browsers support the change event
    const interval = setInterval(() => {
      const currentPermission = Notification.permission as PermissionStatus;
      setStatus((prev) => {
        if (currentPermission === 'granted' && prev !== 'granted') {
          return 'granted';
        }
        if (currentPermission === 'denied' && prev !== 'denied') {
          return 'denied';
        }
        return prev;
      });
    }, 5000);

    return () => clearInterval(interval);
  }, [checkSupport]);

  return {
    status,
    isLoading,
    requestPermission: handleRequestPermission,
    refreshStatus,
  };
}
