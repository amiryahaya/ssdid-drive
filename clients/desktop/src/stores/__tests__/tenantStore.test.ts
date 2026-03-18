import { describe, it, expect, beforeEach, vi, afterEach } from 'vitest';
import { useTenantStore } from '../tenantStore';
import { useFileStore } from '../fileStore';
import { useAuthStore } from '../authStore';
import { invoke } from '@tauri-apps/api/core';

vi.mock('@tauri-apps/api/core');
vi.mock('../fileStore');
vi.mock('../authStore');

const mockInvoke = vi.mocked(invoke);

const mockLoginWithSession = vi.fn().mockResolvedValue(undefined);
const mockUseAuthStore = vi.mocked(useAuthStore);
const mockUseFileStore = vi.mocked(useFileStore);

const mockTenant = {
  id: 'tenant-1',
  name: 'Test Org',
  slug: 'test-org',
  role: 'admin' as const,
  member_count: 5,
  created_at: '2026-01-01T00:00:00Z',
};

// Tenant config shape kept for reference but not used in current tests
// const mockTenantConfig = {
//   max_file_size: 100 * 1024 * 1024,
//   max_storage: 10 * 1024 * 1024 * 1024,
//   allowed_file_types: ['*'],
//   features: { pii_detection: true, audit_log: true },
// };

