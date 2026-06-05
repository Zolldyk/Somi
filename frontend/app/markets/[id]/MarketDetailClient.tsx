'use client';

import { useEffect } from 'react';
import { notFound } from 'next/navigation';
import { useAccount, useWriteContract, useWaitForTransactionReceipt } from 'wagmi';
import { formatUnits } from 'viem';
import { toast } from 'sonner';
import { useMarket } from '@/hooks/useMarket';
import { useMarketPools } from '@/hooks/useMarketPools';
import { usePoolDelta } from '@/hooks/usePoolDelta';
import { useUserPosition } from '@/hooks/useUserPosition';
import { StatusPill } from '@/components/somi/StatusPill';
import { PoolBar } from '@/components/somi/PoolBar';
import { ResolutionPlan } from '@/components/somi/ResolutionPlan';
import { BetForm } from '@/components/somi/BetForm';
import { ResolutionPipelineStrip } from '@/components/somi/ResolutionPipelineStrip';
import { VerdictBanner } from '@/components/somi/VerdictBanner';
import { ReceiptSummaryCard } from '@/components/somi/ReceiptSummaryCard';
import { predictionMarketAbi } from '@/lib/abi';
import { CONTRACT_ADDRESS } from '@/lib/constants';
import { translateContractError } from '@/lib/errors';

function fmtSTT(wei: bigint): string {
  return Number(formatUnits(wei, 18)).toFixed(2);
}

function isUserRejection(error: unknown): boolean {
  if (typeof error !== 'object' || error === null) return false;
  const msg =
    (error as { shortMessage?: string; message?: string }).shortMessage ??
    (error as { message?: string }).message ??
    '';
  return msg.toLowerCase().includes('rejected') || msg.toLowerCase().includes('denied');
}

