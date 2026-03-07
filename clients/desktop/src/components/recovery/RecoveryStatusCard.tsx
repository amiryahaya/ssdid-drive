import { useEffect, useState } from 'react';
import {
  Key,
  Shield,
  ShieldCheck,
  ShieldX,
  User,
  Clock,
  Check,
  X,
  Settings,
  Trash2,
  Loader2,
} from 'lucide-react';
import { useRecoveryStore, TrusteeStatus } from '@/stores/recoveryStore';
import { Button } from '@/components/ui/Button';
import { ConfirmDialog } from '@/components/ui/ConfirmDialog';
import { RecoverySetupDialog } from './RecoverySetupDialog';

function getTrusteeStatusIcon(status: TrusteeStatus) {
  switch (status) {
    case 'accepted':
      return <Check className="h-4 w-4 text-green-500" />;
    case 'declined':
      return <X className="h-4 w-4 text-red-500" />;
    case 'pending':
    default:
      return <Clock className="h-4 w-4 text-amber-500" />;
  }
}

function getTrusteeStatusLabel(status: TrusteeStatus) {
  switch (status) {
    case 'accepted':
      return 'Accepted';
    case 'declined':
      return 'Declined';
    case 'pending':
    default:
      return 'Pending';
  }
}

export function RecoveryStatusCard() {
  const { setup, isLoading, loadRecoveryStatus, removeRecovery } =
    useRecoveryStore();
  const [setupDialogOpen, setSetupDialogOpen] = useState(false);
  const [removeDialogOpen, setRemoveDialogOpen] = useState(false);
  const [isRemoving, setIsRemoving] = useState(false);

  useEffect(() => {
    loadRecoveryStatus();
  }, [loadRecoveryStatus]);

  const handleRemove = async () => {
    setIsRemoving(true);
    try {
      await removeRecovery();
    } finally {
      setIsRemoving(false);
      setRemoveDialogOpen(false);
    }
  };

  const acceptedCount = setup?.trustees.filter((t) => t.status === 'accepted').length ?? 0;
  const isFullyConfigured = setup && acceptedCount >= setup.threshold;

  return (
    <div className="rounded-lg border bg-card p-6">
      <div className="flex items-start justify-between">
        <div className="flex items-center gap-3">
          <div
            className={`p-2 rounded-lg ${
              isFullyConfigured
                ? 'bg-green-500/10 text-green-500'
                : setup
                ? 'bg-amber-500/10 text-amber-500'
                : 'bg-muted text-muted-foreground'
            }`}
          >
            {isFullyConfigured ? (
              <ShieldCheck className="h-6 w-6" />
            ) : setup ? (
              <Shield className="h-6 w-6" />
            ) : (
              <ShieldX className="h-6 w-6" />
            )}
          </div>
          <div>
            <h3 className="font-semibold">Account Recovery</h3>
            <p className="text-sm text-muted-foreground">
              {isFullyConfigured
                ? 'Your account is protected'
                : setup
                ? 'Setup in progress'
                : 'Not configured'}
            </p>
          </div>
        </div>

        <div className="flex items-center gap-2">
          {setup && (
            <Button
              variant="ghost"
              size="icon"
              onClick={() => setRemoveDialogOpen(true)}
              disabled={isRemoving}
            >
              {isRemoving ? (
                <Loader2 className="h-4 w-4 animate-spin" />
              ) : (
                <Trash2 className="h-4 w-4 text-destructive" />
              )}
            </Button>
          )}
          <Button
            variant={setup ? 'outline' : 'default'}
            onClick={() => setSetupDialogOpen(true)}
          >
            {setup ? (
              <>
                <Settings className="h-4 w-4 mr-2" />
                Configure
              </>
            ) : (
              <>
                <Key className="h-4 w-4 mr-2" />
                Set Up Recovery
              </>
            )}
          </Button>
        </div>
      </div>

      {isLoading ? (
        <div className="flex justify-center py-8">
          <Loader2 className="h-6 w-6 animate-spin text-muted-foreground" />
        </div>
      ) : setup ? (
        <div className="mt-6 space-y-4">
          <div className="flex items-center gap-4 text-sm">
            <div className="flex items-center gap-2">
              <Key className="h-4 w-4 text-muted-foreground" />
              <span>
                Recovery threshold:{' '}
                <strong>
                  {setup.threshold} of {setup.total_trustees}
                </strong>{' '}
                trustees
              </span>
            </div>
          </div>

          <div className="border-t pt-4">
            <h4 className="text-sm font-medium mb-3">Trusted Contacts</h4>
            <div className="space-y-2">
              {setup.trustees.map((trustee) => (
                <div
                  key={trustee.id}
                  className="flex items-center justify-between py-2 px-3 rounded-lg bg-muted/50"
                >
                  <div className="flex items-center gap-3">
                    <div className="w-8 h-8 rounded-full bg-primary/10 flex items-center justify-center">
                      <User className="h-4 w-4 text-primary" />
                    </div>
                    <div>
                      <p className="text-sm font-medium">
                        {trustee.name || trustee.email}
                      </p>
                      {trustee.name && (
                        <p className="text-xs text-muted-foreground">
                          {trustee.email}
                        </p>
                      )}
                    </div>
                  </div>
                  <div className="flex items-center gap-2 text-sm">
                    {getTrusteeStatusIcon(trustee.status)}
                    <span className="text-muted-foreground">
                      {getTrusteeStatusLabel(trustee.status)}
                    </span>
                  </div>
                </div>
              ))}
            </div>
          </div>

          {!isFullyConfigured && (
            <div className="flex items-start gap-2 p-3 rounded-lg bg-amber-500/10 text-amber-700 dark:text-amber-400 text-sm">
              <Clock className="h-4 w-4 mt-0.5" />
              <div>
                <p className="font-medium">Waiting for acceptances</p>
                <p className="text-xs opacity-80">
                  {acceptedCount} of {setup.threshold} required trustees have
                  accepted
                </p>
              </div>
            </div>
          )}
        </div>
      ) : (
        <div className="mt-6 p-4 rounded-lg bg-muted/50 text-center">
          <p className="text-sm text-muted-foreground">
            Set up account recovery to protect your data. If you ever lose access to
            your device, trusted contacts can help you regain access to your
            encrypted files.
          </p>
        </div>
      )}

      <RecoverySetupDialog
        open={setupDialogOpen}
        onOpenChange={setSetupDialogOpen}
        existingSetup={setup}
      />

      <ConfirmDialog
        open={removeDialogOpen}
        onOpenChange={setRemoveDialogOpen}
        title="Remove Recovery Protection"
        description="Are you sure you want to remove recovery protection? You will need to set it up again if you want to recover your account."
        confirmLabel="Remove"
        variant="destructive"
        isLoading={isRemoving}
        onConfirm={handleRemove}
      />
    </div>
  );
}
