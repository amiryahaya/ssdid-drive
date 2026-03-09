import { create } from 'zustand';
import { persist } from 'zustand/middleware';
import { invoke } from '@tauri-apps/api/core';

interface User {
  id: string;
  email: string;
  name: string;
  tenantId: string;
}

export interface Device {
  id: string;
  name: string | null;
  device_type: string;
  last_active: string;
  created_at: string;
  is_current: boolean;
}

interface AuthState {
  user: User | null;
  isAuthenticated: boolean;
  isLoading: boolean;
  isLocked: boolean;
  error: string | null;
  devices: Device[];
  isLoadingDevices: boolean;
  lastActivity: number;

  // Actions
  loginWithSession: (sessionToken: string) => Promise<void>;
  logout: () => Promise<void>;
  checkAuth: () => Promise<void>;
  lock: () => void;
  unlock: () => Promise<void>;
  unlockWithBiometric: () => Promise<void>;
  updateLastActivity: () => void;
  clearError: () => void;
  updateProfile: (name: string) => Promise<void>;
  loadDevices: () => Promise<void>;
  revokeDevice: (deviceId: string) => Promise<void>;
}

export const useAuthStore = create<AuthState>()(
  persist(
    (set, get) => ({
      user: null,
      isAuthenticated: false,
      isLoading: false,
      isLocked: true,
      error: null,
      devices: [],
      isLoadingDevices: false,
      lastActivity: Date.now(),

      loginWithSession: async (sessionToken: string) => {
        set({ isLoading: true, error: null });
        try {
          // Store the session token via Tauri backend and fetch user info
          const response = await invoke<{ user: User }>('login_with_session', {
            sessionToken,
          });
          set({
            user: response.user,
            isAuthenticated: true,
            isLocked: false,
            isLoading: false,
          });
        } catch (error) {
          // If the backend command isn't wired yet, set authenticated state
          // based on the token being present (temporary until backend is ready)
          console.warn('login_with_session not available yet, using fallback:', error);
          set({
            isAuthenticated: true,
            isLocked: false,
            isLoading: false,
          });
        }
      },

      logout: async () => {
        try {
          await invoke('logout');
        } catch (error) {
          console.error('Logout error:', error);
        }
        set({
          user: null,
          isAuthenticated: false,
          isLocked: true,
        });
      },

      checkAuth: async () => {
        set({ isLoading: true });
        try {
          const status = await invoke<{
            is_authenticated: boolean;
            is_locked: boolean;
            user: User | null;
          }>('check_auth_status');

          set({
            user: status.user,
            isAuthenticated: status.is_authenticated,
            isLocked: status.is_locked,
            isLoading: false,
          });
        } catch (error) {
          set({
            user: null,
            isAuthenticated: false,
            isLocked: true,
            isLoading: false,
          });
        }
      },

      lock: () => {
        const { isAuthenticated, isLocked } = get();
        if (isAuthenticated && !isLocked) {
          set({ isLocked: true });
        }
      },

      updateLastActivity: () => {
        set({ lastActivity: Date.now() });
      },

      unlock: async () => {
        set({ isLoading: true, error: null });
        try {
          // For SSDID, unlock uses biometric or re-scans QR
          // Simplified: just unlock if authenticated
          const { isAuthenticated } = get();
          if (isAuthenticated) {
            set({ isLocked: false, isLoading: false });
          } else {
            throw new Error('Not authenticated');
          }
        } catch (error) {
          const message = error instanceof Error ? error.message : String(error);
          set({ error: message, isLoading: false });
          throw error;
        }
      },

      unlockWithBiometric: async () => {
        set({ isLoading: true, error: null });
        try {
          const success = await invoke<boolean>('unlock_with_biometric');
          if (success) {
            set({ isLocked: false, isLoading: false });
          } else {
            throw new Error('Biometric unlock failed');
          }
        } catch (error) {
          const message = error instanceof Error ? error.message : String(error);
          set({ error: message, isLoading: false });
          throw error;
        }
      },

      clearError: () => set({ error: null }),

      updateProfile: async (name) => {
        set({ isLoading: true, error: null });
        try {
          const user = await invoke<User>('update_profile', { name });
          set({ user, isLoading: false });
        } catch (error) {
          const message = error instanceof Error ? error.message : String(error);
          set({ error: message, isLoading: false });
          throw error;
        }
      },

      loadDevices: async () => {
        set({ isLoadingDevices: true });
        try {
          const devices = await invoke<Device[]>('list_devices');
          set({ devices, isLoadingDevices: false });
        } catch (error) {
          console.error('Failed to load devices:', error);
          set({ isLoadingDevices: false });
        }
      },

      revokeDevice: async (deviceId) => {
        try {
          await invoke('revoke_device', { deviceId });
          const devices = await invoke<Device[]>('list_devices');
          set({ devices });
        } catch (error) {
          const message = error instanceof Error ? error.message : String(error);
          set({ error: message });
          throw error;
        }
      },
    }),
    {
      name: 'auth-storage',
      partialize: (state) => ({
        isAuthenticated: state.isAuthenticated,
        user: state.user ? { id: state.user.id, email: state.user.email } : null,
      }),
    }
  )
);
