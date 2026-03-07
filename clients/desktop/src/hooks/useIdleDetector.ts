import { useEffect, useCallback, useRef } from 'react';

interface UseIdleDetectorOptions {
  /** Timeout in seconds before considered idle (0 = disabled) */
  timeout: number;
  /** Callback when user becomes idle */
  onIdle: () => void;
  /** Callback when user becomes active again (optional) */
  onActive?: () => void;
  /** Whether the detector is enabled */
  enabled?: boolean;
}

/**
 * Hook to detect user inactivity
 * Tracks mouse, keyboard, touch, and scroll events
 */
export function useIdleDetector({
  timeout,
  onIdle,
  onActive,
  enabled = true,
}: UseIdleDetectorOptions) {
  const timeoutRef = useRef<ReturnType<typeof setTimeout> | null>(null);
  const isIdleRef = useRef(false);

  const resetTimer = useCallback(() => {
    // Clear existing timeout
    if (timeoutRef.current) {
      clearTimeout(timeoutRef.current);
      timeoutRef.current = null;
    }

    // If was idle and now active, call onActive
    if (isIdleRef.current && onActive) {
      isIdleRef.current = false;
      onActive();
    }

    // Don't set timer if disabled or timeout is 0
    if (!enabled || timeout <= 0) {
      return;
    }

    // Set new timeout
    timeoutRef.current = setTimeout(() => {
      if (!isIdleRef.current) {
        isIdleRef.current = true;
        onIdle();
      }
    }, timeout * 1000);
  }, [timeout, onIdle, onActive, enabled]);

  useEffect(() => {
    if (!enabled || timeout <= 0) {
      // Clean up if disabled
      if (timeoutRef.current) {
        clearTimeout(timeoutRef.current);
        timeoutRef.current = null;
      }
      return;
    }

    // Events to track for activity
    const events = [
      'mousedown',
      'mousemove',
      'keydown',
      'scroll',
      'touchstart',
      'wheel',
      'resize',
      'visibilitychange',
    ];

    // Throttle the reset to avoid excessive calls
    let lastReset = 0;
    const throttledReset = () => {
      const now = Date.now();
      // Throttle to max once per second
      if (now - lastReset > 1000) {
        lastReset = now;
        resetTimer();
      }
    };

    // Handle visibility change specially
    const handleVisibilityChange = () => {
      if (document.visibilityState === 'visible') {
        resetTimer();
      }
    };

    // Add event listeners
    events.forEach((event) => {
      if (event === 'visibilitychange') {
        document.addEventListener(event, handleVisibilityChange);
      } else {
        window.addEventListener(event, throttledReset, { passive: true });
      }
    });

    // Start the initial timer
    resetTimer();

    // Cleanup
    return () => {
      if (timeoutRef.current) {
        clearTimeout(timeoutRef.current);
      }
      events.forEach((event) => {
        if (event === 'visibilitychange') {
          document.removeEventListener(event, handleVisibilityChange);
        } else {
          window.removeEventListener(event, throttledReset);
        }
      });
    };
  }, [enabled, timeout, resetTimer]);

  // Return function to manually reset the timer (e.g., after user action)
  return { resetTimer };
}
