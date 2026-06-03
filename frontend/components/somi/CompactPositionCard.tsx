'use client';

import { useState, useEffect } from 'react';
import Link from 'next/link';
import { formatUnits } from 'viem';
import { StatusPill } from './StatusPill';
import { PoolBar } from './PoolBar';
import { useClaim } from '@/hooks/useClaim';
import { useRefund } from '@/hooks/useRefund';
import type { UserPosition } from '@/types/market';
import type { PositionBucket } from '@/lib/myBetsSort';

function fmtSTT(wei: bigint): string {
  return Number(formatUnits(wei, 18)).toFixed(2);
}

function calculateClaimPayout(pos: UserPosition): bigint {
  const { market, yesStake, noStake } = pos;
  if (market.verdict === 'YES') {
    if (market.yesPool === 0n) return yesStake;
    return (yesStake * market.noPool) / market.yesPool + yesStake;
  }
  if (market.verdict === 'NO') {
    if (market.noPool === 0n) return noStake;
    return (noStake * market.yesPool) / market.noPool + noStake;
  }
  return 0n;
}

export interface CompactPositionCardProps {
  pos: UserPosition;
  bucket: PositionBucket;
}

export function CompactPositionCard({ pos, bucket }: CompactPositionCardProps) {
  const [localClaimed, setLocalClaimed] = useState(false);
  const [localRefunded, setLocalRefunded] = useState(false);

  const claimHook = useClaim(pos.market.id);
  const refundHook = useRefund(pos.market.id);

  useEffect(() => {
    if (claimHook.isConfirmed) setLocalClaimed(true);
  }, [claimHook.isConfirmed]); // eslint-disable-line react-hooks/exhaustive-deps

  useEffect(() => {
    if (refundHook.isConfirmed) setLocalRefunded(true);
  }, [refundHook.isConfirmed]); // eslint-disable-line react-hooks/exhaustive-deps

  const winnerSide: 0 | 1 | undefined =
    pos.market.status === 'Resolved' && pos.market.verdict === 'YES' ? 0 :
    pos.market.status === 'Resolved' && pos.market.verdict === 'NO' ? 1 :
    undefined;

  const isClaimBusy = claimHook.isPending || claimHook.isConfirming;
  const isRefundBusy = refundHook.isPending || refundHook.isConfirming;

  function renderActionArea() {
    if (bucket === 'claimable') {
      if (localClaimed) {
        return <span className="font-mono text-xs text-muted-foreground">Claimed</span>;
      }
      const claimLabel = claimHook.isPending
        ? 'Signing…'
        : claimHook.isConfirming
        ? 'Confirming…'
        : `Claim ${fmtSTT(calculateClaimPayout(pos))} STT`;
      return (
        <button
          disabled={isClaimBusy}
          onClick={claimHook.claim}
          className={`min-h-[44px] rounded-sm py-2 font-mono text-sm w-full ${
            isClaimBusy
              ? 'bg-foreground/10 text-foreground/50 cursor-not-allowed'
              : 'bg-accent-yes/20 text-accent-yes hover:bg-accent-yes/30'
          }`}
        >
          {claimLabel}
        </button>
      );
    }

    if (bucket === 'refundable-invalid') {
      if (localRefunded) {
        return <span className="font-mono text-xs text-muted-foreground">Refunded</span>;
      }
      const refundLabel = refundHook.isPending
        ? 'Signing…'
        : refundHook.isConfirming
        ? 'Confirming…'
        : `Refund ${fmtSTT(pos.yesStake + pos.noStake)} STT`;
      return (
        <button
          disabled={isRefundBusy}
          onClick={refundHook.refund}
          className={`min-h-[44px] rounded-sm py-2 font-mono text-sm w-full ${
            isRefundBusy
              ? 'bg-foreground/10 text-foreground/50 cursor-not-allowed'
              : 'bg-accent-llm/20 text-accent-llm hover:bg-accent-llm/30'
          }`}
        >
          {refundLabel}
        </button>
      );
    }

    if (bucket === 'refundable-disputed') {
      if (localRefunded) {
        return <span className="font-mono text-xs text-muted-foreground">Refunded</span>;
      }
      const refundLabel = refundHook.isPending
        ? 'Signing…'
        : refundHook.isConfirming
        ? 'Confirming…'
        : `Refund ${fmtSTT(pos.yesStake + pos.noStake)} STT`;
      return (
        <button
          disabled={isRefundBusy}
          onClick={refundHook.refund}
          className={`min-h-[44px] rounded-sm py-2 font-mono text-sm w-full ${
            isRefundBusy
              ? 'bg-foreground/10 text-foreground/50 cursor-not-allowed'
              : 'bg-accent-warning/20 text-accent-warning hover:bg-accent-warning/30'
          }`}
        >
          {refundLabel}
        </button>
      );
    }

    if (bucket === 'settled-loss') {
      return <span className="font-mono text-xs text-muted-foreground">Lost</span>;
    }

    return null;
  }

  const actionArea = renderActionArea();

  return (
    <div className="rounded-xl bg-card ring-1 ring-foreground/10 flex flex-col gap-3 px-3 py-3">
      <StatusPill
        variant="bordered"
        status={pos.market.status}
        verdict={pos.market.verdict}
        resolutionTime={pos.market.status === 'Open' ? pos.market.resolutionTime : undefined}
      />
      <Link
        href={'/markets/' + String(pos.market.id)}
        className="focus:outline-none focus-visible:ring-2 focus-visible:ring-ring focus-visible:ring-offset-1 rounded-sm"
      >
        <p className="text-base line-clamp-1">{pos.market.question}</p>
      </Link>
      <PoolBar
        variant="sm"
        yesPool={pos.market.yesPool}
        noPool={pos.market.noPool}
        winnerSide={winnerSide}
      />
      <div className="flex gap-3 font-mono text-xs tabular-nums text-muted-foreground">
        {pos.yesStake > 0n && <span>my YES: {fmtSTT(pos.yesStake)} STT</span>}
        {pos.noStake > 0n && <span>my NO: {fmtSTT(pos.noStake)} STT</span>}
      </div>
      {actionArea !== null && <div>{actionArea}</div>}
    </div>
  );
}
