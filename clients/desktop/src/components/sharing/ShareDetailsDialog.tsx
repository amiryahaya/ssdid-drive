import { useState, useEffect, useCallback } from 'react';
import { Loader2, User, X, Calendar, Shield } from 'lucide-react';
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogHeader,
  DialogTitle,
} from '../ui/dialog';
import { Button } from '../ui/Button';
import { Input } from '../ui/input';
import { Label } from '../ui/label';
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from '../ui/select';
import { ConfirmDialog } from '../ui/ConfirmDialog';
import { useShareStore } from '../../stores/shareStore';
import { useToast } from '../../hooks/useToast';
import { cn, formatDate, getPermissionLabel } from '../../lib/utils';
import type { FileItem, Share } from '../../types';

interface ShareDetailsDialogProps {
  open: boolean;
  onOpenChange: (open: boolean) => void;
  item: FileItem | null;
}

function ShareRow({
  share,
  onUpdatePermission,
  onSetExpiry,
  onRevoke,
  isUpdating,
}: {
  share: Share;
  onUpdatePermission: (shareId: string, permission: string) => void;
  onSetExpiry: (shareId: string, expiresAt: string | null) => void;
  onRevoke: (shareId: string) => void;
  isUpdating: boolean;
}) {
  const [showRevokeConfirm, setShowRevokeConfirm] = useState(false);

  const handleExpiryChange = useCallback(
    (e: React.ChangeEvent<HTMLInputElement>) => {
      const value = e.target.value;
      onSetExpiry(share.id, value ? new Date(value).toISOString() : null);
    },
    [share.id, onSetExpiry]
  );

  // Format expires_at to YYYY-MM-DD for the date input
  const expiryDateValue = share.expires_at
    ? new Date(share.expires_at).toISOString().split('T')[0]
    : '';

  return (
    <>
      <div className="flex items-start gap-3 rounded-lg border p-3">
        <div className="flex h-9 w-9 shrink-0 items-center justify-center rounded-full bg-muted">
          <User className="h-4 w-4 text-muted-foreground" />
        </div>

        <div className="flex-1 min-w-0 space-y-2">
          {/* Recipient info */}
          <div className="flex items-center justify-between gap-2">
            <div className="min-w-0">
              <p className="truncate text-sm font-medium">{share.recipient_name}</p>
              <p className="truncate text-xs text-muted-foreground">
                {share.recipient_email}
              </p>
            </div>
            <span
              className={cn(
                'shrink-0 rounded-full px-2 py-0.5 text-xs font-medium',
                share.status === 'accepted'
                  ? 'bg-green-100 text-green-700 dark:bg-green-900/30 dark:text-green-400'
                  : share.status === 'pending'
                    ? 'bg-yellow-100 text-yellow-700 dark:bg-yellow-900/30 dark:text-yellow-400'
                    : 'bg-red-100 text-red-700 dark:bg-red-900/30 dark:text-red-400'
              )}
            >
              {share.status}
            </span>
          </div>

          {/* Permission + Expiry controls */}
          <div className="flex flex-wrap items-end gap-2">
            {/* Permission select */}
            <div className="space-y-1">
              <Label className="text-xs text-muted-foreground">Permission</Label>
              <Select
                value={share.permission}
                onValueChange={(value) => onUpdatePermission(share.id, value)}
                disabled={isUpdating}
              >
                <SelectTrigger className="h-8 w-[130px] text-xs">
                  <SelectValue />
                </SelectTrigger>
                <SelectContent>
                  <SelectItem value="read">
                    <div className="flex items-center gap-1.5">
                      <Shield className="h-3 w-3" />
                      <span>Read</span>
                    </div>
                  </SelectItem>
                  <SelectItem value="write">
                    <div className="flex items-center gap-1.5">
                      <Shield className="h-3 w-3" />
                      <span>Write</span>
                    </div>
                  </SelectItem>
                  <SelectItem value="admin">
                    <div className="flex items-center gap-1.5">
                      <Shield className="h-3 w-3" />
                      <span>Admin</span>
                    </div>
                  </SelectItem>
                </SelectContent>
              </Select>
            </div>

            {/* Expiry date picker */}
            <div className="space-y-1">
              <Label className="text-xs text-muted-foreground">Expires</Label>
              <div className="relative">
                <Calendar className="absolute left-2 top-1/2 h-3 w-3 -translate-y-1/2 text-muted-foreground" />
                <Input
                  type="date"
                  value={expiryDateValue}
                  onChange={handleExpiryChange}
                  className="h-8 w-[150px] pl-7 text-xs"
                  min={new Date().toISOString().split('T')[0]}
                  disabled={isUpdating}
                />
              </div>
            </div>

            {/* Revoke button */}
            <Button
              variant="ghost"
              size="sm"
              className="h-8 px-2 text-destructive hover:bg-destructive/10 hover:text-destructive"
              onClick={() => setShowRevokeConfirm(true)}
              disabled={isUpdating}
              aria-label={`Revoke access for ${share.recipient_name}`}
            >
              <X className="h-3.5 w-3.5 mr-1" />
              <span className="text-xs">Revoke</span>
            </Button>
          </div>

          {/* Expiry info */}
          {share.expires_at && (
            <p className="text-xs text-muted-foreground">
              Expires {formatDate(share.expires_at)}
            </p>
          )}
        </div>
      </div>

      <ConfirmDialog
        open={showRevokeConfirm}
        onOpenChange={setShowRevokeConfirm}
        title="Revoke access"
        description={`Are you sure you want to revoke ${share.recipient_name}'s access? They will no longer be able to view or edit this item.`}
        confirmLabel="Revoke"
        variant="destructive"
        onConfirm={() => onRevoke(share.id)}
      />
    </>
  );
}

