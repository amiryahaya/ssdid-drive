import { useState, useEffect, useCallback } from 'react';
import { invoke } from '@tauri-apps/api/core';
import { platform } from '@tauri-apps/plugin-os';

/**
 * File Provider extension status
 */
interface FileProviderStatus {
  isAvailable: boolean;
  isRegistered: boolean;
  containerPath: string | null;
}

/**
 * Hook for managing macOS File Provider extension (Finder integration)
 *
 * The File Provider extension allows SecureSharing files to appear directly
 * in Finder, enabling users to browse, open, and manage encrypted files
 * as if they were local files.
 *
 * This hook is only functional on macOS - on other platforms it returns
 * a disabled state.
 */
export function useFileProvider() {
  const [status, setStatus] = useState<FileProviderStatus>({
    isAvailable: false,
    isRegistered: false,
    containerPath: null,
  });
  const [isLoading, setIsLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [isMacOS, setIsMacOS] = useState(false);

  // Check platform on mount
  useEffect(() => {
    const checkPlatform = async () => {
      try {
        const currentPlatform = await platform();
        setIsMacOS(currentPlatform === 'macos');
      } catch {
        setIsMacOS(false);
      }
    };
    checkPlatform();
  }, []);

  // Check File Provider availability
  const checkAvailability = useCallback(async () => {
    if (!isMacOS) {
      setStatus({
        isAvailable: false,
        isRegistered: false,
        containerPath: null,
      });
      return;
    }

    try {
      const [isAvailable, containerPath] = await Promise.all([
        invoke<boolean>('is_file_provider_available'),
        invoke<string | null>('get_file_provider_container_path'),
      ]);

      setStatus(prev => ({
        ...prev,
        isAvailable,
        containerPath,
      }));
    } catch (err) {
      console.error('Failed to check File Provider availability:', err);
      setError(err instanceof Error ? err.message : 'Unknown error');
    }
  }, [isMacOS]);

  // Initial availability check
  useEffect(() => {
    if (isMacOS) {
      checkAvailability();
    }
  }, [isMacOS, checkAvailability]);

  // Register the File Provider domain
  const register = useCallback(async () => {
    if (!isMacOS || !status.isAvailable) {
      return;
    }

    setIsLoading(true);
    setError(null);

    try {
      await invoke('register_file_provider_domain');
      setStatus(prev => ({ ...prev, isRegistered: true }));
    } catch (err) {
      console.error('Failed to register File Provider:', err);
      setError(err instanceof Error ? err.message : 'Failed to register');
    } finally {
      setIsLoading(false);
    }
  }, [isMacOS, status.isAvailable]);

  // Unregister the File Provider domain (e.g., on logout)
  const unregister = useCallback(async () => {
    if (!isMacOS) {
      return;
    }

    setIsLoading(true);
    setError(null);

    try {
      await invoke('unregister_file_provider_domain');
      setStatus(prev => ({ ...prev, isRegistered: false }));
    } catch (err) {
      console.error('Failed to unregister File Provider:', err);
      setError(err instanceof Error ? err.message : 'Failed to unregister');
    } finally {
      setIsLoading(false);
    }
  }, [isMacOS]);

  // Signal that a file has changed
  const signalFileChanged = useCallback(async (fileId: string) => {
    if (!isMacOS || !status.isAvailable) {
      return;
    }

    try {
      await invoke('signal_file_changed', { fileId });
    } catch (err) {
      console.error('Failed to signal file change:', err);
    }
  }, [isMacOS, status.isAvailable]);

  // Process pending crypto requests from the extension
  const processCryptoRequests = useCallback(async (): Promise<number> => {
    if (!isMacOS || !status.isAvailable) {
      return 0;
    }

    try {
      const processed = await invoke<number>('process_crypto_requests');
      return processed;
    } catch (err) {
      console.error('Failed to process crypto requests:', err);
      return 0;
    }
  }, [isMacOS, status.isAvailable]);

  // Sync file metadata to the extension
  const syncMetadata = useCallback(async (): Promise<number> => {
    if (!isMacOS || !status.isAvailable) {
      return 0;
    }

    setIsLoading(true);
    setError(null);

    try {
      const synced = await invoke<number>('sync_file_metadata_to_extension');
      return synced;
    } catch (err) {
      console.error('Failed to sync metadata:', err);
      setError(err instanceof Error ? err.message : 'Failed to sync');
      return 0;
    } finally {
      setIsLoading(false);
    }
  }, [isMacOS, status.isAvailable]);

  // Set up periodic crypto request processing
  useEffect(() => {
    if (!isMacOS || !status.isAvailable || !status.isRegistered) {
      return;
    }

    // Process crypto requests every 2 seconds
    const interval = setInterval(() => {
      processCryptoRequests();
    }, 2000);

    return () => clearInterval(interval);
  }, [isMacOS, status.isAvailable, status.isRegistered, processCryptoRequests]);

  return {
    // Status
    status,
    isLoading,
    error,
    isMacOS,

    // Computed
    isEnabled: status.isAvailable && status.isRegistered,

    // Actions
    register,
    unregister,
    signalFileChanged,
    processCryptoRequests,
    syncMetadata,
    refreshStatus: checkAvailability,
  };
}
