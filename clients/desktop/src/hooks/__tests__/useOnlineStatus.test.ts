import { describe, it, expect, vi, beforeEach, afterEach } from 'vitest';
import { renderHook, act } from '@testing-library/react';
import { useOnlineStatus, isNetworkError } from '../useOnlineStatus';

describe('useOnlineStatus', () => {
  let originalNavigator: typeof navigator.onLine;
  let onlineHandlers: Array<() => void>;
  let offlineHandlers: Array<() => void>;

  beforeEach(() => {
    vi.useFakeTimers();
    originalNavigator = navigator.onLine;
    onlineHandlers = [];
    offlineHandlers = [];

    // Mock navigator.onLine
    Object.defineProperty(navigator, 'onLine', {
      configurable: true,
      get: () => true,
    });

    // Mock window event listeners
    vi.spyOn(window, 'addEventListener').mockImplementation((event, handler) => {
      if (event === 'online') {
        onlineHandlers.push(handler as () => void);
      } else if (event === 'offline') {
        offlineHandlers.push(handler as () => void);
      }
    });

    vi.spyOn(window, 'removeEventListener').mockImplementation((event, handler) => {
      if (event === 'online') {
        onlineHandlers = onlineHandlers.filter((h) => h !== handler);
      } else if (event === 'offline') {
        offlineHandlers = offlineHandlers.filter((h) => h !== handler);
      }
    });
  });

  afterEach(() => {
    vi.useRealTimers();
    vi.restoreAllMocks();
    Object.defineProperty(navigator, 'onLine', {
      configurable: true,
      get: () => originalNavigator,
    });
  });

  describe('initial state', () => {
    it('should return isOnline as true when navigator.onLine is true', () => {
      const { result } = renderHook(() => useOnlineStatus());

      expect(result.current.isOnline).toBe(true);
    });

    it('should return wasOffline as false initially', () => {
      const { result } = renderHook(() => useOnlineStatus());

      expect(result.current.wasOffline).toBe(false);
    });

    it('should return lastOnline as null initially', () => {
      const { result } = renderHook(() => useOnlineStatus());

      expect(result.current.lastOnline).toBeNull();
    });
  });

  describe('online/offline events', () => {
    it('should add event listeners on mount', () => {
      renderHook(() => useOnlineStatus());

      expect(window.addEventListener).toHaveBeenCalledWith('online', expect.any(Function));
      expect(window.addEventListener).toHaveBeenCalledWith('offline', expect.any(Function));
    });

    it('should remove event listeners on unmount', () => {
      const { unmount } = renderHook(() => useOnlineStatus());

      unmount();

      expect(window.removeEventListener).toHaveBeenCalledWith(
        'online',
        expect.any(Function)
      );
      expect(window.removeEventListener).toHaveBeenCalledWith(
        'offline',
        expect.any(Function)
      );
    });

    it('should set isOnline to false when offline event fires', () => {
      const { result } = renderHook(() => useOnlineStatus());

      act(() => {
        offlineHandlers.forEach((handler) => handler());
      });

      expect(result.current.isOnline).toBe(false);
    });

    it('should set lastOnline when going offline', () => {
      const { result } = renderHook(() => useOnlineStatus());

      act(() => {
        offlineHandlers.forEach((handler) => handler());
      });

      expect(result.current.lastOnline).toBeInstanceOf(Date);
    });

    it('should set isOnline to true when online event fires', () => {
      const { result } = renderHook(() => useOnlineStatus());

      // First go offline
      act(() => {
        offlineHandlers.forEach((handler) => handler());
      });

      expect(result.current.isOnline).toBe(false);

      // Then come back online
      act(() => {
        onlineHandlers.forEach((handler) => handler());
      });

      expect(result.current.isOnline).toBe(true);
    });
  });
});

describe('isNetworkError', () => {
  it('should return true for network-related error messages', () => {
    expect(isNetworkError(new Error('network error'))).toBe(true);
    expect(isNetworkError(new Error('fetch failed'))).toBe(true);
    expect(isNetworkError(new Error('connection refused'))).toBe(true);
    expect(isNetworkError(new Error('You are offline'))).toBe(true);
    expect(isNetworkError(new Error('request timeout'))).toBe(true);
    expect(isNetworkError(new Error('ECONNREFUSED'))).toBe(true);
  });

  it('should return false for non-network error messages', () => {
    expect(isNetworkError(new Error('Invalid input'))).toBe(false);
    expect(isNetworkError(new Error('Not found'))).toBe(false);
    expect(isNetworkError(new Error('Permission denied'))).toBe(false);
    expect(isNetworkError(new Error('Validation failed'))).toBe(false);
  });

  it('should return false for non-Error values', () => {
    expect(isNetworkError('string error')).toBe(false);
    expect(isNetworkError(null)).toBe(false);
    expect(isNetworkError(undefined)).toBe(false);
    expect(isNetworkError(123)).toBe(false);
    expect(isNetworkError({ message: 'network error' })).toBe(false);
  });

  it('should be case-insensitive', () => {
    expect(isNetworkError(new Error('NETWORK ERROR'))).toBe(true);
    expect(isNetworkError(new Error('Network Failed'))).toBe(true);
    expect(isNetworkError(new Error('CONNECTION TIMEOUT'))).toBe(true);
  });
});
