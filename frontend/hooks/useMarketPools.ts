'use client';

import { useMarket } from './useMarket';

export function useMarketPools(marketId: bigint) {
  const { market, isPending, isFetching, isError, error } = useMarket(marketId);

  return {
    yesPool: market?.yesPool ?? 0n,
    noPool: market?.noPool ?? 0n,
    isPending,
    isFetching,
    isError,
    error,
  };
}
