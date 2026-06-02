'use client';

import { Skeleton } from '@/components/ui/skeleton';
import { cn } from '@/lib/utils';
import { buildReceiptUrl } from '@/lib/receipt';
import type { Market } from '@/types/market';

type CardState = 'success' | 'llm-invoked' | 'invalid' | 'disputed';

function resolveCardState(market: Market): CardState {
  if (market.status === 'Disputed') return 'disputed';
  if (market.status === 'Refunded') return 'invalid';
  if (market.pendingAgentType === 'Llm') return 'llm-invoked';
  return 'success';
}

function truncateHex(id: bigint): string {
  const hex = id.toString(16).padStart(8, '0');
  if (hex.length <= 10) return `0x${hex}`;
  return `0x${hex.slice(0, 4)}…${hex.slice(-4)}`;
}

function truncateDataSource(dataSource: string): string {
  try {
    return new URL(dataSource).hostname;
  } catch {
    return dataSource.slice(0, 40);
  }
}

function formatResolvedAt(resolvedAt: bigint): string {
  const date = new Date(Number(resolvedAt) * 1000).toLocaleString('en-US', {
    dateStyle: 'medium',
    timeStyle: 'short',
    timeZone: 'UTC',
  });
  return `${date} UTC · same block as callback`;
}

export interface ReceiptSummaryCardProps {
  market: Market;
  className?: string;
}

