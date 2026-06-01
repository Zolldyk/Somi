'use client';

import Link from 'next/link';
import { useMarketList } from '@/hooks/useMarketList';
import { MarketCard } from './MarketCard';

const SKELETON_COUNT = 4;
const GRID_CLASS = 'grid grid-cols-1 lg:grid-cols-2 gap-4';

export function MarketGrid() {
  const { markets, isPending, isError } = useMarketList();

  if (isError) {
    return (
      <div className={GRID_CLASS}>
        <p role="alert" className="col-span-full text-sm text-accent-no">
          Couldn&apos;t load markets. Check your network and refresh.
        </p>
      </div>
    );
  }

  if (isPending) {
    return (
      <div className={GRID_CLASS}>
        {Array.from({ length: SKELETON_COUNT }).map((_, i) => (
          <MarketCard.Skeleton key={i} />
        ))}
      </div>
    );
  }

  if (markets.length === 0) {
    return (
      <div className={GRID_CLASS}>
        <p className="col-span-full text-sm text-muted-foreground">
          No open markets yet.{' '}
          <Link href="/create" className="text-foreground underline-offset-4 hover:underline">
            Create one →
          </Link>
        </p>
      </div>
    );
  }

  return (
    <div className={GRID_CLASS}>
      {markets.map((m) => (
        <MarketCard key={String(m.id)} market={m} />
      ))}
    </div>
  );
}