export default function MarketDetailClient({ id }: { id: string }) {
  let parsedMarketId: bigint | null;
  try {
    parsedMarketId = BigInt(id);
  } catch {
    parsedMarketId = null;
  }
  const isInvalidMarketId = parsedMarketId === null || parsedMarketId <= 0n;
  const marketId: bigint = isInvalidMarketId ? 0n : parsedMarketId!;

  const { market, isPending, isError } = useMarket(marketId);
  const { yesPool: chainYesPool, noPool: chainNoPool } = useMarketPools(marketId);
  const poolDelta = usePoolDelta(marketId);
  const { address, isConnected } = useAccount();
  const { yesPosition, noPosition } = useUserPosition(marketId, isConnected ? address : undefined);

  const { writeContract: writeClaimTx, isPending: isClaimSigning, data: claimTxHash, error: claimWriteError } = useWriteContract();
  const { isLoading: isClaimConfirming, isSuccess: isClaimConfirmed } = useWaitForTransactionReceipt({ hash: claimTxHash });

  const { writeContract: writeRefundTx, isPending: isRefundSigning, data: refundTxHash, error: refundWriteError } = useWriteContract();
  const { isLoading: isRefundConfirming, isSuccess: isRefundConfirmed } = useWaitForTransactionReceipt({ hash: refundTxHash });
  const claimError = isClaimConfirmed || !claimWriteError ? null : translateContractError(claimWriteError);
  const refundError = isRefundConfirmed || !refundWriteError ? null : translateContractError(refundWriteError);

  useEffect(() => {
    if (!claimWriteError) return;
    if (translateContractError(claimWriteError)) return;
    if (isUserRejection(claimWriteError)) { toast('Claim not processed.'); }
    else { toast('Claim failed. Please try again.'); }
  }, [claimWriteError]);

  useEffect(() => {
    if (!refundWriteError) return;
    if (translateContractError(refundWriteError)) return;
    if (isUserRejection(refundWriteError)) { toast('Refund not processed.'); }
    else { toast('Refund failed. Please try again.'); }
  }, [refundWriteError]);

  if (isInvalidMarketId) notFound();
  if (!isPending && isError) notFound();
  if (!isPending && market && market.id === 0n) notFound();

  if (isPending || !market) return null;

  const isSettled =
    market.status === 'Resolved' ||
    market.status === 'Refunded' ||
    market.status === 'Disputed';

  const winnerSide: 0 | 1 | undefined =
    market.status === 'Resolved' && market.verdict === 'YES' ? 0 :
    market.status === 'Resolved' && market.verdict === 'NO' ? 1 :
    undefined;

  const showPosition = isConnected && (yesPosition > 0n || noPosition > 0n);

  const hasClaimablePosition =
    market.status === 'Resolved' &&
    ((market.verdict === 'YES' && yesPosition > 0n) ||
     (market.verdict === 'NO' && noPosition > 0n));

  const hasRefundablePosition =
    (market.status === 'Refunded' || market.status === 'Disputed') &&
    (yesPosition > 0n || noPosition > 0n);

  const isClaimBusy = isClaimSigning || isClaimConfirming;
  const isRefundBusy = isRefundSigning || isRefundConfirming;

  const claimLabel = isClaimSigning ? 'Signing…' : isClaimConfirming ? 'Confirming…' : 'Claim';
  const refundLabel = isRefundSigning ? 'Signing…' : isRefundConfirming ? 'Confirming…' : 'Refund';

  function handleClaim() {
    if (!CONTRACT_ADDRESS || !market) return;
    writeClaimTx({
      address: CONTRACT_ADDRESS,
      abi: predictionMarketAbi,
      functionName: 'claim',
      args: [market.id],
    });
  }

  function handleRefund() {
    if (!CONTRACT_ADDRESS || !market) return;
    writeRefundTx({
      address: CONTRACT_ADDRESS,
      abi: predictionMarketAbi,
      functionName: 'refund',
      args: [market.id],
    });
  }

  return (
    <div className="max-w-4xl mx-auto px-4 lg:px-8 py-8 lg:py-12">
      <div className="flex flex-col gap-6">
        {isSettled && <VerdictBanner market={market} />}
        <StatusPill
          variant="bordered"
          status={market.status}
          verdict={market.verdict}
          resolutionTime={market.status === 'Open' ? market.resolutionTime : undefined}
        />
        {isSettled ? (
          <h2 className="text-2xl lg:text-3xl font-semibold tracking-tight">{market.question}</h2>
        ) : (
          <h1 className="text-2xl lg:text-3xl font-semibold tracking-tight">{market.question}</h1>
        )}
        <PoolBar variant="lg" yesPool={chainYesPool + poolDelta.delta.yesPool} noPool={chainNoPool + poolDelta.delta.noPool} winnerSide={winnerSide} />
        {showPosition && (
          <div className="font-mono text-sm tabular-nums text-muted-foreground flex gap-4">
            <span>Your YES: {fmtSTT(yesPosition)} STT</span>
            <span>Your NO: {fmtSTT(noPosition)} STT</span>
          </div>
        )}
        <ResolutionPlan variant="full" market={market} />
        {isSettled && <ReceiptSummaryCard market={market} />}
        {isConnected && hasClaimablePosition && (
          <div className="flex flex-col gap-2">
            <button
              disabled={isClaimBusy}
              onClick={handleClaim}
              className={isClaimBusy
                ? 'w-full min-h-[44px] rounded-sm py-2.5 font-mono text-sm bg-foreground/10 text-foreground/50 cursor-not-allowed'
                : 'w-full min-h-[44px] rounded-sm py-2.5 font-mono text-sm bg-accent-yes/20 text-accent-yes hover:bg-accent-yes/30'
              }
            >
              {claimLabel}
            </button>
            {claimError && (
              <p className="font-mono text-xs text-destructive">{claimError}</p>
            )}
          </div>
        )}
        {isConnected && hasRefundablePosition && market.status === 'Refunded' && (
          <div className="flex flex-col gap-2">
            <button
              disabled={isRefundBusy}
              onClick={handleRefund}
              className={isRefundBusy
                ? 'w-full min-h-[44px] rounded-sm py-2.5 font-mono text-sm bg-foreground/10 text-foreground/50 cursor-not-allowed'
                : 'w-full min-h-[44px] rounded-sm py-2.5 font-mono text-sm bg-accent-llm/20 text-accent-llm hover:bg-accent-llm/30'
              }
            >
              {refundLabel}
            </button>
            {refundError && (
              <p className="font-mono text-xs text-destructive">{refundError}</p>
            )}
          </div>
        )}
        {isConnected && hasRefundablePosition && market.status === 'Disputed' && (
          <div className="flex flex-col gap-2">
            <button
              disabled={isRefundBusy}
              onClick={handleRefund}
              className={isRefundBusy
                ? 'w-full min-h-[44px] rounded-sm py-2.5 font-mono text-sm bg-foreground/10 text-foreground/50 cursor-not-allowed'
                : 'w-full min-h-[44px] rounded-sm py-2.5 font-mono text-sm bg-accent-warning/20 text-accent-warning hover:bg-accent-warning/30'
              }
            >
              {refundLabel}
            </button>
            {refundError && (
              <p className="font-mono text-xs text-destructive">{refundError}</p>
            )}
          </div>
        )}
        {market.status === 'Open' && <BetForm market={market} poolDelta={poolDelta} />}
        {(market.status === 'Resolving' || market.status === 'LLMResolving') && (
          <ResolutionPipelineStrip variant="hero" market={market} />
        )}
      </div>
    </div>
  );
}
