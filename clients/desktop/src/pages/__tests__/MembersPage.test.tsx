import { describe, it, expect, vi, beforeEach } from 'vitest';
import { screen, waitFor } from '@testing-library/react';
import { render } from '../../test/utils';
import { MembersPage } from '../MembersPage';
import { useMemberStore } from '../../stores/memberStore';
import { useTenantStore } from '../../stores/tenantStore';
import { useAuthStore } from '../../stores/authStore';
import type { TenantMember } from '../../stores/memberStore';

// Mock @tauri-apps/api/core
vi.mock('@tauri-apps/api/core', () => ({
  invoke: vi.fn().mockRejectedValue(new Error('not available')),
}));

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

function setupStores(overrides?: {
  currentRole?: 'owner' | 'admin' | 'member';
  members?: TenantMember[];
  error?: string | null;
  isLoading?: boolean;
  isUpdating?: boolean;
  currentUserId?: string;
}) {
  const loadMembers = vi.fn();
  const updateMemberRole = vi.fn().mockResolvedValue(undefined);
  const removeMember = vi.fn().mockResolvedValue(undefined);
  const clearError = vi.fn();

  useMemberStore.setState({
    members: overrides?.members ?? mockMembers,
    isLoading: overrides?.isLoading ?? false,
    isUpdating: overrides?.isUpdating ?? false,
    error: overrides?.error ?? null,
    loadMembers,
    updateMemberRole,
    removeMember,
    clearError,
  });

  const role = overrides?.currentRole ?? 'owner';
  useTenantStore.setState({
    currentTenant: {
      id: 'tenant-1',
      name: 'Acme Corp',
      slug: 'acme',
      role,
      joined_at: '2024-01-01T00:00:00Z',
    },
    currentTenantId: 'tenant-1',
    currentRole: role,
    canManageMembers: role === 'owner' || role === 'admin',
    canManageTenant: role === 'owner',
    availableTenants: [],
    isLoading: false,
    error: null,
  });

  useAuthStore.setState({
    user: {
      id: overrides?.currentUserId ?? 'user-1',
      email: 'owner@example.com',
      name: 'Owner User',
      tenantId: 'tenant-1',
    },
    isAuthenticated: true,
    isLocked: false,
    error: null,
  });

  return { loadMembers, updateMemberRole, removeMember, clearError };
}

describe('MembersPage', () => {
  beforeEach(() => {
    vi.clearAllMocks();
  });

  it('should render member list with names', () => {
    setupStores();
    render(<MembersPage />);

    expect(screen.getByText('Owner User')).toBeInTheDocument();
    expect(screen.getByText('Admin User')).toBeInTheDocument();
    expect(screen.getByText('Member User')).toBeInTheDocument();
  });

  it('should load members on mount', () => {
    const mocks = setupStores();
    render(<MembersPage />);

    expect(mocks.loadMembers).toHaveBeenCalledWith('tenant-1');
  });

  it('should show (you) next to current user', () => {
    setupStores({ currentUserId: 'user-1' });
    render(<MembersPage />);

    expect(screen.getByText('(you)')).toBeInTheDocument();
  });

  it('should show member count', () => {
    setupStores();
    render(<MembersPage />);

    expect(screen.getByText('3 members')).toBeInTheDocument();
  });

  it('should show singular member count for 1 member', () => {
    setupStores({ members: [mockMembers[0]] });
    render(<MembersPage />);

    expect(screen.getByText('1 member')).toBeInTheDocument();
  });

  it('should show remove button for editable members when user is owner', () => {
    setupStores({ currentRole: 'owner', currentUserId: 'user-1' });
    render(<MembersPage />);

    // Owner can remove admin (user-2) and member (user-3), but not themselves (user-1) or other owners
    expect(screen.getByRole('button', { name: /Remove Admin User/i })).toBeInTheDocument();
    expect(screen.getByRole('button', { name: /Remove Member User/i })).toBeInTheDocument();
  });

  it('should not show remove button for current user', () => {
    setupStores({ currentRole: 'owner', currentUserId: 'user-1' });
    render(<MembersPage />);

    expect(screen.queryByRole('button', { name: /Remove Owner User/i })).not.toBeInTheDocument();
  });

  it('should not show role dropdown for members when current user is member role', () => {
    setupStores({ currentRole: 'member', currentUserId: 'user-3' });
    render(<MembersPage />);

    // No role dropdowns should appear since member cannot edit anyone
    const removeButtons = screen.queryAllByRole('button', { name: /Remove/i });
    // Filter out any "Dismiss" buttons
    const actualRemoveButtons = removeButtons.filter((b) => b.textContent?.includes('Remove'));
    expect(actualRemoveButtons).toHaveLength(0);
  });

  it('should show remove confirmation dialog when remove is clicked', async () => {
    setupStores({ currentRole: 'owner', currentUserId: 'user-1' });
    const { user } = render(<MembersPage />);

    await user.click(screen.getByRole('button', { name: /Remove Member User/i }));

    await waitFor(() => {
      expect(screen.getByText('Remove Member')).toBeInTheDocument();
    });
    expect(screen.getByText(/Are you sure you want to remove Member User/)).toBeInTheDocument();
  });

  it('should show loading state', () => {
    setupStores({ isLoading: true });
    render(<MembersPage />);

    // Should not show member list when loading
    expect(screen.queryByText('Owner User')).not.toBeInTheDocument();
  });

  it('should show empty state when no members', () => {
    setupStores({ members: [] });
    render(<MembersPage />);

    expect(screen.getByText('No members found')).toBeInTheDocument();
  });

  it('should show error banner when error is set', () => {
    setupStores({ error: 'Failed to load members' });
    render(<MembersPage />);

    expect(screen.getByText('Failed to load members')).toBeInTheDocument();
    expect(screen.getByRole('button', { name: 'Dismiss' })).toBeInTheDocument();
  });

  it('should call clearError when Dismiss is clicked', async () => {
    const mocks = setupStores({ error: 'Failed to load members' });
    const { user } = render(<MembersPage />);

    await user.click(screen.getByRole('button', { name: 'Dismiss' }));

    expect(mocks.clearError).toHaveBeenCalled();
  });

  it('should show tenant name in subtitle', () => {
    setupStores();
    render(<MembersPage />);

    expect(screen.getByText('Manage members of Acme Corp')).toBeInTheDocument();
  });

  describe('admin permissions', () => {
    it('should show remove button only for members when current user is admin', () => {
      setupStores({ currentRole: 'admin', currentUserId: 'user-2' });
      render(<MembersPage />);

      // Admin can only manage members (not owners or other admins)
      expect(screen.getByRole('button', { name: /Remove Member User/i })).toBeInTheDocument();
      expect(screen.queryByRole('button', { name: /Remove Owner User/i })).not.toBeInTheDocument();
    });
  });
});
