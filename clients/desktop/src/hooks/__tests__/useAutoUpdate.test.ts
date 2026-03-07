import { describe, it, expect, vi, beforeEach, afterEach } from 'vitest';
import { renderHook, act } from '@testing-library/react';
import { useAutoUpdate } from '../useAutoUpdate';

const mockCheck = vi.fn();
const mockRelaunch = vi.fn();

vi.mock('@tauri-apps/plugin-updater', () => ({
  check: (...args: unknown[]) => mockCheck(...args),
}));

vi.mock('@tauri-apps/plugin-process', () => ({
  relaunch: (...args: unknown[]) => mockRelaunch(...args),
}));

describe('useAutoUpdate', () => {
  beforeEach(() => {
    vi.useFakeTimers();
    vi.clearAllMocks();
    mockCheck.mockResolvedValue(null); // No update available by default
  });

  afterEach(() => {
    vi.useRealTimers();
    vi.restoreAllMocks();
  });

  describe('initial state', () => {
    it('should start with no update available', () => {
      const { result } = renderHook(() => useAutoUpdate());

      expect(result.current.updateAvailable).toBe(false);
      expect(result.current.version).toBeNull();
      expect(result.current.isUpdating).toBe(false);
      expect(result.current.error).toBeNull();
    });
  });

  describe('checkForUpdate', () => {
    it('should detect available update', async () => {
      mockCheck.mockResolvedValue({
        version: '2.0.0',
        body: 'New features and bug fixes',
        downloadAndInstall: vi.fn(),
      });

      const { result } = renderHook(() => useAutoUpdate());

      await act(async () => {
        await result.current.checkForUpdate();
      });

      expect(result.current.updateAvailable).toBe(true);
      expect(result.current.version).toBe('2.0.0');
      expect(result.current.body).toBe('New features and bug fixes');
    });

    it('should handle no update available', async () => {
      mockCheck.mockResolvedValue(null);

      const { result } = renderHook(() => useAutoUpdate());

      await act(async () => {
        await result.current.checkForUpdate();
      });

      expect(result.current.updateAvailable).toBe(false);
      expect(result.current.version).toBeNull();
    });

    it('should handle check failure', async () => {
      mockCheck.mockRejectedValue(new Error('Network error'));

      const { result } = renderHook(() => useAutoUpdate());

      await act(async () => {
        await result.current.checkForUpdate();
      });

      expect(result.current.error).toBeTruthy();
      expect(result.current.updateAvailable).toBe(false);
    });
  });

  describe('auto-check on mount', () => {
    it('should check for updates after initial delay', async () => {
      renderHook(() => useAutoUpdate());

      // Advance past the 5-second initial delay
      await act(async () => {
        vi.advanceTimersByTime(6_000);
      });

      expect(mockCheck).toHaveBeenCalled();
    });
  });

  describe('dismiss', () => {
    it('should clear update notification', async () => {
      mockCheck.mockResolvedValue({
        version: '2.0.0',
        body: 'Updates',
        downloadAndInstall: vi.fn(),
      });

      const { result } = renderHook(() => useAutoUpdate());

      await act(async () => {
        await result.current.checkForUpdate();
      });

      expect(result.current.updateAvailable).toBe(true);

      act(() => {
        result.current.dismiss();
      });

      expect(result.current.updateAvailable).toBe(false);
    });
  });

  describe('installUpdate', () => {
    it('should download and install update', async () => {
      const mockDownloadAndInstall = vi.fn().mockResolvedValue(undefined);
      mockCheck.mockResolvedValue({
        version: '2.0.0',
        body: 'Updates',
        downloadAndInstall: mockDownloadAndInstall,
      });

      const { result } = renderHook(() => useAutoUpdate());

      await act(async () => {
        await result.current.checkForUpdate();
      });

      await act(async () => {
        await result.current.installUpdate();
      });

      expect(mockDownloadAndInstall).toHaveBeenCalled();
      expect(mockRelaunch).toHaveBeenCalled();
    });
  });
});
