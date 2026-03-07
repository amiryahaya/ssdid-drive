import { describe, it, expect, vi, beforeEach } from 'vitest';
import { screen, waitFor } from '@testing-library/react';
import { render } from '../../../test/utils';
import { ConfirmDialog } from '../ConfirmDialog';

describe('ConfirmDialog', () => {
  const mockOnOpenChange = vi.fn();
  const mockOnConfirm = vi.fn();

  beforeEach(() => {
    vi.clearAllMocks();
    mockOnConfirm.mockResolvedValue(undefined);
  });

  const renderDialog = (props = {}) => {
    const defaultProps = {
      open: true,
      onOpenChange: mockOnOpenChange,
      title: 'Confirm Action',
      description: 'Are you sure you want to proceed?',
      onConfirm: mockOnConfirm,
    };

    return render(<ConfirmDialog {...defaultProps} {...props} />);
  };

  it('should render with title and description', () => {
    renderDialog();

    expect(screen.getByText('Confirm Action')).toBeInTheDocument();
    expect(screen.getByText('Are you sure you want to proceed?')).toBeInTheDocument();
  });

  it('should not render when closed', () => {
    renderDialog({ open: false });

    expect(screen.queryByText('Confirm Action')).not.toBeInTheDocument();
  });

  it('should render default button labels', () => {
    renderDialog();

    expect(screen.getByRole('button', { name: 'Confirm' })).toBeInTheDocument();
    expect(screen.getByRole('button', { name: 'Cancel' })).toBeInTheDocument();
  });

  it('should render custom button labels', () => {
    renderDialog({ confirmLabel: 'Delete', cancelLabel: 'Keep' });

    expect(screen.getByRole('button', { name: 'Delete' })).toBeInTheDocument();
    expect(screen.getByRole('button', { name: 'Keep' })).toBeInTheDocument();
  });

  it('should call onConfirm when confirm button clicked', async () => {
    const { user } = renderDialog();

    await user.click(screen.getByRole('button', { name: 'Confirm' }));

    await waitFor(() => {
      expect(mockOnConfirm).toHaveBeenCalled();
    });
  });

  it('should close dialog after confirm', async () => {
    const { user } = renderDialog();

    await user.click(screen.getByRole('button', { name: 'Confirm' }));

    await waitFor(() => {
      expect(mockOnOpenChange).toHaveBeenCalledWith(false);
    });
  });

  it('should call onOpenChange with false when cancel clicked', async () => {
    const { user } = renderDialog();

    await user.click(screen.getByRole('button', { name: 'Cancel' }));

    expect(mockOnOpenChange).toHaveBeenCalledWith(false);
  });

  it('should show loading state', () => {
    renderDialog({ isLoading: true });

    const confirmButton = screen.getByRole('button', { name: /Confirm/i });
    expect(confirmButton).toBeDisabled();

    const cancelButton = screen.getByRole('button', { name: 'Cancel' });
    expect(cancelButton).toBeDisabled();
  });

  it('should render destructive variant', () => {
    renderDialog({ variant: 'destructive' });

    // Should have alert triangle icon for destructive variant
    const confirmButton = screen.getByRole('button', { name: 'Confirm' });
    expect(confirmButton).toHaveClass('bg-destructive');
  });
});
