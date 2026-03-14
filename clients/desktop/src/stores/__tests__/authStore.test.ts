import { describe, it, expect, beforeEach, vi } from 'vitest';
import { useAuthStore } from '../authStore';
import { invoke } from '@tauri-apps/api/core';
import { mockUser, mockAuthStatus } from '../../test/mocks/tauri';

vi.mock('@tauri-apps/api/core');

const mockInvoke = vi.mocked(invoke);

describe('authStore', () => {
  beforeEach(() => {
    vi.clearAllMocks();
    // Reset store to initial state
    useAuthStore.setState({
      user: null,
      isAuthenticated: false,
      isLoading: false,
      isLocked: true,
      error: null,
      devices: [],
      isLoadingDevices: false,
    });
  });

  describe('loginWithSession', () => {
    it('should set loading state while logging in', async () => {
      mockInvoke.mockImplementation(
        () => new Promise((resolve) => setTimeout(() => resolve({ user: mockUser }), 100))
      );

      const loginPromise = useAuthStore.getState().loginWithSession('session-token-123');

      expect(useAuthStore.getState().isLoading).toBe(true);
      expect(useAuthStore.getState().error).toBeNull();

      await loginPromise;
    });

    it('should set user and isAuthenticated on successful session login', async () => {
      mockInvoke.mockResolvedValueOnce({ user: mockUser });

      await useAuthStore.getState().loginWithSession('session-token-123');

      expect(mockInvoke).toHaveBeenCalledWith('login_with_session', {
        sessionToken: 'session-token-123',
      });
      expect(useAuthStore.getState().user).toEqual(mockUser);
      expect(useAuthStore.getState().isAuthenticated).toBe(true);
      expect(useAuthStore.getState().isLocked).toBe(false);
      expect(useAuthStore.getState().isLoading).toBe(false);
    });

    it('should set error and rethrow when login_with_session fails', async () => {
      mockInvoke.mockRejectedValueOnce(new Error('command not found'));

      await expect(
        useAuthStore.getState().loginWithSession('session-token-123')
      ).rejects.toThrow('command not found');

      expect(useAuthStore.getState().error).toBe('command not found');
      expect(useAuthStore.getState().isAuthenticated).toBe(false);
      expect(useAuthStore.getState().isLoading).toBe(false);
    });
  });

  describe('logout', () => {
    it('should clear user and authentication state', async () => {
      useAuthStore.setState({
        user: mockUser,
        isAuthenticated: true,
        isLocked: false,
      });

      mockInvoke.mockResolvedValueOnce(undefined);

      await useAuthStore.getState().logout();

      expect(mockInvoke).toHaveBeenCalledWith('logout');
      expect(useAuthStore.getState().user).toBeNull();
      expect(useAuthStore.getState().isAuthenticated).toBe(false);
      expect(useAuthStore.getState().isLocked).toBe(true);
    });

    it('should clear state even if logout API fails', async () => {
      useAuthStore.setState({
        user: mockUser,
        isAuthenticated: true,
        isLocked: false,
      });

      mockInvoke.mockRejectedValueOnce(new Error('Network error'));

      await useAuthStore.getState().logout();

      expect(useAuthStore.getState().user).toBeNull();
      expect(useAuthStore.getState().isAuthenticated).toBe(false);
    });
  });

  describe('checkAuth', () => {
    it('should restore authentication state from backend', async () => {
      mockInvoke.mockResolvedValueOnce(mockAuthStatus);

      await useAuthStore.getState().checkAuth();

      expect(mockInvoke).toHaveBeenCalledWith('check_auth_status');
      expect(useAuthStore.getState().user).toEqual(mockAuthStatus.user);
      expect(useAuthStore.getState().isAuthenticated).toBe(true);
      expect(useAuthStore.getState().isLocked).toBe(false);
      expect(useAuthStore.getState().isLoading).toBe(false);
    });

    it('should set unauthenticated state on checkAuth failure', async () => {
      mockInvoke.mockRejectedValueOnce(new Error('No session'));

      await useAuthStore.getState().checkAuth();

      expect(useAuthStore.getState().user).toBeNull();
      expect(useAuthStore.getState().isAuthenticated).toBe(false);
      expect(useAuthStore.getState().isLocked).toBe(true);
    });
  });

  describe('lock', () => {
    it('should lock when authenticated and unlocked', () => {
      useAuthStore.setState({
        isAuthenticated: true,
        isLocked: false,
      });

      useAuthStore.getState().lock();

      expect(useAuthStore.getState().isLocked).toBe(true);
    });

    it('should not lock when not authenticated', () => {
      useAuthStore.setState({
        isAuthenticated: false,
        isLocked: false,
      });

      useAuthStore.getState().lock();

      // isLocked remains false because the guard check fails
      expect(useAuthStore.getState().isLocked).toBe(false);
    });
  });

  describe('unlock', () => {
    it('should unlock when authenticated', async () => {
      useAuthStore.setState({
        user: mockUser,
        isAuthenticated: true,
        isLocked: true,
      });

      await useAuthStore.getState().unlock();

      expect(useAuthStore.getState().isLocked).toBe(false);
      expect(useAuthStore.getState().isLoading).toBe(false);
    });

    it('should throw error when not authenticated', async () => {
      useAuthStore.setState({
        user: null,
        isAuthenticated: false,
        isLocked: true,
      });

      await expect(useAuthStore.getState().unlock()).rejects.toThrow('Not authenticated');

      expect(useAuthStore.getState().error).toBe('Not authenticated');
      expect(useAuthStore.getState().isLocked).toBe(true);
    });
  });

  describe('unlockWithBiometric', () => {
    it('should unlock on successful biometric auth', async () => {
      useAuthStore.setState({
        user: mockUser,
        isAuthenticated: true,
        isLocked: true,
      });

      mockInvoke.mockResolvedValueOnce(true);

      await useAuthStore.getState().unlockWithBiometric();

      expect(mockInvoke).toHaveBeenCalledWith('unlock_with_biometric');
      expect(useAuthStore.getState().isLocked).toBe(false);
    });

    it('should set error on biometric failure', async () => {
      useAuthStore.setState({
        user: mockUser,
        isAuthenticated: true,
        isLocked: true,
      });

      mockInvoke.mockResolvedValueOnce(false);

      await expect(useAuthStore.getState().unlockWithBiometric()).rejects.toThrow(
        'Biometric unlock failed'
      );

      expect(useAuthStore.getState().error).toBe('Biometric unlock failed');
      expect(useAuthStore.getState().isLocked).toBe(true);
    });
  });

  describe('clearError', () => {
    it('should clear error state', () => {
      useAuthStore.setState({ error: 'Some error' });

      useAuthStore.getState().clearError();

      expect(useAuthStore.getState().error).toBeNull();
    });
  });

  describe('updateProfile', () => {
    it('should update user profile', async () => {
      const updatedUser = { ...mockUser, name: 'New Name' };
      mockInvoke.mockResolvedValueOnce(updatedUser);

      await useAuthStore.getState().updateProfile('New Name');

      expect(mockInvoke).toHaveBeenCalledWith('update_profile', { name: 'New Name' });
      expect(useAuthStore.getState().user).toEqual(updatedUser);
      expect(useAuthStore.getState().isLoading).toBe(false);
    });

    it('should set error on profile update failure', async () => {
      mockInvoke.mockRejectedValueOnce(new Error('Update failed'));

      await expect(useAuthStore.getState().updateProfile('New Name')).rejects.toThrow(
        'Update failed'
      );

      expect(useAuthStore.getState().error).toBe('Update failed');
      expect(useAuthStore.getState().isLoading).toBe(false);
    });
  });

  describe('loadDevices', () => {
    it('should load devices list', async () => {
      const mockDevices = [
        {
          id: 'device-1',
          name: 'MacBook Pro',
          device_type: 'desktop',
          last_active: '2024-01-15T10:00:00Z',
          created_at: '2024-01-01T00:00:00Z',
          is_current: true,
        },
      ];
      mockInvoke.mockResolvedValueOnce(mockDevices);

      await useAuthStore.getState().loadDevices();

      expect(mockInvoke).toHaveBeenCalledWith('list_devices');
      expect(useAuthStore.getState().devices).toEqual(mockDevices);
      expect(useAuthStore.getState().isLoadingDevices).toBe(false);
    });
  });

  describe('revokeDevice', () => {
    it('should revoke a device and reload device list', async () => {
      const remainingDevices = [
        {
          id: 'device-1',
          name: 'MacBook Pro',
          device_type: 'desktop',
          last_active: '2024-01-15T10:00:00Z',
          created_at: '2024-01-01T00:00:00Z',
          is_current: true,
        },
      ];
      mockInvoke
        .mockResolvedValueOnce(undefined) // revoke_device
        .mockResolvedValueOnce(remainingDevices); // list_devices

      await useAuthStore.getState().revokeDevice('device-2');

      expect(mockInvoke).toHaveBeenCalledWith('revoke_device', { deviceId: 'device-2' });
      expect(mockInvoke).toHaveBeenCalledWith('list_devices');
      expect(useAuthStore.getState().devices).toEqual(remainingDevices);
    });
  });

  describe('sendOtp', () => {
    it('should call invoke with send_otp and correct args', async () => {
      mockInvoke.mockResolvedValueOnce(undefined);

      await useAuthStore.getState().sendOtp('test@example.com');

      expect(mockInvoke).toHaveBeenCalledWith('send_otp', {
        email: 'test@example.com',
        invitationToken: null,
      });
    });

    it('should set isLoading true during call', async () => {
      mockInvoke.mockImplementation(
        () => new Promise((resolve) => setTimeout(() => resolve(undefined), 100))
      );

      const promise = useAuthStore.getState().sendOtp('test@example.com');

      expect(useAuthStore.getState().isLoading).toBe(true);
      expect(useAuthStore.getState().error).toBeNull();

      await promise;

      expect(useAuthStore.getState().isLoading).toBe(false);
    });

    it('should set error on failure and rethrow', async () => {
      mockInvoke.mockRejectedValueOnce(new Error('Rate limited'));

      await expect(
        useAuthStore.getState().sendOtp('test@example.com')
      ).rejects.toThrow('Rate limited');

      expect(useAuthStore.getState().error).toBe('Rate limited');
      expect(useAuthStore.getState().isLoading).toBe(false);
    });

    it('should pass invitationToken when provided', async () => {
      mockInvoke.mockResolvedValueOnce(undefined);

      await useAuthStore.getState().sendOtp('test@example.com', 'invite-token-123');

      expect(mockInvoke).toHaveBeenCalledWith('send_otp', {
        email: 'test@example.com',
        invitationToken: 'invite-token-123',
      });
    });
  });

  describe('verifyOtp', () => {
    it('should call invoke with verify_otp and correct args', async () => {
      mockInvoke
        .mockResolvedValueOnce({ token: 'session-token', totp_setup_required: false }) // verify_otp
        .mockResolvedValueOnce(mockAuthStatus); // check_auth_status

      await useAuthStore.getState().verifyOtp('test@example.com', '123456');

      expect(mockInvoke).toHaveBeenCalledWith('verify_otp', {
        email: 'test@example.com',
        code: '123456',
        invitationToken: null,
      });
    });

    it('should call checkAuth after success', async () => {
      mockInvoke
        .mockResolvedValueOnce({ token: 'session-token', totp_setup_required: false })
        .mockResolvedValueOnce(mockAuthStatus);

      await useAuthStore.getState().verifyOtp('test@example.com', '123456');

      expect(mockInvoke).toHaveBeenCalledWith('check_auth_status');
    });

    it('should return totpSetupRequired from response', async () => {
      mockInvoke
        .mockResolvedValueOnce({ token: 'session-token', totp_setup_required: true })
        .mockResolvedValueOnce(mockAuthStatus);

      const result = await useAuthStore.getState().verifyOtp('test@example.com', '123456');

      expect(result).toEqual({ totpSetupRequired: true });
    });

    it('should set error on failure', async () => {
      mockInvoke.mockRejectedValueOnce(new Error('Invalid OTP'));

      await expect(
        useAuthStore.getState().verifyOtp('test@example.com', '999999')
      ).rejects.toThrow('Invalid OTP');

      expect(useAuthStore.getState().error).toBe('Invalid OTP');
      expect(useAuthStore.getState().isLoading).toBe(false);
    });
  });

  describe('emailLogin', () => {
    it('should call invoke with email_login', async () => {
      mockInvoke.mockResolvedValueOnce({ requires_totp: false });

      await useAuthStore.getState().emailLogin('test@example.com');

      expect(mockInvoke).toHaveBeenCalledWith('email_login', { email: 'test@example.com' });
    });

    it('should return requiresTotp true when response indicates', async () => {
      mockInvoke.mockResolvedValueOnce({ requires_totp: true });

      const result = await useAuthStore.getState().emailLogin('test@example.com');

      expect(result).toEqual({ requiresTotp: true });
    });

    it('should return requiresTotp false when response indicates', async () => {
      mockInvoke.mockResolvedValueOnce({ requires_totp: false });

      const result = await useAuthStore.getState().emailLogin('test@example.com');

      expect(result).toEqual({ requiresTotp: false });
    });

    it('should set error on failure', async () => {
      mockInvoke.mockRejectedValueOnce(new Error('User not found'));

      await expect(
        useAuthStore.getState().emailLogin('unknown@example.com')
      ).rejects.toThrow('User not found');

      expect(useAuthStore.getState().error).toBe('User not found');
      expect(useAuthStore.getState().isLoading).toBe(false);
    });
  });

  describe('loginWithOidc', () => {
    it('should call invoke with oidc_login', async () => {
      mockInvoke.mockResolvedValueOnce(undefined);

      await useAuthStore.getState().loginWithOidc('google');

      expect(mockInvoke).toHaveBeenCalledWith('oidc_login', { provider: 'google' });
    });

    it('should set isLoading during call', async () => {
      mockInvoke.mockImplementation(
        () => new Promise((resolve) => setTimeout(() => resolve(undefined), 100))
      );

      const promise = useAuthStore.getState().loginWithOidc('microsoft');

      expect(useAuthStore.getState().isLoading).toBe(true);
      expect(useAuthStore.getState().error).toBeNull();

      await promise;

      expect(useAuthStore.getState().isLoading).toBe(false);
    });

    it('should set error on failure', async () => {
      mockInvoke.mockRejectedValueOnce(new Error('Browser open failed'));

      await expect(
        useAuthStore.getState().loginWithOidc('google')
      ).rejects.toThrow('Browser open failed');

      expect(useAuthStore.getState().error).toBe('Browser open failed');
      expect(useAuthStore.getState().isLoading).toBe(false);
    });
  });

  describe('totpVerify', () => {
    it('should call invoke with totp_verify', async () => {
      mockInvoke
        .mockResolvedValueOnce(undefined) // totp_verify
        .mockResolvedValueOnce(mockAuthStatus); // check_auth_status

      await useAuthStore.getState().totpVerify('test@example.com', '123456');

      expect(mockInvoke).toHaveBeenCalledWith('totp_verify', {
        email: 'test@example.com',
        code: '123456',
      });
    });

    it('should call checkAuth after success', async () => {
      mockInvoke
        .mockResolvedValueOnce(undefined) // totp_verify
        .mockResolvedValueOnce(mockAuthStatus); // check_auth_status

      await useAuthStore.getState().totpVerify('test@example.com', '123456');

      expect(mockInvoke).toHaveBeenCalledWith('check_auth_status');
      expect(useAuthStore.getState().isAuthenticated).toBe(true);
      expect(useAuthStore.getState().user).toEqual(mockAuthStatus.user);
    });

    it('should set error on failure', async () => {
      mockInvoke.mockRejectedValueOnce(new Error('Invalid TOTP code'));

      await expect(
        useAuthStore.getState().totpVerify('test@example.com', '000000')
      ).rejects.toThrow('Invalid TOTP code');

      expect(useAuthStore.getState().error).toBe('Invalid TOTP code');
      expect(useAuthStore.getState().isLoading).toBe(false);
    });
  });
});
