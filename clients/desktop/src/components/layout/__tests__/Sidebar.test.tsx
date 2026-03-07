import { describe, it, expect, vi, beforeEach } from 'vitest';
import { screen } from '@testing-library/react';
import { render } from '../../../test/utils';
import { Sidebar } from '../Sidebar';
import { useSettingsStore } from '../../../stores/settingsStore';
import { invoke } from '@tauri-apps/api/core';

vi.mock('@tauri-apps/api/core');

const mockInvoke = vi.mocked(invoke);

const mockStorageInfo = {
  cacheSize: 1024 * 1024 * 50,
  totalUsed: 1024 * 1024 * 500, // 500 MB used
  quota: 1024 * 1024 * 1024 * 10, // 10 GB quota
};

describe('Sidebar', () => {
  beforeEach(() => {
    vi.clearAllMocks();

    useSettingsStore.setState({
      storageInfo: mockStorageInfo,
      isLoading: false,
    });

    mockInvoke.mockResolvedValue(mockStorageInfo);
  });

  it('should render the app logo and name', () => {
    render(<Sidebar />);

    expect(screen.getByText('SSDID Drive')).toBeInTheDocument();
  });

  it('should render all navigation links', () => {
    render(<Sidebar />);

    expect(screen.getByRole('link', { name: /my files/i })).toBeInTheDocument();
    expect(screen.getByRole('link', { name: /shared with me/i })).toBeInTheDocument();
    expect(screen.getByRole('link', { name: /my shares/i })).toBeInTheDocument();
    expect(screen.getByRole('link', { name: /settings/i })).toBeInTheDocument();
  });

  it('should have correct hrefs for navigation links', () => {
    render(<Sidebar />);

    expect(screen.getByRole('link', { name: /my files/i })).toHaveAttribute('href', '/files');
    expect(screen.getByRole('link', { name: /shared with me/i })).toHaveAttribute('href', '/shared-with-me');
    expect(screen.getByRole('link', { name: /my shares/i })).toHaveAttribute('href', '/my-shares');
    expect(screen.getByRole('link', { name: /settings/i })).toHaveAttribute('href', '/settings');
  });

  it('should render storage section', () => {
    render(<Sidebar />);

    expect(screen.getByText('Storage')).toBeInTheDocument();
  });

  it('should display storage usage', () => {
    render(<Sidebar />);

    // Should show used / quota
    expect(screen.getByText(/500 MB/)).toBeInTheDocument();
    expect(screen.getByText(/10 GB/)).toBeInTheDocument();
  });

  it('should render storage progress bar', () => {
    render(<Sidebar />);

    // The progress bar container
    const progressContainer = document.querySelector('.h-2.bg-muted.rounded-full');
    expect(progressContainer).toBeInTheDocument();

    // The progress indicator
    const progressBar = progressContainer?.querySelector('.bg-primary');
    expect(progressBar).toBeInTheDocument();
  });

  it('should show default quota when storage info is not loaded', () => {
    useSettingsStore.setState({ storageInfo: null });

    render(<Sidebar />);

    // Should show 0 Bytes used with 10 GB default quota
    expect(screen.getByText(/0 Bytes/)).toBeInTheDocument();
    expect(screen.getByText(/10 GB/)).toBeInTheDocument();
  });

  it('should render navigation icons', () => {
    render(<Sidebar />);

    // Each nav item should have an SVG icon
    const links = screen.getAllByRole('link');
    links.forEach((link) => {
      expect(link.querySelector('svg')).toBeInTheDocument();
    });
  });
});
