'use client';

import { useReadContract } from 'wagmi';
import { predictionMarketAbi } from '@/lib/abi';
import { CONTRACT_ADDRESS } from '@/lib/constants';
import {
  MARKET_STATUS,
  VERDICT,
  AGENT_REQUEST_TYPE,
  type Market,
  type RawMarket,
} from '@/types/market';
import { useInvalidateOnBlock } from './internal/useInvalidateOnBlock';

export function useMarket(marketId: bigint) {
  const result = useReadContract({
    address: CONTRACT_ADDRESS,
    abi: predictionMarketAbi,
    functionName: 'getMarket',
    args: [marketId],
    query: { enabled: !!CONTRACT_ADDRESS && marketId > 0n },
  });

  useInvalidateOnBlock(result.queryKey);

  const rawData = result.data as unknown as RawMarket | undefined;

  const market: Market | undefined = rawData
    ? {
        ...rawData,
        status: MARKET_STATUS[rawData.status],
        verdict: VERDICT[rawData.verdict],
        pendingAgentType: AGENT_REQUEST_TYPE[rawData.pendingAgentType],
      }
    : undefined;

  return {
    market,
    isPending: result.isPending,
    isFetching: result.isFetching,
    isError: result.isError,
    error: result.error,
  };
}
