import { describe, it, expect, vi, beforeEach } from 'vitest';
import { screen, waitFor } from '@testing-library/react';
import { invoke } from '@tauri-apps/api/core';
import { render } from '../../../test/utils';
import { ShareDetailsDialog } from '../ShareDetailsDialog';
import { useShareStore } from '../../../stores/shareStore';
import { mockShares } from '../../../test/mocks/tauri';
import type { FileItem, Share } from '../../../types';

vi.mock('@tauri-apps/api/core');

const mockInvoke = vi.mocked(invoke);

describe('ShareDetailsDialog', () => {
  const mockOnOpenChange = vi.fn();

  const mockFile: FileItem = {
    id: 'file-1',
    name: 'Document.pdf',
    type: 'file',
    size: 1024,
    mime_type: 'application/pdf',
    folder_id: null,
    is_shared: true,
    created_at: '2024-01-15T10:00:00Z',
    updated_at: '2024-01-15T10:00:00Z',
  };

  const acceptedShares: Share[] = [
    {
      ...mockShares[0],
      status: 'accepted',
      recipient_name: 'Recipient User',
      recipient_email: 'recipient@example.com',
    },
    {
      ...mockShares[1],
      status: 'accepted',
      recipient_name: 'Alice Smith',
      recipient_email: 'alice@example.com',
    },
  ];

  beforeEach(() => {
    vi.clearAllMocks();
    useShareStore.setState({
      myShares: [],
      sharedWithMe: [],
      itemShares: [],
      searchResults: [],
      isLoading: false,
      isSearching: false,
      isCreating: false,
      isUpdating: false,
      error: null,
    });

    mockInvoke.mockImplementation(async (cmd: string) => {
      switch (cmd) {
        case 'get_shares_for_item':
          return { shares: acceptedShares };
        case 'update_share_permission':
          return acceptedShares[0];
        case 'set_share_expiry':
          return acceptedShares[0];
        case 'revoke_share':
          return undefined;
        case 'list_my_shares':
          return { shares: mockShares };
        default:
          return undefined;
      }
    });
  });

  const renderDialog = (item: FileItem | null = mockFile, open = true) => {
    return render(
      <ShareDetailsDialog open={open} onOpenChange={mockOnOpenChange} item={item} />
    );
  };

  it('should render with item name in title', async () => {
    renderDialog();

    await waitFor(() => {
      expect(screen.getByText('Manage sharing for "Document.pdf"')).toBeInTheDocument();
    });
  });

  it('should not render when item is null', () => {
    renderDialog(null);

    expect(screen.queryByText('Manage sharing')).not.toBeInTheDocument();
  });

  it('should show loading state', () => {
    useShareStore.setState({ isLoading: true });

    renderDialog();

    expect(screen.getByText('Loading shares...')).toBeInTheDocument();
  });

  it('should show empty state when no shares', async () => {
    mockInvoke.mockImplementation(async (cmd: string) => {
      if (cmd === 'get_shares_for_item') return { shares: [] };
      return undefined;
    });

    renderDialog();

    await waitFor(() => {
      expect(screen.getByText('No active shares')).toBeInTheDocument();
    });
    expect(
      screen.getByText('This file has not been shared with anyone yet.')
    ).toBeInTheDocument();
  });

  it('should display existing shares', async () => {
    renderDialog();

    await waitFor(() => {
      expect(screen.getByText('Recipient User')).toBeInTheDocument();
    });
    expect(screen.getByText('recipient@example.com')).toBeInTheDocument();
    expect(screen.getByText('Alice Smith')).toBeInTheDocument();
    expect(screen.getByText('alice@example.com')).toBeInTheDocument();
  });

  it('should show share count', async () => {
    renderDialog();

    await waitFor(() => {
      expect(screen.getByText('2 people have access')).toBeInTheDocument();
    });
  });

  it('should show singular count for one share', async () => {
    mockInvoke.mockImplementation(async (cmd: string) => {
      if (cmd === 'get_shares_for_item') return { shares: [acceptedShares[0]] };
      return undefined;
    });

    renderDialog();

    await waitFor(() => {
      expect(screen.getByText('1 person has access')).toBeInTheDocument();
    });
  });

  it('should show status badges for each share', async () => {
    renderDialog();

    await waitFor(() => {
      const statusBadges = screen.getAllByText('accepted');
      expect(statusBadges.length).toBe(2);
    });
  });

  it('should have permission select for each share', async () => {
    renderDialog();

    await waitFor(() => {
      const comboboxes = screen.getAllByRole('combobox');
      expect(comboboxes.length).toBe(2);
    });
  });

  it('should have revoke button for each share', async () => {
    renderDialog();

    await waitFor(() => {
      const revokeButtons = screen.getAllByText('Revoke');
      expect(revokeButtons.length).toBe(2);
    });
  });

  it('should show confirm dialog when clicking revoke', async () => {
    const { user } = renderDialog();

    await waitFor(() => {
      expect(screen.getAllByText('Revoke').length).toBe(2);
    });

    const revokeButtons = screen.getAllByText('Revoke');
    await user.click(revokeButtons[0]);

    expect(screen.getByText('Revoke access')).toBeInTheDocument();
    expect(
      screen.getByText(
        "Are you sure you want to revoke Recipient User's access? They will no longer be able to view or edit this item."
      )
    ).toBeInTheDocument();
  });

  it('should call revokeShare when confirming revoke', async () => {
    const { user } = renderDialog();

    await waitFor(() => {
      expect(screen.getAllByText('Revoke').length).toBe(2);
    });

    // Click the revoke button for the first share
    const revokeButtons = screen.getAllByText('Revoke');
    await user.click(revokeButtons[0]);

    // Find the confirm dialog's Revoke button (the last one)
    const allRevokeButtons = screen.getAllByText('Revoke');
    const confirmRevokeButton = allRevokeButtons[allRevokeButtons.length - 1];
    await user.click(confirmRevokeButton);

    await waitFor(() => {
      expect(mockInvoke).toHaveBeenCalledWith('revoke_share', { shareId: 'share-1' });
    });
  });

  it('should call updateSharePermission when changing permission', async () => {
    mockInvoke.mockImplementation(async (cmd: string) => {
      if (cmd === 'get_shares_for_item') return { shares: [acceptedShares[0]] };
      if (cmd === 'update_share_permission') return acceptedShares[0];
      return undefined;
    });

    const { user } = renderDialog();

    await waitFor(() => {
      expect(screen.getByRole('combobox')).toBeInTheDocument();
    });

    // Click the permission select trigger
    const combobox = screen.getByRole('combobox');
    await user.click(combobox);

    // Select Write permission
    await waitFor(() => {
      const writeOption = screen.getByRole('option', { name: /write/i });
      expect(writeOption).toBeInTheDocument();
    });

    await user.click(screen.getByRole('option', { name: /write/i }));

    await waitFor(() => {
      expect(mockInvoke).toHaveBeenCalledWith('update_share_permission', {
        shareId: 'share-1',
        permission: 'write',
      });
    });
  });

  it('should have date input for expiry', async () => {
    mockInvoke.mockImplementation(async (cmd: string) => {
      if (cmd === 'get_shares_for_item') return { shares: [acceptedShares[0]] };
      return undefined;
    });

    renderDialog();

    await waitFor(() => {
      expect(screen.getByText('Expires')).toBeInTheDocument();
    });
    const dateInput = document.querySelector('input[type="date"]');
    expect(dateInput).toBeInTheDocument();
  });

  it('should display expiry date when share has one', async () => {
    const shareWithExpiry: Share = {
      ...acceptedShares[0],
      expires_at: '2024-12-31T23:59:59Z',
    };

    mockInvoke.mockImplementation(async (cmd: string) => {
      if (cmd === 'get_shares_for_item') return { shares: [shareWithExpiry] };
      return undefined;
    });

    renderDialog();

    await waitFor(() => {
      // There should be 2 elements matching /Expires/: the label + the expiry info paragraph
      const expiryElements = screen.getAllByText(/Expires/);
      expect(expiryElements.length).toBe(2);
    });
  });

  it('should load shares when dialog opens', async () => {
    renderDialog();

    await waitFor(() => {
      expect(mockInvoke).toHaveBeenCalledWith('get_shares_for_item', {
        itemId: 'file-1',
      });
    });
  });

  describe('folder items', () => {
    const mockFolder: FileItem = {
      id: 'folder-1',
      name: 'Project Files',
      type: 'folder',
      size: 0,
      mime_type: null,
      folder_id: null,
      is_shared: true,
      created_at: '2024-01-10T08:00:00Z',
      updated_at: '2024-01-10T08:00:00Z',
    };

    it('should show folder type in description', async () => {
      renderDialog(mockFolder);

      await waitFor(() => {
        expect(
          screen.getByText('View and manage who has access to this folder.')
        ).toBeInTheDocument();
      });
    });

    it('should show empty state for folder', async () => {
      mockInvoke.mockImplementation(async (cmd: string) => {
        if (cmd === 'get_shares_for_item') return { shares: [] };
        return undefined;
      });

      renderDialog(mockFolder);

      await waitFor(() => {
        expect(
          screen.getByText('This folder has not been shared with anyone yet.')
        ).toBeInTheDocument();
      });
    });
  });
});
