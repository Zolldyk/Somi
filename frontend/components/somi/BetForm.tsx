'use client';

import { useState, useEffect } from 'react';
import { useAccount, useWriteContract, useWaitForTransactionReceipt } from 'wagmi';
import { parseEther, formatUnits } from 'viem';
import { toast } from 'sonner';
import { Skeleton } from '@/components/ui/skeleton';
import { cn } from '@/lib/utils';
import { predictionMarketAbi } from '@/lib/abi';
import { CONTRACT_ADDRESS, MIN_BET_STT } from '@/lib/constants';
import { translateContractError } from '@/lib/errors';
import { useUserPosition } from '@/hooks/useUserPosition';
import type { Market } from '@/types/market';

type PoolDeltaControls = {
  addOptimistic(side: 0 | 1, amount: bigint): void;
  rollback(): void;
  clear(): void;
};

export interface BetFormProps {
  market: Market;
  poolDelta: PoolDeltaControls;
  className?: string;
}

type FormMode = 'disconnected' | 'no-side' | 'invalid' | 'valid' | 'signing' | 'confirming';

function deriveMode(
  isConnected: boolean,
  selectedSide: 0 | 1 | null,
  isValidAmount: boolean,
  isSigning: boolean,
  isConfirming: boolean
): FormMode {
  if (isSigning) return 'signing';
  if (isConfirming) return 'confirming';
  if (!isConnected) return 'disconnected';
  if (selectedSide === null) return 'no-side';
  if (!isValidAmount) return 'invalid';
  return 'valid';
}

function isUserRejection(error: unknown): boolean {
  if (typeof error !== 'object' || error === null) return false;
  const msg =
    (error as { shortMessage?: string; message?: string }).shortMessage ??
    (error as { message?: string }).message ??
    '';
  return msg.toLowerCase().includes('rejected') || msg.toLowerCase().includes('denied');
}

