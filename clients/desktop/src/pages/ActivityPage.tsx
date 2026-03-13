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
  RefreshCw,
  ChevronLeft,
  ChevronRight,
} from 'lucide-react';
import { Button } from '@/components/ui/Button';
import { useToast } from '@/hooks/useToast';
import { cn, formatDistanceToNow } from '@/lib/utils';
import tauriService from '@/services/tauri';
import type { ActivityItem, ActivityResponse } from '@/services/tauri';

type FilterType =
  | 'all'
  | 'file.uploaded'
  | 'file.downloaded'
  | 'file.shared'
  | 'file.renamed'
  | 'file.deleted'
  | 'folder.created';

interface FilterChip {
  label: string;
  value: FilterType;
}

const filters: FilterChip[] = [
  { label: 'All Events', value: 'all' },
  { label: 'Uploads', value: 'file.uploaded' },
  { label: 'Downloads', value: 'file.downloaded' },
  { label: 'Shares', value: 'file.shared' },
  { label: 'Renames', value: 'file.renamed' },
  { label: 'Deletes', value: 'file.deleted' },
  { label: 'Folders', value: 'folder.created' },
];

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

function getEventLabel(eventType: string): string {
  switch (eventType) {
    case 'file.uploaded':
      return 'Uploaded';
    case 'file.downloaded':
      return 'Downloaded';
    case 'file.renamed':
      return 'Renamed';
    case 'file.moved':
      return 'Moved';
    case 'file.deleted':
      return 'Deleted';
    case 'file.previewed':
      return 'Previewed';
    case 'file.shared':
      return 'Shared';
    case 'share.revoked':
      return 'Share Revoked';
    case 'permission.changed':
      return 'Permission Changed';
    case 'folder.created':
      return 'Folder Created';
    default:
      return eventType;
  }
}

function getEventDetails(item: ActivityItem): string {
  if (item.details) {
    if (item.event_type === 'file.renamed' && item.details.old_name) {
      return `from "${item.details.old_name}"`;
    }
    if (item.event_type === 'file.moved' && item.details.destination) {
      return `to "${item.details.destination}"`;
    }
    if (item.event_type === 'file.shared' && item.details.shared_with) {
      return `with ${item.details.shared_with}`;
    }
    if (item.event_type === 'permission.changed' && item.details.new_permission) {
      return `to ${item.details.new_permission}`;
    }
  }
  return item.actor_name ? `by ${item.actor_name}` : '';
}

const PAGE_SIZE = 20;

