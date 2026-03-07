import { describe, it, expect, vi, beforeEach } from 'vitest';
import { screen, waitFor } from '@testing-library/react';
import { render } from '../../test/utils';
import { FavoritesPage } from '../FavoritesPage';
import { useFileStore } from '../../stores/fileStore';
import { useFavoritesStore } from '../../stores/favoritesStore';
import { invoke } from '@tauri-apps/api/core';

vi.mock('@tauri-apps/api/core', () => ({
  invoke: vi.fn().mockResolvedValue({ items: [] }),
}));

vi.mock('@tauri-apps/plugin-dialog', () => ({
  save: vi.fn(),
}));

vi.mock('../../components/files/RenameDialog', () => ({
  RenameDialog: ({ open }: { open: boolean }) =>
    open ? <div data-testid="rename-dialog" /> : null,
}));

vi.mock('../../components/files/FilePreviewDialog', () => ({
  FilePreviewDialog: ({ open }: { open: boolean }) =>
    open ? <div data-testid="preview-dialog" /> : null,
}));

vi.mock('../../components/sharing/ShareDialog', () => ({
  ShareDialog: ({ open }: { open: boolean }) =>
    open ? <div data-testid="share-dialog" /> : null,
}));

vi.mock('../../components/ui/DropdownMenu', () => ({
  DropdownMenu: ({ children }: { children: React.ReactNode }) => <div>{children}</div>,
  DropdownMenuTrigger: ({ children }: { children: React.ReactNode }) => <div>{children}</div>,
  DropdownMenuContent: ({ children }: { children: React.ReactNode }) => <div>{children}</div>,
  DropdownMenuItem: ({ children, onClick }: { children: React.ReactNode; onClick?: () => void }) => (
    <div onClick={onClick}>{children}</div>
  ),
  DropdownMenuSeparator: () => <hr />,
}));

const mockInvoke = vi.mocked(invoke);

describe('FavoritesPage', () => {
  beforeEach(() => {
    vi.clearAllMocks();
    useFavoritesStore.setState({ favorites: new Set<string>() });
    useFileStore.setState({
      items: [],
      isLoading: false,
      isLoadingPreview: false,
      previewError: null,
      previewFile: null,
    });
    mockInvoke.mockResolvedValue({ items: [] });
  });

  describe('rendering', () => {
    it('should render the page title', () => {
      render(<FavoritesPage />);
      expect(screen.getByText('Favorites')).toBeInTheDocument();
    });

    it('should show empty state when no favorites', () => {
      render(<FavoritesPage />);
      expect(screen.getByText(/no favorites yet/i)).toBeInTheDocument();
    });

    it('should show subtitle text', () => {
      render(<FavoritesPage />);
      expect(screen.getByText(/quick access to your starred files/i)).toBeInTheDocument();
    });
  });

  describe('with favorite items', () => {
    const mockFileItems = [
      {
        id: 'file-1',
        name: 'test-report.pdf',
        item_type: 'file',
        size: 1024,
        mime_type: 'application/pdf',
        folder_id: null,
        owner_id: 'user-1',
        created_at: '2026-01-01T00:00:00Z',
        updated_at: '2026-01-15T00:00:00Z',
        is_shared: false,
        is_received_share: false,
      },
      {
        id: 'folder-1',
        name: 'Project Files',
        item_type: 'folder',
        size: 0,
        mime_type: null,
        folder_id: null,
        owner_id: 'user-1',
        created_at: '2026-01-01T00:00:00Z',
        updated_at: '2026-01-10T00:00:00Z',
        is_shared: true,
        is_received_share: false,
      },
    ];

    it('should not show empty state when favorites exist', () => {
      useFavoritesStore.setState({
        favorites: new Set(['file-1']),
      });

      render(<FavoritesPage />);
      expect(screen.queryByText(/no favorites yet/i)).not.toBeInTheDocument();
    });

    it('should render favorite file items returned by invoke', async () => {
      useFavoritesStore.setState({
        favorites: new Set(['file-1', 'folder-1']),
      });
      mockInvoke.mockResolvedValue({ items: mockFileItems });

      render(<FavoritesPage />);

      await waitFor(() => {
        expect(screen.getByText('test-report.pdf')).toBeInTheDocument();
      });
      expect(screen.getByText('Project Files')).toBeInTheDocument();
    });

    it('should call invoke with list_files to load favorites', async () => {
      useFavoritesStore.setState({
        favorites: new Set(['file-1']),
      });
      mockInvoke.mockResolvedValue({ items: mockFileItems });

      render(<FavoritesPage />);

      await waitFor(() => {
        expect(mockInvoke).toHaveBeenCalledWith('list_files', { folderId: null });
      });
    });

    it('should only display items that are in favorites set', async () => {
      // Only file-1 is favorited, not folder-1
      useFavoritesStore.setState({
        favorites: new Set(['file-1']),
      });
      mockInvoke.mockResolvedValue({ items: mockFileItems });

      render(<FavoritesPage />);

      await waitFor(() => {
        expect(screen.getByText('test-report.pdf')).toBeInTheDocument();
      });
      expect(screen.queryByText('Project Files')).not.toBeInTheDocument();
    });
  });
});
