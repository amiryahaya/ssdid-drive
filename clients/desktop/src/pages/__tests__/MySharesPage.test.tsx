import { describe, it, expect, vi, beforeEach } from 'vitest';
import { screen, waitFor } from '@testing-library/react';
import { invoke } from '@tauri-apps/api/core';
import { render } from '../../test/utils';
import { MySharesPage } from '../MySharesPage';
import { useShareStore } from '../../stores/shareStore';
import { mockShares } from '../../test/mocks/tauri';

vi.mock('@tauri-apps/api/core');

// Mock DropdownMenu to simplify testing - Radix portals are tricky
vi.mock('../../components/ui/DropdownMenu', () => ({
  DropdownMenu: ({ children }: { children: React.ReactNode }) => <div>{children}</div>,
  DropdownMenuTrigger: ({ children }: { children: React.ReactNode }) => <div data-testid="dropdown-trigger">{children}</div>,
  DropdownMenuContent: ({ children }: { children: React.ReactNode }) => <div data-testid="dropdown-content">{children}</div>,
  DropdownMenuItem: ({ children, onClick }: { children: React.ReactNode; onClick?: () => void }) => (
    <button data-testid="dropdown-item" onClick={onClick}>{children}</button>
  ),
}));

const mockInvoke = vi.mocked(invoke);

// Store the original store functions
const originalLoadMyShares = useShareStore.getState().loadMyShares;
const originalClearError = useShareStore.getState().clearError;

