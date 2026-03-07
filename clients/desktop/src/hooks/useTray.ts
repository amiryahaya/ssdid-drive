import { useEffect, useCallback } from 'react';
import { invoke } from '@tauri-apps/api/core';
import { listen, UnlistenFn } from '@tauri-apps/api/event';
import { useNavigate } from 'react-router-dom';
import { useFileStore } from '@/stores/fileStore';
import { useNotificationStore } from '@/stores/notificationStore';

/**
 * Sync status for tray display
 */
export type SyncStatus =
  | { Idle: null }
  | { Syncing: { progress: number; file_name: string | null } }
  | { Error: string };

/**
 * Recent file entry for tray menu
 */
export interface RecentFile {
  id: string;
  name: string;
  path: string | null;
}

/**
 * Hook for system tray integration
 * - Syncs recent files to tray menu
 * - Syncs notification count to tray
 * - Handles tray menu events
 */
export function useTray() {
  const navigate = useNavigate();
  const files = useFileStore((state) => state.items);
  const unreadCount = useNotificationStore((state) => state.unreadCount);

  // Update recent files in tray
  const updateRecentFiles = useCallback(async () => {
    try {
      // Get 5 most recently modified files
      const recentFiles: RecentFile[] = files
        .filter((f) => f.item_type === 'file')
        .sort((a, b) => new Date(b.updated_at).getTime() - new Date(a.updated_at).getTime())
        .slice(0, 5)
        .map((f) => ({
          id: f.id,
          name: f.name,
          path: null,
        }));

      await invoke('tray_set_recent_files', { files: recentFiles });
    } catch (err) {
      console.error('Failed to update tray recent files:', err);
    }
  }, [files]);

  // Update notification count in tray
  const updateNotificationCount = useCallback(async () => {
    try {
      await invoke('tray_set_notification_count', { count: unreadCount });
    } catch (err) {
      console.error('Failed to update tray notification count:', err);
    }
  }, [unreadCount]);

  // Update sync status in tray
  const setSyncStatus = useCallback(async (status: SyncStatus) => {
    try {
      await invoke('tray_set_sync_status', { status });
    } catch (err) {
      console.error('Failed to update tray sync status:', err);
    }
  }, []);

  // Set syncing status helper
  const setSyncing = useCallback(
    (progress: number, fileName?: string) => {
      setSyncStatus({ Syncing: { progress, file_name: fileName ?? null } });
    },
    [setSyncStatus]
  );

  // Set idle status helper
  const setIdle = useCallback(() => {
    setSyncStatus({ Idle: null });
  }, [setSyncStatus]);

  // Set error status helper
  const setSyncError = useCallback(
    (message: string) => {
      setSyncStatus({ Error: message });
    },
    [setSyncStatus]
  );

  // Sync files and notifications to tray when they change
  useEffect(() => {
    updateRecentFiles();
  }, [updateRecentFiles]);

  useEffect(() => {
    updateNotificationCount();
  }, [updateNotificationCount]);

  // Listen to tray events from backend
  useEffect(() => {
    const listeners: UnlistenFn[] = [];

    const setupListeners = async () => {
      // Handle navigation requests from tray
      const unlistenNavigate = await listen<string>('tray://navigate', (event) => {
        const path = event.payload;
        navigate(path);
      });
      listeners.push(unlistenNavigate);

      // Handle quick upload request
      const unlistenUpload = await listen('tray://quick-upload', async () => {
        // Navigate to files and trigger upload dialog
        navigate('/files');
        // Small delay to ensure page is loaded, then emit upload trigger
        setTimeout(() => {
          window.dispatchEvent(new CustomEvent('tray-quick-upload'));
        }, 100);
      });
      listeners.push(unlistenUpload);

      // Handle open file request
      const unlistenOpenFile = await listen<string>('tray://open-file', (event) => {
        const fileId = event.payload;
        navigate(`/files/preview/${fileId}`);
      });
      listeners.push(unlistenOpenFile);
    };

    setupListeners();

    return () => {
      listeners.forEach((unlisten) => unlisten());
    };
  }, [navigate]);

  return {
    setSyncing,
    setIdle,
    setSyncError,
    updateRecentFiles,
    updateNotificationCount,
  };
}

/**
 * Hook to listen for tray quick upload event
 */
export function useTrayQuickUpload(onUpload: () => void) {
  useEffect(() => {
    const handler = () => onUpload();
    window.addEventListener('tray-quick-upload', handler);
    return () => window.removeEventListener('tray-quick-upload', handler);
  }, [onUpload]);
}
