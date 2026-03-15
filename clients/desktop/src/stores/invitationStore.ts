import { create } from 'zustand';
import { invoke } from '@tauri-apps/api/core';
import type { TenantRole } from './tenantStore';

export type InvitationStatus = 'pending' | 'accepted' | 'declined' | 'revoked' | 'expired';

export interface ReceivedInvitation {
  id: string;
  tenant_id: string;
  tenant_name: string;
  invited_by: string;
  invited_by_name: string | null;
  role: TenantRole;
  message: string | null;
  short_code: string;
  status: InvitationStatus;
  created_at: string;
  expires_at: string | null;
}

export interface SentInvitation {
  id: string;
  tenant_id: string;
  tenant_name: string;
  email: string | null;
  role: TenantRole;
  message: string | null;
  short_code: string;
  status: InvitationStatus;
  created_at: string;
  expires_at: string | null;
}

export interface CreateInvitationRequest {
  email?: string;
  role?: TenantRole;
  message?: string;
}

export interface CreateInvitationResponse {
  id: string;
  short_code: string;
  role: TenantRole;
  email: string | null;
  expires_at: string | null;
  email_sent: boolean;
  email_error: string | null;
}

interface PaginatedResponse<T> {
  items: T[];
  total: number;
  page: number;
  per_page: number;
  total_pages: number;
}

async function getApiBaseUrl(): Promise<string> {
  try {
    const info = await invoke<{ api_base_url: string }>('get_api_base_url');
    return info.api_base_url;
  } catch {
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    return (import.meta as any).env?.VITE_API_BASE_URL ?? 'http://localhost:5147';
  }
}

async function getAuthHeaders(): Promise<Record<string, string>> {
  try {
    const token = await invoke<string>('get_auth_token');
    return {
      'Content-Type': 'application/json',
      Authorization: `Bearer ${token}`,
    };
  } catch {
    return { 'Content-Type': 'application/json' };
  }
}

function handleResponseStatus(resp: Response): void {
  if (resp.status === 401) {
    // Trigger redirect to login by clearing auth state
    // This import is safe because zustand stores are singletons
    import('@/stores/authStore').then(({ useAuthStore }) => {
      useAuthStore.getState().logout();
    });
    throw new Error('Session expired. Please log in again.');
  }
}

interface InvitationState {
  // State
  receivedInvitations: ReceivedInvitation[];
  sentInvitations: SentInvitation[];
  receivedTotal: number;
  sentTotal: number;
  receivedPage: number;
  sentPage: number;
  perPage: number;
  receivedTotalPages: number;
  sentTotalPages: number;
  pendingReceivedCount: number;
  isLoadingReceived: boolean;
  isLoadingSent: boolean;
  isCreating: boolean;
  error: string | null;

  // Actions
  loadReceivedInvitations: (page?: number) => Promise<void>;
  loadSentInvitations: (page?: number) => Promise<void>;
  createInvitation: (request: CreateInvitationRequest) => Promise<CreateInvitationResponse>;
  revokeInvitation: (invitationId: string) => Promise<void>;
  acceptInvitation: (invitationId: string) => Promise<void>;
  declineInvitation: (invitationId: string) => Promise<void>;
  loadPendingCount: () => Promise<void>;
  clearError: () => void;
}

