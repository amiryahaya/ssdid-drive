import { useEffect, useState } from 'react';
import {
  Share2,
  File,
  Folder,
  Loader2,
  Trash2,
  AlertCircle,
  MoreHorizontal,
} from 'lucide-react';
import { useShareStore } from '../stores/shareStore';
import { useToast } from '../hooks/useToast';
import { Button } from '../components/ui/Button';
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuTrigger,
} from '../components/ui/DropdownMenu';
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from '../components/ui/dialog';
import { StatusBadge } from '../components/common/StatusBadge';
import { formatDate, getPermissionLabel } from '../lib/utils';
import type { Share } from '../types';

interface ShareItemProps {
  share: Share;
  onRevoke: (share: Share) => void;
}

function ShareItem({ share, onRevoke }: ShareItemProps) {
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
          <span>Shared with {share.recipient_name || share.recipient_email}</span>
          <span>·</span>
          <span>{getPermissionLabel(share.permission)}</span>
          <span>·</span>
          <span>{formatDate(share.created_at)}</span>
        </div>
        {share.expires_at && (
          <p className="mt-1 text-xs text-muted-foreground">
            Expires: {formatDate(share.expires_at)}
          </p>
        )}
      </div>

      <DropdownMenu>
        <DropdownMenuTrigger asChild>
          <Button variant="ghost" size="icon">
            <MoreHorizontal className="h-4 w-4" />
          </Button>
        </DropdownMenuTrigger>
        <DropdownMenuContent align="end">
          <DropdownMenuItem
            className="text-red-600 focus:text-red-600"
            onClick={() => onRevoke(share)}
          >
            <Trash2 className="h-4 w-4 mr-2" />
            Revoke Share
          </DropdownMenuItem>
        </DropdownMenuContent>
      </DropdownMenu>
    </div>
  );
}

export function MySharesPage() {
  const {
    myShares,
    isLoading,
    error,
    loadMyShares,
    revokeShare,
    clearError,
  } = useShareStore();

  const { success, error: showError } = useToast();
  const [shareToRevoke, setShareToRevoke] = useState<Share | null>(null);
  const [isRevoking, setIsRevoking] = useState(false);

  useEffect(() => {
    loadMyShares();
  }, [loadMyShares]);

  const handleRevoke = async () => {
    if (!shareToRevoke) return;

    setIsRevoking(true);
    try {
      await revokeShare(shareToRevoke.id);
      success({
        title: 'Share revoked',
        description: `${shareToRevoke.recipient_name || shareToRevoke.recipient_email} no longer has access`,
      });
      setShareToRevoke(null);
    } catch (err) {
      showError({ title: 'Failed to revoke share', description: String(err) });
    } finally {
      setIsRevoking(false);
    }
  };

  return (
    <div className="space-y-6">
      <div>
        <h1 className="text-2xl font-bold">My Shares</h1>
        <p className="text-muted-foreground mt-1">
          Files and folders you have shared with others
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
      ) : myShares.length === 0 ? (
        <div className="flex flex-col items-center justify-center h-64 text-muted-foreground">
          <Share2 className="h-16 w-16 mb-4 opacity-50" />
          <p className="text-lg">No shares yet</p>
          <p className="text-sm">
            Share files with others using the share button
          </p>
        </div>
      ) : (
        <div className="space-y-3">
          {myShares.map((share) => (
            <ShareItem
              key={share.id}
              share={share}
              onRevoke={setShareToRevoke}
            />
          ))}
        </div>
      )}

      {/* Revoke Confirmation Dialog */}
      <Dialog open={!!shareToRevoke} onOpenChange={() => setShareToRevoke(null)}>
        <DialogContent>
          <DialogHeader>
            <DialogTitle>Revoke Share</DialogTitle>
            <DialogDescription>
              Are you sure you want to revoke this share? {shareToRevoke?.recipient_name || shareToRevoke?.recipient_email} will
              no longer be able to access "{shareToRevoke?.item_name}".
            </DialogDescription>
          </DialogHeader>
          <DialogFooter>
            <Button variant="outline" onClick={() => setShareToRevoke(null)}>
              Cancel
            </Button>
            <Button variant="destructive" onClick={handleRevoke} disabled={isRevoking}>
              {isRevoking && <Loader2 className="h-4 w-4 mr-2 animate-spin" />}
              Revoke
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>
    </div>
  );
}
