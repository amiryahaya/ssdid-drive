import { describe, it, expect, vi, beforeEach } from 'vitest';
import { screen, waitFor } from '@testing-library/react';
import { render } from '../../../test/utils';
import { RecoveryStatusCard } from '../RecoveryStatusCard';
import { useRecoveryStore, RecoverySetup } from '../../../stores/recoveryStore';
import { invoke } from '@tauri-apps/api/core';

vi.mock('@tauri-apps/api/core');

const mockInvoke = vi.mocked(invoke);

const mockSetupNotConfigured: RecoverySetup | null = null;

const mockSetupPending: RecoverySetup = {
  id: 'setup-1',
  threshold: 2,
  total_trustees: 3,
  trustees: [
    {
      id: 'trustee-1',
      email: 'alice@example.com',
      name: 'Alice Smith',
      status: 'pending',
      added_at: '2024-01-15T10:00:00Z',
    },
    {
      id: 'trustee-2',
      email: 'bob@example.com',
      name: 'Bob Jones',
      status: 'accepted',
      added_at: '2024-01-15T10:00:00Z',
    },
    {
      id: 'trustee-3',
      email: 'carol@example.com',
      name: null,
      status: 'declined',
      added_at: '2024-01-15T10:00:00Z',
    },
  ],
  created_at: '2024-01-15T10:00:00Z',
  updated_at: '2024-01-15T10:00:00Z',
};

const mockSetupFullyConfigured: RecoverySetup = {
  id: 'setup-2',
  threshold: 2,
  total_trustees: 3,
  trustees: [
    {
      id: 'trustee-1',
      email: 'alice@example.com',
      name: 'Alice Smith',
      status: 'accepted',
      added_at: '2024-01-15T10:00:00Z',
    },
    {
      id: 'trustee-2',
      email: 'bob@example.com',
      name: 'Bob Jones',
      status: 'accepted',
      added_at: '2024-01-15T10:00:00Z',
    },
    {
      id: 'trustee-3',
      email: 'carol@example.com',
      name: 'Carol White',
      status: 'pending',
      added_at: '2024-01-15T10:00:00Z',
    },
  ],
  created_at: '2024-01-15T10:00:00Z',
  updated_at: '2024-01-15T10:00:00Z',
};

