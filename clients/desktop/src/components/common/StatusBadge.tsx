import { cn } from '@/lib/utils';

type ShareStatus = 'pending' | 'accepted' | 'declined';

interface StatusBadgeProps {
  status: ShareStatus | string;
  className?: string;
}

const statusStyles: Record<ShareStatus, string> = {
  pending: 'bg-yellow-100 text-yellow-800 dark:bg-yellow-900/30 dark:text-yellow-400',
  accepted: 'bg-green-100 text-green-800 dark:bg-green-900/30 dark:text-green-400',
  declined: 'bg-red-100 text-red-800 dark:bg-red-900/30 dark:text-red-400',
};

const statusLabels: Record<ShareStatus, string> = {
  pending: 'Pending',
  accepted: 'Accepted',
  declined: 'Declined',
};

export function StatusBadge({ status, className }: StatusBadgeProps) {
  const normalizedStatus = status as ShareStatus;
  const styles = statusStyles[normalizedStatus];
  const label = statusLabels[normalizedStatus];

  if (!styles || !label) {
    return null;
  }

  return (
    <span
      className={cn(
        'inline-flex items-center rounded-full px-2 py-1 text-xs font-medium',
        styles,
        className
      )}
    >
      {label}
    </span>
  );
}
