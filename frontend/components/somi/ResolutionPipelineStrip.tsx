'use client';

import { useState, useEffect, useRef } from 'react';
import { useWatchContractEvent, usePublicClient } from 'wagmi';
import { cn } from '@/lib/utils';
import { Skeleton } from '@/components/ui/skeleton';
import { predictionMarketAbi } from '@/lib/abi';
import { CONTRACT_ADDRESS } from '@/lib/constants';
import type { Market } from '@/types/market';

type StepState = 'pending' | 'live' | 'done' | 'failed';

interface PipelineState {
  triggerBlock: bigint | null;
  triggerTimestamp: bigint | null;
  step3State: StepState;
  step3Timestamp: bigint | null;
  requestId: bigint | null;
}

const INITIAL_STATE: PipelineState = {
  triggerBlock: null,
  triggerTimestamp: null,
  step3State: 'pending',
  step3Timestamp: null,
  requestId: null,
};

function usePipelineEvents(marketId: bigint, enabled: boolean): PipelineState {
  const [state, setState] = useState<PipelineState>(INITIAL_STATE);
  const publicClient = usePublicClient();
  const prevEnabledRef = useRef(enabled);

  // fetchAndSetTimestamp lives inside the hook so publicClient is captured fresh
  // each render; setter is passed as a callback to avoid stale-closure over setState
  function fetchAndSetTimestamp(blockNumber: bigint, setter: (ts: bigint) => void) {
    if (!publicClient) return;
    publicClient
      .getBlock({ blockNumber })
      .then((block) => setter(block.timestamp))
      .catch(() => {
        // Timestamps degrade to "—" on failure
      });
  }

  useEffect(() => {
    setState(INITIAL_STATE);
  }, [marketId]);

  // Reset when the same market re-enters Resolving after a prior resolution cycle
  useEffect(() => {
    if (enabled && !prevEnabledRef.current) {
      setState(INITIAL_STATE);
    }
    prevEnabledRef.current = enabled;
  }, [enabled]);

  useWatchContractEvent({
    address: CONTRACT_ADDRESS,
    abi: predictionMarketAbi,
    eventName: 'ResolutionInitiated',
    args: { marketId } as unknown as Record<string, unknown>,
    enabled: enabled && !!CONTRACT_ADDRESS,
    onLogs(logs) {
      const log = logs[0];
      if (!log) return;
      const { args, blockNumber: logBlock } = log as unknown as {
        args: { marketId: bigint; requestId: bigint };
        blockNumber: bigint | null;
      };
      if (args.marketId !== marketId) return;
      if (!logBlock) return; // pending tx; skip rather than fetch genesis block
      setState((prev) => ({ ...prev, triggerBlock: logBlock, requestId: args.requestId }));
      fetchAndSetTimestamp(logBlock, (ts) => {
        setState((prev) => ({ ...prev, triggerTimestamp: ts }));
      });
    },
  });

  useWatchContractEvent({
    address: CONTRACT_ADDRESS,
    abi: predictionMarketAbi,
    eventName: 'MarketResolved',
    args: { marketId } as unknown as Record<string, unknown>,
    enabled: enabled && !!CONTRACT_ADDRESS,
    onLogs(logs) {
      const log = logs[0];
      if (!log) return;
      const { args, blockNumber: logBlock } = log as unknown as {
        args: { marketId: bigint };
        blockNumber: bigint | null;
      };
      if (args.marketId !== marketId) return;
      if (!logBlock) return;
      setState((prev) => ({ ...prev, step3State: 'done' }));
      fetchAndSetTimestamp(logBlock, (ts) => {
        setState((prev) => ({ ...prev, step3Timestamp: ts }));
      });
    },
  });

  useWatchContractEvent({
    address: CONTRACT_ADDRESS,
    abi: predictionMarketAbi,
    eventName: 'ResolutionFailed',
    args: { marketId } as unknown as Record<string, unknown>,
    enabled: enabled && !!CONTRACT_ADDRESS,
    onLogs(logs) {
      const log = logs[0];
      if (!log) return;
      const { args, blockNumber: logBlock } = log as unknown as {
        args: { marketId: bigint };
        blockNumber: bigint | null;
      };
      if (args.marketId !== marketId) return;
      if (!logBlock) return;
      setState((prev) => ({ ...prev, step3State: 'failed' }));
      fetchAndSetTimestamp(logBlock, (ts) => {
        setState((prev) => ({ ...prev, step3Timestamp: ts }));
      });
    },
  });

  return state;
}

function fmtElapsed(start: bigint | null, end: bigint | null): string {
  if (start === null || end === null) return '—';
  if (end < start) return '—';
  return `+${(end - start).toString()}s`;
}

