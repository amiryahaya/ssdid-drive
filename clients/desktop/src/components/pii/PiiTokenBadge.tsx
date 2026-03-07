import { ShieldAlert } from 'lucide-react';
import {
  Tooltip,
  TooltipContent,
  TooltipProvider,
  TooltipTrigger,
} from '@/components/ui/tooltip';
import { cn } from '@/lib/utils';

interface PiiTokenBadgeProps {
  tokensDetected: number;
  className?: string;
}

export function PiiTokenBadge({ tokensDetected, className }: PiiTokenBadgeProps) {
  if (tokensDetected === 0) return null;

  return (
    <TooltipProvider>
      <Tooltip>
        <TooltipTrigger asChild>
          <div
            className={cn(
              'inline-flex items-center gap-1 px-2 py-0.5 rounded-full text-xs font-medium',
              'bg-amber-100 text-amber-800 dark:bg-amber-900/30 dark:text-amber-300',
              'cursor-help',
              className
            )}
          >
            <ShieldAlert className="h-3 w-3" />
            <span>{tokensDetected} PII</span>
          </div>
        </TooltipTrigger>
        <TooltipContent>
          <p>
            {tokensDetected} piece{tokensDetected !== 1 ? 's' : ''} of personally identifiable
            information detected and protected with post-quantum encryption.
          </p>
        </TooltipContent>
      </Tooltip>
    </TooltipProvider>
  );
}
