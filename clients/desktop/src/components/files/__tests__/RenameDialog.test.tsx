import { describe, it, expect, vi, beforeEach } from 'vitest';
import { screen, waitFor } from '@testing-library/react';
import { render } from '../../../test/utils';
import { RenameDialog } from '../RenameDialog';
import type { FileItem } from '../../../types';

describe('RenameDialog', () => {
  const mockOnOpenChange = vi.fn();
  const mockOnRename = vi.fn();

  const mockFile: FileItem = {
    id: 'file-1',
    name: 'document.pdf',
    type: 'file',
    size: 1024,
    mime_type: 'application/pdf',
    folder_id: null,
    is_shared: false,
    created_at: '2024-01-15T10:00:00Z',
    updated_at: '2024-01-15T10:00:00Z',
  };

  const mockFolder: FileItem = {
    id: 'folder-1',
    name: 'My Folder',
    type: 'folder',
    size: 0,
    mime_type: null,
    folder_id: null,
    is_shared: false,
    created_at: '2024-01-15T10:00:00Z',
    updated_at: '2024-01-15T10:00:00Z',
  };

  beforeEach(() => {
    vi.clearAllMocks();
    mockOnRename.mockResolvedValue(undefined);
  });

  const renderDialog = (item: FileItem | null = mockFile, open = true) => {
    return render(
      <RenameDialog
        open={open}
        onOpenChange={mockOnOpenChange}
        item={item}
        onRename={mockOnRename}
      />
    );
  };

  it('should render with file title when open', () => {
    renderDialog(mockFile);

    expect(screen.getByText('Rename File')).toBeInTheDocument();
  });

  it('should render with folder title when item is folder', () => {
    renderDialog(mockFolder);

    expect(screen.getByText('Rename Folder')).toBeInTheDocument();
  });

  it('should not render when item is null', () => {
    renderDialog(null);

    expect(screen.queryByText('Rename')).not.toBeInTheDocument();
  });

  it('should pre-fill current item name', () => {
    renderDialog(mockFile);

    const input = screen.getByLabelText('Name');
    expect(input).toHaveValue('document.pdf');
  });

  it('should disable submit for whitespace-only name', async () => {
    const { user } = renderDialog();

    const input = screen.getByLabelText('Name');
    await user.clear(input);
    await user.type(input, '   '); // Whitespace only

    const submitButton = screen.getByRole('button', { name: 'Rename' });
    expect(submitButton).toBeDisabled();
  });

  it('should show error for invalid characters', async () => {
    const { user } = renderDialog();

    const input = screen.getByLabelText('Name');
    await user.clear(input);
    await user.type(input, 'invalid<name>.pdf');

    const submitButton = screen.getByRole('button', { name: 'Rename' });
    await user.click(submitButton);

    expect(screen.getByText('Name contains invalid characters')).toBeInTheDocument();
  });

  it('should close without calling onRename if name unchanged', async () => {
    const { user } = renderDialog();

    const submitButton = screen.getByRole('button', { name: 'Rename' });
    await user.click(submitButton);

    expect(mockOnRename).not.toHaveBeenCalled();
    expect(mockOnOpenChange).toHaveBeenCalledWith(false);
  });

  it('should call onRename with new name', async () => {
    const { user } = renderDialog();

    const input = screen.getByLabelText('Name');
    await user.clear(input);
    await user.type(input, 'renamed-file.pdf');

    const submitButton = screen.getByRole('button', { name: 'Rename' });
    await user.click(submitButton);

    await waitFor(() => {
      expect(mockOnRename).toHaveBeenCalledWith('file-1', 'renamed-file.pdf');
    });
  });

  it('should close dialog on successful rename', async () => {
    const { user } = renderDialog();

    const input = screen.getByLabelText('Name');
    await user.clear(input);
    await user.type(input, 'new-name.pdf');

    const submitButton = screen.getByRole('button', { name: 'Rename' });
    await user.click(submitButton);

    await waitFor(() => {
      expect(mockOnOpenChange).toHaveBeenCalledWith(false);
    });
  });

  it('should show error on rename failure', async () => {
    mockOnRename.mockRejectedValueOnce(new Error('Name already exists'));

    const { user } = renderDialog();

    const input = screen.getByLabelText('Name');
    await user.clear(input);
    await user.type(input, 'existing-name.pdf');

    const submitButton = screen.getByRole('button', { name: 'Rename' });
    await user.click(submitButton);

    await waitFor(() => {
      expect(screen.getByText('Error: Name already exists')).toBeInTheDocument();
    });
  });

  it('should close dialog on cancel', async () => {
    const { user } = renderDialog();

    const cancelButton = screen.getByRole('button', { name: 'Cancel' });
    await user.click(cancelButton);

    expect(mockOnOpenChange).toHaveBeenCalledWith(false);
  });
});
