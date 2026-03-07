import { describe, it, expect, vi, beforeEach } from 'vitest';
import { screen, waitFor } from '@testing-library/react';
import { render } from '../../../test/utils';
import { Header } from '../Header';
import { useAuthStore } from '../../../stores/authStore';
import { useFileStore } from '../../../stores/fileStore';
import { useNotificationStore } from '../../../stores/notificationStore';
import { invoke } from '@tauri-apps/api/core';

vi.mock('@tauri-apps/api/core');

const mockInvoke = vi.mocked(invoke);

const mockUser = {
  id: 'user-1',
  email: 'test@example.com',
  name: 'Test User',
  tenantId: 'tenant-1',
};

describe('Header', () => {
  beforeEach(() => {
    vi.clearAllMocks();

    // Reset auth store
    useAuthStore.setState({
      user: mockUser,
      isAuthenticated: true,
      isLocked: false,
    });

    // Reset file store
    useFileStore.setState({
      searchQuery: '',
      items: [],
    });

    // Reset notification store
    useNotificationStore.setState({
      notifications: [],
      unreadCount: 0,
      isLoading: false,
    });

    mockInvoke.mockResolvedValue([]);
  });

  it('should render search input', () => {
    render(<Header />);

    expect(screen.getByPlaceholderText('Search files and folders...')).toBeInTheDocument();
  });

  it('should render user name', () => {
    render(<Header />);

    expect(screen.getByText('Test User')).toBeInTheDocument();
  });

  it('should render notification bell icon', () => {
    render(<Header />);

    expect(document.querySelector('.lucide-bell')).toBeInTheDocument();
  });

  it('should render user avatar button', () => {
    render(<Header />);

    // Look for the button containing user name
    expect(screen.getByText('Test User')).toBeInTheDocument();
  });

  it('should show "User" when user name is not available', () => {
    useAuthStore.setState({ user: null });

    render(<Header />);

    expect(screen.getByText('User')).toBeInTheDocument();
  });

  it('should render search icon', () => {
    render(<Header />);

    expect(document.querySelector('.lucide-search')).toBeInTheDocument();
  });

  describe('search functionality', () => {
    it('should update search value on input', async () => {
      const { user } = render(<Header />);

      const searchInput = screen.getByPlaceholderText('Search files and folders...');
      await user.type(searchInput, 'test query');

      expect(searchInput).toHaveValue('test query');
    });

    it('should sync with store search query', () => {
      useFileStore.setState({ searchQuery: 'existing search' });

      render(<Header />);

      const searchInput = screen.getByPlaceholderText('Search files and folders...');
      expect(searchInput).toHaveValue('existing search');
    });

    it('should update store after debounce', async () => {
      const { user } = render(<Header />);

      const searchInput = screen.getByPlaceholderText('Search files and folders...');
      await user.type(searchInput, 'test');

      // Store should be updated after debounce (300ms + some buffer)
      await waitFor(
        () => {
          expect(useFileStore.getState().searchQuery).toBe('test');
        },
        { timeout: 500 }
      );
    });
  });
});
