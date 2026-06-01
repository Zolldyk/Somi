import { cva, type VariantProps } from 'class-variance-authority';
import { Skeleton } from '@/components/ui/skeleton';
import { cn } from '@/lib/utils';
import type { MarketStatus, Verdict } from '@/types/market';
import { CountdownTimer } from './CountdownTimer';

const statusPillVariants = cva(
  'inline-flex items-center gap-1 font-mono text-xs tracking-wider uppercase',
  {
    variants: {
      variant: {
        default: '',
        bordered: 'border border-current/20 rounded-sm px-1.5 py-0.5',
        solid: 'bg-current/10 border border-current/20 rounded-sm px-1.5 py-0.5',
      },
    },
    defaultVariants: {
      variant: 'default',
    },
  }
);

type StatusColor =
  | 'text-muted-foreground'
  | 'text-accent-llm'
  | 'text-accent-yes'
  | 'text-accent-no'
  | 'text-accent-warning';

function resolveDisplay(
  status: MarketStatus,
  verdict?: Verdict
): { text: string; color: StatusColor } {
  switch (status) {
    case 'Open':
      return { text: 'OPEN', color: 'text-muted-foreground' };
    case 'Resolving':
    case 'LLMResolving':
      return { text: 'RESOLVING…', color: 'text-accent-llm' };
    case 'Resolved':
      if (verdict === 'YES') return { text: 'RESOLVED · YES', color: 'text-accent-yes' };
      if (verdict === 'NO') return { text: 'RESOLVED · NO', color: 'text-accent-no' };
      // Contract invariant: Resolved is only reachable with verdict YES or NO.
      return { text: 'RESOLVED', color: 'text-muted-foreground' };
    case 'Refunded':
      return { text: 'INCONCLUSIVE', color: 'text-accent-llm' };
    case 'Disputed':
      return { text: 'FAILED', color: 'text-accent-warning' };
    default: {
      // Compile-time exhaustiveness — surfaces new MarketStatus additions.
      const _exhaustive: never = status;
      return { text: String(_exhaustive).toUpperCase(), color: 'text-muted-foreground' };
    }
  }
}

export interface StatusPillProps extends VariantProps<typeof statusPillVariants> {
  status: MarketStatus;
  verdict?: Verdict;
  resolutionTime?: bigint;
  className?: string;
}

function StatusPillBase({ status, verdict, resolutionTime, variant, className }: StatusPillProps) {
  const { text, color } = resolveDisplay(status, verdict);

  return (
    <span
      role="status"
      aria-live="polite"
      className={cn(statusPillVariants({ variant }), color, className)}
    >
      {variant === 'bordered' && <span aria-hidden="true">·</span>}
      {text}
      {status === 'Open' && resolutionTime !== undefined && (
        <CountdownTimer resolutionTime={resolutionTime} />
      )}
    </span>
  );
}

function StatusPillSkeleton() {
  return <Skeleton className="h-4 w-24 rounded-sm" />;
}

export const StatusPill = Object.assign(StatusPillBase, { Skeleton: StatusPillSkeleton });
