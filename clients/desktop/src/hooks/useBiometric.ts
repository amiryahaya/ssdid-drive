import { useState, useEffect, useCallback } from 'react';
import { invoke } from '@tauri-apps/api/core';

export type BiometricAvailability =
  | 'available'
  | 'not_configured'
  | 'not_available'
  | 'disabled_by_policy'
  | 'unknown';

export interface BiometricStatus {
  available: boolean;
  availability: BiometricAvailability;
  biometric_type: string | null;
  message: string;
}

interface UseBiometricReturn {
  /** Current biometric status */
  status: BiometricStatus | null;
  /** Whether biometric is available on this device */
  isAvailable: boolean;
  /** Whether biometric is enabled by user preference */
  isEnabled: boolean;
  /** The type of biometric (e.g., "Touch ID", "Windows Hello") */
  biometricType: string | null;
  /** Human-readable message about availability */
  message: string;
  /** Whether we're loading status */
  isLoading: boolean;
  /** Error message if any */
  error: string | null;
  /** Enable biometric authentication */
  enable: () => Promise<boolean>;
  /** Disable biometric authentication */
  disable: () => Promise<void>;
  /** Authenticate using biometric */
  authenticate: (reason?: string) => Promise<boolean>;
  /** Refresh the biometric status */
  refresh: () => Promise<void>;
}

export function useBiometric(): UseBiometricReturn {
  const [status, setStatus] = useState<BiometricStatus | null>(null);
  const [isEnabled, setIsEnabled] = useState(false);
  const [isLoading, setIsLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  const checkAvailability = useCallback(async () => {
    try {
      setIsLoading(true);
      setError(null);

      const [biometricStatus, enabled] = await Promise.all([
        invoke<BiometricStatus>('check_biometric_availability'),
        invoke<boolean>('is_biometric_enabled'),
      ]);

      setStatus(biometricStatus);
      setIsEnabled(enabled);
    } catch (err) {
      console.error('Failed to check biometric availability:', err);
      setError(err instanceof Error ? err.message : String(err));
      setStatus({
        available: false,
        availability: 'unknown',
        biometric_type: null,
        message: 'Failed to check biometric availability',
      });
    } finally {
      setIsLoading(false);
    }
  }, []);

  useEffect(() => {
    checkAvailability();
  }, [checkAvailability]);

  const enable = useCallback(async (): Promise<boolean> => {
    try {
      setError(null);
      await invoke('set_biometric_enabled', { enabled: true });
      setIsEnabled(true);
      return true;
    } catch (err) {
      const message = err instanceof Error ? err.message : String(err);
      setError(message);
      return false;
    }
  }, []);

  const disable = useCallback(async (): Promise<void> => {
    try {
      setError(null);
      await invoke('set_biometric_enabled', { enabled: false });
      setIsEnabled(false);
    } catch (err) {
      const message = err instanceof Error ? err.message : String(err);
      setError(message);
      throw err;
    }
  }, []);

  const authenticate = useCallback(async (reason = 'Authenticate'): Promise<boolean> => {
    try {
      setError(null);
      const result = await invoke<boolean>('authenticate_biometric', { reason });
      return result;
    } catch (err) {
      const message = err instanceof Error ? err.message : String(err);
      setError(message);
      return false;
    }
  }, []);

  return {
    status,
    isAvailable: status?.available ?? false,
    isEnabled,
    biometricType: status?.biometric_type ?? null,
    message: status?.message ?? 'Checking biometric availability...',
    isLoading,
    error,
    enable,
    disable,
    authenticate,
    refresh: checkAvailability,
  };
}
