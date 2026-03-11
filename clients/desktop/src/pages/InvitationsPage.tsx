import { useEffect, useState } from 'react';
import {
  Mail,
  Send,
  Loader2,
  AlertCircle,
  Check,
  X,
  Copy,
  Plus,
  ChevronLeft,
  ChevronRight,
  Clock,
  UserPlus,
} from 'lucide-react';
import { Button } from '@/components/ui/Button';
import { ConfirmDialog } from '@/components/ui/ConfirmDialog';
import { CreateInvitationDialog } from '@/components/tenant/CreateInvitationDialog';
import { useTenantStore } from '@/stores/tenantStore';
import {
  useInvitationStore,
  type ReceivedInvitation,
  type SentInvitation,
  type InvitationStatus,
} from '@/stores/invitationStore';
import { useToast } from '@/hooks/useToast';
import { cn, formatDate } from '@/lib/utils';
import type { TenantRole } from '@/stores/tenantStore';

type Tab = 'received' | 'sent';

function getRoleLabel(role: TenantRole): string {
  switch (role) {
    case 'owner':
      return 'Owner';
    case 'admin':
      return 'Admin';
    case 'member':
      return 'Member';
    default:
      return role;
  }
}

function InvitationStatusBadge({ status }: { status: InvitationStatus }) {
  const styles: Record<InvitationStatus, string> = {
    pending:
      'bg-yellow-100 text-yellow-800 dark:bg-yellow-900/30 dark:text-yellow-400',
    accepted:
      'bg-green-100 text-green-800 dark:bg-green-900/30 dark:text-green-400',
    declined:
      'bg-red-100 text-red-800 dark:bg-red-900/30 dark:text-red-400',
    revoked:
      'bg-gray-100 text-gray-800 dark:bg-gray-900/30 dark:text-gray-400',
    expired:
      'bg-gray-100 text-gray-600 dark:bg-gray-900/30 dark:text-gray-500',
  };

  const labels: Record<InvitationStatus, string> = {
    pending: 'Pending',
    accepted: 'Accepted',
    declined: 'Declined',
    revoked: 'Revoked',
    expired: 'Expired',
  };

  return (
    <span
      className={cn(
        'inline-flex items-center rounded-full px-2 py-0.5 text-xs font-medium',
        styles[status]
      )}
    >
      {labels[status]}
    </span>
  );
}

function RoleBadge({ role }: { role: TenantRole }) {
  const styles: Record<TenantRole, string> = {
    owner:
      'bg-amber-100 text-amber-800 dark:bg-amber-900/30 dark:text-amber-400',
    admin:
      'bg-blue-100 text-blue-800 dark:bg-blue-900/30 dark:text-blue-400',
    member:
      'bg-gray-100 text-gray-800 dark:bg-gray-900/30 dark:text-gray-400',
  };

  return (
    <span
      className={cn(
        'inline-flex items-center rounded-full px-2 py-0.5 text-xs font-medium',
        styles[role]
      )}
    >
      {getRoleLabel(role)}
    </span>
  );
}

interface ReceivedItemProps {
  invitation: ReceivedInvitation;
  onAccept: (id: string) => void;
  onDecline: (id: string) => void;
  isActioning: boolean;
}

function ReceivedItem({
  invitation,
  onAccept,
  onDecline,
  isActioning,
}: ReceivedItemProps) {
  return (
    <div className="flex items-center gap-4 rounded-lg border p-4 hover:bg-accent/50 transition-colors">
      <div className="flex h-10 w-10 items-center justify-center rounded-lg bg-primary/10">
        <Mail className="h-5 w-5 text-primary" />
      </div>

      <div className="flex-1 min-w-0">
        <div className="flex items-center gap-2">
          <span className="font-medium">{invitation.tenant_name}</span>
          <RoleBadge role={invitation.role} />
          <InvitationStatusBadge status={invitation.status} />
        </div>
        <div className="flex items-center gap-2 text-sm text-muted-foreground mt-0.5">
          <span>
            From {invitation.invited_by_name ?? invitation.invited_by}
          </span>
          <span>&middot;</span>
          <span>{formatDate(invitation.created_at)}</span>
        </div>
        {invitation.message && (
          <p className="text-sm text-muted-foreground mt-1 italic">
            &ldquo;{invitation.message}&rdquo;
          </p>
        )}
        {invitation.expires_at && (
          <p className="text-xs text-muted-foreground mt-1 flex items-center gap-1">
            <Clock className="h-3 w-3" />
            Expires {formatDate(invitation.expires_at)}
          </p>
        )}
      </div>

      {invitation.status === 'pending' && (
        <div className="flex items-center gap-2">
          <Button
            size="sm"
            onClick={() => onAccept(invitation.id)}
            disabled={isActioning}
          >
            <Check className="h-4 w-4 mr-1" />
            Accept
          </Button>
          <Button
            size="sm"
            variant="outline"
            onClick={() => onDecline(invitation.id)}
            disabled={isActioning}
          >
            <X className="h-4 w-4 mr-1" />
            Decline
          </Button>
        </div>
      )}
    </div>
  );
}

