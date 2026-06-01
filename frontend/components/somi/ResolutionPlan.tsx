import { cn } from '@/lib/utils';
import type { Market } from '@/types/market';
import { AmbiguityBandViz } from './AmbiguityBandViz';

export interface ResolutionPlanProps {
  market: Market;
  variant: 'preview' | 'full';
  className?: string;
}

export function ResolutionPlan({ market, variant, className }: ResolutionPlanProps) {
  if (market.status === 'Resolving' || market.status === 'LLMResolving') return null;

  const isPost =
    market.status === 'Resolved' ||
    market.status === 'Refunded' ||
    market.status === 'Disputed';
  const marker = isPost ? '[✓]' : '[→]';

  let hostname: string;
  try {
    hostname = new URL(market.dataSource).hostname;
  } catch {
    hostname = market.dataSource;
  }

  const BPS_DENOM = 10_000n;
  const clampedBps = market.ambiguityBandBps > BPS_DENOM ? BPS_DENOM : market.ambiguityBandBps;
  const bandPct = (Number(clampedBps) / 100).toFixed(2).replace(/\.?0+$/, '');
  const thresholdDisplay = Number(market.threshold).toLocaleString();
  const half = market.threshold > 0n ? (market.threshold * clampedBps) / BPS_DENOM : 0n;
  const lowDisplay = Number(market.threshold - half).toLocaleString();
  const highDisplay = Number(market.threshold + half).toLocaleString();

  if (variant === 'preview') {
    return (
      <ul role="list" aria-label="Resolution plan steps" className={cn('space-y-0.5', className)}>
        <li role="listitem" className="font-mono text-xs text-muted-foreground truncate">
          {marker} {isPost ? 'Fetched' : 'Fetch'} {hostname}/{market.jsonSelector}
        </li>
        <li role="listitem" className="font-mono text-xs text-muted-foreground">
          {marker} {isPost ? 'Compared' : 'Compare'} to {thresholdDisplay}; ±{bandPct}% triggers AI tiebreaker
        </li>
      </ul>
    );
  }

  const lines = (
    <>
      <ul role="list" aria-label="Resolution plan steps" className="space-y-1">
        <li role="listitem" className="font-mono text-xs text-muted-foreground flex gap-1 min-w-0">
          <span className="shrink-0">{marker} {isPost ? 'Fetched' : 'Fetch'}</span>
          <span className="truncate" title={market.dataSource}>{market.dataSource}</span>
        </li>
        <li role="listitem" className="font-mono text-xs text-muted-foreground">
          {marker} {isPost ? 'Extracted' : 'Extract'} {market.jsonSelector}
        </li>
        <li role="listitem" className="font-mono text-xs text-muted-foreground">
          {marker} {isPost ? 'Compared' : 'Compare'} to threshold {thresholdDisplay}; band{' '}
          {String(market.ambiguityBandBps)} bps (range {lowDisplay}–{highDisplay})
        </li>
        <li role="listitem" className="font-mono text-xs text-muted-foreground">
          {marker} AI Tiebreaker if value within band; INVALID full-refund possible
        </li>
      </ul>
      <AmbiguityBandViz
        variant="md"
        threshold={market.threshold}
        bandBps={market.ambiguityBandBps}
        className="mt-3"
      />
    </>
  );

  if (isPost) {
    return (
      <div className={className}>
        <details>
          <summary className="cursor-pointer font-mono text-xs text-muted-foreground mb-1">
            Resolution plan · expand
          </summary>
          {lines}
        </details>
      </div>
    );
  }

  return <div className={cn('space-y-3', className)}>{lines}</div>;
}
