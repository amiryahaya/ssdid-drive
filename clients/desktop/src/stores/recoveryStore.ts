import { create } from 'zustand';
import { invoke } from '@tauri-apps/api/core';

export type TrusteeStatus = 'pending' | 'accepted' | 'declined';

export interface Trustee {
  id: string;
  email: string;
  name: string | null;
  status: TrusteeStatus;
  added_at: string;
}

export interface RecoverySetup {
  id: string;
  threshold: number;
  total_trustees: number;
  trustees: Trustee[];
  created_at: string;
  updated_at: string;
}

export interface RecoveryRequest {
  id: string;
  requester_email: string;
  requester_name: string | null;
  status: 'pending' | 'approved' | 'denied';
  created_at: string;
  approvals_received: number;
  approvals_required: number;
}

interface RecoveryState {
  setup: RecoverySetup | null;
  pendingRequests: RecoveryRequest[];
  isLoading: boolean;
  isSettingUp: boolean;
  error: string | null;

  // Actions
  loadRecoveryStatus: () => Promise<void>;
  loadPendingRequests: () => Promise<void>;
  setupRecovery: (threshold: number, emails: string[]) => Promise<void>;
  updateRecovery: (threshold: number, emails: string[]) => Promise<void>;
  removeRecovery: () => Promise<void>;
  approveRequest: (requestId: string) => Promise<void>;
  denyRequest: (requestId: string) => Promise<void>;
  clearError: () => void;
}

export const useRecoveryStore = create<RecoveryState>((set, get) => ({
  setup: null,
  pendingRequests: [],
  isLoading: false,
  isSettingUp: false,
  error: null,

  loadRecoveryStatus: async () => {
    set({ isLoading: true, error: null });
    try {
      const setup = await invoke<RecoverySetup | null>('get_recovery_setup');
      set({ setup, isLoading: false });
    } catch (error) {
      const message = error instanceof Error ? error.message : String(error);
      set({ error: message, isLoading: false });
    }
  },

  loadPendingRequests: async () => {
    try {
      const pendingRequests = await invoke<RecoveryRequest[]>(
        'get_pending_recovery_requests'
      );
      set({ pendingRequests });
    } catch (error) {
      const message = error instanceof Error ? error.message : String(error);
      set({ error: message });
    }
  },

  setupRecovery: async (threshold, emails) => {
    set({ isSettingUp: true, error: null });
    try {
      await invoke('setup_recovery', { threshold, trusteeEmails: emails });
      await get().loadRecoveryStatus();
      set({ isSettingUp: false });
    } catch (error) {
      const message = error instanceof Error ? error.message : String(error);
      set({ error: message, isSettingUp: false });
      throw error;
    }
  },

  updateRecovery: async (threshold, emails) => {
    set({ isSettingUp: true, error: null });
    try {
      await invoke('update_recovery', { threshold, trusteeEmails: emails });
      await get().loadRecoveryStatus();
      set({ isSettingUp: false });
    } catch (error) {
      const message = error instanceof Error ? error.message : String(error);
      set({ error: message, isSettingUp: false });
      throw error;
    }
  },

  removeRecovery: async () => {
    set({ isLoading: true, error: null });
    try {
      await invoke('remove_recovery');
      set({ setup: null, isLoading: false });
    } catch (error) {
      const message = error instanceof Error ? error.message : String(error);
      set({ error: message, isLoading: false });
      throw error;
    }
  },

  approveRequest: async (requestId) => {
    try {
      await invoke('approve_recovery_request', { requestId });
      await get().loadPendingRequests();
    } catch (error) {
      const message = error instanceof Error ? error.message : String(error);
      set({ error: message });
      throw error;
    }
  },

  denyRequest: async (requestId) => {
    try {
      await invoke('deny_recovery_request', { requestId });
      await get().loadPendingRequests();
    } catch (error) {
      const message = error instanceof Error ? error.message : String(error);
      set({ error: message });
      throw error;
    }
  },

  clearError: () => set({ error: null }),
}));