interface SentItemProps {
  invitation: SentInvitation;
  onRevoke: (invitation: SentInvitation) => void;
}

function SentItem({ invitation, onRevoke }: SentItemProps) {
  const [copied, setCopied] = useState(false);

  const handleCopyCode = async () => {
    try {
      await navigator.clipboard.writeText(invitation.short_code);
      setCopied(true);
      setTimeout(() => setCopied(false), 2000);
    } catch {
      // Ignore clipboard errors
    }
  };

  return (
    <div className="flex items-center gap-4 rounded-lg border p-4 hover:bg-accent/50 transition-colors">
      <div className="flex h-10 w-10 items-center justify-center rounded-lg bg-muted">
        <Send className="h-5 w-5 text-muted-foreground" />
      </div>

      <div className="flex-1 min-w-0">
        <div className="flex items-center gap-2">
          <span className="font-medium">
            {invitation.email ?? 'Open invite'}
          </span>
          <RoleBadge role={invitation.role} />
          <InvitationStatusBadge status={invitation.status} />
        </div>
        <div className="flex items-center gap-2 text-sm text-muted-foreground mt-0.5">
          <span className="font-mono text-xs">{invitation.short_code}</span>
          <button
            onClick={handleCopyCode}
            className="text-muted-foreground hover:text-foreground transition-colors"
            aria-label="Copy invite code"
          >
            {copied ? (
              <Check className="h-3.5 w-3.5 text-green-500" />
            ) : (
              <Copy className="h-3.5 w-3.5" />
            )}
          </button>
          <span>&middot;</span>
          <span>{formatDate(invitation.created_at)}</span>
        </div>
        {invitation.expires_at && (
          <p className="text-xs text-muted-foreground mt-1 flex items-center gap-1">
            <Clock className="h-3 w-3" />
            Expires {formatDate(invitation.expires_at)}
          </p>
        )}
      </div>

      {invitation.status === 'pending' && (
        <Button
          size="sm"
          variant="outline"
          className="text-destructive hover:text-destructive"
          onClick={() => onRevoke(invitation)}
        >
          Revoke
        </Button>
      )}
    </div>
  );
}

interface PaginationProps {
  page: number;
  totalPages: number;
  onPageChange: (page: number) => void;
}

function Pagination({ page, totalPages, onPageChange }: PaginationProps) {
  if (totalPages <= 1) return null;

  return (
    <div className="flex items-center justify-center gap-2 pt-4">
      <Button
        variant="outline"
        size="sm"
        disabled={page <= 1}
        onClick={() => onPageChange(page - 1)}
      >
        <ChevronLeft className="h-4 w-4" />
      </Button>
      <span className="text-sm text-muted-foreground">
        Page {page} of {totalPages}
      </span>
      <Button
        variant="outline"
        size="sm"
        disabled={page >= totalPages}
        onClick={() => onPageChange(page + 1)}
      >
        <ChevronRight className="h-4 w-4" />
      </Button>
    </div>
  );
}

