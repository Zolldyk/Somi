'use client';

import { useMarket } from '@/hooks/useMarket';
import { FeaturedMarketCard } from './FeaturedMarketCard';

export interface FeaturedMarketSlotProps {
  marketId: bigint;
}

export function FeaturedMarketSlot({ marketId }: FeaturedMarketSlotProps) {
  const { market, isPending, isError } = useMarket(marketId);

  if (isPending) return <FeaturedMarketCard.Skeleton />;
  if (isError || !market) return null;
  return <FeaturedMarketCard market={market} />;
}
