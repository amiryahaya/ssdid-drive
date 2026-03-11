import { useEffect, useState } from 'react';
import {
  Users,
  Crown,
  Shield,
  User,
  Loader2,
  AlertCircle,
  Trash2,
} from 'lucide-react';
import { Button } from '@/components/ui/Button';
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from '@/components/ui/select';
import { ConfirmDialog } from '@/components/ui/ConfirmDialog';
import { useTenantStore, type TenantRole } from '@/stores/tenantStore';
import { useMemberStore, type TenantMember } from '@/stores/memberStore';
import { useAuthStore } from '@/stores/authStore';
import { useToast } from '@/hooks/useToast';
import { cn, formatDate } from '@/lib/utils';

function getRoleIcon(role: TenantRole) {
  switch (role) {
    case 'owner':
      return <Crown className="h-4 w-4 text-amber-500" />;
    case 'admin':
      return <Shield className="h-4 w-4 text-blue-500" />;
    default:
      return <User className="h-4 w-4 text-muted-foreground" />;
  }
}

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
        'inline-flex items-center gap-1 rounded-full px-2 py-0.5 text-xs font-medium',
        styles[role]
      )}
    >
      {getRoleIcon(role)}
      {getRoleLabel(role)}
    </span>
  );
}

interface MemberRowProps {
  member: TenantMember;
  isCurrentUser: boolean;
  currentUserRole: TenantRole | null;
  tenantId: string;
  onRoleChange: (userId: string, role: TenantRole) => void;
  onRemove: (member: TenantMember) => void;
  isUpdating: boolean;
}

function MemberRow({
  member,
  isCurrentUser,
  currentUserRole,
  tenantId: _tenantId,
  onRoleChange,
  onRemove,
  isUpdating,
}: MemberRowProps) {
  // Owner can manage admins and members; admin can manage members only
  const canEdit =
    !isCurrentUser &&
    member.role !== 'owner' &&
    (currentUserRole === 'owner' ||
      (currentUserRole === 'admin' && member.role === 'member'));

  return (
    <div
      className={cn(
        'flex items-center gap-4 rounded-lg border p-4 transition-colors',
        isCurrentUser
          ? 'bg-primary/5 border-primary/20'
          : 'hover:bg-accent/50'
      )}
    >
      {/* Avatar placeholder */}
      <div className="flex h-10 w-10 items-center justify-center rounded-full bg-muted">
        <User className="h-5 w-5 text-muted-foreground" />
      </div>

      {/* Member info */}
      <div className="flex-1 min-w-0">
        <div className="flex items-center gap-2">
          <span className="font-medium truncate">
            {member.name ?? member.did ?? member.user_id}
          </span>
          {isCurrentUser && (
            <span className="text-xs text-muted-foreground">(you)</span>
          )}
        </div>
        <div className="flex items-center gap-2 text-sm text-muted-foreground">
          {member.email && <span>{member.email}</span>}
          {member.email && <span>&middot;</span>}
          <span>Joined {formatDate(member.joined_at)}</span>
        </div>
      </div>

      {/* Role badge or dropdown */}
      <div className="flex items-center gap-2">
        {canEdit ? (
          <Select
            value={member.role}
            onValueChange={(value) =>
              onRoleChange(member.user_id, value as TenantRole)
            }
            disabled={isUpdating}
          >
            <SelectTrigger className="w-[120px]">
              <SelectValue />
            </SelectTrigger>
            <SelectContent>
              <SelectItem value="member">Member</SelectItem>
              {currentUserRole === 'owner' && (
                <SelectItem value="admin">Admin</SelectItem>
              )}
            </SelectContent>
          </Select>
        ) : (
          <RoleBadge role={member.role} />
        )}

        {/* Remove button — only owner can remove non-owner, non-self members */}
        {canEdit && (
          <Button
            variant="ghost"
            size="icon"
            className="text-destructive hover:text-destructive hover:bg-destructive/10"
            onClick={() => onRemove(member)}
            disabled={isUpdating}
            aria-label={`Remove ${member.name ?? member.user_id}`}
          >
            <Trash2 className="h-4 w-4" />
          </Button>
        )}
      </div>
    </div>
  );
}

