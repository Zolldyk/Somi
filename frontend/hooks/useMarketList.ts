'use client';

import { useReadContract, useReadContracts } from 'wagmi';
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

export function useMarketList(offset = 0, limit = 20) {
  const countResult = useReadContract({
    address: CONTRACT_ADDRESS,
    abi: predictionMarketAbi,
    functionName: 'getMarketCount',
    query: { enabled: !!CONTRACT_ADDRESS },
  });

  useInvalidateOnBlock(countResult.queryKey);

  const totalCount = Number((countResult.data as unknown as bigint | undefined) ?? 0n);

  const startId = offset + 1;
  const endId = Math.min(offset + limit, totalCount);
  const ids = totalCount > 0
    ? Array.from({ length: Math.max(0, endId - startId + 1) }, (_, i) => BigInt(startId + i))
    : [];

  const listResult = useReadContracts({
    contracts: ids.map((id) => ({
      address: CONTRACT_ADDRESS,
      abi: predictionMarketAbi,
      functionName: 'getMarket',
      args: [id],
    })),
    query: { enabled: !!CONTRACT_ADDRESS && ids.length > 0 },
  });

  useInvalidateOnBlock(listResult.queryKey);

  const rows = listResult.data ?? [];
  const hasFailure = rows.some((r) => r.status === 'failure');

  const markets: Market[] = rows
    .flatMap((r) => (r.status === 'success' && r.result ? [r.result as unknown as RawMarket] : []))
    .map((raw) => ({
      ...raw,
      status: MARKET_STATUS[raw.status],
      verdict: VERDICT[raw.verdict],
      pendingAgentType: AGENT_REQUEST_TYPE[raw.pendingAgentType],
    }))
    .filter((m) => m.status === 'Open')
    .sort((a, b) => (a.resolutionTime < b.resolutionTime ? -1 : a.resolutionTime > b.resolutionTime ? 1 : 0));

  return {
    markets,
    totalCount,
    isPending: countResult.isPending || listResult.isPending,
    isFetching: countResult.isFetching || listResult.isFetching,
    isError: countResult.isError || listResult.isError || hasFailure,
    error: countResult.error ?? listResult.error,
  };
}
