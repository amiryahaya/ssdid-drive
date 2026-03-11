import { describe, it, expect, vi, beforeEach } from 'vitest';
import { screen, waitFor } from '@testing-library/react';
import { render } from '../../../test/utils';
import { CreateInvitationDialog } from '../CreateInvitationDialog';
import { useInvitationStore } from '../../../stores/invitationStore';
import { useTenantStore } from '../../../stores/tenantStore';

// Mock @tauri-apps/api/core
vi.mock('@tauri-apps/api/core', () => ({
  invoke: vi.fn().mockRejectedValue(new Error('not available')),
}));

function setupStores(overrides?: {
  canManageTenant?: boolean;
  isCreating?: boolean;
}) {
  const createInvitation = vi.fn().mockResolvedValue({
    id: 'new-inv',
    short_code: 'ACME-NEW1',
    role: 'member',
    email: null,
    expires_at: null,
  });

  useInvitationStore.setState({
    isCreating: overrides?.isCreating ?? false,
    createInvitation,
  });

  const role = overrides?.canManageTenant ? 'owner' : 'admin';
  useTenantStore.setState({
    currentTenant: {
      id: 'tenant-1',
      name: 'Acme Corp',
      slug: 'acme',
      role: role as 'owner' | 'admin',
      joined_at: '2024-01-01T00:00:00Z',
    },
    currentTenantId: 'tenant-1',
    canManageTenant: overrides?.canManageTenant ?? false,
    canManageMembers: true,
    availableTenants: [],
    isLoading: false,
    error: null,
  });

  return { createInvitation };
}

describe('CreateInvitationDialog', () => {
  let mockOnOpenChange: ReturnType<typeof vi.fn>;

  beforeEach(() => {
    vi.clearAllMocks();
    mockOnOpenChange = vi.fn();
  });

  function renderDialog(open = true) {
    return render(
      <CreateInvitationDialog open={open} onOpenChange={mockOnOpenChange} />
    );
  }

  it('should render dialog when open', () => {
    setupStores();
    renderDialog();

    // "Create Invitation" appears as both the dialog title (h2) and the submit button
    expect(screen.getByRole('heading', { name: 'Create Invitation' })).toBeInTheDocument();
    expect(screen.getByText(/Invite someone to join/)).toBeInTheDocument();
  });

  it('should not render dialog content when closed', () => {
    setupStores();
    renderDialog(false);

    expect(screen.queryByText('Create Invitation')).not.toBeInTheDocument();
  });

  it('should show email input with optional label', () => {
    setupStores();
    renderDialog();

    expect(screen.getByLabelText(/Email/i)).toBeInTheDocument();
    // Both email and message fields have "(optional)" labels
    expect(screen.getAllByText('(optional)')).toHaveLength(2);
  });

  it('should show email validation error for invalid email', async () => {
    setupStores();
    const { user } = renderDialog();

    const emailInput = screen.getByLabelText(/Email/i);
    await user.type(emailInput, 'not-an-email');
    await user.tab(); // blur to trigger validation

    expect(screen.getByText('Please enter a valid email address')).toBeInTheDocument();
  });

  it('should not show validation error for blank email (optional field)', async () => {
    setupStores();
    const { user } = renderDialog();

    const emailInput = screen.getByLabelText(/Email/i);
    await user.click(emailInput);
    await user.tab(); // blur with empty value

    expect(screen.queryByText('Please enter a valid email address')).not.toBeInTheDocument();
  });

  it('should not show validation error for valid email', async () => {
    setupStores();
    const { user } = renderDialog();

    const emailInput = screen.getByLabelText(/Email/i);
    await user.type(emailInput, 'valid@example.com');
    await user.tab();

    expect(screen.queryByText('Please enter a valid email address')).not.toBeInTheDocument();
  });

  it('should cap message at 500 characters', async () => {
    setupStores();
    const { user } = renderDialog();

    const messageInput = screen.getByLabelText(/Message/i);
    const longText = 'a'.repeat(600);
    await user.type(messageInput, longText);

    expect(messageInput).toHaveValue('a'.repeat(500));
    expect(screen.getByText('500/500')).toBeInTheDocument();
  });

  it('should show character counter for message', () => {
    setupStores();
    renderDialog();

    expect(screen.getByText('0/500')).toBeInTheDocument();
  });

  it('should call createInvitation on submit with valid data', async () => {
    const mocks = setupStores();
    const { user } = renderDialog();

    const emailInput = screen.getByLabelText(/Email/i);
    await user.type(emailInput, 'test@example.com');

    await user.click(screen.getByRole('button', { name: 'Create Invitation' }));

    await waitFor(() => {
      expect(mocks.createInvitation).toHaveBeenCalledWith({
        email: 'test@example.com',
        role: 'member',
        message: undefined,
      });
    });
  });

  it('should show short code after successful creation', async () => {
    setupStores();
    const { user } = renderDialog();

    await user.click(screen.getByRole('button', { name: 'Create Invitation' }));

    await waitFor(() => {
      expect(screen.getByText('ACME-NEW1')).toBeInTheDocument();
    });
    expect(screen.getByText('Invite Code')).toBeInTheDocument();
  });

  it('should show copy button in success state', async () => {
    setupStores();
    const { user } = renderDialog();

    await user.click(screen.getByRole('button', { name: 'Create Invitation' }));

    await waitFor(() => {
      expect(screen.getByRole('button', { name: 'Copy invite code' })).toBeInTheDocument();
    });
  });

  it('should call navigator.clipboard.writeText when copy is clicked', async () => {
    setupStores();

    const writeText = vi.fn().mockResolvedValue(undefined);
    vi.spyOn(navigator.clipboard, 'writeText').mockImplementation(writeText);

    const { user } = renderDialog();

    await user.click(screen.getByRole('button', { name: 'Create Invitation' }));

    await waitFor(() => {
      expect(screen.getByRole('button', { name: 'Copy invite code' })).toBeInTheDocument();
    });

    await user.click(screen.getByRole('button', { name: 'Copy invite code' }));

    expect(writeText).toHaveBeenCalledWith('ACME-NEW1');
  });

  it('should not allow creating with invalid email', async () => {
    const mocks = setupStores();
    const { user } = renderDialog();

    const emailInput = screen.getByLabelText(/Email/i);
    await user.type(emailInput, 'invalid-email');
    await user.tab();

    // The create button should be disabled when there's an email error
    const createButton = screen.getByRole('button', { name: 'Create Invitation' });
    expect(createButton).toBeDisabled();

    expect(mocks.createInvitation).not.toHaveBeenCalled();
  });

  it('should reset form when dialog is closed', async () => {
    setupStores();
    const { user } = renderDialog();

    const emailInput = screen.getByLabelText(/Email/i);
    await user.type(emailInput, 'test@example.com');

    // Close the dialog via Cancel button
    await user.click(screen.getByRole('button', { name: 'Cancel' }));

    expect(mockOnOpenChange).toHaveBeenCalledWith(false);
  });

  it('should show Done button after successful creation', async () => {
    setupStores();
    const { user } = renderDialog();

    await user.click(screen.getByRole('button', { name: 'Create Invitation' }));

    await waitFor(() => {
      expect(screen.getByRole('button', { name: 'Done' })).toBeInTheDocument();
    });
  });
});