export function MembersPage() {
  const currentUser = useAuthStore((state) => state.user);
  const { currentTenant, currentTenantId, currentRole } = useTenantStore();
  const {
    members,
    isLoading,
    isUpdating,
    error,
    loadMembers,
    updateMemberRole,
    removeMember,
    clearError,
  } = useMemberStore();

  const { success, error: showError } = useToast();
  const [memberToRemove, setMemberToRemove] = useState<TenantMember | null>(
    null
  );
  const [isRemoving, setIsRemoving] = useState(false);

  const tenantId = currentTenantId ?? currentTenant?.id;

  useEffect(() => {
    if (tenantId) {
      loadMembers(tenantId);
    }
  }, [tenantId, loadMembers]);

  const handleRoleChange = async (userId: string, role: TenantRole) => {
    if (!tenantId) return;
    try {
      await updateMemberRole(tenantId, userId, role);
      success({
        title: 'Role updated',
        description: `Member role changed to ${getRoleLabel(role)}`,
      });
    } catch (err) {
      showError({
        title: 'Failed to update role',
        description: err instanceof Error ? err.message : String(err),
      });
    }
  };

  const handleRemove = async () => {
    if (!memberToRemove || !tenantId) return;
    setIsRemoving(true);
    try {
      await removeMember(tenantId, memberToRemove.user_id);
      success({
        title: 'Member removed',
        description: `${memberToRemove.name ?? memberToRemove.user_id} has been removed from the organization`,
      });
      setMemberToRemove(null);
    } catch (err) {
      showError({
        title: 'Failed to remove member',
        description: err instanceof Error ? err.message : String(err),
      });
    } finally {
      setIsRemoving(false);
    }
  };

  // Sort members: owner first, then admins, then members
  const sortedMembers = [...members].sort((a, b) => {
    const order: Record<TenantRole, number> = { owner: 0, admin: 1, member: 2 };
    return (order[a.role] ?? 3) - (order[b.role] ?? 3);
  });

  return (
    <div className="space-y-6">
      {/* Header */}
      <div>
        <h1 className="text-2xl font-bold">Members</h1>
        <p className="text-muted-foreground mt-1">
          {currentTenant
            ? `Manage members of ${currentTenant.name}`
            : 'Manage organization members'}
        </p>
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

      {/* Member count */}
      {!isLoading && members.length > 0 && (
        <div className="flex items-center gap-2 text-sm text-muted-foreground">
          <Users className="h-4 w-4" />
          <span>
            {members.length} member{members.length !== 1 ? 's' : ''}
          </span>
        </div>
      )}

      {/* Content */}
      {isLoading ? (
        <div className="flex items-center justify-center h-64">
          <Loader2 className="h-8 w-8 animate-spin text-muted-foreground" />
        </div>
      ) : members.length === 0 ? (
        <div className="flex flex-col items-center justify-center h-64 text-muted-foreground">
          <Users className="h-16 w-16 mb-4 opacity-50" />
          <p className="text-lg">No members found</p>
          <p className="text-sm">
            This organization doesn&apos;t have any members yet
          </p>
        </div>
      ) : (
        <div className="space-y-3">
          {sortedMembers.map((member) => (
            <MemberRow
              key={member.user_id}
              member={member}
              isCurrentUser={member.user_id === currentUser?.id}
              currentUserRole={currentRole}
              tenantId={tenantId ?? ''}
              onRoleChange={handleRoleChange}
              onRemove={setMemberToRemove}
              isUpdating={isUpdating}
            />
          ))}
        </div>
      )}

      {/* Remove confirmation dialog */}
      <ConfirmDialog
        open={!!memberToRemove}
        onOpenChange={() => setMemberToRemove(null)}
        title="Remove Member"
        description={`Are you sure you want to remove ${
          memberToRemove?.name ?? memberToRemove?.user_id
        } from ${currentTenant?.name ?? 'this organization'}? They will lose access to all shared resources.`}
        confirmLabel="Remove"
        variant="destructive"
        isLoading={isRemoving}
        onConfirm={handleRemove}
      />
    </div>
  );
}
