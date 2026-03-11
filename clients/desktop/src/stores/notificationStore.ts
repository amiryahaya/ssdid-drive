import { create } from 'zustand';
import { invoke } from '@tauri-apps/api/core';

export type NotificationType =
  | 'share_received'
  | 'share_accepted'
  | 'recovery_request'
  | 'system';

export interface Notification {
  id: string;
  type: NotificationType;
  title: string;
  message: string;
  read: boolean;
  created_at: string;
  metadata?: Record<string, unknown>;
}

const POLL_INTERVAL_MS = 30_000; // 30 seconds

interface NotificationState {
  notifications: Notification[];
  unreadCount: number;
  isLoading: boolean;
  error: string | null;
  _pollTimer: ReturnType<typeof setInterval> | null;

  // Actions
  loadNotifications: () => Promise<void>;
  markAsRead: (id: string) => Promise<void>;
  markAllAsRead: () => Promise<void>;
  removeNotification: (id: string) => void;
  clearError: () => void;
  startPolling: () => void;
  stopPolling: () => void;
}

export const useNotificationStore = create<NotificationState>((set, get) => ({
  notifications: [],
  unreadCount: 0,
  isLoading: false,
  error: null,
  _pollTimer: null,

  loadNotifications: async () => {
    set({ isLoading: true, error: null });
    try {
      const notifications = await invoke<Notification[]>('get_notifications');
      const unreadCount = notifications.filter((n) => !n.read).length;
      set({ notifications, unreadCount, isLoading: false });
    } catch (error) {
      const message = error instanceof Error ? error.message : String(error);
      set({ error: message, isLoading: false });
    }
  },

  markAsRead: async (id) => {
    try {
      await invoke('mark_notification_read', { notificationId: id });
      set((state) => {
        const notifications = state.notifications.map((n) =>
          n.id === id ? { ...n, read: true } : n
        );
        const unreadCount = notifications.filter((n) => !n.read).length;
        return { notifications, unreadCount };
      });
    } catch (error) {
      const message = error instanceof Error ? error.message : String(error);
      set({ error: message });
    }
  },

  markAllAsRead: async () => {
    try {
      await invoke('mark_all_notifications_read');
      set((state) => ({
        notifications: state.notifications.map((n) => ({ ...n, read: true })),
        unreadCount: 0,
      }));
    } catch (error) {
      const message = error instanceof Error ? error.message : String(error);
      set({ error: message });
    }
  },

  removeNotification: (id) => {
    set((state) => {
      const notifications = state.notifications.filter((n) => n.id !== id);
      const unreadCount = notifications.filter((n) => !n.read).length;
      return { notifications, unreadCount };
    });
  },

  clearError: () => set({ error: null }),

  startPolling: () => {
    const { _pollTimer } = get();
    if (_pollTimer) return; // already polling

    // Load immediately, then poll
    get().loadNotifications();
    const timer = setInterval(() => {
      get().loadNotifications();
    }, POLL_INTERVAL_MS);
    set({ _pollTimer: timer });
  },

  stopPolling: () => {
    const { _pollTimer } = get();
    if (_pollTimer) {
      clearInterval(_pollTimer);
      set({ _pollTimer: null });
    }
  },
}));
