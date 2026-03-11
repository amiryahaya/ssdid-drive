import { describe, it, expect, beforeEach, vi, type Mock } from 'vitest';
import { useInvitationStore } from '../invitationStore';
import { useAuthStore } from '../authStore';
import { invoke } from '@tauri-apps/api/core';
import type { ReceivedInvitation, SentInvitation } from '../invitationStore';

vi.mock('@tauri-apps/api/core');

const mockInvoke = vi.mocked(invoke);

const mockReceivedInvitations: ReceivedInvitation[] = [
  {
    id: 'inv-1',
    tenant_id: 'tenant-1',
    tenant_name: 'Acme Corp',
    invited_by: 'user-owner',
    invited_by_name: 'Owner User',
    role: 'member',
    message: 'Welcome!',
    short_code: 'ACME-1234',
    status: 'pending',
    created_at: '2024-01-15T10:00:00Z',
    expires_at: null,
  },
  {
    id: 'inv-2',
    tenant_id: 'tenant-2',
    tenant_name: 'Beta Inc',
    invited_by: 'user-admin',
    invited_by_name: null,
    role: 'admin',
    message: null,
    short_code: 'BETA-5678',
    status: 'accepted',
    created_at: '2024-01-10T08:00:00Z',
    expires_at: '2024-12-31T23:59:59Z',
  },
];

const mockSentInvitations: SentInvitation[] = [
  {
    id: 'sinv-1',
    tenant_id: 'tenant-1',
    tenant_name: 'Acme Corp',
    email: 'invitee@example.com',
    role: 'member',
    message: 'Join us!',
    short_code: 'ACME-AAAA',
    status: 'pending',
    created_at: '2024-01-15T10:00:00Z',
    expires_at: null,
  },
  {
    id: 'sinv-2',
    tenant_id: 'tenant-1',
    tenant_name: 'Acme Corp',
    email: null,
    role: 'admin',
    message: null,
    short_code: 'ACME-BBBB',
    status: 'revoked',
    created_at: '2024-01-10T08:00:00Z',
    expires_at: null,
  },
];

function mockFetchSuccess(data: unknown) {
  (global.fetch as Mock).mockResolvedValueOnce({
    ok: true,
    status: 200,
    json: () => Promise.resolve(data),
  });
}

function mockFetchError(status: number) {
  (global.fetch as Mock).mockResolvedValueOnce({
    ok: false,
    status,
    json: () => Promise.resolve({ detail: `Error ${status}` }),
  });
}

function resetStore() {
  useInvitationStore.setState({
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
  });
}

