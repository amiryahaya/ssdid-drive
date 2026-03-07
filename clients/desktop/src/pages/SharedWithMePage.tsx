import { useEffect } from 'react';
import { FolderInput, File, Folder, Loader2, Check, X, AlertCircle } from 'lucide-react';
import { useShareStore } from '../stores/shareStore';
import { useToast } from '../hooks/useToast';
import { Button } from '../components/ui/Button';
import { StatusBadge } from '../components/common/StatusBadge';
import { formatDate, getPermissionLabel } from '../lib/utils';
import type { Share } from '../types';

interface ShareItemProps {
  share: Share;
  onAccept: (id: string) => void;
  onDecline: (id: string) => void;
}

function ShareItem({ share, onAccept, onDecline }: ShareItemProps) {
  const ItemIcon = share.item_type === 'folder' ? Folder : File;

  return (
    <div className="flex items-center gap-4 rounded-lg border p-4 hover:bg-accent/50 transition-colors">
      <div className="flex h-10 w-10 items-center justify-center rounded-lg bg-muted">
        <ItemIcon className="h-5 w-5 text-muted-foreground" />
      </div>

      <div className="flex-1 min-w-0">
        <div className="flex items-center gap-2">
          <span className="font-medium truncate">{share.item_name}</span>
          <StatusBadge status={share.status} />
        </div>
        <div className="flex items-center gap-2 text-sm text-muted-foreground">
          <span>From {share.owner_name || share.owner_email}</span>
          <span>·</span>
          <span>{getPermissionLabel(share.permission)}</span>
          <span>·</span>
          <span>{formatDate(share.created_at)}</span>
        </div>
        {share.message && (
          <p className="mt-1 text-sm text-muted-foreground italic">"{share.message}"</p>
        )}
      </div>

      {share.status === 'pending' && (
        <div className="flex items-center gap-2">
          <Button size="sm" onClick={() => onAccept(share.id)}>
            <Check className="h-4 w-4 mr-1" />
            Accept
          </Button>
          <Button size="sm" variant="outline" onClick={() => onDecline(share.id)}>
            <X className="h-4 w-4 mr-1" />
            Decline
          </Button>
        </div>
      )}
    </div>
  );
}

export function SharedWithMePage() {
  const {
    sharedWithMe,
    isLoading,
    error,
    loadSharedWithMe,
    acceptShare,
    declineShare,
    clearError,
  } = useShareStore();

  const { success, error: showError } = useToast();

  useEffect(() => {
    loadSharedWithMe();
  }, [loadSharedWithMe]);

  const handleAccept = async (shareId: string) => {
    try {
      await acceptShare(shareId);
      success({ title: 'Share accepted', description: 'You can now access this item' });
    } catch (err) {
      showError({ title: 'Failed to accept share', description: String(err) });
    }
  };

  const handleDecline = async (shareId: string) => {
    try {
      await declineShare(shareId);
      success({ title: 'Share declined' });
    } catch (err) {
      showError({ title: 'Failed to decline share', description: String(err) });
    }
  };

  return (
    <div className="space-y-6">
      <div>
        <h1 className="text-2xl font-bold">Shared with Me</h1>
        <p className="text-muted-foreground mt-1">
          Files and folders others have shared with you
        </p>
      </div>

      {error && (
        <div className="flex items-center gap-2 rounded-lg border border-red-200 bg-red-50 p-4 text-red-800 dark:border-red-900 dark:bg-red-900/20 dark:text-red-400">
          <AlertCircle className="h-5 w-5" />
          <span>{error}</span>
          <Button size="sm" variant="ghost" onClick={clearError}>
            Dismiss
          </Button>
        </div>
      )}

      {isLoading ? (
        <div className="flex items-center justify-center h-64">
          <Loader2 className="h-8 w-8 animate-spin text-muted-foreground" />
        </div>
      ) : sharedWithMe.length === 0 ? (
        <div className="flex flex-col items-center justify-center h-64 text-muted-foreground">
          <FolderInput className="h-16 w-16 mb-4 opacity-50" />
          <p className="text-lg">No shared items</p>
          <p className="text-sm">
            When someone shares a file or folder with you, it will appear here
          </p>
        </div>
      ) : (
        <div className="space-y-3">
          {sharedWithMe.map((share) => (
            <ShareItem
              key={share.id}
              share={share}
              onAccept={handleAccept}
              onDecline={handleDecline}
            />
          ))}
        </div>
      )}
    </div>
  );
}
