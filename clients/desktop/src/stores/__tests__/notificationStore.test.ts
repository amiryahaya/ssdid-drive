import { describe, it, expect, beforeEach, vi } from 'vitest';
import { useNotificationStore, Notification } from '../notificationStore';
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
    read: false,
    created_at: '2024-01-15T09:00:00Z',
  },
  {
    id: 'notif-3',
    type: 'system',
    title: 'System Update',
    message: 'New version available',
    read: true,
    created_at: '2024-01-14T08:00:00Z',
  },
];

describe('notificationStore', () => {
  beforeEach(() => {
    vi.clearAllMocks();
    // Reset store to initial state
    useNotificationStore.setState({
      notifications: [],
      unreadCount: 0,
      isLoading: false,
      error: null,
    });
  });

  describe('initial state', () => {
    it('should have empty notifications initially', () => {
      const state = useNotificationStore.getState();
      expect(state.notifications).toEqual([]);
      expect(state.unreadCount).toBe(0);
      expect(state.isLoading).toBe(false);
      expect(state.error).toBeNull();
    });
  });

  describe('loadNotifications', () => {
    it('should set loading state while fetching', async () => {
      mockInvoke.mockImplementation(
        () => new Promise((resolve) => setTimeout(() => resolve(mockNotifications), 100))
      );

      const loadPromise = useNotificationStore.getState().loadNotifications();

      expect(useNotificationStore.getState().isLoading).toBe(true);
      expect(useNotificationStore.getState().error).toBeNull();

      await loadPromise;
    });

    it('should load notifications and calculate unread count', async () => {
      mockInvoke.mockResolvedValueOnce(mockNotifications);

      await useNotificationStore.getState().loadNotifications();

      expect(mockInvoke).toHaveBeenCalledWith('get_notifications');
      expect(useNotificationStore.getState().notifications).toEqual(mockNotifications);
      expect(useNotificationStore.getState().unreadCount).toBe(2); // 2 unread
      expect(useNotificationStore.getState().isLoading).toBe(false);
    });

    it('should set unreadCount to 0 when all notifications are read', async () => {
      const allReadNotifications = mockNotifications.map((n) => ({ ...n, read: true }));
      mockInvoke.mockResolvedValueOnce(allReadNotifications);

      await useNotificationStore.getState().loadNotifications();

      expect(useNotificationStore.getState().unreadCount).toBe(0);
    });

    it('should handle empty notifications', async () => {
      mockInvoke.mockResolvedValueOnce([]);

      await useNotificationStore.getState().loadNotifications();

      expect(useNotificationStore.getState().notifications).toEqual([]);
      expect(useNotificationStore.getState().unreadCount).toBe(0);
    });

    it('should set error on failure', async () => {
      mockInvoke.mockRejectedValueOnce(new Error('Network error'));

      await useNotificationStore.getState().loadNotifications();

      expect(useNotificationStore.getState().error).toBe('Network error');
      expect(useNotificationStore.getState().isLoading).toBe(false);
    });
  });

  describe('markAsRead', () => {
    beforeEach(() => {
      useNotificationStore.setState({
        notifications: mockNotifications,
        unreadCount: 2,
      });
    });

    it('should mark a notification as read', async () => {
      mockInvoke.mockResolvedValueOnce(undefined);

      await useNotificationStore.getState().markAsRead('notif-1');

      expect(mockInvoke).toHaveBeenCalledWith('mark_notification_read', {
        notificationId: 'notif-1',
      });

      const notification = useNotificationStore
        .getState()
        .notifications.find((n) => n.id === 'notif-1');
      expect(notification?.read).toBe(true);
    });

    it('should update unread count after marking as read', async () => {
      mockInvoke.mockResolvedValueOnce(undefined);

      await useNotificationStore.getState().markAsRead('notif-1');

      expect(useNotificationStore.getState().unreadCount).toBe(1);
    });

    it('should not change other notifications', async () => {
      mockInvoke.mockResolvedValueOnce(undefined);

      await useNotificationStore.getState().markAsRead('notif-1');

      const notif2 = useNotificationStore
        .getState()
        .notifications.find((n) => n.id === 'notif-2');
      expect(notif2?.read).toBe(false);
    });

    it('should set error on failure', async () => {
      mockInvoke.mockRejectedValueOnce(new Error('Failed to mark as read'));

      await useNotificationStore.getState().markAsRead('notif-1');

      expect(useNotificationStore.getState().error).toBe('Failed to mark as read');
    });
  });

  describe('markAllAsRead', () => {
    beforeEach(() => {
      useNotificationStore.setState({
        notifications: mockNotifications,
        unreadCount: 2,
      });
    });

    it('should mark all notifications as read', async () => {
      mockInvoke.mockResolvedValueOnce(undefined);

      await useNotificationStore.getState().markAllAsRead();

      expect(mockInvoke).toHaveBeenCalledWith('mark_all_notifications_read');

      const notifications = useNotificationStore.getState().notifications;
      expect(notifications.every((n) => n.read)).toBe(true);
    });

    it('should set unread count to 0', async () => {
      mockInvoke.mockResolvedValueOnce(undefined);

      await useNotificationStore.getState().markAllAsRead();

      expect(useNotificationStore.getState().unreadCount).toBe(0);
    });

    it('should set error on failure', async () => {
      mockInvoke.mockRejectedValueOnce(new Error('Failed to mark all as read'));

      await useNotificationStore.getState().markAllAsRead();

      expect(useNotificationStore.getState().error).toBe('Failed to mark all as read');
    });
  });

  describe('removeNotification', () => {
    beforeEach(() => {
      useNotificationStore.setState({
        notifications: mockNotifications,
        unreadCount: 2,
      });
    });

    it('should remove a notification from the list', () => {
      useNotificationStore.getState().removeNotification('notif-1');

      const notifications = useNotificationStore.getState().notifications;
      expect(notifications.length).toBe(2);
      expect(notifications.find((n) => n.id === 'notif-1')).toBeUndefined();
    });

    it('should update unread count when removing unread notification', () => {
      useNotificationStore.getState().removeNotification('notif-1');

      expect(useNotificationStore.getState().unreadCount).toBe(1);
    });

    it('should not change unread count when removing read notification', () => {
      useNotificationStore.getState().removeNotification('notif-3');

      expect(useNotificationStore.getState().unreadCount).toBe(2);
    });

    it('should handle removing non-existent notification', () => {
      useNotificationStore.getState().removeNotification('non-existent');

      expect(useNotificationStore.getState().notifications.length).toBe(3);
    });
  });

  describe('clearError', () => {
    it('should clear error state', () => {
      useNotificationStore.setState({ error: 'Some error' });

      useNotificationStore.getState().clearError();

      expect(useNotificationStore.getState().error).toBeNull();
    });
  });
});