describe('invitationStore', () => {
  beforeEach(() => {
    vi.clearAllMocks();
    (global.fetch as Mock).mockReset();
    resetStore();

    // Default: invoke resolves for get_api_base_url and get_auth_token
    mockInvoke.mockImplementation(async (cmd: string) => {
      if (cmd === 'get_api_base_url') return { api_base_url: 'http://localhost:5147' };
      if (cmd === 'get_auth_token') return 'mock-token';
      throw new Error(`Unhandled command: ${cmd}`);
    });
  });

  describe('loadReceivedInvitations', () => {
    it('should load received invitations and set state', async () => {
      mockFetchSuccess({
        items: mockReceivedInvitations,
        total: 2,
        page: 1,
        per_page: 20,
        total_pages: 1,
      });

      await useInvitationStore.getState().loadReceivedInvitations();

      const state = useInvitationStore.getState();
      expect(state.receivedInvitations).toEqual(mockReceivedInvitations);
      expect(state.receivedTotal).toBe(2);
      expect(state.receivedPage).toBe(1);
      expect(state.receivedTotalPages).toBe(1);
      expect(state.pendingReceivedCount).toBe(1); // only inv-1 is pending
      expect(state.isLoadingReceived).toBe(false);
      expect(state.error).toBeNull();
    });

    it('should set isLoadingReceived while loading', async () => {
      (global.fetch as Mock).mockImplementation(
        () => new Promise((resolve) => setTimeout(() => resolve({
          ok: true,
          status: 200,
          json: () => Promise.resolve({ items: [], total: 0, page: 1, per_page: 20, total_pages: 1 }),
        }), 100))
      );

      const loadPromise = useInvitationStore.getState().loadReceivedInvitations();
      expect(useInvitationStore.getState().isLoadingReceived).toBe(true);

      await loadPromise;
      expect(useInvitationStore.getState().isLoadingReceived).toBe(false);
    });

    it('should set error on fetch failure', async () => {
      mockFetchError(500);

      await useInvitationStore.getState().loadReceivedInvitations();

      const state = useInvitationStore.getState();
      expect(state.error).toBe('Failed to load invitations (500)');
      expect(state.isLoadingReceived).toBe(false);
    });

    it('should pass page parameter to API', async () => {
      mockFetchSuccess({
        items: [],
        total: 0,
        page: 3,
        per_page: 20,
        total_pages: 5,
      });

      await useInvitationStore.getState().loadReceivedInvitations(3);

      expect(global.fetch).toHaveBeenCalledWith(
        expect.stringContaining('page=3'),
        expect.any(Object)
      );
    });
  });

  describe('loadSentInvitations', () => {
    it('should load sent invitations and set state', async () => {
      mockFetchSuccess({
        items: mockSentInvitations,
        total: 2,
        page: 1,
        per_page: 20,
        total_pages: 1,
      });

      await useInvitationStore.getState().loadSentInvitations();

      const state = useInvitationStore.getState();
      expect(state.sentInvitations).toEqual(mockSentInvitations);
      expect(state.sentTotal).toBe(2);
      expect(state.isLoadingSent).toBe(false);
    });

    it('should set isLoadingSent while loading', async () => {
      (global.fetch as Mock).mockImplementation(
        () => new Promise((resolve) => setTimeout(() => resolve({
          ok: true,
          status: 200,
          json: () => Promise.resolve({ items: [], total: 0, page: 1, per_page: 20, total_pages: 1 }),
        }), 100))
      );

      const loadPromise = useInvitationStore.getState().loadSentInvitations();
      expect(useInvitationStore.getState().isLoadingSent).toBe(true);

      await loadPromise;
      expect(useInvitationStore.getState().isLoadingSent).toBe(false);
    });

    it('should set error on fetch failure', async () => {
      mockFetchError(500);

      await useInvitationStore.getState().loadSentInvitations();

      expect(useInvitationStore.getState().error).toBe('Failed to load sent invitations (500)');
    });
  });

  describe('createInvitation', () => {
    it('should create invitation and return response', async () => {
      const createResponse = {
        id: 'new-inv',
        short_code: 'ACME-NEW1',
        role: 'member' as const,
        email: 'new@example.com',
        expires_at: null,
      };

      // First call: create; second call: reload sent (from the side effect)
      mockFetchSuccess(createResponse);
      mockFetchSuccess({
        items: mockSentInvitations,
        total: 2,
        page: 1,
        per_page: 20,
        total_pages: 1,
      });

      const result = await useInvitationStore.getState().createInvitation({
        email: 'new@example.com',
        role: 'member',
        message: 'Join us',
      });

      expect(result).toEqual(createResponse);
      expect(useInvitationStore.getState().isCreating).toBe(false);
    });

    it('should set isCreating while creating', async () => {
      (global.fetch as Mock).mockImplementation(
        () => new Promise((resolve) => setTimeout(() => resolve({
          ok: true,
          status: 200,
          json: () => Promise.resolve({
            id: 'new-inv',
            short_code: 'X',
            role: 'member',
            email: null,
            expires_at: null,
          }),
        }), 100))
      );

      const promise = useInvitationStore.getState().createInvitation({});
      expect(useInvitationStore.getState().isCreating).toBe(true);

      await promise;
      expect(useInvitationStore.getState().isCreating).toBe(false);
    });

    it('should set error and throw on failure', async () => {
      mockFetchError(400);

      await expect(
        useInvitationStore.getState().createInvitation({ email: 'bad' })
      ).rejects.toThrow('Error 400');

      expect(useInvitationStore.getState().error).toBe('Error 400');
      expect(useInvitationStore.getState().isCreating).toBe(false);
    });
  });

  describe('revokeInvitation', () => {
    it('should revoke and update local state optimistically', async () => {
      useInvitationStore.setState({ sentInvitations: mockSentInvitations });

      (global.fetch as Mock).mockResolvedValueOnce({
        ok: true,
        status: 200,
        json: () => Promise.resolve({}),
      });

      await useInvitationStore.getState().revokeInvitation('sinv-1');

      const updated = useInvitationStore.getState().sentInvitations;
      expect(updated.find((i) => i.id === 'sinv-1')?.status).toBe('revoked');
      // sinv-2 should be unchanged
      expect(updated.find((i) => i.id === 'sinv-2')?.status).toBe('revoked');
    });

    it('should set error and throw on failure', async () => {
      useInvitationStore.setState({ sentInvitations: mockSentInvitations });
      mockFetchError(500);

      await expect(
        useInvitationStore.getState().revokeInvitation('sinv-1')
      ).rejects.toThrow();

      expect(useInvitationStore.getState().error).toBe('Failed to revoke invitation (500)');
    });
  });

  describe('acceptInvitation', () => {
    it('should accept and update local state', async () => {
      useInvitationStore.setState({ receivedInvitations: mockReceivedInvitations });

      mockInvoke.mockImplementation(async (cmd: string) => {
        if (cmd === 'get_api_base_url') return { api_base_url: 'http://localhost:5147' };
        if (cmd === 'get_auth_token') return 'mock-token';
        if (cmd === 'accept_tenant_invitation') return undefined;
        throw new Error(`Unhandled: ${cmd}`);
      });

      await useInvitationStore.getState().acceptInvitation('inv-1');

      const state = useInvitationStore.getState();
      expect(state.receivedInvitations.find((i) => i.id === 'inv-1')?.status).toBe('accepted');
      expect(state.pendingReceivedCount).toBe(0); // no more pending
    });

    it('should set error and throw on failure', async () => {
      useInvitationStore.setState({ receivedInvitations: mockReceivedInvitations });

      mockInvoke.mockImplementation(async (cmd: string) => {
        if (cmd === 'get_api_base_url') return { api_base_url: 'http://localhost:5147' };
        if (cmd === 'get_auth_token') return 'mock-token';
        if (cmd === 'accept_tenant_invitation') throw new Error('Accept failed');
        throw new Error(`Unhandled: ${cmd}`);
      });

      await expect(
        useInvitationStore.getState().acceptInvitation('inv-1')
      ).rejects.toThrow('Accept failed');

      expect(useInvitationStore.getState().error).toBe('Accept failed');
    });
  });

  describe('declineInvitation', () => {
    it('should decline and update local state', async () => {
      useInvitationStore.setState({ receivedInvitations: mockReceivedInvitations });

      mockInvoke.mockImplementation(async (cmd: string) => {
        if (cmd === 'get_api_base_url') return { api_base_url: 'http://localhost:5147' };
        if (cmd === 'get_auth_token') return 'mock-token';
        if (cmd === 'decline_tenant_invitation') return undefined;
        throw new Error(`Unhandled: ${cmd}`);
      });

      await useInvitationStore.getState().declineInvitation('inv-1');

      const state = useInvitationStore.getState();
      expect(state.receivedInvitations.find((i) => i.id === 'inv-1')?.status).toBe('declined');
      expect(state.pendingReceivedCount).toBe(0);
    });

    it('should set error and throw on failure', async () => {
      useInvitationStore.setState({ receivedInvitations: mockReceivedInvitations });

      mockInvoke.mockImplementation(async (cmd: string) => {
        if (cmd === 'get_api_base_url') return { api_base_url: 'http://localhost:5147' };
        if (cmd === 'get_auth_token') return 'mock-token';
        if (cmd === 'decline_tenant_invitation') throw new Error('Decline failed');
        throw new Error(`Unhandled: ${cmd}`);
      });

      await expect(
        useInvitationStore.getState().declineInvitation('inv-1')
      ).rejects.toThrow('Decline failed');

      expect(useInvitationStore.getState().error).toBe('Decline failed');
    });
  });

  describe('loadPendingCount', () => {
    it('should load pending count from API', async () => {
      mockFetchSuccess({
        items: [],
        total: 5,
        page: 1,
        per_page: 1,
        total_pages: 5,
      });

      await useInvitationStore.getState().loadPendingCount();

      expect(useInvitationStore.getState().pendingReceivedCount).toBe(5);
    });

    it('should skip when no auth token is available', async () => {
      mockInvoke.mockImplementation(async (cmd: string) => {
        if (cmd === 'get_api_base_url') return { api_base_url: 'http://localhost:5147' };
        if (cmd === 'get_auth_token') throw new Error('no token');
        throw new Error(`Unhandled: ${cmd}`);
      });

      await useInvitationStore.getState().loadPendingCount();

      // fetch should not have been called because no Authorization header
      expect(global.fetch).not.toHaveBeenCalled();
    });

    it('should silently fail on error', async () => {
      (global.fetch as Mock).mockRejectedValueOnce(new Error('Network error'));

      await useInvitationStore.getState().loadPendingCount();

      // Should not throw and count stays at 0
      expect(useInvitationStore.getState().pendingReceivedCount).toBe(0);
    });
  });

  describe('401 triggers logout', () => {
    it('should trigger logout on 401 response in loadReceivedInvitations', async () => {
      const logoutSpy = vi.fn().mockResolvedValue(undefined);
      useAuthStore.setState({ logout: logoutSpy });

      (global.fetch as Mock).mockResolvedValueOnce({
        ok: false,
        status: 401,
        json: () => Promise.resolve({}),
      });

      await useInvitationStore.getState().loadReceivedInvitations();

      expect(useInvitationStore.getState().error).toBe('Session expired. Please log in again.');

      // The logout is triggered via a dynamic import, give it a tick
      await new Promise((r) => setTimeout(r, 50));
      expect(logoutSpy).toHaveBeenCalled();
    });
  });

  describe('clearError', () => {
    it('should clear error state', () => {
      useInvitationStore.setState({ error: 'Some error' });

      useInvitationStore.getState().clearError();

      expect(useInvitationStore.getState().error).toBeNull();
    });
  });
});
