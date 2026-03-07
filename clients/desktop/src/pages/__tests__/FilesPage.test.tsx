import { describe, it, expect, vi, beforeEach } from 'vitest';
import { screen, fireEvent, waitFor } from '@testing-library/react';
import { render } from '../../test/utils';
import { FilesPage } from '../FilesPage';
import { useFileStore } from '../../stores/fileStore';

// Mock Tauri dialog
vi.mock('@tauri-apps/plugin-dialog', () => ({
  open: vi.fn(),
  save: vi.fn(),
}));

// Mock child components to simplify tests
vi.mock('../../components/files/CreateFolderDialog', () => ({
  CreateFolderDialog: ({ open, onOpenChange }: { open: boolean; onOpenChange: (open: boolean) => void }) =>
    open ? <div data-testid="create-folder-dialog"><button onClick={() => onOpenChange(false)}>Close</button></div> : null,
}));

vi.mock('../../components/files/RenameDialog', () => ({
  RenameDialog: ({ open }: { open: boolean }) =>
    open ? <div data-testid="rename-dialog">Rename Dialog</div> : null,
}));

vi.mock('../../components/sharing/ShareDialog', () => ({
  ShareDialog: ({ open }: { open: boolean }) =>
    open ? <div data-testid="share-dialog">Share Dialog</div> : null,
}));

vi.mock('../../components/files/FilePreviewDialog', () => ({
  FilePreviewDialog: ({ open }: { open: boolean }) =>
    open ? <div data-testid="preview-dialog">Preview Dialog</div> : null,
}));

vi.mock('../../components/files/UploadProgressIndicator', () => ({
  UploadProgressIndicator: () => <div data-testid="upload-progress">Upload Progress</div>,
}));

vi.mock('../../components/files/DownloadProgressIndicator', () => ({
  DownloadProgressIndicator: () => <div data-testid="download-progress">Download Progress</div>,
}));

vi.mock('../../components/files/DropZoneOverlay', () => ({
  DropZoneOverlay: ({ isVisible }: { isVisible: boolean }) =>
    isVisible ? <div data-testid="drop-zone-overlay">Drop Zone</div> : null,
}));

vi.mock('../../components/files/FileFilters', () => ({
  FileFilters: () => <div data-testid="file-filters">File Filters</div>,
}));

vi.mock('../../components/files/FileContextMenu', () => ({
  FileContextMenu: ({ children }: { children: React.ReactNode }) => <>{children}</>,
}));

vi.mock('../../components/files/FileGridView', () => ({
  FileGridView: ({ items, onItemClick }: { items: unknown[]; onItemClick: (item: unknown) => void }) => (
    <div data-testid="file-grid-view">
      {(items as { id: string; name: string }[]).map((item) => (
        <div key={item.id} data-testid={`grid-item-${item.id}`} onClick={() => onItemClick(item)}>
          {item.name}
        </div>
      ))}
    </div>
  ),
}));

vi.mock('../../components/files/FileListSkeleton', () => ({
  FileListSkeleton: () => <div data-testid="file-list-skeleton">Loading...</div>,
  FileGridSkeleton: () => <div data-testid="file-grid-skeleton">Loading...</div>,
}));

vi.mock('../../components/common/KeyboardShortcutsDialog', () => ({
  KeyboardShortcutsDialog: () => null,
}));

// Mock DropdownMenu to simplify testing - Radix portals are tricky
vi.mock('../../components/ui/DropdownMenu', () => ({
  DropdownMenu: ({ children }: { children: React.ReactNode }) => <div>{children}</div>,
  DropdownMenuTrigger: ({ children }: { children: React.ReactNode }) => <div>{children}</div>,
  DropdownMenuContent: ({ children }: { children: React.ReactNode }) => <div data-testid="dropdown-content">{children}</div>,
  DropdownMenuItem: ({ children, onClick }: { children: React.ReactNode; onClick?: (e: React.MouseEvent) => void }) => (
    <button data-testid="dropdown-item" onClick={onClick}>{children}</button>
  ),
  DropdownMenuSeparator: () => <hr />,
}));

