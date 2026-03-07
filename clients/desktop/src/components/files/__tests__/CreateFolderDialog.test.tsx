import { describe, it, expect, vi, beforeEach } from 'vitest';
import { screen, waitFor } from '@testing-library/react';
import { render } from '../../../test/utils';
import { CreateFolderDialog } from '../CreateFolderDialog';

describe('CreateFolderDialog', () => {
  const mockOnOpenChange = vi.fn();
  const mockOnCreateFolder = vi.fn();

  beforeEach(() => {
    vi.clearAllMocks();
    mockOnCreateFolder.mockResolvedValue(undefined);
  });

  const renderDialog = (open = true) => {
    return render(
      <CreateFolderDialog
        open={open}
        onOpenChange={mockOnOpenChange}
        onCreateFolder={mockOnCreateFolder}
      />
    );
  };

  it('should render with correct title when open', () => {
    renderDialog();

    expect(screen.getByText('Create New Folder')).toBeInTheDocument();
    expect(screen.getByLabelText('Folder Name')).toBeInTheDocument();
  });

  it('should not render when closed', () => {
    renderDialog(false);

    expect(screen.queryByText('Create New Folder')).not.toBeInTheDocument();
  });

  it('should disable submit for whitespace-only name', async () => {
    const { user } = renderDialog();

    const input = screen.getByLabelText('Folder Name');
    await user.type(input, '   '); // Whitespace only

    const submitButton = screen.getByRole('button', { name: 'Create' });
    expect(submitButton).toBeDisabled();
  });

  it('should show error for invalid characters', async () => {
    const { user } = renderDialog();

    const input = screen.getByLabelText('Folder Name');
    await user.type(input, 'Invalid/Name');

    const submitButton = screen.getByRole('button', { name: 'Create' });
    await user.click(submitButton);

    expect(screen.getByText('Folder name contains invalid characters')).toBeInTheDocument();
  });

  it('should call onCreateFolder with trimmed name', async () => {
    const { user } = renderDialog();

    const input = screen.getByLabelText('Folder Name');
    await user.type(input, '  My New Folder  ');

    const submitButton = screen.getByRole('button', { name: 'Create' });
    await user.click(submitButton);

    await waitFor(() => {
      expect(mockOnCreateFolder).toHaveBeenCalledWith('My New Folder');
    });
  });

  it('should close dialog on successful creation', async () => {
    const { user } = renderDialog();

    const input = screen.getByLabelText('Folder Name');
    await user.type(input, 'New Folder');

    const submitButton = screen.getByRole('button', { name: 'Create' });
    await user.click(submitButton);

    await waitFor(() => {
      expect(mockOnOpenChange).toHaveBeenCalledWith(false);
    });
  });

  it('should show error on creation failure', async () => {
    mockOnCreateFolder.mockRejectedValueOnce(new Error('Folder already exists'));

    const { user } = renderDialog();

    const input = screen.getByLabelText('Folder Name');
    await user.type(input, 'Existing Folder');

    const submitButton = screen.getByRole('button', { name: 'Create' });
    await user.click(submitButton);

    await waitFor(() => {
      expect(screen.getByText('Error: Folder already exists')).toBeInTheDocument();
    });
    expect(mockOnOpenChange).not.toHaveBeenCalledWith(false);
  });

  it('should close dialog on cancel', async () => {
    const { user } = renderDialog();

    const cancelButton = screen.getByRole('button', { name: 'Cancel' });
    await user.click(cancelButton);

    expect(mockOnOpenChange).toHaveBeenCalledWith(false);
  });

  it('should disable submit button when input is empty', () => {
    renderDialog();

    const submitButton = screen.getByRole('button', { name: 'Create' });
    expect(submitButton).toBeDisabled();
  });

  it('should enable submit button when input has value', async () => {
    const { user } = renderDialog();

    const input = screen.getByLabelText('Folder Name');
    await user.type(input, 'Test');

    const submitButton = screen.getByRole('button', { name: 'Create' });
    expect(submitButton).not.toBeDisabled();
  });
});
