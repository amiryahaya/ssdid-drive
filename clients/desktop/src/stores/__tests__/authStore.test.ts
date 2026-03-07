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
    });
  });

  describe('login', () => {
    it('should set loading state while logging in', async () => {
      mockInvoke.mockImplementation(
        () => new Promise((resolve) => setTimeout(() => resolve({ user: mockUser }), 100))
      );

      const loginPromise = useAuthStore.getState().login('test@example.com', 'password');

      expect(useAuthStore.getState().isLoading).toBe(true);
      expect(useAuthStore.getState().error).toBeNull();

      await loginPromise;
    });

    it('should set user and isAuthenticated on successful login', async () => {
      mockInvoke.mockResolvedValueOnce({ user: mockUser });

      await useAuthStore.getState().login('test@example.com', 'password');

      expect(mockInvoke).toHaveBeenCalledWith('login', {
        email: 'test@example.com',
        password: 'password',
      });
      expect(useAuthStore.getState().user).toEqual(mockUser);
      expect(useAuthStore.getState().isAuthenticated).toBe(true);
      expect(useAuthStore.getState().isLocked).toBe(false);
      expect(useAuthStore.getState().isLoading).toBe(false);
    });

    it('should set error on login failure', async () => {
      mockInvoke.mockRejectedValueOnce(new Error('Invalid credentials'));

      await expect(
        useAuthStore.getState().login('test@example.com', 'wrong')
      ).rejects.toThrow('Invalid credentials');

      expect(useAuthStore.getState().error).toBe('Invalid credentials');
      expect(useAuthStore.getState().isLoading).toBe(false);
      expect(useAuthStore.getState().isAuthenticated).toBe(false);
    });
  });

  describe('register', () => {
    it('should set user and isAuthenticated on successful registration', async () => {
      mockInvoke.mockResolvedValueOnce({ user: mockUser });

      await useAuthStore.getState().register(
        'test@example.com',
        'password123',
        'Test User',
        'invite-token'
      );

      expect(mockInvoke).toHaveBeenCalledWith('register', {
        email: 'test@example.com',
        password: 'password123',
        name: 'Test User',
        invitationToken: 'invite-token',
      });
      expect(useAuthStore.getState().user).toEqual(mockUser);
      expect(useAuthStore.getState().isAuthenticated).toBe(true);
      expect(useAuthStore.getState().isLocked).toBe(false);
    });

    it('should set error on registration failure', async () => {
      mockInvoke.mockRejectedValueOnce(new Error('Invalid invitation token'));

      await expect(
        useAuthStore.getState().register('test@example.com', 'pass', 'Name', 'bad-token')
      ).rejects.toThrow('Invalid invitation token');

      expect(useAuthStore.getState().error).toBe('Invalid invitation token');
      expect(useAuthStore.getState().isAuthenticated).toBe(false);
    });
  });

  describe('logout', () => {
    it('should clear user and authentication state', async () => {
      // Set authenticated state first
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

  describe('unlock', () => {
    it('should unlock when password is correct', async () => {
      useAuthStore.setState({
        user: mockUser,
        isAuthenticated: true,
        isLocked: true,
      });

      mockInvoke.mockResolvedValueOnce({ user: mockUser });

      await useAuthStore.getState().unlock('password');

      expect(mockInvoke).toHaveBeenCalledWith('login', {
        email: mockUser.email,
        password: 'password',
      });
      expect(useAuthStore.getState().isLocked).toBe(false);
    });

    it('should set error on wrong password', async () => {
      useAuthStore.setState({
        user: mockUser,
        isAuthenticated: true,
        isLocked: true,
      });

      mockInvoke.mockRejectedValueOnce(new Error('Invalid password'));

      await expect(useAuthStore.getState().unlock('wrong')).rejects.toThrow(
        'Invalid password'
      );

      expect(useAuthStore.getState().error).toBe('Invalid password');
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
});