function ReceiptSummaryCardBase({ market, className }: ReceiptSummaryCardProps) {
  if (
    market.status !== 'Resolved' &&
    market.status !== 'Refunded' &&
    market.status !== 'Disputed'
  ) {
    return null;
  }

  const cardState = resolveCardState(market);
  const hasReceipt = market.pendingRequestId > 0n;

  return (
    <div className={cn('rounded-sm border p-4', className)}>
      {cardState === 'disputed' ? (
        <dl className="grid grid-cols-[130px_1fr] gap-y-2">
          <dt className="font-mono text-sm text-muted-foreground">failureReason:</dt>
          <dd className="font-mono text-sm text-foreground">
            Agent consensus failed or data source was unavailable.
          </dd>
          {hasReceipt && (
            <>
              <dt className="font-mono text-sm text-muted-foreground">requestId:</dt>
              <dd className="font-mono text-sm text-foreground flex items-center">
                <span>{truncateHex(market.pendingRequestId)}</span>
                <button
                  type="button"
                  onClick={() => navigator.clipboard.writeText('0x' + market.pendingRequestId.toString(16))}
                  aria-label="Copy request ID"
                  className="ml-2 font-mono text-xs text-muted-foreground hover:text-foreground transition-colors"
                >
                  [copy]
                </button>
              </dd>
            </>
          )}
        </dl>
      ) : (
        <dl className="grid grid-cols-[130px_1fr] gap-y-2">
          <dt className="font-mono text-sm text-muted-foreground">agentType:</dt>
          {(cardState === 'llm-invoked' || cardState === 'invalid') ? (
            <dd className="font-mono text-sm text-foreground">JSON API + LLM Tiebreaker</dd>
          ) : (
            <dd className="font-mono text-sm text-foreground">JSON API</dd>
          )}

          <dt className="font-mono text-sm text-muted-foreground">requestId:</dt>
          <dd className="font-mono text-sm text-foreground flex items-center">
            {hasReceipt ? (
              <>
                <span>{truncateHex(market.pendingRequestId)}</span>
                <button
                  type="button"
                  onClick={() => navigator.clipboard.writeText('0x' + market.pendingRequestId.toString(16))}
                  aria-label="Copy request ID"
                  className="ml-2 font-mono text-xs text-muted-foreground hover:text-foreground transition-colors"
                >
                  [copy]
                </button>
              </>
            ) : (
              <span>—</span>
            )}
          </dd>

          <dt className="font-mono text-sm text-muted-foreground">verdict:</dt>
          {market.verdict === 'YES' && (
            <dd className="font-mono text-sm text-accent-yes">YES</dd>
          )}
          {market.verdict === 'NO' && (
            <dd className="font-mono text-sm text-accent-no">NO</dd>
          )}
          {market.verdict === 'INVALID' && (
            <dd className="font-mono text-sm text-accent-llm">INVALID</dd>
          )}
          {market.verdict === 'Unset' && (
            <dd className="font-mono text-sm text-foreground">—</dd>
          )}

          <dt className="font-mono text-sm text-muted-foreground">dataSource:</dt>
          <dd className="font-mono text-sm text-foreground flex items-center">
            <span>{truncateDataSource(market.dataSource)}</span>
            <button
              type="button"
              onClick={() => navigator.clipboard.writeText(market.dataSource)}
              aria-label="Copy data source"
              className="ml-2 font-mono text-xs text-muted-foreground hover:text-foreground transition-colors"
            >
              [copy]
            </button>
          </dd>

          <dt className="font-mono text-sm text-muted-foreground">resolvedAt:</dt>
          <dd className="font-mono text-sm text-foreground">
            {formatResolvedAt(market.resolvedAt)}
          </dd>

          {(cardState === 'llm-invoked' || cardState === 'invalid') && (
            <>
              <dt className="font-mono text-sm text-muted-foreground">reasoning:</dt>
              <dd className="font-mono text-sm text-foreground">—</dd>
            </>
          )}
        </dl>
      )}

      {cardState === 'llm-invoked' && hasReceipt && (
        <div className="mt-4">
          <p className="mb-2 text-sm text-muted-foreground">Every step the AI took is recorded on-chain.</p>
          <a
            href={buildReceiptUrl(market.pendingRequestId)}
            target="_blank"
            rel="noopener noreferrer"
            aria-label="Open receipt in new tab"
            className="inline-block rounded-sm border border-accent-llm px-4 py-2 font-mono text-base text-accent-llm transition-colors hover:bg-accent-llm/10"
          >
            View full reasoning on Agent Explorer →
          </a>
        </div>
      )}
      {cardState === 'success' && hasReceipt && (
        <div className="mt-4">
          <p className="mb-2 text-sm text-muted-foreground">The JSON the agent fetched is recorded on-chain.</p>
          <a
            href={buildReceiptUrl(market.pendingRequestId)}
            target="_blank"
            rel="noopener noreferrer"
            aria-label="Open receipt in new tab"
            className="inline-block rounded-sm border border-border px-4 py-2 font-mono text-sm text-foreground transition-colors hover:bg-foreground/5"
          >
            View resolution receipt →
          </a>
        </div>
      )}
      {cardState === 'invalid' && hasReceipt && (
        <div className="mt-4">
          <p className="mb-2 text-sm text-muted-foreground">The AI examined the data and found it inconclusive. See exactly why.</p>
          <a
            href={buildReceiptUrl(market.pendingRequestId)}
            target="_blank"
            rel="noopener noreferrer"
            aria-label="Open receipt in new tab"
            className="inline-block rounded-sm border border-accent-llm px-4 py-2 font-mono text-base text-accent-llm transition-colors hover:bg-accent-llm/10"
          >
            View the AI's reasoning →
          </a>
        </div>
      )}
      {cardState === 'disputed' && hasReceipt && (
        <div className="mt-4">
          <p className="mb-2 text-sm text-muted-foreground">The resolution agent could not complete. See the technical record.</p>
          <a
            href={buildReceiptUrl(market.pendingRequestId)}
            target="_blank"
            rel="noopener noreferrer"
            aria-label="Open receipt in new tab"
            className="inline-block rounded-sm border border-border px-4 py-2 font-mono text-sm text-foreground transition-colors hover:bg-foreground/5"
          >
            View failure details →
          </a>
        </div>
      )}
    </div>
  );
}

function ReceiptSummaryCardSkeleton() {
  return (
    <div className="flex flex-col gap-3 rounded-sm border p-4">
      <Skeleton className="h-4 w-3/4" />
      <Skeleton className="h-4 w-full" />
      <Skeleton className="h-4 w-5/6" />
      <Skeleton className="h-4 w-2/3" />
      <Skeleton className="h-4 w-1/2" />
    </div>
  );
}

export const ReceiptSummaryCard = Object.assign(ReceiptSummaryCardBase, {
  Skeleton: ReceiptSummaryCardSkeleton,
});
