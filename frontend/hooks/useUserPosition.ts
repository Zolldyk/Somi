'use client';

import { useReadContracts } from 'wagmi';
import { predictionMarketAbi } from '@/lib/abi';
import { CONTRACT_ADDRESS } from '@/lib/constants';
import { useInvalidateOnBlock } from './internal/useInvalidateOnBlock';

const ZERO_ADDRESS = '0x0000000000000000000000000000000000000000' as const;

export function useUserPosition(marketId: bigint, address: `0x${string}` | undefined) {
  const enabled = !!CONTRACT_ADDRESS && !!address && marketId > 0n;

  const result = useReadContracts({
    contracts: [
      {
        address: CONTRACT_ADDRESS,
        abi: predictionMarketAbi,
        functionName: 'getBet',
        args: [marketId, address ?? ZERO_ADDRESS, 0],
      },
      {
        address: CONTRACT_ADDRESS,
        abi: predictionMarketAbi,
        functionName: 'getBet',
        args: [marketId, address ?? ZERO_ADDRESS, 1],
      },
    ],
    query: { enabled },
  });

  useInvalidateOnBlock(result.queryKey);

  const yesResult = result.data?.[0];
  const noResult = result.data?.[1];
  const hasFailure =
    yesResult?.status === 'failure' || noResult?.status === 'failure';

  return {
    yesPosition: (yesResult?.result as unknown as bigint | undefined) ?? 0n,
    noPosition: (noResult?.result as unknown as bigint | undefined) ?? 0n,
    isPending: result.isPending,
    isFetching: result.isFetching,
    isError: result.isError || hasFailure,
    error: result.error ?? yesResult?.error ?? noResult?.error,
  };
}
