import { create } from 'zustand';
import { persist } from 'zustand/middleware';
import { invoke } from '@tauri-apps/api/core';
import type { AuthProvider, OidcCallbackResponse } from '../types';

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
  providers: AuthProvider[];
  isLoadingProviders: boolean;

  // Actions
  login: (email: string, password: string) => Promise<void>;
  register: (email: string, password: string, name: string, invitationToken: string) => Promise<void>;
  logout: () => Promise<void>;
  checkAuth: () => Promise<void>;
  lock: () => void;
  unlock: (password: string) => Promise<void>;
  unlockWithBiometric: () => Promise<void>;
  updateLastActivity: () => void;
  clearError: () => void;
  changePassword: (currentPassword: string, newPassword: string) => Promise<void>;
  updateProfile: (name: string) => Promise<void>;
  loadDevices: () => Promise<void>;
  revokeDevice: (deviceId: string) => Promise<void>;
  loadProviders: (tenantSlug: string) => Promise<void>;
  loginWithOidc: (providerId: string) => Promise<string>;
  handleOidcCallback: (code: string, state: string) => Promise<OidcCallbackResponse>;
  loginWithPasskey: (email?: string) => Promise<void>;
}

/** Convert an ArrayBuffer to a URL-safe base64 string */
function arrayBufferToBase64(buffer: ArrayBuffer): string {
  const bytes = new Uint8Array(buffer);
  let binary = '';
  for (let i = 0; i < bytes.byteLength; i++) {
    binary += String.fromCharCode(bytes[i]);
  }
  return btoa(binary)
    .replace(/\+/g, '-')
    .replace(/\//g, '_')
    .replace(/=+$/, '');
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
      providers: [],
      isLoadingProviders: false,

      login: async (email, password) => {
        set({ isLoading: true, error: null });
        try {
          const response = await invoke<{ user: User }>('login', {
            email,
            password,
          });
          set({
            user: response.user,
            isAuthenticated: true,
            isLocked: false,
            isLoading: false,
          });
        } catch (error) {
          const message = error instanceof Error ? error.message : String(error);
          set({
            error: message,
            isLoading: false,
          });
          throw error;
        }
      },

      register: async (email, password, name, invitationToken) => {
        set({ isLoading: true, error: null });
        try {
          const response = await invoke<{ user: User }>('register', {
            email,
            password,
            name,
            invitationToken,
          });
          set({
            user: response.user,
            isAuthenticated: true,
            isLocked: false,
            isLoading: false,
          });
        } catch (error) {
          const message = error instanceof Error ? error.message : String(error);
          set({
            error: message,
            isLoading: false,
          });
          throw error;
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

      unlock: async (password) => {
        set({ isLoading: true, error: null });
        try {
          // Re-login with saved credentials
          const user = get().user;
          if (user) {
            await invoke('login', { email: user.email, password });
            set({ isLocked: false, isLoading: false });
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

      changePassword: async (currentPassword, newPassword) => {
        set({ isLoading: true, error: null });
        try {
          await invoke('change_password', {
            currentPassword,
            newPassword,
          });
          set({ isLoading: false });
        } catch (error) {
          const message = error instanceof Error ? error.message : String(error);
          set({ error: message, isLoading: false });
          throw error;
        }
      },

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
          // Refresh device list after revocation
          const devices = await invoke<Device[]>('list_devices');
          set({ devices });
        } catch (error) {
          const message = error instanceof Error ? error.message : String(error);
          set({ error: message });
          throw error;
        }
      },

      loadProviders: async (tenantSlug) => {
        set({ isLoadingProviders: true });
        try {
          const providers = await invoke<AuthProvider[]>('oidc_get_providers', {
            tenantSlug,
          });
          set({ providers, isLoadingProviders: false });
        } catch (error) {
          console.error('Failed to load providers:', error);
          set({ providers: [], isLoadingProviders: false });
        }
      },

      loginWithOidc: async (providerId) => {
        set({ isLoading: true, error: null });
        try {
          const authUrl = await invoke<string>('oidc_begin_login', {
            providerId,
          });
          set({ isLoading: false });
          return authUrl;
        } catch (error) {
          const message = error instanceof Error ? error.message : String(error);
          set({ error: message, isLoading: false });
          throw error;
        }
      },

      handleOidcCallback: async (code, oidcState) => {
        set({ isLoading: true, error: null });
        try {
          const response = await invoke<OidcCallbackResponse>(
            'oidc_handle_callback',
            { code, oidcState }
          );
          if (response.status === 'authenticated' && response.user) {
            set({
              user: response.user as unknown as User,
              isAuthenticated: true,
              isLocked: false,
              isLoading: false,
            });
          } else {
            set({ isLoading: false });
          }
          return response;
        } catch (error) {
          const message = error instanceof Error ? error.message : String(error);
          set({ error: message, isLoading: false });
          throw error;
        }
      },

      loginWithPasskey: async (email) => {
        set({ isLoading: true, error: null });
        try {
          // Step 1: Begin WebAuthn login (get challenge options)
          const beginResponse = await invoke<{
            options: Record<string, unknown>;
            challenge_id: string;
          }>('webauthn_login_begin', { email: email ?? null });

          // Step 2: Call navigator.credentials.get() in the webview
          const publicKeyOptions = beginResponse.options as PublicKeyCredentialRequestOptions;
          const credential = await navigator.credentials.get({
            publicKey: publicKeyOptions,
          }) as PublicKeyCredential;

          if (!credential) {
            throw new Error('No credential returned from WebAuthn ceremony');
          }

          // Step 3: Serialize the assertion
          const response = credential.response as AuthenticatorAssertionResponse;
          const assertion = {
            id: credential.id,
            rawId: arrayBufferToBase64(credential.rawId),
            type: credential.type,
            response: {
              authenticatorData: arrayBufferToBase64(response.authenticatorData),
              clientDataJSON: arrayBufferToBase64(response.clientDataJSON),
              signature: arrayBufferToBase64(response.signature),
              userHandle: response.userHandle
                ? arrayBufferToBase64(response.userHandle)
                : null,
            },
          };

          // Step 4: Complete login with the assertion
          const loginResponse = await invoke<{ user: User }>(
            'webauthn_login_complete',
            {
              challengeId: beginResponse.challenge_id,
              assertion,
              prfOutput: null,
            }
          );

          set({
            user: loginResponse.user,
            isAuthenticated: true,
            isLocked: false,
            isLoading: false,
          });
        } catch (error) {
          const message = error instanceof Error ? error.message : String(error);
          set({ error: message, isLoading: false });
          throw error;
        }
      },
    }),
    {
      name: 'auth-storage',
      partialize: (state) => ({
        // Only persist non-sensitive data
        isAuthenticated: state.isAuthenticated,
        user: state.user ? { id: state.user.id, email: state.user.email } : null,
      }),
    }
  )
);