export const useInvitationStore = create<InvitationState>()((set, get) => ({
  // Initial state
  receivedInvitations: [],
  sentInvitations: [],
  receivedTotal: 0,
  sentTotal: 0,
  receivedPage: 1,
  sentPage: 1,
  perPage: 20,
  receivedTotalPages: 1,
  sentTotalPages: 1,
  pendingReceivedCount: 0,
  isLoadingReceived: false,
  isLoadingSent: false,
  isCreating: false,
  error: null,

  loadReceivedInvitations: async (page = 1) => {
    set({ isLoadingReceived: true, error: null });
    try {
      const baseUrl = await getApiBaseUrl();
      const headers = await getAuthHeaders();
      const perPage = get().perPage;

      const resp = await fetch(
        `${baseUrl}/api/invitations?page=${page}&per_page=${perPage}`,
        { headers }
      );

      handleResponseStatus(resp);
      if (!resp.ok) {
        throw new Error(`Failed to load invitations (${resp.status})`);
      }

      const data: PaginatedResponse<ReceivedInvitation> = await resp.json();
      const pendingCount = data.items.filter((i) => i.status === 'pending').length;

      set({
        receivedInvitations: data.items,
        receivedTotal: data.total,
        receivedPage: data.page,
        receivedTotalPages: data.total_pages,
        pendingReceivedCount: pendingCount,
        isLoadingReceived: false,
      });
    } catch (error) {
      const message = error instanceof Error ? error.message : String(error);
      set({ error: message, isLoadingReceived: false });
    }
  },

  loadSentInvitations: async (page = 1) => {
    set({ isLoadingSent: true, error: null });
    try {
      const baseUrl = await getApiBaseUrl();
      const headers = await getAuthHeaders();
      const perPage = get().perPage;

      const resp = await fetch(
        `${baseUrl}/api/invitations/sent?page=${page}&per_page=${perPage}`,
        { headers }
      );

      handleResponseStatus(resp);
      if (!resp.ok) {
        throw new Error(`Failed to load sent invitations (${resp.status})`);
      }

      const data: PaginatedResponse<SentInvitation> = await resp.json();

      set({
        sentInvitations: data.items,
        sentTotal: data.total,
        sentPage: data.page,
        sentTotalPages: data.total_pages,
        isLoadingSent: false,
      });
    } catch (error) {
      const message = error instanceof Error ? error.message : String(error);
      set({ error: message, isLoadingSent: false });
    }
  },

  createInvitation: async (request) => {
    set({ isCreating: true, error: null });
    try {
      const baseUrl = await getApiBaseUrl();
      const headers = await getAuthHeaders();

      const resp = await fetch(`${baseUrl}/api/invitations`, {
        method: 'POST',
        headers,
        body: JSON.stringify(request),
      });

      handleResponseStatus(resp);
      if (!resp.ok) {
        const errorData = await resp.json().catch(() => null);
        throw new Error(
          errorData?.detail ?? `Failed to create invitation (${resp.status})`
        );
      }

      const data: CreateInvitationResponse = await resp.json();
      set({ isCreating: false });

      // Reload sent invitations to reflect the new one
      get().loadSentInvitations(get().sentPage);

      return data;
    } catch (error) {
      const message = error instanceof Error ? error.message : String(error);
      set({ error: message, isCreating: false });
      throw error;
    }
  },

  revokeInvitation: async (invitationId) => {
    set({ error: null });
    try {
      const baseUrl = await getApiBaseUrl();
      const headers = await getAuthHeaders();

      const resp = await fetch(`${baseUrl}/api/invitations/${invitationId}`, {
        method: 'DELETE',
        headers,
      });

      handleResponseStatus(resp);
      if (!resp.ok) {
        throw new Error(`Failed to revoke invitation (${resp.status})`);
      }

      // Update local state
      const sentInvitations = get().sentInvitations.map((inv) =>
        inv.id === invitationId ? { ...inv, status: 'revoked' as InvitationStatus } : inv
      );
      set({ sentInvitations });
    } catch (error) {
      const message = error instanceof Error ? error.message : String(error);
      set({ error: message });
      throw error;
    }
  },

  acceptInvitation: async (invitationId) => {
    set({ error: null });
    try {
      await invoke('accept_tenant_invitation', { invitationId });

      // Update local state
      const receivedInvitations = get().receivedInvitations.map((inv) =>
        inv.id === invitationId
          ? { ...inv, status: 'accepted' as InvitationStatus }
          : inv
      );
      const pendingCount = receivedInvitations.filter(
        (i) => i.status === 'pending'
      ).length;
      set({ receivedInvitations, pendingReceivedCount: pendingCount });
    } catch (error) {
      const message = error instanceof Error ? error.message : String(error);
      set({ error: message });
      throw error;
    }
  },

  declineInvitation: async (invitationId) => {
    set({ error: null });
    try {
      await invoke('decline_tenant_invitation', { invitationId });

      // Update local state
      const receivedInvitations = get().receivedInvitations.map((inv) =>
        inv.id === invitationId
          ? { ...inv, status: 'declined' as InvitationStatus }
          : inv
      );
      const pendingCount = receivedInvitations.filter(
        (i) => i.status === 'pending'
      ).length;
      set({ receivedInvitations, pendingReceivedCount: pendingCount });
    } catch (error) {
      const message = error instanceof Error ? error.message : String(error);
      set({ error: message });
      throw error;
    }
  },

  loadPendingCount: async () => {
    try {
      const baseUrl = await getApiBaseUrl();
      const headers = await getAuthHeaders();

      if (!headers.Authorization) {
        // No auth token — skip loading
        return;
      }

      const resp = await fetch(
        `${baseUrl}/api/invitations?page=1&per_page=1&status=pending`,
        { headers }
      );

      if (resp.ok) {
        const data: PaginatedResponse<ReceivedInvitation> = await resp.json();
        set({ pendingReceivedCount: data.total });
      }
    } catch {
      // Silently fail for badge count
    }
  },

  clearError: () => set({ error: null }),
}));
