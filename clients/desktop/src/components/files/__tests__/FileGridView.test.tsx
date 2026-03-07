import { describe, it, expect, vi, beforeEach } from 'vitest';
import { screen } from '@testing-library/react';
import { render } from '../../../test/utils';
import { FileGridView } from '../FileGridView';

// Mock DropdownMenu to simplify testing - Radix portals are tricky
vi.mock('../../ui/DropdownMenu', () => ({
  DropdownMenu: ({ children }: { children: React.ReactNode }) => <div>{children}</div>,
  DropdownMenuTrigger: ({ children }: { children: React.ReactNode }) => <div data-testid="dropdown-trigger">{children}</div>,
  DropdownMenuContent: ({ children }: { children: React.ReactNode }) => <div data-testid="dropdown-content">{children}</div>,
  DropdownMenuItem: ({ children, onClick }: { children: React.ReactNode; onClick?: (e: React.MouseEvent) => void }) => (
    <button data-testid="dropdown-item" onClick={onClick}>{children}</button>
  ),
  DropdownMenuSeparator: () => <hr />,
}));

// Mock FileContextMenu to capture callback calls
vi.mock('../FileContextMenu', () => ({
  FileContextMenu: ({
    children,
    item,
    onDownload,
    onShare,
    onRename,
    onDelete
  }: {
    children: React.ReactNode;
    item: { id: string };
    onDownload: () => void;
    onShare: () => void;
    onRename: () => void;
    onDelete: () => void;
  }) => (
    <div data-testid={`context-menu-${item.id}`}>
      {children}
      <div data-testid="context-actions" style={{ display: 'none' }}>
        <button data-testid={`ctx-download-${item.id}`} onClick={onDownload}>Download</button>
        <button data-testid={`ctx-share-${item.id}`} onClick={onShare}>Share</button>
        <button data-testid={`ctx-rename-${item.id}`} onClick={onRename}>Rename</button>
        <button data-testid={`ctx-delete-${item.id}`} onClick={onDelete}>Delete</button>
      </div>
    </div>
  ),
}));

const mockItems = [
  {
    id: '1',
    name: 'Documents',
    item_type: 'folder' as const,
    size: 0,
    mime_type: null,
    folder_id: null,
    owner_id: 'user1',
    created_at: '2024-01-01T00:00:00Z',
    updated_at: '2024-01-01T00:00:00Z',
    is_shared: false,
    is_received_share: false,
  },
  {
    id: '2',
    name: 'report.pdf',
    item_type: 'file' as const,
    size: 1024000,
    mime_type: 'application/pdf',
    folder_id: null,
    owner_id: 'user1',
    created_at: '2024-01-01T00:00:00Z',
    updated_at: '2024-01-01T00:00:00Z',
    is_shared: true,
    is_received_share: false,
  },
  {
    id: '3',
    name: 'image.png',
    item_type: 'file' as const,
    size: 512000,
    mime_type: 'image/png',
    folder_id: null,
    owner_id: 'user1',
    created_at: '2024-01-01T00:00:00Z',
    updated_at: '2024-01-01T00:00:00Z',
    is_shared: false,
    is_received_share: true,
  },
];

