import { describe, it, expect, vi, beforeEach } from 'vitest';
import { screen, waitFor } from '@testing-library/react';
import { render } from '../../../test/utils';
import { NotificationsDropdown } from '../NotificationsDropdown';
import { useNotificationStore, Notification } from '../../../stores/notificationStore';
import { invoke } from '@tauri-apps/api/core';

vi.mock('@tauri-apps/api/core');

const mockInvoke = vi.mocked(invoke);

const mockNotifications: Notification[] = [
  {
    id: 'notif-1',
    type: 'share_received',
    title: 'New Share',
    message: 'John shared a file with you',
    read: false,
    created_at: '2024-01-15T10:00:00Z',
  },
  {
    id: 'notif-2',
    type: 'share_accepted',
    title: 'Share Accepted',
    message: 'Jane accepted your share',
    read: true,
    created_at: '2024-01-15T09:00:00Z',
  },
  {
    id: 'notif-3',
    type: 'recovery_request',
    title: 'Recovery Request',
    message: 'Someone requested account recovery',
    read: false,
    created_at: '2024-01-15T08:00:00Z',
  },
  {
    id: 'notif-4',
    type: 'system',
    title: 'System Update',
    message: 'New version available',
    read: true,
    created_at: '2024-01-14T12:00:00Z',
  },
];

