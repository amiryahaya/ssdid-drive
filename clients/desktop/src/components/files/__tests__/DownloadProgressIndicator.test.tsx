import { describe, it, expect, vi } from 'vitest';
import { screen } from '@testing-library/react';
import { render } from '../../../test/utils';
import { DownloadProgressIndicator } from '../DownloadProgressIndicator';

type DownloadPhase = 'preparing' | 'downloading' | 'decrypting' | 'writing' | 'complete' | 'error';

interface DownloadProgress {
  file_id: string;
  file_name: string;
  phase: DownloadPhase;
  bytes_downloaded: number;
  total_bytes: number;
  progress_percent: number;
}

const createMockDownload = (overrides: Partial<DownloadProgress> = {}): DownloadProgress => ({
  file_id: 'test-file-id',
  file_name: 'test-document.pdf',
  phase: 'downloading',
  bytes_downloaded: 50,
  total_bytes: 100,
  progress_percent: 50,
  ...overrides,
});

describe('DownloadProgressIndicator', () => {
  it('should not render when downloads map is empty', () => {
    const { container } = render(
      <DownloadProgressIndicator downloads={new Map()} />
    );

    expect(container.firstChild).toBeNull();
  });

  it('should render file name for active download', () => {
    const downloads = new Map<string, DownloadProgress>();
    downloads.set('download-1', createMockDownload({ file_name: 'my-report.pdf' }));

    render(<DownloadProgressIndicator downloads={downloads} />);

    expect(screen.getByText('my-report.pdf')).toBeInTheDocument();
  });

  it('should show progress bar with correct percentage', () => {
    const downloads = new Map<string, DownloadProgress>();
    downloads.set('download-1', createMockDownload({ progress_percent: 75 }));

    render(<DownloadProgressIndicator downloads={downloads} />);

    expect(screen.getByText('75%')).toBeInTheDocument();
    const progressBar = screen.getByRole('progressbar');
    expect(progressBar).toHaveAttribute('aria-valuenow', '75');
  });

  it('should show phase label for preparing', () => {
    const downloads = new Map<string, DownloadProgress>();
    downloads.set('download-1', createMockDownload({ phase: 'preparing' }));

    render(<DownloadProgressIndicator downloads={downloads} />);

    expect(screen.getByText('Preparing...')).toBeInTheDocument();
  });

  it('should show phase label for downloading', () => {
    const downloads = new Map<string, DownloadProgress>();
    downloads.set('download-1', createMockDownload({ phase: 'downloading' }));

    render(<DownloadProgressIndicator downloads={downloads} />);

    expect(screen.getByText('Downloading...')).toBeInTheDocument();
  });

  it('should show phase label for decrypting', () => {
    const downloads = new Map<string, DownloadProgress>();
    downloads.set('download-1', createMockDownload({ phase: 'decrypting' }));

    render(<DownloadProgressIndicator downloads={downloads} />);

    expect(screen.getByText('Decrypting...')).toBeInTheDocument();
  });

  it('should show phase label for writing', () => {
    const downloads = new Map<string, DownloadProgress>();
    downloads.set('download-1', createMockDownload({ phase: 'writing' }));

    render(<DownloadProgressIndicator downloads={downloads} />);

    expect(screen.getByText('Writing...')).toBeInTheDocument();
  });

  it('should show "Complete" for finished downloads', () => {
    const downloads = new Map<string, DownloadProgress>();
    downloads.set('download-1', createMockDownload({ phase: 'complete', progress_percent: 100 }));

    render(<DownloadProgressIndicator downloads={downloads} />);

    expect(screen.getByText('Complete')).toBeInTheDocument();
  });

  it('should show "Failed" for error downloads', () => {
    const downloads = new Map<string, DownloadProgress>();
    downloads.set('download-1', createMockDownload({ phase: 'error' }));

    render(<DownloadProgressIndicator downloads={downloads} />);

    expect(screen.getByText('Failed')).toBeInTheDocument();
  });

  it('should render multiple downloads', () => {
    const downloads = new Map<string, DownloadProgress>();
    downloads.set('download-1', createMockDownload({ file_name: 'document1.pdf' }));
    downloads.set('download-2', createMockDownload({ file_name: 'document2.pdf' }));
    downloads.set('download-3', createMockDownload({ file_name: 'document3.pdf' }));

    render(<DownloadProgressIndicator downloads={downloads} />);

    expect(screen.getByText('document1.pdf')).toBeInTheDocument();
    expect(screen.getByText('document2.pdf')).toBeInTheDocument();
    expect(screen.getByText('document3.pdf')).toBeInTheDocument();
  });

  it('should show correct header count for single download', () => {
    const downloads = new Map<string, DownloadProgress>();
    downloads.set('download-1', createMockDownload());

    render(<DownloadProgressIndicator downloads={downloads} />);

    expect(screen.getByText('Downloading 1 file')).toBeInTheDocument();
  });

  it('should show correct header count for multiple downloads', () => {
    const downloads = new Map<string, DownloadProgress>();
    downloads.set('download-1', createMockDownload());
    downloads.set('download-2', createMockDownload({ file_name: 'another.pdf' }));

    render(<DownloadProgressIndicator downloads={downloads} />);

    expect(screen.getByText('Downloading 2 files')).toBeInTheDocument();
  });

  it('should show "Downloads" header when no active downloads', () => {
    const downloads = new Map<string, DownloadProgress>();
    downloads.set('download-1', createMockDownload({ phase: 'complete' }));

    render(<DownloadProgressIndicator downloads={downloads} />);

    expect(screen.getByText('Downloads')).toBeInTheDocument();
  });

  it('should show dismiss button for completed downloads', () => {
    const onDismiss = vi.fn();
    const downloads = new Map<string, DownloadProgress>();
    downloads.set('download-1', createMockDownload({ phase: 'complete' }));

    render(<DownloadProgressIndicator downloads={downloads} onDismiss={onDismiss} />);

    expect(screen.getByRole('button', { name: 'Dismiss' })).toBeInTheDocument();
  });

  it('should show dismiss button for error downloads', () => {
    const onDismiss = vi.fn();
    const downloads = new Map<string, DownloadProgress>();
    downloads.set('download-1', createMockDownload({ phase: 'error' }));

    render(<DownloadProgressIndicator downloads={downloads} onDismiss={onDismiss} />);

    expect(screen.getByRole('button', { name: 'Dismiss' })).toBeInTheDocument();
  });

  it('should not show dismiss button for active downloads', () => {
    const onDismiss = vi.fn();
    const downloads = new Map<string, DownloadProgress>();
    downloads.set('download-1', createMockDownload({ phase: 'downloading' }));

    render(<DownloadProgressIndicator downloads={downloads} onDismiss={onDismiss} />);

    expect(screen.queryByRole('button', { name: 'Dismiss' })).not.toBeInTheDocument();
  });

  it('should call onDismiss with download id when dismiss is clicked', async () => {
    const onDismiss = vi.fn();
    const downloads = new Map<string, DownloadProgress>();
    downloads.set('download-1', createMockDownload({ phase: 'complete' }));

    const { user } = render(
      <DownloadProgressIndicator downloads={downloads} onDismiss={onDismiss} />
    );

    await user.click(screen.getByRole('button', { name: 'Dismiss' }));

    expect(onDismiss).toHaveBeenCalledWith('download-1');
  });

  it('should show check icon for completed downloads', () => {
    const downloads = new Map<string, DownloadProgress>();
    downloads.set('download-1', createMockDownload({ phase: 'complete' }));

    render(<DownloadProgressIndicator downloads={downloads} />);

    const successIcon = document.querySelector('.text-green-500');
    expect(successIcon).toBeInTheDocument();
  });

  it('should show error icon for failed downloads', () => {
    const downloads = new Map<string, DownloadProgress>();
    downloads.set('download-1', createMockDownload({ phase: 'error' }));

    render(<DownloadProgressIndicator downloads={downloads} />);

    const errorIcon = document.querySelector('.text-destructive');
    expect(errorIcon).toBeInTheDocument();
  });

  it('should show animated download icon for active downloads', () => {
    const downloads = new Map<string, DownloadProgress>();
    downloads.set('download-1', createMockDownload({ phase: 'downloading' }));

    render(<DownloadProgressIndicator downloads={downloads} />);

    const animatedIcon = document.querySelector('.animate-pulse');
    expect(animatedIcon).toBeInTheDocument();
  });
});
