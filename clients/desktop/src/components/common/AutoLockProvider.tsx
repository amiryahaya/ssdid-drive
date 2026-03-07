import { useEffect } from 'react';
import { useIdleDetector } from '@/hooks/useIdleDetector';
import { useAuthStore } from '@/stores/authStore';
import { useSettingsStore } from '@/stores/settingsStore';

/**
 * Provider component that handles automatic locking after inactivity
 * Place this in the app root to enable auto-lock functionality
 */
export function AutoLockProvider() {
  const isAuthenticated = useAuthStore((state) => state.isAuthenticated);
  const isLocked = useAuthStore((state) => state.isLocked);
  const lock = useAuthStore((state) => state.lock);
  const updateLastActivity = useAuthStore((state) => state.updateLastActivity);

  const autoLockTimeout = useSettingsStore((state) => state.settings.autoLockTimeout);

  // Use idle detector to auto-lock
  useIdleDetector({
    timeout: autoLockTimeout,
    onIdle: () => {
      // Only lock if authenticated and not already locked
      if (isAuthenticated && !isLocked) {
        console.log('Auto-locking due to inactivity');
        lock();
      }
    },
    onActive: () => {
      // Update last activity timestamp when user becomes active
      updateLastActivity();
    },
    enabled: isAuthenticated && !isLocked && autoLockTimeout > 0,
  });

  // Also handle window blur/focus for additional security
  useEffect(() => {
    if (!isAuthenticated || isLocked || autoLockTimeout <= 0) {
      return;
    }

    let blurTimeout: ReturnType<typeof setTimeout> | null = null;

    const handleBlur = () => {
      // Start a shorter timeout when window loses focus
      // Use half the normal timeout for background inactivity
      const blurLockTime = Math.min(autoLockTimeout * 500, 30000); // Max 30 seconds
      blurTimeout = setTimeout(() => {
        if (!document.hasFocus()) {
          lock();
        }
      }, blurLockTime);
    };

    const handleFocus = () => {
      // Clear the blur timeout if window regains focus
      if (blurTimeout) {
        clearTimeout(blurTimeout);
        blurTimeout = null;
      }
      updateLastActivity();
    };

    window.addEventListener('blur', handleBlur);
    window.addEventListener('focus', handleFocus);

    return () => {
      if (blurTimeout) {
        clearTimeout(blurTimeout);
      }
      window.removeEventListener('blur', handleBlur);
      window.removeEventListener('focus', handleFocus);
    };
  }, [isAuthenticated, isLocked, autoLockTimeout, lock, updateLastActivity]);

  // This component doesn't render anything
  return null;
}
