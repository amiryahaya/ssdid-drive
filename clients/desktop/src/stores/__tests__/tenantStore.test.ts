import { describe, it, expect, beforeEach, vi, afterEach } from 'vitest';
import { useTenantStore } from '../tenantStore';
import { invoke } from '@tauri-apps/api/core';

vi.mock('@tauri-apps/api/core');

const mockInvoke = vi.mocked(invoke);

const mockTenant = {
  id: 'tenant-1',
  name: 'Test Org',
  slug: 'test-org',
  role: 'admin' as const,
  member_count: 5,
  created_at: '2026-01-01T00:00:00Z',
};

const mockTenantConfig = {
  max_file_size: 100 * 1024 * 1024,
  max_storage: 10 * 1024 * 1024 * 1024,
  allowed_file_types: ['*'],
  features: { pii_detection: true, audit_log: true },
};

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
    it('should switch to a different tenant', async () => {
      useTenantStore.setState({ availableTenants: [mockTenant] });
      // switchTenant expects TenantSwitchResponse
      mockInvoke
        .mockResolvedValueOnce({ tenant: mockTenant, access_token: 'tok', refresh_token: 'ref' })
        .mockResolvedValueOnce(mockTenantConfig); // loadTenantConfig is called after switch

      await useTenantStore.getState().switchTenant('tenant-1');

      const state = useTenantStore.getState();
      expect(state.currentTenantId).toBe('tenant-1');
      expect(state.isSwitching).toBe(false);
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
});