describe('NotificationsDropdown', () => {
  beforeEach(() => {
    vi.clearAllMocks();

    useNotificationStore.setState({
      notifications: [],
      unreadCount: 0,
      isLoading: false,
      error: null,
      loadNotifications: vi.fn(),
      markAsRead: vi.fn(),
      markAllAsRead: vi.fn(),
    });

    mockInvoke.mockResolvedValue([]);
  });

  describe('trigger button', () => {
    it('should render bell icon trigger', () => {
      render(<NotificationsDropdown />);

      expect(document.querySelector('.lucide-bell')).toBeInTheDocument();
    });

    it('should render trigger button', () => {
      render(<NotificationsDropdown />);

      expect(screen.getByRole('button')).toBeInTheDocument();
    });
  });

  describe('unread badge', () => {
    it('should not show badge when no unread notifications', () => {
      render(<NotificationsDropdown />);

      expect(screen.queryByText('1')).not.toBeInTheDocument();
      expect(screen.queryByText('2')).not.toBeInTheDocument();
    });

    it('should show unread count badge when count is 1', () => {
      useNotificationStore.setState({
        notifications: [],
        unreadCount: 1,
      });

      render(<NotificationsDropdown />);

      expect(screen.getByText('1')).toBeInTheDocument();
    });

    it('should show unread count badge when count is 5', () => {
      useNotificationStore.setState({
        notifications: [],
        unreadCount: 5,
      });

      render(<NotificationsDropdown />);

      expect(screen.getByText('5')).toBeInTheDocument();
    });

    it('should show 9+ for more than 9 unread', () => {
      useNotificationStore.setState({
        notifications: [],
        unreadCount: 15,
      });

      render(<NotificationsDropdown />);

      expect(screen.getByText('9+')).toBeInTheDocument();
    });

    it('should show exactly 9 when count is 9', () => {
      useNotificationStore.setState({
        notifications: [],
        unreadCount: 9,
      });

      render(<NotificationsDropdown />);

      expect(screen.getByText('9')).toBeInTheDocument();
    });
  });

  describe('loading', () => {
    it('should call loadNotifications on mount', () => {
      const loadNotificationsSpy = vi.fn();
      useNotificationStore.setState({
        loadNotifications: loadNotificationsSpy,
      });

      render(<NotificationsDropdown />);

      expect(loadNotificationsSpy).toHaveBeenCalled();
    });
  });

  describe('store interactions', () => {
    it('should have correct store state shape', () => {
      const state = useNotificationStore.getState();
      expect(state).toHaveProperty('notifications');
      expect(state).toHaveProperty('unreadCount');
      expect(state).toHaveProperty('isLoading');
      expect(state).toHaveProperty('loadNotifications');
      expect(state).toHaveProperty('markAsRead');
      expect(state).toHaveProperty('markAllAsRead');
    });

    it('should update when store state changes', () => {
      const { rerender } = render(<NotificationsDropdown />);

      // Initially no badge
      expect(screen.queryByText('5')).not.toBeInTheDocument();

      // Update store
      useNotificationStore.setState({ unreadCount: 5 });

      // Re-render to reflect changes
      rerender(<NotificationsDropdown />);

      expect(screen.getByText('5')).toBeInTheDocument();
    });
  });

  describe('dropdown content', () => {
    it('should show loading spinner when isLoading', async () => {
      useNotificationStore.setState({
        notifications: [],
        unreadCount: 0,
        isLoading: true,
      });

      const { user } = render(<NotificationsDropdown />);

      // Open dropdown
      const trigger = screen.getByRole('button');
      await user.click(trigger);

      await waitFor(() => {
        expect(document.querySelector('.animate-spin')).toBeInTheDocument();
      });
    });

    it('should show empty state when no notifications', async () => {
      useNotificationStore.setState({
        notifications: [],
        unreadCount: 0,
        isLoading: false,
      });

      const { user } = render(<NotificationsDropdown />);

      // Open dropdown
      const trigger = screen.getByRole('button');
      await user.click(trigger);

      await waitFor(() => {
        expect(screen.getByText('No notifications')).toBeInTheDocument();
      });
    });

    it('should show notifications list when has notifications', async () => {
      useNotificationStore.setState({
        notifications: mockNotifications,
        unreadCount: 2,
        isLoading: false,
      });

      const { user } = render(<NotificationsDropdown />);

      // Open dropdown
      const trigger = screen.getByRole('button');
      await user.click(trigger);

      await waitFor(() => {
        expect(screen.getByText('New Share')).toBeInTheDocument();
        expect(screen.getByText('Share Accepted')).toBeInTheDocument();
        expect(screen.getByText('Recovery Request')).toBeInTheDocument();
        expect(screen.getByText('System Update')).toBeInTheDocument();
      });
    });

    it('should show mark all read button when has unread notifications', async () => {
      useNotificationStore.setState({
        notifications: mockNotifications,
        unreadCount: 2,
        isLoading: false,
      });

      const { user } = render(<NotificationsDropdown />);

      // Open dropdown
      const trigger = screen.getByRole('button');
      await user.click(trigger);

      await waitFor(() => {
        expect(screen.getByText('Mark all read')).toBeInTheDocument();
      });
    });

    it('should not show mark all read button when no unread notifications', async () => {
      useNotificationStore.setState({
        notifications: mockNotifications.map((n) => ({ ...n, read: true })),
        unreadCount: 0,
        isLoading: false,
      });

      const { user } = render(<NotificationsDropdown />);

      // Open dropdown
      const trigger = screen.getByRole('button');
      await user.click(trigger);

      await waitFor(() => {
        expect(screen.queryByText('Mark all read')).not.toBeInTheDocument();
      });
    });

    it('should call markAllAsRead when mark all read is clicked', async () => {
      const markAllAsReadSpy = vi.fn();
      useNotificationStore.setState({
        notifications: mockNotifications,
        unreadCount: 2,
        isLoading: false,
        markAllAsRead: markAllAsReadSpy,
      });

      const { user } = render(<NotificationsDropdown />);

      // Open dropdown
      const trigger = screen.getByRole('button');
      await user.click(trigger);

      await waitFor(() => {
        expect(screen.getByText('Mark all read')).toBeInTheDocument();
      });

      // Click mark all read
      const markAllButton = screen.getByText('Mark all read');
      await user.click(markAllButton);

      expect(markAllAsReadSpy).toHaveBeenCalled();
    });

    it('should call markAsRead when clicking unread notification', async () => {
      const markAsReadSpy = vi.fn();
      useNotificationStore.setState({
        notifications: mockNotifications,
        unreadCount: 2,
        isLoading: false,
        markAsRead: markAsReadSpy,
      });

      const { user } = render(<NotificationsDropdown />);

      // Open dropdown
      const trigger = screen.getByRole('button');
      await user.click(trigger);

      await waitFor(() => {
        expect(screen.getByText('New Share')).toBeInTheDocument();
      });

      // Click unread notification
      const notification = screen.getByText('New Share');
      await user.click(notification);

      expect(markAsReadSpy).toHaveBeenCalledWith('notif-1');
    });

    it('should not call markAsRead when clicking already read notification', async () => {
      const markAsReadSpy = vi.fn();
      useNotificationStore.setState({
        notifications: mockNotifications,
        unreadCount: 2,
        isLoading: false,
        markAsRead: markAsReadSpy,
      });

      const { user } = render(<NotificationsDropdown />);

      // Open dropdown
      const trigger = screen.getByRole('button');
      await user.click(trigger);

      await waitFor(() => {
        expect(screen.getByText('Share Accepted')).toBeInTheDocument();
      });

      // Click already read notification (notif-2)
      const notification = screen.getByText('Share Accepted');
      await user.click(notification);

      expect(markAsReadSpy).not.toHaveBeenCalled();
    });

    it('should show Notifications label in dropdown', async () => {
      useNotificationStore.setState({
        notifications: [],
        unreadCount: 0,
        isLoading: false,
      });

      const { user } = render(<NotificationsDropdown />);

      // Open dropdown
      const trigger = screen.getByRole('button');
      await user.click(trigger);

      await waitFor(() => {
        expect(screen.getByText('Notifications')).toBeInTheDocument();
      });
    });

    it('should show notification messages', async () => {
      useNotificationStore.setState({
        notifications: mockNotifications,
        unreadCount: 2,
        isLoading: false,
      });

      const { user } = render(<NotificationsDropdown />);

      // Open dropdown
      const trigger = screen.getByRole('button');
      await user.click(trigger);

      await waitFor(() => {
        expect(screen.getByText('John shared a file with you')).toBeInTheDocument();
        expect(screen.getByText('Jane accepted your share')).toBeInTheDocument();
      });
    });

    it('should highlight unread notifications', async () => {
      useNotificationStore.setState({
        notifications: [mockNotifications[0]], // Only unread notification
        unreadCount: 1,
        isLoading: false,
      });

      const { user } = render(<NotificationsDropdown />);

      // Open dropdown
      const trigger = screen.getByRole('button');
      await user.click(trigger);

      await waitFor(() => {
        const notificationItem = screen.getByText('New Share').closest('[class*="cursor-pointer"]');
        expect(notificationItem).toHaveClass('bg-primary/5');
      });
    });

    it('should show unread indicator dot for unread notifications', async () => {
      useNotificationStore.setState({
        notifications: [mockNotifications[0]], // Only unread notification
        unreadCount: 1,
        isLoading: false,
      });

      const { user } = render(<NotificationsDropdown />);

      // Open dropdown
      const trigger = screen.getByRole('button');
      await user.click(trigger);

      await waitFor(() => {
        // Unread indicator is a small dot - check for 2x2 rounded-full element
        const unreadDots = document.querySelectorAll('.rounded-full');
        // At least one should be a small indicator dot
        expect(unreadDots.length).toBeGreaterThan(0);
      });
    });
  });

  describe('notification icons', () => {
    it('should show share icon for share_received type', async () => {
      useNotificationStore.setState({
        notifications: [mockNotifications[0]], // share_received
        unreadCount: 1,
        isLoading: false,
      });

      const { user } = render(<NotificationsDropdown />);

      // Open dropdown
      const trigger = screen.getByRole('button');
      await user.click(trigger);

      await waitFor(() => {
        // Lucide icon class is lucide-share2 (no hyphen before 2)
        expect(document.querySelector('.lucide-share2')).toBeInTheDocument();
      });
    });

    it('should show user-check icon for share_accepted type', async () => {
      useNotificationStore.setState({
        notifications: [mockNotifications[1]], // share_accepted
        unreadCount: 0,
        isLoading: false,
      });

      const { user } = render(<NotificationsDropdown />);

      // Open dropdown
      const trigger = screen.getByRole('button');
      await user.click(trigger);

      await waitFor(() => {
        // Lucide icon class is lucide-user-check
        expect(document.querySelector('.lucide-user-check')).toBeInTheDocument();
      });
    });

    it('should show key icon for recovery_request type', async () => {
      useNotificationStore.setState({
        notifications: [mockNotifications[2]], // recovery_request
        unreadCount: 1,
        isLoading: false,
      });

      const { user } = render(<NotificationsDropdown />);

      // Open dropdown
      const trigger = screen.getByRole('button');
      await user.click(trigger);

      await waitFor(() => {
        expect(document.querySelector('.lucide-key')).toBeInTheDocument();
      });
    });

    it('should show info icon for system type', async () => {
      useNotificationStore.setState({
        notifications: [mockNotifications[3]], // system
        unreadCount: 0,
        isLoading: false,
      });

      const { user } = render(<NotificationsDropdown />);

      // Open dropdown
      const trigger = screen.getByRole('button');
      await user.click(trigger);

      await waitFor(() => {
        expect(document.querySelector('.lucide-info')).toBeInTheDocument();
      });
    });
  });
});
