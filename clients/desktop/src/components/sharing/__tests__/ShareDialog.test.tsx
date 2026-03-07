import { describe, it, expect, vi, beforeEach } from 'vitest';
import { screen, waitFor } from '@testing-library/react';
import { invoke } from '@tauri-apps/api/core';
import { render } from '../../../test/utils';
import { ShareDialog } from '../ShareDialog';
import { useShareStore } from '../../../stores/shareStore';
import { mockRecipients, mockShares } from '../../../test/mocks/tauri';
import type { FileItem } from '../../../types';

vi.mock('@tauri-apps/api/core');

const mockInvoke = vi.mocked(invoke);

describe('ShareDialog', () => {
  const mockOnOpenChange = vi.fn();

  const mockFile: FileItem = {
    id: 'file-1',
    name: 'Document.pdf',
    type: 'file',
    size: 1024,
    mime_type: 'application/pdf',
    folder_id: null,
    is_shared: false,
    created_at: '2024-01-15T10:00:00Z',
    updated_at: '2024-01-15T10:00:00Z',
  };

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

    mockInvoke.mockImplementation(async (cmd: string) => {
      switch (cmd) {
        case 'search_recipients':
          return mockRecipients;
        case 'create_share':
          return { share: mockShares[0] };
        case 'list_my_shares':
          return { shares: mockShares };
        default:
          throw new Error(`Unknown command: ${cmd}`);
      }
    });
  });

  const renderDialog = (item: FileItem | null = mockFile, open = true) => {
    return render(
      <ShareDialog open={open} onOpenChange={mockOnOpenChange} item={item} />
    );
  };

  it('should render with item name in title', () => {
    renderDialog();

    expect(screen.getByText('Share "Document.pdf"')).toBeInTheDocument();
  });

  it('should not render when item is null', () => {
    renderDialog(null);

    expect(screen.queryByText('Share')).not.toBeInTheDocument();
  });

  it('should have recipient search input', () => {
    renderDialog();

    expect(screen.getByPlaceholderText('Search by email or name...')).toBeInTheDocument();
  });

  it('should have permission select with default read', () => {
    renderDialog();

    expect(screen.getByText('Read')).toBeInTheDocument();
  });

  it('should show search results after typing', async () => {
    const { user } = renderDialog();

    const searchInput = screen.getByPlaceholderText('Search by email or name...');
    await user.type(searchInput, 'alice');

    await waitFor(() => {
      expect(mockInvoke).toHaveBeenCalledWith('search_recipients', { query: 'alice' });
    });

    await waitFor(() => {
      expect(screen.getByText('Alice Smith')).toBeInTheDocument();
      expect(screen.getByText('alice@example.com')).toBeInTheDocument();
    });
  });

  it('should select recipient on click', async () => {
    useShareStore.setState({ searchResults: mockRecipients });

    const { user } = renderDialog();

    const searchInput = screen.getByPlaceholderText('Search by email or name...');
    await user.type(searchInput, 'al');

    // Wait for search results to appear
    await waitFor(() => {
      expect(screen.getByText('Alice Smith')).toBeInTheDocument();
    });

    await user.click(screen.getByText('Alice Smith'));

    expect(searchInput).toHaveValue('alice@example.com');
    expect(screen.getByText('Selected: Alice Smith')).toBeInTheDocument();
  });

  it('should close dialog on cancel', async () => {
    const { user } = renderDialog();

    const cancelButton = screen.getByRole('button', { name: 'Cancel' });
    await user.click(cancelButton);

    expect(mockOnOpenChange).toHaveBeenCalledWith(false);
  });

  it('should disable share button when no recipient', () => {
    renderDialog();

    const shareButton = screen.getByRole('button', { name: 'Share' });
    expect(shareButton).toBeDisabled();
  });

  it('should enable share button when recipient entered', async () => {
    const { user } = renderDialog();

    const searchInput = screen.getByPlaceholderText('Search by email or name...');
    await user.type(searchInput, 'test@example.com');

    const shareButton = screen.getByRole('button', { name: 'Share' });
    expect(shareButton).not.toBeDisabled();
  });

  it('should call createShare with correct data', async () => {
    useShareStore.setState({ searchResults: mockRecipients });

    const { user } = renderDialog();

    // Enter recipient email directly
    const searchInput = screen.getByPlaceholderText('Search by email or name...');
    await user.type(searchInput, 'recipient@example.com');

    // Add optional message
    const messageInput = screen.getByPlaceholderText('Add a personal message...');
    await user.type(messageInput, 'Please review this file');

    const shareButton = screen.getByRole('button', { name: 'Share' });
    await user.click(shareButton);

    await waitFor(() => {
      expect(mockInvoke).toHaveBeenCalledWith('create_share', {
        request: {
          item_id: 'file-1',
          recipient_email: 'recipient@example.com',
          permission: 'read',
          message: 'Please review this file',
        },
      });
    });
  });

  it('should close dialog on successful share', async () => {
    const { user } = renderDialog();

    const searchInput = screen.getByPlaceholderText('Search by email or name...');
    await user.type(searchInput, 'test@example.com');

    const shareButton = screen.getByRole('button', { name: 'Share' });
    await user.click(shareButton);

    await waitFor(() => {
      expect(mockOnOpenChange).toHaveBeenCalledWith(false);
    });
  });

  describe('error handling', () => {
    it('should show error when createShare fails', async () => {
      mockInvoke.mockImplementation(async (cmd: string) => {
        if (cmd === 'create_share') {
          throw new Error('Share creation failed');
        }
        return mockRecipients;
      });

      const { user } = renderDialog();

      const searchInput = screen.getByPlaceholderText('Search by email or name...');
      await user.type(searchInput, 'test@example.com');

      const shareButton = screen.getByRole('button', { name: 'Share' });
      await user.click(shareButton);

      // Verify createShare was called
      await waitFor(() => {
        expect(mockInvoke).toHaveBeenCalledWith('create_share', expect.any(Object));
      });

      // Dialog should NOT close on error
      expect(mockOnOpenChange).not.toHaveBeenCalledWith(false);
    });
  });

  describe('permission selection', () => {
    it('should allow changing permission to write', async () => {
      const { user } = renderDialog();

      // Click permission select trigger
      const selectTrigger = screen.getByRole('combobox');
      await user.click(selectTrigger);

      // Select Write permission
      await waitFor(() => {
        const writeOption = screen.getByRole('option', { name: /write/i });
        expect(writeOption).toBeInTheDocument();
      });

      await user.click(screen.getByRole('option', { name: /write/i }));

      // Now type recipient and share
      const searchInput = screen.getByPlaceholderText('Search by email or name...');
      await user.type(searchInput, 'test@example.com');

      const shareButton = screen.getByRole('button', { name: 'Share' });
      await user.click(shareButton);

      await waitFor(() => {
        expect(mockInvoke).toHaveBeenCalledWith('create_share', {
          request: {
            item_id: 'file-1',
            recipient_email: 'test@example.com',
            permission: 'write',
            message: undefined,
          },
        });
      });
    });

    it('should allow changing permission to admin', async () => {
      const { user } = renderDialog();

      // Click permission select trigger
      const selectTrigger = screen.getByRole('combobox');
      await user.click(selectTrigger);

      // Select Admin permission
      await waitFor(() => {
        const adminOption = screen.getByRole('option', { name: /admin/i });
        expect(adminOption).toBeInTheDocument();
      });

      await user.click(screen.getByRole('option', { name: /admin/i }));

      // Now type recipient and share
      const searchInput = screen.getByPlaceholderText('Search by email or name...');
      await user.type(searchInput, 'test@example.com');

      const shareButton = screen.getByRole('button', { name: 'Share' });
      await user.click(shareButton);

      await waitFor(() => {
        expect(mockInvoke).toHaveBeenCalledWith('create_share', {
          request: {
            item_id: 'file-1',
            recipient_email: 'test@example.com',
            permission: 'admin',
            message: undefined,
          },
        });
      });
    });
  });

  describe('loading state', () => {
    it('should show loading spinner when searching', async () => {
      mockInvoke.mockImplementation(
        () => new Promise((resolve) => setTimeout(() => resolve(mockRecipients), 500))
      );

      const { user } = renderDialog();

      const searchInput = screen.getByPlaceholderText('Search by email or name...');
      await user.type(searchInput, 'alice');

      // Check for spinner while searching
      await waitFor(() => {
        expect(document.querySelector('.animate-spin')).toBeInTheDocument();
      });
    });

    it('should show loading spinner when creating share', async () => {
      mockInvoke.mockImplementation(async (cmd: string) => {
        if (cmd === 'create_share') {
          return new Promise((resolve) => setTimeout(() => resolve({ share: mockShares[0] }), 500));
        }
        return mockRecipients;
      });

      const { user } = renderDialog();

      const searchInput = screen.getByPlaceholderText('Search by email or name...');
      await user.type(searchInput, 'test@example.com');

      const shareButton = screen.getByRole('button', { name: 'Share' });
      await user.click(shareButton);

      // Share button should be disabled while creating
      await waitFor(() => {
        expect(shareButton).toBeDisabled();
      });
    });
  });

  describe('form reset', () => {
    it('should reset form when dialog closes', async () => {
      const { rerender, user } = renderDialog();

      const searchInput = screen.getByPlaceholderText('Search by email or name...');
      await user.type(searchInput, 'test@example.com');

      expect(searchInput).toHaveValue('test@example.com');

      // Close dialog
      rerender(
        <ShareDialog open={false} onOpenChange={mockOnOpenChange} item={mockFile} />
      );

      // Reopen dialog
      rerender(
        <ShareDialog open={true} onOpenChange={mockOnOpenChange} item={mockFile} />
      );

      const newSearchInput = screen.getByPlaceholderText('Search by email or name...');
      expect(newSearchInput).toHaveValue('');
    });
  });
});
