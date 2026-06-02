import { decodeErrorResult } from 'viem';
import { predictionMarketAbi } from '@/lib/abi';

const ERROR_MAP: Record<string, string> = {
  // Bet placement errors
  PredictionMarket__BetBelowMinimum: 'Minimum bet is 0.01 STT.',
  PredictionMarket__MarketClosed: 'Market closes in <1m — try again.',
  PredictionMarket__MarketNotOpen: 'This market is no longer open.',
  PredictionMarket__InvalidSide: 'Invalid bet side. Select YES or NO.',
  // Market existence / state errors
  PredictionMarket__MarketDoesNotExist: 'Market not found.',
  PredictionMarket__InvalidStateTransition: 'This market is not in the expected state. Refresh and try again.',
  // Claim / refund errors
  PredictionMarket__AlreadyClaimed: "You've already claimed this market.",
  PredictionMarket__AlreadyRefunded: "You've already refunded this market.",
  PredictionMarket__NotWinningPosition: 'No winning position to claim.',
  PredictionMarket__NotRefundable: 'No position eligible for refund.',
  PredictionMarket__TransferFailed: 'Transfer failed. The contract could not send funds.',
  // Market creation errors
  PredictionMarket__InvalidThreshold: 'Threshold must be greater than zero.',
  PredictionMarket__ResolutionTimeInPast: 'Resolution time must be at least 5 minutes from now.',
  PredictionMarket__EmptyQuestion: 'Question cannot be empty.',
  PredictionMarket__EmptyDataSource: 'Data source URL cannot be empty.',
  PredictionMarket__InvalidAmbiguityBand: 'Ambiguity band must be between 1 and 1000 basis points (0.01%–10%).',
  PredictionMarket__InsufficientReactivityFunds: 'This market cannot be created right now — the contract is low on reactivity funds. Try again shortly.',
  // Agent / internal errors
  PredictionMarket__OnlySomniaAgents: 'Internal: agent callback caller mismatch. Please report this.',
  PredictionMarket__UnknownRequest: 'Internal: unknown agent request. Please report this.',
  PredictionMarket__ZeroAddress: 'Internal: zero address configuration error. Please report this.',
};

export function translateContractError(error: unknown): string | null {
  if (typeof error !== 'object' || error === null) return null;
  const data = (error as { data?: unknown }).data;
  if (!data || typeof data !== 'object') return null;
  try {
    const decoded = decodeErrorResult({
      abi: predictionMarketAbi,
      data: (data as { data?: `0x${string}` }).data ?? (data as unknown as `0x${string}`),
    });
    return ERROR_MAP[decoded.errorName] ?? null;
  } catch {
    return null;
  }
}
