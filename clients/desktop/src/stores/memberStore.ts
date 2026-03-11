import { create } from 'zustand';
import { invoke } from '@tauri-apps/api/core';
import type { TenantRole } from './tenantStore';

export interface TenantMember {
  id: string;
  user_id: string;
  did: string | null;
  email: string | null;
  name: string | null;
  role: TenantRole;
  joined_at: string;
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

interface MemberState {
  members: TenantMember[];
  isLoading: boolean;
  isUpdating: boolean;
  error: string | null;

  loadMembers: (tenantId: string) => Promise<void>;
  updateMemberRole: (tenantId: string, userId: string, role: TenantRole) => Promise<void>;
  removeMember: (tenantId: string, userId: string) => Promise<void>;
  clearError: () => void;
}

export const useMemberStore = create<MemberState>()((set, get) => ({
  members: [],
  isLoading: false,
  isUpdating: false,
  error: null,

  loadMembers: async (tenantId) => {
    set({ isLoading: true, error: null });
    try {
      const baseUrl = await getApiBaseUrl();
      const headers = await getAuthHeaders();

      const resp = await fetch(
        `${baseUrl}/api/tenants/${tenantId}/members`,
        { headers }
      );

      if (!resp.ok) {
        throw new Error(`Failed to load members (${resp.status})`);
      }

      const data: { members: TenantMember[] } = await resp.json();
      set({ members: data.members, isLoading: false });
    } catch (error) {
      const message = error instanceof Error ? error.message : String(error);
      set({ error: message, isLoading: false });
    }
  },

  updateMemberRole: async (tenantId, userId, role) => {
    set({ isUpdating: true, error: null });
    try {
      const baseUrl = await getApiBaseUrl();
      const headers = await getAuthHeaders();

      const resp = await fetch(
        `${baseUrl}/api/tenants/${tenantId}/members/${userId}`,
        {
          method: 'PUT',
          headers,
          body: JSON.stringify({ role }),
        }
      );

      if (!resp.ok) {
        const errorData = await resp.json().catch(() => null);
        throw new Error(
          errorData?.detail ?? `Failed to update role (${resp.status})`
        );
      }

      // Update local state
      const members = get().members.map((m) =>
        m.user_id === userId ? { ...m, role } : m
      );
      set({ members, isUpdating: false });
    } catch (error) {
      const message = error instanceof Error ? error.message : String(error);
      set({ error: message, isUpdating: false });
      throw error;
    }
  },

  removeMember: async (tenantId, userId) => {
    set({ isUpdating: true, error: null });
    try {
      const baseUrl = await getApiBaseUrl();
      const headers = await getAuthHeaders();

      const resp = await fetch(
        `${baseUrl}/api/tenants/${tenantId}/members/${userId}`,
        {
          method: 'DELETE',
          headers,
        }
      );

      if (!resp.ok) {
        const errorData = await resp.json().catch(() => null);
        throw new Error(
          errorData?.detail ?? `Failed to remove member (${resp.status})`
        );
      }

      // Remove from local state
      const members = get().members.filter((m) => m.user_id !== userId);
      set({ members, isUpdating: false });
    } catch (error) {
      const message = error instanceof Error ? error.message : String(error);
      set({ error: message, isUpdating: false });
      throw error;
    }
  },

  clearError: () => set({ error: null }),
}));
