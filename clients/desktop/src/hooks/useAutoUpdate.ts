import { useState, useEffect, useCallback, useRef } from 'react';
import { check } from '@tauri-apps/plugin-updater';
import { relaunch } from '@tauri-apps/plugin-process';

interface UpdateState {
  /** Whether an update is available */
  updateAvailable: boolean;
  /** Version string of the available update */
  version: string | null;
  /** Release notes / changelog */
  body: string | null;
  /** Whether the update is currently downloading/installing */
  isUpdating: boolean;
  /** Download progress percentage (0-100) */
  progress: number;
  /** Error message if update check/install failed */
  error: string | null;
  /** Check for updates manually */
  checkForUpdate: () => Promise<void>;
  /** Download and install the available update */
  installUpdate: () => Promise<void>;
  /** Dismiss the update notification */
  dismiss: () => void;
}

/** Check interval: 4 hours in milliseconds */
const CHECK_INTERVAL = 4 * 60 * 60 * 1000;

/**
 * Hook for automatic update detection and installation.
 * Checks for updates on mount and every 4 hours.
 */
export function useAutoUpdate(): UpdateState {
  const [updateAvailable, setUpdateAvailable] = useState(false);
  const [version, setVersion] = useState<string | null>(null);
  const [body, setBody] = useState<string | null>(null);
  const [isUpdating, setIsUpdating] = useState(false);
  const [progress, setProgress] = useState(0);
  const [error, setError] = useState<string | null>(null);
  const updateRef = useRef<Awaited<ReturnType<typeof check>> | null>(null);

  const checkForUpdate = useCallback(async () => {
    try {
      setError(null);
      const update = await check();

      if (update) {
        setUpdateAvailable(true);
        setVersion(update.version);
        setBody(update.body ?? null);
        updateRef.current = update;
      } else {
        setUpdateAvailable(false);
        setVersion(null);
        setBody(null);
        updateRef.current = null;
      }
    } catch (e) {
      console.error('Update check failed:', e);
      setError(e instanceof Error ? e.message : 'Update check failed');
    }
  }, []);

  const installUpdate = useCallback(async () => {
    const update = updateRef.current;
    if (!update) return;

    try {
      setIsUpdating(true);
      setError(null);
      setProgress(0);

      let downloaded = 0;
      let contentLength = 0;

      await update.downloadAndInstall((event) => {
        switch (event.event) {
          case 'Started':
            contentLength = event.data.contentLength ?? 0;
            break;
          case 'Progress':
            downloaded += event.data.chunkLength;
            if (contentLength > 0) {
              setProgress(Math.round((downloaded / contentLength) * 100));
            }
            break;
          case 'Finished':
            setProgress(100);
            break;
        }
      });

      // Relaunch the app to apply the update
      await relaunch();
    } catch (e) {
      console.error('Update install failed:', e);
      setError(e instanceof Error ? e.message : 'Update installation failed');
      setIsUpdating(false);
    }
  }, []);

  const dismiss = useCallback(() => {
    setUpdateAvailable(false);
    updateRef.current = null;
  }, []);

  // Check on mount and at regular intervals
  useEffect(() => {
    // Initial check after a short delay to not block app startup
    const initialTimeout = setTimeout(checkForUpdate, 5000);

    const interval = setInterval(checkForUpdate, CHECK_INTERVAL);

    return () => {
      clearTimeout(initialTimeout);
      clearInterval(interval);
    };
  }, [checkForUpdate]);

  return {
    updateAvailable,
    version,
    body,
    isUpdating,
    progress,
    error,
    checkForUpdate,
    installUpdate,
    dismiss,
  };
}
