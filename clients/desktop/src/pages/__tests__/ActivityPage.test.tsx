import { describe, it, expect, vi, beforeEach } from 'vitest';
import { screen, waitFor } from '@testing-library/react';
import { render } from '../../test/utils';
import { ActivityPage } from '../ActivityPage';
import type { ActivityResponse } from '@/services/tauri';

// Mock tauriService
const mockListActivity = vi.fn();
vi.mock('@/services/tauri', () => ({
  default: {
    listActivity: (...args: unknown[]) => mockListActivity(...args),
  },
}));

// Mock useToast
const mockShowError = vi.fn();
vi.mock('@/hooks/useToast', () => ({
  useToast: () => ({
    success: vi.fn(),
    error: mockShowError,
    info: vi.fn(),
    warning: vi.fn(),
  }),
}));

const mockActivityResponse: ActivityResponse = {
  items: [
    {
      id: 'act-1',
      actor_id: 'user-1',
      actor_name: 'Test User',
      event_type: 'file.uploaded',
      resource_type: 'file',
      resource_id: 'file-1',
      resource_name: 'Document.pdf',
      details: null,
      created_at: '2024-01-15T10:00:00Z',
    },
    {
      id: 'act-2',
      actor_id: 'user-1',
      actor_name: 'Test User',
      event_type: 'file.downloaded',
      resource_type: 'file',
      resource_id: 'file-2',
      resource_name: 'Report.xlsx',
      details: null,
      created_at: '2024-01-15T09:00:00Z',
    },
    {
      id: 'act-3',
      actor_id: 'user-2',
      actor_name: 'Alice',
      event_type: 'file.renamed',
      resource_type: 'file',
      resource_id: 'file-3',
      resource_name: 'Notes.txt',
      details: { old_name: 'OldNotes.txt' },
      created_at: '2024-01-14T15:00:00Z',
    },
    {
      id: 'act-4',
      actor_id: 'user-1',
      actor_name: 'Test User',
      event_type: 'file.shared',
      resource_type: 'file',
      resource_id: 'file-4',
      resource_name: 'Presentation.pptx',
      details: { shared_with: 'bob@example.com' },
      created_at: '2024-01-14T12:00:00Z',
    },
  ],
  total: 4,
  page: 1,
  page_size: 20,
};

const emptyActivityResponse: ActivityResponse = {
  items: [],
  total: 0,
  page: 1,
  page_size: 20,
};