function BetFormBase({ market, poolDelta, className }: BetFormProps) {
  const { address, isConnected } = useAccount();
  const { yesPosition, noPosition } = useUserPosition(market.id, isConnected ? address : undefined);

  const [selectedSide, setSelectedSide] = useState<0 | 1 | null>(null);
  const [amountStr, setAmountStr] = useState('');
  const [inlineError, setInlineError] = useState<string | null>(null);

  const trimmedAmount = amountStr.trim();
  const isStrictDecimal = /^\d*\.?\d+$/.test(trimmedAmount);
  const amountNum = isStrictDecimal ? parseFloat(trimmedAmount) : NaN;
  const isValidAmount = isStrictDecimal && !isNaN(amountNum) && amountNum >= MIN_BET_STT;

  const { writeContract, isPending: isSigning, data: txHash } = useWriteContract();
  const { isLoading: isConfirming, isSuccess: isConfirmed, isError: isReceiptError } =
    useWaitForTransactionReceipt({ hash: txHash });

  useEffect(() => {
    if (isConfirmed) {
      queueMicrotask(() => {
        poolDelta.clear();
        setSelectedSide(null);
        setAmountStr('');
        setInlineError(null);
      });
    }
  }, [isConfirmed]); // eslint-disable-line react-hooks/exhaustive-deps

  useEffect(() => {
    if (isReceiptError) {
      poolDelta.rollback();
      toast('Bet failed. Please try again.');
    }
  }, [isReceiptError]); // eslint-disable-line react-hooks/exhaustive-deps

  if (market.status !== 'Open') return null;

  const mode = deriveMode(isConnected, selectedSide, isValidAmount, isSigning, isConfirming);
  const showPosition = isConnected && (yesPosition > 0n || noPosition > 0n);
  const errorId = 'bet-amount-error';

  function handleSubmit() {
    if (selectedSide === null || !isValidAmount || !CONTRACT_ADDRESS) return;
    setInlineError(null);
    let amountWei: bigint;
    try {
      amountWei = parseEther(trimmedAmount);
    } catch {
      setInlineError('Enter a valid amount.');
      return;
    }
    writeContract(
      {
        address: CONTRACT_ADDRESS,
        abi: predictionMarketAbi,
        functionName: 'placeBet',
        args: [market.id, selectedSide],
        value: amountWei,
      },
      {
        onSuccess() {
          poolDelta.addOptimistic(selectedSide!, amountWei);
        },
        onError(err) {
          poolDelta.rollback();
          const msg = translateContractError(err);
          if (msg) {
            setInlineError(msg);
          } else if (isUserRejection(err)) {
            toast('Bet not placed.');
          } else {
            toast('Bet failed. Please try again.');
          }
        },
      }
    );
  }

  const ctaLabel =
    mode === 'disconnected' ? 'Connect Wallet to Bet' :
    mode === 'no-side' ? 'Select a side' :
    mode === 'invalid' ? 'Place Bet' :
    mode === 'signing' ? 'Signing…' :
    mode === 'confirming' ? 'Confirming in block…' :
    `Place Bet · ${amountStr} STT on ${selectedSide === 0 ? 'YES' : 'NO'}`;

  const ctaDisabled = mode !== 'valid';

  return (
    <div className={cn('flex flex-col gap-4', className)}>
      <div role="radiogroup" aria-label="Bet side" className="flex gap-2">
        {selectedSide === 0 ? (
          <button
            role="radio"
            aria-checked={true}
            onClick={() => setSelectedSide(0)}
            className="flex-1 min-h-[44px] rounded-sm border border-accent-yes bg-accent-yes/15 py-2 font-mono text-sm text-accent-yes"
          >
            YES
          </button>
        ) : (
          <button
            role="radio"
            aria-checked={false}
            onClick={() => setSelectedSide(0)}
            className="flex-1 min-h-[44px] rounded-sm border border-accent-yes/30 py-2 font-mono text-sm text-accent-yes/60"
          >
            YES
          </button>
        )}
        {selectedSide === 1 ? (
          <button
            role="radio"
            aria-checked={true}
            onClick={() => setSelectedSide(1)}
            className="flex-1 min-h-[44px] rounded-sm border border-accent-no bg-accent-no/15 py-2 font-mono text-sm text-accent-no"
          >
            NO
          </button>
        ) : (
          <button
            role="radio"
            aria-checked={false}
            onClick={() => setSelectedSide(1)}
            className="flex-1 min-h-[44px] rounded-sm border border-accent-no/30 py-2 font-mono text-sm text-accent-no/60"
          >
            NO
          </button>
        )}
      </div>

      <div className="flex flex-col gap-1">
        <input
          type="text"
          inputMode="decimal"
          placeholder="0.00"
          value={amountStr}
          onChange={e => {
            setAmountStr(e.target.value);
            setInlineError(null);
          }}
          aria-label="Bet amount in STT"
          aria-describedby={inlineError ? errorId : undefined}
          className="w-full rounded-sm border border-border bg-transparent px-3 py-2 font-mono text-sm tabular-nums placeholder:text-muted-foreground/50"
        />
        <p className="font-mono text-xs text-muted-foreground">Min bet: 0.01 STT</p>
        {inlineError && (
          <p id={errorId} className="font-mono text-xs text-destructive">
            {inlineError}
          </p>
        )}
      </div>

      {showPosition && (
        <div className="flex gap-4 font-mono text-xs text-muted-foreground">
          {yesPosition > 0n && (
            <span>Your YES: {Number(formatUnits(yesPosition, 18)).toFixed(2)} STT</span>
          )}
          {noPosition > 0n && (
            <span>Your NO: {Number(formatUnits(noPosition, 18)).toFixed(2)} STT</span>
          )}
        </div>
      )}

      <button
        disabled={ctaDisabled}
        onClick={handleSubmit}
        className={cn(
          'w-full min-h-[44px] rounded-sm py-2.5 font-mono text-sm',
          ctaDisabled
            ? 'bg-foreground/10 text-foreground/50 cursor-not-allowed'
            : 'bg-accent-yes/20 text-foreground hover:bg-accent-yes/30'
        )}
      >
        {ctaLabel}
      </button>
    </div>
  );
}

function BetFormSkeleton() {
  return (
    <div className="flex flex-col gap-4">
      <div className="flex gap-2">
        <Skeleton className="h-9 flex-1 rounded-sm" />
        <Skeleton className="h-9 flex-1 rounded-sm" />
      </div>
      <Skeleton className="h-9 w-full rounded-sm" />
      <Skeleton className="h-10 w-full rounded-sm" />
    </div>
  );
}

export const BetForm = Object.assign(BetFormBase, { Skeleton: BetFormSkeleton });