describe('RecoveryStatusCard', () => {
  const mockLoadRecoveryStatus = vi.fn();

  beforeEach(() => {
    vi.clearAllMocks();

    // Mock the store with a no-op loadRecoveryStatus to prevent state changes
    useRecoveryStore.setState({
      setup: null,
      pendingRequests: [],
      isLoading: false,
      isSettingUp: false,
      error: null,
      loadRecoveryStatus: mockLoadRecoveryStatus,
    });

    mockInvoke.mockResolvedValue(null);
  });

  describe('when not configured', () => {
    it('should render "Not configured" status', () => {
      useRecoveryStore.setState({
        setup: mockSetupNotConfigured,
        isLoading: false,
        loadRecoveryStatus: mockLoadRecoveryStatus,
      });

      render(<RecoveryStatusCard />);

      expect(screen.getByText('Not configured')).toBeInTheDocument();
    });

    it('should render "Set Up Recovery" button', () => {
      useRecoveryStore.setState({
        setup: null,
        isLoading: false,
        loadRecoveryStatus: mockLoadRecoveryStatus,
      });

      render(<RecoveryStatusCard />);

      expect(screen.getByRole('button', { name: /set up recovery/i })).toBeInTheDocument();
    });

    it('should show setup instructions when not configured', () => {
      useRecoveryStore.setState({
        setup: null,
        isLoading: false,
        loadRecoveryStatus: mockLoadRecoveryStatus,
      });

      render(<RecoveryStatusCard />);

      expect(
        screen.getByText(/set up account recovery to protect your data/i)
      ).toBeInTheDocument();
    });

    it('should not render remove button when not configured', () => {
      useRecoveryStore.setState({
        setup: null,
        isLoading: false,
        loadRecoveryStatus: mockLoadRecoveryStatus,
      });

      render(<RecoveryStatusCard />);

      expect(document.querySelector('.lucide-trash2')).not.toBeInTheDocument();
    });
  });

  describe('when setup is in progress (pending trustees)', () => {
    beforeEach(() => {
      useRecoveryStore.setState({
        setup: mockSetupPending,
        isLoading: false,
        loadRecoveryStatus: mockLoadRecoveryStatus,
      });
    });

    it('should render "Setup in progress" status', () => {
      render(<RecoveryStatusCard />);

      expect(screen.getByText('Setup in progress')).toBeInTheDocument();
    });

    it('should render "Configure" button', () => {
      render(<RecoveryStatusCard />);

      expect(screen.getByRole('button', { name: /configure/i })).toBeInTheDocument();
    });

    it('should show threshold information', () => {
      render(<RecoveryStatusCard />);

      // The threshold is rendered as "Recovery threshold: <strong>2 of 3</strong> trustees"
      expect(screen.getByText(/Recovery threshold:/)).toBeInTheDocument();
    });

    it('should show trusted contacts section', () => {
      render(<RecoveryStatusCard />);

      expect(screen.getByText('Trusted Contacts')).toBeInTheDocument();
    });

    it('should display all trustees', () => {
      render(<RecoveryStatusCard />);

      expect(screen.getByText('Alice Smith')).toBeInTheDocument();
      expect(screen.getByText('Bob Jones')).toBeInTheDocument();
      // Carol has no name, so email is shown as primary
      expect(screen.getByText('carol@example.com')).toBeInTheDocument();
    });

    it('should show trustee statuses', () => {
      render(<RecoveryStatusCard />);

      expect(screen.getByText('Pending')).toBeInTheDocument();
      expect(screen.getByText('Accepted')).toBeInTheDocument();
      expect(screen.getByText('Declined')).toBeInTheDocument();
    });

    it('should show waiting for acceptances message', () => {
      render(<RecoveryStatusCard />);

      expect(screen.getByText('Waiting for acceptances')).toBeInTheDocument();
      expect(screen.getByText(/1 of 2 required trustees/)).toBeInTheDocument();
    });

    it('should render remove button when configured', () => {
      render(<RecoveryStatusCard />);

      // Find the button containing the trash icon (destructive button)
      const trashIcon = document.querySelector('.lucide-trash2');
      expect(trashIcon).toBeInTheDocument();
    });
  });

  describe('when fully configured', () => {
    beforeEach(() => {
      useRecoveryStore.setState({
        setup: mockSetupFullyConfigured,
        isLoading: false,
        loadRecoveryStatus: mockLoadRecoveryStatus,
      });
    });

    it('should render "Your account is protected" status', () => {
      render(<RecoveryStatusCard />);

      expect(screen.getByText('Your account is protected')).toBeInTheDocument();
    });

    it('should not show waiting message when fully configured', () => {
      render(<RecoveryStatusCard />);

      expect(screen.queryByText('Waiting for acceptances')).not.toBeInTheDocument();
    });

    it('should show shield check icon', () => {
      render(<RecoveryStatusCard />);

      expect(document.querySelector('.lucide-shield-check')).toBeInTheDocument();
    });
  });

  describe('loading state', () => {
    it('should show loading spinner when loading', () => {
      useRecoveryStore.setState({
        isLoading: true,
        loadRecoveryStatus: mockLoadRecoveryStatus,
      });

      render(<RecoveryStatusCard />);

      expect(document.querySelector('.animate-spin')).toBeInTheDocument();
    });

    it('should call loadRecoveryStatus on mount', async () => {
      render(<RecoveryStatusCard />);

      await waitFor(() => {
        expect(mockLoadRecoveryStatus).toHaveBeenCalled();
      });
    });
  });

  describe('Account Recovery title', () => {
    it('should always show Account Recovery title', () => {
      useRecoveryStore.setState({
        setup: null,
        isLoading: false,
        loadRecoveryStatus: mockLoadRecoveryStatus,
      });

      render(<RecoveryStatusCard />);

      expect(screen.getByText('Account Recovery')).toBeInTheDocument();
    });
  });

  describe('remove recovery', () => {
    it('should open remove dialog when trash button is clicked', async () => {
      useRecoveryStore.setState({
        setup: mockSetupPending,
        isLoading: false,
        loadRecoveryStatus: mockLoadRecoveryStatus,
      });

      const { user } = render(<RecoveryStatusCard />);

      // Find and click the trash button (class is lucide-trash2, not lucide-trash-2)
      const trashButton = document.querySelector('.lucide-trash2')?.closest('button');
      expect(trashButton).toBeInTheDocument();
      await user.click(trashButton!);

      // Dialog should open
      await waitFor(() => {
        expect(screen.getByText('Remove Recovery Protection')).toBeInTheDocument();
      });
    });

    it('should show remove confirmation dialog description', async () => {
      useRecoveryStore.setState({
        setup: mockSetupPending,
        isLoading: false,
        loadRecoveryStatus: mockLoadRecoveryStatus,
      });

      const { user } = render(<RecoveryStatusCard />);

      // Click trash button
      const trashButton = document.querySelector('.lucide-trash2')?.closest('button');
      await user.click(trashButton!);

      await waitFor(() => {
        expect(
          screen.getByText(/Are you sure you want to remove recovery protection/i)
        ).toBeInTheDocument();
      });
    });

    it('should call removeRecovery when remove is confirmed', async () => {
      const removeRecoverySpy = vi.fn().mockResolvedValue(undefined);
      useRecoveryStore.setState({
        setup: mockSetupPending,
        isLoading: false,
        loadRecoveryStatus: mockLoadRecoveryStatus,
        removeRecovery: removeRecoverySpy,
      });

      const { user } = render(<RecoveryStatusCard />);

      // Click trash button
      const trashButton = document.querySelector('.lucide-trash2')?.closest('button');
      await user.click(trashButton!);

      // Wait for dialog to open
      await waitFor(() => {
        expect(screen.getByText('Remove Recovery Protection')).toBeInTheDocument();
      });

      // Click Remove button in dialog
      const confirmButton = screen.getByRole('button', { name: /^remove$/i });
      await user.click(confirmButton);

      await waitFor(() => {
        expect(removeRecoverySpy).toHaveBeenCalled();
      });
    });

    it('should close dialog after successful removal', async () => {
      const removeRecoverySpy = vi.fn().mockResolvedValue(undefined);
      useRecoveryStore.setState({
        setup: mockSetupPending,
        isLoading: false,
        loadRecoveryStatus: mockLoadRecoveryStatus,
        removeRecovery: removeRecoverySpy,
      });

      const { user } = render(<RecoveryStatusCard />);

      // Click trash button
      const trashButton = document.querySelector('.lucide-trash2')?.closest('button');
      await user.click(trashButton!);

      // Wait for dialog to open
      await waitFor(() => {
        expect(screen.getByText('Remove Recovery Protection')).toBeInTheDocument();
      });

      // Click Remove button in dialog
      const confirmButton = screen.getByRole('button', { name: /^remove$/i });
      await user.click(confirmButton);

      // Dialog should close
      await waitFor(() => {
        expect(screen.queryByText('Remove Recovery Protection')).not.toBeInTheDocument();
      });
    });

    it('should show loading state on trash button during removal', async () => {
      const removeRecoverySpy = vi.fn().mockImplementation(
        () => new Promise((resolve) => setTimeout(resolve, 1000))
      );
      useRecoveryStore.setState({
        setup: mockSetupPending,
        isLoading: false,
        loadRecoveryStatus: mockLoadRecoveryStatus,
        removeRecovery: removeRecoverySpy,
      });

      const { user } = render(<RecoveryStatusCard />);

      // Click trash button
      const trashButton = document.querySelector('.lucide-trash2')?.closest('button');
      await user.click(trashButton!);

      // Wait for dialog to open
      await waitFor(() => {
        expect(screen.getByText('Remove Recovery Protection')).toBeInTheDocument();
      });

      // Click Remove button in dialog
      const confirmButton = screen.getByRole('button', { name: /^remove$/i });
      await user.click(confirmButton);

      // Confirm button should be disabled during removal
      await waitFor(() => {
        expect(confirmButton).toBeDisabled();
      });
    });
  });

  describe('setup dialog', () => {
    it('should open setup dialog when Set Up Recovery is clicked', async () => {
      useRecoveryStore.setState({
        setup: null,
        isLoading: false,
        loadRecoveryStatus: mockLoadRecoveryStatus,
      });

      const { user } = render(<RecoveryStatusCard />);

      const setupButton = screen.getByRole('button', { name: /set up recovery/i });
      await user.click(setupButton);

      // RecoverySetupDialog should open - look for dialog element
      await waitFor(() => {
        expect(screen.getByRole('dialog')).toBeInTheDocument();
      });
    });

    it('should open configure dialog when Configure is clicked', async () => {
      useRecoveryStore.setState({
        setup: mockSetupPending,
        isLoading: false,
        loadRecoveryStatus: mockLoadRecoveryStatus,
      });

      const { user } = render(<RecoveryStatusCard />);

      const configureButton = screen.getByRole('button', { name: /configure/i });
      await user.click(configureButton);

      // RecoverySetupDialog should open - look for dialog element
      await waitFor(() => {
        expect(screen.getByRole('dialog')).toBeInTheDocument();
      });
    });
  });
});
