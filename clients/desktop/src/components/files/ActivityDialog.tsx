import { useEffect, useState, useCallback } from 'react';
import {
  Activity,
  Upload,
  Download,
  Pencil,
  FolderInput,
  Trash2,
  Eye,
  Share2,
  UserMinus,
  Shield,
  FolderPlus,
  Loader2,
} from 'lucide-react';
import {
  Dialog,
  DialogContent,
  DialogHeader,
  DialogTitle,
} from '../ui/dialog';
import { Button } from '../ui/Button';
import { cn, formatDistanceToNow } from '@/lib/utils';
import tauriService from '@/services/tauri';
import type { ActivityItem } from '@/services/tauri';

interface ActivityDialogProps {
  open: boolean;
  onOpenChange: (open: boolean) => void;
  resourceId: string;
  resourceName: string;
}

function getEventIcon(eventType: string) {
  switch (eventType) {
    case 'file.uploaded':
      return Upload;
    case 'file.downloaded':
      return Download;
    case 'file.renamed':
      return Pencil;
    case 'file.moved':
      return FolderInput;
    case 'file.deleted':
      return Trash2;
    case 'file.previewed':
      return Eye;
    case 'file.shared':
      return Share2;
    case 'share.revoked':
      return UserMinus;
    case 'permission.changed':
      return Shield;
    case 'folder.created':
      return FolderPlus;
    default:
      return Activity;
  }
}

function getEventColor(eventType: string): string {
  switch (eventType) {
    case 'file.uploaded':
    case 'file.shared':
      return 'text-green-600 bg-green-100 dark:text-green-400 dark:bg-green-900/30';
    case 'file.downloaded':
      return 'text-blue-600 bg-blue-100 dark:text-blue-400 dark:bg-blue-900/30';
    case 'file.renamed':
      return 'text-purple-600 bg-purple-100 dark:text-purple-400 dark:bg-purple-900/30';
    case 'file.moved':
    case 'folder.created':
    case 'permission.changed':
      return 'text-amber-600 bg-amber-100 dark:text-amber-400 dark:bg-amber-900/30';
    case 'file.deleted':
    case 'share.revoked':
      return 'text-red-600 bg-red-100 dark:text-red-400 dark:bg-red-900/30';
    case 'file.previewed':
      return 'text-gray-600 bg-gray-100 dark:text-gray-400 dark:bg-gray-900/30';
    default:
      return 'text-muted-foreground bg-muted';
  }
}

function getEventDescription(item: ActivityItem): string {
  const actor = item.actor_name ?? 'Someone';

  switch (item.event_type) {
    case 'file.uploaded':
      return `${actor} uploaded this file`;
    case 'file.downloaded':
      return `${actor} downloaded this file`;
    case 'file.renamed': {
      const oldName = item.details?.old_name;
      return oldName
        ? `${actor} renamed from "${oldName}"`
        : `${actor} renamed this file`;
    }
    case 'file.moved': {
      const dest = item.details?.destination;
      return dest
        ? `${actor} moved to "${dest}"`
        : `${actor} moved this file`;
    }
    case 'file.deleted':
      return `${actor} deleted this file`;
    case 'file.previewed':
      return `${actor} previewed this file`;
    case 'file.shared': {
      const sharedWith = item.details?.shared_with;
      return sharedWith
        ? `${actor} shared with ${sharedWith}`
        : `${actor} shared this file`;
    }
    case 'share.revoked':
      return `${actor} revoked sharing`;
    case 'permission.changed': {
      const perm = item.details?.new_permission;
      return perm
        ? `${actor} changed permission to ${perm}`
        : `${actor} changed permissions`;
    }
    case 'folder.created':
      return `${actor} created this folder`;
    default:
      return `${actor} performed ${item.event_type}`;
  }
}

function getDateGroup(dateString: string): string {
  const date = new Date(dateString);
  const now = new Date();
  const today = new Date(now.getFullYear(), now.getMonth(), now.getDate());
  const yesterday = new Date(today);
  yesterday.setDate(yesterday.getDate() - 1);

  const itemDate = new Date(
    date.getFullYear(),
    date.getMonth(),
    date.getDate()
  );

  if (itemDate.getTime() >= today.getTime()) return 'Today';
  if (itemDate.getTime() >= yesterday.getTime()) return 'Yesterday';
  return 'Earlier';
}

