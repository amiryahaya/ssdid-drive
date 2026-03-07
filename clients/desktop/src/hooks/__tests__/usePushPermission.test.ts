import { describe, it, expect, vi, beforeEach, afterEach } from 'vitest';
import { renderHook, act } from '@testing-library/react';
import { usePushPermission } from '../usePushPermission';

// Mock the onesignal service
vi.mock('@/services/onesignal', () => ({
  requestPermission: vi.fn(),
  isPushEnabled: vi.fn(),
}));

import { requestPermission, isPushEnabled } from '@/services/onesignal';

const mockRequestPermission = vi.mocked(requestPermission);
const mockIsPushEnabled = vi.mocked(isPushEnabled);

describe('usePushPermission', () => {
  let originalNotification: typeof Notification | undefined;

  beforeEach(() => {
    vi.useFakeTimers();
    vi.clearAllMocks();

    // Store original Notification
    originalNotification = window.Notification;

    // Default mocks - resolve immediately
    mockIsPushEnabled.mockResolvedValue(true);
    mockRequestPermission.mockResolvedValue(true);
  });

  afterEach(() => {
    vi.useRealTimers();
    vi.restoreAllMocks();

    // Restore original Notification
    if (originalNotification) {
      Object.defineProperty(window, 'Notification', {
        configurable: true,
        writable: true,
        value: originalNotification,
      });
    }
  });

  // Helper to mock Notification API
  function mockNotificationAPI(permission: NotificationPermission) {
    Object.defineProperty(window, 'Notification', {
      configurable: true,
      writable: true,
      value: {
        permission,
        requestPermission: vi.fn().mockResolvedValue(permission),
      },
    });
  }

  // Helper to remove Notification API (unsupported)
  function removeNotificationAPI() {
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    delete (window as any).Notification;
  }

  // Helper to wait for initial load to complete
  async function waitForInitialLoad() {
    // Flush promises without advancing interval timers
    await act(async () => {
      // Flush microtasks/promises
      await Promise.resolve();
      await Promise.resolve();
    });
  }

  describe('initial state', () => {
    it('should return isLoading as true initially', async () => {
      mockNotificationAPI('default');
      const { result } = renderHook(() => usePushPermission());

      // Initial state before any async operations
      expect(result.current.isLoading).toBe(true);

      // Cleanup
      await waitForInitialLoad();
    });

    it('should return status as default initially', async () => {
      mockNotificationAPI('default');
      const { result } = renderHook(() => usePushPermission());

      expect(result.current.status).toBe('default');

      // Cleanup
      await waitForInitialLoad();
    });

    it('should provide requestPermission function', async () => {
      mockNotificationAPI('default');
      const { result } = renderHook(() => usePushPermission());

      expect(typeof result.current.requestPermission).toBe('function');

      // Cleanup
      await waitForInitialLoad();
    });

    it('should provide refreshStatus function', async () => {
      mockNotificationAPI('default');
      const { result } = renderHook(() => usePushPermission());

      expect(typeof result.current.refreshStatus).toBe('function');

      // Cleanup
      await waitForInitialLoad();
    });
  });

  describe('unsupported notifications', () => {
    it('should set status to unsupported when Notification API is not available', async () => {
      removeNotificationAPI();
      const { result } = renderHook(() => usePushPermission());

      await waitForInitialLoad();

      expect(result.current.status).toBe('unsupported');
      expect(result.current.isLoading).toBe(false);
    });

    it('should return false from requestPermission when unsupported', async () => {
      removeNotificationAPI();
      const { result } = renderHook(() => usePushPermission());

      await waitForInitialLoad();

      let permissionResult: boolean;
      await act(async () => {
        permissionResult = await result.current.requestPermission();
      });

      expect(permissionResult!).toBe(false);
    });
  });

  describe('refreshStatus', () => {
    it('should set status to granted when browser permission is granted and OneSignal is enabled', async () => {
      mockNotificationAPI('granted');
      mockIsPushEnabled.mockResolvedValue(true);

      const { result } = renderHook(() => usePushPermission());

      await waitForInitialLoad();

      expect(result.current.status).toBe('granted');
      expect(result.current.isLoading).toBe(false);
    });

    it('should set status to default when browser permission is granted but OneSignal is not enabled', async () => {
      mockNotificationAPI('granted');
      mockIsPushEnabled.mockResolvedValue(false);

      const { result } = renderHook(() => usePushPermission());

      await waitForInitialLoad();

      expect(result.current.status).toBe('default');
    });

    it('should set status to denied when browser permission is denied', async () => {
      mockNotificationAPI('denied');

      const { result } = renderHook(() => usePushPermission());

      await waitForInitialLoad();

      expect(result.current.status).toBe('denied');
      expect(result.current.isLoading).toBe(false);
    });

    it('should set status to default when browser permission is default', async () => {
      mockNotificationAPI('default');

      const { result } = renderHook(() => usePushPermission());

      await waitForInitialLoad();

      expect(result.current.status).toBe('default');
      expect(result.current.isLoading).toBe(false);
    });

    it('should set status to default on error', async () => {
      mockNotificationAPI('granted');
      mockIsPushEnabled.mockRejectedValue(new Error('OneSignal error'));

      const consoleSpy = vi.spyOn(console, 'error').mockImplementation(() => {});

      const { result } = renderHook(() => usePushPermission());

      await waitForInitialLoad();

      expect(result.current.status).toBe('default');
      expect(result.current.isLoading).toBe(false);
      expect(consoleSpy).toHaveBeenCalledWith(
        '[PushPermission] Error checking status:',
        expect.any(Error)
      );

      consoleSpy.mockRestore();
    });

    it('should call isPushEnabled to check OneSignal state', async () => {
      mockNotificationAPI('granted');

      renderHook(() => usePushPermission());

      await waitForInitialLoad();

      expect(mockIsPushEnabled).toHaveBeenCalled();
    });
  });

  describe('requestPermission', () => {
    it('should call OneSignal requestPermission', async () => {
      mockNotificationAPI('default');

      const { result } = renderHook(() => usePushPermission());

      await waitForInitialLoad();

      await act(async () => {
        await result.current.requestPermission();
      });

      expect(mockRequestPermission).toHaveBeenCalled();
    });

    it('should return true when permission is granted', async () => {
      mockNotificationAPI('default');
      mockRequestPermission.mockResolvedValue(true);

      const { result } = renderHook(() => usePushPermission());

      await waitForInitialLoad();

      let permissionResult: boolean;
      await act(async () => {
        permissionResult = await result.current.requestPermission();
      });

      expect(permissionResult!).toBe(true);
    });

    it('should return false when permission is denied', async () => {
      mockNotificationAPI('default');
      mockRequestPermission.mockResolvedValue(false);

      const { result } = renderHook(() => usePushPermission());

      await waitForInitialLoad();

      let permissionResult: boolean;
      await act(async () => {
        permissionResult = await result.current.requestPermission();
      });

      expect(permissionResult!).toBe(false);
    });

    it('should return false on error', async () => {
      mockNotificationAPI('default');
      mockRequestPermission.mockRejectedValue(new Error('Permission request failed'));

      const consoleSpy = vi.spyOn(console, 'error').mockImplementation(() => {});

      const { result } = renderHook(() => usePushPermission());

      await waitForInitialLoad();

      let permissionResult: boolean;
      await act(async () => {
        permissionResult = await result.current.requestPermission();
      });

      expect(permissionResult!).toBe(false);
      expect(consoleSpy).toHaveBeenCalledWith(
        '[PushPermission] Error requesting permission:',
        expect.any(Error)
      );

      consoleSpy.mockRestore();
    });

    it('should set isLoading to true while requesting', async () => {
      mockNotificationAPI('default');

      let resolvePermission: (value: boolean) => void;
      mockRequestPermission.mockImplementation(
        () =>
          new Promise((resolve) => {
            resolvePermission = resolve;
          })
      );

      const { result } = renderHook(() => usePushPermission());

      await waitForInitialLoad();

      expect(result.current.isLoading).toBe(false);

      // Start request but don't resolve it yet
      let requestPromise: Promise<boolean>;
      act(() => {
        requestPromise = result.current.requestPermission();
      });

      expect(result.current.isLoading).toBe(true);

      // Resolve the permission request
      await act(async () => {
        resolvePermission!(true);
        await requestPromise;
      });

      expect(result.current.isLoading).toBe(false);
    });

    it('should refresh status after requesting permission', async () => {
      mockNotificationAPI('default');

      const { result } = renderHook(() => usePushPermission());

      await waitForInitialLoad();

      // Clear previous calls
      mockIsPushEnabled.mockClear();

      await act(async () => {
        await result.current.requestPermission();
      });

      // isPushEnabled is called during refreshStatus
      expect(mockIsPushEnabled).toHaveBeenCalled();
    });
  });

  describe('polling for permission changes', () => {
    it('should detect when permission changes to granted', async () => {
      // Start with default permission
      mockNotificationAPI('default');

      const { result } = renderHook(() => usePushPermission());

      await waitForInitialLoad();

      expect(result.current.status).toBe('default');

      // Change permission to granted
      mockNotificationAPI('granted');

      // Advance timer to trigger poll (5 seconds)
      act(() => {
        vi.advanceTimersByTime(5000);
      });

      expect(result.current.status).toBe('granted');
    });

    it('should detect when permission changes to denied', async () => {
      // Start with default permission
      mockNotificationAPI('default');

      const { result } = renderHook(() => usePushPermission());

      await waitForInitialLoad();

      expect(result.current.status).toBe('default');

      // Change permission to denied
      mockNotificationAPI('denied');

      // Advance timer to trigger poll
      act(() => {
        vi.advanceTimersByTime(5000);
      });

      expect(result.current.status).toBe('denied');
    });

    it('should not change status if permission remains the same', async () => {
      mockNotificationAPI('default');

      const { result } = renderHook(() => usePushPermission());

      await waitForInitialLoad();

      const initialStatus = result.current.status;

      // Advance timer to trigger poll
      act(() => {
        vi.advanceTimersByTime(5000);
      });

      expect(result.current.status).toBe(initialStatus);
    });

    it('should clear interval on unmount', async () => {
      mockNotificationAPI('default');
      const clearIntervalSpy = vi.spyOn(global, 'clearInterval');

      const { unmount } = renderHook(() => usePushPermission());

      await waitForInitialLoad();

      unmount();

      expect(clearIntervalSpy).toHaveBeenCalled();
    });

    it('should not start polling when notifications are unsupported', async () => {
      removeNotificationAPI();
      const setIntervalSpy = vi.spyOn(global, 'setInterval');

      // Clear any previous calls
      setIntervalSpy.mockClear();

      renderHook(() => usePushPermission());

      await waitForInitialLoad();

      // Should not have set up any polling intervals
      const pollCalls = setIntervalSpy.mock.calls.filter(
        (call) => typeof call[1] === 'number' && call[1] === 5000
      );
      expect(pollCalls.length).toBe(0);
    });
  });

  describe('manual refresh', () => {
    it('should allow manual refresh of status', async () => {
      mockNotificationAPI('default');

      const { result } = renderHook(() => usePushPermission());

      await waitForInitialLoad();

      expect(result.current.status).toBe('default');

      // Change the browser permission
      mockNotificationAPI('granted');
      mockIsPushEnabled.mockResolvedValue(true);

      // Manually refresh
      await act(async () => {
        await result.current.refreshStatus();
      });

      expect(result.current.status).toBe('granted');
    });
  });
});
