import { useState, useEffect, useCallback } from 'react';
import { invoke } from '@tauri-apps/api/core';

/**
 * Sync status from backend
 */
export type SyncStatus =
  | { status: 'Idle' }
  | { status: 'Syncing'; data: { progress: number; message: string } }
  | { status: 'Offline' }
  | { status: 'Error'; data: { message: string } };

/**
 * Full sync state from backend
 */
interface SyncState {
  status: SyncStatus;
  is_online: boolean;
  pending_count: number;
}

/**
 * Hook for managing sync status and offline mode
 */
export function useSync() {
  const [syncState, setSyncState] = useState<SyncState>({
    status: { status: 'Idle' },
    is_online: true,
    pending_count: 0,
  });
  const [isLoading, setIsLoading] = useState(false);

  // Fetch current sync status
  const fetchSyncStatus = useCallback(async () => {
    try {
      const state = await invoke<SyncState>('get_sync_status');
      setSyncState(state);
    } catch (err) {
      console.error('Failed to fetch sync status:', err);
    }
  }, []);

  // Set online/offline status
  const setOnlineStatus = useCallback(async (online: boolean) => {
    try {
      await invoke('set_online_status', { online });
      await fetchSyncStatus();
    } catch (err) {
      console.error('Failed to set online status:', err);
    }
  }, [fetchSyncStatus]);

  // Trigger manual sync
  const triggerSync = useCallback(async () => {
    if (!syncState.is_online) {
      return;
    }

    setIsLoading(true);
    try {
      await invoke('trigger_sync');
      await fetchSyncStatus();
    } catch (err) {
      console.error('Failed to trigger sync:', err);
    } finally {
      setIsLoading(false);
    }
  }, [syncState.is_online, fetchSyncStatus]);

  // Clear pending sync queue
  const clearSyncQueue = useCallback(async () => {
    try {
      await invoke('clear_sync_queue');
      await fetchSyncStatus();
    } catch (err) {
      console.error('Failed to clear sync queue:', err);
    }
  }, [fetchSyncStatus]);

  // Detect online/offline status
  useEffect(() => {
    const handleOnline = () => setOnlineStatus(true);
    const handleOffline = () => setOnlineStatus(false);

    window.addEventListener('online', handleOnline);
    window.addEventListener('offline', handleOffline);

    // Set initial status
    setOnlineStatus(navigator.onLine);

    return () => {
      window.removeEventListener('online', handleOnline);
      window.removeEventListener('offline', handleOffline);
    };
  }, [setOnlineStatus]);

  // Poll sync status periodically
  useEffect(() => {
    fetchSyncStatus();

    const interval = setInterval(fetchSyncStatus, 30000); // Every 30 seconds

    return () => clearInterval(interval);
  }, [fetchSyncStatus]);

  // Derived state
  const isOnline = syncState.is_online;
  const isOffline = !syncState.is_online;
  const isSyncing = syncState.status.status === 'Syncing';
  const hasPendingChanges = syncState.pending_count > 0;
  const syncProgress = syncState.status.status === 'Syncing'
    ? syncState.status.data.progress
    : 0;
  const syncMessage = syncState.status.status === 'Syncing'
    ? syncState.status.data.message
    : syncState.status.status === 'Error'
    ? syncState.status.data.message
    : '';

  return {
    // State
    syncState,
    isOnline,
    isOffline,
    isSyncing,
    isLoading,
    hasPendingChanges,
    pendingCount: syncState.pending_count,
    syncProgress,
    syncMessage,

    // Actions
    setOnlineStatus,
    triggerSync,
    clearSyncQueue,
    refreshStatus: fetchSyncStatus,
  };
}