export function InvitationsPage() {
  const { canManageMembers } = useTenantStore();
  const {
    receivedInvitations,
    sentInvitations,
    receivedPage,
    sentPage,
    receivedTotalPages,
    sentTotalPages,
    isLoadingReceived,
    isLoadingSent,
    error,
    loadReceivedInvitations,
    loadSentInvitations,
    acceptInvitation,
    declineInvitation,
    revokeInvitation,
    clearError,
  } = useInvitationStore();

  const { success, error: showError } = useToast();
  const [activeTab, setActiveTab] = useState<Tab>('received');
  const [isActioning, setIsActioning] = useState(false);
  const [invitationToRevoke, setInvitationToRevoke] =
    useState<SentInvitation | null>(null);
  const [isRevoking, setIsRevoking] = useState(false);
  const [showCreateDialog, setShowCreateDialog] = useState(false);

  useEffect(() => {
    loadReceivedInvitations();
    loadSentInvitations();
  }, [loadReceivedInvitations, loadSentInvitations]);

  const handleAccept = async (id: string) => {
    setIsActioning(true);
    try {
      await acceptInvitation(id);
      success({
        title: 'Invitation accepted',
        description: 'You have joined the organization',
      });
    } catch (err) {
      showError({
        title: 'Failed to accept invitation',
        description: err instanceof Error ? err.message : String(err),
      });
    } finally {
      setIsActioning(false);
    }
  };

  const handleDecline = async (id: string) => {
    setIsActioning(true);
    try {
      await declineInvitation(id);
      success({
        title: 'Invitation declined',
      });
    } catch (err) {
      showError({
        title: 'Failed to decline invitation',
        description: err instanceof Error ? err.message : String(err),
      });
    } finally {
      setIsActioning(false);
    }
  };

  const handleRevoke = async () => {
    if (!invitationToRevoke) return;
    setIsRevoking(true);
    try {
      await revokeInvitation(invitationToRevoke.id);
      success({
        title: 'Invitation revoked',
        description: `Invitation for ${invitationToRevoke.email ?? invitationToRevoke.short_code} has been revoked`,
      });
      setInvitationToRevoke(null);
    } catch (err) {
      showError({
        title: 'Failed to revoke invitation',
        description: err instanceof Error ? err.message : String(err),
      });
    } finally {
      setIsRevoking(false);
    }
  };

  const isLoading = activeTab === 'received' ? isLoadingReceived : isLoadingSent;

  return (
    <div className="space-y-6">
      {/* Header */}
      <div className="flex items-center justify-between">
        <div>
          <h1 className="text-2xl font-bold">Invitations</h1>
          <p className="text-muted-foreground mt-1">
            Manage your organization invitations
          </p>
        </div>
        {canManageMembers && (
          <Button onClick={() => setShowCreateDialog(true)}>
            <Plus className="h-4 w-4 mr-2" />
            Create Invitation
          </Button>
        )}
      </div>

      {/* Error banner */}
      {error && (
        <div className="flex items-center gap-2 rounded-lg border border-red-200 bg-red-50 p-4 text-red-800 dark:border-red-900 dark:bg-red-900/20 dark:text-red-400">
          <AlertCircle className="h-5 w-5" />
          <span>{error}</span>
          <Button size="sm" variant="ghost" onClick={clearError}>
            Dismiss
          </Button>
        </div>
      )}

      {/* Tabs */}
      <div className="border-b">
        <div className="flex gap-4" role="tablist" aria-label="Invitation tabs">
          <button
            role="tab"
            aria-selected={activeTab === 'received'}
            aria-controls="tab-panel-received"
            onClick={() => setActiveTab('received')}
            className={cn(
              'pb-3 text-sm font-medium border-b-2 transition-colors',
              activeTab === 'received'
                ? 'border-primary text-foreground'
                : 'border-transparent text-muted-foreground hover:text-foreground'
            )}
          >
            Received
          </button>
          <button
            role="tab"
            aria-selected={activeTab === 'sent'}
            aria-controls="tab-panel-sent"
            onClick={() => setActiveTab('sent')}
            className={cn(
              'pb-3 text-sm font-medium border-b-2 transition-colors',
              activeTab === 'sent'
                ? 'border-primary text-foreground'
                : 'border-transparent text-muted-foreground hover:text-foreground'
            )}
          >
            Sent
          </button>
        </div>
      </div>

      {/* Content */}
      {isLoading ? (
        <div className="flex items-center justify-center h-64" role="status" aria-label="Loading invitations">
          <Loader2 className="h-8 w-8 animate-spin text-muted-foreground" />
        </div>
      ) : activeTab === 'received' ? (
        receivedInvitations.length === 0 ? (
          <div className="flex flex-col items-center justify-center h-64 text-muted-foreground">
            <UserPlus className="h-16 w-16 mb-4 opacity-50" />
            <p className="text-lg">No invitations received</p>
            <p className="text-sm">
              Invitations to join organizations will appear here
            </p>
          </div>
        ) : (
          <>
            <div className="space-y-3">
              {receivedInvitations.map((inv) => (
                <ReceivedItem
                  key={inv.id}
                  invitation={inv}
                  onAccept={handleAccept}
                  onDecline={handleDecline}
                  isActioning={isActioning}
                />
              ))}
            </div>
            <Pagination
              page={receivedPage}
              totalPages={receivedTotalPages}
              onPageChange={(p) => loadReceivedInvitations(p)}
            />
          </>
        )
      ) : sentInvitations.length === 0 ? (
        <div className="flex flex-col items-center justify-center h-64 text-muted-foreground">
          <Send className="h-16 w-16 mb-4 opacity-50" />
          <p className="text-lg">No invitations sent</p>
          <p className="text-sm">
            {canManageMembers
              ? 'Create an invitation to get started'
              : 'Only admins and owners can send invitations'}
          </p>
        </div>
      ) : (
        <>
          <div className="space-y-3">
            {sentInvitations.map((inv) => (
              <SentItem
                key={inv.id}
                invitation={inv}
                onRevoke={setInvitationToRevoke}
              />
            ))}
          </div>
          <Pagination
            page={sentPage}
            totalPages={sentTotalPages}
            onPageChange={(p) => loadSentInvitations(p)}
          />
        </>
      )}

      {/* Revoke confirmation dialog */}
      <ConfirmDialog
        open={!!invitationToRevoke}
        onOpenChange={() => setInvitationToRevoke(null)}
        title="Revoke Invitation"
        description={`Are you sure you want to revoke this invitation${
          invitationToRevoke?.email
            ? ` for ${invitationToRevoke.email}`
            : ` (${invitationToRevoke?.short_code})`
        }? The invite code will no longer be valid.`}
        confirmLabel="Revoke"
        variant="destructive"
        isLoading={isRevoking}
        onConfirm={handleRevoke}
      />

      {/* Create invitation dialog */}
      <CreateInvitationDialog
        open={showCreateDialog}
        onOpenChange={setShowCreateDialog}
      />
    </div>
  );
}
