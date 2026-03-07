import { useEffect, useState, useMemo } from 'react';
import { Bell, Share2, UserCheck, Key, Info, CheckCheck, Loader2, Filter } from 'lucide-react';
import { useNotificationStore, NotificationType } from '@/stores/notificationStore';
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuLabel,
  DropdownMenuSeparator,
  DropdownMenuTrigger,
} from '@/components/ui/DropdownMenu';
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from '@/components/ui/select';
import { Button } from '@/components/ui/Button';
import { formatDistanceToNow } from '@/lib/utils';

type NotificationFilter = 'all' | NotificationType;

const FILTER_OPTIONS: { value: NotificationFilter; label: string }[] = [
  { value: 'all', label: 'All' },
  { value: 'share_received', label: 'Shares Received' },
  { value: 'share_accepted', label: 'Shares Accepted' },
  { value: 'recovery_request', label: 'Recovery Requests' },
  { value: 'system', label: 'System' },
];

function getNotificationIcon(type: NotificationType) {
  switch (type) {
    case 'share_received':
      return <Share2 className="h-4 w-4 text-blue-500" />;
    case 'share_accepted':
      return <UserCheck className="h-4 w-4 text-green-500" />;
    case 'recovery_request':
      return <Key className="h-4 w-4 text-amber-500" />;
    case 'system':
    default:
      return <Info className="h-4 w-4 text-muted-foreground" />;
  }
}

export function NotificationsDropdown() {
  const {
    notifications,
    unreadCount,
    isLoading,
    loadNotifications,
    markAsRead,
    markAllAsRead,
  } = useNotificationStore();

  const [filter, setFilter] = useState<NotificationFilter>('all');

  useEffect(() => {
    loadNotifications();
  }, [loadNotifications]);

  // Filter notifications based on selected type
  const filteredNotifications = useMemo(() => {
    if (filter === 'all') {
      return notifications;
    }
    return notifications.filter((n) => n.type === filter);
  }, [notifications, filter]);

  const handleNotificationClick = (id: string, read: boolean) => {
    if (!read) {
      markAsRead(id);
    }
  };

  return (
    <DropdownMenu>
      <DropdownMenuTrigger asChild>
        <Button variant="ghost" size="icon" className="relative">
          <Bell className="h-5 w-5" />
          {unreadCount > 0 && (
            <span className="absolute -top-1 -right-1 h-5 w-5 flex items-center justify-center bg-primary text-primary-foreground text-xs font-medium rounded-full">
              {unreadCount > 9 ? '9+' : unreadCount}
            </span>
          )}
        </Button>
      </DropdownMenuTrigger>
      <DropdownMenuContent align="end" className="w-80">
        <DropdownMenuLabel className="flex items-center justify-between">
          <span>Notifications</span>
          {unreadCount > 0 && (
            <Button
              variant="ghost"
              size="sm"
              className="h-auto py-0 px-2 text-xs"
              onClick={(e) => {
                e.preventDefault();
                markAllAsRead();
              }}
            >
              <CheckCheck className="h-3 w-3 mr-1" />
              Mark all read
            </Button>
          )}
        </DropdownMenuLabel>

        {/* Filter */}
        <div className="px-2 py-2">
          <Select
            value={filter}
            onValueChange={(value) => setFilter(value as NotificationFilter)}
          >
            <SelectTrigger className="h-8 text-xs">
              <Filter className="h-3 w-3 mr-2" />
              <SelectValue placeholder="Filter by type" />
            </SelectTrigger>
            <SelectContent>
              {FILTER_OPTIONS.map((option) => (
                <SelectItem key={option.value} value={option.value}>
                  {option.label}
                </SelectItem>
              ))}
            </SelectContent>
          </Select>
        </div>

        <DropdownMenuSeparator />

        {isLoading ? (
          <div className="flex items-center justify-center py-8">
            <Loader2 className="h-6 w-6 animate-spin text-muted-foreground" />
          </div>
        ) : filteredNotifications.length === 0 ? (
          <div className="flex flex-col items-center justify-center py-8 text-muted-foreground">
            <Bell className="h-8 w-8 mb-2 opacity-50" />
            <p className="text-sm">
              {filter === 'all' ? 'No notifications' : 'No notifications in this category'}
            </p>
            {filter !== 'all' && (
              <Button
                variant="ghost"
                size="sm"
                className="mt-2"
                onClick={() => setFilter('all')}
              >
                Show all
              </Button>
            )}
          </div>
        ) : (
          <div className="max-h-96 overflow-y-auto">
            {filteredNotifications.map((notification) => (
              <DropdownMenuItem
                key={notification.id}
                className={`flex items-start gap-3 p-3 cursor-pointer ${
                  !notification.read ? 'bg-primary/5' : ''
                }`}
                onClick={() =>
                  handleNotificationClick(notification.id, notification.read)
                }
              >
                <div className="mt-0.5">
                  {getNotificationIcon(notification.type)}
                </div>
                <div className="flex-1 min-w-0">
                  <p
                    className={`text-sm ${
                      !notification.read ? 'font-medium' : ''
                    }`}
                  >
                    {notification.title}
                  </p>
                  <p className="text-xs text-muted-foreground truncate">
                    {notification.message}
                  </p>
                  <p className="text-xs text-muted-foreground mt-1">
                    {formatDistanceToNow(notification.created_at)}
                  </p>
                </div>
                {!notification.read && (
                  <div className="w-2 h-2 rounded-full bg-primary mt-1.5" />
                )}
              </DropdownMenuItem>
            ))}
          </div>
        )}
      </DropdownMenuContent>
    </DropdownMenu>
  );
}
