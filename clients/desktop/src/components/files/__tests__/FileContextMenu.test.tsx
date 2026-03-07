import { describe, it, expect, vi, beforeEach } from 'vitest';
import { screen, fireEvent } from '@testing-library/react';
import { render } from '../../../test/utils';
import { FileContextMenu } from '../FileContextMenu';

// Mock favoritesStore
vi.mock('../../../stores/favoritesStore', () => ({
  useFavoritesStore: vi.fn(() => ({
    isFavorite: vi.fn(() => false),
    toggleFavorite: vi.fn(),
  })),
}));

// Mock the ContextMenu UI components
vi.mock('@/components/ui/ContextMenu', () => ({
  ContextMenu: ({ children }: { children: React.ReactNode }) => <div>{children}</div>,
  ContextMenuTrigger: ({ children }: { children: React.ReactNode }) => (
    <div data-testid="context-trigger">{children}</div>
  ),
  ContextMenuContent: ({ children }: { children: React.ReactNode }) => (
    <div data-testid="context-content">{children}</div>
  ),
  ContextMenuItem: ({
    children,
    onClick,
    className,
  }: {
    children: React.ReactNode;
    onClick: () => void;
    className?: string;
  }) => (
    <button data-testid="context-item" onClick={onClick} className={className}>
      {children}
    </button>
  ),
  ContextMenuSeparator: () => <hr data-testid="context-separator" />,
}));

const mockFileItem = {
  id: 'file-1',
  name: 'test.pdf',
  item_type: 'file' as const,
};

const mockFolderItem = {
  id: 'folder-1',
  name: 'Documents',
  item_type: 'folder' as const,
};

describe('FileContextMenu', () => {
  const defaultProps = {
    item: mockFileItem,
    onDownload: vi.fn(),
    onShare: vi.fn(),
    onRename: vi.fn(),
    onDelete: vi.fn(),
    children: <div data-testid="trigger-content">Right-click me</div>,
  };

  beforeEach(() => {
    vi.clearAllMocks();
  });

  describe('rendering', () => {
    it('should render children as the trigger', () => {
      render(<FileContextMenu {...defaultProps} />);
      expect(screen.getByTestId('trigger-content')).toBeInTheDocument();
    });

    it('should render all menu items for files', () => {
      render(<FileContextMenu {...defaultProps} />);
      expect(screen.getByText('Download')).toBeInTheDocument();
      expect(screen.getByText('Share')).toBeInTheDocument();
      expect(screen.getByText('Rename')).toBeInTheDocument();
      expect(screen.getByText('Delete')).toBeInTheDocument();
    });

    it('should not render download option for folders', () => {
      render(<FileContextMenu {...defaultProps} item={mockFolderItem} />);
      expect(screen.queryByText('Download')).not.toBeInTheDocument();
      expect(screen.getByText('Share')).toBeInTheDocument();
      expect(screen.getByText('Rename')).toBeInTheDocument();
      expect(screen.getByText('Delete')).toBeInTheDocument();
    });

    it('should render separators for menu sections', () => {
      render(<FileContextMenu {...defaultProps} />);
      // Two separators: one after favorites, one before delete
      expect(screen.getAllByTestId('context-separator')).toHaveLength(2);
    });
  });

  describe('file menu actions', () => {
    it('should call onDownload when Download is clicked', () => {
      render(<FileContextMenu {...defaultProps} />);
      fireEvent.click(screen.getByText('Download'));
      expect(defaultProps.onDownload).toHaveBeenCalledTimes(1);
    });

    it('should call onShare when Share is clicked', () => {
      render(<FileContextMenu {...defaultProps} />);
      fireEvent.click(screen.getByText('Share'));
      expect(defaultProps.onShare).toHaveBeenCalledTimes(1);
    });

    it('should call onRename when Rename is clicked', () => {
      render(<FileContextMenu {...defaultProps} />);
      fireEvent.click(screen.getByText('Rename'));
      expect(defaultProps.onRename).toHaveBeenCalledTimes(1);
    });

    it('should call onDelete when Delete is clicked', () => {
      render(<FileContextMenu {...defaultProps} />);
      fireEvent.click(screen.getByText('Delete'));
      expect(defaultProps.onDelete).toHaveBeenCalledTimes(1);
    });
  });

  describe('folder menu actions', () => {
    it('should call onShare when Share is clicked for folder', () => {
      render(<FileContextMenu {...defaultProps} item={mockFolderItem} />);
      fireEvent.click(screen.getByText('Share'));
      expect(defaultProps.onShare).toHaveBeenCalledTimes(1);
    });

    it('should call onRename when Rename is clicked for folder', () => {
      render(<FileContextMenu {...defaultProps} item={mockFolderItem} />);
      fireEvent.click(screen.getByText('Rename'));
      expect(defaultProps.onRename).toHaveBeenCalledTimes(1);
    });

    it('should call onDelete when Delete is clicked for folder', () => {
      render(<FileContextMenu {...defaultProps} item={mockFolderItem} />);
      fireEvent.click(screen.getByText('Delete'));
      expect(defaultProps.onDelete).toHaveBeenCalledTimes(1);
    });
  });

  describe('styling', () => {
    it('should apply destructive styling to Delete item', () => {
      render(<FileContextMenu {...defaultProps} />);
      const deleteButton = screen.getByText('Delete').closest('button');
      expect(deleteButton).toHaveClass('text-destructive');
    });
  });
});
