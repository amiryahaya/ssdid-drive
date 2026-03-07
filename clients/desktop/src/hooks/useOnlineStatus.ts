import { useState, useEffect, useCallback } from 'react';

interface OnlineStatus {
  isOnline: boolean;
  wasOffline: boolean;
  lastOnline: Date | null;
}

/**
 * Hook to monitor network connectivity status.
 * Provides isOnline state and wasOffline flag to show "back online" notifications.
 */
export function useOnlineStatus(): OnlineStatus {
  const [isOnline, setIsOnline] = useState(
    typeof navigator !== 'undefined' ? navigator.onLine : true
  );
  const [wasOffline, setWasOffline] = useState(false);
  const [lastOnline, setLastOnline] = useState<Date | null>(null);

  const handleOnline = useCallback(() => {
    setIsOnline(true);
    if (!isOnline) {
      // Coming back online after being offline
      setWasOffline(true);
      // Clear the wasOffline flag after a short delay
      setTimeout(() => setWasOffline(false), 5000);
    }
  }, [isOnline]);

  const handleOffline = useCallback(() => {
    setIsOnline(false);
    setLastOnline(new Date());
  }, []);

  useEffect(() => {
    window.addEventListener('online', handleOnline);
    window.addEventListener('offline', handleOffline);

    return () => {
      window.removeEventListener('online', handleOnline);
      window.removeEventListener('offline', handleOffline);
    };
  }, [handleOnline, handleOffline]);

  return { isOnline, wasOffline, lastOnline };
}

/**
 * Utility to check if an error is likely a network error.
 */
export function isNetworkError(error: unknown): boolean {
  if (error instanceof Error) {
    const message = error.message.toLowerCase();
    return (
      message.includes('network') ||
      message.includes('fetch') ||
      message.includes('connection') ||
      message.includes('offline') ||
      message.includes('timeout') ||
      message.includes('econnrefused')
    );
  }
  return false;
}
