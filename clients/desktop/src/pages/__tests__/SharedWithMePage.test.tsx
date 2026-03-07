import { describe, it, expect, vi, beforeEach } from 'vitest';
import { screen, waitFor } from '@testing-library/react';
import { invoke } from '@tauri-apps/api/core';
import { render } from '../../test/utils';
import { SharedWithMePage } from '../SharedWithMePage';
import { useShareStore } from '../../stores/shareStore';
import { mockShares } from '../../test/mocks/tauri';

vi.mock('@tauri-apps/api/core');

const mockInvoke = vi.mocked(invoke);

describe('SharedWithMePage', () => {
  beforeEach(() => {
    vi.clearAllMocks();
    useShareStore.setState({
      myShares: [],
      sharedWithMe: [],
      searchResults: [],
      isLoading: false,
      isSearching: false,
      isCreating: false,
      error: null,
    });
  });

  it('should render page title', () => {
    mockInvoke.mockResolvedValueOnce({ shares: [] });

    render(<SharedWithMePage />);

    expect(screen.getByText('Shared with Me')).toBeInTheDocument();
    expect(
      screen.getByText('Files and folders others have shared with you')
    ).toBeInTheDocument();
  });

  it('should show loading spinner initially', () => {
    mockInvoke.mockImplementation(
      () => new Promise((resolve) => setTimeout(() => resolve({ shares: [] }), 1000))
    );

    render(<SharedWithMePage />);

    // The loading spinner uses Loader2 which has the animate-spin class
    expect(document.querySelector('.animate-spin')).toBeInTheDocument();
  });

  it('should show empty state when no shares', async () => {
    mockInvoke.mockResolvedValueOnce({ shares: [] });

    render(<SharedWithMePage />);

    await waitFor(() => {
      expect(screen.getByText('No shared items')).toBeInTheDocument();
      expect(
        screen.getByText(
          'When someone shares a file or folder with you, it will appear here'
        )
      ).toBeInTheDocument();
    });
  });

  it('should render share list after loading', async () => {
    mockInvoke.mockResolvedValueOnce({ shares: mockShares });

    render(<SharedWithMePage />);

    await waitFor(() => {
      expect(screen.getByText('Document.pdf')).toBeInTheDocument();
      expect(screen.getByText('Project Files')).toBeInTheDocument();
    });
  });

  it('should show owner information', async () => {
    mockInvoke.mockResolvedValueOnce({ shares: mockShares });

    render(<SharedWithMePage />);

    await waitFor(() => {
      expect(screen.getByText('Document.pdf')).toBeInTheDocument();
    });

    // Check owner info is displayed (multiple items may show same owner)
    const ownerTexts = screen.getAllByText(/Owner User/);
    expect(ownerTexts.length).toBeGreaterThan(0);
  });

  it('should show permission level', async () => {
    mockInvoke.mockResolvedValueOnce({ shares: mockShares });

    render(<SharedWithMePage />);

    await waitFor(() => {
      expect(screen.getByText(/View only/)).toBeInTheDocument();
      expect(screen.getByText(/Can edit/)).toBeInTheDocument();
    });
  });

  it('should show accept/decline buttons for pending shares', async () => {
    const pendingShare = { ...mockShares[0], status: 'pending' as const };
    mockInvoke.mockResolvedValueOnce({ shares: [pendingShare] });

    render(<SharedWithMePage />);

    await waitFor(() => {
      expect(screen.getByRole('button', { name: /Accept/ })).toBeInTheDocument();
      expect(screen.getByRole('button', { name: /Decline/ })).toBeInTheDocument();
    });
  });

  it('should not show accept/decline for accepted shares', async () => {
    const acceptedShare = { ...mockShares[0], status: 'accepted' as const };
    mockInvoke.mockResolvedValueOnce({ shares: [acceptedShare] });

    render(<SharedWithMePage />);

    await waitFor(() => {
      expect(screen.getByText('Document.pdf')).toBeInTheDocument();
    });

    expect(screen.queryByRole('button', { name: /Accept/ })).not.toBeInTheDocument();
  });

  it('should call acceptShare when Accept clicked', async () => {
    const pendingShare = { ...mockShares[0], status: 'pending' as const };
    mockInvoke
      .mockResolvedValueOnce({ shares: [pendingShare] }) // listSharedWithMe
      .mockResolvedValueOnce({ ...pendingShare, status: 'accepted' }); // acceptShare

    const { user } = render(<SharedWithMePage />);

    await waitFor(() => {
      expect(screen.getByRole('button', { name: /Accept/ })).toBeInTheDocument();
    });

    await user.click(screen.getByRole('button', { name: /Accept/ }));

    await waitFor(() => {
      expect(mockInvoke).toHaveBeenCalledWith('accept_share', { shareId: 'share-1' });
    });
  });

  it('should call declineShare when Decline clicked', async () => {
    const pendingShare = { ...mockShares[0], status: 'pending' as const };
    mockInvoke
      .mockResolvedValueOnce({ shares: [pendingShare] }) // listSharedWithMe
      .mockResolvedValueOnce(undefined); // declineShare

    const { user } = render(<SharedWithMePage />);

    await waitFor(() => {
      expect(screen.getByRole('button', { name: /Decline/ })).toBeInTheDocument();
    });

    await user.click(screen.getByRole('button', { name: /Decline/ }));

    await waitFor(() => {
      expect(mockInvoke).toHaveBeenCalledWith('decline_share', { shareId: 'share-1' });
    });
  });

  it('should show error banner when error occurs', async () => {
    mockInvoke.mockRejectedValueOnce(new Error('Network error'));

    render(<SharedWithMePage />);

    await waitFor(() => {
      expect(screen.getByText(/Network error/)).toBeInTheDocument();
    });
  });

  it('should show message if share has one', async () => {
    mockInvoke.mockResolvedValueOnce({ shares: mockShares });

    render(<SharedWithMePage />);

    await waitFor(() => {
      expect(screen.getByText(/"Please review these files"/)).toBeInTheDocument();
    });
  });

  it('should show status badges', async () => {
    mockInvoke.mockResolvedValueOnce({ shares: mockShares });

    render(<SharedWithMePage />);

    await waitFor(() => {
      expect(screen.getByText('Pending')).toBeInTheDocument();
      expect(screen.getByText('Accepted')).toBeInTheDocument();
    });
  });
});
