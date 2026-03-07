import { describe, it, expect } from 'vitest';
import { screen } from '@testing-library/react';
import { render } from '../../../test/utils';
import { FileListSkeleton, FileGridSkeleton } from '../FileListSkeleton';

describe('FileListSkeleton', () => {
  describe('default rendering', () => {
    it('should render a table structure', () => {
      render(<FileListSkeleton />);
      expect(screen.getByRole('table')).toBeInTheDocument();
    });

    it('should render default 5 skeleton rows', () => {
      render(<FileListSkeleton />);
      const rows = screen.getAllByRole('row');
      // Header row + 5 body rows = 6 total
      expect(rows.length).toBe(6);
    });

    it('should have loading status role', () => {
      render(<FileListSkeleton />);
      expect(screen.getByRole('status')).toBeInTheDocument();
    });

    it('should have accessible label', () => {
      render(<FileListSkeleton />);
      expect(screen.getByRole('status')).toHaveAttribute('aria-label', 'Loading files');
    });

    it('should have screen reader text', () => {
      render(<FileListSkeleton />);
      expect(screen.getByText('Loading file list...')).toHaveClass('sr-only');
    });
  });

  describe('custom count', () => {
    it('should render specified number of skeleton rows', () => {
      render(<FileListSkeleton count={3} />);
      const rows = screen.getAllByRole('row');
      // Header row + 3 body rows = 4 total
      expect(rows.length).toBe(4);
    });

    it('should render 10 rows when count is 10', () => {
      render(<FileListSkeleton count={10} />);
      const rows = screen.getAllByRole('row');
      expect(rows.length).toBe(11);
    });

    it('should render 1 row when count is 1', () => {
      render(<FileListSkeleton count={1} />);
      const rows = screen.getAllByRole('row');
      expect(rows.length).toBe(2);
    });
  });

  describe('table headers', () => {
    it('should have Name column header', () => {
      render(<FileListSkeleton />);
      expect(screen.getByText('Name')).toBeInTheDocument();
    });

    it('should have Size column header', () => {
      render(<FileListSkeleton />);
      expect(screen.getByText('Size')).toBeInTheDocument();
    });

    it('should have Modified column header', () => {
      render(<FileListSkeleton />);
      expect(screen.getByText('Modified')).toBeInTheDocument();
    });
  });

  describe('animation', () => {
    it('should have pulse animation on rows', () => {
      render(<FileListSkeleton count={1} />);
      const tbody = screen.getByRole('table').querySelector('tbody');
      const row = tbody?.querySelector('tr');
      expect(row).toHaveClass('animate-pulse');
    });
  });
});

describe('FileGridSkeleton', () => {
  describe('default rendering', () => {
    it('should render grid structure', () => {
      render(<FileGridSkeleton />);
      expect(screen.getByRole('status')).toHaveClass('grid');
    });

    it('should render default 12 skeleton items', () => {
      render(<FileGridSkeleton />);
      // Count direct children with animate-pulse (grid items)
      const grid = screen.getByRole('status');
      const items = grid.querySelectorAll(':scope > .animate-pulse');
      expect(items.length).toBe(12);
    });

    it('should have loading status role', () => {
      render(<FileGridSkeleton />);
      expect(screen.getByRole('status')).toBeInTheDocument();
    });

    it('should have accessible label', () => {
      render(<FileGridSkeleton />);
      expect(screen.getByRole('status')).toHaveAttribute('aria-label', 'Loading files');
    });

    it('should have screen reader text', () => {
      render(<FileGridSkeleton />);
      expect(screen.getByText('Loading file list...')).toHaveClass('sr-only');
    });
  });

  describe('custom count', () => {
    it('should render specified number of skeleton items', () => {
      render(<FileGridSkeleton count={6} />);
      const grid = screen.getByRole('status');
      const items = grid.querySelectorAll(':scope > .animate-pulse');
      expect(items.length).toBe(6);
    });

    it('should render 20 items when count is 20', () => {
      render(<FileGridSkeleton count={20} />);
      const grid = screen.getByRole('status');
      const items = grid.querySelectorAll(':scope > .animate-pulse');
      expect(items.length).toBe(20);
    });
  });

  describe('responsive grid', () => {
    it('should have responsive column classes', () => {
      render(<FileGridSkeleton />);
      const grid = screen.getByRole('status');
      expect(grid).toHaveClass('grid-cols-2');
      expect(grid).toHaveClass('sm:grid-cols-3');
      expect(grid).toHaveClass('md:grid-cols-4');
      expect(grid).toHaveClass('lg:grid-cols-5');
      expect(grid).toHaveClass('xl:grid-cols-6');
    });
  });

  describe('animation', () => {
    it('should have pulse animation on items', () => {
      render(<FileGridSkeleton count={1} />);
      const item = screen.getByRole('status').querySelector('.animate-pulse');
      expect(item).toBeInTheDocument();
    });
  });
});
