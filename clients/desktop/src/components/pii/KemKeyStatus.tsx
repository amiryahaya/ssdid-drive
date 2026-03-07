import { Shield, ShieldCheck, Loader2 } from 'lucide-react';
import { cn } from '@/lib/utils';

interface KemKeyStatusProps {
  isRegistered: boolean;
  isLoading?: boolean;
  className?: string;
}

export function KemKeyStatus({ isRegistered, isLoading, className }: KemKeyStatusProps) {
  if (isLoading) {
    return (
      <div className={cn('flex items-center gap-2 text-sm text-muted-foreground', className)}>
        <Loader2 className="h-4 w-4 animate-spin" />
        <span>Registering keys...</span>
      </div>
    );
  }

  if (isRegistered) {
    return (
      <div className={cn('flex items-center gap-2 text-sm text-green-600 dark:text-green-400', className)}>
        <ShieldCheck className="h-4 w-4" />
        <span>Post-quantum encryption active</span>
      </div>
    );
  }

  return (
    <div className={cn('flex items-center gap-2 text-sm text-muted-foreground', className)}>
      <Shield className="h-4 w-4" />
      <span>Keys will be registered on first message</span>
    </div>
  );
}
