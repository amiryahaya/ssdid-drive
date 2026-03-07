import { useEffect, useCallback } from 'react';
import {
  Bell,
  Check,
  CheckCheck,
  Key,
  Loader2,
  Monitor,
  Share2,
  UserCheck,
  X,
} from 'lucide-react';
import { Button } from '../ui/Button';
import {
  useNotificationStore,
  type Notification,
  type NotificationType,
} from '../../stores/notificationStore';
import { cn, formatDistanceToNow } from '../../lib/utils';

function getNotificationIcon(type: NotificationType) {
  switch (type) {
    case 'share_received':
      return Share2;
    case 'share_accepted':
      return UserCheck;
    case 'recovery_request':
      return Key;
    case 'system':
      return Monitor;
    default:
      return Bell;
  }
}

function getNotificationIconColor(type: NotificationType): string {
  switch (type) {
    case 'share_received':
      return 'text-blue-500 bg-blue-100 dark:bg-blue-900/30';
    case 'share_accepted':
      return 'text-green-500 bg-green-100 dark:bg-green-900/30';
    case 'recovery_request':
      return 'text-orange-500 bg-orange-100 dark:bg-orange-900/30';
    case 'system':
      return 'text-gray-500 bg-gray-100 dark:bg-gray-900/30';
    default:
      return 'text-gray-500 bg-gray-100 dark:bg-gray-900/30';
  }
}

function NotificationItem({
  notification,
  onMarkAsRead,
  onRemove,
}: {
  notification: Notification;
  onMarkAsRead: (id: string) => void;
  onRemove: (id: string) => void;
}) {
  const Icon = getNotificationIcon(notification.type);
  const iconColor = getNotificationIconColor(notification.type);

  const handleClick = useCallback(() => {
    if (!notification.read) {
      onMarkAsRead(notification.id);
    }
  }, [notification.id, notification.read, onMarkAsRead]);

  const handleRemove = useCallback(
    (e: React.MouseEvent) => {
      e.stopPropagation();
      onRemove(notification.id);
    },
    [notification.id, onRemove]
  );

  return (
    <div
      role="button"
      tabIndex={0}
      className={cn(
        'group flex items-start gap-3 rounded-lg p-3 transition-colors',
        'hover:bg-accent cursor-pointer',
        !notification.read && 'bg-accent/50'
      )}
      onClick={handleClick}
      onKeyDown={(e) => {
        if (e.key === 'Enter' || e.key === ' ') {
          e.preventDefault();
          handleClick();
        }
      }}
    >
      {/* Icon */}
      <div className={cn('flex h-8 w-8 shrink-0 items-center justify-center rounded-full', iconColor)}>
        <Icon className="h-4 w-4" />
      </div>

      {/* Content */}
      <div className="flex-1 min-w-0 space-y-1">
        <div className="flex items-start justify-between gap-2">
          <p
            className={cn(
              'text-sm leading-tight',
              !notification.read ? 'font-semibold' : 'font-medium'
            )}
          >
            {notification.title}
          </p>
          {/* Unread dot */}
          {!notification.read && (
            <span className="mt-1 h-2 w-2 shrink-0 rounded-full bg-primary" />
          )}
        </div>
        <p className="text-xs text-muted-foreground line-clamp-2">
          {notification.message}
        </p>
        <p className="text-xs text-muted-foreground/70">
          {formatDistanceToNow(notification.created_at)}
        </p>
      </div>

      {/* Remove button */}
      <Button
        variant="ghost"
        size="icon"
        className="h-7 w-7 shrink-0 opacity-0 group-hover:opacity-100 transition-opacity"
        onClick={handleRemove}
        aria-label={`Dismiss notification: ${notification.title}`}
      >
        <X className="h-3.5 w-3.5" />
      </Button>
    </div>
  );
}

interface NotificationsPanelProps {
  className?: string;
}

export function NotificationsPanel({ className }: NotificationsPanelProps) {
  const {
    notifications,
    unreadCount,
    isLoading,
    loadNotifications,
    markAsRead,
    markAllAsRead,
    removeNotification,
  } = useNotificationStore();

  useEffect(() => {
    loadNotifications();
  }, [loadNotifications]);

  const handleMarkAsRead = useCallback(
    async (id: string) => {
      await markAsRead(id);
    },
    [markAsRead]
  );

  const handleRemove = useCallback(
    (id: string) => {
      removeNotification(id);
    },
    [removeNotification]
  );

  const handleMarkAllAsRead = useCallback(async () => {
    await markAllAsRead();
  }, [markAllAsRead]);

  return (
    <div className={cn('flex flex-col', className)}>
      {/* Header */}
      <div className="flex items-center justify-between border-b px-4 py-3">
        <div className="flex items-center gap-2">
          <h2 className="text-sm font-semibold">Notifications</h2>
          {unreadCount > 0 && (
            <span className="flex h-5 min-w-5 items-center justify-center rounded-full bg-primary px-1.5 text-xs font-medium text-primary-foreground">
              {unreadCount}
            </span>
          )}
        </div>
        {unreadCount > 0 && (
          <Button
            variant="ghost"
            size="sm"
            className="h-7 gap-1 text-xs"
            onClick={handleMarkAllAsRead}
          >
            <CheckCheck className="h-3.5 w-3.5" />
            Mark all as read
          </Button>
        )}
      </div>

      {/* Notification list */}
      <div className="flex-1 overflow-y-auto">
        {isLoading ? (
          <div className="flex items-center justify-center py-8">
            <Loader2 className="h-5 w-5 animate-spin text-muted-foreground" />
            <span className="ml-2 text-sm text-muted-foreground">Loading...</span>
          </div>
        ) : notifications.length === 0 ? (
          <div className="flex flex-col items-center justify-center py-12 text-center px-4">
            <div className="flex h-12 w-12 items-center justify-center rounded-full bg-muted">
              <Check className="h-6 w-6 text-muted-foreground" />
            </div>
            <p className="mt-3 text-sm font-medium text-muted-foreground">
              All caught up
            </p>
            <p className="mt-1 text-xs text-muted-foreground">
              No notifications at the moment.
            </p>
          </div>
        ) : (
          <div className="divide-y">
            {notifications.map((notification) => (
              <NotificationItem
                key={notification.id}
                notification={notification}
                onMarkAsRead={handleMarkAsRead}
                onRemove={handleRemove}
              />
            ))}
          </div>
        )}
      </div>
    </div>
  );
}
