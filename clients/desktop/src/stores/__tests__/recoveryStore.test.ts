import { describe, it, expect, beforeEach, vi } from 'vitest';
import { useRecoveryStore, RecoverySetup, RecoveryRequest } from '../recoveryStore';
import { invoke } from '@tauri-apps/api/core';

vi.mock('@tauri-apps/api/core');

const mockInvoke = vi.mocked(invoke);

const mockRecoverySetup: RecoverySetup = {
  id: 'setup-1',
  threshold: 2,
  total_trustees: 3,
  trustees: [
    {
      id: 'trustee-1',
      email: 'trustee1@example.com',
      name: 'Trustee One',
      status: 'accepted',
      added_at: '2024-01-15T10:00:00Z',
    },
    {
      id: 'trustee-2',
      email: 'trustee2@example.com',
      name: 'Trustee Two',
      status: 'accepted',
      added_at: '2024-01-15T10:00:00Z',
    },
    {
      id: 'trustee-3',
      email: 'trustee3@example.com',
      name: null,
      status: 'pending',
      added_at: '2024-01-15T10:00:00Z',
    },
  ],
  created_at: '2024-01-15T10:00:00Z',
  updated_at: '2024-01-15T10:00:00Z',
};

const mockPendingRequests: RecoveryRequest[] = [
  {
    id: 'request-1',
    requester_email: 'user@example.com',
    requester_name: 'John Doe',
    status: 'pending',
    created_at: '2024-01-15T10:00:00Z',
    approvals_received: 1,
    approvals_required: 2,
  },
];

