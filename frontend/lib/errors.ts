import { decodeErrorResult } from 'viem';
import { predictionMarketAbi } from '@/lib/abi';

const ERROR_MAP: Record<string, string> = {
  PredictionMarket__BetBelowMinimum: 'Minimum bet is 0.01 STT',
  PredictionMarket__MarketClosed: 'Market closes in <1m — try again',
  PredictionMarket__MarketNotOpen: 'Market is no longer open for bets',
  PredictionMarket__AlreadyClaimed: "You've already claimed this market.",
  PredictionMarket__AlreadyRefunded: "You've already refunded this market.",
  PredictionMarket__NotWinningPosition: 'No winning position to claim.',
  PredictionMarket__NotRefundable: 'No position eligible for refund.',
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
