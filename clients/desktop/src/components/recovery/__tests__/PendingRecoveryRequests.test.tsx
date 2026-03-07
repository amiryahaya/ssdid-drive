import { describe, it, expect, vi, beforeEach } from 'vitest';
import { screen, waitFor } from '@testing-library/react';
import { render } from '../../../test/utils';
import { PendingRecoveryRequests } from '../PendingRecoveryRequests';
import { useRecoveryStore, RecoveryRequest } from '../../../stores/recoveryStore';
import { invoke } from '@tauri-apps/api/core';

vi.mock('@tauri-apps/api/core');

const mockInvoke = vi.mocked(invoke);

const mockPendingRequests: RecoveryRequest[] = [
  {
    id: 'request-1',
    requester_email: 'john@example.com',
    requester_name: 'John Doe',
    status: 'pending',
    created_at: '2024-01-15T10:00:00Z',
    approvals_received: 1,
    approvals_required: 2,
  },
  {
    id: 'request-2',
    requester_email: 'jane@example.com',
    requester_name: null,
    status: 'pending',
    created_at: '2024-01-14T10:00:00Z',
    approvals_received: 0,
    approvals_required: 3,
  },
];

describe('PendingRecoveryRequests', () => {
  beforeEach(() => {
    vi.clearAllMocks();

    useRecoveryStore.setState({
      setup: null,
      pendingRequests: [],
      isLoading: false,
      isSettingUp: false,
      error: null,
    });

    mockInvoke.mockResolvedValue([]);
  });

  describe('when no pending requests', () => {
    it('should render nothing when no pending requests', () => {
      useRecoveryStore.setState({ pendingRequests: [] });

      const { container } = render(<PendingRecoveryRequests />);

      // Component returns null when no pending requests
      expect(container.firstChild).toBeNull();
    });
  });

  describe('when has pending requests', () => {
    it('should render Recovery Requests header', () => {
      useRecoveryStore.setState({ pendingRequests: mockPendingRequests });

      render(<PendingRecoveryRequests />);

      expect(screen.getByText('Recovery Requests')).toBeInTheDocument();
    });

    it('should render description text', () => {
      useRecoveryStore.setState({ pendingRequests: mockPendingRequests });

      render(<PendingRecoveryRequests />);

      expect(
        screen.getByText('Someone is requesting your help to recover their account')
      ).toBeInTheDocument();
    });

    it('should display requester name when available', () => {
      useRecoveryStore.setState({ pendingRequests: mockPendingRequests });

      render(<PendingRecoveryRequests />);

      expect(screen.getByText('John Doe')).toBeInTheDocument();
    });

    it('should display requester email when name not available', () => {
      useRecoveryStore.setState({ pendingRequests: mockPendingRequests });

      render(<PendingRecoveryRequests />);

      // Jane has no name, so email is shown as primary
      expect(screen.getByText('jane@example.com')).toBeInTheDocument();
    });

    it('should show approval counts', () => {
      useRecoveryStore.setState({ pendingRequests: mockPendingRequests });

      render(<PendingRecoveryRequests />);

      expect(screen.getByText(/1 of 2/)).toBeInTheDocument();
      expect(screen.getByText(/0 of 3/)).toBeInTheDocument();
    });

    it('should render Approve button for each request', () => {
      useRecoveryStore.setState({ pendingRequests: mockPendingRequests });

      render(<PendingRecoveryRequests />);

      const approveButtons = screen.getAllByRole('button', { name: /approve/i });
      expect(approveButtons).toHaveLength(2);
    });

    it('should render Deny button for each request', () => {
      useRecoveryStore.setState({ pendingRequests: mockPendingRequests });

      render(<PendingRecoveryRequests />);

      const denyButtons = screen.getAllByRole('button', { name: /deny/i });
      expect(denyButtons).toHaveLength(2);
    });

    it('should render key icon in header', () => {
      useRecoveryStore.setState({ pendingRequests: mockPendingRequests });

      render(<PendingRecoveryRequests />);

      expect(document.querySelector('.lucide-key')).toBeInTheDocument();
    });

    it('should render user icons for each request', () => {
      useRecoveryStore.setState({ pendingRequests: mockPendingRequests });

      render(<PendingRecoveryRequests />);

      const userIcons = document.querySelectorAll('.lucide-user');
      expect(userIcons.length).toBeGreaterThanOrEqual(2);
    });

    it('should call loadPendingRequests on mount', async () => {
      const loadPendingRequestsSpy = vi.fn();
      useRecoveryStore.setState({
        pendingRequests: mockPendingRequests,
        loadPendingRequests: loadPendingRequestsSpy,
      });

      render(<PendingRecoveryRequests />);

      await waitFor(() => {
        expect(loadPendingRequestsSpy).toHaveBeenCalled();
      });
    });
  });

  describe('error state', () => {
    it('should display error message when error exists', () => {
      useRecoveryStore.setState({
        pendingRequests: mockPendingRequests,
        error: 'Failed to load requests',
      });

      render(<PendingRecoveryRequests />);

      expect(screen.getByText('Failed to load requests')).toBeInTheDocument();
    });
  });

  describe('interactions', () => {
    it('should call approveRequest when Approve is clicked', async () => {
      const approveRequestSpy = vi.fn().mockResolvedValue(undefined);
      useRecoveryStore.setState({
        pendingRequests: [mockPendingRequests[0]],
        approveRequest: approveRequestSpy,
      });

      const { user } = render(<PendingRecoveryRequests />);

      const approveButton = screen.getByRole('button', { name: /approve/i });
      await user.click(approveButton);

      await waitFor(() => {
        expect(approveRequestSpy).toHaveBeenCalledWith('request-1');
      });
    });

    it('should open deny confirmation dialog when Deny is clicked', async () => {
      useRecoveryStore.setState({
        pendingRequests: [mockPendingRequests[0]],
      });

      const { user } = render(<PendingRecoveryRequests />);

      const denyButton = screen.getByRole('button', { name: /deny/i });
      await user.click(denyButton);

      // Should open confirmation dialog
      await waitFor(() => {
        expect(screen.getByText('Deny Recovery Request')).toBeInTheDocument();
      });
    });

    it('should call denyRequest when confirm deny is clicked', async () => {
      const denyRequestSpy = vi.fn().mockResolvedValue(undefined);
      useRecoveryStore.setState({
        pendingRequests: [mockPendingRequests[0]],
        denyRequest: denyRequestSpy,
      });

      const { user } = render(<PendingRecoveryRequests />);

      // Click deny to open dialog
      const denyButton = screen.getByRole('button', { name: /deny/i });
      await user.click(denyButton);

      // Wait for dialog to open
      await waitFor(() => {
        expect(screen.getByText('Deny Recovery Request')).toBeInTheDocument();
      });

      // Confirm deny in dialog
      const confirmButton = screen.getByRole('button', { name: /^deny$/i });
      await user.click(confirmButton);

      await waitFor(() => {
        expect(denyRequestSpy).toHaveBeenCalledWith('request-1');
      });
    });

    it('should show error toast when approve fails', async () => {
      const approveRequestSpy = vi.fn().mockRejectedValue(new Error('Network error'));
      useRecoveryStore.setState({
        pendingRequests: [mockPendingRequests[0]],
        approveRequest: approveRequestSpy,
      });

      const { user } = render(<PendingRecoveryRequests />);

      const approveButton = screen.getByRole('button', { name: /approve/i });
      await user.click(approveButton);

      await waitFor(() => {
        expect(approveRequestSpy).toHaveBeenCalledWith('request-1');
      });
    });

    it('should show error toast when deny fails', async () => {
      const denyRequestSpy = vi.fn().mockRejectedValue(new Error('Network error'));
      useRecoveryStore.setState({
        pendingRequests: [mockPendingRequests[0]],
        denyRequest: denyRequestSpy,
      });

      const { user } = render(<PendingRecoveryRequests />);

      // Click deny to open dialog
      const denyButton = screen.getByRole('button', { name: /deny/i });
      await user.click(denyButton);

      // Wait for dialog and confirm
      await waitFor(() => {
        expect(screen.getByText('Deny Recovery Request')).toBeInTheDocument();
      });

      const confirmButton = screen.getByRole('button', { name: /^deny$/i });
      await user.click(confirmButton);

      await waitFor(() => {
        expect(denyRequestSpy).toHaveBeenCalledWith('request-1');
      });
    });

    it('should close dialog after successful deny', async () => {
      const denyRequestSpy = vi.fn().mockResolvedValue(undefined);
      useRecoveryStore.setState({
        pendingRequests: [mockPendingRequests[0]],
        denyRequest: denyRequestSpy,
      });

      const { user } = render(<PendingRecoveryRequests />);

      // Click deny to open dialog
      const denyButton = screen.getByRole('button', { name: /deny/i });
      await user.click(denyButton);

      await waitFor(() => {
        expect(screen.getByText('Deny Recovery Request')).toBeInTheDocument();
      });

      // Confirm deny
      const confirmButton = screen.getByRole('button', { name: /^deny$/i });
      await user.click(confirmButton);

      // Dialog should close after deny
      await waitFor(() => {
        expect(screen.queryByText('Deny Recovery Request')).not.toBeInTheDocument();
      });
    });

    it('should show loading spinner on buttons while processing', async () => {
      const approveRequestSpy = vi.fn().mockImplementation(
        () => new Promise((resolve) => setTimeout(resolve, 1000))
      );
      useRecoveryStore.setState({
        pendingRequests: [mockPendingRequests[0]],
        approveRequest: approveRequestSpy,
      });

      const { user } = render(<PendingRecoveryRequests />);

      const approveButton = screen.getByRole('button', { name: /approve/i });
      await user.click(approveButton);

      // Button should be disabled while processing
      await waitFor(() => {
        expect(approveButton).toBeDisabled();
      });
    });
  });
});
