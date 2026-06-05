import { formatUnits } from 'viem';
import { cva, type VariantProps } from 'class-variance-authority';
import { Skeleton } from '@/components/ui/skeleton';
import { cn } from '@/lib/utils';

const poolBarTrackVariants = cva('flex w-full overflow-hidden rounded-sm', {
  variants: {
    variant: {
      sm: 'h-1',
      md: 'h-1.5',
      lg: 'h-2',
    },
  },
  defaultVariants: { variant: 'md' },
});

export interface PoolBarProps extends VariantProps<typeof poolBarTrackVariants> {
  yesPool: bigint;
  noPool: bigint;
  winnerSide?: 0 | 1;
  className?: string;
}

function PoolBarBase({ yesPool, noPool, winnerSide, variant = 'md', className }: PoolBarProps) {
  const total = yesPool + noPool;
  const isEmpty = total === 0n;
  const yesPct = isEmpty ? 50n : (yesPool * 100n) / total;
  const noPct = isEmpty ? 50n : 100n - yesPct;
  const yesPctNum = Number(yesPct);
  const noPctNum = Number(noPct);

  // Keep tiny-but-nonzero minorities visible: 1% min slice for any nonzero pool.
  const yesFlex = isEmpty ? 50 : yesPool > 0n ? Math.max(1, yesPctNum) : 0;
  const noFlex = isEmpty ? 50 : noPool > 0n ? Math.max(1, noPctNum) : 0;

  let yesClass: string;
  let noClass: string;
  if (isEmpty) {
    yesClass = 'bg-muted';
    noClass = 'bg-muted';
  } else if (winnerSide === 0) {
    yesClass = 'bg-accent-yes';
    noClass = 'bg-muted';
  } else if (winnerSide === 1) {
    yesClass = 'bg-muted';
    noClass = 'bg-accent-no';
  } else {
    yesClass = 'bg-accent-yes/70';
    noClass = 'bg-accent-no/70';
  }

  return (
    <div className={cn('w-full', className)}>
      {variant === 'lg' && !isEmpty && (
        <div className="mb-0.5 flex justify-between font-mono text-xs tabular-nums text-muted-foreground">
          <span>{yesPctNum}% YES</span>
          <span>{formatUnits(total, 18).slice(0, 6)} STT total</span>
          <span>{noPctNum}% NO</span>
        </div>
      )}

      <div
        role="meter"
        aria-valuemin={0}
        aria-valuemax={100}
        aria-valuenow={yesPctNum}
        aria-label="YES probability"
        className={cn(poolBarTrackVariants({ variant }))}
      >
        <div style={{ flex: yesFlex }} className={cn('transition-none', yesClass)} />
        <div style={{ flex: noFlex }} className={cn('transition-none', noClass)} />
      </div>

      {(variant === 'md' || variant === 'lg') && !isEmpty && (
        <div className="mt-0.5 flex justify-between font-mono text-xs tabular-nums text-muted-foreground">
          <span>{yesPctNum}% YES</span>
          <span>{noPctNum}% NO</span>
        </div>
      )}

      {isEmpty && (
        <p className="mt-1 text-center font-mono text-xs text-muted-foreground">No bets yet</p>
      )}
    </div>
  );
}

function PoolBarSkeleton({
  variant = 'md',
  className,
}: Pick<PoolBarProps, 'variant' | 'className'>) {
  const heightClass =
    variant === 'sm' ? 'h-1' : variant === 'lg' ? 'h-2' : 'h-1.5';
  return (
    <div className={cn('w-full', className)}>
      {variant === 'lg' && (
        <div className="mb-0.5 flex justify-between">
          <Skeleton className="h-3 w-12 rounded-sm" />
          <Skeleton className="h-3 w-16 rounded-sm" />
          <Skeleton className="h-3 w-12 rounded-sm" />
        </div>
      )}
      <Skeleton className={cn('w-full rounded-sm', heightClass)} />
      {(variant === 'md' || variant === 'lg') && (
        <div className="mt-0.5 flex justify-between">
          <Skeleton className="h-3 w-12 rounded-sm" />
          <Skeleton className="h-3 w-12 rounded-sm" />
        </div>
      )}
    </div>
  );
}

export const PoolBar = Object.assign(PoolBarBase, { Skeleton: PoolBarSkeleton });
