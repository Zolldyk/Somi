import type { Market } from '@/types/market';
import { MarketCard } from '@/components/somi/MarketCard';

export interface LiveMarketPreviewProps {
  question: string;
  dataSource: string;
  jsonSelector: string;
  threshold: string;
  ambiguityBandBps: number;
  resolutionTime: number;
}

export function LiveMarketPreview({
  question,
  dataSource,
  jsonSelector,
  threshold,
  ambiguityBandBps,
  resolutionTime,
}: LiveMarketPreviewProps) {
  let thresholdBigInt = 0n;
  try { thresholdBigInt = BigInt(threshold || '0'); } catch { /* empty or non-numeric */ }

  const syntheticMarket: Market = {
    id: 0n,
    creator: '0x0000000000000000000000000000000000000000',
    question: question || 'Your question will appear here…',
    dataSource,
    jsonSelector,
    threshold: thresholdBigInt,
    ambiguityBandBps: BigInt(ambiguityBandBps),
    resolutionTime: BigInt(resolutionTime),
    yesPool: 0n,
    noPool: 0n,
    status: 'Open',
    verdict: 'Unset',
    subscriptionId: 0n,
    pendingRequestId: 0n,
    pendingAgentType: 'None',
    resolvedAt: 0n,
  };

  return (
    <div className="flex flex-col gap-2">
      <p className="font-mono text-xs text-muted-foreground">
        Preview — exactly how this will appear on /
      </p>
      <div className="pointer-events-none">
        <MarketCard market={syntheticMarket} variant="default" />
      </div>
    </div>
  );
}
