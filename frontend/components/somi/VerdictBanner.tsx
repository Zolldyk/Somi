import { Skeleton } from '@/components/ui/skeleton';
import { cn } from '@/lib/utils';
import type { Market } from '@/types/market';

export interface VerdictBannerProps {
  market: Market;
  className?: string;
}

function formatResolvedSubtitle(resolvedAt: bigint): string {
  const date = new Date(Number(resolvedAt) * 1000).toLocaleString('en-US', {
    dateStyle: 'medium',
    timeStyle: 'short',
    timeZone: 'UTC',
  });
  return `resolved · ${date} UTC · same block as agent callback`;
}

function VerdictBannerBase({ market, className }: VerdictBannerProps) {
  if (
    market.status !== 'Resolved' &&
    market.status !== 'Refunded' &&
    market.status !== 'Disputed'
  ) {
    return null;
  }

  if (market.status === 'Resolved' && market.verdict === 'YES') {
    const subtitle = formatResolvedSubtitle(market.resolvedAt);
    return (
      <div
        role="status"
        aria-live="off"
        className={cn('w-full rounded-sm border border-accent-yes bg-accent-yes/[0.04] p-6 lg:p-8', className)}
      >
        <h1 className="font-mono text-5xl font-bold uppercase text-accent-yes">VERDICT: YES</h1>
        <p className="mt-2 text-sm text-muted-foreground">{subtitle}</p>
      </div>
    );
  }

  if (market.status === 'Resolved' && market.verdict === 'NO') {
    const subtitle = formatResolvedSubtitle(market.resolvedAt);
    return (
      <div
        role="status"
        aria-live="off"
        className={cn('w-full rounded-sm border border-accent-no bg-accent-no/[0.04] p-6 lg:p-8', className)}
      >
        <h1 className="font-mono text-5xl font-bold uppercase text-accent-no">VERDICT: NO</h1>
        <p className="mt-2 text-sm text-muted-foreground">{subtitle}</p>
      </div>
    );
  }

  if (market.status === 'Refunded') {
    return (
      <div
        role="status"
        aria-live="off"
        className={cn('w-full rounded-sm border border-accent-llm bg-accent-llm/[0.04] p-6 lg:p-8', className)}
      >
        <h1 className="font-mono text-5xl font-bold uppercase text-accent-llm">VERDICT: INCONCLUSIVE</h1>
        <p className="mt-2 text-sm text-muted-foreground">
          AI determined the data was too ambiguous to resolve fairly. Full refund issued.
        </p>
      </div>
    );
  }

  return (
    <div
      role="status"
      aria-live="off"
      className={cn('w-full rounded-sm border border-accent-warning bg-accent-warning/[0.04] p-6 lg:p-8', className)}
    >
      <h1 className="font-mono text-5xl font-bold uppercase text-accent-warning">RESOLUTION FAILED</h1>
      <p className="mt-2 text-sm text-muted-foreground">
        The resolution agent could not complete — consensus failed or the data source was unavailable. Full refund issued.
      </p>
    </div>
  );
}

function VerdictBannerSkeleton() {
  return <Skeleton className="h-24 w-full rounded-sm" />;
}

export const VerdictBanner = Object.assign(VerdictBannerBase, { Skeleton: VerdictBannerSkeleton });