describe('tenantStore', () => {
  beforeEach(() => {
    vi.clearAllMocks();
    useTenantStore.setState({
      currentTenantId: null,
      currentTenant: null,
      availableTenants: [],
      tenantConfig: null,
      pendingInvitations: [],
      isLoading: false,
      isSwitching: false,
      error: null,
    });

    // Default: no active uploads
    mockUseFileStore.getState = vi.fn().mockReturnValue({
      uploadProgress: new Map(),
    });

    // Default: loginWithSession succeeds
    mockLoginWithSession.mockResolvedValue(undefined);
    mockUseAuthStore.getState = vi.fn().mockReturnValue({
      loginWithSession: mockLoginWithSession,
    });

    // Mock window.location.reload
    Object.defineProperty(window, 'location', {
      writable: true,
      value: { ...window.location, reload: vi.fn() },
    });
  });

  afterEach(() => {
    vi.restoreAllMocks();
  });

  describe('initial state', () => {
    it('should have no current tenant', () => {
      const state = useTenantStore.getState();
      expect(state.currentTenantId).toBeNull();
      expect(state.currentTenant).toBeNull();
    });

    it('should not be loading', () => {
      expect(useTenantStore.getState().isLoading).toBe(false);
    });
  });

  describe('loadTenants', () => {
    it('should load tenants and set current tenant', async () => {
      mockInvoke.mockResolvedValueOnce({
        tenants: [mockTenant],
        current_tenant_id: 'tenant-1',
      });

      await useTenantStore.getState().loadTenants();

      const state = useTenantStore.getState();
      expect(state.availableTenants).toHaveLength(1);
      expect(state.currentTenantId).toBe('tenant-1');
      expect(state.isLoading).toBe(false);
    });

    it('should set error on failure', async () => {
      mockInvoke.mockRejectedValueOnce(new Error('Network error'));

      await useTenantStore.getState().loadTenants();

      expect(useTenantStore.getState().error).toBeTruthy();
      expect(useTenantStore.getState().isLoading).toBe(false);
    });
  });

  describe('switchTenant', () => {
    it('should invoke switch_tenant and reload on success', async () => {
      useTenantStore.setState({ availableTenants: [mockTenant] });
      mockInvoke.mockResolvedValueOnce({ tenant: mockTenant, session_token: 'new-session-tok' });

      await useTenantStore.getState().switchTenant('tenant-1');

      expect(mockInvoke).toHaveBeenCalledWith('switch_tenant', { tenantId: 'tenant-1' });
      expect(mockLoginWithSession).toHaveBeenCalledWith('new-session-tok');
      expect(window.location.reload).toHaveBeenCalled();
    });

    it('should block switch if uploads are active', async () => {
      const activeUpload = new Map([
        ['upload-1', { file_id: 'upload-1', file_name: 'test.txt', phase: 'uploading', bytes_uploaded: 100, total_bytes: 200, progress_percent: 50 }],
      ]);
      mockUseFileStore.getState = vi.fn().mockReturnValue({ uploadProgress: activeUpload });

      await useTenantStore.getState().switchTenant('tenant-1');

      expect(mockInvoke).not.toHaveBeenCalled();
      expect(useTenantStore.getState().error).toBe('Cannot switch tenant while uploads are in progress.');
    });

    it('should not block switch if all uploads are complete or errored', async () => {
      const doneUploads = new Map([
        ['upload-1', { file_id: 'upload-1', file_name: 'test.txt', phase: 'complete', bytes_uploaded: 200, total_bytes: 200, progress_percent: 100 }],
        ['upload-2', { file_id: 'upload-2', file_name: 'fail.txt', phase: 'error', bytes_uploaded: 0, total_bytes: 100, progress_percent: 0 }],
      ]);
      mockUseFileStore.getState = vi.fn().mockReturnValue({ uploadProgress: doneUploads });
      mockInvoke.mockResolvedValueOnce({ tenant: mockTenant, session_token: 'new-session-tok' });

      await useTenantStore.getState().switchTenant('tenant-1');

      expect(mockInvoke).toHaveBeenCalledWith('switch_tenant', { tenantId: 'tenant-1' });
      expect(mockLoginWithSession).toHaveBeenCalledWith('new-session-tok');
    });

    it('should set error on switch failure', async () => {
      mockInvoke.mockRejectedValueOnce(new Error('Switch failed'));

      // switchTenant rethrows, so we need to catch
      await expect(useTenantStore.getState().switchTenant('tenant-1')).rejects.toThrow('Switch failed');

      expect(useTenantStore.getState().error).toBeTruthy();
      expect(useTenantStore.getState().isSwitching).toBe(false);
    });
  });

  describe('clearError', () => {
    it('should clear the error state', () => {
      useTenantStore.setState({ error: 'some error' });
      useTenantStore.getState().clearError();
      expect(useTenantStore.getState().error).toBeNull();
    });
  });

  describe('reset', () => {
    it('should reset all state', () => {
      useTenantStore.setState({
        currentTenantId: 'tenant-1',
        currentTenant: mockTenant,
        availableTenants: [mockTenant],
        error: 'some error',
      });

      useTenantStore.getState().reset();

      const state = useTenantStore.getState();
      expect(state.currentTenantId).toBeNull();
      expect(state.currentTenant).toBeNull();
      expect(state.availableTenants).toEqual([]);
      expect(state.error).toBeNull();
    });
  });

  describe('loadTenantConfig', () => {
    it('should load tenant config successfully', async () => {
      mockInvoke.mockResolvedValueOnce({
        id: 'tenant-1',
        name: 'Test Org',
        slug: 'test-org',
        pqc_algorithm: 'ML-KEM-768',
        plan: 'enterprise',
        settings: { allow_external_sharing: true },
      });

      await useTenantStore.getState().loadTenantConfig();

      expect(mockInvoke).toHaveBeenCalledWith('get_tenant_config');
      expect(useTenantStore.getState().tenantConfig).toBeTruthy();
      expect(useTenantStore.getState().tenantConfig?.plan).toBe('enterprise');
    });

    it('should handle config load failure gracefully', async () => {
      const consoleSpy = vi.spyOn(console, 'error').mockImplementation(() => {});
      mockInvoke.mockRejectedValueOnce(new Error('Config not found'));

      await useTenantStore.getState().loadTenantConfig();

      expect(useTenantStore.getState().tenantConfig).toBeNull();
      expect(consoleSpy).toHaveBeenCalled();
      consoleSpy.mockRestore();
    });
  });

  describe('leaveTenant', () => {
    it('should leave tenant and remove from available list', async () => {
      useTenantStore.setState({
        availableTenants: [
          { ...mockTenant, id: 'tenant-1' },
          { ...mockTenant, id: 'tenant-2', name: 'Other Org', slug: 'other-org' },
        ],
      });
      mockInvoke.mockResolvedValueOnce(undefined);

      await useTenantStore.getState().leaveTenant('tenant-1');

      expect(mockInvoke).toHaveBeenCalledWith('leave_tenant', { tenantId: 'tenant-1' });
      expect(useTenantStore.getState().availableTenants).toHaveLength(1);
      expect(useTenantStore.getState().availableTenants[0].id).toBe('tenant-2');
      expect(useTenantStore.getState().isLoading).toBe(false);
    });

    it('should set error and throw on failure', async () => {
      mockInvoke.mockRejectedValueOnce(new Error('Cannot leave'));

      await expect(useTenantStore.getState().leaveTenant('tenant-1')).rejects.toThrow('Cannot leave');

      expect(useTenantStore.getState().error).toBe('Cannot leave');
      expect(useTenantStore.getState().isLoading).toBe(false);
    });
  });

  describe('invitations', () => {
    const mockInvitations = [
      {
        id: 'invite-1',
        tenant_id: 'tenant-2',
        tenant_name: 'New Org',
        invited_by: 'admin@example.com',
        role: 'member' as const,
        created_at: '2026-01-01T00:00:00Z',
        expires_at: null,
      },
    ];

    it('should load invitations', async () => {
      mockInvoke.mockResolvedValueOnce(mockInvitations);

      await useTenantStore.getState().loadInvitations();

      expect(mockInvoke).toHaveBeenCalledWith('get_tenant_invitations');
      expect(useTenantStore.getState().pendingInvitations).toEqual(mockInvitations);
    });

    it('should handle load invitations failure gracefully', async () => {
      const consoleSpy = vi.spyOn(console, 'error').mockImplementation(() => {});
      mockInvoke.mockRejectedValueOnce(new Error('Failed'));

      await useTenantStore.getState().loadInvitations();

      expect(useTenantStore.getState().pendingInvitations).toEqual([]);
      expect(consoleSpy).toHaveBeenCalled();
      consoleSpy.mockRestore();
    });

    it('should accept invitation and add tenant', async () => {
      useTenantStore.setState({ pendingInvitations: mockInvitations, availableTenants: [mockTenant] });
      const newTenant = { id: 'tenant-2', name: 'New Org', slug: 'new-org', role: 'member' as const, joined_at: '2026-01-01T00:00:00Z' };
      mockInvoke.mockResolvedValueOnce(newTenant);

      const result = await useTenantStore.getState().acceptInvitation('invite-1');

      expect(mockInvoke).toHaveBeenCalledWith('accept_tenant_invitation', { invitationId: 'invite-1' });
      expect(result).toEqual(newTenant);
      expect(useTenantStore.getState().availableTenants).toHaveLength(2);
      expect(useTenantStore.getState().pendingInvitations).toHaveLength(0);
    });

    it('should set error on accept failure', async () => {
      useTenantStore.setState({ pendingInvitations: mockInvitations });
      mockInvoke.mockRejectedValueOnce(new Error('Invitation expired'));

      await expect(useTenantStore.getState().acceptInvitation('invite-1')).rejects.toThrow('Invitation expired');
      expect(useTenantStore.getState().error).toBe('Invitation expired');
    });

    it('should decline invitation and remove from list', async () => {
      useTenantStore.setState({ pendingInvitations: mockInvitations });
      mockInvoke.mockResolvedValueOnce(undefined);

      await useTenantStore.getState().declineInvitation('invite-1');

      expect(mockInvoke).toHaveBeenCalledWith('decline_tenant_invitation', { invitationId: 'invite-1' });
      expect(useTenantStore.getState().pendingInvitations).toHaveLength(0);
    });

    it('should set error on decline failure', async () => {
      useTenantStore.setState({ pendingInvitations: mockInvitations });
      mockInvoke.mockRejectedValueOnce(new Error('Decline failed'));

      await expect(useTenantStore.getState().declineInvitation('invite-1')).rejects.toThrow('Decline failed');
      expect(useTenantStore.getState().error).toBe('Decline failed');
    });
  });

});
