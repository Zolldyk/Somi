'use client';

import { useState } from 'react';
import Link from 'next/link';
import { ChevronDown } from 'lucide-react';
import { useAccount } from 'wagmi';
import { Skeleton } from '@/components/ui/skeleton';
import { PoolBar } from '@/components/somi/PoolBar';
import { WalletConnectPill } from '@/components/somi/WalletConnectPill';
import { CompactPositionCard } from '@/components/somi/CompactPositionCard';
import { useMyPositions } from '@/hooks/useMyPositions';
import { classifyAndSort, type PositionBucket } from '@/lib/myBetsSort';

const BUCKET_ORDER: PositionBucket[] = [
  'claimable',
  'refundable-invalid',
  'refundable-disputed',
  'resolving',
  'open',
  'settled-loss',
];

const BUCKET_LABEL: Record<PositionBucket, string> = {
  claimable: 'READY TO CLAIM',
  'refundable-invalid': 'REFUND AVAILABLE — INVALID',
  'refundable-disputed': 'REFUND AVAILABLE — DISPUTED',
  resolving: 'RESOLVING',
  open: 'OPEN',
  'settled-loss': 'SETTLED',
};

function CompactRowSkeleton() {
  return (
    <div className="flex flex-col gap-3 px-3 py-3 rounded-xl bg-card ring-1 ring-foreground/10">
      <Skeleton className="h-4 w-24 rounded-sm" />
      <Skeleton className="h-5 w-full" />
      <PoolBar.Skeleton variant="sm" />
      <Skeleton className="h-3.5 w-2/3" />
    </div>
  );
}

export default function MyBetsPage() {
  const { address, isConnected } = useAccount();
  const { positions, isPending } = useMyPositions(isConnected ? address : undefined);
  const [settledOpen, setSettledOpen] = useState(false);

  if (!isConnected) {
    return (
      <div className="max-w-4xl mx-auto px-4 lg:px-8 py-8 lg:py-12 flex flex-col items-center gap-6 text-center">
        <p className="text-muted-foreground">Connect your wallet to see your positions</p>
        <WalletConnectPill />
      </div>
    );
  }

  if (isPending) {
    return (
      <div className="max-w-4xl mx-auto px-4 lg:px-8 py-8 lg:py-12">
        <Skeleton className="h-8 w-32 mb-8" />
        <div className="flex flex-col gap-3">
          <CompactRowSkeleton />
          <CompactRowSkeleton />
          <CompactRowSkeleton />
          <CompactRowSkeleton />
        </div>
      </div>
    );
  }

  return (
    <div className="max-w-4xl mx-auto px-4 lg:px-8 py-8 lg:py-12">
      <h1 className="text-2xl font-bold mb-8">My Bets</h1>
      {positions.length === 0 ? (
        <p className="text-muted-foreground">
          No bets yet.{' '}
          <Link href="/" className="underline underline-offset-2 hover:opacity-80">
            Browse open markets →
          </Link>
        </p>
      ) : (
        <div className="flex flex-col gap-8">
          {(() => {
            const groups = classifyAndSort(positions);
            return BUCKET_ORDER.filter((key) => groups[key].length > 0).map((key) => {
              if (key === 'settled-loss') {
                return (
                  <section key={key}>
                    <details
                      open={settledOpen}
                      onToggle={() => setSettledOpen(prev => !prev)}
                    >
                      <summary className="list-none flex items-center gap-2 cursor-pointer text-xs font-mono uppercase tracking-wider text-muted-foreground focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring focus-visible:ring-offset-1 rounded-sm">
                        SETTLED · {groups[key].length} bets{!settledOpen && ' (expand to view)'}
                        <ChevronDown className={`h-3 w-3 transition-transform${settledOpen ? ' rotate-180' : ''}`} />
                      </summary>
                      <ul className="flex flex-col gap-3 mt-3">
                        {groups[key].map((pos) => (
                          <li key={pos.market.id.toString()}>
                            <CompactPositionCard pos={pos} bucket="settled-loss" />
                          </li>
                        ))}
                      </ul>
                    </details>
                  </section>
                );
              }
              return (
                <section key={key}>
                  <h2 className="text-xs font-mono uppercase tracking-wider text-muted-foreground mb-3">
                    {BUCKET_LABEL[key]} · {groups[key].length}
                  </h2>
                  <ul className="flex flex-col gap-3">
                    {groups[key].map((pos) => (
                      <li key={pos.market.id.toString()}>
                        <CompactPositionCard pos={pos} bucket={key as PositionBucket} />
                      </li>
                    ))}
                  </ul>
                </section>
              );
            });
          })()}
        </div>
      )}
    </div>
  );
}
