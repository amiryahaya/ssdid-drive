import { describe, it, expect, vi, beforeEach } from 'vitest';
import { screen, waitFor } from '@testing-library/react';
import { render } from '../../test/utils';
import { InvitationsPage } from '../InvitationsPage';
import { useInvitationStore } from '../../stores/invitationStore';
import { useTenantStore } from '../../stores/tenantStore';
import type { ReceivedInvitation, SentInvitation } from '../../stores/invitationStore';

// Mock @tauri-apps/api/core
vi.mock('@tauri-apps/api/core', () => ({
  invoke: vi.fn().mockRejectedValue(new Error('not available')),
}));

// Mock CreateInvitationDialog to keep tests focused
vi.mock('@/components/tenant/CreateInvitationDialog', () => ({
  CreateInvitationDialog: ({ open }: { open: boolean }) =>
    open ? <div data-testid="create-invitation-dialog">Create Dialog</div> : null,
}));

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
];

const mockSentInvitations: SentInvitation[] = [
  {
    id: 'sinv-1',
    tenant_id: 'tenant-1',
    tenant_name: 'Acme Corp',
    email: 'invitee@example.com',
    role: 'member',
    message: null,
    short_code: 'ACME-AAAA',
    status: 'pending',
    created_at: '2024-01-15T10:00:00Z',
    expires_at: null,
  },
];

function setupStores(overrides?: {
  canManageMembers?: boolean;
  received?: ReceivedInvitation[];
  sent?: SentInvitation[];
  error?: string | null;
  isLoadingReceived?: boolean;
  isLoadingSent?: boolean;
}) {
  const loadReceivedInvitations = vi.fn();
  const loadSentInvitations = vi.fn();
  const acceptInvitation = vi.fn().mockResolvedValue(undefined);
  const declineInvitation = vi.fn().mockResolvedValue(undefined);
  const revokeInvitation = vi.fn().mockResolvedValue(undefined);
  const clearError = vi.fn();

  useInvitationStore.setState({
    receivedInvitations: overrides?.received ?? mockReceivedInvitations,
    sentInvitations: overrides?.sent ?? mockSentInvitations,
    receivedPage: 1,
    sentPage: 1,
    receivedTotalPages: 1,
    sentTotalPages: 1,
    isLoadingReceived: overrides?.isLoadingReceived ?? false,
    isLoadingSent: overrides?.isLoadingSent ?? false,
    error: overrides?.error ?? null,
    loadReceivedInvitations,
    loadSentInvitations,
    acceptInvitation,
    declineInvitation,
    revokeInvitation,
    clearError,
  });

  // The tenant store uses computed getters (get canManageMembers()) which derive
  // from currentTenant.role. We need to set both the currentTenant and the
  // computed property, because setState overwrites getters with plain values.
  const role = overrides?.canManageMembers === false ? 'member' : 'admin';
  const canManageMembers = role === 'owner' || role === 'admin';
  const canManageTenant = role === 'owner';
  useTenantStore.setState({
    currentTenant: {
      id: 'tenant-1',
      name: 'Acme Corp',
      slug: 'acme',
      role: role as 'admin' | 'member' | 'owner',
      joined_at: '2024-01-01T00:00:00Z',
    },
    currentTenantId: 'tenant-1',
    availableTenants: [],
    isLoading: false,
    error: null,
    canManageMembers,
    canManageTenant,
  });

  return {
    loadReceivedInvitations,
    loadSentInvitations,
    acceptInvitation,
    declineInvitation,
    revokeInvitation,
    clearError,
  };
}

