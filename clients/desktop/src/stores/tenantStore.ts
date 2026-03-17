import { create } from 'zustand';
import { persist } from 'zustand/middleware';
import { invoke } from '@tauri-apps/api/core';
import { useFileStore } from './fileStore';
import { useAuthStore } from './authStore';

export type TenantRole = 'owner' | 'admin' | 'member';
export type MemberStatus = 'active' | 'pending' | 'inactive';

export interface Tenant {
  id: string;
  name: string;
  slug: string;
  role: TenantRole;
  joined_at: string;
}

export interface TenantConfig {
  id: string;
  name: string;
  slug: string;
  pqc_algorithm: string;
  plan: string;
  settings: TenantSettings;
}

export interface TenantSettings {
  max_file_size_bytes?: number;
  storage_quota_bytes?: number;
  allow_external_sharing: boolean;
}

export interface TenantMember {
  id: string;
  user_id: string;
  email: string;
  name: string | null;
  role: TenantRole;
  status: MemberStatus;
  joined_at: string;
}

export interface TenantInvitation {
  id: string;
  tenant_id: string;
  tenant_name: string;
  invited_by: string;
  role: TenantRole;
  created_at: string;
  expires_at: string | null;
}

interface TenantListResponse {
  tenants: Tenant[];
  current_tenant_id: string;
}

interface TenantSwitchResponse {
  tenant: Tenant;
  session_token: string;
}

interface TenantState {
  // State
  currentTenantId: string | null;
  currentTenant: Tenant | null;
  availableTenants: Tenant[];
  tenantConfig: TenantConfig | null;
  pendingInvitations: TenantInvitation[];
  isLoading: boolean;
  isSwitching: boolean;
  error: string | null;

  // Computed
  isMultiTenant: boolean;
  currentRole: TenantRole | null;
  canManageMembers: boolean;
  canManageTenant: boolean;

  // Actions
  loadTenants: () => Promise<void>;
  switchTenant: (tenantId: string) => Promise<void>;
  loadTenantConfig: () => Promise<void>;
  leaveTenant: (tenantId: string) => Promise<void>;
  loadInvitations: () => Promise<void>;
  acceptInvitation: (invitationId: string) => Promise<Tenant>;
  declineInvitation: (invitationId: string) => Promise<void>;
  clearError: () => void;
  reset: () => void;
}

export const useTenantStore = create<TenantState>()(
  persist(
    (set, get) => ({
      // Initial state
      currentTenantId: null,
      currentTenant: null,
      availableTenants: [],
      tenantConfig: null,
      pendingInvitations: [],
      isLoading: false,
      isSwitching: false,
      error: null,

      // Computed properties (as getters via get())
      get isMultiTenant() {
        return get().availableTenants.length > 1;
      },

      get currentRole() {
        return get().currentTenant?.role ?? null;
      },

      get canManageMembers() {
        const role = get().currentTenant?.role;
        return role === 'owner' || role === 'admin';
      },

      get canManageTenant() {
        return get().currentTenant?.role === 'owner';
      },

      // Actions
      loadTenants: async () => {
        set({ isLoading: true, error: null });
        try {
          const response = await invoke<TenantListResponse>('list_tenants');
          const currentTenant =
            response.tenants.find((t) => t.id === response.current_tenant_id) ?? null;

          set({
            availableTenants: response.tenants,
            currentTenantId: response.current_tenant_id,
            currentTenant,
            isLoading: false,
          });
        } catch (error) {
          const message = error instanceof Error ? error.message : String(error);
          set({ error: message, isLoading: false });
        }
      },

      switchTenant: async (tenantId) => {
        // Guard: block switch if uploads are active
        const fileStore = useFileStore.getState();
        const activeUploads = [...fileStore.uploadProgress.values()].filter(
          (u) => u.phase !== 'complete' && u.phase !== 'error'
        );
        if (activeUploads.length > 0) {
          set({ error: 'Cannot switch tenant while uploads are in progress.' });
          return;
        }

        set({ isSwitching: true, error: null });
        try {
          const response = await invoke<TenantSwitchResponse>('switch_tenant', { tenantId });

          // Save the new session token before reloading
          await useAuthStore.getState().loginWithSession(response.session_token);

          // Reload to clear all in-memory state
          window.location.reload();
        } catch (error) {
          const message = error instanceof Error ? error.message : String(error);
          set({ error: message, isSwitching: false });
          throw error;
        }
      },

      loadTenantConfig: async () => {
        try {
          const config = await invoke<TenantConfig>('get_tenant_config');
          set({ tenantConfig: config });
        } catch (error) {
          console.error('Failed to load tenant config:', error);
        }
      },

      leaveTenant: async (tenantId) => {
        set({ isLoading: true, error: null });
        try {
          await invoke('leave_tenant', { tenantId });

          // Remove from available tenants
          const availableTenants = get().availableTenants.filter((t) => t.id !== tenantId);
          set({ availableTenants, isLoading: false });
        } catch (error) {
          const message = error instanceof Error ? error.message : String(error);
          set({ error: message, isLoading: false });
          throw error;
        }
      },

      loadInvitations: async () => {
        try {
          const invitations = await invoke<TenantInvitation[]>('get_tenant_invitations');
          set({ pendingInvitations: invitations });
        } catch (error) {
          console.error('Failed to load invitations:', error);
        }
      },

      acceptInvitation: async (invitationId) => {
        set({ isLoading: true, error: null });
        try {
          const tenant = await invoke<Tenant>('accept_tenant_invitation', { invitationId });

          // Add to available tenants and remove from invitations
          const availableTenants = [...get().availableTenants, tenant];
          const pendingInvitations = get().pendingInvitations.filter(
            (i) => i.id !== invitationId
          );

          set({ availableTenants, pendingInvitations, isLoading: false });
          return tenant;
        } catch (error) {
          const message = error instanceof Error ? error.message : String(error);
          set({ error: message, isLoading: false });
          throw error;
        }
      },

      declineInvitation: async (invitationId) => {
        set({ isLoading: true, error: null });
        try {
          await invoke('decline_tenant_invitation', { invitationId });

          // Remove from invitations
          const pendingInvitations = get().pendingInvitations.filter(
            (i) => i.id !== invitationId
          );
          set({ pendingInvitations, isLoading: false });
        } catch (error) {
          const message = error instanceof Error ? error.message : String(error);
          set({ error: message, isLoading: false });
          throw error;
        }
      },

      clearError: () => set({ error: null }),

      reset: () =>
        set({
          currentTenantId: null,
          currentTenant: null,
          availableTenants: [],
          tenantConfig: null,
          pendingInvitations: [],
          isLoading: false,
          isSwitching: false,
          error: null,
        }),
    }),
    {
      name: 'tenant-storage',
      partialize: (state) => ({
        currentTenantId: state.currentTenantId,
      }),
    }
  )
);
