import { describe, it, expect, vi, beforeEach } from 'vitest';
import { screen } from '@testing-library/react';
import { render } from '../../../test/utils';
import { FilePreviewDialog } from '../FilePreviewDialog';
import {
  mockImagePreview,
  mockTextPreview,
  mockUnsupportedPreview,
} from '../../../test/mocks/tauri';

describe('FilePreviewDialog', () => {
  const mockOnOpenChange = vi.fn();

  beforeEach(() => {
    vi.clearAllMocks();
  });

  it('should render loading state when isLoading is true', () => {
    render(
      <FilePreviewDialog
        open={true}
        onOpenChange={mockOnOpenChange}
        preview={null}
        isLoading={true}
      />
    );

    expect(screen.getByText('Loading preview...')).toBeInTheDocument();
    expect(document.querySelector('.animate-spin')).toBeInTheDocument();
  });

  it('should render file name in header', () => {
    render(
      <FilePreviewDialog
        open={true}
        onOpenChange={mockOnOpenChange}
        preview={mockImagePreview}
        isLoading={false}
      />
    );

    expect(screen.getByText('photo.png')).toBeInTheDocument();
  });

  it('should render image preview for image MIME types', () => {
    render(
      <FilePreviewDialog
        open={true}
        onOpenChange={mockOnOpenChange}
        preview={mockImagePreview}
        isLoading={false}
      />
    );

    const img = screen.getByRole('img', { name: 'photo.png' });
    expect(img).toBeInTheDocument();
    expect(img).toHaveAttribute(
      'src',
      `data:image/png;base64,${mockImagePreview.preview_data}`
    );
  });

  it('should render text preview for text MIME types', () => {
    render(
      <FilePreviewDialog
        open={true}
        onOpenChange={mockOnOpenChange}
        preview={mockTextPreview}
        isLoading={false}
      />
    );

    expect(screen.getByText(/Hello, World!/)).toBeInTheDocument();
    expect(screen.getByText(/This is a sample text file/)).toBeInTheDocument();
  });

  it('should render "not available" when can_preview is false', () => {
    render(
      <FilePreviewDialog
        open={true}
        onOpenChange={mockOnOpenChange}
        preview={mockUnsupportedPreview}
        isLoading={false}
      />
    );

    expect(screen.getByText('Preview not available')).toBeInTheDocument();
    expect(screen.getByText('This file type cannot be previewed')).toBeInTheDocument();
  });

  it('should render error state when error is provided', () => {
    render(
      <FilePreviewDialog
        open={true}
        onOpenChange={mockOnOpenChange}
        preview={null}
        isLoading={false}
        error="Network error"
      />
    );

    expect(screen.getByText('Failed to load preview')).toBeInTheDocument();
    expect(screen.getByText('Network error')).toBeInTheDocument();
  });

  it('should call onOpenChange when close button is clicked', async () => {
    const { user } = render(
      <FilePreviewDialog
        open={true}
        onOpenChange={mockOnOpenChange}
        preview={mockImagePreview}
        isLoading={false}
      />
    );

    const closeButton = screen.getByRole('button', { name: /close/i });
    await user.click(closeButton);

    expect(mockOnOpenChange).toHaveBeenCalledWith(false);
  });

  it('should not render when open is false', () => {
    render(
      <FilePreviewDialog
        open={false}
        onOpenChange={mockOnOpenChange}
        preview={mockImagePreview}
        isLoading={false}
      />
    );

    expect(screen.queryByText('photo.png')).not.toBeInTheDocument();
  });
});