export function ActivityPage() {
  const { error: showError } = useToast();
  const [response, setResponse] = useState<ActivityResponse | null>(null);
  const [isLoading, setIsLoading] = useState(true);
  const [isRefreshing, setIsRefreshing] = useState(false);
  const [activeFilter, setActiveFilter] = useState<FilterType>('all');
  const [page, setPage] = useState(1);

  const loadActivity = useCallback(
    async (showRefreshSpinner = false) => {
      if (showRefreshSpinner) {
        setIsRefreshing(true);
      } else {
        setIsLoading(true);
      }

      try {
        const data = await tauriService.listActivity({
          page,
          pageSize: PAGE_SIZE,
          eventType: activeFilter === 'all' ? undefined : activeFilter,
        });
        setResponse(data);
      } catch (err) {
        console.error('Failed to load activity:', err);
        showError({
          title: 'Failed to load activity',
          description: String(err),
        });
      } finally {
        setIsLoading(false);
        setIsRefreshing(false);
      }
    },
    [page, activeFilter, showError]
  );

  useEffect(() => {
    loadActivity();
  }, [loadActivity]);

  const handleFilterChange = (filter: FilterType) => {
    setActiveFilter(filter);
    setPage(1);
  };

  const totalPages = response ? Math.ceil(response.total / PAGE_SIZE) : 0;

  return (
    <div className="space-y-6">
      {/* Header */}
      <div className="flex items-center justify-between">
        <div>
          <h1 className="text-2xl font-bold flex items-center gap-2">
            <Activity className="h-6 w-6 text-primary" />
            Activity
          </h1>
          <p className="text-muted-foreground mt-1">
            Recent activity across your files and folders
          </p>
        </div>
        <Button
          variant="outline"
          size="icon"
          onClick={() => loadActivity(true)}
          disabled={isRefreshing}
        >
          <RefreshCw
            className={cn('h-4 w-4', isRefreshing && 'animate-spin')}
          />
        </Button>
      </div>

      {/* Filter chips */}
      <div className="flex flex-wrap gap-2">
        {filters.map((filter) => (
          <button
            key={filter.value}
            onClick={() => handleFilterChange(filter.value)}
            className={cn(
              'px-3 py-1.5 text-sm font-medium rounded-full border transition-colors',
              activeFilter === filter.value
                ? 'bg-primary text-primary-foreground border-primary'
                : 'bg-background text-muted-foreground border-border hover:bg-accent hover:text-accent-foreground'
            )}
          >
            {filter.label}
          </button>
        ))}
      </div>

      {/* Content */}
      {isLoading ? (
        <div className="flex items-center justify-center h-64">
          <Loader2 className="h-8 w-8 animate-spin text-muted-foreground" />
        </div>
      ) : !response || response.items.length === 0 ? (
        <div className="flex flex-col items-center justify-center h-64 text-muted-foreground">
          <Activity className="h-16 w-16 mb-4 opacity-50" />
          <p className="text-lg">No activity yet</p>
          <p className="text-sm">
            Activity will appear here as you use your drive
          </p>
        </div>
      ) : (
        <>
          <div className="border rounded-lg overflow-hidden">
            <table className="w-full">
              <thead className="bg-muted/50">
                <tr className="text-left text-sm">
                  <th className="px-4 py-3 font-medium">Event</th>
                  <th className="px-4 py-3 font-medium">File / Folder</th>
                  <th className="px-4 py-3 font-medium">Details</th>
                  <th className="px-4 py-3 font-medium text-right">When</th>
                </tr>
              </thead>
              <tbody className="divide-y">
                {response.items.map((item) => {
                  const Icon = getEventIcon(item.event_type);
                  const colorClass = getEventColor(item.event_type);
                  const label = getEventLabel(item.event_type);
                  const details = getEventDetails(item);

                  return (
                    <tr key={item.id} className="hover:bg-muted/50">
                      <td className="px-4 py-3">
                        <div className="flex items-center gap-3">
                          <div
                            className={cn(
                              'h-8 w-8 rounded-full flex items-center justify-center',
                              colorClass
                            )}
                          >
                            <Icon className="h-4 w-4" />
                          </div>
                          <span className="text-sm font-medium">{label}</span>
                        </div>
                      </td>
                      <td className="px-4 py-3">
                        <span className="text-sm font-medium truncate max-w-[200px] block">
                          {item.resource_name}
                        </span>
                      </td>
                      <td className="px-4 py-3">
                        <span className="text-sm text-muted-foreground">
                          {details}
                        </span>
                      </td>
                      <td className="px-4 py-3 text-right">
                        <span className="text-sm text-muted-foreground whitespace-nowrap">
                          {formatDistanceToNow(item.created_at)}
                        </span>
                      </td>
                    </tr>
                  );
                })}
              </tbody>
            </table>
          </div>

          {/* Pagination */}
          {totalPages > 1 && (
            <div className="flex items-center justify-between">
              <p className="text-sm text-muted-foreground">
                Page {page} of {totalPages} ({response.total} events)
              </p>
              <div className="flex items-center gap-2">
                <Button
                  variant="outline"
                  size="sm"
                  onClick={() => setPage((p) => Math.max(1, p - 1))}
                  disabled={page <= 1}
                >
                  <ChevronLeft className="h-4 w-4 mr-1" />
                  Previous
                </Button>
                <Button
                  variant="outline"
                  size="sm"
                  onClick={() => setPage((p) => Math.min(totalPages, p + 1))}
                  disabled={page >= totalPages}
                >
                  Next
                  <ChevronRight className="h-4 w-4 ml-1" />
                </Button>
              </div>
            </div>
          )}
        </>
      )}
    </div>
  );
}