describe('recoveryStore', () => {
  beforeEach(() => {
    vi.clearAllMocks();
    // Reset store to initial state
    useRecoveryStore.setState({
      setup: null,
      pendingRequests: [],
      isLoading: false,
      isSettingUp: false,
      error: null,
    });
  });

  describe('initial state', () => {
    it('should have null setup initially', () => {
      const state = useRecoveryStore.getState();
      expect(state.setup).toBeNull();
      expect(state.pendingRequests).toEqual([]);
      expect(state.isLoading).toBe(false);
      expect(state.isSettingUp).toBe(false);
      expect(state.error).toBeNull();
    });
  });

  describe('loadRecoveryStatus', () => {
    it('should set loading state while fetching', async () => {
      mockInvoke.mockImplementation(
        () => new Promise((resolve) => setTimeout(() => resolve(mockRecoverySetup), 100))
      );

      const loadPromise = useRecoveryStore.getState().loadRecoveryStatus();

      expect(useRecoveryStore.getState().isLoading).toBe(true);
      expect(useRecoveryStore.getState().error).toBeNull();

      await loadPromise;
    });

    it('should load recovery setup successfully', async () => {
      mockInvoke.mockResolvedValueOnce(mockRecoverySetup);

      await useRecoveryStore.getState().loadRecoveryStatus();

      expect(mockInvoke).toHaveBeenCalledWith('get_recovery_setup');
      expect(useRecoveryStore.getState().setup).toEqual(mockRecoverySetup);
      expect(useRecoveryStore.getState().isLoading).toBe(false);
    });

    it('should handle no recovery setup (null)', async () => {
      mockInvoke.mockResolvedValueOnce(null);

      await useRecoveryStore.getState().loadRecoveryStatus();

      expect(useRecoveryStore.getState().setup).toBeNull();
      expect(useRecoveryStore.getState().isLoading).toBe(false);
    });

    it('should set error on failure', async () => {
      mockInvoke.mockRejectedValueOnce(new Error('Network error'));

      await useRecoveryStore.getState().loadRecoveryStatus();

      expect(useRecoveryStore.getState().error).toBe('Network error');
      expect(useRecoveryStore.getState().isLoading).toBe(false);
    });
  });

  describe('loadPendingRequests', () => {
    it('should load pending requests successfully', async () => {
      mockInvoke.mockResolvedValueOnce(mockPendingRequests);

      await useRecoveryStore.getState().loadPendingRequests();

      expect(mockInvoke).toHaveBeenCalledWith('get_pending_recovery_requests');
      expect(useRecoveryStore.getState().pendingRequests).toEqual(mockPendingRequests);
    });

    it('should handle empty pending requests', async () => {
      mockInvoke.mockResolvedValueOnce([]);

      await useRecoveryStore.getState().loadPendingRequests();

      expect(useRecoveryStore.getState().pendingRequests).toEqual([]);
    });

    it('should set error on failure', async () => {
      mockInvoke.mockRejectedValueOnce(new Error('Failed to load requests'));

      await useRecoveryStore.getState().loadPendingRequests();

      expect(useRecoveryStore.getState().error).toBe('Failed to load requests');
    });
  });

  describe('setupRecovery', () => {
    it('should set isSettingUp state while setting up', async () => {
      mockInvoke.mockImplementation((cmd) => {
        if (cmd === 'setup_recovery') {
          return new Promise((resolve) => setTimeout(() => resolve(undefined), 100));
        }
        return Promise.resolve(mockRecoverySetup);
      });

      const setupPromise = useRecoveryStore
        .getState()
        .setupRecovery(2, ['trustee1@example.com', 'trustee2@example.com']);

      expect(useRecoveryStore.getState().isSettingUp).toBe(true);
      expect(useRecoveryStore.getState().error).toBeNull();

      await setupPromise;
    });

    it('should setup recovery and reload status', async () => {
      mockInvoke
        .mockResolvedValueOnce(undefined) // setup_recovery
        .mockResolvedValueOnce(mockRecoverySetup); // get_recovery_setup

      await useRecoveryStore
        .getState()
        .setupRecovery(2, ['trustee1@example.com', 'trustee2@example.com']);

      expect(mockInvoke).toHaveBeenCalledWith('setup_recovery', {
        threshold: 2,
        trusteeEmails: ['trustee1@example.com', 'trustee2@example.com'],
      });
      expect(useRecoveryStore.getState().setup).toEqual(mockRecoverySetup);
      expect(useRecoveryStore.getState().isSettingUp).toBe(false);
    });

    it('should set error and throw on failure', async () => {
      mockInvoke.mockRejectedValueOnce(new Error('Invalid threshold'));

      await expect(
        useRecoveryStore.getState().setupRecovery(5, ['trustee@example.com'])
      ).rejects.toThrow('Invalid threshold');

      expect(useRecoveryStore.getState().error).toBe('Invalid threshold');
      expect(useRecoveryStore.getState().isSettingUp).toBe(false);
    });
  });

  describe('updateRecovery', () => {
    it('should update recovery and reload status', async () => {
      mockInvoke
        .mockResolvedValueOnce(undefined) // update_recovery
        .mockResolvedValueOnce(mockRecoverySetup); // get_recovery_setup

      await useRecoveryStore
        .getState()
        .updateRecovery(3, ['trustee1@example.com', 'trustee2@example.com', 'trustee3@example.com']);

      expect(mockInvoke).toHaveBeenCalledWith('update_recovery', {
        threshold: 3,
        trusteeEmails: ['trustee1@example.com', 'trustee2@example.com', 'trustee3@example.com'],
      });
      expect(useRecoveryStore.getState().isSettingUp).toBe(false);
    });

    it('should set error and throw on failure', async () => {
      mockInvoke.mockRejectedValueOnce(new Error('Update failed'));

      await expect(
        useRecoveryStore.getState().updateRecovery(2, ['trustee@example.com'])
      ).rejects.toThrow('Update failed');

      expect(useRecoveryStore.getState().error).toBe('Update failed');
      expect(useRecoveryStore.getState().isSettingUp).toBe(false);
    });
  });

  describe('removeRecovery', () => {
    beforeEach(() => {
      useRecoveryStore.setState({ setup: mockRecoverySetup });
    });

    it('should remove recovery and clear setup', async () => {
      mockInvoke.mockResolvedValueOnce(undefined);

      await useRecoveryStore.getState().removeRecovery();

      expect(mockInvoke).toHaveBeenCalledWith('remove_recovery');
      expect(useRecoveryStore.getState().setup).toBeNull();
      expect(useRecoveryStore.getState().isLoading).toBe(false);
    });

    it('should set error and throw on failure', async () => {
      mockInvoke.mockRejectedValueOnce(new Error('Cannot remove recovery'));

      await expect(useRecoveryStore.getState().removeRecovery()).rejects.toThrow(
        'Cannot remove recovery'
      );

      expect(useRecoveryStore.getState().error).toBe('Cannot remove recovery');
      expect(useRecoveryStore.getState().isLoading).toBe(false);
    });
  });

  describe('approveRequest', () => {
    beforeEach(() => {
      useRecoveryStore.setState({ pendingRequests: mockPendingRequests });
    });

    it('should approve request and reload pending requests', async () => {
      mockInvoke
        .mockResolvedValueOnce(undefined) // approve_recovery_request
        .mockResolvedValueOnce([]); // get_pending_recovery_requests

      await useRecoveryStore.getState().approveRequest('request-1');

      expect(mockInvoke).toHaveBeenCalledWith('approve_recovery_request', {
        requestId: 'request-1',
      });
      expect(useRecoveryStore.getState().pendingRequests).toEqual([]);
    });

    it('should set error and throw on failure', async () => {
      mockInvoke.mockRejectedValueOnce(new Error('Approval failed'));

      await expect(useRecoveryStore.getState().approveRequest('request-1')).rejects.toThrow(
        'Approval failed'
      );

      expect(useRecoveryStore.getState().error).toBe('Approval failed');
    });
  });

  describe('denyRequest', () => {
    beforeEach(() => {
      useRecoveryStore.setState({ pendingRequests: mockPendingRequests });
    });

    it('should deny request and reload pending requests', async () => {
      mockInvoke
        .mockResolvedValueOnce(undefined) // deny_recovery_request
        .mockResolvedValueOnce([]); // get_pending_recovery_requests

      await useRecoveryStore.getState().denyRequest('request-1');

      expect(mockInvoke).toHaveBeenCalledWith('deny_recovery_request', {
        requestId: 'request-1',
      });
      expect(useRecoveryStore.getState().pendingRequests).toEqual([]);
    });

    it('should set error and throw on failure', async () => {
      mockInvoke.mockRejectedValueOnce(new Error('Denial failed'));

      await expect(useRecoveryStore.getState().denyRequest('request-1')).rejects.toThrow(
        'Denial failed'
      );

      expect(useRecoveryStore.getState().error).toBe('Denial failed');
    });
  });

  describe('clearError', () => {
    it('should clear error state', () => {
      useRecoveryStore.setState({ error: 'Some error' });

      useRecoveryStore.getState().clearError();

      expect(useRecoveryStore.getState().error).toBeNull();
    });
  });
});
