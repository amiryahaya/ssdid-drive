import { describe, it, expect, vi, beforeEach } from 'vitest';
import { screen, waitFor } from '@testing-library/react';
import { invoke } from '@tauri-apps/api/core';
import { render } from '../../../test/utils';
import { NotificationsPanel } from '../NotificationsPanel';
import { useNotificationStore } from '../../../stores/notificationStore';
import { mockNotifications } from '../../../test/mocks/tauri';

vi.mock('@tauri-apps/api/core');

const mockInvoke = vi.mocked(invoke);

describe('NotificationsPanel', () => {
  beforeEach(() => {
    vi.clearAllMocks();
    useNotificationStore.setState({
      notifications: [],
      unreadCount: 0,
      isLoading: false,
      error: null,
    });

    mockInvoke.mockImplementation(async (cmd: string) => {
      switch (cmd) {
        case 'get_notifications':
          return mockNotifications;
        case 'mark_notification_read':
          return undefined;
        case 'mark_all_notifications_read':
          return undefined;
        default:
          return undefined;
      }
    });
  });

  const renderPanel = () => {
    return render(<NotificationsPanel />);
  };

  it('should render header with title', () => {
    renderPanel();

    expect(screen.getByText('Notifications')).toBeInTheDocument();
  });

  it('should show loading state', () => {
    useNotificationStore.setState({ isLoading: true });

    renderPanel();

    expect(screen.getByText('Loading...')).toBeInTheDocument();
  });

  it('should show empty state when no notifications', async () => {
    mockInvoke.mockImplementation(async (cmd: string) => {
      if (cmd === 'get_notifications') return [];
      return undefined;
    });

    renderPanel();

    await waitFor(() => {
      expect(screen.getByText('All caught up')).toBeInTheDocument();
    });
    expect(screen.getByText('No notifications at the moment.')).toBeInTheDocument();
  });

  it('should display notifications', async () => {
    renderPanel();

    await waitFor(() => {
      expect(screen.getByText('New share received')).toBeInTheDocument();
    });
    expect(screen.getByText('Share accepted')).toBeInTheDocument();
    expect(screen.getByText('System update')).toBeInTheDocument();
    expect(screen.getByText('Recovery request')).toBeInTheDocument();
  });

  it('should display notification messages', async () => {
    renderPanel();

    await waitFor(() => {
      expect(
        screen.getByText('Alice Smith shared "Document.pdf" with you')
      ).toBeInTheDocument();
    });
    expect(
      screen.getByText('Bob Jones accepted your share of "Project Files"')
    ).toBeInTheDocument();
  });

  it('should show unread count badge', async () => {
    renderPanel();

    const unreadCount = mockNotifications.filter((n) => !n.read).length;
    await waitFor(() => {
      expect(screen.getByText(String(unreadCount))).toBeInTheDocument();
    });
  });

  it('should show "Mark all as read" button when there are unread notifications', async () => {
    renderPanel();

    await waitFor(() => {
      expect(screen.getByText('Mark all as read')).toBeInTheDocument();
    });
  });

  it('should not show "Mark all as read" button when all notifications are read', async () => {
    const readNotifications = mockNotifications.map((n) => ({ ...n, read: true }));
    mockInvoke.mockImplementation(async (cmd: string) => {
      if (cmd === 'get_notifications') return readNotifications;
      return undefined;
    });

    renderPanel();

    await waitFor(() => {
      expect(screen.getByText('System update')).toBeInTheDocument();
    });
    expect(screen.queryByText('Mark all as read')).not.toBeInTheDocument();
  });

  it('should mark notification as read on click', async () => {
    const { user } = renderPanel();

    await waitFor(() => {
      expect(screen.getByText('New share received')).toBeInTheDocument();
    });

    // Click the first unread notification
    const notifTitle = screen.getByText('New share received');
    await user.click(notifTitle.closest('[role="button"]')!);

    await waitFor(() => {
      expect(mockInvoke).toHaveBeenCalledWith('mark_notification_read', {
        notificationId: 'notif-1',
      });
    });
  });

  it('should not call markAsRead when clicking already-read notification', async () => {
    // Use only the read notification
    const readNotification = mockNotifications.find((n) => n.read)!;
    mockInvoke.mockImplementation(async (cmd: string) => {
      if (cmd === 'get_notifications') return [readNotification];
      return undefined;
    });

    const { user } = renderPanel();

    await waitFor(() => {
      expect(screen.getByText('System update')).toBeInTheDocument();
    });

    const notifTitle = screen.getByText('System update');
    await user.click(notifTitle.closest('[role="button"]')!);

    // mark_notification_read should NOT be called
    await waitFor(() => {
      expect(mockInvoke).not.toHaveBeenCalledWith(
        'mark_notification_read',
        expect.any(Object)
      );
    });
  });

  it('should call markAllAsRead when clicking mark all button', async () => {
    const { user } = renderPanel();

    await waitFor(() => {
      expect(screen.getByText('Mark all as read')).toBeInTheDocument();
    });

    const markAllButton = screen.getByText('Mark all as read');
    await user.click(markAllButton);

    await waitFor(() => {
      expect(mockInvoke).toHaveBeenCalledWith('mark_all_notifications_read');
    });
  });

  it('should remove notification when clicking dismiss button', async () => {
    mockInvoke.mockImplementation(async (cmd: string) => {
      if (cmd === 'get_notifications') return [mockNotifications[0]];
      return undefined;
    });

    const { user } = renderPanel();

    await waitFor(() => {
      expect(screen.getByText('New share received')).toBeInTheDocument();
    });

    const dismissButton = screen.getByLabelText(
      'Dismiss notification: New share received'
    );
    await user.click(dismissButton);

    // After removal, the notification should be gone from state
    const state = useNotificationStore.getState();
    expect(state.notifications).toHaveLength(0);
  });

  it('should visually distinguish unread from read notifications', async () => {
    renderPanel();

    await waitFor(() => {
      expect(screen.getByText('New share received')).toBeInTheDocument();
    });

    // Unread notification title should have font-semibold
    const unreadTitle = screen.getByText('New share received');
    expect(unreadTitle).toHaveClass('font-semibold');

    // Read notification title should have font-medium (not font-semibold)
    const readTitle = screen.getByText('System update');
    expect(readTitle).toHaveClass('font-medium');
    expect(readTitle).not.toHaveClass('font-semibold');
  });

  it('should show unread indicator dot for unread notifications', async () => {
    mockInvoke.mockImplementation(async (cmd: string) => {
      if (cmd === 'get_notifications') return [mockNotifications[0]];
      return undefined;
    });

    renderPanel();

    await waitFor(() => {
      expect(screen.getByText('New share received')).toBeInTheDocument();
    });

    // The unread dot should be present (a small span with rounded-full and bg-primary)
    const container = screen.getByText('New share received').closest('[role="button"]')!;
    const dot = container.querySelector('.rounded-full.bg-primary');
    expect(dot).toBeInTheDocument();
  });

  it('should display time ago for notifications', async () => {
    mockInvoke.mockImplementation(async (cmd: string) => {
      if (cmd === 'get_notifications') return [mockNotifications[0]];
      return undefined;
    });

    renderPanel();

    await waitFor(() => {
      expect(screen.getByText('5m ago')).toBeInTheDocument();
    });
  });

  it('should load notifications on mount', async () => {
    renderPanel();

    await waitFor(() => {
      expect(mockInvoke).toHaveBeenCalledWith('get_notifications');
    });
  });

  it('should accept className prop', async () => {
    mockInvoke.mockImplementation(async (cmd: string) => {
      if (cmd === 'get_notifications') return [];
      return undefined;
    });

    const { container } = render(<NotificationsPanel className="w-80" />);

    const panel = container.firstChild as HTMLElement;
    expect(panel).toHaveClass('w-80');
  });
});
