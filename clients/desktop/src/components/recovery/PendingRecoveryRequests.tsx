import { useEffect, useState } from 'react';
import { Key, User, Check, X, Clock, Loader2 } from 'lucide-react';
import { useRecoveryStore } from '@/stores/recoveryStore';
import { Button } from '@/components/ui/Button';
import { ConfirmDialog } from '@/components/ui/ConfirmDialog';
import { useToast } from '@/hooks/useToast';
import { formatDistanceToNow } from '@/lib/utils';

export function PendingRecoveryRequests() {
  const {
    pendingRequests,
    loadPendingRequests,
    approveRequest,
    denyRequest,
    error,
  } = useRecoveryStore();
  const { success, error: showError } = useToast();
  const [processingId, setProcessingId] = useState<string | null>(null);
  const [denyDialogOpen, setDenyDialogOpen] = useState(false);
  const [requestToDeny, setRequestToDeny] = useState<string | null>(null);

  useEffect(() => {
    loadPendingRequests();
  }, [loadPendingRequests]);

  const handleApprove = async (requestId: string) => {
    setProcessingId(requestId);
    try {
      await approveRequest(requestId);
      success({
        title: 'Request approved',
        description: 'You have approved the recovery request',
      });
    } catch (err) {
      showError({
        title: 'Failed to approve',
        description: String(err),
      });
    } finally {
      setProcessingId(null);
    }
  };

  const openDenyDialog = (requestId: string) => {
    setRequestToDeny(requestId);
    setDenyDialogOpen(true);
  };

  const handleDeny = async () => {
    if (!requestToDeny) return;
    setProcessingId(requestToDeny);
    try {
      await denyRequest(requestToDeny);
      success({
        title: 'Request denied',
        description: 'You have denied the recovery request',
      });
    } catch (err) {
      showError({
        title: 'Failed to deny',
        description: String(err),
      });
    } finally {
      setProcessingId(null);
      setDenyDialogOpen(false);
      setRequestToDeny(null);
    }
  };

  if (pendingRequests.length === 0) {
    return null;
  }

  return (
    <div className="rounded-lg border bg-card p-6">
      <div className="flex items-center gap-3 mb-4">
        <div className="p-2 rounded-lg bg-amber-500/10 text-amber-500">
          <Key className="h-5 w-5" />
        </div>
        <div>
          <h3 className="font-semibold">Recovery Requests</h3>
          <p className="text-sm text-muted-foreground">
            Someone is requesting your help to recover their account
          </p>
        </div>
      </div>

      <div className="space-y-3">
        {pendingRequests.map((request) => (
          <div
            key={request.id}
            className="flex items-center justify-between p-4 rounded-lg bg-muted/50"
          >
            <div className="flex items-center gap-3">
              <div className="w-10 h-10 rounded-full bg-primary/10 flex items-center justify-center">
                <User className="h-5 w-5 text-primary" />
              </div>
              <div>
                <p className="font-medium">
                  {request.requester_name || request.requester_email}
                </p>
                {request.requester_name && (
                  <p className="text-sm text-muted-foreground">
                    {request.requester_email}
                  </p>
                )}
                <div className="flex items-center gap-2 mt-1 text-xs text-muted-foreground">
                  <Clock className="h-3 w-3" />
                  <span>{formatDistanceToNow(request.created_at)}</span>
                  <span className="mx-1">|</span>
                  <span>
                    {request.approvals_received} of {request.approvals_required}{' '}
                    approvals
                  </span>
                </div>
              </div>
            </div>

            <div className="flex items-center gap-2">
              <Button
                variant="outline"
                size="sm"
                onClick={() => openDenyDialog(request.id)}
                disabled={processingId === request.id}
              >
                {processingId === request.id ? (
                  <Loader2 className="h-4 w-4 animate-spin" />
                ) : (
                  <>
                    <X className="h-4 w-4 mr-1" />
                    Deny
                  </>
                )}
              </Button>
              <Button
                size="sm"
                onClick={() => handleApprove(request.id)}
                disabled={processingId === request.id}
              >
                {processingId === request.id ? (
                  <Loader2 className="h-4 w-4 animate-spin" />
                ) : (
                  <>
                    <Check className="h-4 w-4 mr-1" />
                    Approve
                  </>
                )}
              </Button>
            </div>
          </div>
        ))}
      </div>

      {error && (
        <div className="mt-4 p-3 rounded-lg bg-destructive/10 text-destructive text-sm">
          {error}
        </div>
      )}

      <ConfirmDialog
        open={denyDialogOpen}
        onOpenChange={setDenyDialogOpen}
        title="Deny Recovery Request"
        description="Are you sure you want to deny this recovery request? The requester will be notified."
        confirmLabel="Deny"
        variant="destructive"
        isLoading={processingId !== null}
        onConfirm={handleDeny}
      />
    </div>
  );
}