function StepMarker({ state }: { state: StepState }) {
  if (state === 'pending') {
    return <span className="shrink-0 text-muted-foreground">[…]</span>;
  }
  if (state === 'live') {
    return (
      <span className="shrink-0 animate-pulse text-accent-llm motion-reduce:animate-none">
        [→]
      </span>
    );
  }
  if (state === 'done') {
    return <span className="shrink-0 text-accent-yes">[✓]</span>;
  }
  return <span className="shrink-0 text-accent-no">[×]</span>;
}

export interface ResolutionPipelineStripProps {
  market: Market;
  variant?: 'hero' | 'compact';
  className?: string;
}

function ResolutionPipelineStripBase({
  market,
  variant = 'hero',
  className,
}: ResolutionPipelineStripProps) {
  const isActive = market.status === 'Resolving' || market.status === 'LLMResolving';
  const isLLM = market.status === 'LLMResolving';

  const pipeline = usePipelineEvents(market.id, isActive);

  // Track whether this market ever reached LLMResolving so step 2 stays visible as done
  const [wasEverLLMResolving, setWasEverLLMResolving] = useState(false);

  useEffect(() => {
    if (isLLM) setWasEverLLMResolving(true);
  }, [isLLM]);

  useEffect(() => {
    setWasEverLLMResolving(false);
  }, [market.id]);

  // Stay mounted through the terminal event so the parent briefly sees the finished pipeline
  const isTerminal = pipeline.step3State === 'done' || pipeline.step3State === 'failed';
  if (!isActive && !isTerminal) return null;

  let hostname: string;
  try {
    hostname = new URL(market.dataSource).hostname;
  } catch {
    hostname = market.dataSource || '(no source)';
  }

  const isCompact = variant === 'compact';

  const step1State: StepState = isLLM || isTerminal ? 'done' : 'live';
  const step2Shown = isLLM || wasEverLLMResolving;
  const step2State: StepState = isLLM ? 'live' : 'done';
  const step3State: StepState = pipeline.step3State;

  const blockDisplay =
    pipeline.triggerBlock !== null ? `block ${pipeline.triggerBlock.toString()}` : 'block —';

  const step3Time = fmtElapsed(pipeline.triggerTimestamp, pipeline.step3Timestamp);

  return (
    <div
      role="status"
      aria-live="polite"
      aria-label="Resolution pipeline running"
      className={cn(
        'w-full rounded-sm border border-accent-llm bg-accent-llm/[0.04]',
        isCompact ? 'p-3' : 'p-4 lg:p-6',
        className,
      )}
    >
      <div className="mb-3 flex items-baseline justify-between gap-2">
        <span
          className={cn(
            'font-mono font-bold uppercase tracking-wider text-accent-llm',
            isCompact ? 'text-xs' : 'text-sm',
          )}
        >
          RESOLVING…
        </span>
        <span className="font-mono text-xs text-muted-foreground">{blockDisplay}</span>
      </div>
      <ol className={cn('space-y-2', isCompact && 'space-y-1')}>
        <li className={cn('flex items-baseline gap-2 font-mono', isCompact ? 'text-xs' : 'text-sm')}>
          <StepMarker state={step1State} />
          <span className="truncate">Fetch JSON from {hostname}</span>
          <span className="ml-auto shrink-0 tabular-nums text-muted-foreground">—</span>
        </li>
        {step2Shown && (
          <li className={cn('flex items-baseline gap-2 font-mono', isCompact ? 'text-xs' : 'text-sm')}>
            <StepMarker state={step2State} />
            <span>AI Tiebreaker</span>
            <span className="ml-auto shrink-0 tabular-nums text-muted-foreground">—</span>
          </li>
        )}
        <li className={cn('flex items-baseline gap-2 font-mono', isCompact ? 'text-xs' : 'text-sm')}>
          <StepMarker state={step3State} />
          <span>Settle on-chain</span>
          <span className="ml-auto shrink-0 tabular-nums text-muted-foreground">{step3Time}</span>
        </li>
      </ol>
    </div>
  );
}

function ResolutionPipelineStripSkeleton() {
  return (
    <div className="flex flex-col gap-3 rounded-sm border border-accent-llm/20 bg-accent-llm/[0.02] p-4 lg:p-6">
      <div className="flex justify-between">
        <Skeleton className="h-4 w-28" />
        <Skeleton className="h-4 w-16" />
      </div>
      <Skeleton className="h-4 w-full" />
      <Skeleton className="h-4 w-3/4" />
    </div>
  );
}

export const ResolutionPipelineStrip = Object.assign(ResolutionPipelineStripBase, {
  Skeleton: ResolutionPipelineStripSkeleton,
});