// Store the original store functions
const originalGetFilteredItems = useFileStore.getState().getFilteredItems;

describe('FilesPage', () => {
  beforeEach(() => {
    vi.clearAllMocks();

    // Reset file store to initial state with no items (loading shows)
    // Mock loadFiles to prevent it from calling the API and resetting state
    useFileStore.setState({
      items: [],
      currentFolder: null,
      breadcrumbs: [],
      isLoading: true,
      error: null,
      previewFile: null,
      isLoadingPreview: false,
      previewError: null,
      uploadProgress: new Map(),
      downloadProgress: new Map(),
      searchQuery: '',
      filters: { type: 'all', sharedStatus: 'all' },
      sortBy: 'name',
      sortOrder: 'asc',
      selectedItems: new Set<string>(),
      viewMode: 'list',
      getFilteredItems: originalGetFilteredItems,
      loadFiles: vi.fn(), // Mock to prevent API calls
    });
  });

  describe('page header', () => {
    it('should render upload button', () => {
      render(<FilesPage />);
      expect(screen.getByRole('button', { name: /upload/i })).toBeInTheDocument();
    });

    it('should render new folder button', () => {
      render(<FilesPage />);
      expect(screen.getByRole('button', { name: /new folder/i })).toBeInTheDocument();
    });

    it('should render view mode toggle buttons', () => {
      render(<FilesPage />);
      expect(screen.getByRole('button', { name: /grid view/i })).toBeInTheDocument();
      expect(screen.getByRole('button', { name: /list view/i })).toBeInTheDocument();
    });
  });

  describe('loading state', () => {
    it('should show skeleton when loading', () => {
      useFileStore.setState({ isLoading: true, items: [] });
      render(<FilesPage />);
      expect(screen.getByTestId('file-list-skeleton')).toBeInTheDocument();
    });

    it('should show grid skeleton when loading in grid mode', () => {
      useFileStore.setState({ isLoading: true, items: [], viewMode: 'grid' });
      render(<FilesPage />);
      expect(screen.getByTestId('file-grid-skeleton')).toBeInTheDocument();
    });
  });

  describe('dialogs', () => {
    it('should open create folder dialog when clicking New Folder', async () => {
      render(<FilesPage />);

      fireEvent.click(screen.getByRole('button', { name: /new folder/i }));

      await waitFor(() => {
        expect(screen.getByTestId('create-folder-dialog')).toBeInTheDocument();
      });
    });
  });

  describe('view mode toggle', () => {
    it('should switch to grid view when clicking grid button', () => {
      const setViewMode = vi.fn();
      useFileStore.setState({ setViewMode });

      render(<FilesPage />);
      fireEvent.click(screen.getByRole('button', { name: /grid view/i }));

      expect(setViewMode).toHaveBeenCalledWith('grid');
    });

    it('should switch to list view when clicking list button', () => {
      const setViewMode = vi.fn();
      useFileStore.setState({ viewMode: 'grid', setViewMode });

      render(<FilesPage />);
      fireEvent.click(screen.getByRole('button', { name: /list view/i }));

      expect(setViewMode).toHaveBeenCalledWith('list');
    });
  });

  describe('file filters', () => {
    it('should render file filters component', () => {
      render(<FilesPage />);
      expect(screen.getByTestId('file-filters')).toBeInTheDocument();
    });
  });

  describe('progress indicators', () => {
    it('should render upload progress indicator', () => {
      render(<FilesPage />);
      expect(screen.getByTestId('upload-progress')).toBeInTheDocument();
    });

    it('should render download progress indicator', () => {
      render(<FilesPage />);
      expect(screen.getByTestId('download-progress')).toBeInTheDocument();
    });
  });

  describe('empty state', () => {
    it('should show empty state when no files', () => {
      useFileStore.setState({
        isLoading: false,
        items: [],
      });
      render(<FilesPage />);
      expect(screen.getByText('No files yet')).toBeInTheDocument();
      expect(screen.getByText('Upload files or create a folder to get started')).toBeInTheDocument();
    });
  });

  describe('error state', () => {
    it('should display error banner when error exists', () => {
      useFileStore.setState({
        isLoading: false,
        items: [],
        error: 'Failed to load files',
      });
      render(<FilesPage />);
      expect(screen.getByText('Failed to load files')).toBeInTheDocument();
    });

    it('should show dismiss button with error', () => {
      useFileStore.setState({
        isLoading: false,
        items: [],
        error: 'Some error',
      });
      render(<FilesPage />);
      expect(screen.getByRole('button', { name: /dismiss/i })).toBeInTheDocument();
    });

    it('should call clearError when dismiss is clicked', () => {
      const clearError = vi.fn();
      useFileStore.setState({
        isLoading: false,
        items: [],
        error: 'Some error',
        clearError,
      });
      render(<FilesPage />);
      fireEvent.click(screen.getByRole('button', { name: /dismiss/i }));
      expect(clearError).toHaveBeenCalled();
    });
  });

  describe('page title', () => {
    it('should show My Files as default title', () => {
      useFileStore.setState({
        isLoading: false,
        items: [],
        currentFolder: null,
      });
      render(<FilesPage />);
      // Use heading role to be specific since "My Files" appears in breadcrumb too
      expect(screen.getByRole('heading', { name: 'My Files' })).toBeInTheDocument();
    });

    it('should show folder name when in a folder', () => {
      useFileStore.setState({
        isLoading: false,
        items: [],
        currentFolder: { id: 'folder-1', name: 'Documents' },
      });
      render(<FilesPage />);
      expect(screen.getByText('Documents')).toBeInTheDocument();
    });
  });

  describe('breadcrumbs', () => {
    it('should render breadcrumb navigation', () => {
      useFileStore.setState({
        isLoading: false,
        items: [],
        breadcrumbs: [
          { id: 'folder-1', name: 'Documents' },
          { id: 'folder-2', name: 'Work' },
        ],
      });
      render(<FilesPage />);
      expect(screen.getByText('Documents')).toBeInTheDocument();
      expect(screen.getByText('Work')).toBeInTheDocument();
    });
  });

  describe('grid view', () => {
    it('should render file grid view when viewMode is grid', () => {
      useFileStore.setState({
        isLoading: false,
        viewMode: 'grid',
        items: [
          {
            id: 'file-1',
            name: 'test.txt',
            item_type: 'file',
            size: 100,
            mime_type: 'text/plain',
            folder_id: null,
            owner_id: 'user-1',
            created_at: '2024-01-01',
            updated_at: '2024-01-01',
            is_shared: false,
            is_received_share: false,
          },
        ],
      });
      render(<FilesPage />);
      expect(screen.getByTestId('file-grid-view')).toBeInTheDocument();
    });
  });

  describe('list view', () => {
    const mockItems = [
      {
        id: 'file-1',
        name: 'document.pdf',
        item_type: 'file' as const,
        size: 1024,
        mime_type: 'application/pdf',
        folder_id: null,
        owner_id: 'user-1',
        created_at: '2024-01-01T00:00:00Z',
        updated_at: '2024-01-01T00:00:00Z',
        is_shared: true,
        is_received_share: false,
      },
      {
        id: 'folder-1',
        name: 'My Folder',
        item_type: 'folder' as const,
        size: 0,
        mime_type: null,
        folder_id: null,
        owner_id: 'user-1',
        created_at: '2024-01-01T00:00:00Z',
        updated_at: '2024-01-01T00:00:00Z',
        is_shared: false,
        is_received_share: false,
      },
    ];

    it('should render list view table when viewMode is list', () => {
      useFileStore.setState({
        isLoading: false,
        viewMode: 'list',
        items: mockItems,
      });
      render(<FilesPage />);
      expect(screen.getByText('Name')).toBeInTheDocument();
      expect(screen.getByText('Size')).toBeInTheDocument();
      expect(screen.getByText('Modified')).toBeInTheDocument();
    });

    it('should display file names in list view', () => {
      useFileStore.setState({
        isLoading: false,
        viewMode: 'list',
        items: mockItems,
      });
      render(<FilesPage />);
      expect(screen.getByText('document.pdf')).toBeInTheDocument();
      expect(screen.getByText('My Folder')).toBeInTheDocument();
    });

    it('should show file icon for files', () => {
      useFileStore.setState({
        isLoading: false,
        viewMode: 'list',
        items: [mockItems[0]],
      });
      render(<FilesPage />);
      expect(document.querySelector('.lucide-file')).toBeInTheDocument();
    });

    it('should show folder icon for folders', () => {
      useFileStore.setState({
        isLoading: false,
        viewMode: 'list',
        items: [mockItems[1]],
      });
      render(<FilesPage />);
      expect(document.querySelector('.lucide-folder')).toBeInTheDocument();
    });

    it('should show share icon for shared items', () => {
      useFileStore.setState({
        isLoading: false,
        viewMode: 'list',
        items: [mockItems[0]], // document.pdf is shared
      });
      render(<FilesPage />);
      expect(document.querySelector('.lucide-share2')).toBeInTheDocument();
    });

    it('should call setSorting when clicking Name header', () => {
      const setSorting = vi.fn();
      useFileStore.setState({
        isLoading: false,
        viewMode: 'list',
        items: mockItems,
        setSorting,
      });
      render(<FilesPage />);
      fireEvent.click(screen.getByText('Name'));
      expect(setSorting).toHaveBeenCalledWith('name');
    });

    it('should call setSorting when clicking Size header', () => {
      const setSorting = vi.fn();
      useFileStore.setState({
        isLoading: false,
        viewMode: 'list',
        items: mockItems,
        setSorting,
      });
      render(<FilesPage />);
      fireEvent.click(screen.getByText('Size'));
      expect(setSorting).toHaveBeenCalledWith('size');
    });

    it('should call setSorting when clicking Modified header', () => {
      const setSorting = vi.fn();
      useFileStore.setState({
        isLoading: false,
        viewMode: 'list',
        items: mockItems,
        setSorting,
      });
      render(<FilesPage />);
      fireEvent.click(screen.getByText('Modified'));
      expect(setSorting).toHaveBeenCalledWith('updated_at');
    });

    it('should show sort direction indicator', () => {
      useFileStore.setState({
        isLoading: false,
        viewMode: 'list',
        items: mockItems,
        sortBy: 'name',
        sortOrder: 'asc',
      });
      render(<FilesPage />);
      expect(document.querySelector('.lucide-chevron-up')).toBeInTheDocument();
    });

    it('should show descending sort indicator', () => {
      useFileStore.setState({
        isLoading: false,
        viewMode: 'list',
        items: mockItems,
        sortBy: 'name',
        sortOrder: 'desc',
      });
      render(<FilesPage />);
      expect(document.querySelector('.lucide-chevron-down')).toBeInTheDocument();
    });
  });

  describe('selection', () => {
    const mockItems = [
      {
        id: 'file-1',
        name: 'document.pdf',
        item_type: 'file' as const,
        size: 1024,
        mime_type: 'application/pdf',
        folder_id: null,
        owner_id: 'user-1',
        created_at: '2024-01-01T00:00:00Z',
        updated_at: '2024-01-01T00:00:00Z',
        is_shared: false,
        is_received_share: false,
      },
    ];

    it('should call toggleSelection when clicking selection checkbox', () => {
      const toggleSelection = vi.fn();
      useFileStore.setState({
        isLoading: false,
        viewMode: 'list',
        items: mockItems,
        selectedItems: new Set<string>(),
        toggleSelection,
      });
      render(<FilesPage />);

      const selectButton = screen.getByRole('button', { name: /select$/i });
      fireEvent.click(selectButton);
      expect(toggleSelection).toHaveBeenCalledWith('file-1');
    });

    it('should show check icon when item is selected', () => {
      useFileStore.setState({
        isLoading: false,
        viewMode: 'list',
        items: mockItems,
        selectedItems: new Set(['file-1']),
      });
      render(<FilesPage />);

      const deselectButton = screen.getByRole('button', { name: /deselect$/i });
      expect(deselectButton.querySelector('.lucide-check')).toBeInTheDocument();
    });

    it('should call selectAll when clicking select all checkbox', () => {
      const selectAll = vi.fn();
      useFileStore.setState({
        isLoading: false,
        viewMode: 'list',
        items: mockItems,
        selectedItems: new Set<string>(),
        selectAll,
      });
      render(<FilesPage />);

      const selectAllButton = screen.getByRole('button', { name: /select all/i });
      fireEvent.click(selectAllButton);
      expect(selectAll).toHaveBeenCalled();
    });

    it('should call clearSelection when all items selected and clicking select all', () => {
      const clearSelection = vi.fn();
      useFileStore.setState({
        isLoading: false,
        viewMode: 'list',
        items: mockItems,
        selectedItems: new Set(['file-1']),
        clearSelection,
      });
      render(<FilesPage />);

      const deselectAllButton = screen.getByRole('button', { name: /deselect all/i });
      fireEvent.click(deselectAllButton);
      expect(clearSelection).toHaveBeenCalled();
    });

    it('should highlight selected rows', () => {
      useFileStore.setState({
        isLoading: false,
        viewMode: 'list',
        items: mockItems,
        selectedItems: new Set(['file-1']),
      });
      render(<FilesPage />);

      const row = screen.getByText('document.pdf').closest('tr');
      expect(row).toHaveClass('bg-primary/10');
    });
  });

  describe('delete dialog', () => {
    const mockItems = [
      {
        id: 'file-1',
        name: 'document.pdf',
        item_type: 'file' as const,
        size: 1024,
        mime_type: 'application/pdf',
        folder_id: null,
        owner_id: 'user-1',
        created_at: '2024-01-01T00:00:00Z',
        updated_at: '2024-01-01T00:00:00Z',
        is_shared: false,
        is_received_share: false,
      },
    ];

    it('should show delete dialog title', async () => {
      useFileStore.setState({
        isLoading: false,
        viewMode: 'list',
        items: mockItems,
        selectedItems: new Set<string>(),
      });

      const { user } = render(<FilesPage />);

      // Open dropdown menu
      const moreButton = document.querySelector('.lucide-more-vertical')?.closest('button');
      if (moreButton) {
        await user.click(moreButton);

        // Wait for dropdown and click Delete
        await waitFor(() => {
          expect(screen.getByText('Delete')).toBeInTheDocument();
        });

        await user.click(screen.getByText('Delete'));

        // Check dialog opens
        await waitFor(() => {
          expect(screen.getByText('Delete File')).toBeInTheDocument();
        });
      }
    });
  });

  describe('file list calls loadFiles', () => {
    it('should call loadFiles on mount', () => {
      const loadFiles = vi.fn();
      useFileStore.setState({
        isLoading: true,
        items: [],
        loadFiles,
      });
      render(<FilesPage />);
      expect(loadFiles).toHaveBeenCalledWith(null);
    });
  });

  describe('dropdown menu actions', () => {
    const mockItems = [
      {
        id: 'file-1',
        name: 'document.pdf',
        item_type: 'file' as const,
        size: 1024,
        mime_type: 'application/pdf',
        folder_id: null,
        owner_id: 'user-1',
        created_at: '2024-01-01T00:00:00Z',
        updated_at: '2024-01-01T00:00:00Z',
        is_shared: false,
        is_received_share: false,
      },
      {
        id: 'folder-1',
        name: 'My Folder',
        item_type: 'folder' as const,
        size: 0,
        mime_type: null,
        folder_id: null,
        owner_id: 'user-1',
        created_at: '2024-01-01T00:00:00Z',
        updated_at: '2024-01-01T00:00:00Z',
        is_shared: false,
        is_received_share: false,
      },
    ];

    it('should show Download option for files in dropdown', async () => {
      useFileStore.setState({
        isLoading: false,
        viewMode: 'list',
        items: [mockItems[0]],
        selectedItems: new Set<string>(),
      });

      const { user } = render(<FilesPage />);

      const moreButton = document.querySelector('.lucide-more-vertical')?.closest('button');
      await user.click(moreButton!);

      await waitFor(() => {
        expect(screen.getByText('Download')).toBeInTheDocument();
      });
    });

    it('should not show Download option for folders in dropdown', async () => {
      useFileStore.setState({
        isLoading: false,
        viewMode: 'list',
        items: [mockItems[1]],
        selectedItems: new Set<string>(),
      });

      const { user } = render(<FilesPage />);

      const moreButton = document.querySelector('.lucide-more-vertical')?.closest('button');
      await user.click(moreButton!);

      await waitFor(() => {
        expect(screen.getByText('Share')).toBeInTheDocument();
      });
      expect(screen.queryByText('Download')).not.toBeInTheDocument();
    });

    it('should show Share option in dropdown', async () => {
      useFileStore.setState({
        isLoading: false,
        viewMode: 'list',
        items: [mockItems[0]],
        selectedItems: new Set<string>(),
      });

      const { user } = render(<FilesPage />);

      const moreButton = document.querySelector('.lucide-more-vertical')?.closest('button');
      await user.click(moreButton!);

      await waitFor(() => {
        expect(screen.getByText('Share')).toBeInTheDocument();
      });
    });

    it('should show Rename option in dropdown', async () => {
      useFileStore.setState({
        isLoading: false,
        viewMode: 'list',
        items: [mockItems[0]],
        selectedItems: new Set<string>(),
      });

      const { user } = render(<FilesPage />);

      const moreButton = document.querySelector('.lucide-more-vertical')?.closest('button');
      await user.click(moreButton!);

      await waitFor(() => {
        expect(screen.getByText('Rename')).toBeInTheDocument();
      });
    });

    it('should open share dialog when clicking Share in dropdown', async () => {
      useFileStore.setState({
        isLoading: false,
        viewMode: 'list',
        items: [mockItems[0]],
        selectedItems: new Set<string>(),
      });

      const { user } = render(<FilesPage />);

      const moreButton = document.querySelector('.lucide-more-vertical')?.closest('button');
      await user.click(moreButton!);

      await waitFor(() => {
        expect(screen.getByText('Share')).toBeInTheDocument();
      });

      await user.click(screen.getByText('Share'));

      await waitFor(() => {
        expect(screen.getByTestId('share-dialog')).toBeInTheDocument();
      });
    });

    it('should open rename dialog when clicking Rename in dropdown', async () => {
      useFileStore.setState({
        isLoading: false,
        viewMode: 'list',
        items: [mockItems[0]],
        selectedItems: new Set<string>(),
      });

      const { user } = render(<FilesPage />);

      const moreButton = document.querySelector('.lucide-more-vertical')?.closest('button');
      await user.click(moreButton!);

      await waitFor(() => {
        expect(screen.getByText('Rename')).toBeInTheDocument();
      });

      await user.click(screen.getByText('Rename'));

      await waitFor(() => {
        expect(screen.getByTestId('rename-dialog')).toBeInTheDocument();
      });
    });
  });

  describe('row click behavior', () => {
    const mockItems = [
      {
        id: 'file-1',
        name: 'document.pdf',
        item_type: 'file' as const,
        size: 1024,
        mime_type: 'application/pdf',
        folder_id: null,
        owner_id: 'user-1',
        created_at: '2024-01-01T00:00:00Z',
        updated_at: '2024-01-01T00:00:00Z',
        is_shared: false,
        is_received_share: false,
      },
    ];

    it('should call loadPreview when clicking on a file row', () => {
      const loadPreview = vi.fn();
      useFileStore.setState({
        isLoading: false,
        viewMode: 'list',
        items: mockItems,
        selectedItems: new Set<string>(),
        loadPreview,
      });

      render(<FilesPage />);

      const row = screen.getByText('document.pdf').closest('tr');
      fireEvent.click(row!);

      expect(loadPreview).toHaveBeenCalledWith('file-1');
    });

    it('should toggle selection when ctrl+clicking a row', () => {
      const toggleSelection = vi.fn();
      useFileStore.setState({
        isLoading: false,
        viewMode: 'list',
        items: mockItems,
        selectedItems: new Set<string>(),
        toggleSelection,
      });

      render(<FilesPage />);

      const row = screen.getByText('document.pdf').closest('tr');
      fireEvent.click(row!, { ctrlKey: true });

      expect(toggleSelection).toHaveBeenCalledWith('file-1');
    });

    it('should toggle selection when meta+clicking a row (Mac)', () => {
      const toggleSelection = vi.fn();
      useFileStore.setState({
        isLoading: false,
        viewMode: 'list',
        items: mockItems,
        selectedItems: new Set<string>(),
        toggleSelection,
      });

      render(<FilesPage />);

      const row = screen.getByText('document.pdf').closest('tr');
      fireEvent.click(row!, { metaKey: true });

      expect(toggleSelection).toHaveBeenCalledWith('file-1');
    });
  });

  describe('delete confirmation flow', () => {
    const mockItems = [
      {
        id: 'file-1',
        name: 'document.pdf',
        item_type: 'file' as const,
        size: 1024,
        mime_type: 'application/pdf',
        folder_id: null,
        owner_id: 'user-1',
        created_at: '2024-01-01T00:00:00Z',
        updated_at: '2024-01-01T00:00:00Z',
        is_shared: false,
        is_received_share: false,
      },
      {
        id: 'folder-1',
        name: 'My Folder',
        item_type: 'folder' as const,
        size: 0,
        mime_type: null,
        folder_id: null,
        owner_id: 'user-1',
        created_at: '2024-01-01T00:00:00Z',
        updated_at: '2024-01-01T00:00:00Z',
        is_shared: false,
        is_received_share: false,
      },
    ];

    it('should show folder delete dialog with folder-specific text', async () => {
      useFileStore.setState({
        isLoading: false,
        viewMode: 'list',
        items: [mockItems[1]],
        selectedItems: new Set<string>(),
      });

      const { user } = render(<FilesPage />);

      const moreButton = document.querySelector('.lucide-more-vertical')?.closest('button');
      await user.click(moreButton!);

      await waitFor(() => {
        expect(screen.getByText('Delete')).toBeInTheDocument();
      });

      await user.click(screen.getByText('Delete'));

      await waitFor(() => {
        expect(screen.getByText('Delete Folder')).toBeInTheDocument();
        expect(screen.getByText(/This will also delete all contents/)).toBeInTheDocument();
      });
    });

    it('should show item name in delete confirmation', async () => {
      // Use single item to avoid multiple "Delete" buttons
      useFileStore.setState({
        isLoading: false,
        viewMode: 'list',
        items: [mockItems[0]],
        selectedItems: new Set<string>(),
      });

      const { user } = render(<FilesPage />);

      // With mocked dropdown, content is always visible - find the Delete button directly
      const deleteButtons = screen.getAllByText('Delete');
      // Find the one in the dropdown (has no special role since it's a button styled as menu item)
      const dropdownDeleteButton = deleteButtons.find(btn => btn.closest('[data-testid="dropdown-item"]'));
      await user.click(dropdownDeleteButton!);

      // Wait for dialog to open - check for dialog description containing the filename
      await waitFor(() => {
        const dialogDescription = screen.getByText(/Are you sure you want to delete/);
        expect(dialogDescription).toHaveTextContent('document.pdf');
      });
    });

    it('should close delete dialog when clicking Cancel', async () => {
      useFileStore.setState({
        isLoading: false,
        viewMode: 'list',
        items: [mockItems[0]],
        selectedItems: new Set<string>(),
      });

      const { user } = render(<FilesPage />);

      // With mocked dropdown, content is always visible
      const deleteButtons = screen.getAllByText('Delete');
      const dropdownDeleteButton = deleteButtons.find(btn => btn.closest('[data-testid="dropdown-item"]'));
      await user.click(dropdownDeleteButton!);

      await waitFor(() => {
        expect(screen.getByText('Delete File')).toBeInTheDocument();
      });

      await user.click(screen.getByRole('button', { name: /cancel/i }));

      await waitFor(() => {
        expect(screen.queryByText('Delete File')).not.toBeInTheDocument();
      });
    });

    it('should call deleteItem when confirming delete', async () => {
      const deleteItem = vi.fn().mockResolvedValue(undefined);
      useFileStore.setState({
        isLoading: false,
        viewMode: 'list',
        items: [mockItems[0]],
        selectedItems: new Set<string>(),
        deleteItem,
      });

      const { user } = render(<FilesPage />);

      // With mocked dropdown, content is always visible
      const deleteButtons = screen.getAllByText('Delete');
      const dropdownDeleteButton = deleteButtons.find(btn => btn.closest('[data-testid="dropdown-item"]'));
      await user.click(dropdownDeleteButton!);

      await waitFor(() => {
        expect(screen.getByRole('button', { name: /^delete$/i })).toBeInTheDocument();
      });

      await user.click(screen.getByRole('button', { name: /^delete$/i }));

      await waitFor(() => {
        expect(deleteItem).toHaveBeenCalledWith('file-1');
      });
    });

    it('should show loading state on Delete button during deletion', async () => {
      const deleteItem = vi.fn().mockImplementation(
        () => new Promise((resolve) => setTimeout(resolve, 1000))
      );
      useFileStore.setState({
        isLoading: false,
        viewMode: 'list',
        items: [mockItems[0]],
        selectedItems: new Set<string>(),
        deleteItem,
      });

      const { user } = render(<FilesPage />);

      // With mocked dropdown, content is always visible
      const deleteButtons = screen.getAllByText('Delete');
      const dropdownDeleteButton = deleteButtons.find(btn => btn.closest('[data-testid="dropdown-item"]'));
      await user.click(dropdownDeleteButton!);

      await waitFor(() => {
        expect(screen.getByRole('button', { name: /^delete$/i })).toBeInTheDocument();
      });

      const deleteButton = screen.getByRole('button', { name: /^delete$/i });
      await user.click(deleteButton);

      await waitFor(() => {
        expect(deleteButton).toBeDisabled();
      });
    });
  });

  describe('sort direction indicators', () => {
    const mockItems = [
      {
        id: 'file-1',
        name: 'document.pdf',
        item_type: 'file' as const,
        size: 1024,
        mime_type: 'application/pdf',
        folder_id: null,
        owner_id: 'user-1',
        created_at: '2024-01-01T00:00:00Z',
        updated_at: '2024-01-01T00:00:00Z',
        is_shared: false,
        is_received_share: false,
      },
    ];

    it('should show sort indicator for size column', () => {
      useFileStore.setState({
        isLoading: false,
        viewMode: 'list',
        items: mockItems,
        sortBy: 'size',
        sortOrder: 'asc',
      });
      render(<FilesPage />);
      expect(document.querySelector('.lucide-chevron-up')).toBeInTheDocument();
    });

    it('should show sort indicator for updated_at column', () => {
      useFileStore.setState({
        isLoading: false,
        viewMode: 'list',
        items: mockItems,
        sortBy: 'updated_at',
        sortOrder: 'desc',
      });
      render(<FilesPage />);
      expect(document.querySelector('.lucide-chevron-down')).toBeInTheDocument();
    });
  });

  describe('select all checkbox', () => {
    const mockItems = [
      {
        id: 'file-1',
        name: 'document.pdf',
        item_type: 'file' as const,
        size: 1024,
        mime_type: 'application/pdf',
        folder_id: null,
        owner_id: 'user-1',
        created_at: '2024-01-01T00:00:00Z',
        updated_at: '2024-01-01T00:00:00Z',
        is_shared: false,
        is_received_share: false,
      },
    ];

    it('should show check icon when all items are selected', () => {
      useFileStore.setState({
        isLoading: false,
        viewMode: 'list',
        items: mockItems,
        selectedItems: new Set(['file-1']),
      });
      render(<FilesPage />);

      const selectAllButton = screen.getByRole('button', { name: /deselect all/i });
      expect(selectAllButton.querySelector('.lucide-check')).toBeInTheDocument();
    });

    it('should not show check icon when no items are selected', () => {
      useFileStore.setState({
        isLoading: false,
        viewMode: 'list',
        items: mockItems,
        selectedItems: new Set<string>(),
      });
      render(<FilesPage />);

      const selectAllButton = screen.getByRole('button', { name: /select all/i });
      expect(selectAllButton.querySelector('.lucide-check')).not.toBeInTheDocument();
    });
  });
});
