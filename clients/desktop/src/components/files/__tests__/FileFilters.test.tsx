import { describe, it, expect, vi, beforeEach } from 'vitest';
import { screen } from '@testing-library/react';
import { render } from '../../../test/utils';
import { FileFilters } from '../FileFilters';

describe('FileFilters', () => {
  const mockOnTypeFilterChange = vi.fn();
  const mockOnSharedStatusFilterChange = vi.fn();
  const mockOnClearFilters = vi.fn();

  beforeEach(() => {
    vi.clearAllMocks();
  });

  const renderFilters = (props = {}) => {
    const defaultProps = {
      typeFilter: 'all' as const,
      sharedStatusFilter: 'all' as const,
      onTypeFilterChange: mockOnTypeFilterChange,
      onSharedStatusFilterChange: mockOnSharedStatusFilterChange,
      onClearFilters: mockOnClearFilters,
      hasActiveFilters: false,
    };

    return render(<FileFilters {...defaultProps} {...props} />);
  };

  it('should render filter dropdowns', () => {
    renderFilters();

    // Check that both select triggers exist
    const comboboxes = screen.getAllByRole('combobox');
    expect(comboboxes).toHaveLength(2);
  });

  it('should display All Types as default', () => {
    renderFilters();

    expect(screen.getByText('All Types')).toBeInTheDocument();
  });

  it('should display All as default for shared status', () => {
    renderFilters();

    expect(screen.getByText('All')).toBeInTheDocument();
  });

  it('should not show clear button when no filters active', () => {
    renderFilters({ hasActiveFilters: false });

    expect(screen.queryByText('Clear filters')).not.toBeInTheDocument();
  });

  it('should show clear button when filters are active', () => {
    renderFilters({ hasActiveFilters: true });

    expect(screen.getByText('Clear filters')).toBeInTheDocument();
  });

  it('should call onClearFilters when clear button clicked', async () => {
    const { user } = renderFilters({ hasActiveFilters: true });

    await user.click(screen.getByText('Clear filters'));

    expect(mockOnClearFilters).toHaveBeenCalled();
  });

  it('should call onTypeFilterChange when type filter changed', async () => {
    const { user } = renderFilters();

    // Click the first combobox (type filter)
    const comboboxes = screen.getAllByRole('combobox');
    await user.click(comboboxes[0]);
    await user.click(screen.getByRole('option', { name: 'Files' }));

    expect(mockOnTypeFilterChange).toHaveBeenCalledWith('file');
  });

  it('should call onSharedStatusFilterChange when shared status changed', async () => {
    const { user } = renderFilters();

    // Click the second combobox (shared status filter)
    const comboboxes = screen.getAllByRole('combobox');
    await user.click(comboboxes[1]);
    await user.click(screen.getByRole('option', { name: 'Shared by me' }));

    expect(mockOnSharedStatusFilterChange).toHaveBeenCalledWith('shared');
  });

  it('should display Folders when typeFilter is folder', () => {
    renderFilters({ typeFilter: 'folder' });

    expect(screen.getByText('Folders')).toBeInTheDocument();
  });

  it('should display Shared with me when sharedStatusFilter is received', () => {
    renderFilters({ sharedStatusFilter: 'received' });

    expect(screen.getByText('Shared with me')).toBeInTheDocument();
  });
});