describe('ActivityPage', () => {
  beforeEach(() => {
    vi.clearAllMocks();
    mockListActivity.mockResolvedValue(mockActivityResponse);
  });

  it('should render page title', async () => {
    render(<ActivityPage />);

    expect(screen.getByText('Activity')).toBeInTheDocument();
  });

  it('should render page description', async () => {
    render(<ActivityPage />);

    expect(
      screen.getByText('Recent activity across your files and folders')
    ).toBeInTheDocument();
  });

  it('should render filter chips', async () => {
    render(<ActivityPage />);

    expect(screen.getByText('All Events')).toBeInTheDocument();
    expect(screen.getByText('Uploads')).toBeInTheDocument();
    expect(screen.getByText('Downloads')).toBeInTheDocument();
    expect(screen.getByText('Shares')).toBeInTheDocument();
    expect(screen.getByText('Renames')).toBeInTheDocument();
    expect(screen.getByText('Deletes')).toBeInTheDocument();
    expect(screen.getByText('Folders')).toBeInTheDocument();
  });

  it('should call listActivity on mount', async () => {
    render(<ActivityPage />);

    await waitFor(() => {
      expect(mockListActivity).toHaveBeenCalledWith({
        page: 1,
        pageSize: 20,
        eventType: undefined,
      });
    });
  });

  it('should display activity items after loading', async () => {
    render(<ActivityPage />);

    await waitFor(() => {
      expect(screen.getByText('Document.pdf')).toBeInTheDocument();
      expect(screen.getByText('Report.xlsx')).toBeInTheDocument();
      expect(screen.getByText('Notes.txt')).toBeInTheDocument();
      expect(screen.getByText('Presentation.pptx')).toBeInTheDocument();
    });
  });

  it('should display event labels', async () => {
    render(<ActivityPage />);

    await waitFor(() => {
      expect(screen.getByText('Uploaded')).toBeInTheDocument();
      expect(screen.getByText('Downloaded')).toBeInTheDocument();
      expect(screen.getByText('Renamed')).toBeInTheDocument();
      expect(screen.getByText('Shared')).toBeInTheDocument();
    });
  });

  it('should display event details for renamed files', async () => {
    render(<ActivityPage />);

    await waitFor(() => {
      expect(screen.getByText('from "OldNotes.txt"')).toBeInTheDocument();
    });
  });

  it('should display event details for shared files', async () => {
    render(<ActivityPage />);

    await waitFor(() => {
      expect(screen.getByText('with bob@example.com')).toBeInTheDocument();
    });
  });

  it('should render table headers', async () => {
    render(<ActivityPage />);

    await waitFor(() => {
      expect(screen.getByText('Event')).toBeInTheDocument();
      expect(screen.getByText('File / Folder')).toBeInTheDocument();
      expect(screen.getByText('Details')).toBeInTheDocument();
      expect(screen.getByText('When')).toBeInTheDocument();
    });
  });

  describe('empty state', () => {
    it('should show empty state when no activity', async () => {
      mockListActivity.mockResolvedValue(emptyActivityResponse);

      render(<ActivityPage />);

      await waitFor(() => {
        expect(screen.getByText('No activity yet')).toBeInTheDocument();
        expect(
          screen.getByText('Activity will appear here as you use your drive')
        ).toBeInTheDocument();
      });
    });
  });

  describe('loading state', () => {
    it('should show loading spinner initially', () => {
      mockListActivity.mockReturnValue(new Promise(() => {})); // never resolves

      render(<ActivityPage />);

      // Should show spinner (animate-spin class)
      expect(document.querySelector('.animate-spin')).toBeInTheDocument();
    });
  });

  describe('error state', () => {
    it('should show error toast when loading fails', async () => {
      mockListActivity.mockRejectedValue(new Error('Network error'));

      render(<ActivityPage />);

      await waitFor(() => {
        expect(mockShowError).toHaveBeenCalledWith({
          title: 'Failed to load activity',
          description: 'Error: Network error',
        });
      });
    });
  });

  describe('filter interactions', () => {
    it('should filter by event type when chip clicked', async () => {
      const { user } = render(<ActivityPage />);

      await waitFor(() => {
        expect(screen.getByText('Document.pdf')).toBeInTheDocument();
      });

      mockListActivity.mockClear();
      await user.click(screen.getByText('Uploads'));

      await waitFor(() => {
        expect(mockListActivity).toHaveBeenCalledWith({
          page: 1,
          pageSize: 20,
          eventType: 'file.uploaded',
        });
      });
    });

    it('should clear filter when All Events is clicked', async () => {
      const { user } = render(<ActivityPage />);

      await waitFor(() => {
        expect(screen.getByText('Document.pdf')).toBeInTheDocument();
      });

      // Click a filter first
      await user.click(screen.getByText('Uploads'));

      mockListActivity.mockClear();
      await user.click(screen.getByText('All Events'));

      await waitFor(() => {
        expect(mockListActivity).toHaveBeenCalledWith({
          page: 1,
          pageSize: 20,
          eventType: undefined,
        });
      });
    });
  });

  describe('refresh', () => {
    it('should reload activity when refresh button is clicked', async () => {
      const { user } = render(<ActivityPage />);

      await waitFor(() => {
        expect(screen.getByText('Document.pdf')).toBeInTheDocument();
      });

      mockListActivity.mockClear();

      // Click the refresh button (icon-only button)
      const refreshButton = document.querySelector(
        '.lucide-refresh-cw'
      )?.closest('button');
      expect(refreshButton).toBeTruthy();
      await user.click(refreshButton!);

      await waitFor(() => {
        expect(mockListActivity).toHaveBeenCalled();
      });
    });
  });

  describe('pagination', () => {
    it('should not show pagination when total fits in one page', async () => {
      render(<ActivityPage />);

      await waitFor(() => {
        expect(screen.getByText('Document.pdf')).toBeInTheDocument();
      });

      expect(screen.queryByText('Previous')).not.toBeInTheDocument();
      expect(screen.queryByText('Next')).not.toBeInTheDocument();
    });

    it('should show pagination when total exceeds page size', async () => {
      mockListActivity.mockResolvedValue({
        ...mockActivityResponse,
        total: 45,
      });

      render(<ActivityPage />);

      await waitFor(() => {
        expect(screen.getByText('Previous')).toBeInTheDocument();
        expect(screen.getByText('Next')).toBeInTheDocument();
        expect(screen.getByText(/Page 1 of 3/)).toBeInTheDocument();
        expect(screen.getByText(/45 events/)).toBeInTheDocument();
      });
    });

    it('should disable Previous button on first page', async () => {
      mockListActivity.mockResolvedValue({
        ...mockActivityResponse,
        total: 45,
      });

      render(<ActivityPage />);

      await waitFor(() => {
        const prevButton = screen.getByText('Previous').closest('button');
        expect(prevButton).toBeDisabled();
      });
    });

    it('should navigate to next page when Next is clicked', async () => {
      mockListActivity.mockResolvedValue({
        ...mockActivityResponse,
        total: 45,
      });

      const { user } = render(<ActivityPage />);

      await waitFor(() => {
        expect(screen.getByText('Next')).toBeInTheDocument();
      });

      mockListActivity.mockClear();
      await user.click(screen.getByText('Next').closest('button')!);

      await waitFor(() => {
        expect(mockListActivity).toHaveBeenCalledWith({
          page: 2,
          pageSize: 20,
          eventType: undefined,
        });
      });
    });
  });
});
