import { useEffect, useState } from 'react';
import {
  Building2,
  Check,
  ChevronDown,
  Crown,
  Loader2,
  Shield,
  User,
} from 'lucide-react';
import { Button } from '@/components/ui/Button';
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuLabel,
  DropdownMenuSeparator,
  DropdownMenuTrigger,
} from '@/components/ui/DropdownMenu';
import { useTenantStore, type Tenant, type TenantRole } from '@/stores/tenantStore';
import { useToast } from '@/hooks/useToast';

function getRoleIcon(role: TenantRole) {
  switch (role) {
    case 'owner':
      return <Crown className="h-3 w-3 text-amber-500" />;
    case 'admin':
      return <Shield className="h-3 w-3 text-blue-500" />;
    default:
      return <User className="h-3 w-3 text-muted-foreground" />;
  }
}

function getRoleLabel(role: TenantRole): string {
  switch (role) {
    case 'owner':
      return 'Owner';
    case 'admin':
      return 'Admin';
    default:
      return 'Member';
  }
}

interface TenantItemProps {
  tenant: Tenant;
  isActive: boolean;
  onSelect: () => void;
  disabled?: boolean;
}

function TenantItem({ tenant, isActive, onSelect, disabled }: TenantItemProps) {
  return (
    <DropdownMenuItem
      onClick={onSelect}
      disabled={disabled}
      className="flex items-center justify-between gap-2 cursor-pointer"
    >
      <div className="flex items-center gap-2 min-w-0">
        <Building2 className="h-4 w-4 shrink-0 text-muted-foreground" />
        <div className="min-w-0">
          <p className="font-medium truncate">{tenant.name}</p>
          <div className="flex items-center gap-1 text-xs text-muted-foreground">
            {getRoleIcon(tenant.role)}
            <span>{getRoleLabel(tenant.role)}</span>
          </div>
        </div>
      </div>
      {isActive && <Check className="h-4 w-4 text-primary shrink-0" />}
    </DropdownMenuItem>
  );
}

export function TenantSwitcher() {
  const {
    currentTenant,
    availableTenants,
    isLoading,
    isSwitching,
    loadTenants,
    switchTenant,
  } = useTenantStore();

  const { success, error: showError } = useToast();
  const [isOpen, setIsOpen] = useState(false);

  useEffect(() => {
    loadTenants();
  }, [loadTenants]);

  // Don't show if only one tenant
  if (availableTenants.length <= 1 && !isLoading) {
    return null;
  }

  const handleSwitchTenant = async (tenant: Tenant) => {
    if (tenant.id === currentTenant?.id) {
      setIsOpen(false);
      return;
    }

    try {
      await switchTenant(tenant.id);
      success({
        title: 'Switched organization',
        description: `Now viewing ${tenant.name}`,
      });
      setIsOpen(false);
      // Reload the page to refresh all data for the new tenant
      window.location.reload();
    } catch (err) {
      showError({
        title: 'Failed to switch organization',
        description: err instanceof Error ? err.message : String(err),
      });
    }
  };

  return (
    <DropdownMenu open={isOpen} onOpenChange={setIsOpen}>
      <DropdownMenuTrigger asChild>
        <Button
          variant="ghost"
          className="flex items-center gap-2 px-3 h-9 max-w-[200px]"
          disabled={isSwitching}
        >
          {isSwitching ? (
            <Loader2 className="h-4 w-4 animate-spin" />
          ) : (
            <Building2 className="h-4 w-4 shrink-0" />
          )}
          <span className="truncate">{currentTenant?.name ?? 'Select Organization'}</span>
          <ChevronDown className="h-4 w-4 shrink-0 opacity-50" />
        </Button>
      </DropdownMenuTrigger>

      <DropdownMenuContent align="start" className="w-[240px]">
        <DropdownMenuLabel className="text-xs text-muted-foreground font-normal">
          Switch Organization
        </DropdownMenuLabel>
        <DropdownMenuSeparator />

        {isLoading ? (
          <div className="flex items-center justify-center py-4">
            <Loader2 className="h-5 w-5 animate-spin text-muted-foreground" />
          </div>
        ) : (
          availableTenants.map((tenant) => (
            <TenantItem
              key={tenant.id}
              tenant={tenant}
              isActive={tenant.id === currentTenant?.id}
              onSelect={() => handleSwitchTenant(tenant)}
              disabled={isSwitching}
            />
          ))
        )}
      </DropdownMenuContent>
    </DropdownMenu>
  );
}
