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
  type UserPosition,
} from '@/types/market';
import { useInvalidateOnBlock } from './internal/useInvalidateOnBlock';

const ZERO_ADDRESS = '0x0000000000000000000000000000000000000000' as const;

export function useMyPositions(address: `0x${string}` | undefined) {
  const enabled = !!CONTRACT_ADDRESS && !!address;

  const countResult = useReadContract({
    address: CONTRACT_ADDRESS,
    abi: predictionMarketAbi,
    functionName: 'getMarketCount',
    query: { enabled },
  });
  useInvalidateOnBlock(countResult.queryKey);

  const totalCount = Number((countResult.data as unknown as bigint | undefined) ?? 0n);
  const ids: bigint[] =
    enabled && totalCount > 0
      ? Array.from({ length: totalCount }, (_, i) => BigInt(i + 1))
      : [];

  const marketsResult = useReadContracts({
    contracts: ids.map((id) => ({
      address: CONTRACT_ADDRESS,
      abi: predictionMarketAbi,
      functionName: 'getMarket',
      args: [id],
    })),
    query: { enabled: enabled && ids.length > 0 },
  });
  useInvalidateOnBlock(marketsResult.queryKey);

  const betsResult = useReadContracts({
    contracts: ids.flatMap((id) => [
      {
        address: CONTRACT_ADDRESS,
        abi: predictionMarketAbi,
        functionName: 'getBet',
        args: [id, address ?? ZERO_ADDRESS, 0],
      },
      {
        address: CONTRACT_ADDRESS,
        abi: predictionMarketAbi,
        functionName: 'getBet',
        args: [id, address ?? ZERO_ADDRESS, 1],
      },
    ]),
    query: { enabled: enabled && ids.length > 0 },
  });
  useInvalidateOnBlock(betsResult.queryKey);

  const betsData = betsResult.data ?? [];

  const positions: UserPosition[] = [];

  (marketsResult.data ?? []).forEach((r, slotIdx) => {
    if (r.status !== 'success' || !r.result) return;
    const raw = r.result as unknown as RawMarket;
    const market: Market = {
      ...raw,
      status: MARKET_STATUS[raw.status],
      verdict: VERDICT[raw.verdict],
      pendingAgentType: AGENT_REQUEST_TYPE[raw.pendingAgentType],
    };

    const yesStake = (betsData[slotIdx * 2]?.result as unknown as bigint | undefined) ?? 0n;
    const noStake = (betsData[slotIdx * 2 + 1]?.result as unknown as bigint | undefined) ?? 0n;

    if (yesStake > 0n || noStake > 0n) {
      positions.push({ market, yesStake, noStake, claimed: false, refunded: false });
    }
  });

  const isPending =
    countResult.isPending || marketsResult.isPending || betsResult.isPending;
  const isFetching =
    countResult.isFetching || marketsResult.isFetching || betsResult.isFetching;
  const error = countResult.error ?? marketsResult.error ?? betsResult.error;

  return { positions, isPending, isFetching, error };
}
