'use client';

import Link from 'next/link';
import { useAccount, useReadContract, useReadContracts } from 'wagmi';
import { predictionMarketAbi } from '@/lib/abi';
import { CONTRACT_ADDRESS } from '@/lib/constants';
import {
  MARKET_STATUS,
  VERDICT,
  AGENT_REQUEST_TYPE,
  type Market,
  type RawMarket,
} from '@/types/market';
import { useInvalidateOnBlock } from '@/hooks/internal/useInvalidateOnBlock';
import { cn } from '@/lib/utils';

const ZERO_ADDRESS = '0x0000000000000000000000000000000000000000' as const;

type Bucket = 'claimable' | 'refundable-invalid' | 'refundable-disputed';

function useActionablePositions(address: `0x${string}` | undefined) {
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
  let claimable = 0;
  let refundableInvalid = 0;
  let refundableDisputed = 0;

  // Iterate over the raw marketsResult slots using the original slot index so
  // betsData[slotIdx * 2] / [slotIdx * 2 + 1] stays aligned even when some
  // getMarket calls fail and are skipped.
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

    if (market.status === 'Resolved') {
      const winningSide = market.verdict === 'YES' ? 0 : market.verdict === 'NO' ? 1 : -1;
      if (winningSide === 0 && yesStake > 0n) claimable++;
      else if (winningSide === 1 && noStake > 0n) claimable++;
    } else if (market.status === 'Refunded') {
      if (yesStake > 0n || noStake > 0n) refundableInvalid++;
    } else if (market.status === 'Disputed') {
      if (yesStake > 0n || noStake > 0n) refundableDisputed++;
    }
  });

  const topBucket: Bucket | null =
    claimable > 0
      ? 'claimable'
      : refundableInvalid > 0
      ? 'refundable-invalid'
      : refundableDisputed > 0
      ? 'refundable-disputed'
      : null;

  return {
    topBucket,
    claimable,
    refundableInvalid,
    refundableDisputed,
    isPending: countResult.isPending,
  };
}

const BUCKET_CONFIG: Record<
  Bucket,
  { bgClass: string; borderClass: string; copyFn: (n: number) => string; ariaFn: (n: number) => string }
> = {
  claimable: {
    bgClass: 'bg-accent-yes/10',
    borderClass: 'border-b border-accent-yes/30',
    copyFn: (n) => `${n} ${n === 1 ? 'bet' : 'bets'} ready to claim →`,
    ariaFn: (n) => `${n} ${n === 1 ? 'bet' : 'bets'} ready to claim. Go to My Bets page.`,
  },
  'refundable-invalid': {
    bgClass: 'bg-accent-llm/10',
    borderClass: 'border-b border-accent-llm/30',
    copyFn: (n) => `${n} ${n === 1 ? 'bet' : 'bets'} eligible for refund (INVALID) →`,
    ariaFn: (n) => `${n} ${n === 1 ? 'bet' : 'bets'} eligible for INVALID refund. Go to My Bets page.`,
  },
  'refundable-disputed': {
    bgClass: 'bg-accent-warning/10',
    borderClass: 'border-b border-accent-warning/30',
    copyFn: (n) => `${n} ${n === 1 ? 'bet' : 'bets'} eligible for refund (Disputed) →`,
    ariaFn: (n) => `${n} ${n === 1 ? 'bet' : 'bets'} eligible for Disputed refund. Go to My Bets page.`,
  },
};

export function AttentionBanner() {
  const { address, isConnected } = useAccount();
  const { topBucket, claimable, refundableInvalid, refundableDisputed, isPending } =
    useActionablePositions(isConnected ? address : undefined);

  if (!isConnected || !topBucket || isPending) return null;

  const count =
    topBucket === 'claimable'
      ? claimable
      : topBucket === 'refundable-invalid'
      ? refundableInvalid
      : refundableDisputed;

  const { bgClass, borderClass, copyFn, ariaFn } = BUCKET_CONFIG[topBucket];

  return (
    <div
      role="status"
      aria-label={ariaFn(count)}
      className={cn('w-full', bgClass, borderClass)}
    >
      <Link
        href="/my-bets"
        className="block max-w-7xl mx-auto py-2 px-4 text-center text-sm text-foreground hover:opacity-90 transition-opacity focus:outline-none focus-visible:ring-2 focus-visible:ring-ring focus-visible:ring-offset-2"
      >
        {copyFn(count)}
      </Link>
    </div>
  );
}