export function ShareDetailsDialog({
  open,
  onOpenChange,
  item,
}: ShareDetailsDialogProps) {
  const {
    itemShares,
    isLoading,
    isUpdating,
    loadSharesForItem,
    updatePermission,
    setExpiry,
    revokeShare,
  } = useShareStore();

  const { success, error: showError } = useToast();

  // Load shares when dialog opens
  useEffect(() => {
    if (open && item) {
      loadSharesForItem(item.id);
    }
  }, [open, item, loadSharesForItem]);

  const handleUpdatePermission = useCallback(
    async (shareId: string, permission: string) => {
      try {
        await updatePermission(shareId, permission);
        success({
          title: 'Permission updated',
          description: `Permission changed to ${getPermissionLabel(permission)}`,
        });
      } catch (err) {
        showError({
          title: 'Failed to update permission',
          description: String(err),
        });
      }
    },
    [updatePermission, success, showError]
  );

  const handleSetExpiry = useCallback(
    async (shareId: string, expiresAt: string | null) => {
      try {
        await setExpiry(shareId, expiresAt);
        success({
          title: expiresAt ? 'Expiry date set' : 'Expiry date removed',
        });
      } catch (err) {
        showError({
          title: 'Failed to update expiry',
          description: String(err),
        });
      }
    },
    [setExpiry, success, showError]
  );

  const handleRevoke = useCallback(
    async (shareId: string) => {
      try {
        await revokeShare(shareId);
        success({ title: 'Access revoked' });
      } catch (err) {
        showError({
          title: 'Failed to revoke access',
          description: String(err),
        });
      }
    },
    [revokeShare, success, showError]
  );

  if (!item) return null;

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent className="sm:max-w-[500px]">
        <DialogHeader>
          <DialogTitle>Manage sharing for "{item.name}"</DialogTitle>
          <DialogDescription>
            View and manage who has access to this {item.type}.
          </DialogDescription>
        </DialogHeader>

        <div className="py-4">
          {isLoading ? (
            <div className="flex items-center justify-center py-8">
              <Loader2 className="h-6 w-6 animate-spin text-muted-foreground" />
              <span className="ml-2 text-sm text-muted-foreground">
                Loading shares...
              </span>
            </div>
          ) : itemShares.length === 0 ? (
            <div className="flex flex-col items-center justify-center py-8 text-center">
              <User className="h-10 w-10 text-muted-foreground/50" />
              <p className="mt-2 text-sm font-medium text-muted-foreground">
                No active shares
              </p>
              <p className="mt-1 text-xs text-muted-foreground">
                This {item.type} has not been shared with anyone yet.
              </p>
            </div>
          ) : (
            <div className="space-y-3 max-h-[400px] overflow-y-auto pr-1">
              <p className="text-xs font-medium text-muted-foreground">
                {itemShares.length} {itemShares.length === 1 ? 'person has' : 'people have'} access
              </p>
              {itemShares.map((share) => (
                <ShareRow
                  key={share.id}
                  share={share}
                  onUpdatePermission={handleUpdatePermission}
                  onSetExpiry={handleSetExpiry}
                  onRevoke={handleRevoke}
                  isUpdating={isUpdating}
                />
              ))}
            </div>
          )}
        </div>
      </DialogContent>
    </Dialog>
  );
}
