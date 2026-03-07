import { describe, it, expect, vi } from 'vitest';
import { screen } from '@testing-library/react';
import { render } from '../../../test/utils';
import { UploadProgressIndicator } from '../UploadProgressIndicator';

type UploadPhase = 'preparing' | 'encrypting' | 'uploading' | 'confirming' | 'complete' | 'error';

interface UploadProgress {
  file_id: string;
  file_name: string;
  phase: UploadPhase;
  bytes_uploaded: number;
  total_bytes: number;
  progress_percent: number;
}

const createMockUpload = (overrides: Partial<UploadProgress> = {}): UploadProgress => ({
  file_id: 'test-file-id',
  file_name: 'test-document.pdf',
  phase: 'uploading',
  bytes_uploaded: 50,
  total_bytes: 100,
  progress_percent: 50,
  ...overrides,
});

describe('UploadProgressIndicator', () => {
  it('should not render when uploads map is empty', () => {
    const { container } = render(
      <UploadProgressIndicator uploads={new Map()} />
    );

    expect(container.firstChild).toBeNull();
  });

  it('should render file name for active upload', () => {
    const uploads = new Map<string, UploadProgress>();
    uploads.set('upload-1', createMockUpload({ file_name: 'my-report.pdf' }));

    render(<UploadProgressIndicator uploads={uploads} />);

    expect(screen.getByText('my-report.pdf')).toBeInTheDocument();
  });

  it('should show progress bar with correct percentage', () => {
    const uploads = new Map<string, UploadProgress>();
    uploads.set('upload-1', createMockUpload({ progress_percent: 75 }));

    render(<UploadProgressIndicator uploads={uploads} />);

    expect(screen.getByText('75%')).toBeInTheDocument();
    const progressBar = screen.getByRole('progressbar');
    expect(progressBar).toHaveAttribute('aria-valuenow', '75');
  });

  it('should show phase label for preparing', () => {
    const uploads = new Map<string, UploadProgress>();
    uploads.set('upload-1', createMockUpload({ phase: 'preparing' }));

    render(<UploadProgressIndicator uploads={uploads} />);

    expect(screen.getByText('Preparing...')).toBeInTheDocument();
  });

  it('should show phase label for encrypting', () => {
    const uploads = new Map<string, UploadProgress>();
    uploads.set('upload-1', createMockUpload({ phase: 'encrypting' }));

    render(<UploadProgressIndicator uploads={uploads} />);

    expect(screen.getByText('Encrypting...')).toBeInTheDocument();
  });

  it('should show phase label for uploading', () => {
    const uploads = new Map<string, UploadProgress>();
    uploads.set('upload-1', createMockUpload({ phase: 'uploading' }));

    render(<UploadProgressIndicator uploads={uploads} />);

    expect(screen.getByText('Uploading...')).toBeInTheDocument();
  });

  it('should show phase label for confirming', () => {
    const uploads = new Map<string, UploadProgress>();
    uploads.set('upload-1', createMockUpload({ phase: 'confirming' }));

    render(<UploadProgressIndicator uploads={uploads} />);

    expect(screen.getByText('Finalizing...')).toBeInTheDocument();
  });

  it('should show "Complete" for finished uploads', () => {
    const uploads = new Map<string, UploadProgress>();
    uploads.set('upload-1', createMockUpload({ phase: 'complete', progress_percent: 100 }));

    render(<UploadProgressIndicator uploads={uploads} />);

    expect(screen.getByText('Complete')).toBeInTheDocument();
  });

  it('should show "Failed" for error uploads', () => {
    const uploads = new Map<string, UploadProgress>();
    uploads.set('upload-1', createMockUpload({ phase: 'error' }));

    render(<UploadProgressIndicator uploads={uploads} />);

    expect(screen.getByText('Failed')).toBeInTheDocument();
  });

  it('should render multiple uploads', () => {
    const uploads = new Map<string, UploadProgress>();
    uploads.set('upload-1', createMockUpload({ file_name: 'document1.pdf' }));
    uploads.set('upload-2', createMockUpload({ file_name: 'document2.pdf' }));
    uploads.set('upload-3', createMockUpload({ file_name: 'document3.pdf' }));

    render(<UploadProgressIndicator uploads={uploads} />);

    expect(screen.getByText('document1.pdf')).toBeInTheDocument();
    expect(screen.getByText('document2.pdf')).toBeInTheDocument();
    expect(screen.getByText('document3.pdf')).toBeInTheDocument();
  });

  it('should show correct header count for single upload', () => {
    const uploads = new Map<string, UploadProgress>();
    uploads.set('upload-1', createMockUpload());

    render(<UploadProgressIndicator uploads={uploads} />);

    expect(screen.getByText('Uploading 1 file')).toBeInTheDocument();
  });

  it('should show correct header count for multiple uploads', () => {
    const uploads = new Map<string, UploadProgress>();
    uploads.set('upload-1', createMockUpload());
    uploads.set('upload-2', createMockUpload({ file_name: 'another.pdf' }));

    render(<UploadProgressIndicator uploads={uploads} />);

    expect(screen.getByText('Uploading 2 files')).toBeInTheDocument();
  });

  it('should show "Uploads" header when no active uploads', () => {
    const uploads = new Map<string, UploadProgress>();
    uploads.set('upload-1', createMockUpload({ phase: 'complete' }));

    render(<UploadProgressIndicator uploads={uploads} />);

    expect(screen.getByText('Uploads')).toBeInTheDocument();
  });

  it('should show dismiss button for completed uploads', () => {
    const onDismiss = vi.fn();
    const uploads = new Map<string, UploadProgress>();
    uploads.set('upload-1', createMockUpload({ phase: 'complete' }));

    render(<UploadProgressIndicator uploads={uploads} onDismiss={onDismiss} />);

    expect(screen.getByRole('button', { name: 'Dismiss' })).toBeInTheDocument();
  });

  it('should show dismiss button for error uploads', () => {
    const onDismiss = vi.fn();
    const uploads = new Map<string, UploadProgress>();
    uploads.set('upload-1', createMockUpload({ phase: 'error' }));

    render(<UploadProgressIndicator uploads={uploads} onDismiss={onDismiss} />);

    expect(screen.getByRole('button', { name: 'Dismiss' })).toBeInTheDocument();
  });

  it('should not show dismiss button for active uploads', () => {
    const onDismiss = vi.fn();
    const uploads = new Map<string, UploadProgress>();
    uploads.set('upload-1', createMockUpload({ phase: 'uploading' }));

    render(<UploadProgressIndicator uploads={uploads} onDismiss={onDismiss} />);

    expect(screen.queryByRole('button', { name: 'Dismiss' })).not.toBeInTheDocument();
  });

  it('should call onDismiss with upload id when dismiss is clicked', async () => {
    const onDismiss = vi.fn();
    const uploads = new Map<string, UploadProgress>();
    uploads.set('upload-1', createMockUpload({ phase: 'complete' }));

    const { user } = render(
      <UploadProgressIndicator uploads={uploads} onDismiss={onDismiss} />
    );

    await user.click(screen.getByRole('button', { name: 'Dismiss' }));

    expect(onDismiss).toHaveBeenCalledWith('upload-1');
  });

  it('should show check icon for completed uploads', () => {
    const uploads = new Map<string, UploadProgress>();
    uploads.set('upload-1', createMockUpload({ phase: 'complete' }));

    render(<UploadProgressIndicator uploads={uploads} />);

    // Check for the green success color class
    const successIcon = document.querySelector('.text-green-500');
    expect(successIcon).toBeInTheDocument();
  });

  it('should show error icon for failed uploads', () => {
    const uploads = new Map<string, UploadProgress>();
    uploads.set('upload-1', createMockUpload({ phase: 'error' }));

    render(<UploadProgressIndicator uploads={uploads} />);

    // Check for the destructive color class
    const errorIcon = document.querySelector('.text-destructive');
    expect(errorIcon).toBeInTheDocument();
  });

  it('should show animated upload icon for active uploads', () => {
    const uploads = new Map<string, UploadProgress>();
    uploads.set('upload-1', createMockUpload({ phase: 'uploading' }));

    render(<UploadProgressIndicator uploads={uploads} />);

    const animatedIcon = document.querySelector('.animate-pulse');
    expect(animatedIcon).toBeInTheDocument();
  });
});
