import Link from 'next/link';
import { formatUnits } from 'viem';
import { Card } from '@/components/ui/card';
import { Separator } from '@/components/ui/separator';
import { Skeleton } from '@/components/ui/skeleton';
import { cn } from '@/lib/utils';
import type { Market } from '@/types/market';
import { PoolBar } from './PoolBar';
import { ResolutionPlan } from './ResolutionPlan';
import { StatusPill } from './StatusPill';

export interface FeaturedMarketCardProps {
  market: Market;
  className?: string;
}

function fmtSTT(wei: bigint): string {
  return Number(formatUnits(wei, 18)).toFixed(2);
}

function borderAccentClass(market: Market): string {
  if (market.status === 'Resolved') {
    if (market.verdict === 'YES') return 'border-l-2 border-accent-yes';
    if (market.verdict === 'NO') return 'border-l-2 border-accent-no';
  }
  if (market.status === 'Refunded') return 'border-l-2 border-accent-llm';
  if (market.status === 'Disputed') return 'border-l-2 border-accent-warning';
  return '';
}

function formatRemaining(resolutionTime: bigint): string | null {
  const diffSec = Number(resolutionTime) - Math.floor(Date.now() / 1000);
  if (diffSec < 0) return null;
  if (diffSec === 0) return 'now';
  const totalMin = Math.floor(diffSec / 60);
  const totalHr = Math.floor(totalMin / 60);
  const totalDay = Math.floor(totalHr / 24);
  if (totalDay >= 1) return `${totalDay}d ${totalHr % 24}h`;
  if (totalHr >= 1) return `${totalHr}h ${totalMin % 60}m`;
  if (totalMin >= 1) return `${totalMin}m`;
  return '<1m';
}

function buildAriaLabel(market: Market): string {
  const q = market.question;
  if (market.status === 'Open') {
    const remaining = formatRemaining(market.resolutionTime);
    return remaining === null ? `${q} — OPEN` : `${q} — OPEN, ${remaining} remaining`;
  }
  if (market.status === 'Resolving' || market.status === 'LLMResolving') return `${q} — RESOLVING`;
  if (market.status === 'Resolved') return `${q} — RESOLVED · ${market.verdict}`;
  if (market.status === 'Refunded') return `${q} — INCONCLUSIVE`;
  if (market.status === 'Disputed') return `${q} — FAILED`;
  return q;
}

function FeaturedMarketCardBase({ market, className }: FeaturedMarketCardProps) {
  const winnerSide =
    market.status === 'Resolved' && market.verdict === 'YES' ? 0 :
    market.status === 'Resolved' && market.verdict === 'NO' ? 1 :
    undefined;

  return (
    <Link
      href={'/markets/' + String(market.id)}
      aria-label={buildAriaLabel(market)}
      className="block rounded-xl focus:outline-none focus-visible:ring-2 focus-visible:ring-ring focus-visible:ring-offset-2"
    >
      <Card
        className={cn(
          borderAccentClass(market),
          'gap-6 p-6 hover:ring-foreground/20 transition-colors',
          className,
        )}
      >
        <StatusPill
          variant="bordered"
          status={market.status}
          verdict={market.verdict}
          resolutionTime={market.status === 'Open' ? market.resolutionTime : undefined}
        />
        <h2 className="text-2xl lg:text-3xl font-semibold tracking-tight" title={market.question}>
          {market.question}
        </h2>
        <PoolBar
          variant="lg"
          yesPool={market.yesPool}
          noPool={market.noPool}
          winnerSide={winnerSide}
        />
        <div className="flex justify-between font-mono text-sm tabular-nums text-muted-foreground">
          <span>YES: {fmtSTT(market.yesPool)} STT</span>
          <span>Total: {fmtSTT(market.yesPool + market.noPool)} STT</span>
          <span>NO: {fmtSTT(market.noPool)} STT</span>
        </div>
        <Separator />
        <ResolutionPlan variant="full" market={market} />
        <Separator />
        <div
          role="note"
          className="rounded-md border border-dashed border-border px-4 py-6 text-sm text-muted-foreground"
        >
          Bet form available on the market page →
        </div>
      </Card>
    </Link>
  );
}

function FeaturedMarketCardSkeleton() {
  return (
    <div className="flex flex-col gap-6 overflow-hidden rounded-xl bg-card p-6 ring-1 ring-foreground/10">
      <Skeleton className="h-4 w-24 rounded-sm" />
      <Skeleton className="h-8 w-full" />
      <Skeleton className="h-8 w-3/4" />
      <PoolBar.Skeleton variant="lg" />
      <div className="flex justify-between">
        <Skeleton className="h-5 w-20" />
        <Skeleton className="h-5 w-20" />
        <Skeleton className="h-5 w-20" />
      </div>
      <Skeleton className="h-px w-full" />
      <div className="space-y-0.5">
        <Skeleton className="h-3.5 w-full" />
        <Skeleton className="h-3.5 w-full" />
        <Skeleton className="h-3.5 w-full" />
        <Skeleton className="h-3.5 w-full" />
      </div>
      <Skeleton className="h-px w-full" />
      <Skeleton className="h-16 w-full rounded-md" />
    </div>
  );
}

export const FeaturedMarketCard = Object.assign(FeaturedMarketCardBase, {
  Skeleton: FeaturedMarketCardSkeleton,
});
