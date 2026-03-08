import { describe, it, expect, vi, beforeEach, afterEach } from 'vitest';
import { renderHook, act } from '@testing-library/react';
import { useSync } from '../useSync';
import { invoke } from '@tauri-apps/api/core';

vi.mock('@tauri-apps/api/core');

const mockInvoke = vi.mocked(invoke);

const mockSyncState = {
  status: { status: 'Idle' as const },
  is_online: true,
  pending_count: 0,
};

describe('useSync', () => {
  beforeEach(() => {
    vi.useFakeTimers();
    vi.clearAllMocks();
    mockInvoke.mockResolvedValue(mockSyncState);
  });

  afterEach(() => {
    vi.useRealTimers();
    vi.restoreAllMocks();
  });

  describe('initial state', () => {
    it('should start online', () => {
      const { result } = renderHook(() => useSync());
      expect(result.current.isOnline).toBe(true);
    });

    it('should start not syncing', () => {
      const { result } = renderHook(() => useSync());
      expect(result.current.isSyncing).toBe(false);
    });

    it('should have no pending changes initially', () => {
      const { result } = renderHook(() => useSync());
      expect(result.current.pendingCount).toBe(0);
    });
  });

  describe('triggerSync', () => {
    it('should invoke trigger_sync command', async () => {
      const { result } = renderHook(() => useSync());

      await act(async () => {
        await result.current.triggerSync();
      });

      expect(mockInvoke).toHaveBeenCalledWith('trigger_sync');
    });
  });

  describe('clearSyncQueue', () => {
    it('should invoke clear_sync_queue command', async () => {
      const { result } = renderHook(() => useSync());

      await act(async () => {
        await result.current.clearSyncQueue();
      });

      expect(mockInvoke).toHaveBeenCalledWith('clear_sync_queue');
    });
  });

  describe('refreshStatus', () => {
    it('should fetch sync status from backend', async () => {
      const { result } = renderHook(() => useSync());

      await act(async () => {
        await result.current.refreshStatus();
      });

      expect(mockInvoke).toHaveBeenCalledWith('get_sync_status');
    });
  });

  describe('setOnlineStatus', () => {
    it('should invoke set_online_status with online flag', async () => {
      const { result } = renderHook(() => useSync());

      await act(async () => {
        await result.current.setOnlineStatus(false);
      });

      expect(mockInvoke).toHaveBeenCalledWith('set_online_status', { online: false });
    });
  });

  describe('sync state with syncing status', () => {
    it('should detect syncing state', async () => {
      mockInvoke.mockResolvedValue({
        status: { status: 'Syncing', data: { progress: 50, message: 'Uploading...' } },
        is_online: true,
        pending_count: 3,
      });

      const { result } = renderHook(() => useSync());

      await act(async () => {
        await result.current.refreshStatus();
      });

      expect(result.current.isSyncing).toBe(true);
      expect(result.current.pendingCount).toBe(3);
    });

    it('should expose sync progress and message when syncing', async () => {
      mockInvoke.mockResolvedValue({
        status: { status: 'Syncing', data: { progress: 75, message: 'Downloading...' } },
        is_online: true,
        pending_count: 1,
      });

      const { result } = renderHook(() => useSync());

      await act(async () => {
        await result.current.refreshStatus();
      });

      expect(result.current.syncProgress).toBe(75);
      expect(result.current.syncMessage).toBe('Downloading...');
    });
  });

  describe('offline state', () => {
    it('should detect offline state', async () => {
      mockInvoke.mockResolvedValue({
        status: { status: 'Offline' },
        is_online: false,
        pending_count: 2,
      });

      const { result } = renderHook(() => useSync());

      await act(async () => {
        await result.current.refreshStatus();
      });

      expect(result.current.isOnline).toBe(false);
      expect(result.current.isOffline).toBe(true);
    });
  });

  describe('error state', () => {
    it('should expose error message', async () => {
      mockInvoke.mockResolvedValue({
        status: { status: 'Error', data: { message: 'Connection lost' } },
        is_online: true,
        pending_count: 0,
      });

      const { result } = renderHook(() => useSync());

      await act(async () => {
        await result.current.refreshStatus();
      });

      expect(result.current.syncMessage).toBe('Connection lost');
    });
  });

  describe('periodic polling', () => {
    it('should poll sync status every 30 seconds', async () => {
      const { result: _result } = renderHook(() => useSync());

      // Flush initial mount effects
      await act(async () => {
        await vi.advanceTimersByTimeAsync(0);
      });

      const initialCallCount = mockInvoke.mock.calls.filter(
        (call) => call[0] === 'get_sync_status'
      ).length;

      // Advance exactly 30 seconds to trigger one interval tick
      await act(async () => {
        await vi.advanceTimersByTimeAsync(30000);
      });

      const afterOneInterval = mockInvoke.mock.calls.filter(
        (call) => call[0] === 'get_sync_status'
      ).length;

      expect(afterOneInterval).toBeGreaterThan(initialCallCount);
    });

    it('should stop polling on unmount', async () => {
      const { unmount } = renderHook(() => useSync());

      // Flush initial mount effects
      await act(async () => {
        await vi.advanceTimersByTimeAsync(0);
      });

      const callCountBeforeUnmount = mockInvoke.mock.calls.length;
      unmount();

      // Advance timers after unmount — no new calls should happen
      await act(async () => {
        vi.advanceTimersByTime(60000);
      });

      expect(mockInvoke.mock.calls.length).toBe(callCountBeforeUnmount);
    });
  });

  describe('browser online/offline events', () => {
    it('should call setOnlineStatus(false) on offline event', async () => {
      renderHook(() => useSync());

      // Flush initial effects
      await act(async () => {
        await vi.advanceTimersByTimeAsync(0);
      });

      mockInvoke.mockClear();

      // Dispatch offline event
      await act(async () => {
        window.dispatchEvent(new Event('offline'));
        await vi.advanceTimersByTimeAsync(0);
      });

      expect(mockInvoke).toHaveBeenCalledWith('set_online_status', { online: false });
    });

    it('should call setOnlineStatus(true) on online event', async () => {
      renderHook(() => useSync());

      // Flush initial effects
      await act(async () => {
        await vi.advanceTimersByTimeAsync(0);
      });

      mockInvoke.mockClear();

      // Dispatch online event
      await act(async () => {
        window.dispatchEvent(new Event('online'));
        await vi.advanceTimersByTimeAsync(0);
      });

      expect(mockInvoke).toHaveBeenCalledWith('set_online_status', { online: true });
    });

    it('should remove event listeners on unmount', async () => {
      const removeSpy = vi.spyOn(window, 'removeEventListener');
      const { unmount } = renderHook(() => useSync());

      // Flush initial effects
      await act(async () => {
        await vi.advanceTimersByTimeAsync(0);
      });

      unmount();

      const onlineRemoved = removeSpy.mock.calls.some((call) => call[0] === 'online');
      const offlineRemoved = removeSpy.mock.calls.some((call) => call[0] === 'offline');

      expect(onlineRemoved).toBe(true);
      expect(offlineRemoved).toBe(true);

      removeSpy.mockRestore();
    });
  });

  describe('derived state', () => {
    it('should report hasPendingChanges when pending_count > 0', async () => {
      mockInvoke.mockResolvedValue({
        status: { status: 'Idle' },
        is_online: true,
        pending_count: 5,
      });

      const { result } = renderHook(() => useSync());

      await act(async () => {
        await result.current.refreshStatus();
      });

      expect(result.current.hasPendingChanges).toBe(true);
      expect(result.current.pendingCount).toBe(5);
    });

    it('should report no pending changes when pending_count is 0', () => {
      const { result } = renderHook(() => useSync());
      expect(result.current.hasPendingChanges).toBe(false);
    });
  });
});