describe('MySharesPage', () => {
  beforeEach(() => {
    vi.clearAllMocks();
    // Reset store to initial state including original functions
    useShareStore.setState({
      myShares: [],
      sharedWithMe: [],
      searchResults: [],
      isLoading: false,
      isSearching: false,
      isCreating: false,
      error: null,
      loadMyShares: originalLoadMyShares,
      clearError: originalClearError,
    });
  });

  it('should render page title', () => {
    mockInvoke.mockResolvedValueOnce({ shares: [] });

    render(<MySharesPage />);

    expect(screen.getByText('My Shares')).toBeInTheDocument();
    expect(
      screen.getByText('Files and folders you have shared with others')
    ).toBeInTheDocument();
  });

  it('should show loading spinner initially', () => {
    mockInvoke.mockImplementation(
      () => new Promise((resolve) => setTimeout(() => resolve({ shares: [] }), 1000))
    );

    render(<MySharesPage />);

    expect(document.querySelector('.animate-spin')).toBeInTheDocument();
  });

  it('should show empty state when no shares', async () => {
    mockInvoke.mockResolvedValueOnce({ shares: [] });

    render(<MySharesPage />);

    await waitFor(() => {
      expect(screen.getByText('No shares yet')).toBeInTheDocument();
      expect(
        screen.getByText('Share files with others using the share button')
      ).toBeInTheDocument();
    });
  });

  it('should render share list after loading', async () => {
    mockInvoke.mockResolvedValueOnce({ shares: mockShares });

    render(<MySharesPage />);

    await waitFor(() => {
      expect(screen.getByText('Document.pdf')).toBeInTheDocument();
      expect(screen.getByText('Project Files')).toBeInTheDocument();
    });
  });

  it('should show recipient information', async () => {
    mockInvoke.mockResolvedValueOnce({ shares: mockShares });

    render(<MySharesPage />);

    await waitFor(() => {
      expect(screen.getByText('Document.pdf')).toBeInTheDocument();
    });

    // Check recipient info is displayed
    expect(screen.getByText(/Recipient User/)).toBeInTheDocument();
  });

  it('should show permission level', async () => {
    mockInvoke.mockResolvedValueOnce({ shares: mockShares });

    render(<MySharesPage />);

    await waitFor(() => {
      expect(screen.getByText(/View only/)).toBeInTheDocument();
      expect(screen.getByText(/Can edit/)).toBeInTheDocument();
    });
  });

  it('should show status badges', async () => {
    mockInvoke.mockResolvedValueOnce({ shares: mockShares });

    render(<MySharesPage />);

    await waitFor(() => {
      expect(screen.getByText('Pending')).toBeInTheDocument();
      expect(screen.getByText('Accepted')).toBeInTheDocument();
    });
  });

  it('should show expiration date if set', async () => {
    mockInvoke.mockResolvedValueOnce({ shares: mockShares });

    render(<MySharesPage />);

    await waitFor(() => {
      expect(screen.getByText(/Expires:/)).toBeInTheDocument();
    });
  });

  it('should call revokeShare when store action is triggered', async () => {
    useShareStore.setState({ myShares: mockShares });
    mockInvoke.mockResolvedValueOnce(undefined); // revokeShare

    const { revokeShare } = useShareStore.getState();
    await revokeShare('share-1');

    expect(mockInvoke).toHaveBeenCalledWith('revoke_share', { shareId: 'share-1' });
    expect(useShareStore.getState().myShares).toHaveLength(1);
  });

  it('should show error in store state', async () => {
    mockInvoke.mockRejectedValueOnce(new Error('Failed to load shares'));

    render(<MySharesPage />);

    await waitFor(() => {
      expect(useShareStore.getState().error).toContain('Failed to load shares');
    });
  });

  it('should clear error when clearError called', () => {
    useShareStore.setState({ error: 'Some error' });

    const { clearError } = useShareStore.getState();
    clearError();

    expect(useShareStore.getState().error).toBeNull();
  });

  describe('error state UI', () => {
    it('should display error message when error exists', async () => {
      // Mock loadMyShares to not change state, keeping error visible
      const loadMySharesSpy = vi.fn();
      useShareStore.setState({
        error: 'Failed to load shares',
        isLoading: false,
        loadMyShares: loadMySharesSpy,
      });

      render(<MySharesPage />);

      expect(screen.getByText('Failed to load shares')).toBeInTheDocument();
    });

    it('should show dismiss button with error', async () => {
      const loadMySharesSpy = vi.fn();
      useShareStore.setState({
        error: 'Some error occurred',
        isLoading: false,
        loadMyShares: loadMySharesSpy,
      });

      render(<MySharesPage />);

      expect(screen.getByRole('button', { name: /dismiss/i })).toBeInTheDocument();
    });

    it('should call clearError when dismiss button clicked', async () => {
      const loadMySharesSpy = vi.fn();
      const clearErrorSpy = vi.fn();
      useShareStore.setState({
        error: 'Some error',
        isLoading: false,
        loadMyShares: loadMySharesSpy,
        clearError: clearErrorSpy,
      });

      const { user } = render(<MySharesPage />);

      const dismissButton = screen.getByRole('button', { name: /dismiss/i });
      await user.click(dismissButton);

      expect(clearErrorSpy).toHaveBeenCalled();
    });
  });

  describe('revoke share flow', () => {
    it('should render share items with action buttons', async () => {
      mockInvoke.mockResolvedValueOnce({ shares: mockShares });

      render(<MySharesPage />);

      await waitFor(() => {
        expect(screen.getByText('Document.pdf')).toBeInTheDocument();
      });

      // Each share item should have a dropdown trigger button
      const buttons = screen.getAllByRole('button');
      // At least one button per share item
      expect(buttons.length).toBeGreaterThan(0);
    });

    it('should have store actions available for revoke', () => {
      const state = useShareStore.getState();
      expect(state.revokeShare).toBeDefined();
      expect(typeof state.revokeShare).toBe('function');
    });
  });

  describe('folder share rendering', () => {
    it('should show folder icon for folder shares', async () => {
      const folderShare = {
        ...mockShares[1],
        item_type: 'folder' as const,
      };
      mockInvoke.mockResolvedValueOnce({ shares: [folderShare] });

      render(<MySharesPage />);

      await waitFor(() => {
        expect(screen.getByText('Project Files')).toBeInTheDocument();
      });

      // Folder icon should be present
      expect(document.querySelector('.lucide-folder')).toBeInTheDocument();
    });
  });

  describe('share recipient display', () => {
    it('should show recipient email when name is not available', async () => {
      const shareWithoutName = {
        ...mockShares[0],
        recipient_name: undefined,
        recipient_email: 'user@example.com',
      };
      mockInvoke.mockResolvedValueOnce({ shares: [shareWithoutName] });

      render(<MySharesPage />);

      await waitFor(() => {
        expect(screen.getByText(/user@example.com/)).toBeInTheDocument();
      });
    });
  });

  describe('revoke confirmation dialog', () => {
    it('should open revoke dialog when clicking Revoke Share in dropdown', async () => {
      const loadMySharesSpy = vi.fn();
      useShareStore.setState({
        myShares: mockShares,
        isLoading: false,
        loadMyShares: loadMySharesSpy,
      });

      const { user } = render(<MySharesPage />);

      // With mocked DropdownMenu, "Revoke Share" is directly visible
      await waitFor(() => {
        expect(screen.getAllByText('Revoke Share').length).toBeGreaterThan(0);
      });

      // Click the first Revoke Share button
      const revokeButtons = screen.getAllByText('Revoke Share');
      await user.click(revokeButtons[0]);

      // Dialog should open
      await waitFor(() => {
        expect(screen.getByText('Revoke Share', { selector: 'h2' })).toBeInTheDocument();
      });
    });

    it('should show share details in revoke confirmation dialog', async () => {
      const loadMySharesSpy = vi.fn();
      useShareStore.setState({
        myShares: [mockShares[0]],
        isLoading: false,
        loadMyShares: loadMySharesSpy,
      });

      const { user } = render(<MySharesPage />);

      // Open dropdown and click revoke
      const dropdownTrigger = document.querySelector('.lucide-ellipsis')?.closest('button');
      await user.click(dropdownTrigger!);

      await waitFor(() => {
        expect(screen.getByText('Revoke Share')).toBeInTheDocument();
      });

      await user.click(screen.getByText('Revoke Share'));

      // Check dialog content includes recipient and item names
      await waitFor(() => {
        expect(screen.getByText(/no longer be able to access/i)).toBeInTheDocument();
      });
    });

    it('should close dialog when Cancel is clicked', async () => {
      const loadMySharesSpy = vi.fn();
      useShareStore.setState({
        myShares: [mockShares[0]],
        isLoading: false,
        loadMyShares: loadMySharesSpy,
      });

      const { user } = render(<MySharesPage />);

      // Open dropdown and click revoke
      const dropdownTrigger = document.querySelector('.lucide-ellipsis')?.closest('button');
      await user.click(dropdownTrigger!);

      await waitFor(() => {
        expect(screen.getByText('Revoke Share')).toBeInTheDocument();
      });

      await user.click(screen.getByText('Revoke Share'));

      // Wait for dialog to open
      await waitFor(() => {
        expect(screen.getByRole('button', { name: /cancel/i })).toBeInTheDocument();
      });

      // Click Cancel
      await user.click(screen.getByRole('button', { name: /cancel/i }));

      // Dialog should close
      await waitFor(() => {
        expect(screen.queryByText('Revoke Share', { selector: 'h2' })).not.toBeInTheDocument();
      });
    });

    it('should call revokeShare when Revoke is confirmed', async () => {
      const loadMySharesSpy = vi.fn();
      const revokeShareSpy = vi.fn().mockResolvedValue(undefined);
      useShareStore.setState({
        myShares: [mockShares[0]],
        isLoading: false,
        loadMyShares: loadMySharesSpy,
        revokeShare: revokeShareSpy,
      });

      const { user } = render(<MySharesPage />);

      // Open dropdown and click revoke
      const dropdownTrigger = document.querySelector('.lucide-ellipsis')?.closest('button');
      await user.click(dropdownTrigger!);

      await waitFor(() => {
        expect(screen.getByText('Revoke Share')).toBeInTheDocument();
      });

      await user.click(screen.getByText('Revoke Share'));

      // Wait for dialog and click Revoke button
      await waitFor(() => {
        expect(screen.getByRole('button', { name: /^revoke$/i })).toBeInTheDocument();
      });

      await user.click(screen.getByRole('button', { name: /^revoke$/i }));

      await waitFor(() => {
        expect(revokeShareSpy).toHaveBeenCalledWith('share-1');
      });
    });

    it('should close dialog after successful revoke', async () => {
      const loadMySharesSpy = vi.fn();
      const revokeShareSpy = vi.fn().mockResolvedValue(undefined);
      useShareStore.setState({
        myShares: [mockShares[0]],
        isLoading: false,
        loadMyShares: loadMySharesSpy,
        revokeShare: revokeShareSpy,
      });

      const { user } = render(<MySharesPage />);

      // Open dropdown and click revoke
      const dropdownTrigger = document.querySelector('.lucide-ellipsis')?.closest('button');
      await user.click(dropdownTrigger!);

      await waitFor(() => {
        expect(screen.getByText('Revoke Share')).toBeInTheDocument();
      });

      await user.click(screen.getByText('Revoke Share'));

      // Click Revoke button
      await waitFor(() => {
        expect(screen.getByRole('button', { name: /^revoke$/i })).toBeInTheDocument();
      });

      await user.click(screen.getByRole('button', { name: /^revoke$/i }));

      // Dialog should close
      await waitFor(() => {
        expect(screen.queryByText('Revoke Share', { selector: 'h2' })).not.toBeInTheDocument();
      });
    });

    it('should show loading state on Revoke button during revoke', async () => {
      const loadMySharesSpy = vi.fn();
      const revokeShareSpy = vi.fn().mockImplementation(
        () => new Promise((resolve) => setTimeout(resolve, 1000))
      );
      useShareStore.setState({
        myShares: [mockShares[0]],
        isLoading: false,
        loadMyShares: loadMySharesSpy,
        revokeShare: revokeShareSpy,
      });

      const { user } = render(<MySharesPage />);

      // Open dropdown and click revoke
      const dropdownTrigger = document.querySelector('.lucide-ellipsis')?.closest('button');
      await user.click(dropdownTrigger!);

      await waitFor(() => {
        expect(screen.getByText('Revoke Share')).toBeInTheDocument();
      });

      await user.click(screen.getByText('Revoke Share'));

      // Click Revoke button
      await waitFor(() => {
        expect(screen.getByRole('button', { name: /^revoke$/i })).toBeInTheDocument();
      });

      const revokeButton = screen.getByRole('button', { name: /^revoke$/i });
      await user.click(revokeButton);

      // Button should be disabled while loading
      await waitFor(() => {
        expect(revokeButton).toBeDisabled();
      });
    });
  });

  describe('file icon', () => {
    it('should show file icon for file shares', async () => {
      const fileShare = {
        ...mockShares[0],
        item_type: 'file' as const,
      };
      mockInvoke.mockResolvedValueOnce({ shares: [fileShare] });

      render(<MySharesPage />);

      await waitFor(() => {
        expect(screen.getByText('Document.pdf')).toBeInTheDocument();
      });

      // File icon should be present
      expect(document.querySelector('.lucide-file')).toBeInTheDocument();
    });
  });
});
