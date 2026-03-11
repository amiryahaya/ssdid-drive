import { describe, it, expect, beforeEach, vi, type Mock } from 'vitest';
import { useMemberStore } from '../memberStore';
import { useAuthStore } from '../authStore';
import { invoke } from '@tauri-apps/api/core';
import type { TenantMember } from '../memberStore';

vi.mock('@tauri-apps/api/core');

const mockInvoke = vi.mocked(invoke);

const mockMembers: TenantMember[] = [
  {
    id: 'membership-1',
    user_id: 'user-1',
    did: 'did:ssdid:user1',
    email: 'owner@example.com',
    name: 'Owner User',
    role: 'owner',
    joined_at: '2024-01-01T00:00:00Z',
  },
  {
    id: 'membership-2',
    user_id: 'user-2',
    did: 'did:ssdid:user2',
    email: 'admin@example.com',
    name: 'Admin User',
    role: 'admin',
    joined_at: '2024-01-05T00:00:00Z',
  },
  {
    id: 'membership-3',
    user_id: 'user-3',
    did: null,
    email: 'member@example.com',
    name: 'Member User',
    role: 'member',
    joined_at: '2024-01-10T00:00:00Z',
  },
];

function mockFetchSuccess(data: unknown) {
  (global.fetch as Mock).mockResolvedValueOnce({
    ok: true,
    status: 200,
    json: () => Promise.resolve(data),
  });
}

function mockFetchError(status: number, detail?: string) {
  (global.fetch as Mock).mockResolvedValueOnce({
    ok: false,
    status,
    json: () => Promise.resolve(detail ? { detail } : {}),
  });
}

function resetStore() {
  useMemberStore.setState({
    members: [],
    isLoading: false,
    isUpdating: false,
    error: null,
  });
}

