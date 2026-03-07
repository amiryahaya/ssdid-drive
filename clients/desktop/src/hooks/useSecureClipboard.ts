import { useCallback, useRef, useState, useEffect } from 'react';
import { useToast } from './useToast';

/**
 * Secure clipboard timeouts in milliseconds
 */
export const CLIPBOARD_TIMEOUTS = {
  /** Default timeout for general sensitive data: 60 seconds */
  DEFAULT: 60_000,
  /** Timeout for passwords: 30 seconds */
  PASSWORD: 30_000,
  /** Timeout for recovery keys: 15 seconds (most sensitive) */
  RECOVERY_KEY: 15_000,
  /** Timeout for share links: 5 minutes (less sensitive) */
  SHARE_LINK: 300_000,
} as const;

export type ClipboardContentType = 'default' | 'password' | 'recovery_key' | 'share_link';

interface ClipboardState {
  hasSensitiveContent: boolean;
  label: string | null;
  willAutoClear: boolean;
  timeUntilClear: number;
}

interface UseSecureClipboardOptions {
  /** Show toast notifications for copy/clear events */
  showNotifications?: boolean;
}

/**
 * Secure clipboard hook that handles sensitive data safely.
 *
 * SECURITY: This hook provides:
 * - Automatic clipboard clearing after a timeout
 * - Different timeouts for different sensitivity levels
 * - Manual clipboard clearing capability
 * - State tracking for UI feedback
 */
export function useSecureClipboard(options: UseSecureClipboardOptions = {}) {
  const { showNotifications = true } = options;
  const { success } = useToast();

  const clearTimeoutRef = useRef<NodeJS.Timeout | null>(null);
  const copiedTextRef = useRef<string | null>(null);
  const copiedLabelRef = useRef<string | null>(null);

  const [clipboardState, setClipboardState] = useState<ClipboardState>({
    hasSensitiveContent: false,
    label: null,
    willAutoClear: false,
    timeUntilClear: 0,
  });

  // Clean up timeout on unmount
  useEffect(() => {
    return () => {
      if (clearTimeoutRef.current) {
        clearTimeout(clearTimeoutRef.current);
      }
    };
  }, []);

  /**
   * Cancel any pending clipboard clear operation
   */
  const cancelPendingClear = useCallback(() => {
    if (clearTimeoutRef.current) {
      clearTimeout(clearTimeoutRef.current);
      clearTimeoutRef.current = null;
    }
    setClipboardState((prev) => ({
      ...prev,
      willAutoClear: false,
      timeUntilClear: 0,
    }));
  }, []);

  /**
   * Clear the clipboard
   */
  const clearClipboard = useCallback(async () => {
    cancelPendingClear();

    try {
      // Write empty string to clipboard
      await navigator.clipboard.writeText('');
      copiedTextRef.current = null;
      copiedLabelRef.current = null;

      setClipboardState({
        hasSensitiveContent: false,
        label: null,
        willAutoClear: false,
        timeUntilClear: 0,
      });

      if (showNotifications) {
        success({
          title: 'Clipboard cleared',
          description: 'Sensitive data has been removed from clipboard',
        });
      }
    } catch (error) {
      console.error('Failed to clear clipboard:', error);
    }
  }, [cancelPendingClear, showNotifications, success]);

  /**
   * Schedule clipboard clear after delay
   */
  const scheduleClear = useCallback((delayMs: number) => {
    cancelPendingClear();

    setClipboardState((prev) => ({
      ...prev,
      willAutoClear: true,
      timeUntilClear: delayMs,
    }));

    clearTimeoutRef.current = setTimeout(() => {
      clearClipboard();
    }, delayMs);
  }, [cancelPendingClear, clearClipboard]);

  /**
   * Copy sensitive text to clipboard with automatic clearing
   */
  const copySensitiveText = useCallback(
    async (
      text: string,
      label: string,
      clearAfterMs: number = CLIPBOARD_TIMEOUTS.DEFAULT
    ): Promise<boolean> => {
      try {
        await navigator.clipboard.writeText(text);

        copiedTextRef.current = text;
        copiedLabelRef.current = label;

        setClipboardState({
          hasSensitiveContent: true,
          label,
          willAutoClear: clearAfterMs > 0,
          timeUntilClear: clearAfterMs,
        });

        if (showNotifications) {
          const clearSeconds = Math.round(clearAfterMs / 1000);
          success({
            title: 'Copied to clipboard',
            description: `${label} copied. Will auto-clear in ${clearSeconds}s`,
          });
        }

        if (clearAfterMs > 0) {
          scheduleClear(clearAfterMs);
        }

        return true;
      } catch (error) {
        console.error('Failed to copy to clipboard:', error);
        return false;
      }
    },
    [showNotifications, success, scheduleClear]
  );

  /**
   * Copy a password to clipboard with short auto-clear time
   */
  const copyPassword = useCallback(
    async (password: string): Promise<boolean> => {
      return copySensitiveText(password, 'Password', CLIPBOARD_TIMEOUTS.PASSWORD);
    },
    [copySensitiveText]
  );

  /**
   * Copy a recovery key or seed phrase with very short auto-clear
   */
  const copyRecoveryKey = useCallback(
    async (key: string): Promise<boolean> => {
      return copySensitiveText(key, 'Recovery Key', CLIPBOARD_TIMEOUTS.RECOVERY_KEY);
    },
    [copySensitiveText]
  );

  /**
   * Copy a share link (less sensitive, longer timeout)
   */
  const copyShareLink = useCallback(
    async (link: string): Promise<boolean> => {
      return copySensitiveText(link, 'Share Link', CLIPBOARD_TIMEOUTS.SHARE_LINK);
    },
    [copySensitiveText]
  );

  /**
   * Copy text without auto-clear (for non-sensitive data)
   */
  const copyText = useCallback(
    async (text: string, label: string = 'Text'): Promise<boolean> => {
      try {
        await navigator.clipboard.writeText(text);

        copiedTextRef.current = text;
        copiedLabelRef.current = label;

        setClipboardState({
          hasSensitiveContent: false,
          label,
          willAutoClear: false,
          timeUntilClear: 0,
        });

        if (showNotifications) {
          success({
            title: 'Copied to clipboard',
            description: `${label} copied`,
          });
        }

        return true;
      } catch (error) {
        console.error('Failed to copy to clipboard:', error);
        return false;
      }
    },
    [showNotifications, success]
  );

  /**
   * Check if the clipboard contains our copied content
   */
  const hasOurContent = useCallback(async (): Promise<boolean> => {
    if (!copiedTextRef.current) return false;

    try {
      const currentText = await navigator.clipboard.readText();
      return currentText === copiedTextRef.current;
    } catch (error) {
      // Clipboard read may be restricted
      return false;
    }
  }, []);

  return {
    // Copy functions
    copySensitiveText,
    copyPassword,
    copyRecoveryKey,
    copyShareLink,
    copyText,

    // State
    clipboardState,

    // Actions
    clearClipboard,
    cancelPendingClear,
    hasOurContent,

    // Constants
    timeouts: CLIPBOARD_TIMEOUTS,
  };
}