const PAGE_SIZE = 10;

export function ActivityDialog({
  open,
  onOpenChange,
  resourceId,
  resourceName,
}: ActivityDialogProps) {
  const [items, setItems] = useState<ActivityItem[]>([]);
  const [isLoading, setIsLoading] = useState(true);
  const [isLoadingMore, setIsLoadingMore] = useState(false);
  const [total, setTotal] = useState(0);
  const [page, setPage] = useState(1);

  const loadActivity = useCallback(
    async (pageNum: number, append = false) => {
      if (pageNum === 1) {
        setIsLoading(true);
      } else {
        setIsLoadingMore(true);
      }

      try {
        const data = await tauriService.listResourceActivity(
          resourceId,
          pageNum,
          PAGE_SIZE
        );
        if (append) {
          setItems((prev) => [...prev, ...data.items]);
        } else {
          setItems(data.items);
        }
        setTotal(data.total);
      } catch (err) {
        console.error('Failed to load resource activity:', err);
      } finally {
        setIsLoading(false);
        setIsLoadingMore(false);
      }
    },
    [resourceId]
  );

  useEffect(() => {
    if (open) {
      setPage(1);
      setItems([]);
      loadActivity(1);
    }
  }, [open, loadActivity]);

  const handleLoadMore = () => {
    const nextPage = page + 1;
    setPage(nextPage);
    loadActivity(nextPage, true);
  };

  const hasMore = items.length < total;

  // Group items by date
  const groupedItems: Record<string, ActivityItem[]> = {};
  for (const item of items) {
    const group = getDateGroup(item.created_at);
    if (!groupedItems[group]) {
      groupedItems[group] = [];
    }
    groupedItems[group].push(item);
  }

  const groupOrder = ['Today', 'Yesterday', 'Earlier'];

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent className="sm:max-w-[500px] max-h-[80vh]">
        <DialogHeader>
          <DialogTitle className="flex items-center gap-2 pr-8">
            <Activity className="h-5 w-5" />
            <span className="truncate">Activity - {resourceName}</span>
          </DialogTitle>
        </DialogHeader>

        <div className="mt-2 overflow-y-auto max-h-[60vh]">
          {isLoading ? (
            <div className="flex items-center justify-center h-48">
              <Loader2 className="h-8 w-8 animate-spin text-muted-foreground" />
            </div>
          ) : items.length === 0 ? (
            <div className="flex flex-col items-center justify-center h-48 text-muted-foreground">
              <Activity className="h-12 w-12 mb-3 opacity-50" />
              <p className="text-sm">No activity recorded</p>
            </div>
          ) : (
            <div className="space-y-6">
              {groupOrder
                .filter((group) => groupedItems[group]?.length > 0)
                .map((group) => (
                  <div key={group}>
                    <h3 className="text-xs font-semibold text-muted-foreground uppercase tracking-wider mb-3">
                      {group}
                    </h3>
                    <div className="space-y-3">
                      {groupedItems[group].map((item) => {
                        const Icon = getEventIcon(item.event_type);
                        const colorClass = getEventColor(item.event_type);
                        const description = getEventDescription(item);

                        return (
                          <div
                            key={item.id}
                            className="flex items-start gap-3"
                          >
                            <div
                              className={cn(
                                'h-8 w-8 rounded-full flex items-center justify-center flex-shrink-0 mt-0.5',
                                colorClass
                              )}
                            >
                              <Icon className="h-4 w-4" />
                            </div>
                            <div className="flex-1 min-w-0">
                              <p className="text-sm">{description}</p>
                              <p className="text-xs text-muted-foreground mt-0.5">
                                {formatDistanceToNow(item.created_at)}
                              </p>
                            </div>
                          </div>
                        );
                      })}
                    </div>
                  </div>
                ))}

              {hasMore && (
                <div className="flex justify-center pt-2">
                  <Button
                    variant="outline"
                    size="sm"
                    onClick={handleLoadMore}
                    disabled={isLoadingMore}
                  >
                    {isLoadingMore && (
                      <Loader2 className="h-4 w-4 mr-2 animate-spin" />
                    )}
                    Load more
                  </Button>
                </div>
              )}
            </div>
          )}
        </div>
      </DialogContent>
    </Dialog>
  );
}