describe('memberStore', () => {
  beforeEach(() => {
    vi.clearAllMocks();
    (global.fetch as Mock).mockReset();
    resetStore();

    mockInvoke.mockImplementation(async (cmd: string) => {
      if (cmd === 'get_api_base_url') return { api_base_url: 'http://localhost:5147' };
      if (cmd === 'get_auth_token') return 'mock-token';
      throw new Error(`Unhandled command: ${cmd}`);
    });
  });

  describe('loadMembers', () => {
    it('should load members and set state', async () => {
      mockFetchSuccess({ members: mockMembers });

      await useMemberStore.getState().loadMembers('tenant-1');

      const state = useMemberStore.getState();
      expect(state.members).toEqual(mockMembers);
      expect(state.isLoading).toBe(false);
      expect(state.error).toBeNull();
    });

    it('should set isLoading while loading', async () => {
      (global.fetch as Mock).mockImplementation(
        () => new Promise((resolve) => setTimeout(() => resolve({
          ok: true,
          status: 200,
          json: () => Promise.resolve({ members: [] }),
        }), 100))
      );

      const promise = useMemberStore.getState().loadMembers('tenant-1');
      expect(useMemberStore.getState().isLoading).toBe(true);

      await promise;
      expect(useMemberStore.getState().isLoading).toBe(false);
    });

    it('should call correct API endpoint with tenant ID', async () => {
      mockFetchSuccess({ members: [] });

      await useMemberStore.getState().loadMembers('tenant-42');

      expect(global.fetch).toHaveBeenCalledWith(
        'http://localhost:5147/api/tenants/tenant-42/members',
        expect.objectContaining({
          headers: expect.objectContaining({
            Authorization: 'Bearer mock-token',
          }),
        })
      );
    });

    it('should set error on fetch failure', async () => {
      mockFetchError(500);

      await useMemberStore.getState().loadMembers('tenant-1');

      const state = useMemberStore.getState();
      expect(state.error).toBe('Failed to load members (500)');
      expect(state.isLoading).toBe(false);
    });
  });

  describe('updateMemberRole', () => {
    it('should update role and update local state optimistically', async () => {
      useMemberStore.setState({ members: mockMembers });

      (global.fetch as Mock).mockResolvedValueOnce({
        ok: true,
        status: 200,
        json: () => Promise.resolve({}),
      });

      await useMemberStore.getState().updateMemberRole('tenant-1', 'user-3', 'admin');

      const state = useMemberStore.getState();
      expect(state.members.find((m) => m.user_id === 'user-3')?.role).toBe('admin');
      expect(state.isUpdating).toBe(false);
    });

    it('should set isUpdating while updating', async () => {
      useMemberStore.setState({ members: mockMembers });

      (global.fetch as Mock).mockImplementation(
        () => new Promise((resolve) => setTimeout(() => resolve({
          ok: true,
          status: 200,
          json: () => Promise.resolve({}),
        }), 100))
      );

      const promise = useMemberStore.getState().updateMemberRole('tenant-1', 'user-3', 'admin');
      expect(useMemberStore.getState().isUpdating).toBe(true);

      await promise;
      expect(useMemberStore.getState().isUpdating).toBe(false);
    });

    it('should set error and throw on failure', async () => {
      useMemberStore.setState({ members: mockMembers });
      mockFetchError(403, 'Insufficient permissions');

      await expect(
        useMemberStore.getState().updateMemberRole('tenant-1', 'user-3', 'admin')
      ).rejects.toThrow('Insufficient permissions');

      const state = useMemberStore.getState();
      expect(state.error).toBe('Insufficient permissions');
      expect(state.isUpdating).toBe(false);
    });

    it('should use generic error when detail is not available', async () => {
      useMemberStore.setState({ members: mockMembers });

      (global.fetch as Mock).mockResolvedValueOnce({
        ok: false,
        status: 500,
        json: () => Promise.reject(new Error('not json')),
      });

      await expect(
        useMemberStore.getState().updateMemberRole('tenant-1', 'user-3', 'admin')
      ).rejects.toThrow('Failed to update role (500)');
    });
  });

  describe('removeMember', () => {
    it('should remove member and update local state', async () => {
      useMemberStore.setState({ members: mockMembers });

      (global.fetch as Mock).mockResolvedValueOnce({
        ok: true,
        status: 200,
        json: () => Promise.resolve({}),
      });

      await useMemberStore.getState().removeMember('tenant-1', 'user-3');

      const state = useMemberStore.getState();
      expect(state.members).toHaveLength(2);
      expect(state.members.find((m) => m.user_id === 'user-3')).toBeUndefined();
      expect(state.isUpdating).toBe(false);
    });

    it('should set error and throw on failure', async () => {
      useMemberStore.setState({ members: mockMembers });
      mockFetchError(403, 'Cannot remove owner');

      await expect(
        useMemberStore.getState().removeMember('tenant-1', 'user-1')
      ).rejects.toThrow('Cannot remove owner');

      const state = useMemberStore.getState();
      expect(state.error).toBe('Cannot remove owner');
      expect(state.isUpdating).toBe(false);
      // Members should remain unchanged on failure
      expect(state.members).toHaveLength(3);
    });

    it('should use generic error when detail is not available', async () => {
      useMemberStore.setState({ members: mockMembers });

      (global.fetch as Mock).mockResolvedValueOnce({
        ok: false,
        status: 500,
        json: () => Promise.reject(new Error('not json')),
      });

      await expect(
        useMemberStore.getState().removeMember('tenant-1', 'user-3')
      ).rejects.toThrow('Failed to remove member (500)');
    });
  });

  describe('401 triggers logout', () => {
    it('should trigger logout on 401 response in loadMembers', async () => {
      const logoutSpy = vi.fn().mockResolvedValue(undefined);
      useAuthStore.setState({ logout: logoutSpy });

      (global.fetch as Mock).mockResolvedValueOnce({
        ok: false,
        status: 401,
        json: () => Promise.resolve({}),
      });

      await useMemberStore.getState().loadMembers('tenant-1');

      expect(useMemberStore.getState().error).toBe('Session expired. Please log in again.');

      await new Promise((r) => setTimeout(r, 50));
      expect(logoutSpy).toHaveBeenCalled();
    });
  });

  describe('clearError', () => {
    it('should clear error state', () => {
      useMemberStore.setState({ error: 'Some error' });

      useMemberStore.getState().clearError();

      expect(useMemberStore.getState().error).toBeNull();
    });
  });
});