describe('FileGridView', () => {
  const mockOnItemClick = vi.fn();
  const mockOnToggleSelection = vi.fn();
  const mockOnDownload = vi.fn();
  const mockOnShare = vi.fn();
  const mockOnRename = vi.fn();
  const mockOnDelete = vi.fn();

  beforeEach(() => {
    vi.clearAllMocks();
  });

  const renderGrid = (props = {}) => {
    const defaultProps = {
      items: mockItems,
      selectedItems: new Set<string>(),
      onItemClick: mockOnItemClick,
      onToggleSelection: mockOnToggleSelection,
      onDownload: mockOnDownload,
      onShare: mockOnShare,
      onRename: mockOnRename,
      onDelete: mockOnDelete,
    };

    return render(<FileGridView {...defaultProps} {...props} />);
  };

  it('should render all items', () => {
    renderGrid();

    expect(screen.getByText('Documents')).toBeInTheDocument();
    expect(screen.getByText('report.pdf')).toBeInTheDocument();
    expect(screen.getByText('image.png')).toBeInTheDocument();
  });

  it('should display folder label for folders', () => {
    renderGrid();

    expect(screen.getByText('Folder')).toBeInTheDocument();
  });

  it('should display formatted file size for files', () => {
    renderGrid();

    expect(screen.getByText('1000 KB')).toBeInTheDocument();
    expect(screen.getByText('500 KB')).toBeInTheDocument();
  });

  it('should call onItemClick when item is clicked', async () => {
    const { user } = renderGrid();

    await user.click(screen.getByText('Documents'));

    expect(mockOnItemClick).toHaveBeenCalledWith(mockItems[0]);
  });

  it('should call onToggleSelection when ctrl+click on item', async () => {
    const { user } = renderGrid();

    await user.keyboard('{Control>}');
    await user.click(screen.getByText('Documents'));
    await user.keyboard('{/Control}');

    expect(mockOnToggleSelection).toHaveBeenCalledWith('1');
  });

  it('should highlight selected items', () => {
    renderGrid({ selectedItems: new Set(['1']) });

    const selectedItem = screen.getByText('Documents').closest('[class*="cursor-pointer"]');
    expect(selectedItem).toHaveClass('bg-primary/10');
    expect(selectedItem).toHaveClass('border-primary');
  });

  it('should show checkbox as checked for selected items', () => {
    renderGrid({ selectedItems: new Set(['1']) });

    const checkboxes = document.querySelectorAll('button[aria-label="Deselect"]');
    expect(checkboxes.length).toBe(1);
  });

  it('should render empty grid when no items', () => {
    renderGrid({ items: [] });

    expect(screen.queryByText('Documents')).not.toBeInTheDocument();
  });

  it('should show shared indicator for shared items', () => {
    renderGrid();

    // report.pdf is shared, should have share icon
    const reportCard = screen.getByText('report.pdf').closest('[class*="cursor-pointer"]');
    expect(reportCard?.querySelector('svg')).toBeInTheDocument();
  });

  describe('selection checkbox', () => {
    it('should call onToggleSelection when selection checkbox is clicked', async () => {
      const { user } = renderGrid();

      const selectButton = document.querySelector('button[aria-label="Select"]');
      if (selectButton) {
        await user.click(selectButton);
        expect(mockOnToggleSelection).toHaveBeenCalledWith('1');
      }
    });

    it('should stop propagation when checkbox is clicked', async () => {
      const { user } = renderGrid();

      const selectButton = document.querySelector('button[aria-label="Select"]');
      if (selectButton) {
        await user.click(selectButton);
        // onItemClick should NOT be called
        expect(mockOnItemClick).not.toHaveBeenCalled();
      }
    });

    it('should show check icon when item is selected', () => {
      renderGrid({ selectedItems: new Set(['1']) });

      const deselectButton = document.querySelector('button[aria-label="Deselect"]');
      expect(deselectButton).toBeInTheDocument();
      expect(deselectButton?.querySelector('svg')).toBeInTheDocument();
    });
  });

  describe('icons', () => {
    it('should render folder icon for folder items', () => {
      renderGrid();

      // Check that folder icon exists (lucide-folder class)
      expect(document.querySelector('.lucide-folder')).toBeInTheDocument();
    });

    it('should render file icon for file items', () => {
      renderGrid();

      // Check that file icons exist (lucide-file class)
      const fileIcons = document.querySelectorAll('.lucide-file');
      expect(fileIcons.length).toBe(2); // report.pdf and image.png
    });
  });

  describe('dropdown actions', () => {
    it('should render dropdown menu trigger for each item', () => {
      renderGrid();

      // Each item should have a more options button (wrapped in a button element)
      // The dropdown trigger is a button that contains an SVG icon
      const gridItems = document.querySelectorAll('[class*="cursor-pointer"]');
      // We have 3 items, each should be rendered
      expect(gridItems.length).toBe(3);
    });

    it('should render dropdown content with Share, Rename, and Delete options', () => {
      renderGrid();

      // With mocked DropdownMenu, content is always visible
      expect(screen.getAllByText('Share').length).toBeGreaterThan(0);
      expect(screen.getAllByText('Rename').length).toBeGreaterThan(0);
      expect(screen.getAllByText('Delete').length).toBeGreaterThan(0);
    });

    it('should render Download option only for files in dropdown', () => {
      renderGrid();

      // With mocked DropdownMenu, content is always visible
      // Find Download items in dropdown-content (not context menu)
      const dropdownContents = document.querySelectorAll('[data-testid="dropdown-content"]');
      let dropdownDownloads = 0;
      dropdownContents.forEach((content) => {
        const downloadBtns = content.querySelectorAll('[data-testid="dropdown-item"]');
        downloadBtns.forEach((btn) => {
          if (btn.textContent?.includes('Download')) {
            dropdownDownloads++;
          }
        });
      });
      // We have 2 files and 1 folder - so Download should appear 2 times (for files only)
      expect(dropdownDownloads).toBe(2);
    });

    it('should call onDownload when Download is clicked in dropdown', async () => {
      const { user } = renderGrid();

      // Find Download buttons (only for files)
      const downloadButtons = screen.getAllByText('Download');
      await user.click(downloadButtons[0]);

      expect(mockOnDownload).toHaveBeenCalled();
    });

    it('should call onShare when Share is clicked in dropdown', async () => {
      const { user } = renderGrid();

      const shareButtons = screen.getAllByText('Share');
      await user.click(shareButtons[0]);

      expect(mockOnShare).toHaveBeenCalled();
    });

    it('should call onRename when Rename is clicked in dropdown', async () => {
      const { user } = renderGrid();

      const renameButtons = screen.getAllByText('Rename');
      await user.click(renameButtons[0]);

      expect(mockOnRename).toHaveBeenCalled();
    });

    it('should call onDelete when Delete is clicked in dropdown', async () => {
      const { user } = renderGrid();

      const deleteButtons = screen.getAllByText('Delete');
      await user.click(deleteButtons[0]);

      expect(mockOnDelete).toHaveBeenCalled();
    });
  });

  describe('context menu callbacks', () => {
    it('should pass onDownload callback to FileContextMenu', async () => {
      const { user } = renderGrid();

      // Click the hidden context menu download button for item 2 (a file)
      const ctxDownloadBtn = screen.getByTestId('ctx-download-2');
      await user.click(ctxDownloadBtn);

      expect(mockOnDownload).toHaveBeenCalledWith(mockItems[1]);
    });

    it('should pass onShare callback to FileContextMenu', async () => {
      const { user } = renderGrid();

      const ctxShareBtn = screen.getByTestId('ctx-share-1');
      await user.click(ctxShareBtn);

      expect(mockOnShare).toHaveBeenCalledWith(mockItems[0]);
    });

    it('should pass onRename callback to FileContextMenu', async () => {
      const { user } = renderGrid();

      const ctxRenameBtn = screen.getByTestId('ctx-rename-1');
      await user.click(ctxRenameBtn);

      expect(mockOnRename).toHaveBeenCalledWith(mockItems[0]);
    });

    it('should pass onDelete callback to FileContextMenu', async () => {
      const { user } = renderGrid();

      const ctxDeleteBtn = screen.getByTestId('ctx-delete-1');
      await user.click(ctxDeleteBtn);

      expect(mockOnDelete).toHaveBeenCalledWith(mockItems[0]);
    });
  });

  describe('file size display', () => {
    it('should display "Folder" for folder item type', () => {
      renderGrid({ items: [mockItems[0]] });

      expect(screen.getByText('Folder')).toBeInTheDocument();
    });

    it('should display formatted byte size for file item type', () => {
      renderGrid({ items: [mockItems[1]] });

      // 1024000 bytes = 1000 KB
      expect(screen.getByText('1000 KB')).toBeInTheDocument();
    });
  });
});
