import { describe, it, expect, vi, beforeEach, afterEach } from 'vitest';
import { renderHook, act } from '@testing-library/react';
import { useBiometric } from '../useBiometric';
import { invoke } from '@tauri-apps/api/core';

vi.mock('@tauri-apps/api/core');

const mockInvoke = vi.mocked(invoke);

const mockBiometricStatus = {
  available: true,
  biometric_type: 'touchid',
  message: 'Touch ID is available',
};

describe('useBiometric', () => {
  beforeEach(() => {
    vi.clearAllMocks();
    mockInvoke.mockImplementation(async (cmd: string) => {
      switch (cmd) {
        case 'check_biometric_availability':
          return mockBiometricStatus;
        case 'is_biometric_enabled':
          return false;
        case 'set_biometric_enabled':
          return undefined;
        case 'authenticate_biometric':
          return true;
        default:
          return undefined;
      }
    });
  });

  afterEach(() => {
    vi.restoreAllMocks();
  });

  describe('initial state', () => {
    it('should start in loading state', () => {
      const { result } = renderHook(() => useBiometric());
      expect(result.current.isLoading).toBe(true);
    });

    it('should load biometric availability on mount', async () => {
      const { result } = renderHook(() => useBiometric());

      // Wait for useEffect to resolve
      await act(async () => {
        await new Promise((r) => setTimeout(r, 0));
      });

      expect(mockInvoke).toHaveBeenCalledWith('check_biometric_availability');
    });
  });

  describe('enable', () => {
    it('should call set_biometric_enabled with true', async () => {
      const { result } = renderHook(() => useBiometric());

      await act(async () => {
        await new Promise((r) => setTimeout(r, 0));
      });

      await act(async () => {
        await result.current.enable();
      });

      expect(mockInvoke).toHaveBeenCalledWith('set_biometric_enabled', { enabled: true });
    });
  });

  describe('disable', () => {
    it('should call set_biometric_enabled with false', async () => {
      const { result } = renderHook(() => useBiometric());

      await act(async () => {
        await new Promise((r) => setTimeout(r, 0));
      });

      await act(async () => {
        await result.current.disable();
      });

      expect(mockInvoke).toHaveBeenCalledWith('set_biometric_enabled', { enabled: false });
    });
  });

  describe('authenticate', () => {
    it('should call authenticate_biometric', async () => {
      const { result } = renderHook(() => useBiometric());

      await act(async () => {
        await new Promise((r) => setTimeout(r, 0));
      });

      let success = false;
      await act(async () => {
        success = await result.current.authenticate('Unlock app');
      });

      expect(mockInvoke).toHaveBeenCalledWith('authenticate_biometric', { reason: 'Unlock app' });
      expect(success).toBe(true);
    });
  });

  describe('error handling', () => {
    it('should set error when availability check fails', async () => {
      mockInvoke.mockRejectedValueOnce(new Error('Not supported'));

      const { result } = renderHook(() => useBiometric());

      await act(async () => {
        await new Promise((r) => setTimeout(r, 0));
      });

      expect(result.current.error).toBeTruthy();
    });
  });
});