describe('InvitationsPage', () => {
  beforeEach(() => {
    vi.clearAllMocks();
  });

  it('should render Received and Sent tabs', () => {
    setupStores();
    render(<InvitationsPage />);

    expect(screen.getByRole('tab', { name: 'Received' })).toBeInTheDocument();
    expect(screen.getByRole('tab', { name: 'Sent' })).toBeInTheDocument();
  });

  it('should show received invitations by default', () => {
    setupStores();
    render(<InvitationsPage />);

    expect(screen.getByText('Acme Corp')).toBeInTheDocument();
    expect(screen.getByText('Pending')).toBeInTheDocument();
  });

  it('should load invitations on mount', () => {
    const mocks = setupStores();
    render(<InvitationsPage />);

    expect(mocks.loadReceivedInvitations).toHaveBeenCalled();
    expect(mocks.loadSentInvitations).toHaveBeenCalled();
  });

  it('should switch to Sent tab when clicked', async () => {
    setupStores();
    const { user } = render(<InvitationsPage />);

    await user.click(screen.getByRole('tab', { name: 'Sent' }));

    expect(screen.getByText('invitee@example.com')).toBeInTheDocument();
    expect(screen.getByText('ACME-AAAA')).toBeInTheDocument();
  });

  it('should show Accept and Decline buttons for pending received invitations', () => {
    setupStores();
    render(<InvitationsPage />);

    expect(screen.getByRole('button', { name: /Accept/i })).toBeInTheDocument();
    expect(screen.getByRole('button', { name: /Decline/i })).toBeInTheDocument();
  });

  it('should call acceptInvitation when Accept is clicked', async () => {
    const mocks = setupStores();
    const { user } = render(<InvitationsPage />);

    await user.click(screen.getByRole('button', { name: /Accept/i }));

    await waitFor(() => {
      expect(mocks.acceptInvitation).toHaveBeenCalledWith('inv-1');
    });
  });

  it('should call declineInvitation when Decline is clicked', async () => {
    const mocks = setupStores();
    const { user } = render(<InvitationsPage />);

    await user.click(screen.getByRole('button', { name: /Decline/i }));

    await waitFor(() => {
      expect(mocks.declineInvitation).toHaveBeenCalledWith('inv-1');
    });
  });

  it('should show Revoke button for pending sent invitations', async () => {
    setupStores();
    const { user } = render(<InvitationsPage />);

    await user.click(screen.getByRole('tab', { name: 'Sent' }));

    expect(screen.getByRole('button', { name: 'Revoke' })).toBeInTheDocument();
  });

  it('should show revoke confirmation dialog when Revoke is clicked', async () => {
    setupStores();
    const { user } = render(<InvitationsPage />);

    await user.click(screen.getByRole('tab', { name: 'Sent' }));
    await user.click(screen.getByRole('button', { name: 'Revoke' }));

    await waitFor(() => {
      expect(screen.getByText('Revoke Invitation')).toBeInTheDocument();
    });
    expect(screen.getByText(/Are you sure you want to revoke/)).toBeInTheDocument();
  });

  it('should show Create Invitation button when canManageMembers is true', () => {
    setupStores({ canManageMembers: true });
    render(<InvitationsPage />);

    expect(screen.getByRole('button', { name: /Create Invitation/i })).toBeInTheDocument();
  });

  it('should not show Create Invitation button when canManageMembers is false', () => {
    setupStores({ canManageMembers: false });
    render(<InvitationsPage />);

    expect(screen.queryByRole('button', { name: /Create Invitation/i })).not.toBeInTheDocument();
  });

  it('should show empty state for received invitations', () => {
    setupStores({ received: [] });
    render(<InvitationsPage />);

    expect(screen.getByText('No invitations received')).toBeInTheDocument();
  });

  it('should show empty state for sent invitations', async () => {
    setupStores({ sent: [] });
    const { user } = render(<InvitationsPage />);

    await user.click(screen.getByRole('tab', { name: 'Sent' }));

    expect(screen.getByText('No invitations sent')).toBeInTheDocument();
  });

  it('should show error banner when error is set', () => {
    setupStores({ error: 'Something went wrong' });
    render(<InvitationsPage />);

    expect(screen.getByText('Something went wrong')).toBeInTheDocument();
    expect(screen.getByRole('button', { name: 'Dismiss' })).toBeInTheDocument();
  });

  it('should call clearError when Dismiss is clicked', async () => {
    const mocks = setupStores({ error: 'Something went wrong' });
    const { user } = render(<InvitationsPage />);

    await user.click(screen.getByRole('button', { name: 'Dismiss' }));

    expect(mocks.clearError).toHaveBeenCalled();
  });

  it('should show loading state for received tab', () => {
    setupStores({ isLoadingReceived: true });
    render(<InvitationsPage />);

    expect(screen.getByRole('status', { name: /Loading invitations/i })).toBeInTheDocument();
  });

  it('should show loading state for sent tab', async () => {
    setupStores({ isLoadingSent: true });
    const { user } = render(<InvitationsPage />);

    await user.click(screen.getByRole('tab', { name: 'Sent' }));

    expect(screen.getByRole('status', { name: /Loading invitations/i })).toBeInTheDocument();
  });

  it('should open create dialog when Create Invitation button is clicked', async () => {
    setupStores({ canManageMembers: true });
    const { user } = render(<InvitationsPage />);

    await user.click(screen.getByRole('button', { name: /Create Invitation/i }));

    expect(screen.getByTestId('create-invitation-dialog')).toBeInTheDocument();
  });
});
